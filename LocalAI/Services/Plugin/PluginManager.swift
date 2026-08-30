import Foundation

/// 模块（JS 插件）管理器：
/// - 模块存放于 Documents/Modules/<id>/（manifest.json + tools.js），独立版本、独立更新
/// - 基础包（IPA）不动；模块更新在 App 内完成（下载 → 替换文件 → 重新加载）
/// - 远程索引：GitHub 仓库 modules/index.json（可随时指向其他源）
@MainActor
final class PluginManager: ObservableObject {

    static let shared = PluginManager()

    /// 已安装模块（含加载好的 JS 引擎）
    struct InstalledModule: Identifiable, Sendable {
        let manifest: PluginManifest
        let directory: URL
        let engine: JSPluginEngine
        var id: String { manifest.id }
        var toolCount: Int { engine.tools.count }
    }

    @Published private(set) var modules: [InstalledModule] = []
    @Published private(set) var remoteIndex: [ModuleIndexEntry] = []
    @Published private(set) var isChecking = false
    @Published var lastCheckError: String?

    private let modulesDir: URL
    /// 模块索引地址（GitHub raw；可换成自己的静态站点）
    private let indexURL = "https://raw.githubusercontent.com/nmn999999999/LocalAI-clean/main/modules/index.json"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        modulesDir = docs.appendingPathComponent("Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: modulesDir, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - 本地加载

    private func loadAll() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: nil) else { return }
        var loaded: [InstalledModule] = []
        for dir in dirs {
            guard dir.hasDirectoryPath else { continue }
            if let module = loadModule(at: dir) {
                loaded.append(module)
            }
        }
        modules = loaded.sorted { $0.manifest.name < $1.manifest.name }
    }

    private func loadModule(at dir: URL) -> InstalledModule? {
        let fm = FileManager.default
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let jsURL = dir.appendingPathComponent("tools.js")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: manifestData),
              let jsSource = try? String(contentsOf: jsURL, encoding: .utf8)
        else { return nil }
        let storageFile = dir.appendingPathComponent("storage.json")
        guard let engine = JSPluginEngine(manifest: manifest, jsSource: jsSource, storageFile: storageFile) else { return nil }
        return InstalledModule(manifest: manifest, directory: dir, engine: engine)
    }

    // MARK: - 增删

    /// 安装/更新模块：写入 manifest.json + tools.js 后重新加载
    func install(entry: ModuleIndexEntry, manifest: PluginManifest, jsSource: String) throws {
        let dir = modulesDir.appendingPathComponent(entry.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        try jsSource.data(using: .utf8)?.write(to: dir.appendingPathComponent("tools.js"), options: .atomic)
        // 移除旧实例并重新加载
        modules.removeAll { $0.id == entry.id }
        if let module = loadModule(at: dir) {
            modules.append(module)
            modules.sort { $0.manifest.name < $1.manifest.name }
        }
    }

    func remove(_ module: InstalledModule) {
        try? FileManager.default.removeItem(at: module.directory)
        modules.removeAll { $0.id == module.id }
    }

    // MARK: - Agent 集成

    /// 全部已安装模块的工具定义（注入 Agent 工具目录）
    func installedToolDefinitions() -> [AgentToolDefinition] {
        modules.flatMap { $0.engine.toolDefinitions() }
    }

    func hasTool(named name: String) -> Bool {
        modules.contains { $0.engine.tools.contains { $0.name == name } }
    }

    func callTool(name: String, argumentsJSON: String) async -> String {
        for module in modules {
            if let def = module.engine.tools.first(where: { $0.name == name }) {
                return await module.engine.call(name: def.name, argumentsJSON: argumentsJSON)
            }
        }
        return "未知工具: \\(name)"
    }

    // MARK: - 远程更新（应用内更新模块）

    /// 拉取远程索引，返回可安装/可更新列表
    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: indexURL) else {
            lastCheckError = "无效的模块索引地址"
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LocalAI-iOS/plugin", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastCheckError = "模块索引响应异常 (HTTP \\((response as? HTTPURLResponse)?.statusCode ?? -1))"
                return
            }
            let index = try JSONDecoder().decode(ModuleIndex.self, from: data)
            remoteIndex = index.modules
            lastCheckError = nil
        } catch {
            lastCheckError = "检查失败: \\(error.localizedDescription.prefix(60))"
        }
    }

    /// 安装或更新远程索引里的模块
    func installOrUpdate(_ entry: ModuleIndexEntry) async -> String? {
        guard let manifestURL = URL(string: entry.files.manifest),
              let toolsURL = URL(string: entry.files.tools)
        else { return "无效的模块地址" }
        do {
            let (manifestData, mResp) = try await URLSession.shared.data(from: manifestURL)
            guard (mResp as? HTTPURLResponse)?.statusCode == 200 else { return "清单下载失败" }
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)

            // 版本兼容检查：App 版本低于模块要求 → 拒绝安装
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if let required = manifest.minAppVersion, !required.isEmpty,
               UpdateCheckerService.compare(UpdateCheckerService.stripV(required), appVersion) > 0 {
                return "需要升级 App 到 v\(required) 才能安装此模块"
            }
            let (jsData, tResp) = try await URLSession.shared.data(from: toolsURL)
            guard (tResp as? HTTPURLResponse)?.statusCode == 200,
                  let jsSource = String(data: jsData, encoding: .utf8)
            else { return "脚本下载失败" }
            try install(entry: entry, manifest: manifest, jsSource: jsSource)
            return nil
        } catch {
            return "安装失败: \\(error.localizedDescription.prefix(60))"
        }
    }

    // MARK: - 状态查询

    /// 可安装/可更新列表（按远程索引）
    func updateStates() -> [ModuleUpdate] {
        remoteIndex.map { entry in
            ModuleUpdate(entry: entry, installedVersion: modules.first { $0.id == entry.id }?.manifest.version)
        }
    }
}
