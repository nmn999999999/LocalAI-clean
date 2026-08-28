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
}
