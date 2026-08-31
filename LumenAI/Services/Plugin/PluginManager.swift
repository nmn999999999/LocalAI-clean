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
    /// 可更新模块数量（服务页角标）
    var updatableCount: Int {
        updateStates().filter(\.hasUpdate).count
    }

    /// 启动静默检查（1 天节流）
    private let lastCheckKey = "plugin_check_ts"
    func checkForUpdatesIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= 86400 else { return }
        await checkForUpdates()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }

    private let modulesDir: URL
    /// 模块索引地址（GitHub raw；可换成自己的静态站点）
    private let indexURL = "https://raw.githubusercontent.com/nmn999999999/LumenAI/main/modules/index.json"

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

    /// 读取模块存储（远程 UI 用）
    func storageValue(module: InstalledModule, key: String) -> String? {
        module.engine.storageGet(key)
    }

    /// 写入模块存储（远程 UI 用）
    func setStorageValue(module: InstalledModule, key: String, value: String) {
        module.engine.storageSet(key, value)
    }

    /// 清空模块存储（远程 UI 的 reset 动作）
    func resetStorage(module: InstalledModule) {
        let dir = module.directory
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("storage.json"))
        if let reloaded = loadModule(at: dir) {
            if let idx = modules.firstIndex(where: { $0.id == module.id }) {
                modules[idx] = reloaded
            }
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
        return "未知工具: \(name)"
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
        request.setValue("LumenAI-iOS/plugin", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastCheckError = "模块索引响应异常 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"
                return
            }
            let index = try JSONDecoder().decode(ModuleIndex.self, from: data)
            remoteIndex = index.modules
            lastCheckError = nil
        } catch {
            lastCheckError = "检查失败: \(error.localizedDescription.prefix(60))"
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
            return conflictWarning(for: manifest.id)
        } catch {
            return "安装失败: \(error.localizedDescription.prefix(60))"
        }
    }

    /// 从本地 .localaimod 导入并安装（返回警告信息；nil = 成功无警告）
    func importBundle(data: Data) throws -> String? {
        let (manifest, tools) = try parseImport(data: data)
        let entry = ModuleIndexEntry(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            minAppVersion: manifest.minAppVersion,
            permissions: manifest.permissions,
            files: .init(manifest: "", tools: "")
        )
        try install(entry: entry, manifest: manifest, jsSource: tools)
        return conflictWarning(for: manifest.id)
    }

    /// 工具名冲突检查：插件工具与内置/MCP 同名 → 内置优先（插件同名的不会被调用）
    private func conflictWarning(for moduleID: String) -> String? {
        guard let module = modules.first(where: { $0.id == moduleID }) else { return nil }
        let builtinNames = Set(BuiltInTools.allTools.map(\.name))
        let mcpNames = Set(MCPService.shared.toolDefinitions.map(\.name))
        let conflicts = module.engine.tools
            .map(\.name)
            .filter { builtinNames.contains($0) || mcpNames.contains($0) }
        guard !conflicts.isEmpty else { return nil }
        return "⚠️ 工具名与已有工具冲突（内置优先）: \(conflicts.joined(separator: ", "))"
    }

    // MARK: - 本地导入 / 导出（.localaimod = LZ4 压缩的 {"manifest":..., "tools":"..."}）

    /// 导出已安装模块为 .localaimod 文件（可分享给他人导入）
    func exportModule(_ module: InstalledModule) -> URL? {
        let dir = module.directory
        guard let manifestData = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: manifestData),
              let jsSource = try? String(contentsOf: dir.appendingPathComponent("tools.js"), encoding: .utf8)
        else { return nil }
        let bundle: [String: Any] = ["manifest": manifest, "tools": jsSource]
        guard let json = try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted]) else { return nil }
        let compressed = LZ4.compress(json)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(module.manifest.id)-\(module.manifest.version).localaimod")
        try? compressed.write(to: file)
        return file
    }

    /// 解析 .localaimod 数据 → (manifest, tools)
    /// 格式：LZ4 压缩的 {"manifest": {...}, "tools": "..."}；兼容未压缩的明文 JSON。
    func parseImport(data: Data) throws -> (PluginManifest, String) {
        let decompressed: Data
        if let d = LZ4.decompress(data) {
            decompressed = d
        } else {
            decompressed = data   // 明文 JSON 兼容
        }
        guard let json = (try? JSONSerialization.jsonObject(with: decompressed)) as? [String: Any],
              let manifestData = try? JSONSerialization.data(withJSONObject: json["manifest"] as Any),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: manifestData),
              let tools = json["tools"] as? String
        else {
            throw NSError(domain: "Plugin", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的 .localaimod 文件"])
        }
        return (manifest, tools)
    }

    // MARK: - 状态查询

    /// 可安装/可更新列表（按远程索引；灰度模块只对命中灰度的设备显示）
    func updateStates() -> [ModuleUpdate] {
        let optIn = UserDefaults.standard.bool(forKey: UpdateCheckerService.grayOptInKey)
        return remoteIndex
            .filter { entry in
                // 灰度模块：非灰度设备隐藏（已安装的保留，不自动卸载）
                guard let gray = entry.gray else { return true }
                return UpdatePolicy.inGray(percent: gray.percent, optIn: optIn)
            }
            .map { entry in
                ModuleUpdate(entry: entry, installedVersion: modules.first { $0.id == entry.id }?.manifest.version)
            }
    }

    /// 模块是否处于灰度中（UI 徽标）
    func isGrayModule(_ entry: ModuleIndexEntry) -> Bool {
        entry.gray != nil
    }
}
