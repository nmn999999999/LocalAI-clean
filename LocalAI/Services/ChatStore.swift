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
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = (try? decoder.decode([Conversation].self, from: data)) ?? []
        currentConversationID = conversations.first?.id
    }
}
