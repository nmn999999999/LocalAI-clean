package com.localai.app.llm

import com.localai.app.data.ChatMessage
import com.localai.app.data.MessageRole
import com.localai.app.data.ModelSettings
import com.localai.app.store.SettingsStorage
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

class LLMException(message: String) : Exception(message)

/** 推理服务门面：管理引擎生命周期 + 流式生成。 */
object LLMService {

    sealed class State {
        object Idle : State()
        data class Loading(val name: String) : State()
        data class Ready(val name: String) : State()
        data class Failed(val message: String) : State()
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating

    @Volatile
    private var engine: LlamaEngine? = null

    val isModelReady: Boolean get() = _state.value is State.Ready
    val loadedModelName: String?
        get() = (when (val s = _state.value) {
            is State.Ready -> s.name
            is State.Loading -> s.name
            else -> null
        })

    /** 后台线程加载模型。 */
    fun load(modelPath: String, displayName: String, mmprojPath: String?) {
        if (_state.value is State.Loading) return
        _state.value = State.Loading(displayName)
        Thread {
            val e = LlamaEngine()
            e.create()
            val ok = e.loadModel(
                modelPath,
                mmprojPath,
                SettingsStorage.settings.contextLength,
                SettingsStorage.settings.gpuLayers,
                inferThreads(),
            )
            if (ok) {
                synchronized(this) {
                    engine?.close()
                    engine = e
                }
                _state.value = State.Ready(displayName)
            } else {
                val err = e.lastError()
                e.close()
                _state.value = State.Failed(err)
            }
        }.start()
    }

    /** 推理线程数：按设备 CPU 核心数自适应（4..8）。比写死 4 在多数设备明显提速，封顶 8 避免小核调度开销/发热。 */
    private fun inferThreads(): Int {
        val cores = Runtime.getRuntime().availableProcessors()
        return minOf(cores, 8).coerceAtLeast(4)
    }

    fun unload() {
        stopGeneration()
        synchronized(this) { engine?.close(); engine = null }
        _state.value = State.Idle
    }

    fun stopGeneration() {
        engine?.stop()
    }

    /** 流式对话。collect 端应在 Dispatchers.IO 上运行（nativeChat 为阻塞调用）。 */
    fun streamChat(
        history: List<ChatMessage>,
        settings: ModelSettings,
        imagePaths: List<String> = emptyList(),
    ): Flow<String> = callbackFlow {
        val e = engine ?: run {
            close(LLMException("模型未加载"))
            return@callbackFlow
        }
        val messagesJson = buildMessagesJson(history, settings)
        val settingsJson = JSONObject().apply {
            put("temp", settings.temperature)
            put("top_k", settings.topK)
            put("top_p", settings.topP)
            put("max_tokens", settings.maxTokens)
        }.toString()
        val imagesJson = JSONArray(imagePaths).toString()

        _isGenerating.value = true
        try {
            val rc = e.chat(messagesJson, settingsJson, imagesJson) { piece ->
                trySend(piece)
            }
            if (rc != 0) {
                close(LLMException(e.lastError()))
            } else {
                close()
            }
        } finally {
            _isGenerating.value = false
        }
        awaitClose { }
    }

    private fun buildMessagesJson(
        messages: List<ChatMessage>,
        settings: ModelSettings,
    ): String {
        val arr = JSONArray()
        val hasSystem = messages.any { it.role == MessageRole.SYSTEM }
        if (!hasSystem && settings.systemPrompt.isNotBlank()) {
            arr.put(JSONObject().apply {
                put("role", "system")
                put("content", settings.systemPrompt)
            })
        }
        messages.forEach { m ->
            arr.put(JSONObject().apply {
                put("role", when (m.role) {
                    MessageRole.USER -> "user"
                    MessageRole.ASSISTANT -> "assistant"
                    MessageRole.SYSTEM -> "system"
                    MessageRole.TOOL -> "tool"
                })
                put("content", m.content)
            })
        }
        return arr.toString()
    }
}
