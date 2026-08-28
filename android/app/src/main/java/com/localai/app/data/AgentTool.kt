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
        AgentToolDefinition(
            "regex_extract", "regex_extract", "使用正则表达式从文本中提取匹配的内容",
            mapOf(
                "text" to ParameterSchema("string", "要搜索的文本"),
                "pattern" to ParameterSchema("string", "正则表达式模式"),
            )
        ),
        AgentToolDefinition(
            "text_summary", "text_summary", "对文本进行智能摘要，提取关键信息",
            mapOf(
                "text" to ParameterSchema("string", "要摘要的文本"),
                "max_length" to ParameterSchema("number", "摘要最大长度（可选，默认200）"),
            )
        ),
        AgentToolDefinition(
            "number_base", "number_base", "进制转换：在 decimal(十进制)/binary(二进制)/octal(八进制)/hex(十六进制) 之间互转",
            mapOf(
                "value" to ParameterSchema("string", "要转换的数值，如 255 或 FF"),
                "from" to ParameterSchema("string", "原进制", listOf("decimal", "binary", "octal", "hex")),
                "to" to ParameterSchema("string", "目标进制", listOf("decimal", "binary", "octal", "hex")),
            )
        ),
        AgentToolDefinition(
            "color_convert", "color_convert", "颜色转换：十六进制(#RRGGBB)与 RGB(255,0,0) 互转",
            mapOf(
                "mode" to ParameterSchema("string", "转换方向", listOf("to_hex", "to_rgb")),
                "value" to ParameterSchema("string", "to_hex 时传 RGB 如 255,0,0；to_rgb 时传十六进制如 #ff0000 或 ff0000"),
            )
        ),
        AgentToolDefinition(
            "sort_text", "sort_text", "按行排序文本，可选去重/忽略大小写/逆序",
            mapOf(
                "text" to ParameterSchema("string", "要排序的文本（按换行分行）"),
                "reverse" to ParameterSchema("boolean", "是否逆序（默认 false）"),
                "ignore_case" to ParameterSchema("boolean", "排序时忽略大小写（默认 false）"),
                "dedup" to ParameterSchema("boolean", "是否去除重复行（默认 false）"),
            )
        ),
        AgentToolDefinition(
            "find_replace", "find_replace", "在文本中查找并替换内容，支持正则与普通文本",
            mapOf(
                "text" to ParameterSchema("string", "原文本"),
                "find" to ParameterSchema("string", "要查找的内容"),
                "replace" to ParameterSchema("string", "替换为的内容（默认空串）"),
                "regex" to ParameterSchema("boolean", "find 是否按正则匹配（默认 false）"),
                "all" to ParameterSchema("boolean", "是否替换全部（默认 true；false 仅替换首个）"),
            )
        ),
        AgentToolDefinition(
            "case_convert", "case_convert", "标识符命名风格转换：snake/camel/Pascal/kebab",
            mapOf(
                "text" to ParameterSchema("string", "要转换的标识符"),
                "style" to ParameterSchema("string", "目标风格", listOf("snake", "camel", "pascal", "kebab")),
            )
        ),
        AgentToolDefinition(
            "password_generate", "password_generate", "生成高强度随机密码，可指定长度与字符类别",
            mapOf(
                "length" to ParameterSchema("number", "长度（默认 16，范围 4~128）"),
                "digits" to ParameterSchema("boolean", "包含数字（默认 true）"),
                "symbols" to ParameterSchema("boolean", "包含符号（默认 true）"),
                "uppercase" to ParameterSchema("boolean", "包含大写字母（默认 true）"),
                "lowercase" to ParameterSchema("boolean", "包含小写字母（默认 true）"),
            )
        ),
        AgentToolDefinition(
            "roman", "roman", "罗马数字与阿拉伯数字互转（自动识别方向）",
            mapOf("value" to ParameterSchema("string", "阿拉伯数字(如 1994)或罗马数字(如 MCMXCIV)"))
        ),
        AgentToolDefinition(
            "unit_convert", "unit_convert", "单位换算：长度/重量/温度/体积/数据量。from 与 to 为同一类别的单位名",
            mapOf(
                "value" to ParameterSchema("number", "数值"),
                "from" to ParameterSchema("string", "原单位（如 km/m/kg/g/°C/°F/K/L/ml/MB/GB）"),
                "to" to ParameterSchema("string", "目标单位"),
            )
        ),
        AgentToolDefinition(
            "ssh", "ssh", "通过 SSH 在远程服务器上执行命令（默认使用设置中的 SSH 连接，也可在参数中临时覆盖）。支持密码(password)与私钥PEM(key)两种认证。参数：command(必填)要执行的命令；host/user/port 可选覆盖；auth_type 可选 password/key；password/private_key/passphrase 可选覆盖",
            mapOf(
                "command" to ParameterSchema("string", "要在远程执行的命令（必填），如 uname -a、df -h、systemctl status nginx"),
                "host" to ParameterSchema("string", "主机地址（可选，默认使用设置中的主机）"),
                "user" to ParameterSchema("string", "登录用户名（可选，默认使用设置中的用户名）"),
                "port" to ParameterSchema("number", "端口（可选，默认 22 或设置中的端口）"),
                "auth_type" to ParameterSchema("string", "认证方式", listOf("password", "key")),
                "password" to ParameterSchema("string", "密码（auth_type=password 时使用；留空则用设置中的密码）"),
                "private_key" to ParameterSchema("string", "私钥 PEM 内容（auth_type=key 时使用；留空则用设置中的私钥）"),
                "passphrase" to ParameterSchema("string", "私钥口令（可选，留空则用设置中的口令）"),
            )
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
        "regex_extract" -> executeRegexExtract(arguments)
        "text_summary" -> executeTextSummary(arguments)
        "number_base" -> executeNumberBase(arguments)
        "color_convert" -> executeColorConvert(arguments)
        "sort_text" -> executeSortText(arguments)
        "find_replace" -> executeFindReplace(arguments)
        "case_convert" -> executeCaseConvert(arguments)
        "password_generate" -> executePasswordGenerate(arguments)
        "roman" -> executeRoman(arguments)
        "unit_convert" -> executeUnitConvert(arguments)
        "ssh" -> executeSSH(arguments)
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

    // MARK: 正则提取

    private fun executeRegexExtract(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val pattern = arguments["pattern"] as? String ?: return "错误: 缺少 pattern 参数"
        val regex = runCatching { Regex(pattern) }.getOrNull() ?: return "错误: 无效的正则表达式模式「$pattern」"
        val matches = regex.findAll(text).toList()
        if (matches.isEmpty()) return "未找到匹配「$pattern」的内容"
        val results = matches.take(20).mapIndexed { i, m ->
            val groups = m.groupValues.drop(1)
            buildString {
                append("${i + 1}. ${m.value}")
                if (groups.isNotEmpty()) append(" [捕获组: ${groups.joinToString(", ")}]")
            }
        }
        return "找到 ${matches.size} 个匹配:\n${results.joinToString("\n")}"
    }

    // MARK: 文本摘要

    private fun executeTextSummary(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val maxLength = (arguments["max_length"] as? Number)?.toInt() ?: 200
        if (text.length <= maxLength) return "原文较短，无需摘要:\n$text"
        val sentences = text.split(Regex("[。！？\\n]")).map { it.trim() }.filter { it.isNotEmpty() }
        if (sentences.isEmpty()) return "无法提取有效内容"
        val keywords = listOf("重要", "关键", "核心", "主要", "首先", "其次", "最后", "总结", "结论",
            "important", "key", "main", "first", "conclusion", "summary")
        val scored = sentences.mapIndexed { idx, s ->
            var score = 0.0
            if (idx < 3) score += 2.0
            if (idx >= sentences.size - 2) score += 1.5
            val len = s.length
            if (len > 10 && len < 100) score += 1.0
            val low = s.lowercase()
            for (k in keywords) if (low.contains(k)) score += 1.5
            s to score
        }
        val top = scored.sortedByDescending { it.second }.take(3).joinToString("。") { it.first }
        val summary = if (top.length > maxLength) top.take(maxLength - 3) + "..." else top
        return "摘要:\n$summary"
    }

    // MARK: 进制转换

    private fun radixFor(name: String): Int? = when (name) {
        "decimal" -> 10
        "binary" -> 2
        "octal" -> 8
        "hex", "hexadecimal" -> 16
        else -> null
    }

    private fun executeNumberBase(arguments: Map<String, Any?>): String {
        val value = (arguments["value"] as? String)?.trim() ?: return "错误: 缺少 value 参数"
        if (value.isEmpty()) return "错误: 缺少 value 参数"
        val from = (arguments["from"] as? String)?.lowercase() ?: "decimal"
        val to = (arguments["to"] as? String)?.lowercase() ?: "hex"
        val fr = radixFor(from) ?: return "错误: from 必须是 decimal/binary/octal/hex 之一"
        val tr = radixFor(to) ?: return "错误: to 必须是 decimal/binary/octal/hex 之一"
        val num = runCatching { value.toInt(fr) }.getOrNull() ?: return "错误: 无法将「$value」按 $from 进制解析"
        val out = if (tr == 10) num.toString() else num.toString(tr)
        return "$value ($from) = $out ($to)"
    }

    // MARK: 颜色转换

    private fun executeColorConvert(arguments: Map<String, Any?>): String {
        val mode = arguments["mode"] as? String ?: return "错误: 缺少 mode 参数(to_hex/to_rgb)"
        val value = (arguments["value"] as? String)?.trim() ?: return "错误: 缺少 value 参数"
        if (value.isEmpty()) return "错误: 缺少 value 参数"
        return if (mode == "to_hex") {
            val parts = value.split(",").map { it.trim() }
            if (parts.size != 3) return "错误: to_hex 需要 RGB 形如 255,0,0"
            val r = parts[0].toIntOrNull() ?: return "错误: 无效 R 分量"
            val g = parts[1].toIntOrNull() ?: return "错误: 无效 G 分量"
            val b = parts[2].toIntOrNull() ?: return "错误: 无效 B 分量"
            if (r !in 0..255 || g !in 0..255 || b !in 0..255) return "错误: RGB 分量需在 0~255"
            String.format("#%02X%02X%02X", r, g, b)
        } else if (mode == "to_rgb") {
            var h = value.removePrefix("#")
            if (h.length != 6) return "错误: to_rgb 需要十六进制形如 #ff0000"
            val intVal = runCatching { h.toInt(16) }.getOrNull() ?: return "错误: 无效十六进制"
            val r = (intVal shr 16) and 0xFF
            val g = (intVal shr 8) and 0xFF
            val b = intVal and 0xFF
            "$r, $g, $b"
        } else "错误: mode 必须是 to_hex 或 to_rgb"
    }

    // MARK: 文本排序

    private fun executeSortText(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val reverse = (arguments["reverse"] as? Boolean) ?: false
        val ignoreCase = (arguments["ignore_case"] as? Boolean) ?: false
        val dedup = (arguments["dedup"] as? Boolean) ?: false
        val lines = text.lines().toMutableList()
        lines.sortWith { a, b ->
            if (ignoreCase) a.compareTo(b, ignoreCase = true) else a.compareTo(b)
        }
        if (reverse) lines.reverse()
        val result = if (dedup) {
            val out = mutableListOf<String>()
            for (l in lines) if (out.lastOrNull() != l) out.add(l)
            out
        } else lines
        return result.joinToString("\n")
    }

    // MARK: 查找替换

    private fun executeFindReplace(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        val find = arguments["find"] as? String ?: return "错误: 缺少 find 参数"
        val replace = arguments["replace"] as? String ?: ""
        val regex = (arguments["regex"] as? Boolean) ?: false
        val all = (arguments["all"] as? Boolean) ?: true
        return if (regex) {
            val re = runCatching { Regex(find) }.getOrNull() ?: return "错误: 无效的正则「$find」"
            if (all) re.replace(text, replace) else re.replaceFirst(text, replace)
        } else {
            if (all) text.replace(find, replace) else text.replaceFirst(find, replace)
        }
    }

    // MARK: 命名风格转换

    private fun splitIdentifier(s: String): List<String> {
        val result = mutableListOf<String>()
        var current = StringBuilder()
        val chars = s.toCharArray()
        for (i in chars.indices) {
            val c = chars[i]
            if (c.isLetterOrDigit()) {
                if (c.isUpperCase() && current.isNotEmpty() && !current.last().isUpperCase()) {
                    result.add(current.toString())
                    current = StringBuilder()
                }
                current.append(c)
            } else if (current.isNotEmpty()) {
                result.add(current.toString())
                current = StringBuilder()
            }
        }
        if (current.isNotEmpty()) result.add(current.toString())
        return result.filter { it.isNotEmpty() }
    }

    private fun executeCaseConvert(arguments: Map<String, Any?>): String {
        val text = arguments["text"] as? String ?: return "错误: 缺少 text 参数"
        if (text.isEmpty()) return "错误: 缺少 text 参数"
        val style = arguments["style"] as? String ?: return "错误: 缺少 style 参数"
        val words = splitIdentifier(text)
        return when (style) {
            "snake" -> words.map { it.lowercase() }.joinToString("_")
            "kebab" -> words.map { it.lowercase() }.joinToString("-")
            "camel" -> words.mapIndexed { i, w -> if (i == 0) w.lowercase() else w.replaceFirstChar { it.uppercase() } }.joinToString("")
            "pascal" -> words.map { it.replaceFirstChar { it.uppercase() } }.joinToString("")
            else -> "错误: style 必须是 snake/camel/pascal/kebab"
        }
    }

    // MARK: 密码生成

    private fun executePasswordGenerate(arguments: Map<String, Any?>): String {
        val length = (arguments["length"] as? Number)?.toInt()?.coerceIn(4, 128) ?: 16
        val digits = (arguments["digits"] as? Boolean) ?: true
        val symbols = (arguments["symbols"] as? Boolean) ?: true
        val uppercase = (arguments["uppercase"] as? Boolean) ?: true
        val lowercase = (arguments["lowercase"] as? Boolean) ?: true
        val lowers = "abcdefghijklmnopqrstuvwxyz"
        val uppers = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        val digs = "0123456789"
        val syms = "!@#\$%^&*()-_=+[]{};:,.<>?"
        val pool = buildString {
            if (lowercase) append(lowers)
            if (uppercase) append(uppers)
            if (digits) append(digs)
            if (symbols) append(syms)
        }
        if (pool.isEmpty()) return "错误: 至少启用一种字符类别"
        val rnd = java.util.Random()
        val chars = CharArray(length) { pool[rnd.nextInt(pool.length)] }
        if (lowercase) chars[0] = lowers[rnd.nextInt(lowers.length)]
        if (uppercase && length > 1) chars[1] = uppers[rnd.nextInt(uppers.length)]
        if (digits && length > 2) chars[2] = digs[rnd.nextInt(digs.length)]
        if (symbols && length > 3) chars[3] = syms[rnd.nextInt(syms.length)]
        return "生成密码（长度 $length）: ${String(chars)}"
    }

    // MARK: 罗马数字

    private val romanMap = listOf(
        "M" to 1000, "CM" to 900, "D" to 500, "CD" to 400, "C" to 100,
        "XC" to 90, "L" to 50, "XL" to 40, "X" to 10, "IX" to 9,
        "V" to 5, "IV" to 4, "I" to 1
    )

    private fun intToRoman(n: Int): String {
        var n = n
        val sb = StringBuilder()
        for ((sym, v) in romanMap) while (n >= v) { sb.append(sym); n -= v }
        return sb.toString()
    }

    private fun romanToInt(s: String): Int? {
        var total = 0
        var i = 0
        while (i < s.length) {
            val two = if (i + 1 < s.length) s.substring(i, i + 2) else null
            if (two != null) {
                val v = romanMap.firstOrNull { it.first == two }?.second
                if (v != null) { total += v; i += 2; continue }
            }
            val v = romanMap.firstOrNull { it.first == s[i].toString() }?.second ?: return null
            total += v
            i += 1
        }
        return total
    }

    private fun executeRoman(arguments: Map<String, Any?>): String {
        val value = (arguments["value"] as? String)?.trim() ?: return "错误: 缺少 value 参数"
        if (value.isEmpty()) return "错误: 缺少 value 参数"
        val num = value.toIntOrNull()
        if (num != null) {
            if (num !in 1..3999) return "错误: 阿拉伯数字需在 1~3999"
            return "$value = ${intToRoman(num)}"
        }
        val up = value.uppercase()
        val n = romanToInt(up) ?: return "错误: 无法解析罗马数字「$value」"
        return "$value = $n"
    }

    // MARK: 单位换算

    private val lengthToMeter = mapOf("m" to 1.0, "km" to 1000.0, "cm" to 0.01, "mm" to 0.001,
        "mile" to 1609.344, "yard" to 0.9144, "foot" to 0.3048, "inch" to 0.0254)
    private val weightToKg = mapOf("kg" to 1.0, "g" to 0.001, "mg" to 0.000001, "t" to 1000.0, "ton" to 1000.0,
        "lb" to 0.45359237, "pound" to 0.45359237, "oz" to 0.028349523125, "ounce" to 0.028349523125)
    private val volumeToLiter = mapOf("l" to 1.0, "liter" to 1.0, "ml" to 0.001, "m3" to 1000.0,
        "gallon" to 3.785411784, "cup" to 0.2365882365)
    private val dataToByte = mapOf("b" to 1.0, "byte" to 1.0, "kb" to 1024.0, "mb" to 1048576.0,
        "gb" to 1073741824.0, "tb" to 1099511627776.0)

    private fun unitCategory(u: String): String? = when {
        u in lengthToMeter -> "length"
        u in weightToKg -> "weight"
        u in volumeToLiter -> "volume"
        u in dataToByte -> "data"
        u in setOf("c", "°c", "f", "°f", "k") -> "temp"
        else -> null
    }

    private fun unitToBase(u: String, value: Double): Double? {
        return when {
            u in lengthToMeter -> value * (lengthToMeter[u] ?: return null)
            u in weightToKg -> value * (weightToKg[u] ?: return null)
            u in volumeToLiter -> value * (volumeToLiter[u] ?: return null)
            u in dataToByte -> value * (dataToByte[u] ?: return null)
            u == "c" || u == "°c" -> value
            u == "f" || u == "°f" -> (value - 32) / 1.8
            u == "k" -> value - 273.15
            else -> null
        }
    }

    private fun baseToUnit(u: String, base: Double): Double? {
        return when {
            u in lengthToMeter -> base / (lengthToMeter[u] ?: return null)
            u in weightToKg -> base / (weightToKg[u] ?: return null)
            u in volumeToLiter -> base / (volumeToLiter[u] ?: return null)
            u in dataToByte -> base / (dataToByte[u] ?: return null)
            u == "c" || u == "°c" -> base
            u == "f" || u == "°f" -> base * 1.8 + 32
            u == "k" -> base + 273.15
            else -> null
        }
    }

    private fun executeUnitConvert(arguments: Map<String, Any?>): String {
        val valueNum = (arguments["value"] as? Number)?.toDouble() ?: return "错误: 缺少或无效 value 参数"
        val from = (arguments["from"] as? String)?.lowercase() ?: return "错误: 缺少 from 参数"
        val to = (arguments["to"] as? String)?.lowercase() ?: return "错误: 缺少 to 参数"
        val catFrom = unitCategory(from) ?: return "错误: 未知单位「$from」"
        val catTo = unitCategory(to) ?: return "错误: 未知单位「$to」"
        if (catFrom != catTo) return "错误: from 与 to 单位类别不一致"
        val base = unitToBase(from, valueNum) ?: return "错误: 未知单位「$from」"
        val out = baseToUnit(to, base) ?: return "错误: 未知单位「$to」"
        val text = if (out == out.roundToInt().toDouble()) out.roundToInt().toString() else String.format("%.6g", out)
        return "$valueNum $from = $text $to"
    }

    // SSH 远程命令执行（JSch：密码 / PEM 私钥）
    private fun executeSSH(arguments: Map<String, Any?>): String {
        val command = (arguments["command"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            ?: return "错误: 缺少 command 参数（要在远程执行的命令）"
        val s = com.localai.app.store.SettingsStorage.settings
        val host = (arguments["host"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: s.sshHost.trim()
        if (host.isEmpty()) return "错误: 未配置 SSH 主机（请在「设置 → SSH 连接」填写，或提供 host）"
        val user = (arguments["user"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: s.sshUser.trim()
        if (user.isEmpty()) return "错误: 未配置 SSH 用户名（请在设置中填写，或提供 user 参数）"
        val port = (arguments["port"] as? Number)?.toInt() ?: if (s.sshPort > 0) s.sshPort else 22

        val authArg = (arguments["auth_type"] as? String)?.lowercase()?.trim() ?: ""
        val useKey = if (authArg.isNotEmpty()) {
            authArg == "key" || authArg == "privatekey" || authArg == "pem"
        } else {
            s.sshAuthType.lowercase() == "key"
        }

        val password = (arguments["password"] as? String)?.takeIf { it.isNotBlank() } ?: s.sshPassword
        val privateKey = (arguments["private_key"] as? String)?.takeIf { it.isNotBlank() } ?: s.sshPrivateKey
        val passphrase = (arguments["passphrase"] as? String)?.takeIf { it.isNotBlank() } ?: s.sshPassphrase

        return try {
            val jsch = com.jcraft.jsch.JSch()
            if (useKey) {
                if (privateKey.isBlank()) return "错误: 使用私钥认证但未提供私钥（请在设置填写，或提供 private_key 参数）"
                val passBytes = if (passphrase.isBlank()) null else passphrase.toByteArray(Charsets.UTF_8)
                jsch.addIdentity("ssh-key", privateKey.toByteArray(Charsets.UTF_8), null, passBytes)
            }
            val session = jsch.getSession(user, host, port)
            if (!useKey) session.setPassword(password)
            session.setConfig("StrictHostKeyChecking", "no")
            session.setConfig("PreferredAuthentications", if (useKey) "publickey" else "password")
            session.connect(15000)

            val channel = session.openChannel("exec") as com.jcraft.jsch.ChannelExec
            channel.setCommand(command)
            val out = StringBuilder()
            val collector = object : java.io.OutputStream() {
                @Synchronized override fun write(b: Int) { out.append(b.toChar()) }
                @Synchronized override fun write(b: ByteArray, off: Int, len: Int) {
                    out.append(String(b, off, len, Charsets.UTF_8))
                }
            }
            channel.setOutputStream(collector)
            channel.setErrStream(collector)
            channel.connect(15000)
            var guard = 0
            while (!channel.isClosed && guard < 200) { Thread.sleep(100); guard++ }
            val exitCode = channel.exitStatus
            channel.disconnect()
            session.disconnect()
            "命令退出码: ${exitCode ?: -1}\n--- 输出 ---\n$out"
        } catch (e: Exception) {
            "SSH 执行失败: ${e.message ?: e.javaClass.simpleName}"
        }
    }
}

/** 应用上下文持有者（MainActivity.onCreate 里设置）。 */
object AppContextHolder {
    var context: android.content.Context? = null
}
