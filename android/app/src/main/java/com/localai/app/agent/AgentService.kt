package com.localai.app.agent

import com.localai.app.data.BuiltInTools
import com.localai.app.data.ChatMessage
import com.localai.app.data.MessageRole
import com.localai.app.data.ModelSettings
import com.localai.app.data.ToolCall
import com.localai.app.llm.LLMService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlin.coroutines.coroutineContext
import org.json.JSONObject

/** Agent 循环：模型决定是否调用工具，工具结果回填上下文。
 *  循环不设硬性轮数上限：正常终止条件是模型输出结束暗号（或生成失败/协程取消）。
 *  但设一个很大的「软上限」兜底：防止模型永远不输出暗号导致死循环烧电。
 *  到达软上限前一轮会先通知模型强制收尾；若仍无暗号则优雅退出并返回最后一轮内容。 */
object AgentService {

    /** 流式展示桥：Agent 循环过程中通过它把每一轮的「思考 / 正文 / 工具调用」实时推给聊天 UI。
     *  UI 负责创建与更新气泡；AgentService 只负责在正确的时机调用对应方法。
     *  不传 sink 时回退为「整轮收集后一次性返回」的旧行为，保证降级兼容。 */
    interface AgentSink {
        /** 开始新一轮迭代：UI 创建一条 streaming 的 assistant 气泡并返回它。 */
        suspend fun beginIteration(): ChatMessage

        /** 给指定气泡追加原始 token（含 <think> 标签，气泡会自动解析为思考/正文流）。 */
        suspend fun appendToken(message: ChatMessage, token: String)

        /** 当前轮解析出工具调用：把记录挂到该气泡（含结果），气泡内以可展开 chip 展示。 */
        suspend fun attachToolCall(message: ChatMessage, call: ToolCall)

        /** 结束当前轮迭代：气泡停止 streaming。 */
        suspend fun endIteration(message: ChatMessage)
    }


    const val SOFT_ITERATION_LIMIT = 50

    /** 工作历史上限（条数）。超过后丢弃最旧的对话消息（保留 system 工具说明），
     *  防止超长 Agent 会话把 prompt 撑爆上下文、并降低反复重编码的开销。 */
    const val MAX_WORKING_MESSAGES = 48

    data class Step(val id: Long, val kind: Kind, val detail: String) {
        enum class Kind { THINKING, EXECUTING, RESULT, FINAL_ANSWER }
    }

    private val _steps = MutableStateFlow<List<Step>>(emptyList())
    val steps: StateFlow<List<Step>> = _steps

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    /** Agent 循环结束「暗号」：模型给出最终回答前必须先输出它，循环据此判定结束。 */
    const val END_SIGNAL = "[[FINAL_ANSWER]]"

    /** 检测暗号并提取最终回答。返回 null 表示输出中没有暗号。兼容暗号在前/在后两种写法。 */
    fun extractFinalAnswer(text: String): String? {
        val signalRegex = Regex(Regex.escape(END_SIGNAL), RegexOption.IGNORE_CASE)
        if (!signalRegex.containsMatchIn(text)) return null
        val cleaned = signalRegex.replace(text, "\n")
            .replace("```", "")
            .trim()
        return cleaned.ifEmpty { null }
    }

    /** 去除推理模型（DeepSeek-R1 / Qwen3 等）的 `<think>…</think>` / `<reasoning>…</reasoning>` 块，
     *  含未闭合的情况（生成被 max_tokens 截断或中止时常见）。
     *  Agent 模式下模型常把工具 JSON / 最终答案整段裹在思考块里，
     *  若不剥离，`extractFinalAnswer` / `parseToolCall` 会把答案误判为"思考内容"而吞掉正文。 */
    private fun stripThinkTags(text: String): String {
        var result = text
        while (true) {
            val t = result.indexOf("<think>", ignoreCase = true)
            val r = result.indexOf("<reasoning>", ignoreCase = true)
            val open = when {
                t >= 0 && r >= 0 -> minOf(t, r)
                t >= 0 -> t
                r >= 0 -> r
                else -> -1
            }
            if (open < 0) break
            val tagLen = if (result.regionMatches(open, "<think>", 0, 7, ignoreCase = true)) 7 else 11
            val afterOpen = open + tagLen
            val tc = result.indexOf("</think>", afterOpen, ignoreCase = true)
            val rc = result.indexOf("</reasoning>", afterOpen, ignoreCase = true)
            val close = when {
                tc >= 0 && rc >= 0 -> minOf(tc, rc)
                tc >= 0 -> tc
                rc >= 0 -> rc
                else -> -1
            }
            result = if (close >= 0) {
                val closeLen = if (result.regionMatches(close, "</think>", 0, 8, ignoreCase = true)) 8 else 12
                result.removeRange(open, close + closeLen)
            } else {
                result = result.removeRange(open, result.length)
                break
            }
        }
        return result.trim()
    }

