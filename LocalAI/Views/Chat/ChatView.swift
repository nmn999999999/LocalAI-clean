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
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchResults: [ChatStore.SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    /// Agent 流式 token 缓冲区（按气泡 id），配合时间节流减少重渲染
    @State private var agentTokenBuffers: [UUID: String] = [:]
    @State private var agentLastFlush = Date.distantPast
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSearch {
                    searchBar
                }
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
            // 点击消息区域任意空白处（含气泡间隙）收起键盘；
            // simultaneousGesture 不阻挡气泡内按钮点击
            .simultaneousGesture(TapGesture().onEnded {
                inputFocused = false
            })
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

    // MARK: - 搜索栏

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索消息...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        // 防抖：停止输入 200ms 后再执行全量搜索，避免每个按键都扫描所有会话
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            guard !Task.isCancelled else { return }
                            searchResults = chatStore.search(query: newValue)
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults.prefix(20)) { result in
                            searchResultRow(result)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func searchResultRow(_ result: ChatStore.SearchResult) -> some View {
        Button {
            // 跳转到对应对话
            chatStore.currentConversationID = result.conversationID
            showSearch = false
            searchText = ""
            searchResults = []
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.conversationTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(excerpt(from: result.messageContent, around: result.matchRange))
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func excerpt(from text: String, around range: NSRange) -> String {
        let nsText = text as NSString
        let start = max(0, range.location - 20)
        let end = min(nsText.length, range.location + range.length + 40)
        let excerpt = nsText.substring(with: NSRange(location: start, length: end - start))
        
        var result = ""
        if start > 0 { result += "..." }
        result += excerpt
        if end < nsText.length { result += "..." }
        return result
    }

    // MARK: - Agent 步骤条

    @ViewBuilder
    private var agentStepsBar: some View {
        let settings = SettingsStorage.shared.settings
        if settings.showToolCalls && !agentService.steps.isEmpty {
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
            Button {
                withAnimation {
                    showSearch.toggle()
                    if !showSearch {
                        searchText = ""
                        searchResults = []
                    }
                }
            } label: {
                Image(systemName: showSearch ? "magnifyingglass" : "magnifyingglass")
                    .symbolEffect(.bounce, value: showSearch)
            }
            
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
        inputFocused = false

        var conv = chatStore.currentOrNew
        conv.messages.append(ChatMessage(role: .user, content: text, images: images))
        conv.updateTitle()
        conv.modelName = llmService.loadedModelName

        let settings = SettingsStorage.shared.settings

        let history: [ChatMessage]
        let assistantMsg: ChatMessage?
        if isAgentMode {
            history = Array(conv.messages)
            assistantMsg = nil
        } else {
            let m = ChatMessage(role: .assistant, content: "", isStreaming: true)
            conv.messages.append(m)
            assistantMsg = m
            history = conv.messages.filter { $0.id != m.id }
        }
        chatStore.upsert(conv)

        isGenerating = true
        generationTask = Task {
            defer {
                isGenerating = false
                generationTask = nil
            }

            if isAgentMode {
                let bridge = AgentService.AgentDisplayBridge(
                    beginIteration: {
                        let m = ChatMessage(role: .assistant, content: "", isStreaming: true, isAgentRound: true)
                        var c = chatStore.currentOrNew
                        c.messages.append(m)
                        chatStore.upsert(c)
                        return m.id
                    },
                    appendToken: { id, token in
                        appendAssistantToken(id: id, token: token)
                    },
                    attachToolCall: { id, call in
                        attachToolCallToMessage(id: id, call: call)
                    },
                    endIteration: { id in
                        finalizeMessage(id: id)
                    }
                )
                _ = await agentService.run(
                    history: history,
                    settings: settings,
                    llm: llmService,
                    bridge: bridge
                )
                return
            }

            guard let assistantMsg else { return }
            var full = ""
            var lastFlush = Date.distantPast
            do {
                let stream = llmService.streamChat(history: history, settings: settings, images: images.compactMap { $0.cgImage })
                for try await token in stream {
                    full += token
                    // 按时间节流刷新 UI（~80ms），避免高速 token 流频繁触发全量重渲染
                    let now = Date()
                    if now.timeIntervalSince(lastFlush) >= 0.08 {
                        updateAssistant(id: assistantMsg.id, content: full)
                        lastFlush = now
                    }
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

    /// 原位更新流式 assistant 消息（批量更新减少触发频率）。
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
        chatStore.upsert(conv)
    }

    private func appendAssistant(content: String, toolCalls: [ChatMessage.ToolCall]) {
        var conv = chatStore.currentOrNew
        conv.messages.append(ChatMessage(role: .assistant, content: content, toolCalls: toolCalls))
        chatStore.upsert(conv)
    }

    // MARK: - Agent 流式辅助（逐轮气泡）

    /// 给指定 assistant 气泡追加一个原始 token（含 <think> 标签，气泡自动解析思考/正文）。
    /// token 先入缓冲区，按时间节流（~80ms）批量刷入气泡，减少流式期间的全量重渲染。
    private func appendAssistantToken(id: UUID, token: String) {
        agentTokenBuffers[id, default: ""] += token
        let now = Date()
        guard now.timeIntervalSince(agentLastFlush) >= 0.08 else { return }
        agentLastFlush = now
        flushAgentTokenBuffer(id: id)
    }

    /// 把指定气泡缓冲区里的 token 一次性追加到消息内容。
    private func flushAgentTokenBuffer(id: UUID) {
        guard let buffered = agentTokenBuffers.removeValue(forKey: id), !buffered.isEmpty else { return }
        var conv = chatStore.currentOrNew
        guard let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].content += buffered
        chatStore.upsert(conv)
    }

    /// 把解析出的工具调用挂到指定气泡（气泡内以可展开 chip 展示参数与结果）。
    private func attachToolCallToMessage(id: UUID, call: ChatMessage.ToolCall) {
        var conv = chatStore.currentOrNew
        guard let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].toolCalls.append(call)
        chatStore.upsert(conv)
    }

    /// 结束指定气泡的流式状态（isStreaming = false），使其可被落盘与正常渲染。
    private func finalizeMessage(id: UUID) {
        // 先刷出缓冲区中尚未上屏的 token，再结束流式
        flushAgentTokenBuffer(id: id)
        var conv = chatStore.currentOrNew
        guard let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].isStreaming = false
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
