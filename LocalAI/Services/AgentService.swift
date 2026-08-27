import Foundation

@MainActor
final class AgentService: ObservableObject {

    struct Step: Identifiable {
        let id = UUID()
        var kind: Kind
        var detail: String

        enum Kind {
            case thinking      // 模型决定调用工具
            case executing     // 正在执行工具
            case result        // 工具结果
            case finalAnswer   // 最终回答
        }
    }

    @Published private(set) var steps: [Step] = []
    @Published private(set) var isRunning = false

    static let maxIterations = 6

    /// 在对话中执行 Agent 循环，返回最终 assistant 消息内容与全部工具调用记录。
    func run(
        history: [ChatMessage],
        settings: ModelSettings,
        toolsEnabledTools: [AgentToolDefinition] = BuiltInTools.allTools,
        llm: LLMService
    ) async -> (content: String, toolCalls: [ChatMessage.ToolCall]) {

        steps.removeAll()
        isRunning = true
        defer { isRunning = false }

        var workingHistory = history
        var allToolCalls: [ChatMessage.ToolCall] = []

        for _ in 0..<Self.maxIterations {
            guard !Task.isCancelled else { break }

            let promptMessages = withToolInstructions(history: workingHistory, tools: toolsEnabledTools)

            let raw: String
            do {
                raw = try await llm.complete(messages: promptMessages, settings: settings)
            } catch {
                appendStep(.finalAnswer, "生成失败: \(error.localizedDescription)")
                break
            }

            if let call = Self.parseToolCall(from: raw) {
                let argsJSON = Self.compactJSON(call.arguments)
                appendStep(.thinking, "调用工具 \(call.name)(\(argsJSON))")
                appendStep(.executing, call.name)

                let result = await BuiltInTools.execute(toolName: call.name, argumentsJSON: argsJSON)
                let limited = Self.limitResult(result)
                let record = ChatMessage.ToolCall(
                    id: UUID().uuidString,
                    name: call.name,
                    arguments: argsJSON,
                    result: limited
                )
                allToolCalls.append(record)
                appendStep(.result, "\(call.name) → \(limited)")

                // 把工具结果作为新一轮上下文
                workingHistory.append(
                    ChatMessage(role: .assistant, content: raw, toolCalls: [record])
                )
                workingHistory.append(
                    ChatMessage(role: .tool, content: "[\(call.name) 结果]\n\(limited)")
                )
            } else {
                // 结尾检测：模型是想调用工具但格式不对（重试），还是真的在给最终回答（结束）？
                if Self.looksLikeToolCall(raw, tools: toolsEnabledTools) {
                    appendStep(.executing, "工具调用格式无效，提示模型重试")
                    workingHistory.append(ChatMessage(role: .assistant, content: raw))
                    workingHistory.append(ChatMessage(role: .tool, content: """
                    你的输出不是有效的工具调用 JSON。规则：
                    - 需要调用工具时，只输出一个 JSON 对象（不要其他文字）：{"name": "<工具名>", "arguments": {...}}
                    - 已经掌握足够信息时，直接给出最终回答（正常中文），不要输出 JSON。
                    请重新输出。
                    """))
                    continue
                }
                appendStep(.finalAnswer, raw)
                return (raw, allToolCalls)
            }
        }

        let fallback = "已达到最大工具调用轮数（\(Self.maxIterations)）。以上为当前结果。"
        appendStep(.finalAnswer, fallback)
        return (fallback, allToolCalls)
    }

    func reset() {
        steps.removeAll()
    }

    // MARK: - 工具说明注入

    private func withToolInstructions(
        history: [ChatMessage],
        tools: [AgentToolDefinition]
    ) -> [ChatMessage] {
        let catalog = tools.map { tool -> String in
            var lines = "- \(tool.name): \(tool.description)"
            if !tool.parameters.isEmpty {
                let params = tool.parameters.map { name, schema -> String in
                    var s = "  - \(name) (\(schema.type))"
                    if !schema.description.isEmpty { s += ": \(schema.description)" }
                    if let enums = schema.enumValues, !enums.isEmpty {
                        s += " [可选: \(enums.joined(separator: " / "))]"
                    }
                    return s
                }.joined(separator: "\n")
                lines += "\n  参数:\n\(params)"
            }
            return lines
        }.joined(separator: "\n")

        let instruction = """
        ## 你能调用的工具
        当需要调用工具时，只输出一个 JSON 对象，不要输出任何其他文字、解释或代码块：

        {"name": "<工具名>", "arguments": {"<参数名>": <值>, ...}}

        ## 调用规则
        1. 一次最多调用一个工具；参数名必须与工具定义完全一致。
        2. 数字参数直接写数值（如 5、3.14）；布尔写 true/false；其余一律写字符串。
        3. 需要查数据/算数/操作时才调用工具；否则直接用中文回答。

        ## 多轮思考与执行
        你可以连续进行多轮：每轮调用一个工具 → 观察返回的工具结果 → 再决定调用下一个工具或给出最终回答。
        当你已经收集到足够信息时，直接输出最终回答（正常中文），不要再输出 JSON。

        ## 工具列表
        \(catalog)

        请开始。
        """

        var messages = history
        if let sysIdx = messages.firstIndex(where: { $0.role == .system }) {
            messages[sysIdx].content += "\n\n" + instruction
        } else {
            messages.insert(ChatMessage(role: .system, content: instruction), at: 0)
        }
        return messages
    }

    // MARK: - 工具调用解析

    struct ParsedCall {
        let name: String
        let arguments: [String: Any]
    }

    static func parseToolCall(from text: String) -> ParsedCall? {
        // 去掉 markdown 代码围栏干扰后，寻找包含 name/arguments 的 JSON 对象
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in extractJSONObjects(in: cleaned) {
            guard let data = candidate.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String
            else { continue }

            // arguments 可能是对象，也可能被模型序列化成了字符串
            var args: [String: Any] = [:]
            if let dict = obj["arguments"] as? [String: Any] {
                args = dict
            } else if let str = obj["arguments"] as? String {
                if let d = str.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    args = parsed
                }
            }

            if BuiltInTools.allTools.contains(where: { $0.name == name }) {
                return ParsedCall(name: name, arguments: args)
            }
        }
        return nil
    }

    /// 结尾检测辅助：判断模型输出是否"看起来想调用工具"（但 JSON 解析失败）。
    /// 用于区分「工具调用格式错误（重试）」与「最终回答（结束）」。
    private static func looksLikeToolCall(_ text: String, tools: [AgentToolDefinition]) -> Bool {
        let lower = text.lowercased()
        if lower.contains("\"name\"") || lower.contains("\"arguments\"") || lower.contains("调用工具") {
            return true
        }
        return tools.contains { text.contains($0.name) }
    }

    /// 截断过长的工具结果，避免撑爆上下文。
    private static func limitResult(_ result: String, maxLength: Int = 2000) -> String {
        if result.count <= maxLength { return result }
        let head = String(result.prefix(maxLength))
        return head + "\n…(结果过长，已截断)"
    }

    /// 粗略提取顶层平衡的 {...} 子串
    private static func extractJSONObjects(in text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var start: String.Index?

        for i in text.indices {
            let ch = text[i]
            if ch == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let s = start {
                        results.append(String(text[s...i]))
                        start = nil
                    }
                }
            }
        }
        return results
    }

    private static func compactJSON(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        else { return "\(dict)" }
        return String(data: data, encoding: .utf8) ?? "\(dict)"
    }

    private func appendStep(_ kind: Step.Kind, _ detail: String) {
        steps.append(Step(kind: kind, detail: detail))
    }
}
