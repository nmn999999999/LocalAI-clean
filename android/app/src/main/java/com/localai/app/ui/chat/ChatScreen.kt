package com.localai.app.ui.chat

import android.content.Context
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.localai.app.agent.AgentService
import com.localai.app.data.ChatMessage
import com.localai.app.data.MessageRole
import com.localai.app.data.ThinkParser
import com.localai.app.data.ToolCall
import com.localai.app.llm.LLMService
import com.localai.app.store.ChatStore
import com.localai.app.store.ModelManager
import com.localai.app.store.SettingsStorage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

@Composable
fun ChatScreen(modifier: Modifier = Modifier) {
    val conversations by ChatStore.conversations.collectAsState()
    val currentId by ChatStore.currentId.collectAsState()
    val current = remember(conversations, currentId) { ChatStore.current }
    val state by LLMService.state.collectAsState()
    val isGenerating by LLMService.isGenerating.collectAsState()
    val agentSteps by AgentService.steps.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var input by remember { mutableStateOf("") }
    var isAgentMode by remember { mutableStateOf(false) }
    var attachments by remember { mutableStateOf<List<ByteArray>>(emptyList()) }
    var generatingJob by remember { mutableStateOf<Job?>(null) }

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes != null) {
                val compressed = compressImage(bytes)
                if (compressed != null) attachments = attachments + compressed
            }
        }
    }

    LaunchedEffect(Unit) {
        if (state is LLMService.State.Idle) {
            val stored = ModelManager.lastUsedModel()
            if (stored != null && ModelManager.fileFor(stored).exists()) {
                val mmproj = detectMMProj(nextTo = ModelManager.fileFor(stored).absolutePath)
                LLMService.load(ModelManager.fileFor(stored).absolutePath, stored.name, mmproj)
            }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        MessageList(
            messages = current.messages,
            isGenerating = isGenerating,
            modifier = Modifier.weight(1f),
        )
        if (LLMService.isModelReady && agentSteps.isNotEmpty()) {
            AgentStepsBar(agentSteps)
        }
        InputBar(
            input = input,
            onInputChange = { input = it },
            canSend = LLMService.isModelReady && (input.isNotBlank() || attachments.isNotEmpty()) && !isGenerating,
            isGenerating = isGenerating,
            isAgentMode = isAgentMode,
            attachments = attachments,
            onToggleAgent = { isAgentMode = !isAgentMode },
            onPickImage = {
                imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
            onRemoveAttachment = { idx -> attachments = attachments.filterIndexed { i, _ -> i != idx } },
            onSend = {
                val text = input.trim()
                if (text.isEmpty() && attachments.isEmpty()) return@InputBar
                val settings = SettingsStorage.settings
                val images = attachments

                val conv = ChatStore.current
                conv.messages.add(ChatMessage(role = MessageRole.USER, content = text, images = images))
                conv.updateTitle()
                // 历史快照：agent 模式不插入占位气泡（由 sink 逐轮建气泡）；普通模式先插一条占位气泡逐字流式。
                val history: List<ChatMessage>
                val assistantMsg: ChatMessage?
                if (isAgentMode) {
                    assistantMsg = null
                    history = ArrayList(conv.messages)
                } else {
                    val m = ChatMessage(role = MessageRole.ASSISTANT, content = "", isStreaming = true)
                    conv.messages.add(m)
                    assistantMsg = m
                    history = conv.messages.filter { it.id != m.id }
                }
                conv.modelName = LLMService.loadedModelName
                ChatStore.upsert(conv)
                input = ""
                attachments = emptyList()

                // 图片写入临时文件供引擎读取
                val imagePaths = images.mapIndexed { i, bytes ->
                    val f = File(context.cacheDir, "img-$i-${UUID.randomUUID().toString().take(8)}.jpg")
                    f.writeBytes(bytes)
                    f.absolutePath
                }

                generatingJob = scope.launch(Dispatchers.IO) {
                    try {
                        if (isAgentMode) {
                            // 流式 sink：每一轮迭代实时建气泡 / 追加 token / 挂工具调用 / 结束。
                            // 气泡直接透传原始 token（含 <think> 标签），MessageBubble 自动解析思考流与正文流。
                            val sink = object : AgentService.AgentSink {
                                override suspend fun beginIteration(): ChatMessage {
                                    val m = ChatMessage(role = MessageRole.ASSISTANT, content = "", isStreaming = true, isAgentRound = true)
                                    withContext(Dispatchers.Main) {
                                        conv.messages.add(m)
                                        ChatStore.upsert(conv)
                                    }
                                    return m
                                }

                                override suspend fun appendToken(message: ChatMessage, token: String) {
                                    withContext(Dispatchers.Main) {
                                        val idx = conv.messages.indexOfFirst { it.id == message.id }
                                        if (idx >= 0) {
                                            conv.messages[idx].content += token
                                            ChatStore.upsert(conv)
                                        }
                                    }
                                }

                                override suspend fun attachToolCall(message: ChatMessage, call: ToolCall) {
                                    withContext(Dispatchers.Main) {
                                        val idx = conv.messages.indexOfFirst { it.id == message.id }
                                        if (idx >= 0) {
                                            conv.messages[idx].toolCalls = conv.messages[idx].toolCalls + call
                                            ChatStore.upsert(conv)
                                        }
                                    }
                                }

                                override suspend fun endIteration(message: ChatMessage) {
                                    withContext(Dispatchers.Main) {
                                        val idx = conv.messages.indexOfFirst { it.id == message.id }
                                        if (idx >= 0) {
                                            conv.messages[idx].isStreaming = false
                                            ChatStore.upsert(conv)
                                        }
                                    }
                                }
                            }
                            AgentService.run(history, settings, sink)
                        } else {
                            val sb = StringBuilder()
                            LLMService.streamChat(history, settings, imagePaths).collect { token ->
                                sb.append(token)
                                withContext(Dispatchers.Main) {
                                    assistantMsg?.content = sb.toString()
                                    ChatStore.upsert(conv)
                                }
                            }
                            withContext(Dispatchers.Main) {
                                assistantMsg?.isStreaming = false
                                ChatStore.upsert(conv)
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            assistantMsg?.isStreaming = false
                            ChatStore.upsert(conv)
                        }
                    } finally {
                        imagePaths.forEach { File(it).delete() }
                    }
                }
            },
            onStop = {
                LLMService.stopGeneration()
                generatingJob?.cancel()
                val conv = ChatStore.current
                conv.messages.lastOrNull()?.let { it.isStreaming = false }
                ChatStore.upsert(conv)
            },
        )
    }
}

// MARK: - 消息列表

@Composable
private fun MessageList(
    messages: List<ChatMessage>,
    isGenerating: Boolean,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(messages.size, messages.lastOrNull()?.content?.length) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }
    LazyColumn(
        state = listState,
        modifier = modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(messages, key = { it.id }) { message ->
            MessageBubble(message)
        }
    }
}

@Composable
private fun MessageBubble(message: ChatMessage) {
    val isUser = message.role == MessageRole.USER
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 320.dp),
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
        ) {
            if (isUser) {
                if (message.images.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        message.images.forEach { bytes ->
                            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            if (bmp != null) {
                                Image(
                                    bitmap = bmp.asImageBitmap(),
                                    contentDescription = "图片",
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(96.dp)
                                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp)),
                                )
                            }
                        }
                    }
                }
                if (message.content.isNotEmpty()) {
                    Surface(
                        color = MaterialTheme.colorScheme.primary,
                        shape = RoundedCornerShape(18.dp, 18.dp, 4.dp, 18.dp),
                    ) {
                        Text(
                            text = message.content,
                            color = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        )
                    }
                }
            } else {
                message.toolCalls.forEach { call ->
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = "🔧 工具调用: ${call.name}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                        call.result?.let { r ->
                            val preview = r.lineSequence().firstOrNull()?.take(80) ?: r.take(80)
                            Text(
                                text = "→ $preview",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                val think = ThinkParser.thinkContent(message.content)
                if (!think.isNullOrEmpty()) {
                    ThinkSection(think = think, isThinking = ThinkParser.isThinking(message.content))
                }
                val visible = ThinkParser.visibleContent(message.content)
                val displayText = if (message.isAgentRound) AgentService.cleanDisplayText(visible) else visible
                if (displayText.isNotEmpty()) {
                    Text(text = displayText, style = MaterialTheme.typography.bodyMedium)
                } else if (message.isStreaming) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.padding(4.dp))
                        Text(
                            "思考中…",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ThinkSection(think: String, isThinking: Boolean) {
    var expanded by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            TextButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("🧠", style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.padding(4.dp))
                    Text(
                        text = if (isThinking) "思考中" else "已深度思考",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    Spacer(Modifier.weight(1f))
                    if (isThinking) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                    } else {
                        Text(if (expanded) "▲" else "▼", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            if (expanded) {
                Text(
                    text = think,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
        }
    }
}

// MARK: - Agent 步骤条

@Composable
private fun AgentStepsBar(steps: List<AgentService.Step>) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        steps.takeLast(6).forEach { step ->
            Surface(
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = when (step.kind) {
                            AgentService.Step.Kind.THINKING -> "🧠"
                            AgentService.Step.Kind.EXECUTING -> "⚙️"
                            AgentService.Step.Kind.RESULT -> "✅"
                            AgentService.Step.Kind.FINAL_ANSWER -> "💬"
                        },
                        style = MaterialTheme.typography.labelSmall,
                    )
                    Spacer(Modifier.padding(2.dp))
                    Text(text = step.detail, style = MaterialTheme.typography.labelSmall, maxLines = 1)
                }
            }
        }
    }
}

// MARK: - 输入栏

@Composable
private fun InputBar(
    input: String,
    onInputChange: (String) -> Unit,
    canSend: Boolean,
    isGenerating: Boolean,
    isAgentMode: Boolean,
    attachments: List<ByteArray>,
    onToggleAgent: () -> Unit,
    onPickImage: () -> Unit,
    onRemoveAttachment: (Int) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
) {
    Surface(tonalElevation = 3.dp) {
        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
            if (attachments.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    attachments.forEachIndexed { idx, bytes ->
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        if (bmp != null) {
                            androidx.compose.foundation.layout.Box {
                                Image(
                                    bitmap = bmp.asImageBitmap(),
                                    contentDescription = "已选图片",
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(56.dp)
                                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
                                        .clickable { onRemoveAttachment(idx) },
                                )
                                Icon(
                                    Icons.Filled.Close,
                                    contentDescription = "移除",
                                    tint = Color.White,
                                    modifier = Modifier
                                        .align(Alignment.TopEnd)
                                        .background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                                        .padding(2.dp)
                                        .size(14.dp),
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.padding(4.dp))
            }
            Row(verticalAlignment = Alignment.Bottom) {
                IconButton(onClick = onToggleAgent) {
                    Icon(
                        imageVector = if (isAgentMode) Icons.Filled.Bolt else Icons.Filled.Terminal,
                        contentDescription = "Agent 模式",
                        tint = if (isAgentMode) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onPickImage) {
                    Icon(
                        Icons.Filled.Image,
                        contentDescription = "选择图片",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedTextField(
                    value = input,
                    onValueChange = onInputChange,
                    placeholder = { Text("输入消息…") },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(24.dp),
                    maxLines = 5,
                )
                Spacer(Modifier.padding(4.dp))
                IconButton(onClick = if (isGenerating) onStop else onSend, enabled = isGenerating || canSend) {
                    Icon(
                        imageVector = if (isGenerating) Icons.Filled.Stop else Icons.AutoMirrored.Filled.Send,
                        contentDescription = if (isGenerating) "停止" else "发送",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }
}

// MARK: - 工具

/** 压缩图片到最长边 1024，JPEG 0.85（对齐 iOS 行为）。 */
private fun compressImage(bytes: ByteArray): ByteArray? {
    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    val scale = minOf(1f, 1024f / maxOf(bmp.width, bmp.height))
    val w = (bmp.width * scale).toInt().coerceAtLeast(1)
    val h = (bmp.height * scale).toInt().coerceAtLeast(1)
    val scaled = android.graphics.Bitmap.createScaledBitmap(bmp, w, h, true)
    val out = java.io.ByteArrayOutputStream()
    scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
    if (scaled != bmp) scaled.recycle()
    bmp.recycle()
    return out.toByteArray()
}

private fun detectMMProj(nextTo: String): String? {
    val dir = File(nextTo).parentFile ?: return null
    return dir.listFiles()?.firstOrNull {
        it.extension.lowercase() == "gguf" && it.name.lowercase().contains("mmproj")
    }?.absolutePath
}
