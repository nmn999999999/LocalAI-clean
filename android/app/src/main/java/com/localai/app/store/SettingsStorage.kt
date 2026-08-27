package com.localai.app.store

import android.content.Context
import com.localai.app.data.ModelSettings
import org.json.JSONObject

/** 全局模型参数（持久化到 SharedPreferences）。 */
object SettingsStorage {

    private const val PREFS = "localai_settings"
    private const val KEY = "model_settings_v1"

    lateinit var context: Context
        private set

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    var settings: ModelSettings
        get() {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY, null) ?: return ModelSettings()
            return runCatching {
                val o = JSONObject(raw)
                ModelSettings(
                    temperature = o.optDouble("temperature", 0.7),
                    topP = o.optDouble("topP", 0.9),
                    topK = o.optInt("topK", 40),
                    maxTokens = o.optInt("maxTokens", 2048),
                    contextLength = o.optInt("contextLength", 4096),
                    systemPrompt = o.optString("systemPrompt", "你是一个有帮助的AI助手。请用中文回答。"),
                    gpuLayers = o.optInt("gpuLayers", 0),
                    // 旧存档兼容：曾用 "searxng"（已废弃）一律归一化为 "web"
                    searchEngine = when (o.optString("searchEngine", "web")) {
                        "wikipedia" -> "wikipedia"
                        else -> "web"
                    },
                    searxngURL = o.optString("searxngURL", ""),
                )
            }.getOrElse { ModelSettings() }
        }
        set(value) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val o = JSONObject().apply {
                put("temperature", value.temperature)
                put("topP", value.topP)
                put("topK", value.topK)
                put("maxTokens", value.maxTokens)
                put("contextLength", value.contextLength)
                put("systemPrompt", value.systemPrompt)
                put("gpuLayers", value.gpuLayers)
                put("searchEngine", value.searchEngine)
                put("searxngURL", value.searxngURL)
            }
            prefs.edit().putString(KEY, o.toString()).apply()
        }
}
