package com.localai.app.store

import android.content.Context
import com.localai.app.data.ChatMessage
import com.localai.app.data.MessageRole
import com.localai.app.data.ToolCall
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class Conversation(
    val id: String,
    var title: String = "新对话",
    val messages: MutableList<ChatMessage> = mutableListOf(),
    val createdAt: Long = System.currentTimeMillis(),
    var updatedAt: Long = System.currentTimeMillis(),
    var modelName: String? = null,
) {
    fun updateTitle() {
        messages.firstOrNull { it.role == MessageRole.USER }?.let {
            title = it.content.take(30)
        }
    }
}

/** 对话存储（内存 StateFlow + JSON 持久化）。 */
object ChatStore {

    private lateinit var context: Context

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations

    private val _currentId = MutableStateFlow<String?>(null)
    val currentId: StateFlow<String?> = _currentId

    private var saveTask: Thread? = null

    private val file: File
        get() = File(context.filesDir, "conversations.json")

    fun init(context: Context) {
        this.context = context.applicationContext
        load()
        if (_conversations.value.isEmpty()) {
            createNew()
        }
    }

    val current: Conversation
        get() = _conversations.value.firstOrNull { it.id == _currentId.value }
            ?: _conversations.value.firstOrNull()
            ?: createNew()

    fun conversation(id: String): Conversation? =
        _conversations.value.firstOrNull { it.id == id }

    fun createNew(): Conversation {
        val conv = Conversation(id = java.util.UUID.randomUUID().toString())
        _conversations.update { listOf(conv) + it }
        _currentId.value = conv.id
        scheduleSave()
        return conv
    }

    fun upsert(conv: Conversation) {
        _conversations.update { list ->
            if (list.any { it.id == conv.id }) {
                list.map { if (it.id == conv.id) conv else it }
            } else {
                listOf(conv) + list
            }
        }
        _currentId.value = conv.id
        scheduleSave()
    }

    fun delete(id: String) {
        _conversations.update { list -> list.filterNot { it.id == id } }
        if (_currentId.value == id) {
            _currentId.value = _conversations.value.firstOrNull()?.id
        }
        if (_conversations.value.isEmpty()) createNew()
        scheduleSave()
    }

    fun deleteAll() {
        _conversations.value = emptyList()
        createNew()
    }

    // MARK: - 持久化

    private fun scheduleSave() {
        // 流式生成中的中间状态不落盘（每 token 触发一次 upsert，避免频繁写大文件）
        if (_conversations.value.lastOrNull()?.messages?.lastOrNull()?.isStreaming == true) return
        saveTask?.interrupt()
        saveTask = Thread {
            try {
                Thread.sleep(400)
            } catch (_: InterruptedException) {
                return@Thread
            }
            persist()
        }.apply { start() }
    }

    private fun persist() {
        val arr = JSONArray()
        _conversations.value.forEach { conv ->
            val msgs = JSONArray()
            conv.messages.forEach { m ->
                val o = JSONObject().apply {
                    put("id", m.id)
                    put("role", m.role.name)
                    put("content", m.content)
                    put("timestamp", m.timestamp)
                    put("isStreaming", m.isStreaming)
                    val imgs = JSONArray()
                    m.images.forEach { bytes ->
                        imgs.put(java.util.Base64.getEncoder().encodeToString(bytes))
                    }
                    put("images", imgs)
                    val calls = JSONArray()
                    m.toolCalls.forEach { tc ->
                        calls.put(JSONObject().apply {
                            put("id", tc.id)
                            put("name", tc.name)
                            put("arguments", tc.arguments)
                            put("result", tc.result ?: "")
                        })
                    }
                    put("toolCalls", calls)
                }
                msgs.put(o)
            }
            arr.put(JSONObject().apply {
                put("id", conv.id)
                put("title", conv.title)
                put("createdAt", conv.createdAt)
                put("updatedAt", conv.updatedAt)
                put("modelName", conv.modelName ?: "")
                put("messages", msgs)
            })
        }
        runCatching { file.writeText(arr.toString()) }
    }

    private fun load() {
        val raw = runCatching { file.readText() }.getOrNull() ?: return
        runCatching {
            val arr = JSONArray(raw)
            val list = (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                val msgsArr = o.optJSONArray("messages") ?: JSONArray()
                val msgs = (0 until msgsArr.length()).map { j ->
                    val mo = msgsArr.getJSONObject(j)
                    val imgsArr = mo.optJSONArray("images") ?: JSONArray()
                    val imgs = (0 until imgsArr.length()).mapNotNull { k ->
                        java.util.Base64.getDecoder().decode(imgsArr.getString(k))
                    }
                    val callsArr = mo.optJSONArray("toolCalls") ?: JSONArray()
                    val calls = (0 until callsArr.length()).map { k ->
                        val co = callsArr.getJSONObject(k)
                        ToolCall(
                            id = co.optString("id"),
                            name = co.optString("name"),
                            arguments = co.optString("arguments"),
                            result = co.optString("result").ifEmpty { null },
                        )
                    }
                    ChatMessage(
                        id = mo.optString("id"),
                        role = MessageRole.valueOf(mo.optString("role", "USER")),
                        content = mo.optString("content"),
                        timestamp = mo.optLong("timestamp"),
                        isStreaming = mo.optBoolean("isStreaming"),
                        images = imgs,
                        toolCalls = calls,
                    )
                }.toMutableList()
                // 复位遗留的流式标记：磁盘里不该有"正在生成"的消息。
                // 若残留 isStreaming == true（旧版 Agent 会话未正确收尾），
                // 会让 scheduleSave 守卫误判、导致整段对话永不落盘。
                msgs.forEach { it.isStreaming = false }
                Conversation(
                    id = o.optString("id"),
                    title = o.optString("title", "新对话"),
                    messages = msgs,
                    createdAt = o.optLong("createdAt"),
                    updatedAt = o.optLong("updatedAt"),
                    modelName = o.optString("modelName").ifEmpty { null },
                )
            }
            _conversations.value = list
            _currentId.value = list.firstOrNull()?.id
        }
    }
}