    suspend fun run(
        history: List<ChatMessage>,
        settings: ModelSettings,
        sink: AgentSink? = null,
    ): Pair<String, List<ToolCall>> {
        _steps.value = emptyList()
        _isRunning.value = true
        try {
            var workingHistory = history.toMutableList()
            val allToolCalls = mutableListOf<ToolCall>()
            var lastThinking: String? = null
            var iteration = 0

            while (true) {
                if (!coroutineContext.isActive) break
                iteration++

                // 软上限前一轮：通知模型这是最后一轮，必须收尾
                if (iteration == SOFT_ITERATION_LIMIT) {
                    appendStep(Step.Kind.THINKING, "已连续思考 ${iteration - 1} 轮未结束，通知模型收尾")
                    workingHistory.add(ChatMessage(role = MessageRole.TOOL, content = """
                        你已连续思考很多轮。本轮是最后一轮：不要再调用工具，
                        立即输出 $END_SIGNAL，然后基于以上所有信息给出最终回答正文。
                        """.trimIndent()))
                }
                // 超过软上限仍未结束：优雅退出，返回最后一轮内容
                if (iteration > SOFT_ITERATION_LIMIT) break

                val iterationMsg = sink?.beginIteration()
                val promptMessages = withToolInstructions(trimmedHistory(workingHistory))
                val raw = try {
                    val sb = StringBuilder()
                    if (sink != null && iterationMsg != null) {
                        // 流式：逐 token 透传原始文本，气泡自动解析 <think> 思考块与正文
                        LLMService.streamChat(promptMessages, settings)
                            .collect {
                                sb.append(it)
                                sink.appendToken(iterationMsg, it)
                            }
                    } else {
                        LLMService.streamChat(promptMessages, settings)
                            .collect { sb.append(it) }
                    }
                    sb.toString()
                } catch (e: Exception) {
                    if (iterationMsg != null) sink?.endIteration(iterationMsg)
                    appendStep(Step.Kind.FINAL_ANSWER, "生成失败: ${e.message}")
                    return Pair("生成失败: ${e.message}", allToolCalls)
                }

                // 1) 结束暗号优先：在【原始文本】上检测，避免答案被裹在 <think> 内时
                //    被提前剥离思考块而连暗号一起丢失。命中后再对最终答案单独剥离思考块，
                //    保证正文干净、不被当成"思考内容"吞掉。
                val finalAnswer = extractFinalAnswer(raw)
                if (finalAnswer != null) {
                    appendStep(Step.Kind.FINAL_ANSWER, "检测到结束暗号，输出最终回答")
                    if (iterationMsg != null) sink?.endIteration(iterationMsg)
                    return Pair(stripThinkTags(finalAnswer), allToolCalls)
                }

                // 其余路径：推理模型会把工具 JSON 裹在 <think> 里，先剥离思考块再解析
                val content = stripThinkTags(raw)

                // 2) 有效的工具调用：执行并回填上下文，进入下一轮
                val call = parseToolCall(content)
                if (call != null) {
                    appendStep(Step.Kind.THINKING, "调用工具 ${call.name}(${compactJson(call.arguments)})")
                    appendStep(Step.Kind.EXECUTING, call.name)
                    val result = BuiltInTools.execute(call.name, call.arguments)
                    val limited = limitResult(result)
                    val record = ToolCall(
                        name = call.name,
                        arguments = compactJson(call.arguments),
                        result = limited,
                    )
                    allToolCalls.add(record)
                    appendStep(Step.Kind.RESULT, "${call.name} → $limited")
                    // 流式：把工具调用挂到当前轮气泡（可展开 chip 展示参数/结果）
                    if (iterationMsg != null) sink?.attachToolCall(iterationMsg, record)

                    workingHistory.add(ChatMessage(role = MessageRole.ASSISTANT, content = content, toolCalls = listOf(record)))
                    workingHistory.add(ChatMessage(role = MessageRole.TOOL, content = "[${call.name} 结果]\n$limited"))
                    if (iterationMsg != null) sink?.endIteration(iterationMsg)
                } else {
                    // 3) 无暗号、无有效工具调用：视为模型的中间思考，
                    //    自动触发下一轮思考（思考内容展示在步骤里，不被吞掉）。
                    lastThinking = content
                    appendStep(Step.Kind.THINKING, "思考：${brief(content)}")
                    if (iterationMsg != null) sink?.endIteration(iterationMsg)

                    workingHistory.add(ChatMessage(role = MessageRole.ASSISTANT, content = content))

                    // 若看起来是想调工具但 JSON 写坏了，顺带纠正格式
                    val hint = if (looksLikeToolCall(content) && looksLikeBrokenJSON(content)) {
                        """
                        你的输出看起来想调用工具，但不是合法 JSON。规则：
                        - 调用工具时只输出一个 JSON 对象：{"name": "<工具名>", "arguments": {...}}
                        - 继续思考就直接输出思考内容
                        - 得出最终结论时，先输出 $END_SIGNAL，再输出最终回答正文
                        请继续。
                        """.trimIndent()
                    } else {
                        """
                        继续。若需调用工具，只输出工具 JSON；
                        若已得出最终结论，先输出 $END_SIGNAL，然后输出最终回答正文（正常中文）。
                        """.trimIndent()
                    }
                    workingHistory.add(ChatMessage(role = MessageRole.TOOL, content = hint))
                }
            }
            // 循环仅在「取消」或「软上限耗尽」时到达这里：返回最后一轮思考内容（保证不吞回答）
            if (!lastThinking.isNullOrEmpty()) {
                appendStep(Step.Kind.FINAL_ANSWER, "已停止（未输出结束暗号），返回最后一轮内容")
                return Pair(lastThinking, allToolCalls)
            }
            val fallback = "已停止思考（达到轮数上限或被取消）。以上为当前结果。"
            appendStep(Step.Kind.FINAL_ANSWER, fallback)
            return Pair(fallback, allToolCalls)
        } finally {
            _isRunning.value = false
        }
    }

