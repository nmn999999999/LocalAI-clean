import Foundation

/// MCP 服务器管理 + Agent 工具目录集成
/// MCP 工具通过「服务」页连接发现，加入 Agent 工具目录，由对话循环执行
@MainActor
final class MCPService: ObservableObject {

    static let shared = MCPService()

    @Published var servers: [MCPServer] = [] {
        didSet { persist() }
    }
    @Published var connectingID: UUID?

    /// 免费公共 MCP 服务预设（免密钥 · streamable HTTP）。
    /// 均为公开社区长期运行的服务：连接失败时显示错误，可随时删除。
    struct MCPPreset: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let url: String
        let note: String
    }

    static let freePresets: [MCPPreset] = [
        MCPPreset(
            name: "DeepWiki",
            url: "https://mcp.deepwiki.com/mcp",
            note: "查询任意 GitHub 仓库的官方文档（免费免密钥）"
        ),
        // ⚠️ ContextX·Grok 搜索曾因公共端点不稳定（2026-08-31 起 /mcp 返回 404）被移除。
        // 如需联网搜索，直接用内置 web_search 工具或 Bing/维基（无需任何 MCP）。
    ]

    private let saveURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = docs.appendingPathComponent("mcp-servers.json")
        load()
    }

    func server(id: UUID?) -> MCPServer? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
    }

    // MARK: - 增删改

    func upsert(_ server: MCPServer) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
    }

    func delete(_ server: MCPServer) {
        servers.removeAll { $0.id == server.id }
    }

    /// 一键添加免费预设：同名已存在则直接返回（不重复添加）。
    @discardableResult
    func addPreset(_ preset: MCPPreset) -> MCPServer {
        if let existing = servers.first(where: { $0.name == preset.name }) {
            return existing
        }
        let server = MCPServer(name: preset.name, url: preset.url)
        servers.append(server)
        return server
    }

    // MARK: - 连接 / 断开

    func connect(_ server: MCPServer) async {
        connectingID = server.id
        defer { connectingID = nil }

        var updated = server
        updated.lastError = nil
        do {
            let sessionID = try await MCPClient.initialize(url: server.url, headers: server.headers)
            let tools = try await MCPClient.listTools(url: server.url, headers: server.headers, sessionID: sessionID)
            updated.sessionID = sessionID
            updated.tools = tools
            if tools.isEmpty { updated.lastError = "已连接，但服务器没有暴露任何工具" }
        } catch {
            updated.sessionID = nil
            updated.lastError = error.localizedDescription
        }
        upsert(updated)
    }

    func disconnect(_ server: MCPServer) {
        var updated = server
        updated.sessionID = nil
        updated.lastError = "已断开"
        upsert(updated)
    }

    // MARK: - Agent 集成

    /// 汇总所有已启用且已连接服务器的工具，转为 Agent 工具目录定义
    var toolDefinitions: [AgentToolDefinition] {
        var defs: [AgentToolDefinition] = []
        for server in servers where server.enabled && server.connected {
            for tool in server.tools {
                defs.append(AgentToolDefinition(
                    id: "mcp-\(server.id.uuidString)-\(tool.name)",
                    name: tool.name,
                    description: tool.description.isEmpty ? "MCP 工具（服务器 \(server.name)）" : tool.description,
                    parameters: Self.parseSchema(tool.inputSchemaJSON),
                    requiresApproval: true  // MCP 工具由第三方服务器提供，权限未知 → 默认需要审批（与 opencode 一致）
                ))
            }
        }
        return defs
    }

    /// 按工具名找到所属服务器
    func server(forToolName name: String) -> (server: MCPServer, tool: MCPTool)? {
        for server in servers where server.enabled && server.connected {
            if let tool = server.tools.first(where: { $0.name == name }) {
                return (server, tool)
            }
        }
        return nil
    }

    /// 调用 MCP 工具（Agent 循环分发）
    func callTool(name: String, argumentsJSON: String) async -> String {
        guard let found = server(forToolName: name) else {
            return "未知工具: \(name)"
        }
        return await callTool(server: found.server, name: name, argumentsJSON: argumentsJSON)
    }

    /// 调用指定服务器上的 MCP 工具（UI 测试用，不要求该工具处于「已连接」也能带 session 尝试）
    func callTool(server: MCPServer, name: String, argumentsJSON: String) async -> String {
        do {
            return try await MCPClient.callTool(
                url: server.url,
                headers: server.headers,
                sessionID: server.sessionID,
                name: name,
                argumentsJSON: argumentsJSON
            )
        } catch {
            return "MCP 调用失败: \(error.localizedDescription)"
        }
    }

    /// 解析 MCP JSON Schema → Agent 参数定义
    private static func parseSchema(_ json: String) -> [String: AgentToolDefinition.ParameterSchema] {
        guard let data = json.data(using: .utf8),
              let schema = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let properties = schema["properties"] as? [String: [String: Any]]
        else { return [:] }

        var params: [String: AgentToolDefinition.ParameterSchema] = [:]
        for (name, prop) in properties {
            params[name] = AgentToolDefinition.ParameterSchema(
                type: prop["type"] as? String ?? "string",
                description: prop["description"] as? String ?? "",
                enumValues: prop["enum"] as? [String]
            )
        }
        return params
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // 与 persist 的 iso8601 一致
        guard let decoded = try? decoder.decode([MCPServer].self, from: data)
        else { return }
        servers = decoded
    }

    private func persist() {
        let snapshot = servers
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
}
