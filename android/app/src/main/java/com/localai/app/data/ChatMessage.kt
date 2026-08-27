package com.localai.app.data

import java.util.UUID

enum class MessageRole { USER, ASSISTANT, SYSTEM, TOOL }

data class ToolCall(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val arguments: String,
    val result: String? = null,
)

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,
    var content: String,
    val timestamp: Long = System.currentTimeMillis(),
    var isStreaming: Boolean = false,
    val images: List<ByteArray> = emptyList(),
    var toolCalls: List<ToolCall> = emptyList(),
)

/**
 * think 块解析（DeepSeek-R1 / Qwen3 风格 <think>…</think> 或 <reasoning>…</reasoning>）。
 * 流式中 `</think>` 未出现时，未闭合部分也算思考内容。
 */
object ThinkParser {

    data class Parsed(val think: String, val answer: String)

    fun parse(content: String): Parsed {
        var think = StringBuilder()
        var answer = StringBuilder()
        var rest = content

        while (true) {
            val openIdx = findOpenTag(rest) ?: break
            answer.append(rest, 0, openIdx)
            val afterOpen = openIdx + tagLen(rest, openIdx)
            val closeIdx = findCloseTag(rest, afterOpen)
            if (closeIdx >= 0) {
                think.append(rest, afterOpen, closeIdx)
                rest = rest.substring(closeIdx + closeTagLen(rest, closeIdx))
            } else {
                think.append(rest.substring(afterOpen))
                rest = ""
                break
            }
        }
        answer.append(rest)

        return Parsed(
            think = think.toString().trim(),
            answer = answer.toString().trim()
        )
    }

    fun thinkContent(content: String): String? =
        parse(content).think.ifEmpty { null }

    fun visibleContent(content: String): String =
        parse(content).answer

    fun isThinking(content: String): Boolean {
        val lower = content.lowercase()
        val hasOpen = lower.contains("<think>") || lower.contains("<reasoning>")
        if (!hasOpen) return false
        val hasClose = lower.contains("</think>") || lower.contains("</reasoning>")
        return !hasClose
    }

    private fun findOpenTag(s: String): Int? {
        val t = s.indexOf("<think>", ignoreCase = true)
        val r = s.indexOf("<reasoning>", ignoreCase = true)
        return when {
            t >= 0 && r >= 0 -> minOf(t, r)
            t >= 0 -> t
            r >= 0 -> r
            else -> null
        }
    }

    private fun tagLen(s: String, idx: Int): Int =
        if (s.regionMatches(idx, "<think>", 0, 7, ignoreCase = true)) 7 else 11

    private fun findCloseTag(s: String, from: Int): Int {
        val t = s.indexOf("</think>", from, ignoreCase = true)
        val r = s.indexOf("</reasoning>", from, ignoreCase = true)
        return when {
            t >= 0 && r >= 0 -> minOf(t, r)
            t >= 0 -> t
            r >= 0 -> r
            else -> -1
        }
    }

    private fun closeTagLen(s: String, idx: Int): Int =
        if (s.regionMatches(idx, "</think>", 0, 8, ignoreCase = true)) 8 else 12
}
