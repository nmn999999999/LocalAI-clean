import SwiftUI
import Combine

@main
struct LocalAIApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var llmService = LLMService()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var agentService = AgentService()
    @StateObject private var theme = ThemeObserver()
    /// 数据安全：切后台/退出时立即落盘（见 body 里的 onChange）
    @Environment(\.scenePhase) private var scenePhase
    /// 监听「默认模型下载完成」信号的订阅（下载是异步的，完成后据此自动加载）。
    @State private var defaultDownloadCancellable: AnyCancellable?

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(modelManager)
                .environmentObject(llmService)
                .environmentObject(chatStore)
                .environmentObject(agentService)
                .environmentObject(theme)
                .tint(theme.current.accentColor)
                .preferredColorScheme(theme.current.preferredColorScheme)
                .task {
                    await autoLoadLastModel()
                    // 滚动更新：启动静默检查 GitHub Release（按设置开关 + 间隔节流）
                    if SettingsStorage.shared.settings.autoCheckUpdate {
                        await UpdateCheckerService.shared.checkIfNeeded()
                    }
                    // 插件：启动静默检查模块更新（1 天节流，服务页显示可更新角标）
                    await PluginManager.shared.checkForUpdatesIfNeeded()
                }
                // 数据安全：切后台/退出时立即落盘对话，防止 500ms 防抖窗口内强杀 App 丢消息
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        chatStore.flushSave()
                    }
                }
        }
    }

    /// ThemeObserver 是 AppStorage 包装,主题变更时通知整个视图树重新 .tint(...)
    final class ThemeObserver: ObservableObject {
        @AppStorage("appTheme") var raw: String = AppTheme.system.rawValue
        var current: AppTheme {
            get { AppTheme(rawValue: raw) ?? .system }
            set { raw = newValue.rawValue; objectWillChange.send() }
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
