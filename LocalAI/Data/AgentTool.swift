import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

struct AgentToolDefinition: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let parameters: [String: ParameterSchema]

    struct ParameterSchema: Codable, Sendable {
        let type: String
        let description: String
        let enumValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }
}

struct ToolCallRequest: Codable {
    let name: String
    let arguments: [String: AnyCodable]

    struct AnyCodable: Codable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                value = intVal
            } else if let doubleVal = try? container.decode(Double.self) {
                value = doubleVal
            } else if let boolVal = try? container.decode(Bool.self) {
                value = boolVal
            } else if let stringVal = try? container.decode(String.self) {
                value = stringVal
            } else if let arrayVal = try? container.decode([AnyCodable].self) {
                value = arrayVal.map(\.value)
            } else if let dictVal = try? container.decode([String: AnyCodable].self) {
                value = dictVal.mapValues(\.value)
            } else {
                value = ""
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let intVal = value as? Int {
                try container.encode(intVal)
            } else if let doubleVal = value as? Double {
                try container.encode(doubleVal)
            } else if let boolVal = value as? Bool {
                try container.encode(boolVal)
            } else if let stringVal = value as? String {
                try container.encode(stringVal)
            } else if let arrayVal = value as? [Any] {
                try container.encode(arrayVal.map { AnyCodable($0) })
            } else if let dictVal = value as? [String: Any] {
                try container.encode(dictVal.mapValues { AnyCodable($0) })
            } else {
                try container.encode("")
            }
        }
    }
}

enum BuiltInTools {

