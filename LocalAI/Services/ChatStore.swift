import Foundation

@MainActor
final class ChatStore: ObservableObject {

    @Published var conversations: [Conversation] = [] {
        didSet { scheduleSave() }
    }
    @Published var currentConversationID: UUID?

    private let saveURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = docs.appendingPathComponent("conversations.json")
        load()
        // 不变式：始终至少存在一个对话，避免视图渲染期间修改状态
        if conversations.isEmpty {
            let conv = Conversation()
            conversations.append(conv)
            currentConversationID = conv.id
        }
    }

    // MARK: - 访问

    var current: Conversation? {
        get { conversations.first { $0.id == currentConversationID } ?? conversations.first }
        set {
            guard let newValue else { return }
            upsert(newValue)
        }
    }

    var currentOrNew: Conversation {
        if let current { return current }
        let conv = Conversation()
        conversations.insert(conv, at: 0)
        currentConversationID = conv.id
        return conv
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func upsert(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        currentConversationID = conversation.id
    }

    func createNew() -> Conversation {
        let conv = Conversation()
        conversations.insert(conv, at: 0)
        currentConversationID = conv.id
        return conv
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversationID == conversation.id {
            currentConversationID = conversations.first?.id
        }
        if conversations.isEmpty {
            let conv = Conversation()
            conversations.append(conv)
            currentConversationID = conv.id
        }
    }

    func deleteAll() {
        conversations.removeAll()
        let conv = Conversation()
        conversations.append(conv)
        currentConversationID = conv.id
    }

    // MARK: - 持久化

    private func scheduleSave() {
        // 流式生成中的中间状态不落盘：每个 token 都会触发 conversations 变化，
        // 若照常持久化，主线程会持续做 JSON 编码与写盘（含图片 base64 时文件很大），
        // 导致主线程卡顿（runloop hang）。等 isStreaming 结束时再保存一次即可。
        if conversations.last?.messages.last?.isStreaming == true { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        let snapshot = conversations
        let url = saveURL
        // JSON 编码与写盘移到后台线程，避免阻塞主线程
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([Conversation].self, from: data)) ?? []
        // 复位遗留的流式标记：磁盘里不该有"正在生成"的消息。
        // 若历史里残留 isStreaming == true（例如旧版 Agent 会话未正确收尾），
        // 会让 scheduleSave 守卫误判、导致整段对话永不落盘。
        conversations = decoded.map { conv in
            var c = conv
            c.messages = c.messages.map { m in
                var mm = m
                mm.isStreaming = false
                return mm
            }
            return c
        }
        currentConversationID = conversations.first?.id
    }
}
