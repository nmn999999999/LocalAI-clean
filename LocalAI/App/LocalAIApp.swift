import SwiftUI

@main
struct LocalAIApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var llmService = LLMService()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var agentService = AgentService()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(modelManager)
                .environmentObject(llmService)
                .environmentObject(chatStore)
                .environmentObject(agentService)
                .task { await autoLoadLastModel() }
        }
    }

    /// 启动时自动加载上一次使用的模型（模型仍在本地文件系统中）。
    private func autoLoadLastModel() async {
        guard case .idle = llmService.state,
              let stored = modelManager.lastUsedModel else { return }
        let url = modelManager.localFileURL(for: stored)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        await llmService.load(url: url, displayName: stored.name)
    }
}
