import SwiftUI

// iOS 27+ 使用 Xcode 27 SDK 构建，TabView 自动呈现液态玻璃效果
// iOS 17-26 使用传统 TabView
struct MainTabView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right.fill")
                }

            ModelListView()
                .tabItem {
                    Label("模型", systemImage: "cpu.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
#if swift(>=27.0)
        .tabBarMinimizeBehavior(.onScrollDown)
#endif
    }
}

#Preview {
    MainTabView()
        .environmentObject(ModelManager.shared)
        .environmentObject(LLMService())
        .environmentObject(ChatStore())
        .environmentObject(AgentService())
}
