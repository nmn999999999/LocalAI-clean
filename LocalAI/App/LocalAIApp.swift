import SwiftUI
import Combine

@main
struct LocalAIApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var llmService = LLMService()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var agentService = AgentService()
    /// 监听「默认模型下载完成」信号的订阅（下载是异步的，完成后据此自动加载）。
    @State private var defaultDownloadCancellable: AnyCancellable?

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

    /// 启动时自动加载上一次使用的模型；若本地没有任何模型，则优先下载内置默认模型
    ///（Apple OpenELM）并在下载完成后自动加载，做到「进入 App 即用」。
    private func autoLoadLastModel() async {
        // 1) 上次用过的模型仍在本地 → 直接加载
        if case .idle = llmService.state,
           let stored = modelManager.lastUsedModel {
            let url = modelManager.localFileURL(for: stored)
            if FileManager.default.fileExists(atPath: url.path) {
                await llmService.load(url: url, displayName: stored.name)
                return
            }
        }
        // 2) 本地没有任何模型 → 优先下载默认模型（Apple OpenELM），下载完成后自动加载
        guard modelManager.downloadedModels.isEmpty else { return }
        let def = AIModelInfo.defaultModel
        modelManager.download(def)
        defaultDownloadCancellable = modelManager.$lastCompletedDownloadID
            .compactMap { $0 }
            .sink { [modelManager, llmService] id in
                guard id == def.id else { return }
                guard llmService.loadedModelName == nil else { return }
                if let stored = ModelManager.shared.downloadedModels.first(where: { $0.id == id }),
                   FileManager.default.fileExists(atPath: ModelManager.shared.localFileURL(for: stored).path) {
                    Task { await llmService.load(url: ModelManager.shared.localFileURL(for: stored), displayName: stored.name) }
                }
            }
    }
}
