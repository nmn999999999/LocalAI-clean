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

    static let maxIterations = 4

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
                appendStep(.thinking, "调用工具 \(call.name)(\(call.arguments))")
                appendStep(.executing, call.name)

                let result = BuiltInTools.execute(toolName: call.name, arguments: call.arguments)
                let record = ChatMessage.ToolCall(
                    id: UUID().uuidString,
                    name: call.name,
                    arguments: Self.compactJSON(call.arguments),
                    result: result
                )
                allToolCalls.append(record)
                appendStep(.result, "\(call.name) → \(result)")

                // 把工具结果作为新一轮上下文
                workingHistory.append(
                    ChatMessage(role: .assistant, content: raw, toolCalls: [record])
                )
                workingHistory.append(
                    ChatMessage(role: .tool, content: "[\(call.name) 结果]\n\(result)")
                )
            } else {
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
            let params = tool.parameters.map { name, schema -> String in
                var desc = "\"\(name)\": {\(schema.type)"
                if !schema.description.isEmpty {
                    desc += ", 描述: \(schema.description)"
                }
                if let enums = schema.enumValues, !enums.isEmpty {
                    desc += ", 可选值: \(enums.joined(separator: "/"))"
                }
                return desc + "}"
            }.joined(separator: "; ")
            return "- \(tool.name): \(tool.description)。参数: {\(params)}"
        }.joined(separator: "\n")

        let instruction = """
        你可以调用以下工具（一次最多一个）。
        当需要调用时，仅输出如下 JSON（不要输出其他文字）：
        {"name": "<工具名>", "arguments": {<参数对象>}}
        当不需要工具、可以直接回答时，正常用中文回答即可。

        可用工具：
        \(catalog)
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
                  let name = obj["name"] as? String,
                  obj["arguments"] != nil || obj.count <= 2
            else { continue }
            let args = obj["arguments"] as? [String: Any] ?? [:]
            if BuiltInTools.allTools.contains(where: { $0.name == name }) {
                return ParsedCall(name: name, arguments: args)
            }
        }
        return nil
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
