import Foundation

@MainActor
final class ChatStore: ObservableObject {

    @Published var conversations: [Conversation] = [] {
        didSet { scheduleSave() }
    }
    @Published var currentConversationID: UUID?

    private let saveURL: URL
    private var saveTask: Task<Void, Never>?
    private var lastSaveData: Data?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = docs.appendingPathComponent("conversations.json")
        load()
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

    /// 从备份整体恢复会话（Backup/Restore）
    func restoreFromBackup(_ newConversations: [Conversation]) {
        let sanitized = newConversations.map { conv -> Conversation in
            var c = conv
            c.messages = c.messages.map { m in
                var mm = m
                mm.isStreaming = false
                return mm
            }
            return c
        }
        conversations = sanitized.isEmpty ? [Conversation()] : sanitized
        currentConversationID = conversations.first?.id
    }

    // MARK: - 持久化

    private func scheduleSave() {
        // 检查当前正在生成的对话（或最近被修改的）的最新消息是否在流式输出。
        // 之前用 `conversations.last` 是错的——`conversations.last` 是最旧对话，
        // 新对话通过 `insert(_:at:0)` 插到开头。结果：用户当前对话在流式时，
        // 500ms 内所有 token 更新全部被跳过，重启即丢失生成内容。
        if let target = conversations.first(where: { $0.id == currentConversationID }) ?? conversations.first,
           target.messages.last?.isStreaming == true {
            return
        }
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
        let lastData = lastSaveData
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            if data == lastData { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        lastSaveData = data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([Conversation].self, from: data)) ?? []
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

    // MARK: - 搜索功能

    struct SearchResult: Identifiable {
        let id = UUID()
        let conversationID: UUID
        let conversationTitle: String
        let messageID: UUID
        let messageContent: String
        let matchRange: NSRange
        let timestamp: Date
    }

    func search(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        var results: [SearchResult] = []
        
        for conversation in conversations {
            for message in conversation.messages {
                let content = message.content
                guard let range = content.range(of: query, options: .caseInsensitive) else { continue }
                
                let start = content.distance(from: content.startIndex, to: range.lowerBound)
                let length = content.distance(from: range.lowerBound, to: range.upperBound)
                let nsRange = NSRange(location: start, length: length)
                
                let result = SearchResult(
                    conversationID: conversation.id,
                    conversationTitle: conversation.title,
                    messageID: message.id,
                    messageContent: content,
                    matchRange: nsRange,
                    timestamp: message.timestamp
                )
                results.append(result)
            }
        }
        
        return results.sorted { $0.timestamp > $1.timestamp }
    }

    func search(query: String, in conversationID: UUID) -> [SearchResult] {
        guard !query.isEmpty, let conversation = conversation(id: conversationID) else { return [] }
        
        var results: [SearchResult] = []
        
        for message in conversation.messages {
            let content = message.content
            guard let range = content.range(of: query, options: .caseInsensitive) else { continue }
            
            let start = content.distance(from: content.startIndex, to: range.lowerBound)
            let length = content.distance(from: range.lowerBound, to: range.upperBound)
            let nsRange = NSRange(location: start, length: length)
            
            let result = SearchResult(
                conversationID: conversation.id,
                conversationTitle: conversation.title,
                messageID: message.id,
                messageContent: content,
                matchRange: nsRange,
                timestamp: message.timestamp
            )
            results.append(result)
        }
        
        return results.sorted { $0.timestamp > $1.timestamp }
    }
}
