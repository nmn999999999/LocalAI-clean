import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var llmService: LLMService
    @EnvironmentObject private var chatStore: ChatStore
    @ObservedObject private var storage = SettingsStorage.shared

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generationCard
                    systemPromptCard
                    searchCard
                    aboutCard
                    dangerZone
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
        }
    }

    // MARK: - 生成参数（液态玻璃卡片 + 玻璃滑块）

    private var generationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "生成参数", systemImage: "slider.horizontal.3")

                sliderRow("温度 (temperature)", value: $storage.settings.temperature, in: 0...1.5)
                sliderRow("Top-P", value: $storage.settings.topP, in: 0.1...1)
                stepperRow("Top-K", value: $storage.settings.topK, in: 1...100, step: 5)
                stepperRow("最大生成 Token", value: $storage.settings.maxTokens, in: 256...8192, step: 256)
                stepperRow("上下文长度", value: $storage.settings.contextLength, in: 1024...8192, step: 1024)
                stepperRow("GPU 层数 (0=纯CPU)", value: $storage.settings.gpuLayers, in: 0...64, step: 4)

                Text("参数在下次对话时生效。上下文越长占用内存越高；iPhone 统一内存有限，开启 GPU 层数时建议上下文 ≤2048，否则极易触发 Metal 显存不足。默认 0（纯 CPU）最稳定；调高 GPU 层数可加速，需在「模型」页重新加载模型。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }

    // MARK: - 系统提示词

    private var systemPromptCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "系统提示词", systemImage: "text.quote")
                TextField(
                    "例如：你是一个有帮助的AI助手…",
                    text: $storage.settings.systemPrompt,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .padding(10)
                .background(.quaternary, in: .rect(cornerRadius: 12))
            }
        }
    }

    // MARK: - 搜索服务

    private var searchCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "搜索服务", systemImage: "magnifyingglass")

                Picker("搜索引擎", selection: $storage.settings.searchEngine) {
                    Text("网页搜索（内置）").tag("web")
                    Text("维基百科（内置）").tag("wikipedia")
                }
                .pickerStyle(.segmented)

                Text("""
                供 Agent 的 web_search 工具使用。网页搜索由设备直接请求 Bing（失败时依次回退 DuckDuckGo、维基百科），无需自建任何服务。
                """)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "关于", systemImage: "info.circle")
                infoRow("推理引擎", "llama.cpp (GGUF) + mtmd 多模态")
                infoRow("界面", "SwiftUI · Liquid Glass (iOS 26+)")
                infoRow("隐私", "全部推理在本机完成，无网络上传")
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 危险区

    private var dangerZone: some View {
        GlassCard(cornerRadius: 18) {
            VStack(spacing: 12) {
                SectionHeader(title: "数据管理", systemImage: "trash")
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除全部对话记录", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .confirmationDialog(
                    "确定删除所有对话？此操作不可撤销。",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("全部删除", role: .destructive) {
                        chatStore.deleteAll()
                    }
                }
            }
        }
    }
}
