import SwiftUI

// iOS 26+ 使用 Xcode 26 SDK 构建时，TabView 的底部标签栏
// 自动呈现悬浮式 Liquid Glass 材质，滚动时会自动最小化。
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
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    MainTabView()
        .environmentObject(ModelManager.shared)
        .environmentObject(LLMService())
        .environmentObject(ChatStore())
        .environmentObject(AgentService())
}
