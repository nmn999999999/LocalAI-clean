package com.localai.app.store

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File

/** 本地模型管理：扫描 Models 目录 + 记住最后使用的模型。 */
object ModelManager {

    data class StoredModel(
        val id: String,
        val name: String,
        val fileName: String,
        val sizeBytes: Long,
        val addedAt: Long,
    )

    private const val PREFS = "localai_settings"
    private const val KEY_LAST_MODEL = "last_used_model_id"

    private lateinit var context: Context

    private val _models = MutableStateFlow<List<StoredModel>>(emptyList())
    val models: StateFlow<List<StoredModel>> = _models

    fun init(context: Context) {
        this.context = context.applicationContext
        scan()
    }

    val modelsDir: File
        get() = File(context.filesDir, "Models").apply { mkdirs() }

    fun scan() {
        val files = modelsDir.listFiles() ?: emptyArray()
        val found = files.filter { f ->
            val ext = f.extension.lowercase()
            ext == "gguf" || ext == "ggml" || ext == "bin"
        }.map { f ->
            StoredModel(
                id = "scan-${f.name}",
                name = f.nameWithoutExtension,
                fileName = f.name,
                sizeBytes = f.length(),
                addedAt = f.lastModified(),
            )
        }
        _models.value = found
    }

    fun fileFor(stored: StoredModel): File = File(modelsDir, stored.fileName)

    fun rememberLastUsed(stored: StoredModel) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_LAST_MODEL, stored.id).apply()
    }

    fun lastUsedModel(): StoredModel? {
        val id = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LAST_MODEL, null) ?: return null
        return _models.value.firstOrNull { it.id == id }
    }

    fun delete(stored: StoredModel) {
        fileFor(stored).delete()
        scan()
    }

    /** 通过 SAF 复制导入模型文件。 */
    fun importFromUri(uri: android.net.Uri, displayName: String?): Boolean {
        return runCatching {
            val resolver = context.contentResolver
            val fileName = displayName
                ?: (resolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
                } ?: "model-${System.currentTimeMillis()}.gguf")
            val dest = File(modelsDir, fileName)
            resolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return false
            scan()
            true
        }.getOrDefault(false)
    }
}
