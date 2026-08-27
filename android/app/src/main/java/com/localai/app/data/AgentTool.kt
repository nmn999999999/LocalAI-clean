package com.localai.app.data

import java.security.MessageDigest
import java.util.Base64
import kotlin.math.*

data class AgentToolDefinition(
    val id: String,
    val name: String,
    val description: String,
    val parameters: Map<String, ParameterSchema> = emptyMap(),
)

data class ParameterSchema(
    val type: String,
    val description: String,
    val enumValues: List<String>? = null,
)

/** 内置工具：与 iOS 版一致。 */
object BuiltInTools {

    val allTools: List<AgentToolDefinition> = listOf(
        AgentToolDefinition(
            "calculator", "calculator",
            "计算数学表达式，支持 + - * / % ^、括号、函数(sqrt/abs/round/sin/cos/tan/log/exp/min/max/pow)与常量(pi/e)",
            mapOf("expression" to ParameterSchema("string", "数学表达式，如 2+3*4 或 sqrt(16)"))
        ),
        AgentToolDefinition("current_time", "current_time", "获取当前日期和时间"),
        AgentToolDefinition("generate_uuid", "generate_uuid", "生成一个UUID"),
        AgentToolDefinition(
            "random_number", "random_number", "生成指定范围内的随机整数",
            mapOf(
                "min" to ParameterSchema("number", "最小值（含），默认 1"),
                "max" to ParameterSchema("number", "最大值（含），默认 100"),
            )
        ),
        AgentToolDefinition(
            "word_count", "word_count", "统计文本的字数、字符数和行数",
            mapOf("text" to ParameterSchema("string", "要统计的文本"))
        ),
        AgentToolDefinition(
            "text_transform", "text_transform", "转换文本格式：大写、小写、反转、Base64编码/解码",
            mapOf(
                "text" to ParameterSchema("string", "要转换的文本"),
                "transform" to ParameterSchema(
                    "string", "转换类型",
                    listOf("uppercase", "lowercase", "reverse", "base64_encode", "base64_decode")
                ),
            )
        ),
        AgentToolDefinition(
            "date_add", "date_add", "计算某个日期加减 N 天后的日期，date 为空表示今天",
            mapOf(
                "date" to ParameterSchema("string", "日期，格式 yyyy-MM-dd，可省略表示今天"),
                "days" to ParameterSchema("number", "加减的天数，负数表示往前"),
            )
        ),
        AgentToolDefinition(
            "date_diff", "date_diff", "计算两个日期相差的天数",
            mapOf(
                "date1" to ParameterSchema("string", "起始日期 yyyy-MM-dd"),
                "date2" to ParameterSchema("string", "结束日期 yyyy-MM-dd"),
            )
        ),
        AgentToolDefinition(
            "hash_text", "hash_text", "计算文本的 MD5 / SHA1 / SHA256 摘要",
            mapOf(
                "text" to ParameterSchema("string", "要哈希的文本"),
                "algorithm" to ParameterSchema("string", "算法", listOf("md5", "sha1", "sha256")),
            )
        ),
        AgentToolDefinition(
            "json_format", "json_format", "格式化或压缩 JSON 字符串",
            mapOf(
                "json" to ParameterSchema("string", "要处理的 JSON 字符串"),
                "pretty" to ParameterSchema("boolean", "是否美化输出（默认 true）"),
            )
        ),
        AgentToolDefinition(
            "url_codec", "url_codec", "URL 编码或解码文本",
            mapOf(
                "text" to ParameterSchema("string", "要处理的文本"),
                "mode" to ParameterSchema("string", "模式", listOf("encode", "decode")),
            )
        ),
        AgentToolDefinition(
            "note", "note", "持久化笔记（本机存储，可跨对话记忆）：save 保存、read 读取、list 列出全部、delete 删除",
            mapOf(
                "op" to ParameterSchema("string", "操作", listOf("save", "read", "list", "delete")),
                "name" to ParameterSchema("string", "笔记名称（save/read/delete 必填）"),
                "content" to ParameterSchema("string", "笔记内容（save 必填）"),
            )
        ),
        AgentToolDefinition(
            "clipboard", "clipboard", "读取或设置系统剪贴板",
            mapOf(
                "op" to ParameterSchema("string", "操作", listOf("get", "set")),
                "text" to ParameterSchema("string", "要写入剪贴板的内容（set 必填）"),
            )
        ),
        AgentToolDefinition(
            "web_search", "web_search", "联网搜索网页（Bing 等），返回相关结果标题、链接与摘要",
            mapOf("query" to ParameterSchema("string", "搜索关键词"))
        ),
    )

