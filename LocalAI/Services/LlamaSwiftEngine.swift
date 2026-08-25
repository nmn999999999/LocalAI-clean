import Foundation
import CoreGraphics

// 基于 https://github.com/eastriverlee/LLM.swift (v3.x) 的 GGUF 推理引擎。
// 在 Xcode 中添加 SPM 依赖后（见 README），此文件自动启用；
// 未添加依赖时整段代码被编译排除，App 使用 EchoEngine 演示模式。

#if canImport(LLM)
import LLM

final class LlamaSwiftEngine: LLMEngine, @unchecked Sendable {

    let modelURL: URL
    private var bot: LLM?
    private let lock = NSLock()

    /// v3 API：同步可失败初始化器，路径为 String；首次调用时加载权重。
    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    deinit {
        bot = nil
    }

    private func acquireBot(settings: ModelSettings) -> LLM? {
        lock.lock()
        defer { lock.unlock() }
        if let bot { return bot }
        guard let instance = LLM(
            from: modelURL.path,
            topK: Int32(settings.topK),
            topP: Float(settings.topP),
            temp: Float(settings.temperature),
            maxTokenCount: Int32(settings.maxTokens)
        ) else {
            return nil
        }
        bot = instance
        return instance
    }

    func stream(
        messages: [EngineMessage],
        settings: ModelSettings,
        images: [CGImage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let bot = self.acquireBot(settings: settings) else {
                        throw LLMError.loadFailed(
                            "模型加载失败：内存不足或 GGUF 文件损坏"
                        )
                    }

                    // 系统提示词（v3 为 Optional）
                    if let sys = messages.first(where: { $0.role == .system })?.content {
                        bot.systemPrompt = sys
                    } else {
                        bot.systemPrompt = nil
                    }

                    // 组装历史：Chat = (role: Role, content: String)
                    // Role 仅含 .user / .bot
                    let history: [Chat] = messages.dropLast().compactMap { m in
                        switch m.role {
                        case .user:
                            return (role: .user, content: m.content)
                        case .assistant:
                            return (role: .bot, content: m.content)
                        case .tool:
                            return (role: .user, content: "[工具结果] \(m.content)")
                        case .system:
                            return nil
                        }
                    }

                    guard let lastUser = messages.last(where: { $0.role == .user })?.content else {
                        throw LLMError.generationFailed("对话中没有用户消息")
                    }

                    // 使用内嵌聊天模板渲染完整 prompt（GGUF 元数据自动识别）
                    let prompt = bot.preprocess(lastUser, history, .none)

                    let answer = await bot.getCompletion(from: prompt)
                    let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)

                    var index = text.startIndex
                    while index < text.endIndex {
                        if Task.isCancelled { break }
                        let end = text.index(
                            index,
                            offsetBy: 6,
                            limitedBy: text.endIndex
                        ) ?? text.endIndex
                        continuation.yield(String(text[index..<end]))
                        index = end
                        try? await Task.sleep(nanoseconds: 12_000_000)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
#endif
