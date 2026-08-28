import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var llmService: LLMService
    @EnvironmentObject private var chatStore: ChatStore
    @ObservedObject private var storage = SettingsStorage.shared

    @State private var showDeleteConfirm = false
    @FocusState private var focusedField: Field?
    
    private enum Field: Hashable {
        case apiEndpoint, apiKey, apiModel, systemPrompt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    apiModeCard
                    generationCard
                    displayCard
                    memoryCard
                    systemPromptCard
                    searchCard
                    sshCard
                    aboutCard
                    dangerZone
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusedField = nil
            }
        }
    }

    // MARK: - API 模式

    private var apiModeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "API 模式", systemImage: "cloud")
                
                Toggle(isOn: $storage.settings.apiEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用外部 API")
                            .font(.subheadline)
                        Text("使用 OpenAI 兼容 API 获取最大性能（如 GPT-4o、Claude、DeepSeek 等）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)
                .onChange(of: storage.settings.apiEnabled) { _, newValue in
                    if newValue {
                        llmService.enableApiMode(settings: storage.settings)
                    } else {
                        llmService.unload()
                    }
                }
                
                if storage.settings.apiEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // API 地址
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API 端点").font(.subheadline)
                            TextField("https://api.openai.com/v1/chat/completions", text: $storage.settings.apiEndpoint)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(.quaternary, in: .rect(cornerRadius: 10))
                                .font(.caption)
                                .focused($focusedField, equals: .apiEndpoint)
                        }
                        
                        // API Key
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API 密钥").font(.subheadline)
                            SecureField("sk-...", text: $storage.settings.apiKey)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(.quaternary, in: .rect(cornerRadius: 10))
                                .font(.caption)
                                .focused($focusedField, equals: .apiKey)
                        }
                        
                        // 模型名称
                        VStack(alignment: .leading, spacing: 4) {
                            Text("模型名称").font(.subheadline)
                            TextField("gpt-4o-mini", text: $storage.settings.apiModel)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(.quaternary, in: .rect(cornerRadius: 10))
                                .font(.caption)
                                .focused($focusedField, equals: .apiModel)
                        }
                        
                        // API 参数
                        sliderRow("温度", value: $storage.settings.apiTemperature, in: 0...2)
                        stepperRow("最大 Token", value: $storage.settings.apiMaxTokens, in: 256...16384, step: 256)
                        
                        Text("支持所有 OpenAI 兼容 API（OpenAI、Anthropic、DeepSeek、本地 Ollama 等）。密钥仅存储在本地，不会上传。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
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

    // MARK: - 显示设置

    private var displayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "显示设置", systemImage: "eye")

                Toggle(isOn: $storage.settings.showThinking) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("显示思考过程")
                            .font(.subheadline)
                        Text("展示模型的 <think> 标签内容（推理模型如 DeepSeek-R1、Qwen3 的思考过程）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $storage.settings.showToolCalls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("显示工具调用")
                            .font(.subheadline)
                        Text("展示 Agent 模式下工具调用的参数和结果")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)
            }
        }
    }

    // MARK: - 内存优化

    private var memoryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "内存优化", systemImage: "memorychip")

                Toggle(isOn: $storage.settings.useMmap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("内存映射加载 (mmap)")
                            .font(.subheadline)
                        Text("开启后模型文件映射到虚拟内存，仅访问的页面才加载到RAM，大幅减少内存占用。关闭可提升推理速度但占用更多内存。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
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
                .focused($focusedField, equals: .systemPrompt)
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

    // MARK: - SSH 配置（Agent ssh 工具默认连接）

    private var sshCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "SSH 连接", systemImage: "terminal")

                VStack(alignment: .leading, spacing: 4) {
                    Text("主机").font(.subheadline)
                    TextField("例如 192.168.1.10 或 example.com", text: $storage.settings.sshHost)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("端口").font(.subheadline)
                        TextField("22", value: $storage.settings.sshPort, format: .number)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .font(.caption)
                            .keyboardType(.numberPad)
                    }
                    .frame(maxWidth: 110)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("用户名").font(.subheadline)
                        TextField("root", text: $storage.settings.sshUser)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .font(.caption)
                    }
                }

                Picker("认证方式", selection: $storage.settings.sshAuthType) {
                    Text("密码").tag("password")
                    Text("私钥").tag("key")
                }
                .pickerStyle(.segmented)

                if storage.settings.sshAuthType == "password" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密码").font(.subheadline)
                        SecureField("登录密码", text: $storage.settings.sshPassword)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .font(.caption)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("私钥 (PEM)").font(.subheadline)
                        TextEditor(text: $storage.settings.sshPrivateKey)
                            .font(.caption.monospaced())
                            .frame(minHeight: 110, maxHeight: 200)
                            .padding(6)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .overlay(alignment: .topLeading) {
                                if storage.settings.sshPrivateKey.isEmpty {
                                    Text("粘贴 -----BEGIN ... PRIVATE KEY----- 内容")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(10)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("私钥口令（可选）").font(.subheadline)
                        SecureField("留空表示无口令", text: $storage.settings.sshPassphrase)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .font(.caption)
                    }
                }

                Text("供 Agent 的 ssh 工具使用：在对话中让 AI「在服务器上执行 xxx」即可。账号信息仅存于本机，私钥不会上传。工具参数可临时覆盖主机/端口/用户/命令。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "关于", systemImage: "info.circle")
                infoRow("推理引擎", "llama.cpp (GGUF) + mtmd 多模态")
                infoRow("API 支持", "OpenAI 兼容格式（GPT-4o/Claude/DeepSeek 等）")
                infoRow("界面", "SwiftUI · Liquid Glass (iOS 26+)")
                infoRow("隐私", "本地模式：全部推理在本机完成，无网络上传")
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
