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

struct Conversation: Identifiable, Codable {
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
