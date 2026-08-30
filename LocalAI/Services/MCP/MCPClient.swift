import Foundation
import Synchronization

// MARK: - MCP 模型（Model Context Protocol，MCP 支持）

struct MCPTool: Identifiable, Codable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    /// JSON Schema 字符串（inputSchema）
    var inputSchemaJSON: String
}

struct MCPServer: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    /// streamable HTTP 端点，如 https://example.com/mcp
    var url: String
    var headers: [String: String]
    var enabled: Bool
    /// 已发现的工具（持久化，断开后可离线查看）
    var tools: [MCPTool]
    var sessionID: String?
    var lastError: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        headers: [String: String] = [:],
        enabled: Bool = true,
        tools: [MCPTool] = [],
        sessionID: String? = nil,
        lastError: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.headers = headers
        self.enabled = enabled
        self.tools = tools
        self.sessionID = sessionID
        self.lastError = lastError
        self.createdAt = createdAt
    }

    var connected: Bool { sessionID != nil && lastError == nil }
}

// MARK: - 错误

enum MCPError: LocalizedError, Sendable {
    case invalidURL
    case httpError(Int, String)
    case rpcError(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "MCP 地址无效"
        case .httpError(let code, let body): return "MCP HTTP \(code): \(String(body.prefix(300)))"
        case .rpcError(let msg): return "MCP 错误: \(msg)"
        case .emptyResult: return "MCP 未返回结果"
        }
    }
}

// MARK: - MCP 客户端（streamable HTTP + JSON-RPC 2.0）

enum MCPClient {

    static let protocolVersion = "2025-03-26"

    /// 建立会话（initialize + notifications/initialized）
    static func initialize(url: String, headers: [String: String]) async throws -> String? {
        let (result, sessionID) = try await request(
            url: url, headers: headers, sessionID: nil,
            method: "initialize",
            params: [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": "LocalAI", "version": "1.0"],
            ]
        )
        // notifications/initialized 通知
        _ = try? await request(
            url: url, headers: headers, sessionID: sessionID,
            method: "notifications/initialized", params: [:],
            isNotification: true
        )
        return sessionID
    }

    /// 列出工具
    static func listTools(url: String, headers: [String: String], sessionID: String?) async throws -> [MCPTool] {
        let (result, _) = try await request(
            url: url, headers: headers, sessionID: sessionID,
            method: "tools/list", params: [:]
        )
        guard let dict = result as? [String: Any],
              let tools = dict["tools"] as? [[String: Any]]
        else { return [] }

        return tools.compactMap { t in
            guard let name = t["name"] as? String else { return nil }
            let desc = t["description"] as? String ?? ""
            let schema = t["inputSchema"] as? [String: Any] ?? [:]
            let schemaData = (try? JSONSerialization.data(withJSONObject: schema)) ?? Data()
            return MCPTool(
                name: name,
                description: desc,
                inputSchemaJSON: String(data: schemaData, encoding: .utf8) ?? "{}"
            )
        }
    }

    /// 调用工具，返回文本化结果
    static func callTool(
        url: String, headers: [String: String], sessionID: String?,
        name: String, argumentsJSON: String
    ) async throws -> String {
        var params: [String: Any] = ["name": name]
        if let data = argumentsJSON.data(using: .utf8),
           let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            params["arguments"] = args
        }
        let (result, _) = try await request(
            url: url, headers: headers, sessionID: sessionID,
            method: "tools/call", params: params
        )
        guard let dict = result as? [String: Any] else { throw MCPError.emptyResult }

        // 错误结果
        if let isError = dict["isError"] as? Bool, isError {
            let content = extractText(dict["content"])
            throw MCPError.rpcError(content.isEmpty ? "工具执行失败" : content)
        }
        let text = extractText(dict["content"])
        guard !text.isEmpty else { throw MCPError.emptyResult }
        return text
    }

    private static func extractText(_ content: Any?) -> String {
        guard let items = content as? [[String: Any]] else { return "" }
        return items.compactMap { item -> String? in
            guard let type = item["type"] as? String else { return nil }
            switch type {
            case "text": return item["text"] as? String
            case "image": return "[图片 \(item["mimeType"] as? String ?? "")]"
            case "resource", "resource_link": return "[资源 \(item["uri"] as? String ?? "")]"
            default: return nil
            }
        }.joined(separator: "\n")
    }

    // MARK: - JSON-RPC 请求

    private static let requestCounter = Mutex<Int>(0)

    private static func request(
        url: String, headers: [String: String], sessionID: String?,
        method: String, params: [String: Any],
        isNotification: Bool = false
    ) async throws -> (Any?, String?) {
        guard let requestURL = URL(string: url) else { throw MCPError.invalidURL }

        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if isNotification {
            if !params.isEmpty { body["params"] = params }
        } else {
            let id = requestCounter.withLock { $0 += 1; return $0 }
            body["id"] = id
            if !params.isEmpty { body["params"] = params }
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidURL }
        let newSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") ?? sessionID

        guard (200...299).contains(http.statusCode) else {
            throw MCPError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        // 可能是 SSE 流（streamable HTTP），取第一条 data 行
        // v0.3.40 修复：不能用 split(separator: Character) 切 "\n" —— Swift 的 Unicode 字形簇
        // 把 CRLF 当成一个整体字符，split 切不开 SSE 标准行尾（DeepWiki 等返回 CRLF，
        // 导致整段响应被当一行、data: 解析不到、工具列表全空）。
        // 改用 components(separatedBy:)（子串级切分）+ whitespacesAndNewlines（顺带去掉 \r）。
        var jsonObject: Any?
        let raw = String(data: data, encoding: .utf8) ?? ""
        if raw.contains("data:") {
            for line in raw.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("data:"),
                   let d = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) {
                    jsonObject = obj
                    break
                }
            }
        } else {
            jsonObject = try? JSONSerialization.jsonObject(with: data)
        }

        if isNotification { return (nil, newSessionID) }

        guard let dict = jsonObject as? [String: Any] else { throw MCPError.emptyResult }
        if let error = dict["error"] as? [String: Any],
           let msg = error["message"] as? String {
            throw MCPError.rpcError(msg)
        }
        return (dict["result"], newSessionID)
    }
}