    /** 执行工具。arguments 为 JSON 解析出的 Map。 */
    suspend fun execute(toolName: String, arguments: Map<String, Any?>): String = when (toolName) {
        "calculator" -> executeCalculator(arguments)
        "current_time" -> executeCurrentTime()
        "generate_uuid" -> java.util.UUID.randomUUID().toString()
        "random_number" -> executeRandomNumber(arguments)
        "word_count" -> executeWordCount(arguments)
        "text_transform" -> executeTextTransform(arguments)
        "date_add" -> executeDateAdd(arguments)
        "date_diff" -> executeDateDiff(arguments)
        "hash_text" -> executeHashText(arguments)
        "json_format" -> executeJsonFormat(arguments)
        "url_codec" -> executeUrlCodec(arguments)
        "note" -> executeNote(arguments)
        "clipboard" -> executeClipboard(arguments)
        "web_search" -> executeWebSearch(arguments)
        else -> "未知工具: $toolName"
    }

    // MARK: 工具实现

    private fun executeCalculator(arguments: Map<String, Any?>): String {
        val expression = arguments["expression"] as? String ?: return "错误: 缺少 expression 参数"
        val value = MathEvaluator.evaluate(expression) ?: return "错误: 无法解析表达式「$expression」，请检查运算符与括号是否完整"
        val text = if (value == value.roundToLong().toDouble() && abs(value) < 1e15) {
            value.roundToLong().toString()
        } else {
            String.format("%.10g", value)
        }
        return "$expression = $text"
    }

