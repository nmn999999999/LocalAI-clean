import Foundation

/// 本地网络搜索：设备直接请求公共搜索引擎，无需自建任何服务。
/// 链路：Bing RSS（国内可达、免密钥、结构化输出）→ DuckDuckGo HTML → 维基百科。
/// 任一级成功即返回；全部失败才报"未找到"。
enum SearchService {

    /// 浏览器 UA：部分公共端点对非浏览器 UA 返回空结果
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// 执行搜索，返回可直接展示给模型的文本结果。
    /// settings.searchEngine == "wikipedia" 时只用维基百科；否则走完整网页搜索链。
    static func search(query: String, settings: ModelSettings) async -> String {
        if settings.searchEngine != "wikipedia" {
            if let result = await bing(query: query) { return result }
            if let result = await duckduckgo(query: query) { return result }
        }
        if let result = await wikipedia(query: query) {
            return result
        }
        return "未找到与「\(query)」相关的结果"
    }

    // MARK: - Bing RSS（首选）

    /// Bing 搜索的 RSS 输出：GET https://cn.bing.com/search?q=<query>&format=rss
    /// 返回标准 RSS XML：<item><title/><link/><description/></item>，解析简单且免密钥。
    private static func bing(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://cn.bing.com/search?q=\(encoded)&format=rss&count=8")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else { return nil }

        let items = parseRSS(xml)
        guard !items.isEmpty else { return nil }

        var lines = ["搜索「\(query)」结果:"]
        for item in items.prefix(5) {
            let content = item.snippet.replacingOccurrences(of: "\n", with: " ")
            lines.append("- \(item.title)\n  \(item.url)\n  \(content)")
        }
        return lines.joined(separator: "\n\n")
    }

    private static func parseRSS(_ xml: String) -> [(title: String, url: String, snippet: String)] {
        var results: [(String, String, String)] = []
        guard let itemRegex = try? NSRegularExpression(
            pattern: #"<item>(.*?)</item>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let ns = xml as NSString
        let matches = itemRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let block = ns.substring(with: m.range(at: 1))
            let title = extractTag("title", from: block)
            let link = extractTag("link", from: block)
            let desc = extractTag("description", from: block)
            if !title.isEmpty {
                results.append((unescapeHTML(title), unescapeHTML(link), unescapeHTML(desc)))
            }
        }
        return results
    }

    private static func extractTag(_ name: String, from xml: String) -> String {
        guard let r1 = xml.range(of: "<\(name)>"),
              let r2 = xml.range(of: "</\(name)>", range: r1.upperBound..<xml.endIndex)
        else { return "" }
        return String(xml[r1.upperBound..<r2.lowerBound])
    }

    // MARK: - DuckDuckGo HTML（次选，国内可能不可达）

    /// DuckDuckGo 纯 HTML 端点：GET https://html.duckduckgo.com/html/?q=<query>
    /// 结果结构：<a rel="nofollow" class="result__a" href="...">标题</a>
    /// 摘要：<a class="result__snippet" ...>摘要</a>
    private static func duckduckgo(query: String) async -> String? {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        // 提取结果链接 + 标题
        let linkRegex = try? NSRegularExpression(
            pattern: #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )
        let snippetRegex = try? NSRegularExpression(
            pattern: #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )
        guard let linkRegex else { return nil }

        let ns = html as NSString
        let linkMatches = linkRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !linkMatches.isEmpty else { return nil }

        let snippetMatches = snippetRegex.map {
            $0.matches(in: html, range: NSRange(location: 0, length: ns.length))
        } ?? []

        var lines = ["搜索「\(query)」结果:"]
        for (i, m) in linkMatches.prefix(5).enumerated() {
            let rawHref = ns.substring(with: m.range(at: 1))
            let title = unescapeHTML(stripTags(ns.substring(with: m.range(at: 2))))
            let url = decodeDDGRedirect(rawHref)
            var snippet = ""
            if i < snippetMatches.count {
                snippet = unescapeHTML(stripTags(ns.substring(with: snippetMatches[i].range(at: 1))))
                    .replacingOccurrences(of: "\n", with: " ")
            }
            lines.append("- \(title)\n  \(url)\n  \(snippet)")
        }
        return lines.joined(separator: "\n\n")
    }

    /// DDG 结果链接是跳转格式 //duckduckgo.com/l/?uddg=<urlencoded>，还原真实地址
    private static func decodeDDGRedirect(_ href: String) -> String {
        var h = href
        if h.hasPrefix("//") { h = "https:" + h }
        guard let comps = URLComponents(string: h),
              let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value?
                .removingPercentEncoding
        else { return h }
        return uddg
    }

    // MARK: - 维基百科（末选回退）

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

    // MARK: - HTML 工具

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(
            of: #"<[^>]+>"#, with: "", options: .regularExpression
        )
    }

    private static func unescapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
