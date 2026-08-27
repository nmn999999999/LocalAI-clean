package com.localai.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * 本地网络搜索：设备直接请求公共搜索引擎，无需自建任何服务。
 * 链路：Bing RSS（国内可达、免密钥、结构化输出）→ DuckDuckGo HTML → 维基百科。
 */
object SearchService {

    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

    suspend fun search(query: String, settings: ModelSettings): String {
        if (settings.searchEngine != "wikipedia") {
            bing(query)?.let { return it }
            duckduckgo(query)?.let { return it }
        }
        wikipedia(query)?.let { return it }
        return "未找到与「$query」相关的结果"
    }

    /** Bing 搜索的 RSS 输出：GET https://cn.bing.com/search?q=<q>&format=rss */
    private suspend fun bing(query: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val url = "https://cn.bing.com/search?q=${URLEncoder.encode(query, "UTF-8")}&format=rss&count=8"
            val xml = httpGet(url) ?: return@runCatching null
            val items = parseRss(xml)
            if (items.isEmpty()) return@runCatching null
            val lines = mutableListOf("搜索「$query」结果:")
            items.take(5).forEach { (title, link, snippet) ->
                lines.add("- $title\n  $link\n  ${snippet.replace("\n", " ")}")
            }
            lines.joinToString("\n\n")
        }.getOrNull()
    }

    private fun parseRss(xml: String): List<Triple<String, String, String>> {
        val items = mutableListOf<Triple<String, String, String>>()
        val itemRegex = Regex("<item>(.*?)</item>", RegexOption.DOT_MATCHES_ALL)
        for (m in itemRegex.findAll(xml)) {
            val block = m.groupValues[1]
            val title = extractTag("title", block)
            val link = extractTag("link", block)
            val desc = extractTag("description", block)
            if (title.isNotEmpty()) {
                items.add(Triple(unescapeHtml(title), unescapeHtml(link), unescapeHtml(desc)))
            }
        }
        return items
    }

    private fun extractTag(name: String, xml: String): String {
        val m = Regex("<$name>(.*?)</$name>", RegexOption.DOT_MATCHES_ALL).find(xml) ?: return ""
        return m.groupValues[1]
    }

    /** DuckDuckGo 纯 HTML 端点（国内可能不可达，作回退） */
    private suspend fun duckduckgo(query: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val url = "https://html.duckduckgo.com/html/?q=${URLEncoder.encode(query, "UTF-8")}"
            val html = httpGet(url) ?: return@runCatching null
            val linkRegex = Regex("""<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
            val snippetRegex = Regex("""<a[^>]*class="result__snippet"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
            val links = linkRegex.findAll(html).toList()
            if (links.isEmpty()) return@runCatching null
            val snippets = snippetRegex.findAll(html).toList()
            val lines = mutableListOf("搜索「$query」结果:")
            links.take(5).forEachIndexed { i, m ->
                val title = unescapeHtml(stripTags(m.groupValues[2]))
                val realUrl = decodeDdgRedirect(m.groupValues[1])
                val snippet = if (i < snippets.size) {
                    unescapeHtml(stripTags(snippets[i].groupValues[1])).replace("\n", " ")
                } else ""
                lines.add("- $title\n  $realUrl\n  $snippet")
            }
            lines.joinToString("\n\n")
        }.getOrNull()
    }

    /** DDG 结果链接是跳转格式 //duckduckgo.com/l/?uddg=<urlencoded>，还原真实地址 */
    private fun decodeDdgRedirect(href: String): String {
        var h = href
        if (h.startsWith("//")) h = "https:$h"
        val uddg = Regex("[?&]uddg=([^&]+)").find(h)?.groupValues?.get(1) ?: return h
        return runCatching { URLDecoder.decode(uddg, "UTF-8") }.getOrDefault(h)
    }

    /** 回退：维基百科 opensearch API */
    private suspend fun wikipedia(query: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val url = "https://zh.wikipedia.org/w/api.php?action=opensearch&format=json&limit=3&search=${URLEncoder.encode(query, "UTF-8")}"
            val body = httpGet(url) ?: return@runCatching null
            val arr = JSONArray(body)
            val titles = arr.optJSONArray(1) ?: return@runCatching null
            val urls = arr.optJSONArray(3)
            if (titles.length() == 0) return@runCatching null
            (0 until titles.length()).joinToString("\n") { i ->
                "${i + 1}. ${titles.getString(i)}\n   ${urls?.optString(i) ?: ""}"
            }
        }.getOrNull()
    }

    // MARK: - HTTP / HTML 工具

    private fun httpGet(url: String, timeoutMs: Int = 12000): String? = runCatching {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = timeoutMs
        conn.readTimeout = timeoutMs
        conn.setRequestProperty("User-Agent", USER_AGENT)
        conn.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        if (conn.responseCode != 200) return@runCatching null
        conn.inputStream.bufferedReader().use { it.readText() }
    }.getOrNull()

    private fun stripTags(html: String): String =
        html.replace(Regex("<[^>]+>"), "")

    private fun unescapeHtml(s: String): String = s
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
}
