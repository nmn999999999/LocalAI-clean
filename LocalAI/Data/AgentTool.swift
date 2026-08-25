import Foundation

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
            description: "计算数学表达式，返回计算结果",
            parameters: [
                "expression": .init(type: "string", description: "数学表达式，如 2+3*4", enumValues: nil)
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
            id: "word_count",
            name: "word_count",
            description: "统计文本的字数和字符数",
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
    ]

    static func execute(toolName: String, arguments: [String: Any]) -> String {
        switch toolName {
        case "calculator":
            return executeCalculator(arguments: arguments)
        case "current_time":
            return executeCurrentTime()
        case "generate_uuid":
            return UUID().uuidString
        case "word_count":
            return executeWordCount(arguments: arguments)
        case "text_transform":
            return executeTextTransform(arguments: arguments)
        default:
            return "未知工具: \(toolName)"
        }
    }

    private static func executeCalculator(arguments: [String: Any]) -> String {
        guard let expression = arguments["expression"] as? String else {
            return "错误: 缺少 expression 参数"
        }
        let result = NSExpression(format: expression).expressionValue(with: nil, context: nil)
        return "\(expression) = \(result ?? "错误")"
    }

    private static func executeCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return "当前时间: \(formatter.string(from: Date()))"
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
}
