import Foundation
import JavaScriptCore

/// JS 插件执行引擎（基于系统 JavaScriptCore，无需任何第三方依赖）。
///
/// 沙箱说明：不向 JS 上下文注入任何 ObjC/Swift 对象——JS 只能做纯计算
/// （字符串/JSON/数字/日期等标准 API），无法访问文件、网络、UI。
/// 需要联网/副作用的工具请用内置 http_get 或 MCP。
///
/// 线程模型：AgentService 在 @MainActor 串行调用，JSContext 不跨线程共享。
final class JSPluginEngine: @unchecked Sendable {

    let manifest: PluginManifest
    private let context: JSContext
    private(set) var tools: [PluginToolDef] = []

    /// - Parameters:
    ///   - manifest: 模块清单
    ///   - jsSource: tools.js 源码（内部调用 registerTool(...) 注册工具）
    init?(manifest: PluginManifest, jsSource: String) {
        self.manifest = manifest
        guard let ctx = JSContext() else { return nil }
        self.context = ctx

        ctx.name = "LocalAI-plugin-\(manifest.id)"
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            print("[plugin:\(manifest.id)] JS exception: \(msg)")
        }

        // 注入注册桥（preamble）：registerTool 收集到 __tools，供 App 读取与调用
        let preamble = """
        var __tools = [];
        function registerTool(def) {
          if (def && typeof def.name === 'string' && typeof def.run === 'function') {
            __tools.push({
              name: def.name,
              description: typeof def.description === 'string' ? def.description : '',
              parameters: def.parameters || {},
              run: def.run
            });
          }
        }
        function __pluginTools() { return JSON.stringify(__tools.map(function(t){
          return { name: t.name, description: t.description, parameters: t.parameters };
        })); }
        function __callTool(name, argsJSON) {
          var t = null;
          for (var i = 0; i < __tools.length; i++) { if (__tools[i].name === name) { t = __tools[i]; break; } }
          if (!t) return JSON.stringify({ error: 'unknown tool: ' + name });
          try {
            var args = argsJSON ? JSON.parse(argsJSON) : {};
            var r = t.run(args);
            return JSON.stringify({ result: r });
          } catch (e) {
            return JSON.stringify({ error: String(e) });
          }
        }
        """

        ctx.evaluateScript(preamble)
        ctx.evaluateScript(jsSource)

        // 读取注册的工具定义
        if let raw = ctx.evaluateScript("__pluginTools()")?.toString(),
           let data = raw.data(using: .utf8),
           let defs = try? JSONDecoder().decode([PluginToolDef].self, from: data) {
            tools = defs
        }
    }

    /// 转成 Agent 工具目录定义（纯计算 → 无需授权）
    func toolDefinitions() -> [AgentToolDefinition] {
        tools.map { def in
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
                requiresApproval: false
            )
        }
    }

    /// 调用插件工具，返回纯文本结果（成功/错误都以文本呈现，供 Agent 回填上下文）
    func call(name: String, argumentsJSON: String) -> String {
        let script = "__callTool(\(JSONString(name)), \(JSONString(argumentsJSON)))"
        guard let value = context.evaluateScript(script)?.toString(),
              let data = value.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return "插件调用失败（无法解析返回值）"
        }
        if let error = obj["error"] as? String {
            return "插件错误: \(error)"
        }
        if let result = obj["result"] {
            if let s = result as? String { return s }
            if let d = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               let s = String(data: d, encoding: .utf8) { return s }
            return "\(result)"
        }
        return "(无返回值)"
    }

    private func JSONString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s),
              let str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return str
    }
}
