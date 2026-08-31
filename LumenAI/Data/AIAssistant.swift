import Foundation

/// 自定义 AI 助手（Custom Assistants）
struct AIAssistant: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    /// 头像 emoji
    var emoji: String
    var systemPrompt: String
    /// 绑定的 Provider（nil = 跟随当前对话选择的 Provider）
    var providerID: UUID?
    /// 绑定的模型名（nil = 跟随当前选择）
    var model: String?
    /// 可覆盖的采样温度（nil = 用全局设置）
    var temperature: Double?
    var enabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "默认助手",
        emoji: String = "🤖",
        systemPrompt: String = "你是一个有帮助的AI助手。请用中文回答。",
        providerID: UUID? = nil,
        model: String? = nil,
        temperature: Double? = nil,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.model = model
        self.temperature = temperature
        self.enabled = enabled
        self.createdAt = createdAt
    }

    static let `default` = AIAssistant()
}
