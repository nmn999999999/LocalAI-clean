import Foundation

/// 本地/自托管搜索服务。
/// 优先使用配置的 SearXNG 实例（自部署元搜索，聚合 Google/Bing/百度等，
/// 官方仓库 https://github.com/searxng/searxng），失败时自动回退维基百科。
enum SearchService {

    /// 执行搜索，返回可直接展示给模型的文本结果。
    static func search(query: String, settings: ModelSettings) async -> String {
        if settings.searchEngine == "searxng", !settings.searxngURL.isEmpty {
            if let result = await searxng(query: query, instance: settings.searxngURL) {
                return result
            }
        }
        // 回退：维基百科 opensearch（稳定、无需配置）
        if let result = await wikipedia(query: query) {
            return result
        }
        return "未找到与「\(query)」相关的结果"
    }

    /// SearXNG JSON API：GET {instance}/search?q=...&format=json&language=zh-CN
    /// 返回 {"results": [{"title","url","content"}, ...]}
    private static func searxng(query: String, instance: String) async -> String? {
        let trimmed = instance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed) else { return nil }
        let searchURL = base.appendingPathComponent("search")
        var comps = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: "zh-CN"),
        ]
        guard let url = comps?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("LocalAI/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]],
              !results.isEmpty else { return nil }

        var lines: [String] = ["搜索「\(query)」结果:"]
        for r in results.prefix(5) {
            let title = r["title"] as? String ?? ""
            let url = r["url"] as? String ?? ""
            let content = (r["content"] as? String ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(200)
            lines.append("- \(title)\n  \(url)\n  \(content)")
        }
        return lines.joined(separator: "\n\n")
    }

    /// 回退：维基百科 opensearch API
    private static func wikipedia(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://zh.wikipedia.org/w/api.php?action=opensearch&format=json&limit=3&search=\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("LocalAI/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 4,
              let titles = arr[1] as? [String],
              let urls = arr[3] as? [String],
              !titles.isEmpty else { return nil }

        return (0..<min(titles.count, urls.count))
            .map { "\($0 + 1). \(titles[$0])\n   \(urls[$0])" }
            .joined(separator: "\n")
    }
}
