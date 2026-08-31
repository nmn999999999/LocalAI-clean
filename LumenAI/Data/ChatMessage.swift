import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var isAgentRound: Bool
    var images: [ImageData]
    var toolCalls: [ToolCall]
    /// 生成速度提示（如 "⚡ 14.3 tok/s"）；nil 不显示。可选字段，旧存档解码兼容。
    var speedText: String?

    struct ImageData: Codable, Sendable {
        let data: Data
        let mimeType: String

        var cgImage: CGImage? {
            guard let uiImage = UIImage(data: data) else { return nil }
            return uiImage.cgImage
        }
    }

    /// opencode 风格的 ToolPart 状态机：
    /// `.pending` — 已解析工具调用、还没开始执行
    /// `.running` — 工具正在执行（长任务时显示等待 spinner）
    /// `.complete` — 执行成功（含结果字符串）
    /// `.error` — 执行失败（result 字段含错误信息）
    /// `.awaitingApproval` — 工具需要用户授权（requiresApproval=true，进入前弹窗）
    struct ToolCall: Codable, Sendable, Identifiable {
        enum Status: String, Codable, Sendable {
            case pending, running, awaitingApproval
            case complete, error
        }
        let id: String
        let name: String
        let arguments: String
        var result: String?
        var status: Status = .complete
        var title: String?
        var truncated: Bool = false

        /// Memberwise init: 给 AgentService / UI 等代码路径直接构造。
        /// status 默认 .complete（与旧行为一致，向上兼容）：
        /// 历史已保存的 toolCalls 全部走 decode(from:) → 不经此 init → 不受影响。
        init(
            id: String,
            name: String,
            arguments: String,
            result: String? = nil,
            status: Status = .complete,
            title: String? = nil,
            truncated: Bool = false
        ) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.result = result
            self.status = status
            self.title = title
            self.truncated = truncated
        }

        // 显式 Codable：旧存档没有 status/title/truncated，用 decodeIfPresent 兜底
        private enum CodingKeys: String, CodingKey {
            case id, name, arguments, result, status, title, truncated
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.name = try c.decode(String.self, forKey: .name)
            self.arguments = try c.decode(String.self, forKey: .arguments)
            self.result = try c.decodeIfPresent(String.self, forKey: .result)
            // status 在 v0.3.11 之前都是隐式 complete；解析旧存档时默认 complete
            let raw = try c.decodeIfPresent(String.self, forKey: .status) ?? "complete"
            self.status = Status(rawValue: raw) ?? .complete
            self.title = try c.decodeIfPresent(String.self, forKey: .title)
            self.truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(arguments, forKey: .arguments)
            try c.encodeIfPresent(result, forKey: .result)
            try c.encode(status.rawValue, forKey: .status)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(truncated, forKey: .truncated)
        }
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        isAgentRound: Bool = false,
        images: [ImageData] = [],
        toolCalls: [ToolCall] = [],
        speedText: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isAgentRound = isAgentRound
        self.images = images
        self.toolCalls = toolCalls
        self.speedText = speedText
    }

    // 显式实现 Codable：所有可选/后加字段用 decodeIfPresent 兼容旧存档
    // 否则编译器的自动实现对每个字段都是必填 → 旧版本（无 speedText）的
    // conversations.json 解码失败 → try? 静默吞错 → 用户对话历史整个丢失。
    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, isStreaming, isAgentRound, images, toolCalls, speedText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.role = try c.decode(MessageRole.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.isStreaming = try c.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        self.isAgentRound = try c.decodeIfPresent(Bool.self, forKey: .isAgentRound) ?? false
        self.images = try c.decodeIfPresent([ImageData].self, forKey: .images) ?? []
        self.toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls) ?? []
        self.speedText = try c.decodeIfPresent(String.self, forKey: .speedText)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(isStreaming, forKey: .isStreaming)
        try c.encode(isAgentRound, forKey: .isAgentRound)
        try c.encode(images, forKey: .images)
        try c.encode(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(speedText, forKey: .speedText)
    }
}

struct Conversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var modelName: String?

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelName = modelName
    }

    // 显式 Codable：防御旧存档字段缺失（modelName/updatedAt 都是后加的）
    private enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, modelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.messages = try c.decode([ChatMessage].self, forKey: .messages)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(messages, forKey: .messages)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(modelName, forKey: .modelName)
    }

    mutating func updateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            title = String(firstUserMessage.content.prefix(30))
        }
    }
}

// MARK: - think 块解析（DeepSeek-R1 / Qwen3 风格的 <think>…</think>）

extension ChatMessage {
    /// 思考内容（不含标签）。流式中若 `</think>` 尚未出现，未闭合部分也算作思考内容。
    var thinkContent: String? {
        let parsed = Self.parseThinkBlock(content)
        return parsed.think.isEmpty ? nil : parsed.think
    }

    /// 展示给用户的正文字（已剔除 think 块）。
    var visibleContent: String {
        Self.parseThinkBlock(content).answer
    }

    /// 是否仍处于思考阶段（存在未闭合的 think 标签）。
    var isThinking: Bool {
        let lower = content.lowercased()
        let hasOpen = lower.contains("<think>") || lower.contains("<reasoning>")
        guard hasOpen else { return false }
        let hasClose = lower.contains("</think>") || lower.contains("</reasoning>")
        return !hasClose
    }

    static func parseThinkBlock(_ content: String) -> (think: String, answer: String) {
        var think = ""
        var answer = ""
        var rest = Substring(content)

        while true {
            let open = rest.range(of: "<think>", options: [.caseInsensitive])
                ?? rest.range(of: "<reasoning>", options: [.caseInsensitive])
            guard let open else {
                answer += rest
                break
            }
            answer += rest[rest.startIndex..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            if let close = afterOpen.range(of: "</think>", options: [.caseInsensitive])
                ?? afterOpen.range(of: "</reasoning>", options: [.caseInsensitive]) {
                think += afterOpen[afterOpen.startIndex..<close.lowerBound]
                rest = afterOpen[close.upperBound...]
            } else {
                think += afterOpen
                break
            }
        }

        let ws = CharacterSet.whitespacesAndNewlines
        return (
            think.trimmingCharacters(in: ws),
            answer.trimmingCharacters(in: ws)
        )
    }
}
