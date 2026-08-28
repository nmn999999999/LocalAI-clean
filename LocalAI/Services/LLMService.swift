import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 错误定义

enum LLMError: LocalizedError, Sendable {
    case modelNotLoaded
    case generationFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "模型未加载，请先在「模型」页下载并加载一个 GGUF 模型"
        case .generationFailed(let msg):
            return "生成失败: \(msg)"
        case .loadFailed(let msg):
            return "模型加载失败: \(msg)"
        }
    }
}

// MARK: - 引擎协议（隔离第三方库依赖）

protocol LLMEngine: AnyObject, Sendable {
    var modelURL: URL { get }
    /// 流式生成。messages 为渲染好的对话；images 可为空（多模态时使用）。
    func stream(
        messages: [EngineMessage],
        settings: ModelSettings,
        images: [CGImage]
    ) -> AsyncThrowingStream<String, Error>
}

struct EngineMessage: Sendable {
    enum Role: String, Sendable {
        case system, user, assistant, tool
    }
    let role: Role
    let content: String
}

// MARK: - LLMService 门面

@MainActor
final class LLMService: ObservableObject {

    enum EngineState: Equatable {
        case idle
        case loading(String)
        case ready(String)
        case failed(String)
    }

    @Published private(set) var state: EngineState = .idle
    @Published private(set) var isGenerating = false
    @Published var partialOutput = ""

    private var engine: LLMEngine?
    private var generationTask: Task<Void, Never>?

    var isModelReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var loadedModelName: String? {
        if case .ready(let name) = state { return name }
        if case .loading(let name) = state { return name }
        return nil
    }

    // MARK: 加载 / 卸载

    func load(url: URL, displayName: String) async {
        unload()
        state = .loading(displayName)
        do {
            let engine = try await makeLlamaEngine(url: url)
            self.engine = engine
            state = .ready(displayName)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func unload() {
        generationTask?.cancel()
        generationTask = nil
        engine = nil
        isGenerating = false
        partialOutput = ""
        state = .idle
    }

    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }

    // MARK: 纯文本流式对话（无工具）

    func streamChat(
        history: [ChatMessage],
        settings: ModelSettings,
        images: [CGImage] = []
    ) -> AsyncThrowingStream<String, Error> {
        let engine = tryRequireEngine()
        let msgs = toEngineMessages(history, settings: settings)
        return engine.stream(messages: msgs, settings: settings, images: images)
    }

    /// 供 Agent 使用：带可选图片的单轮流式调用，聚合返回完整文本。
    func complete(
        messages: [ChatMessage],
        settings: ModelSettings,
        images: [CGImage] = []
    ) async throws -> String {
        let engine = tryRequireEngine()
        let msgs = toEngineMessages(messages, settings: settings)
        var result = ""
        for try await token in engine.stream(messages: msgs, settings: settings, images: images) {
            try Task.checkCancellation()
            result += token
        }
        return result
    }

    /// 多模态：图片 + 提问
    func describe(image: CGImage, prompt: String, settings: ModelSettings) async throws -> String {
        let user = ChatMessage(role: .user, content: prompt)
        return try await complete(messages: [user], settings: settings, images: [image])
    }

    // MARK: 私有辅助

    private func tryRequireEngine() -> LLMEngine {
        if let engine { return engine }
        return EchoEngine()
    }

    private func toEngineMessages(_ messages: [ChatMessage], settings: ModelSettings) -> [EngineMessage] {
        var result: [EngineMessage] = []
        // 若消息里已含 system（例如 Agent 注入了工具说明），保留它，不再重复添加设置里的系统提示词
        let hasSystem = messages.contains { $0.role == .system }
        if !hasSystem, !settings.systemPrompt.isEmpty {
            result.append(EngineMessage(role: .system, content: settings.systemPrompt))
        }
        for m in messages {
            switch m.role {
            case .user:
                result.append(.init(role: .user, content: m.content))
            case .assistant:
                result.append(.init(role: .assistant, content: m.content))
            case .tool:
                result.append(.init(role: .tool, content: m.content))
            case .system:
                result.append(.init(role: .system, content: m.content))
            }
        }
        return result
    }

    /// 创建 llama.cpp(GGUF) 引擎（本地推理，支持多模态）。
    /// 注意：`LlamaSwiftEngine.init` 内部是同步阻塞的 C 调用 `llama_bridge_load_model`
    /// （含 ggml/Metal 后端初始化），耗时数百毫秒。若在主线程执行会卡 UI
    /// （见 UIKit-runloop 卡顿报告）。用 detached 切到后台线程跑，
    /// 引擎创建完成后再回到调用方 actor（MainActor）写 @Published 状态。
    private func makeLlamaEngine(url: URL) async throws -> LLMEngine {
        let gpuLayers = SettingsStorage.shared.settings.gpuLayers
        return try await Task.detached(priority: .userInitiated) {
            try await LlamaSwiftEngine(modelURL: url, gpuLayers: Int32(gpuLayers))
        }.value
    }
}

// MARK: - 演示引擎（未接入真实模型时保证 App 可运行）

final class EchoEngine: LLMEngine, @unchecked Sendable {
    let modelURL = URL(fileURLWithPath: "/dev/null")

    func stream(
        messages: [EngineMessage],
        settings: ModelSettings,
        images: [CGImage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let lastUser = messages.last(where: { $0.role == .user })?.content ?? ""
                let reply = """
                ⚠️ 当前处于演示模式（未集成 LLM.swift 或模型未加载）。

                收到消息: \(lastUser.prefix(120))

                请在「模型」页下载/导入 GGUF 模型后重新加载；
                并按 README 添加 LLM.swift 依赖以启用真实推理。
                """
                for chunk in reply.split(separator: "", omittingEmptySubsequences: true) {
                    continuation.yield(String(chunk))
                    try? await Task.sleep(nanoseconds: 4_000_000)
                }
                continuation.finish()
            }
        }
    }
}
