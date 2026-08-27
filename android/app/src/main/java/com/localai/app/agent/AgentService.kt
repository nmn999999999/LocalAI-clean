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
import org.json.JSONObject

/** Agent 循环：模型决定是否调用工具，工具结果回填上下文，最多 maxIterations 轮。 */
object AgentService {

    data class Step(val id: Long, val kind: Kind, val detail: String) {
        enum class Kind { THINKING, EXECUTING, RESULT, FINAL_ANSWER }
    }

    private val _steps = MutableStateFlow<List<Step>>(emptyList())
    val steps: StateFlow<List<Step>> = _steps

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    const val maxIterations = 4

    suspend fun run(
        history: List<ChatMessage>,
        settings: ModelSettings,
    ): Pair<String, List<ToolCall>> {
        _steps.value = emptyList()
        _isRunning.value = true
        try {
            var workingHistory = history.toMutableList()
            val allToolCalls = mutableListOf<ToolCall>()

            repeat(maxIterations) {
                val promptMessages = withToolInstructions(workingHistory)
                val raw = try {
                    val sb = StringBuilder()
                    LLMService.streamChat(promptMessages, settings)
                        .collect { sb.append(it) }
                    sb.toString()
                } catch (e: Exception) {
                    appendStep(Step.Kind.FINAL_ANSWER, "生成失败: ${e.message}")
                    return Pair("生成失败: ${e.message}", allToolCalls)
                }

                val call = parseToolCall(raw)
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

                    workingHistory.add(ChatMessage(role = MessageRole.ASSISTANT, content = raw, toolCalls = listOf(record)))
                    workingHistory.add(ChatMessage(role = MessageRole.TOOL, content = "[${call.name} 结果]\n$limited"))
                } else {
                    appendStep(Step.Kind.FINAL_ANSWER, raw)
                    return Pair(raw, allToolCalls)
                }
            }
            val fallback = "已达到最大工具调用轮数（$maxIterations）。以上为当前结果。"
            appendStep(Step.Kind.FINAL_ANSWER, fallback)
            return Pair(fallback, allToolCalls)
        } finally {
            _isRunning.value = false
        }
    }

    fun reset() {
        _steps.value = emptyList()
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
        3. 先判断是否需要工具：需要查数据/算数/操作时才调用；否则直接用中文回答。

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
