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

    /// 循环不设硬性轮数上限：正常终止条件是模型输出结束暗号（或生成失败/任务取消）。
    /// 但设一个很大的「软上限」兜底：防止模型永远不输出暗号导致死循环烧电。
    /// 到达软上限前一轮会先通知模型强制收尾；若仍无暗号则优雅退出并返回最后一轮内容。
    static let softIterationLimit = 50

    /// Agent 循环结束「暗号」：模型给出最终回答前必须先输出它，
    /// 循环据此判定"模型已收集够信息，可以结束"。
    static let endSignal = "[[FINAL_ANSWER]]"

    /// 检测暗号并提取最终回答。返回 nil 表示输出中没有暗号。
    /// 兼容暗号在前（`暗号+正文`）与在后（`正文+暗号`）两种写法。
    /// 暗号对用户永远隐藏——展示/返回的只有正文。
    static func extractFinalAnswer(from text: String) -> String? {
        guard text.range(of: endSignal, options: [.caseInsensitive]) != nil else { return nil }
        let cleaned = text
            .replacingOccurrences(
                of: endSignal, with: "\n",
                options: [.caseInsensitive]
            )
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 只输出了暗号没有正文：交给上层兜底
        return cleaned.isEmpty ? nil : cleaned
    }

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
        var lastThinking: String?
        var iteration = 0

        while true {
            guard !Task.isCancelled else { break }
            iteration += 1

            // 软上限前一轮：通知模型这是最后一轮，必须收尾
            if iteration == Self.softIterationLimit {
                appendStep(.thinking, "已连续思考 \(iteration - 1) 轮未结束，通知模型收尾")
                workingHistory.append(ChatMessage(role: .tool, content: """
                你已连续思考很多轮。本轮是最后一轮：不要再调用工具，\
                立即输出 \(Self.endSignal)，然后基于以上所有信息给出最终回答正文。
                """))
            }
            // 超过软上限仍未结束：优雅退出，返回最后一轮内容
            if iteration > Self.softIterationLimit { break }

            let promptMessages = withToolInstructions(history: workingHistory, tools: toolsEnabledTools)

            let raw: String
            do {
                raw = try await llm.complete(messages: promptMessages, settings: settings)
            } catch {
                let msg = "生成失败: \(error.localizedDescription)"
                appendStep(.finalAnswer, msg)
                return (msg, allToolCalls)
            }

            // 1) 结束暗号优先：模型已明确表示"信息足够，给出最终回答"，立即终止循环
            if let answer = Self.extractFinalAnswer(from: raw) {
                appendStep(.finalAnswer, "检测到结束暗号，输出最终回答")
                return (answer, allToolCalls)
            }

            // 2) 有效的工具调用：执行并把结果回填上下文，进入下一轮
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
                // 3) 无暗号、无有效工具调用：视为模型的中间思考，
                //    自动触发下一轮思考（思考内容展示在步骤里，不被吞掉）。
                lastThinking = raw
                appendStep(.thinking, "思考：\(Self.brief(raw))")

                workingHistory.append(ChatMessage(role: .assistant, content: raw))

                // 若看起来是想调工具但 JSON 写坏了，顺带纠正格式
                let hint: String
                if Self.looksLikeToolCall(raw, tools: toolsEnabledTools),
                   Self.looksLikeBrokenJSON(raw) {
                    hint = """
                    你的输出看起来想调用工具，但不是合法 JSON。规则：
                    - 调用工具时只输出一个 JSON 对象：{"name": "<工具名>", "arguments": {...}}
                    - 继续思考就直接输出思考内容
                    - 得出最终结论时，先输出 \(Self.endSignal)，再输出最终回答正文
                    请继续。
                    """
                } else {
                    hint = """
                    继续。若需调用工具，只输出工具 JSON；
                    若已得出最终结论，先输出 \(Self.endSignal)，然后输出最终回答正文（正常中文）。
                    """
                }
                workingHistory.append(ChatMessage(role: .tool, content: hint))
            }
        }

        // 循环仅在「取消」或「软上限耗尽」时到达这里：返回最后一轮思考内容（保证不吞回答）
        if let last = lastThinking, !last.isEmpty {
            appendStep(.finalAnswer, "已停止（未输出结束暗号），返回最后一轮内容")
            return (last, allToolCalls)
        }

        let fallback = "已停止思考（达到轮数上限或被取消）。以上为当前结果。"
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
        3. 需要查数据/算数/操作时才调用工具；否则直接结束（见下方结束暗号）。

        ## 多轮思考与执行
        你可以连续多轮：每轮可以调用一个工具，也可以输出一段纯思考内容（不带暗号）——
        系统会自动让你继续思考，你的思考会被保留。观察工具结果后再决定下一步。

        ## 结束暗号（重要！）
        当你已经收集到足够信息、准备给出最终回答时，必须先输出结束暗号：

        \(Self.endSignal)

        然后紧接着输出最终回答正文（正常中文）。
        暗号是循环结束的唯一信号：只要不输出暗号，系统就会认为你仍在思考并让你继续。

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
        if lower.contains("\"name\"") || lower.contains("\"arguments\"") { return true }
        return tools.contains { text.contains($0.name) }
    }

    /// 输出里确实有 JSON 花括号结构（而非普通文本里恰好提到工具名），
    /// 才值得让模型重试；否则直接按最终回答结束。
    private static func looksLikeBrokenJSON(_ text: String) -> Bool {
        text.contains("{") && text.contains("}")
    }

    /// 截断过长的工具结果，避免撑爆上下文。
    private static func limitResult(_ result: String, maxLength: Int = 2000) -> String {
        if result.count <= maxLength { return result }
        let head = String(result.prefix(maxLength))
        return head + "\n…(结果过长，已截断)"
    }

    /// 步骤面板里展示的思考摘要（截断，避免刷屏）。
    private static func brief(_ text: String, maxLength: Int = 300) -> String {
        let oneLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > maxLength else { return oneLine }
        return String(oneLine.prefix(maxLength)) + "…"
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