    static let allTools: [AgentToolDefinition] = [
        AgentToolDefinition(
            id: "calculator",
            name: "calculator",
            description: "计算数学表达式，支持 + - * / % ^、括号、函数(sqrt/abs/round/sin/cos/tan/log/exp/min/max/pow)与常量(pi/e)",
            parameters: [
                "expression": .init(type: "string", description: "数学表达式，如 2+3*4 或 sqrt(16)", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "current_time",
            name: "current_time",
            description: "获取当前日期和时间",
            parameters: [:]
        ),
        AgentToolDefinition(
            id: "generate_uuid",
            name: "generate_uuid",
            description: "生成一个UUID",
            parameters: [:]
        ),
        AgentToolDefinition(
            id: "random_number",
            name: "random_number",
            description: "生成指定范围内的随机整数",
            parameters: [
                "min": .init(type: "number", description: "最小值（含），默认 1", enumValues: nil),
                "max": .init(type: "number", description: "最大值（含），默认 100", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "word_count",
            name: "word_count",
            description: "统计文本的字数、字符数和行数",
            parameters: [
                "text": .init(type: "string", description: "要统计的文本", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "text_transform",
            name: "text_transform",
            description: "转换文本格式：大写、小写、反转、Base64编码/解码",
            parameters: [
                "text": .init(type: "string", description: "要转换的文本", enumValues: nil),
                "transform": .init(type: "string", description: "转换类型", enumValues: ["uppercase", "lowercase", "reverse", "base64_encode", "base64_decode"])
            ]
        ),
        AgentToolDefinition(
            id: "date_add",
            name: "date_add",
            description: "计算某个日期加减 N 天后的日期，date 为空表示今天",
            parameters: [
                "date": .init(type: "string", description: "日期，格式 yyyy-MM-dd，可省略表示今天", enumValues: nil),
                "days": .init(type: "number", description: "加减的天数，负数表示往前", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "date_diff",
            name: "date_diff",
            description: "计算两个日期相差的天数",
            parameters: [
                "date1": .init(type: "string", description: "起始日期 yyyy-MM-dd", enumValues: nil),
                "date2": .init(type: "string", description: "结束日期 yyyy-MM-dd", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "hash_text",
            name: "hash_text",
            description: "计算文本的 MD5 / SHA1 / SHA256 摘要",
            parameters: [
                "text": .init(type: "string", description: "要哈希的文本", enumValues: nil),
                "algorithm": .init(type: "string", description: "算法", enumValues: ["md5", "sha1", "sha256"])
            ]
        ),
        AgentToolDefinition(
            id: "json_format",
            name: "json_format",
            description: "格式化或压缩 JSON 字符串",
            parameters: [
                "json": .init(type: "string", description: "要处理的 JSON 字符串", enumValues: nil),
                "pretty": .init(type: "boolean", description: "是否美化输出（默认 true）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "url_codec",
            name: "url_codec",
            description: "URL 编码或解码文本",
            parameters: [
                "text": .init(type: "string", description: "要处理的文本", enumValues: nil),
                "mode": .init(type: "string", description: "模式", enumValues: ["encode", "decode"])
            ]
        ),
        AgentToolDefinition(
            id: "note",
            name: "note",
            description: "持久化笔记（本机存储，可跨对话记忆）：save 保存、read 读取、list 列出全部、delete 删除",
            parameters: [
                "op": .init(type: "string", description: "操作", enumValues: ["save", "read", "list", "delete"]),
                "name": .init(type: "string", description: "笔记名称（save/read/delete 必填）", enumValues: nil),
                "content": .init(type: "string", description: "笔记内容（save 必填）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "clipboard",
            name: "clipboard",
            description: "读取或设置系统剪贴板",
            parameters: [
                "op": .init(type: "string", description: "操作", enumValues: ["get", "set"]),
                "text": .init(type: "string", description: "要写入剪贴板的内容（set 必填）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "web_search",
            name: "web_search",
            description: "联网搜索网页（Bing 等），返回相关结果标题、链接与摘要",
            parameters: [
                "query": .init(type: "string", description: "搜索关键词", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "regex_extract",
            name: "regex_extract",
            description: "使用正则表达式从文本中提取匹配的内容",
            parameters: [
                "text": .init(type: "string", description: "要搜索的文本", enumValues: nil),
                "pattern": .init(type: "string", description: "正则表达式模式", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "text_summary",
            name: "text_summary",
            description: "对文本进行智能摘要，提取关键信息",
            parameters: [
                "text": .init(type: "string", description: "要摘要的文本", enumValues: nil),
                "max_length": .init(type: "number", description: "摘要最大长度（可选，默认200）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "number_base",
            name: "number_base",
            description: "进制转换：在 decimal(十进制)/binary(二进制)/octal(八进制)/hex(十六进制) 之间互转",
            parameters: [
                "value": .init(type: "string", description: "要转换的数值，如 255 或 FF", enumValues: nil),
                "from": .init(type: "string", description: "原进制", enumValues: ["decimal", "binary", "octal", "hex"]),
                "to": .init(type: "string", description: "目标进制", enumValues: ["decimal", "binary", "octal", "hex"])
            ]
        ),
        AgentToolDefinition(
            id: "color_convert",
            name: "color_convert",
            description: "颜色转换：十六进制(#RRGGBB)与 RGB(255,0,0) 互转",
            parameters: [
                "mode": .init(type: "string", description: "转换方向", enumValues: ["to_hex", "to_rgb"]),
                "value": .init(type: "string", description: "to_hex 时传 RGB 如 255,0,0；to_rgb 时传十六进制如 #ff0000 或 ff0000", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "sort_text",
            name: "sort_text",
            description: "按行排序文本，可选去重/忽略大小写/逆序",
            parameters: [
                "text": .init(type: "string", description: "要排序的文本（按换行分行）", enumValues: nil),
                "reverse": .init(type: "boolean", description: "是否逆序（默认 false）", enumValues: nil),
                "ignore_case": .init(type: "boolean", description: "排序时忽略大小写（默认 false）", enumValues: nil),
                "dedup": .init(type: "boolean", description: "是否去除重复行（默认 false）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "find_replace",
            name: "find_replace",
            description: "在文本中查找并替换内容，支持正则与普通文本",
            parameters: [
                "text": .init(type: "string", description: "原文本", enumValues: nil),
                "find": .init(type: "string", description: "要查找的内容", enumValues: nil),
                "replace": .init(type: "string", description: "替换为的内容（默认空串）", enumValues: nil),
                "regex": .init(type: "boolean", description: "find 是否按正则匹配（默认 false）", enumValues: nil),
                "all": .init(type: "boolean", description: "是否替换全部（默认 true；false 仅替换首个）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "case_convert",
            name: "case_convert",
            description: "标识符命名风格转换：snake/camel/Pascal/kebab",
            parameters: [
                "text": .init(type: "string", description: "要转换的标识符", enumValues: nil),
                "style": .init(type: "string", description: "目标风格", enumValues: ["snake", "camel", "pascal", "kebab"])
            ]
        ),
        AgentToolDefinition(
            id: "password_generate",
            name: "password_generate",
            description: "生成高强度随机密码，可指定长度与字符类别",
            parameters: [
                "length": .init(type: "number", description: "长度（默认 16，范围 4~128）", enumValues: nil),
                "digits": .init(type: "boolean", description: "包含数字（默认 true）", enumValues: nil),
                "symbols": .init(type: "boolean", description: "包含符号（默认 true）", enumValues: nil),
                "uppercase": .init(type: "boolean", description: "包含大写字母（默认 true）", enumValues: nil),
                "lowercase": .init(type: "boolean", description: "包含小写字母（默认 true）", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "roman",
            name: "roman",
            description: "罗马数字与阿拉伯数字互转（自动识别方向）",
            parameters: [
                "value": .init(type: "string", description: "阿拉伯数字(如 1994)或罗马数字(如 MCMXCIV)", enumValues: nil)
            ]
        ),
        AgentToolDefinition(
            id: "unit_convert",
            name: "unit_convert",
            description: "单位换算：长度/重量/温度/体积/数据量。from 与 to 为同一类别的单位名",
            parameters: [
                "value": .init(type: "number", description: "数值", enumValues: nil),
                "from": .init(type: "string", description: "原单位（如 km/m/kg/g/°C/°F/K/L/ml/MB/GB）", enumValues: nil),
                "to": .init(type: "string", description: "目标单位", enumValues: nil)
            ]
        ),
    ]

    // MARK: - 执行入口

    /// arguments 以 JSON 字符串传入（String 为 Sendable，可安全跨 actor 传递）。
    static func execute(toolName: String, argumentsJSON: String) async -> String {
        var arguments: [String: Any] = [:]
        if let data = argumentsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = obj
        }
        switch toolName {
        case "calculator":      return executeCalculator(arguments: arguments)
        case "current_time":    return executeCurrentTime()
        case "generate_uuid":   return UUID().uuidString
        case "random_number":   return executeRandomNumber(arguments: arguments)
        case "word_count":      return executeWordCount(arguments: arguments)
        case "text_transform":  return executeTextTransform(arguments: arguments)
        case "date_add":        return executeDateAdd(arguments: arguments)
        case "date_diff":       return executeDateDiff(arguments: arguments)
        case "hash_text":       return executeHashText(arguments: arguments)
        case "json_format":     return executeJsonFormat(arguments: arguments)
        case "url_codec":       return executeUrlCodec(arguments: arguments)
        case "note":            return executeNote(arguments: arguments)
        case "clipboard":       return executeClipboard(arguments: arguments)
        case "web_search":      return await executeWebSearch(arguments: arguments)
        case "regex_extract":   return executeRegexExtract(arguments: arguments)
        case "text_summary":    return executeTextSummary(arguments: arguments)
        case "number_base":     return executeNumberBase(arguments: arguments)
        case "color_convert":   return executeColorConvert(arguments: arguments)
        case "sort_text":       return executeSortText(arguments: arguments)
        case "find_replace":    return executeFindReplace(arguments: arguments)
        case "case_convert":    return executeCaseConvert(arguments: arguments)
        case "password_generate": return executePasswordGenerate(arguments: arguments)
        case "roman":           return executeRoman(arguments: arguments)
        case "unit_convert":    return executeUnitConvert(arguments: arguments)
        default:
            return "未知工具: \(toolName)"
        }
    }

    // MARK: - 工具实现

    private static func executeCalculator(arguments: [String: Any]) -> String {
        guard let expression = arguments["expression"] as? String else {
            return "错误: 缺少 expression 参数"
        }
        guard let value = evaluateMath(expression) else {
            return "错误: 无法解析表达式「\(expression)」，请检查运算符与括号是否完整"
        }
        // 整数结果不显示小数
        let text: String
        if value == value.rounded() && Swift.abs(value) < 1e15 {
            text = String(Int64(value))
        } else {
            text = String(format: "%.10g", value)
        }
        return "\(expression) = \(text)"
    }

    private static func executeCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return "当前时间: \(formatter.string(from: Date()))"
    }

    private static func executeRandomNumber(arguments: [String: Any]) -> String {
        let minV = (arguments["min"] as? NSNumber)?.intValue ?? 1
        let maxV = (arguments["max"] as? NSNumber)?.intValue ?? 100
        guard minV <= maxV else { return "错误: min 应不大于 max" }
        return "随机数: \(Int.random(in: minV...maxV))（范围 \(minV)~\(maxV)）"
    }

    private static func executeWordCount(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else {
            return "错误: 缺少 text 参数"
        }
        let charCount = text.count
        let wordCount = text.split(separator: /\s+/).count
        let lineCount = text.components(separatedBy: .newlines).count
        return "字符数: \(charCount), 单词数: \(wordCount), 行数: \(lineCount)"
    }

    private static func executeTextTransform(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String,
              let transform = arguments["transform"] as? String else {
            return "错误: 缺少参数"
        }
        switch transform {
        case "uppercase":
            return text.uppercased()
        case "lowercase":
            return text.lowercased()
        case "reverse":
            return String(text.reversed())
        case "base64_encode":
            return Data(text.utf8).base64EncodedString()
        case "base64_decode":
            guard let data = Data(base64Encoded: text) else { return "Base64解码失败" }
            return String(data: data, encoding: .utf8) ?? "解码结果非有效UTF-8文本"
        default:
            return "未知转换类型: \(transform)"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        return f
    }()

    private static func executeDateAdd(arguments: [String: Any]) -> String {
        let dateStr = arguments["date"] as? String ?? ""
        let days = (arguments["days"] as? NSNumber)?.intValue ?? 0
        let base = dateStr.isEmpty ? Date() : (dateFormatter.date(from: dateStr) ?? Date())
        guard let result = Calendar.current.date(byAdding: .day, value: days, to: base) else {
            return "日期计算失败"
        }
        return "\(dateFormatter.string(from: base)) + \(days) 天 = \(dateFormatter.string(from: result))"
    }

    private static func executeDateDiff(arguments: [String: Any]) -> String {
        guard let d1 = arguments["date1"] as? String,
              let d2 = arguments["date2"] as? String,
              let a = dateFormatter.date(from: d1),
              let b = dateFormatter.date(from: d2) else {
            return "错误: 需要有效的 date1 和 date2（格式 yyyy-MM-dd）"
        }
        let days = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        return "\(d1) 到 \(d2) 相差 \(Swift.abs(days)) 天"
    }

    private static func executeHashText(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else { return "错误: 缺少 text 参数" }
        let algorithm = (arguments["algorithm"] as? String)?.lowercased() ?? "sha256"
        let data = Data(text.utf8)
        let hex: String
        switch algorithm {
        case "md5":
            hex = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha1":
            hex = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha256":
            hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default:
            return "未知算法: \(algorithm)（可选 md5/sha1/sha256）"
        }
        return "\(algorithm) = \(hex)"
    }

    private static func executeJsonFormat(arguments: [String: Any]) -> String {
        guard let json = arguments["json"] as? String else { return "错误: 缺少 json 参数" }
        let pretty = (arguments["pretty"] as? Bool) ?? true
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return "错误: JSON 解析失败"
        }
        let options: JSONSerialization.WritingOptions =
            pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: options),
              let text = String(data: out, encoding: .utf8) else {
            return "错误: JSON 序列化失败"
        }
        return text
    }

    private static func executeUrlCodec(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else { return "错误: 缺少 text 参数" }
        let mode = arguments["mode"] as? String ?? "encode"
        if mode == "decode" {
            return text.removingPercentEncoding ?? "解码失败"
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private static let notesDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("agent_notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func executeNote(arguments: [String: Any]) -> String {
        let op = arguments["op"] as? String ?? "list"
        let rawName = (arguments["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = rawName.replacingOccurrences(of: "/", with: "-")

        switch op {
        case "save":
            guard !name.isEmpty else { return "错误: 保存笔记需要 name 参数" }
            let content = arguments["content"] as? String ?? ""
            let url = notesDirectory.appendingPathComponent(name + ".txt")
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                return "已保存笔记「\(rawName)」（\(content.count) 字）"
            } catch {
                return "保存失败: \(error.localizedDescription)"
            }
        case "read":
            guard !name.isEmpty else { return "错误: 读取笔记需要 name 参数" }
            let url = notesDirectory.appendingPathComponent(name + ".txt")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "未找到笔记「\(rawName)」"
            }
            return "「\(rawName)」: \(text)"
        case "delete":
            guard !name.isEmpty else { return "错误: 删除笔记需要 name 参数" }
            let url = notesDirectory.appendingPathComponent(name + ".txt")
            do {
                try FileManager.default.removeItem(at: url)
                return "已删除笔记「\(rawName)」"
            } catch {
                return "删除失败或不存在: \(error.localizedDescription)"
            }
        default: // list
            let files = (try? FileManager.default.contentsOfDirectory(atPath: notesDirectory.path)) ?? []
            let names = files.filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }
            return names.isEmpty ? "暂无笔记" : "现有笔记: \(names.joined(separator: ", "))"
        }
    }

    private static func executeClipboard(arguments: [String: Any]) -> String {
        let op = arguments["op"] as? String ?? "get"
        #if canImport(UIKit)
        if op == "set" {
            guard let text = arguments["text"] as? String else { return "错误: 缺少 text 参数" }
            UIPasteboard.general.string = text
            return "已写入剪贴板（\(text.count) 字）"
        }
        let current = UIPasteboard.general.string
        if let current, !current.isEmpty {
            return "剪贴板内容: \(current.prefix(2000))"
        }
        return "剪贴板为空"
        #else
        return "剪贴板在当前平台不可用"
        #endif
    }

    private static func executeWebSearch(arguments: [String: Any]) async -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return "错误: 缺少 query 参数"
        }
        // 优先 SearXNG（自托管搜索服务，可在设置中配置），失败自动回退维基百科
        return await SearchService.search(query: query, settings: SettingsStorage.shared.settings)
    }

    // MARK: - 安全数学表达式求值（Shunting-yard + RPN，纯 Swift 无崩溃风险）

    private enum MathToken: Equatable {
        case number(Double)
        case op(String)        // + - * / % ^、一元 u+/u-、函数名
        case constant(String)  // pi / e
        case lparen
        case rparen
        case comma
    }

    private static let binaryOps = ["+", "-", "*", "/", "%", "^", "min", "max", "pow"]
    private static let unaryOps = ["u+", "u-", "sqrt", "abs", "round", "floor", "ceil",
                                   "sin", "cos", "tan", "asin", "acos", "atan",
                                   "log", "ln", "log10", "exp"]

    private static func tokenizeMath(_ input: String) -> [MathToken]? {
        var tokens: [MathToken] = []
        let chars = Array(input)
        var idx = 0
        let count = chars.count
        var expectOperand = true

        while idx < count {
            let c = chars[idx]
            if c.isWhitespace { idx += 1; continue }
            if c.isNumber || c == "." {
                var num = ""
                while idx < count, chars[idx].isNumber || chars[idx] == "." {
                    num.append(chars[idx])
                    idx += 1
                }
                // 科学计数法 1e3 / 2.5e-2
                if idx + 1 < count, chars[idx] == "e" || chars[idx] == "E" {
                    let next = chars[idx + 1]
                    if next.isNumber || next == "+" || next == "-" {
                        num.append("e")
                        idx += 1
                        if chars[idx] == "+" || chars[idx] == "-" {
                            num.append(chars[idx])
                            idx += 1
                        }
                        while idx < count, chars[idx].isNumber {
                            num.append(chars[idx])
                            idx += 1
                        }
                    }
                }
                guard let v = Double(num) else { return nil }
                tokens.append(.number(v))
                expectOperand = false
                continue
            }
            if c.isLetter {
                var ident = ""
                while idx < count, chars[idx].isLetter {
                    ident.append(chars[idx])
                    idx += 1
                }
                let lower = ident.lowercased()
                if lower == "pi" || lower == "π" {
                    tokens.append(.constant("pi"))
                    expectOperand = false
                } else if lower == "e" {
                    tokens.append(.constant("e"))
                    expectOperand = false
                } else if isFunction(lower) {
                    tokens.append(.op(lower))
                    expectOperand = true
                } else {
                    return nil
                }
                continue
            }
            switch c {
            case "+", "-", "*", "/", "%", "^":
                if (c == "+" || c == "-") && expectOperand {
                    tokens.append(.op(c == "-" ? "u-" : "u+"))
                } else {
                    tokens.append(.op(String(c)))
                }
                expectOperand = true
                idx += 1
            case "(", "（":
                tokens.append(.lparen)
                expectOperand = true
                idx += 1
            case ")", "）":
                tokens.append(.rparen)
                expectOperand = false
                idx += 1
            case ",", "，":
                tokens.append(.comma)
                expectOperand = true
                idx += 1
            default:
                return nil
            }
        }
        return tokens
    }

    private static func isFunction(_ name: String) -> Bool {
        unaryOps.contains(name) || binaryOps.contains(name)
    }

    private static func precedence(_ op: String) -> Int {
        switch op {
        case "+", "-": return 1
        case "*", "/", "%": return 2
        case "^": return 3
        default: return 4 // 一元运算符与函数
        }
    }

    private static func evaluateMath(_ input: String) -> Double? {
        let cleaned = input
            .lowercased()
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "π", with: "pi")
        guard let tokens = tokenizeMath(cleaned), !tokens.isEmpty else { return nil }

        // Shunting-yard → RPN
        var output: [MathToken] = []
        var stack: [MathToken] = []

        for token in tokens {
            switch token {
            case .number, .constant:
                output.append(token)
            case .op(let name):
                let prec = precedence(name)
                while let top = stack.last, case .op(let topName) = top {
                    let topPrec = precedence(topName)
                    let rightAssoc = name == "^"
                    if topPrec > prec || (topPrec == prec && !rightAssoc && topName != "^") {
                        output.append(stack.removeLast())
                    } else {
                        break
                    }
                }
                stack.append(token)
            case .lparen:
                stack.append(token)
            case .comma:
                while let top = stack.last, top != .lparen {
                    output.append(stack.removeLast())
                }
            case .rparen:
                var found = false
                while let top = stack.last {
                    if top == .lparen {
                        stack.removeLast()
                        found = true
                        break
                    }
                    output.append(stack.removeLast())
                }
                if !found { return nil } // 括号不匹配
                if case .op(let fn)? = stack.last, isFunction(fn) {
                    output.append(stack.removeLast())
                }
            }
        }
        while let top = stack.popLast() {
            if top == .lparen { return nil } // 括号不匹配
            output.append(top)
        }

        // RPN 求值
        var values: [Double] = []
        for token in output {
            switch token {
            case .number(let v):
                values.append(v)
            case .constant(let name):
                values.append(name == "pi" ? .pi : M_E)
            case .op(let name):
                let n = binaryOps.contains(name) ? 2 : 1
                guard values.count >= n else { return nil }
                let args = Array(values.suffix(n))
                values.removeLast(n)
                let a = args[0]
                let b = n == 2 ? args[1] : 0
                let result: Double?
                switch name {
                case "+": result = a + b
                case "-": result = a - b
                case "u+": result = a
                case "u-": result = -a
                case "*": result = a * b
                case "/": result = b == 0 ? nil : a / b
                case "%": result = b == 0 ? nil : a.truncatingRemainder(dividingBy: b)
                case "^": result = pow(a, b)
                case "sqrt": result = a >= 0 ? sqrt(a) : nil
                case "abs": result = Swift.abs(a)
                case "round": result = a.rounded()
                case "floor": result = floor(a)
                case "ceil": result = ceil(a)
                case "sin": result = sin(a)
                case "cos": result = cos(a)
                case "tan": result = cos(a) == 0 ? nil : tan(a)
                case "asin": result = (-1...1).contains(a) ? asin(a) : nil
                case "acos": result = (-1...1).contains(a) ? acos(a) : nil
                case "atan": result = atan(a)
                case "log", "log10": result = a > 0 ? log10(a) : nil
                case "ln": result = a > 0 ? log(a) : nil
                case "exp": result = exp(a)
                case "min": result = min(a, b)
                case "max": result = max(a, b)
                case "pow": result = pow(a, b)
                default: result = nil
                }
                guard let result else { return nil }
                values.append(result)
            case .lparen, .rparen, .comma:
                return nil
            }
        }
        return values.count == 1 ? values[0] : nil
    }

    // MARK: - 正则表达式提取工具

    private static func executeRegexExtract(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else {
            return "错误: 缺少 text 参数"
        }
        guard let pattern = arguments["pattern"] as? String else {
            return "错误: 缺少 pattern 参数"
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return "错误: 无效的正则表达式模式「\(pattern)」"
        }
        
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        
        if matches.isEmpty {
            return "未找到匹配「\(pattern)」的内容"
        }
        
        var results: [String] = []
        for (i, match) in matches.prefix(20).enumerated() {
            // 完整匹配
            let fullMatch = nsText.substring(with: match.range)
            
            // 捕获组（如果有）
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for j in 1..<match.numberOfRanges {
                    let groupRange = match.range(at: j)
                    if groupRange.location != NSNotFound {
                        groups.append(nsText.substring(with: groupRange))
                    }
                }
            }
            
            var line = "\(i + 1). \(fullMatch)"
            if !groups.isEmpty {
                line += " [捕获组: \(groups.joined(separator: ", "))]"
            }
            results.append(line)
        }
        
        return "找到 \(matches.count) 个匹配:\n\(results.joined(separator: "\n"))"
    }

    // MARK: - 文本摘要工具

    private static func executeTextSummary(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else {
            return "错误: 缺少 text 参数"
        }
        
        let maxLength = (arguments["max_length"] as? NSNumber)?.intValue ?? 200
        
        if text.count <= maxLength {
            return "原文较短，无需摘要:\n\(text)"
        }
        
        // 智能摘要：提取关键句子
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if sentences.isEmpty {
            return "无法提取有效内容"
        }
        
        // 简单的关键词提取和句子重要性评分
        var scoredSentences: [(sentence: String, score: Double)] = []
        
        // 常见关键词（中文）
        let keywords = ["重要", "关键", "核心", "主要", "首先", "其次", "最后", "总结", "结论", 
                       "important", "key", "main", "first", "conclusion", "summary"]
        
        for sentence in sentences {
            var score = 0.0
            
            // 位置得分：开头和结尾的句子更重要
            if let index = sentences.firstIndex(of: sentence) {
                if index < 3 { score += 2.0 }
                if index >= sentences.count - 2 { score += 1.5 }
            }
            
            // 长度得分：中等长度的句子更可能是关键句
            let length = sentence.count
            if length > 10 && length < 100 {
                score += 1.0
            }
            
            // 关键词得分
            let lowerSentence = sentence.lowercased()
            for keyword in keywords {
                if lowerSentence.contains(keyword) {
                    score += 1.5
                }
            }
            
            scoredSentences.append((sentence, score))
        }
        
        // 按得分排序，取前几句
        let topSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map(\.sentence)
        
        var summary = topSentences.joined(separator: "。")
        
        // 截断到指定长度
        if summary.count > maxLength {
            summary = String(summary.prefix(maxLength - 3)) + "..."
        }
        
        return "摘要:\n\(summary)"
    }

    // MARK: - 进制转换

    private static func radixFor(name: String) -> Int? {
        switch name {
        case "decimal": return 10
        case "binary": return 2
        case "octal": return 8
        case "hex", "hexadecimal": return 16
        default: return nil
        }
    }

    private static func executeNumberBase(arguments: [String: Any]) -> String {
        guard let value = (arguments["value"] as? String)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty else { return "错误: 缺少 value 参数" }
        let from = (arguments["from"] as? String)?.lowercased() ?? "decimal"
        let to = (arguments["to"] as? String)?.lowercased() ?? "hex"
        guard let fr = radixFor(name: from), let tr = radixFor(name: to) else {
            return "错误: from/to 必须是 decimal/binary/octal/hex 之一"
        }
        guard let num = Int(value, radix: fr) else {
            return "错误: 无法将「\(value)」按 \(from) 进制解析"
        }
        let out: String = (tr == 10) ? String(num) : String(num, radix: tr)
        return "\(value) (\(from)) = \(out) (\(to))"
    }

    // MARK: - 颜色转换

    private static func executeColorConvert(arguments: [String: Any]) -> String {
        guard let mode = arguments["mode"] as? String else { return "错误: 缺少 mode 参数(to_hex/to_rgb)" }
        guard let value = (arguments["value"] as? String)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty else { return "错误: 缺少 value 参数" }
        if mode == "to_hex" {
            let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3,
                  let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]),
                  (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else {
                return "错误: to_hex 需要 RGB 形如 255,0,0（各分量 0~255）"
            }
            return String(format: "#%02X%02X%02X", r, g, b)
        } else if mode == "to_rgb" {
            var h = value
            if h.hasPrefix("#") { h.removeFirst() }
            guard h.count == 6, let intVal = Int(h, radix: 16) else {
                return "错误: to_rgb 需要十六进制形如 #ff0000"
            }
            let r = (intVal >> 16) & 0xFF
            let g = (intVal >> 8) & 0xFF
            let b = intVal & 0xFF
            return "\(r), \(g), \(b)"
        }
        return "错误: mode 必须是 to_hex 或 to_rgb"
    }

    // MARK: - 文本排序

    private static func executeSortText(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else { return "错误: 缺少 text 参数" }
        let reverse = (arguments["reverse"] as? Bool) ?? false
        let ignoreCase = (arguments["ignore_case"] as? Bool) ?? false
        let dedup = (arguments["dedup"] as? Bool) ?? false
        var lines = text.components(separatedBy: .newlines)
        lines.sort {
            ignoreCase ? ($0.localizedCaseInsensitiveCompare($1) == .orderedAscending) : ($0 < $1)
        }
        if reverse { lines.reverse() }
        if dedup {
            var out: [String] = []
            for l in lines where out.last != l { out.append(l) }
            lines = out
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 查找替换

    private static func executeFindReplace(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String else { return "错误: 缺少 text 参数" }
        guard let find = arguments["find"] as? String else { return "错误: 缺少 find 参数" }
        let replace = arguments["replace"] as? String ?? ""
        let regex = (arguments["regex"] as? Bool) ?? false
        let all = (arguments["all"] as? Bool) ?? true
        if regex {
            guard let re = try? NSRegularExpression(pattern: find) else {
                return "错误: 无效的正则「\(find)」"
            }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if all {
                return re.stringByReplacingMatches(in: text, range: range, withTemplate: replace)
            } else if let match = re.firstMatch(in: text, range: range) {
                let result = re.replacementString(for: match, in: text, offset: 0, template: replace)
                return nsText.replacingCharacters(in: match.range, with: result)
            }
            return text
        } else if all {
            return text.replacingOccurrences(of: find, with: replace)
        } else if let r = text.range(of: find) {
            return text.replacingCharacters(in: r, with: replace)
        }
        return text
    }

    // MARK: - 命名风格转换

    private static func splitIdentifier(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(s)
        for i in 0..<chars.count {
            let c = chars[i]
            if c.isLetter || c.isNumber {
                if c.isUppercase, !current.isEmpty, let prev = current.last, !prev.isUppercase {
                    result.append(current)
                    current = ""
                }
                current.append(c)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.isEmpty }
    }

    private static func executeCaseConvert(arguments: [String: Any]) -> String {
        guard let text = arguments["text"] as? String, !text.isEmpty else { return "错误: 缺少 text 参数" }
        guard let style = arguments["style"] as? String else { return "错误: 缺少 style 参数" }
        let words = splitIdentifier(text)
        switch style {
        case "snake":  return words.map { $0.lowercased() }.joined(separator: "_")
        case "kebab":  return words.map { $0.lowercased() }.joined(separator: "-")
        case "camel":  return words.enumerated().map { i, w in i == 0 ? w.lowercased() : w.capitalized }.joined()
        case "pascal": return words.map { $0.capitalized }.joined()
        default: return "错误: style 必须是 snake/camel/pascal/kebab"
        }
    }

    // MARK: - 密码生成

    private static func executePasswordGenerate(arguments: [String: Any]) -> String {
        let length = min(max((arguments["length"] as? NSNumber)?.intValue ?? 16, 4), 128)
        let digits = (arguments["digits"] as? Bool) ?? true
        let symbols = (arguments["symbols"] as? Bool) ?? true
        let uppercase = (arguments["uppercase"] as? Bool) ?? true
        let lowercase = (arguments["lowercase"] as? Bool) ?? true
        let lowers = "abcdefghijklmnopqrstuvwxyz"
        let uppers = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let digs = "0123456789"
        let syms = "!@#$%^&*()-_=+[]{};:,.<>?"
        var pool = ""
        if lowercase { pool += lowers }
        if uppercase { pool += uppers }
        if digits { pool += digs }
        if symbols { pool += syms }
        guard !pool.isEmpty else { return "错误: 至少启用一种字符类别" }
        var chars = (0..<length).map { _ in pool.randomElement()! }
        if lowercase { chars[0] = lowers.randomElement()! }
        if uppercase, chars.count > 1 { chars[1] = uppers.randomElement()! }
        if digits, chars.count > 2 { chars[2] = digs.randomElement()! }
        if symbols, chars.count > 3 { chars[3] = syms.randomElement()! }
        return "生成密码（长度 \(length)）: \(String(chars))"
    }

    // MARK: - 罗马数字

    private static let romanMap: [(String, Int)] = [
        ("M", 1000), ("CM", 900), ("D", 500), ("CD", 400), ("C", 100),
        ("XC", 90), ("L", 50), ("XL", 40), ("X", 10), ("IX", 9),
        ("V", 5), ("IV", 4), ("I", 1)
    ]

    private static func intToRoman(_ n: Int) -> String {
        var n = n
        var s = ""
        for (sym, val) in romanMap {
            while n >= val { s += sym; n -= val }
        }
        return s
    }

    private static func romanToInt(_ s: String) -> Int? {
        var total = 0
        var i = 0
        let chars = Array(s)
        while i < chars.count {
            let two = (i + 1 < chars.count) ? String(chars[i]) + String(chars[i + 1]) : nil
            if let two, let val = romanMap.first(where: { $0.0 == two })?.1 {
                total += val
                i += 2
                continue
            }
            guard let val = romanMap.first(where: { $0.0 == String(chars[i]) })?.1 else { return nil }
            total += val
            i += 1
        }
        return total
    }

    private static func executeRoman(arguments: [String: Any]) -> String {
        guard let value = (arguments["value"] as? String)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty else { return "错误: 缺少 value 参数" }
        if let num = Int(value) {
            guard (1...3999).contains(num) else { return "错误: 阿拉伯数字需在 1~3999" }
            return "\(num) = \(intToRoman(num))"
        }
        let upper = value.uppercased()
        guard let num = romanToInt(upper) else { return "错误: 无法解析罗马数字「\(value)」" }
        return "\(value) = \(num)"
    }

    // MARK: - 单位换算

    private static let lengthToMeter = ["m": 1.0, "km": 1000.0, "cm": 0.01, "mm": 0.001,
                                        "mile": 1609.344, "yard": 0.9144, "foot": 0.3048, "inch": 0.0254]
    private static let weightToKg = ["kg": 1.0, "g": 0.001, "mg": 0.000001, "t": 1000.0, "ton": 1000.0,
                                    "lb": 0.45359237, "pound": 0.45359237, "oz": 0.028349523125, "ounce": 0.028349523125]
    private static let volumeToLiter = ["l": 1.0, "liter": 1.0, "ml": 0.001, "m3": 1000.0,
                                       "gallon": 3.785411784, "cup": 0.2365882365]
    private static let dataToByte = ["b": 1.0, "byte": 1.0, "kb": 1024.0, "mb": 1048576.0,
                                    "gb": 1073741824.0, "tb": 1099511627776.0]

    private static func unitCategory(_ u: String) -> String? {
        if lengthToMeter[u] != nil { return "length" }
        if weightToKg[u] != nil { return "weight" }
        if volumeToLiter[u] != nil { return "volume" }
        if dataToByte[u] != nil { return "data" }
        if ["c", "°c", "f", "°f", "k"].contains(u) { return "temp" }
        return nil
    }

    private static func unitToBase(_ u: String, value: Double) -> Double? {
        if let f = lengthToMeter[u] { return value * f }
        if let f = weightToKg[u] { return value * f }
        if let f = volumeToLiter[u] { return value * f }
        if let f = dataToByte[u] { return value * f }
        if u == "c" || u == "°c" { return value }
        if u == "f" || u == "°f" { return (value - 32) / 1.8 }
        if u == "k" { return value - 273.15 }
        return nil
    }

    private static func baseToUnit(_ u: String, base: Double) -> Double? {
        if let f = lengthToMeter[u] { return base / f }
        if let f = weightToKg[u] { return base / f }
        if let f = volumeToLiter[u] { return base / f }
        if let f = dataToByte[u] { return base / f }
        if u == "c" || u == "°c" { return base }
        if u == "f" || u == "°f" { return base * 1.8 + 32 }
        if u == "k" { return base + 273.15 }
        return nil
    }

    private static func executeUnitConvert(arguments: [String: Any]) -> String {
        guard let valueNum = (arguments["value"] as? NSNumber)?.doubleValue else {
            return "错误: 缺少或无效 value 参数"
        }
        guard let from = (arguments["from"] as? String)?.lowercased(), !from.isEmpty else {
            return "错误: 缺少 from 参数"
        }
        guard let to = (arguments["to"] as? String)?.lowercased(), !to.isEmpty else {
            return "错误: 缺少 to 参数"
        }
        guard let catFrom = unitCategory(from), let catTo = unitCategory(to), catFrom == catTo else {
            return "错误: from 与 to 单位类别不一致或未知"
        }
        guard let base = unitToBase(from, value: valueNum) else { return "错误: 未知单位「\(from)」" }
        guard let out = baseToUnit(to, base: base) else { return "错误: 未知单位「\(to)」" }
        let text = (out == out.rounded()) ? String(Int64(out)) : String(format: "%.6g", out)
        return "\(valueNum) \(from) = \(text) \(to)"
    }
}
