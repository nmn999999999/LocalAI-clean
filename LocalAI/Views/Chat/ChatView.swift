import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var llmService: LLMService
    @EnvironmentObject private var agentService: AgentService
    @EnvironmentObject private var modelManager: ModelManager

    @State private var inputText = ""
    @State private var isAgentMode = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var attachments: [ChatMessage.ImageData] = []
    @State private var showConversationList = false
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if llmService.isModelReady {
                    agentStepsBar
                }
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(chatStore.currentOrNew.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showConversationList) {
                ConversationListView()
                    .presentationDetents([.medium, .large])
            }
            .alert("出错了", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !llmService.isModelReady && chatStore.currentOrNew.messages.isEmpty {
                        emptyState
                    }
                    ForEach(chatStore.currentOrNew.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id.uuidString)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: chatStore.currentOrNew.messages.count) { _, _ in
                withAnimation(.snappy) {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: chatStore.currentOrNew.messages.last?.content) { _, _ in
                scrollToBottom(proxy)
            }
            .defaultScrollAnchor(.bottom)
            // 在消息列表上下滑即可收起键盘
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // 点消息区域空白处收起键盘
                inputFocused = false
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let id = chatStore.currentOrNew.messages.last?.id.uuidString {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(llmService.isModelReady ? "开始对话吧" : "还没有加载模型")
                .font(.title3.weight(.semibold))
            Text(llmService.isModelReady
                 ? "在下方输入消息，或开启 Agent 模式使用工具"
                 : "前往「模型」页下载或导入 GGUF 模型")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 120)
    }

    // MARK: - Agent 步骤条

    @ViewBuilder
    private var agentStepsBar: some View {
        if !agentService.steps.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(agentService.steps) { step in
                        HStack(spacing: 4) {
                            Image(systemName: iconName(for: step.kind))
                                .font(.caption2)
                            Text(step.detail)
                                .lineLimit(1)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 6)
        }
    }

    private func iconName(for kind: AgentService.Step.Kind) -> String {
        switch kind {
        case .thinking: return "brain"
        case .executing: return "gearshape.2"
        case .result: return "checkmark.circle"
        case .finalAnswer: return "text.bubble"
        }
    }

    // MARK: - 输入栏（液态玻璃）

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.glass)
                .opacity(llmService.isModelReady ? 1 : 0.35)

                Button {
                    withAnimation(.bouncy) { isAgentMode.toggle() }
                } label: {
                    Image(systemName: isAgentMode ? "wand.and.stars" : "terminal")
                        .symbolEffect(.bounce, value: isAgentMode)
                }
                .buttonStyle(.glass)
                .tint(isAgentMode ? .orange : nil)
                .opacity(llmService.isModelReady ? 1 : 0.35)

                TextField("输入消息…", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .onChange(of: selectedItems) { _, items in
            Task { await loadAttachments(items) }
        }
    }

    private var sendButton: some View {
        Button {
            if isGenerating {
                stopGeneration()
            } else {
                sendMessage()
            }
        } label: {
            Image(systemName: isGenerating
                  ? "stop.circle.fill"
                  : (canSend ? "arrow.up.circle.fill" : "arrow.up.circle"))
                .font(.system(size: 26))
        }
        .buttonStyle(.glassProminent)
        .disabled(!canSend && !isGenerating)
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !attachments.isEmpty
        return llmService.isModelReady && (hasText || hasImage) && !isGenerating
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showConversationList = true
            } label: {
                Image(systemName: "sidebar.left")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                ForEach(modelManager.downloadedModels) { model in
                    Button {
                        Task { await loadModel(model) }
                    } label: {
                        Label(model.name, systemImage:
                            llmService.loadedModelName == model.name ? "checkmark" : "cpu")
                    }
                }
            } label: {
                Label(
                    llmService.loadedModelName ?? "选择模型",
                    systemImage: "cpu"
                )
                .lineLimit(1)
            }
            Button {
                chatStore.createNew()
            } label: {
                Image(systemName: "square.and.pencil")
            }
        }
    }

    // MARK: - 动作

    private func loadModel(_ stored: ModelManager.StoredModel) async {
        let url = modelManager.localFileURL(for: stored)
        await llmService.load(url: url, displayName: stored.name)
        if case .ready = llmService.state {
            modelManager.rememberLastUsed(stored)
        }
        if case .failed(let msg) = llmService.state {
            errorMessage = msg
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        let images = attachments
        inputText = ""
        attachments = []
        selectedItems = []
        inputFocused = false // 发送后收起键盘

        var conv = chatStore.currentOrNew
        conv.messages.append(ChatMessage(role: .user, content: text, images: images))
        conv.updateTitle()
        conv.modelName = llmService.loadedModelName

        // 预插入一条流式 assistant 消息，token 逐字更新到气泡内
        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        conv.messages.append(assistantMsg)
        chatStore.upsert(conv)

        // 传给引擎的历史不包含占位消息本身
        let history = conv.messages.filter { $0.id != assistantMsg.id }
        let settings = SettingsStorage.shared.settings

        isGenerating = true
        generationTask = Task {
            defer {
                isGenerating = false
                generationTask = nil
            }

            if isAgentMode {
                let result = await agentService.run(
                    history: history,
                    settings: settings,
                    llm: llmService
                )
                // 注意：必须显式传 streaming: false，否则 assistant 消息的 isStreaming 永远为 true，
                // 导致 ChatStore.scheduleSave() 的守卫永久拦截落盘，整段 Agent 会话丢失。
                updateAssistant(id: assistantMsg.id, content: result.content, toolCalls: result.toolCalls, streaming: false)
                return
            }

            var full = ""
            do {
                let stream = llmService.streamChat(history: history, settings: settings)
                for try await token in stream {
                    full += token
                    updateAssistant(id: assistantMsg.id, content: full)
                }
                updateAssistant(id: assistantMsg.id, content: full, streaming: false)
            } catch {
                updateAssistant(id: assistantMsg.id, content: full, streaming: false)
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// 原位更新流式 assistant 消息（每来一个 token 调用一次）。
    private func updateAssistant(
        id: UUID,
        content: String,
        toolCalls: [ChatMessage.ToolCall] = [],
        streaming: Bool = true
    ) {
        var conv = chatStore.currentOrNew
        guard let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].content = content
        conv.messages[idx].toolCalls = toolCalls
        conv.messages[idx].isStreaming = streaming
        conv.messages[idx].timestamp = Date()
        chatStore.upsert(conv)
    }

    private func appendAssistant(content: String, toolCalls: [ChatMessage.ToolCall]) {
        var conv = chatStore.currentOrNew
        conv.messages.append(ChatMessage(role: .assistant, content: content, toolCalls: toolCalls))
        chatStore.upsert(conv)
    }

    private func loadAttachments(_ items: [PhotosPickerItem]) async {
        var loaded: [ChatMessage.ImageData] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let resized = Self.resizedImageData(from: data, maxDimension: 1024) {
                loaded.append(resized)
            }
        }
        attachments = loaded
    }

    /// 压缩图片，避免超出模型/内存限制
    static func resizedImageData(from data: Data, maxDimension: CGFloat) -> ChatMessage.ImageData? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return ChatMessage.ImageData(data: resized.jpegData(compressionQuality: 0.85) ?? data,
                                     mimeType: "image/jpeg")
        #else
        return ChatMessage.ImageData(data: data, mimeType: "image/png")
        #endif
    }
}
