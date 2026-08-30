import Foundation

// MARK: - 世界观设定（World Book）
// 实体/角色/规则定义，注入系统提示词后让模型遵循

struct WorldBookEntry: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var content: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, content: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.content = content
        self.enabled = enabled
    }
}

// MARK: - 长期记忆（Memory）
// 用户主动写入的跨会话记忆条目，注入系统提示词

struct MemoryEntry: Identifiable, Codable, Sendable {
    var id: UUID
    var content: String
    var createdAt: Date
    var enabled: Bool

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(), enabled: Bool = true) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.enabled = enabled
    }
}

// MARK: - 指令（Instruction Injection）
// 分组指令，注入系统提示词让模型在每次对话都遵守

struct InstructionGroup: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var instructions: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, instructions: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.enabled = enabled
    }
}

// MARK: - 组合存储

@MainActor
final class PersonaStore: ObservableObject {

    static let shared = PersonaStore()

    @Published var worldBook: [WorldBookEntry] = [] { didSet { persist() } }
    @Published var memory: [MemoryEntry] = [] { didSet { persist() } }
    @Published var instructions: [InstructionGroup] = [] { didSet { persist() } }

    private let saveURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = docs.appendingPathComponent("persona.json")
        load()
    }

    // MARK: - 注入系统提示词的文本块

    /// 按设置开关 + 条目启用状态，生成追加到系统提示词的内容
    func injectionText(settings: ModelSettings) -> String {
        var parts: [String] = []

        if settings.worldBookEnabled {
            let entries = worldBook.filter(\.enabled)
            if !entries.isEmpty {
                parts.append("## 世界观设定\n" + entries.map {
                    "- 【\($0.name)】\($0.content.replacingOccurrences(of: "\n", with: " "))"
                }.joined(separator: "\n"))
            }
        }

        if settings.memoryEnabled {
            let entries = memory.filter(\.enabled)
            if !entries.isEmpty {
                parts.append("## 长期记忆（来自之前对话，请记住并在回答时考虑）\n" + entries.map {
                    "- \($0.content.replacingOccurrences(of: "\n", with: " "))"
                }.joined(separator: "\n"))
            }
        }

        if settings.instructionEnabled {
            let groups = instructions.filter(\.enabled)
            if !groups.isEmpty {
                parts.append("## 指令（每次对话必须遵守）\n" + groups.map { group in
                    "### \(group.name)\n\(group.instructions)"
                }.joined(separator: "\n"))
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - 记忆自动提炼（世界观自动记忆抽取 pipeline）

    /// 根据一段对话提炼出稳定的用户事实/偏好，去重后合并进「长期记忆」。
    /// 返回本次新增的记忆条数（0 表示没有新内容或提炼失败）。
    /// 失败静默：不抛错、不打扰用户（后台 pipeline 语义）。
    func extractMemories(from messages: [ChatMessage], llm: LLMService) async -> Int {
        // 只取最近几轮 user/assistant 正文（去掉工具/系统消息，控制输入规模）
        let recent = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(12)
            .map { msg -> String in
                let role = msg.role == .user ? "用户" : "助手"
                return role + ": " + msg.visibleContent.prefix(300)
            }
            .joined(separator: "\n")

        let instruction = """
        你是记忆提炼助手。根据下面这段对话，提炼出关于用户的稳定事实与偏好（如职业、习惯、技术栈、语言偏好、回答风格），
        输出为 JSON 字符串数组，例如 ["用户是 iOS 开发者", "用户偏好中文回答"]。

        规则：
        1. 只提炼跨会话仍然有用的稳定事实；不要一次性信息（如"今天天气很好"）。
        2. 每条不超过 40 字，最多 5 条。
        3. 没有可提炼内容时输出 []
        4. 只输出 JSON 数组本身，不要任何其他文字或解释。

        对话：
        \(recent)
        """

        do {
            let reply = try await llm.complete(
                messages: [ChatMessage(role: .user, content: instruction)],
                settings: SettingsStorage.shared.settings
            )
            let extracted = Self.parseMemoryList(reply)
            guard !extracted.isEmpty else { return 0 }
            return mergeMemories(extracted)
        } catch {
            return 0   // 静默失败（未加载模型 / 云端不可用等）
        }
    }

    /// 从模型输出里解析 JSON 字符串数组（容错：允许围栏/前后缀文字/单引号）。
    static func parseMemoryList(_ text: String) -> [String] {
        // 先找第一对平衡的 [ ... ]（跳过 ``` 围栏）
        guard let open = text.firstIndex(of: "["),
              let close = text[open...].lastIndex(of: "]"),
              close > open
        else { return [] }
        let json = String(text[open...close])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 }
    }

    /// 与已有记忆去重（忽略大小写/子串匹配）后合并，返回新增条数。
    private func mergeMemories(_ extracted: [String]) -> Int {
        var added = 0
        for item in extracted {
            let key = item.lowercased()
            let exists = memory.contains { existing in
                let e = existing.content.lowercased()
                return e == key || e.contains(key) || key.contains(e)
            }
            guard !exists else { continue }
            memory.append(MemoryEntry(content: item))
            added += 1
        }
        return added
    }

    // MARK: - 持久化

    private struct Payload: Codable {
        var worldBook: [WorldBookEntry]
        var memory: [MemoryEntry]
        var instructions: [InstructionGroup]
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // 与 persist 的 iso8601 一致
        guard let pkg = try? decoder.decode(Payload.self, from: data)
        else { return }
        worldBook = pkg.worldBook
        memory = pkg.memory
        instructions = pkg.instructions
    }

    private func persist() {
        let pkg = Payload(worldBook: worldBook, memory: memory, instructions: instructions)
        let url = saveURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(pkg) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
