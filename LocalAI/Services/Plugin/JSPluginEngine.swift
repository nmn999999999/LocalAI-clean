import Foundation
import JavaScriptCore

/// JS 插件执行引擎（基于系统 JavaScriptCore）。
///
/// 沙箱边界：
/// - 默认纯计算：JS 只能做字符串/JSON/数字/日期等标准 API
/// - 显式能力（manifest.permissions 声明）：
///   * "network" → 暴露 nativeFetch(url)（仅 https、20s 超时、2MB 上限），插件工具需授权执行
///   * "storage" → 暴露 storeGet/storeSet（模块专属 Documents/Modules/<id>/storage.json）
///
/// 线程模型：AgentService 在 @MainActor 串行调用；JSContext 与 JSValue 只在主线程触碰。
final class JSPluginEngine: @unchecked Sendable {

    let manifest: PluginManifest
    private let context: JSContext
    private(set) var tools: [PluginToolDef] = []
    private let storageFile: URL?
    private var storage: [String: String] = [:]

    /// - Parameters:
    ///   - manifest: 模块清单
    ///   - jsSource: tools.js 源码
    ///   - storageFile: 模块专属存储文件（permissions 含 storage 时启用）
    init?(manifest: PluginManifest, jsSource: String, storageFile: URL? = nil) {
        self.manifest = manifest
        self.storageFile = storageFile
        guard let ctx = JSContext() else { return nil }
        self.context = ctx

        ctx.name = "LocalAI-plugin-\(manifest.id)"
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            print("[plugin:\(manifest.id)] JS exception: \(msg)")
        }

        // 本地存储加载
        if let storageFile, let data = try? Data(contentsOf: storageFile),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            storage = dict
        }

        // 原生桥（JSExport）：network / storage
        let bridge = PluginNativeBridge(
            allowsNetwork: manifest.permissions.contains("network"),
            storageGetter: { [weak self] key in self?.storage[key] },
            storageSetter: { [weak self] key, value in self?.setStorage(key, value) }
        )
        ctx.setObject(bridge, forKeyedSubscript: "NativeBridge" as NSString)

        // 注册桥 + JS 侧包装（Promise）
        let preamble = """
        var __tools = [];
        function registerTool(def) {
          if (def && typeof def.name === 'string' && typeof def.run === 'function') {
            __tools.push({ name: def.name, description: typeof def.description === 'string' ? def.description : '', parameters: def.parameters || {}, run: def.run });
          }
        }
        function __pluginTools() { return JSON.stringify(__tools.map(function(t){
          return { name: t.name, description: t.description, parameters: t.parameters };
        })); }
        function __callToolAsync(name, argsJSON, done) {
          var t = null;
          for (var i = 0; i < __tools.length; i++) { if (__tools[i].name === name) { t = __tools[i]; break; } }
          if (!t) { done({ error: 'unknown tool: ' + name }); return; }
          try {
            var args = argsJSON ? JSON.parse(argsJSON) : {};
            var r = t.run(args);
            if (r && typeof r.then === 'function') {
              r.then(function(v){ done({ result: v }); }, function(e){ done({ error: String(e) }); });
            } else {
              done({ result: r });
            }
          } catch (e) {
            done({ error: String(e) });
          }
        }
        function nativeFetch(url) {
          if (!NativeBridge || typeof NativeBridge.fetchAsync !== 'function') {
            return Promise.reject(new Error('模块未声明 network 权限'));
          }
          return new Promise(function (resolve, reject) {
            NativeBridge.fetchAsync(String(url), function (err, data) {
              if (err && err !== null) reject(new Error(String(err)));
              else resolve(String(data));
            });
          });
        }
        function storeGet(key) {
          if (!NativeBridge || typeof NativeBridge.storeGet !== 'function') return null;
          return NativeBridge.storeGet(String(key));
        }
        function storeSet(key, value) {
          if (!NativeBridge || typeof NativeBridge.storeSet !== 'function') return;
          NativeBridge.storeSet(String(key), String(value));
        }
        """

        ctx.evaluateScript(preamble)
        ctx.evaluateScript(jsSource)

        if let raw = ctx.evaluateScript("__pluginTools()")?.toString(),
           let data = raw.data(using: .utf8),
           let defs = try? JSONDecoder().decode([PluginToolDef].self, from: data) {
            tools = defs
        }
    }

    /// 工具是否被授权（网络权限 → 需用户批准）
    func requiresApproval() -> Bool {
        manifest.permissions.contains("network")
    }

    func toolDefinitions() -> [AgentToolDefinition] {
        let approval = requiresApproval()
        return tools.map { def in
            var params: [String: AgentToolDefinition.ParameterSchema] = [:]
            for (k, p) in def.parameters {
                params[k] = AgentToolDefinition.ParameterSchema(
                    type: p.type,
                    description: p.description,
                    enumValues: nil
                )
            }
            return AgentToolDefinition(
                id: "plugin-\(manifest.id)-\(def.name)",
                name: def.name,
                description: def.description.isEmpty ? "JS 插件工具（\(manifest.name)）" : def.description,
                parameters: params,
                requiresApproval: approval
            )
        }
    }

    /// 调用插件工具（支持同步返回与 async/Promise），返回文本结果。
    /// JS 侧 __callToolAsync 通过 done 回调回传（主线程），continuation 只 resume 一次。
    func call(name: String, argumentsJSON: String) async -> String {
        await withCheckedContinuation { continuation in
            let done: @convention(block) (Any) -> Void = { result in
                guard let dict = result as? [String: Any] else {
                    continuation.resume(returning: "插件调用失败（无法解析返回值）")
                    return
                }
                if let error = dict["error"] as? String {
                    continuation.resume(returning: "插件错误: \(error)")
                    return
                }
                if let result = dict["result"] {
                    if let s = result as? String {
                        continuation.resume(returning: s)
                    } else if let d = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                              let s = String(data: d, encoding: .utf8) {
                        continuation.resume(returning: s)
                    } else {
                        continuation.resume(returning: "\(result)")
                    }
                } else {
                    continuation.resume(returning: "(无返回值)")
                }
            }
            guard let callback = JSValue(object: done, in: context) else {
                continuation.resume(returning: "插件回调创建失败")
                return
            }
            let script = "__callToolAsync(\(JSONString(name)), \(JSONString(argumentsJSON)), callback)"
            context.setObject(callback, forKeyedSubscript: "callback" as NSString)
            context.evaluateScript(script)
        }
    }

    // MARK: - 存储

    private func setStorage(_ key: String, _ value: String) {
        storage[key] = value
        persistStorage()
    }

    private func persistStorage() {
        guard let storageFile else { return }
        let snapshot = storage
        try? JSONEncoder().encode(snapshot).write(to: storageFile, options: .atomic)
    }

    private func JSONString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return str
    }
}

