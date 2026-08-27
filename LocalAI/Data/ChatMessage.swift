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
    var images: [ImageData]
    var toolCalls: [ToolCall]

    struct ImageData: Codable, Sendable {
        let data: Data
        let mimeType: String

        var cgImage: CGImage? {
            guard let uiImage = UIImage(data: data) else { return nil }
            return uiImage.cgImage
        }
    }

    struct ToolCall: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        let arguments: String
        var result: String?
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        images: [ImageData] = [],
        toolCalls: [ToolCall] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.images = images
        self.toolCalls = toolCalls
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