    /** 结尾检测辅助：输出看起来像工具调用但 JSON 解析失败。 */
    private fun looksLikeToolCall(text: String): Boolean {
        val lower = text.lowercase()
        if (lower.contains("\"name\"") || lower.contains("\"arguments\"")) return true
        return BuiltInTools.allTools.any { text.contains(it.name) }
    }

    /** 输出里确实有 JSON 花括号结构（而非普通文本里恰好提到工具名），才值得重试。 */
    private fun looksLikeBrokenJSON(text: String): Boolean =
        text.contains("{") && text.contains("}")

    /** 步骤面板里展示的思考摘要（截断，避免刷屏）。 */
    private fun brief(text: String, maxLength: Int = 300): String {
        val oneLine = text.trim().replace("\n", " ")
        return if (oneLine.length <= maxLength) oneLine
        else oneLine.take(maxLength) + "…"
    }

    fun reset() {
        _steps.value = emptyList()
    }

    /** 把 Agent 原始输出清理为可展示给用户的正文：移除结束暗号、工具调用 JSON、markdown 围栏。
     *  仅用于 Agent 轮次的气泡渲染；普通聊天内容不会经过此处。 */
    fun cleanDisplayText(text: String): String {
        val toolNames = BuiltInTools.allTools.map { it.name }

        // 1) 先移除结束暗号（不区分大小写）
        var result = text.replace(Regex(Regex.escape(END_SIGNAL), RegexOption.IGNORE_CASE), "")

        // 2) 移除 markdown 代码围栏标记
        result = result.replace("```json", "", ignoreCase = true)
        result = result.replace("```", "")

        // 3) 移除工具调用 JSON：找到顶层 {...}，若包含 "name"/"arguments" 且 name 是已知工具名则去掉
        for (candidate in extractJsonObjects(result)) {
            val lower = candidate.lowercase()
            if (!lower.contains("\"name\"") || !lower.contains("\"arguments\"")) continue
            val name = runCatching {
                JSONObject(candidate).optString("name")
            }.getOrNull() ?: continue
            if (name.isEmpty() || !toolNames.contains(name)) continue
            result = result.replace(candidate, "")
        }

        return result.trim()
    }