// MARK: - 原生桥（JSExport）

/// 注入 JS 的原生桥。仅当 manifest.permissions 声明对应能力时才暴露；
/// fetch 只允许 https，超时 20s，响应 2MB 上限。
@objc private protocol PluginNativeBridgeExport: JSExport {
    func fetchAsync(_ url: String, _ callback: JSValue)
    func storeGet(_ key: String) -> String?
    func storeSet(_ key: String, _ value: String)
}

private final class PluginNativeBridge: NSObject, PluginNativeBridgeExport {

    private let allowsNetwork: Bool
    private let storageGetter: (String) -> String?
    private let storageSetter: (String, String) -> Void

    init(allowsNetwork: Bool, storageGetter: @escaping (String) -> String?, storageSetter: @escaping (String, String) -> Void) {
        self.allowsNetwork = allowsNetwork
        self.storageGetter = storageGetter
        self.storageSetter = storageSetter
        super.init()
    }

    func fetchAsync(_ urlString: String, _ callback: JSValue) {
        // JSValue 非 Sendable：立即包进 unchecked 盒子，异步闭包只捕获盒子（主线程触碰）
        let box = JSCallbackBox(callback: callback)
        guard allowsNetwork else {
            DispatchQueue.main.async { box.callback.call(withArguments: ["模块未声明 network 权限", NSNull()]) }
            return
        }
        guard let url = URL(string: urlString), url.scheme == "https" else {
            DispatchQueue.main.async { box.callback.call(withArguments: ["仅支持 https 地址", NSNull()]) }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("LocalAI-Plugin/1.0", forHTTPHeaderField: "User-Agent")

        Task.detached(priority: .userInitiated) {
            let result: (String?, String?)
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let limited = data.prefix(2 * 1024 * 1024)
                let text = String(data: limited, encoding: .utf8) ?? ""
                result = (nil, text)
            } catch {
                result = (error.localizedDescription, nil)
            }
            DispatchQueue.main.async {
                let err: Any = result.0 ?? NSNull()
                let data: Any = result.1 ?? NSNull()
                box.callback.call(withArguments: [err, data])
            }
        }
    }

    func storeGet(_ key: String) -> String? {
        storageGetter(key)
    }

    func storeSet(_ key: String, _ value: String) {
        storageSetter(key, value)
    }
}

/// JSValue 非 Sendable：包一层 unchecked 盒子跨 Task 传递（只在主线程触碰）
private final class JSCallbackBox: @unchecked Sendable {
    let callback: JSValue
    init(callback: JSValue) { self.callback = callback }
}
