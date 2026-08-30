import Foundation

/// 自定义助手存储（Custom Assistants）
@MainActor
final class AssistantStore: ObservableObject {

    static let shared = AssistantStore()

    @Published var assistants: [AIAssistant] = [] {
        didSet { persist() }
    }
    @Published var currentAssistantID: UUID? {
        didSet { persistSelection() }
    }

    private let saveURL: URL
    private let selectionKey = "assistant.selection.v1"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = docs.appendingPathComponent("assistants.json")
        load()
        if assistants.isEmpty {
            assistants = [AIAssistant.default]
        }
        loadSelection()
    }

    var current: AIAssistant? {
        guard let id = currentAssistantID else { return nil }
        return assistants.first { $0.id == id }
    }

    func assistant(id: UUID?) -> AIAssistant? {
        guard let id else { return nil }
        return assistants.first { $0.id == id }
    }

    func upsert(_ assistant: AIAssistant) {
        if let idx = assistants.firstIndex(where: { $0.id == assistant.id }) {
            assistants[idx] = assistant
        } else {
            assistants.append(assistant)
        }
    }

    func delete(_ assistant: AIAssistant) {
        assistants.removeAll { $0.id == assistant.id }
        if currentAssistantID == assistant.id {
            currentAssistantID = assistants.first?.id
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // 与 persist 的 iso8601 一致
        guard let decoded = try? decoder.decode([AIAssistant].self, from: data)
        else { return }
        assistants = decoded
    }

    private func persist() {
        let snapshot = assistants
        let url = saveURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadSelection() {
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(UUID?.self, from: data) {
            currentAssistantID = decoded
        } else {
            currentAssistantID = assistants.first?.id
        }
    }

    private func persistSelection() {
        if let data = try? JSONEncoder().encode(currentAssistantID) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
    }
}
