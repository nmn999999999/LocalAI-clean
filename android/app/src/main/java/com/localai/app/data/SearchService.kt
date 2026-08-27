package com.localai.app.data

import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 本地/自托管搜索服务。
 * 优先使用配置的 SearXNG 实例（开源元搜索，https://github.com/searxng/searxng），
 * 失败时自动回退维基百科。
 */
object SearchService {

    suspend fun search(query: String, settings: ModelSettings): String {
        if (settings.searchEngine == "searxng" && settings.searxngURL.isNotBlank()) {
            searxng(query, settings.searxngURL)?.let { return it }
        }
        wikipedia(query)?.let { return it }
        return "未找到与「$query」相关的结果"
    }

    /** SearXNG JSON API：GET {instance}/search?q=...&format=json&language=zh-CN */
    private suspend fun searxng(query: String, instance: String): String? = runCatching {
        val base = instance.trim().trimEnd('/')
        val url = "$base/search?q=${URLEncoder.encode(query, "UTF-8")}&format=json&language=zh-CN"
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 12000
        conn.readTimeout = 12000
        conn.setRequestProperty("User-Agent", "LocalAI-Android/1.0")
        val body = conn.inputStream.bufferedReader().readText()
        val obj = org.json.JSONObject(body)
        val results = obj.optJSONArray("results") ?: return@runCatching null
        if (results.length() == 0) return@runCatching null
        val lines = mutableListOf("搜索「$query」结果:")
        for (i in 0 until minOf(5, results.length())) {
            val r = results.getJSONObject(i)
            val title = r.optString("title")
            val url = r.optString("url")
            val content = r.optString("content").replace("\n", " ").take(200)
            lines.add("- $title\n  $url\n  $content")
        }
        lines.joinToString("\n\n")
    }.getOrNull()

    /** 回退：维基百科 opensearch API */
    private suspend fun wikipedia(query: String): String? = runCatching {
        val url = "https://zh.wikipedia.org/w/api.php?action=opensearch&format=json&limit=3&search=${URLEncoder.encode(query, "UTF-8")}"
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 10000
        conn.readTimeout = 10000
        conn.setRequestProperty("User-Agent", "LocalAI-Android/1.0")
        val body = conn.inputStream.bufferedReader().readText()
        val arr = JSONArray(body)
        val titles = arr.optJSONArray(1) ?: return@runCatching null
        val urls = arr.optJSONArray(3)
        if (titles.length() == 0) return@runCatching null
        (0 until titles.length()).joinToString("\n") { i ->
            "${i + 1}. ${titles.getString(i)}\n   ${urls?.optString(i) ?: ""}"
        }
    }.getOrNull()
}
