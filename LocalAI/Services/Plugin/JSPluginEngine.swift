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
/// 崩溃防护（v0.3.38 加固，针对线上"插件运行中 App 崩溃"）：
/// 1. 原生桥用 block 注册（nativeFetchAsync/nativeStoreGet/nativeStoreSet），
///    不用 JSExport —— JSExport 多参数方法在 JS 里的名字含冒号，调用方写
///    NativeBridge.fetchAsync(...) 实际是 undefined，且该歧义路径存在崩溃风险。
/// 2. 回调盒子强持有 JSContext：JS 回调时上下文一定还活着（防 use-after-free）。
/// 3. 调用在专属串行队列执行：插件死循环只卡插件队列，不冻结 UI（MainActor）。
/// 4. 30s 看门狗：超时未返回 → resume 并重建引擎（丢弃卡死队列），continuation
///    只 resume 一次（CallState 双守卫），杜绝 Swift Continuation 双 resume trap。
final class JSPluginEngine: @unchecked Sendable {

    let manifest: PluginManifest
    private(set) var tools: [PluginToolDef] = []
    private let storageFile: URL?
    private var storage: [String: String] = [:]

    private let lock = NSLock()
    private var runQueue: DispatchQueue
    private var context: JSContext?
    private let preamble: String
    private let jsSource: String

    private static let callTimeout: TimeInterval = 30