    private fun executeCurrentTime(): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.CHINA)
        return "当前时间: ${fmt.format(java.util.Date())}"
    }

    private fun executeRandomNumber(arguments: Map<String, Any?>): String {
        val minV = (arguments["min"] as? Number)?.toInt() ?: 1
        val maxV = (arguments["max"] as? Number)?.toInt() ?: 100
        if (minV > maxV) return "错误: min 应不大于 max"
        return "随机数: ${(minV..maxV).random()}（范围 $minV~$maxV）"
    }

    private fun executeWordCount(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val wordCount = text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }
        return "字符数: ${text.length}, 单词数: $wordCount, 行数: ${text.lines().size}"
    }

    private fun executeTextTransform(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少参数"
        val transform = arguments["transform"] as? String ?: return "错误: 缺少参数"
        return when (transform) {
            "uppercase" -> text.uppercase()
            "lowercase" -> text.lowercase()
            "reverse" -> text.reversed()
            "base64_encode" -> Base64.getEncoder().encodeToString(text.toByteArray())
            "base64_decode" -> runCatching {
                String(Base64.getDecoder().decode(text))
            }.getOrElse { "Base64解码失败" }
            else -> "未知转换类型: $transform"
        }
    }

    private fun dateFmt(): java.text.SimpleDateFormat =
        java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.CHINA)

    private fun executeDateAdd(arguments: Map<String, Any?>): String {
        val dateStr = arguments["date"] as? String ?: ""
        val days = (arguments["days"] as? Number)?.toInt() ?: 0
        val base = if (dateStr.isEmpty()) java.util.Date() else
            runCatching { dateFmt().parse(dateStr)!! }.getOrElse { java.util.Date() }
        val cal = java.util.Calendar.getInstance().apply { time = base; add(java.util.Calendar.DAY_OF_MONTH, days) }
        return "${dateFmt().format(base)} + $days 天 = ${dateFmt().format(cal.time)}"
    }

    private fun executeDateDiff(arguments: Map<String, Any?>): String {
        val d1 = arguments["date1"] as? String ?: return "错误: 需要有效的 date1 和 date2（格式 yyyy-MM-dd）"
        val d2 = arguments["date2"] as? String ?: return "错误: 需要有效的 date1 和 date2（格式 yyyy-MM-dd）"
        val a = runCatching { dateFmt().parse(d1)!! }.getOrNull()
            ?: return "错误: 需要有效的 date1 和 date2（格式 yyyy-MM-dd）"
        val b = runCatching { dateFmt().parse(d2)!! }.getOrNull()
            ?: return "错误: 需要有效的 date1 和 date2（格式 yyyy-MM-dd）"
        val days = ((b.time - a.time) / 86400000.0).roundToLong()
        return "$d1 到 $d2 相差 ${abs(days)} 天"
    }

    private fun executeHashText(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val algorithm = (arguments["algorithm"] as? String)?.lowercase() ?: "sha256"
        val digestName = when (algorithm) {
            "md5" -> "MD5"
            "sha1" -> "SHA-1"
            "sha256" -> "SHA-256"
            else -> return "未知算法: $algorithm（可选 md5/sha1/sha256）"
        }
        val bytes = MessageDigest.getInstance(digestName).digest(text.toByteArray())
        val hex = bytes.joinToString("") { "%02x".format(it) }
        return "$algorithm = $hex"
    }

    private fun executeJsonFormat(arguments: Map<String, Any?>): String {
        val json = arguments["json"] as? String ?: return "错误: 缺少 json 参数"
        val pretty = (arguments["pretty"] as? Boolean) ?: true
        return runCatching {
            val obj = org.json.JSONObject(json)
            if (pretty) obj.toString(2) else obj.toString()
        }.getOrElse { "错误: JSON 解析失败" }
    }

    private fun executeUrlCodec(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val mode = arguments["mode"] as? String ?: "encode"
        return if (mode == "decode") {
            java.net.URLDecoder.decode(text, "UTF-8")
        } else {
            java.net.URLEncoder.encode(text, "UTF-8")
        }
    }

    private fun notesDir(): java.io.File {
        // 应用私有目录（分区存储下公共外部存储无权限，必须用私有目录）
        val dir = java.io.File(AppContextHolder.context?.filesDir ?: return java.io.File(""), "agent_notes")
        dir.mkdirs()
        return dir
    }

    private fun executeNote(arguments: Map<String, Any?>): String {
        val op = arguments["op"] as? String ?: "list"
        val name = (arguments["name"] as? String)?.trim()?.replace("/", "-") ?: ""
        val dir = notesDir()
        return when (op) {
            "save" -> {
                if (name.isEmpty()) "错误: 保存笔记需要 name 参数"
                else {
                    val content = arguments["content"] as? String ?: ""
                    runCatching {
                        java.io.File(dir, "$name.txt").writeText(content, Charsets.UTF_8)
                        "已保存笔记「$name」（${content.length} 字）"
                    }.getOrElse { "保存失败: ${it.message}" }
                }
            }
            "read" -> {
                if (name.isEmpty()) "错误: 读取笔记需要 name 参数"
                else {
                    val f = java.io.File(dir, "$name.txt")
                    if (f.exists()) "「$name」: ${f.readText(Charsets.UTF_8)}" else "未找到笔记「$name」"
                }
            }
            "delete" -> {
                if (name.isEmpty()) "错误: 删除笔记需要 name 参数"
                else {
                    val f = java.io.File(dir, "$name.txt")
                    if (f.delete()) "已删除笔记「$name」" else "删除失败或不存在: $name"
                }
            }
            else -> {
                val names = dir.listFiles()?.filter { it.extension == "txt" }
                    ?.map { it.nameWithoutExtension } ?: emptyList()
                if (names.isEmpty()) "暂无笔记" else "现有笔记: ${names.joinToString(", ")}"
            }
        }
    }

    private fun executeClipboard(arguments: Map<String, Any?>): String {
        val op = arguments["op"] as? String ?: "get"
        val ctx = AppContextHolder.context ?: return "剪贴板不可用"
        val cm = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        return if (op == "set") {
            val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
            cm.setPrimaryClip(android.content.ClipData.newPlainText("LocalAI", text))
            "已写入剪贴板（${text.length} 字）"
        } else {
            val clip = cm.primaryClip
            val text = clip?.getItemAt(0)?.coerceToText(ctx)?.toString() ?: ""
            if (text.isEmpty()) "剪贴板为空" else "剪贴板内容: ${text.take(2000)}"
        }
    }

    private suspend fun executeWebSearch(arguments: Map<String, Any?>): String {
        val query = arguments["query"] as? String ?: return "错误: 缺少 query 参数"
        // 优先 SearXNG（自托管搜索服务，可在设置中配置），失败自动回退维基百科
        return SearchService.search(query, com.localai.app.store.SettingsStorage.settings)
    }
}

/** 应用上下文持有者（MainActivity.onCreate 里设置）。 */
object AppContextHolder {
    var context: android.content.Context? = null
}
