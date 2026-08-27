package com.localai.app.store

import com.localai.app.data.AIModelInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** 模型下载器：从 HuggingFace 下载 GGUF 到 Models 目录，带进度。 */
object ModelDownloader {

    data class DownloadState(
        val progress: Float = 0f,
        val error: String? = null,
        val isDownloading: Boolean = false,
    )

    private val _downloads = MutableStateFlow<Map<String, DownloadState>>(emptyMap())
    val downloads: StateFlow<Map<String, DownloadState>> = _downloads

    @Volatile
    private var cancelled = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    private val active = mutableMapOf<String, Thread>()

    fun stateFor(id: String): DownloadState =
        _downloads.value[id] ?: DownloadState()

    fun isDownloading(id: String): Boolean = stateFor(id).isDownloading

    /** 下载模型主文件；VL 模型可同时下载 mmproj（存在同目录，自动探测）。 */
    fun download(model: AIModelInfo) {
        if (isDownloading(model.id)) return
        _downloads.update { it + (model.id to DownloadState(isDownloading = true)) }
        cancelled.remove(model.id)
        val t = Thread { downloadTo(model, model.fileName, model.huggingFaceURL, model.id) }
        active[model.id] = t
        t.start()
        // mmproj（VL 模型）
        model.mmprojURL?.let { mmURL ->
            if (!File(ModelManager.modelsDir, model.mmprojFileName!!).exists()) {
                val mmId = "${model.id}-mmproj"
                _downloads.update { it + (mmId to DownloadState(isDownloading = true)) }
                cancelled.remove(mmId)
                val t2 = Thread { downloadTo(model, model.mmprojFileName!!, mmURL, mmId) }
                active[mmId] = t2
                t2.start()
            }
        }
    }

    fun cancel(id: String) {
        cancelled.add(id)
        active.remove(id)?.interrupt()
        _downloads.update { it + (id to DownloadState()) }
    }

    private fun downloadTo(model: AIModelInfo, fileName: String, urlStr: String, stateId: String) {
        val dest = File(ModelManager.modelsDir, fileName)
        val tmp = File(ModelManager.modelsDir, "$fileName.part")
        try {
            if (dest.exists()) {
                _downloads.update { it + (stateId to DownloadState()) }
                ModelManager.scan()
                return
            }
            val conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            conn.setRequestProperty("User-Agent", "LocalAI-Android/1.0")
            conn.instanceFollowRedirects = true
            conn.connect()
            val code = conn.responseCode
            if (code !in 200..399) {
                _downloads.update { it + (stateId to DownloadState(error = "下载失败 (HTTP $code)")) }
                return
            }
            val total = conn.contentLengthLong
            var downloaded = 0L
            conn.inputStream.use { input ->
                tmp.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        if (cancelled.contains(stateId)) {
                            _downloads.update { it + (stateId to DownloadState()) }
                            return
                        }
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        downloaded += n
                        if (total > 0) {
                            val p = (downloaded.toFloat() / total).coerceIn(0f, 1f)
                            _downloads.update { it + (stateId to DownloadState(progress = p, isDownloading = true)) }
                        }
                    }
                }
            }
            if (tmp.length() > 0) {
                tmp.renameTo(dest)
            } else {
                tmp.delete()
                _downloads.update { it + (stateId to DownloadState(error = "下载内容为空")) }
                return
            }
            _downloads.update { it + (stateId to DownloadState()) }
            ModelManager.scan()
        } catch (e: Exception) {
            tmp.delete()
            _downloads.update { it + (stateId to DownloadState(error = "下载失败: ${e.message}")) }
        } finally {
            active.remove(stateId)
        }
    }
}