    init?(manifest: PluginManifest, jsSource: String, storageFile: URL? = nil) {
        self.manifest = manifest
        self.jsSource = jsSource
        self.storageFile = storageFile
        let queue = DispatchQueue(label: "localai.plugin.\(manifest.id)")
        self.runQueue = queue

        if let storageFile, let data = try? Data(contentsOf: storageFile),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            storage = dict
        }

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
        function __sanitize(v) {
          // JSON 归一化：NaN/Infinity→null；undefined→null（JSON.parse(undefined) 会抛异常，v0.3.40 修复）
          try { return JSON.parse(JSON.stringify(v)); } catch (e) { return v === undefined ? null : v; }
        }
        function __callToolAsync(name, argsJSON, done) {
          var t = null;
          for (var i = 0; i < __tools.length; i++) { if (__tools[i].name === name) { t = __tools[i]; break; } }
          if (!t) { done({ error: 'unknown tool: ' + name }); return; }
          try {
            var args = argsJSON ? JSON.parse(argsJSON) : {};
            var r = t.run(args);
            if (r && typeof r.then === 'function') {
              r.then(function(v){ done({ result: __sanitize(v) }); }, function(e){ done({ error: String(e) }); });
            } else {
              done({ result: __sanitize(r) });
            }
          } catch (e) {
            done({ error: String(e) });
          }
        }
        function nativeFetch(url) {
          if (typeof nativeFetchAsync !== 'function') {
            return Promise.reject(new Error('模块未声明 network 权限'));
          }
          return new Promise(function (resolve, reject) {
            nativeFetchAsync(String(url), function (err, data) {
              if (err && err !== null) reject(new Error(String(err)));
              else resolve(String(data));
            });
          });
        }
        function storeGet(key) {
          if (typeof nativeStoreGet !== 'function') return null;
          return nativeStoreGet(String(key));
        }
        function storeSet(key, value) {
          if (typeof nativeStoreSet !== 'function') return;
          nativeStoreSet(String(key), String(value));
        }
        """
        self.preamble = preamble

        // 在专属队列上创建上下文并加载模块（bridge 用 block 注册，名字显式无歧义）
        var setupError: String?
        queue.sync {
            guard let ctx = JSContext() else {
                setupError = "无法创建 JS 上下文"
                return
            }
            ctx.name = "LocalAI-plugin-\(manifest.id)"
            ctx.exceptionHandler = { _, exception in
                let msg = exception?.toString() ?? "unknown"
                print("[plugin:\(manifest.id)] JS exception: \(msg)")
            }

            // 原生桥（block 注册）
            let allowsNetwork = manifest.permissions.contains("network")
            let fetchBlock: @convention(block) (String, JSValue) -> Void = { url, cb in
                PluginNativeBridge.dispatchFetch(urlString: url, allowsNetwork: allowsNetwork, completionQueue: queue, callback: cb, context: ctx)
            }
            if let fn = JSValue(object: fetchBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeFetchAsync" as NSString)
            }
            let getBlock: @convention(block) (String) -> String? = { [weak self] key in
                self?.storage[key]
            }
            if let fn = JSValue(object: getBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeStoreGet" as NSString)
            }
            let setBlock: @convention(block) (String, String) -> Void = { [weak self] key, value in
                self?.setStorage(key, value)
            }
            if let fn = JSValue(object: setBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeStoreSet" as NSString)
            }

            ctx.evaluateScript(preamble)
            ctx.evaluateScript(jsSource)
            if let raw = ctx.evaluateScript("__pluginTools()")?.toString(),
               let data = raw.data(using: .utf8),
               let defs = try? JSONDecoder().decode([PluginToolDef].self, from: data) {
                self.tools = defs
            } else {
                setupError = "模块未注册任何工具或脚本有误"
            }
            self.context = ctx
        }
        if let setupError { return nil }
    }

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

    // MARK: - 调用（看门狗 + 单次 resume 守卫）

    func call(name: String, argumentsJSON: String) async -> String {
        await withCheckedContinuation { continuation in
            let state = CallState()
            state.register(continuation)

            lock.lock()
            let queue = runQueue
            let ctx = context
            lock.unlock()
            guard let ctx else {
                state.complete("插件引擎未就绪")
                return
            }

            queue.async { [weak self] in
                guard let self else {
                    state.complete("插件引擎已释放")
                    return
                }
                let done: @convention(block) (Any) -> Void = { result in
                    state.complete(self.describe(result))
                }
                guard let callback = JSValue(object: done, in: ctx) else {
                    state.complete("插件回调创建失败")
                    return
                }
                ctx.setObject(callback, forKeyedSubscript: "callback" as NSString)
                ctx.evaluateScript("__callToolAsync(\(self.JSONString(name)), \(self.JSONString(argumentsJSON)), callback)")
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.callTimeout) {
                if state.completeIfPending("插件调用超时（>\(Int(Self.callTimeout))s），已重置该模块引擎") {
                    self.resetEngine()
                }
            }
        }
    }

    private func resetEngine() {
        let newQueue = DispatchQueue(label: "localai.plugin.\(manifest.id).regen")
        newQueue.sync {
            guard let ctx = JSContext() else { return }
            ctx.name = "LocalAI-plugin-\(self.manifest.id)"
            ctx.exceptionHandler = { _, exception in
                print("[plugin:\(self.manifest.id)] JS exception: \(exception?.toString() ?? "?")")
            }
            let allowsNetwork = self.manifest.permissions.contains("network")
            let fetchBlock: @convention(block) (String, JSValue) -> Void = { url, cb in
                PluginNativeBridge.dispatchFetch(urlString: url, allowsNetwork: allowsNetwork, completionQueue: newQueue, callback: cb, context: ctx)
            }
            if let fn = JSValue(object: fetchBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeFetchAsync" as NSString)
            }
            let getBlock: @convention(block) (String) -> String? = { [weak self] key in
                self?.storage[key]
            }
            if let fn = JSValue(object: getBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeStoreGet" as NSString)
            }
            let setBlock: @convention(block) (String, String) -> Void = { [weak self] key, value in
                self?.setStorage(key, value)
            }
            if let fn = JSValue(object: setBlock, in: ctx) {
                ctx.setObject(fn, forKeyedSubscript: "nativeStoreSet" as NSString)
            }
            ctx.evaluateScript(self.preamble)
            // 超时重置必须重新加载模块工具脚本，否则后续调用全部 unknown tool（v0.3.40 修复）
            ctx.evaluateScript(self.jsSource)
            self.context = ctx
        }
        lock.lock()
        runQueue = newQueue
        lock.unlock()
    }

    /// 把 JS 回调的 result 转成展示文本。
    /// ⚠️ 不能用 NSJSONSerialization：插件返回值可能含 NaN/Infinity（JSCore 桥接成
    /// NSNumber(NaN)），dataWithJSONObject 遇到会抛 **ObjC 异常**，而 try? 捕不住
    /// （线上 v0.3.37 崩溃即由此导致：ModuleDetailView.test → call → describe → SIGABRT）。
    /// 这里用逐层类型检查的安全序列化，NaN/Infinity 输出为 null，绝不抛异常。
    private func describe(_ result: Any) -> String {
        guard let dict = result as? [String: Any] else {
            return "插件调用失败（无法解析返回值）"
        }
        if let error = dict["error"] as? String {
            return "插件错误: \(error)"
        }
        if let result = dict["result"] {
            let text: String
            if let s = result as? String { text = s }
            else if let t = Self.safeJSONText(result) { text = t }
            else { text = "\(result)" }
            // 防超长结果（尤其单行 JSON）卡死 SwiftUI Text 排版（v0.3.39 修复：
            // UIKit-runloop 卡死报告主线程 354/354 采样在 ResolvedStyledText.layers）
            return Self.capped(text, limit: 4000)
        }
        return "(无返回值)"
    }

    /// 截断超长文本（保留开头与结尾各一半），防止巨型字符串触发昂贵文本排版
    static func capped(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let half = limit / 2
        let head = String(text.prefix(half))
        let tail = String(text.suffix(half))
        return head + "\n…（结果过长，已截断）…\n" + tail
    }

    /// 安全序列化（无 NSJSONSerialization，永不抛异常；NaN/Infinity → null）
    private static func safeJSONText(_ value: Any) -> String? {
        var out = ""
        guard serialize(value, into: &out) else { return nil }
        return out
    }

    private static func serialize(_ value: Any, into out: inout String) -> Bool {
        if value is NSNull {
            out += "null"
            return true
        }
        if let s = value as? String {
            out += escapedString(s)
            return true
        }
        if let n = value as? NSNumber {
            // NaN / Infinity → null（NSJSONSerialization 会因它们抛异常）
            let v = n.doubleValue
            if v.isNaN || v.isInfinite {
                out += "null"
            } else if CFGetTypeID(n) == CFBooleanGetTypeID() {
                out += (n.boolValue ? "true" : "false")
            } else {
                out += n.stringValue
            }
            return true
        }
        if let arr = value as? [Any] {
            var parts: [String] = []
            for item in arr {
                var s = ""
                if serialize(item, into: &s) { parts.append(s) } else { return false }
            }
            out += "[" + parts.joined(separator: ",") + "]"
            return true
        }
        if let dict = value as? [String: Any] {
            var parts: [String] = []
            for (k, v) in dict {
                var s = ""
                if serialize(v, into: &s) {
                    parts.append(escapedString(k) + ":" + s)
                } else {
                    return false
                }
            }
            out += "{" + parts.joined(separator: ",") + "}"
            return true
        }
        return false
    }

    private static func escapedString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        out += "\""
        return out
    }

    // MARK: - 存储

    /// 读取模块本地存储（远程 UI 绑定用）
    func storageGet(_ key: String) -> String? {
        storage[key]
    }

    /// 写入模块本地存储（远程 UI 绑定用）
    func storageSet(_ key: String, _ value: String) {
        setStorage(key, value)
    }

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
        Self.escapedString(s)
    }
}

// MARK: - 调用状态（看门狗与回调共用，双守卫保证单次 resume）

private final class CallState: @unchecked Sendable {
    private let stateLock = NSLock()
    private var done = false
    private var continuation: CheckedContinuation<String, Never>?

    func register(_ cont: CheckedContinuation<String, Never>) {
        stateLock.lock()
        if done {
            stateLock.unlock()
            cont.resume(returning: "(调用已完成)")
            return
        }
        continuation = cont
        stateLock.unlock()
    }

    func complete(_ value: String) {
        stateLock.lock()
        if done {
            stateLock.unlock()
            return
        }
        done = true
        let cont = continuation
        stateLock.unlock()
        cont?.resume(returning: value)
    }

    func completeIfPending(_ value: String) -> Bool {
        stateLock.lock()
        if done {
            stateLock.unlock()
            return false
        }
        done = true
        let cont = continuation
        stateLock.unlock()
        cont?.resume(returning: value)
        return true
    }
}

// MARK: - 原生桥（block 分发）

/// 回调盒子：强持有 JSContext，保证回调执行时上下文存活（防 use-after-free）
private final class JSCallbackBox: @unchecked Sendable {
    let callback: JSValue
    let context: JSContext
    init(callback: JSValue, context: JSContext) {
        self.callback = callback
        self.context = context
    }
}

enum PluginNativeBridge {

    /// 发起一次受控 HTTP GET（https only / 20s / 2MB）；完成后在 completionQueue 上回调
    static func dispatchFetch(urlString: String, allowsNetwork: Bool, completionQueue: DispatchQueue, callback: JSValue, context: JSContext) {
        let box = JSCallbackBox(callback: callback, context: context)
        guard allowsNetwork else {
            completionQueue.async { box.callback.call(withArguments: ["模块未声明 network 权限", NSNull()]) }
            return
        }
        guard let url = URL(string: urlString), url.scheme == "https" else {
            completionQueue.async { box.callback.call(withArguments: ["仅支持 https 地址", NSNull()]) }
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
            completionQueue.async {
                let err: Any = result.0 ?? NSNull()
                let data: Any = result.1 ?? NSNull()
                box.callback.call(withArguments: [err, data])
            }
        }
    }
}