    /** 把工作历史裁剪到最多 [MAX_WORKING_MESSAGES] 条：保留第一条 system 消息（工具说明所在），
     *  丢弃最旧的对话消息，保留最近的上下文。返回新列表，不修改入参。 */
    private fun trimmedHistory(history: List<ChatMessage>): List<ChatMessage> {
        if (history.size <= MAX_WORKING_MESSAGES) return history

        var system: ChatMessage? = null
        val rest = mutableListOf<ChatMessage>()
        for (m in history) {
            if (m.role == MessageRole.SYSTEM && system == null) {
                system = m          // system 只保留第一条（含工具说明）
            } else {
                rest.add(m)
            }
        }
        val keep = maxOf(0, MAX_WORKING_MESSAGES - if (system != null) 1 else 0)
        val tail = rest.takeLast(keep)
        return (system?.let { listOf(it) } ?: emptyList()) + tail
    }

    // MARK: - 工具说明注入

    private fun withToolInstructions(history: List<ChatMessage>): List<ChatMessage> {
        val catalog = BuiltInTools.allTools.joinToString("\n") { tool ->
            var lines = "- ${tool.name}: ${tool.description}"
            if (tool.parameters.isNotEmpty()) {
                val params = tool.parameters.entries.joinToString("\n") { (name, schema) ->
                    var s = "  - $name (${schema.type})"
                    if (schema.description.isNotEmpty()) s += ": ${schema.description}"
                    if (!schema.enumValues.isNullOrEmpty()) s += " [可选: ${schema.enumValues.joinToString(" / ")}]"
                    s
                }
                lines += "\n  参数:\n$params"
            }
            lines
        }
        val instruction = """
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

        $END_SIGNAL

        然后紧接着输出最终回答正文（正常中文）。
        暗号是循环结束的唯一信号：只要不输出暗号，系统就会认为你仍在思考并让你继续。

        ## 工具列表
        $catalog

        请开始。
        """.trimIndent()

        val messages = history.toMutableList()
        val sysIdx = messages.indexOfFirst { it.role == MessageRole.SYSTEM }
        if (sysIdx >= 0) {
            messages[sysIdx] = messages[sysIdx].copy(content = messages[sysIdx].content + "\n\n" + instruction)
        } else {
            messages.add(0, ChatMessage(role = MessageRole.SYSTEM, content = instruction))
        }
        return messages
    }

    // MARK: - 工具调用解析

    data class ParsedCall(val name: String, val arguments: Map<String, Any?>)

    fun parseToolCall(text: String): ParsedCall? {
        val cleaned = text
            .replace("```json", "")
            .replace("```", "")
            .trim()
        for (candidate in extractJsonObjects(cleaned)) {
            val obj = runCatching { JSONObject(candidate) }.getOrNull() ?: continue
            val name = obj.optString("name")
            if (name.isEmpty()) continue
            val args: Map<String, Any?> = when (val a = obj.opt("arguments")) {
                is JSONObject -> a.keys().asSequence().associateWith { a.opt(it) }
                is String -> runCatching {
                    val o = JSONObject(a)
                    o.keys().asSequence().associateWith { o.opt(it) }
                }.getOrNull() ?: emptyMap()
                else -> emptyMap()
            }
            if (BuiltInTools.allTools.any { it.name == name }) {
                return ParsedCall(name, args)
            }
        }
        return null
    }

    private fun extractJsonObjects(text: String): List<String> {
        val results = mutableListOf<String>()
        var depth = 0
        var start = -1
        text.forEachIndexed { i, ch ->
            when (ch) {
                '{' -> { if (depth == 0) start = i; depth++ }
                '}' -> {
                    if (depth > 0) {
                        depth--
                        if (depth == 0 && start >= 0) {
                            results.add(text.substring(start, i + 1))
                            start = -1
                        }
                    }
                }
            }
        }
        return results
    }

    private fun compactJson(dict: Map<String, Any?>): String =
        runCatching { JSONObject(dict).toString() }.getOrDefault(dict.toString())

    private fun limitResult(result: String, maxLength: Int = 2000): String =
        if (result.length <= maxLength) result
        else result.take(maxLength) + "\n…(结果过长，已截断)"

    private fun appendStep(kind: Step.Kind, detail: String) {
        _steps.update { it + Step(System.currentTimeMillis(), kind, detail) }
    }
}
