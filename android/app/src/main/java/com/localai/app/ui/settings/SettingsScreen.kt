package com.localai.app.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.localai.app.data.ModelSettings
import com.localai.app.store.ChatStore
import com.localai.app.store.SettingsStorage
import com.localai.app.llm.LLMService

@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    var settings by remember { mutableStateOf(SettingsStorage.settings) }
    val conversations by ChatStore.conversations.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("设置", style = MaterialTheme.typography.headlineSmall, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("生成参数", style = MaterialTheme.typography.titleSmall)

                SliderRow("温度", settings.temperature, 0.0..1.5) { settings = settings.copy(temperature = it) }
                SliderRow("Top-P", settings.topP, 0.1..1.0) { settings = settings.copy(topP = it) }
                StepperRow("Top-K", settings.topK, 1..100, 5) { settings = settings.copy(topK = it) }
                StepperRow("最大生成 Token", settings.maxTokens, 256..8192, 256) { settings = settings.copy(maxTokens = it) }
                StepperRow("上下文长度", settings.contextLength, 1024..32768, 1024) { settings = settings.copy(contextLength = it) }
                StepperRow("GPU 层数 (0=纯CPU)", settings.gpuLayers, 0..99, 8) { settings = settings.copy(gpuLayers = it) }

                Text(
                    "参数在下次对话/加载时生效。Android 上默认纯 CPU 最稳定；调高 GPU 层数可加速（需重新加载模型）。",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = {
                    SettingsStorage.settings = settings
                    LLMService.unload()
                }, modifier = Modifier.fillMaxWidth()) {
                    Text("保存并重载模型")
                }
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("系统提示词", style = MaterialTheme.typography.titleSmall)
                var prompt by remember { mutableStateOf(settings.systemPrompt) }
                OutlinedTextField(
                    value = prompt,
                    onValueChange = { prompt = it; settings = settings.copy(systemPrompt = it) },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("搜索服务", style = MaterialTheme.typography.titleSmall)

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("搜索引擎", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    androidx.compose.material3.FilterChip(
                        selected = settings.searchEngine != "wikipedia",
                        onClick = { settings = settings.copy(searchEngine = "web") },
                        label = { Text("网页搜索（内置）") },
                    )
                    Spacer(Modifier.padding(4.dp))
                    androidx.compose.material3.FilterChip(
                        selected = settings.searchEngine == "wikipedia",
                        onClick = { settings = settings.copy(searchEngine = "wikipedia") },
                        label = { Text("维基百科（内置）") },
                    )
                }

                Text(
                    "供 Agent 的 web_search 工具使用。网页搜索由设备直接请求 Bing（失败时依次回退 DuckDuckGo、维基百科），无需自建任何服务。",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("SSH 连接", style = MaterialTheme.typography.titleSmall)

                var host by remember { mutableStateOf(settings.sshHost) }
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it; settings = settings.copy(sshHost = it) },
                    label = { Text("主机") },
                    modifier = Modifier.fillMaxWidth(),
                )

                var portText by remember { mutableStateOf(settings.sshPort.toString()) }
                OutlinedTextField(
                    value = portText,
                    onValueChange = {
                        portText = it
                        settings = settings.copy(sshPort = it.toIntOrNull() ?: 22)
                    },
                    label = { Text("端口") },
                    modifier = Modifier.fillMaxWidth(),
                )

                var user by remember { mutableStateOf(settings.sshUser) }
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it; settings = settings.copy(sshUser = it) },
                    label = { Text("用户名") },
                    modifier = Modifier.fillMaxWidth(),
                )

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("认证方式", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    androidx.compose.material3.FilterChip(
                        selected = settings.sshAuthType != "key",
                        onClick = { settings = settings.copy(sshAuthType = "password") },
                        label = { Text("密码") },
                    )
                    Spacer(Modifier.padding(4.dp))
                    androidx.compose.material3.FilterChip(
                        selected = settings.sshAuthType == "key",
                        onClick = { settings = settings.copy(sshAuthType = "key") },
                        label = { Text("私钥") },
                    )
                }

                if (settings.sshAuthType == "key") {
                    var keyText by remember { mutableStateOf(settings.sshPrivateKey) }
                    OutlinedTextField(
                        value = keyText,
                        onValueChange = { keyText = it; settings = settings.copy(sshPrivateKey = it) },
                        label = { Text("私钥 (PEM)") },
                        minLines = 4,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    var sf by remember { mutableStateOf(settings.sshPassphrase) }
                    OutlinedTextField(
                        value = sf,
                        onValueChange = { sf = it; settings = settings.copy(sshPassphrase = it) },
                        label = { Text("私钥口令（可选）") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    var pw by remember { mutableStateOf(settings.sshPassword) }
                    OutlinedTextField(
                        value = pw,
                        onValueChange = { pw = it; settings = settings.copy(sshPassword = it) },
                        label = { Text("密码") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                Button(onClick = { SettingsStorage.settings = settings }, modifier = Modifier.fillMaxWidth()) {
                    Text("保存 SSH 配置")
                }

                Text(
                    "供 Agent 的 ssh 工具使用：在对话中让 AI「在服务器上执行 xxx」即可。账号信息仅存于本机，私钥不会上传。工具参数可临时覆盖主机/端口/用户/命令。",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("内存优化", style = MaterialTheme.typography.titleSmall)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("内存映射加载 (mmap)", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            "开启后模型文件映射到虚拟内存，仅访问的页面才加载到RAM，大幅减少内存占用。",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    androidx.compose.material3.Switch(
                        checked = settings.useMmap,
                        onCheckedChange = { settings = settings.copy(useMmap = it) },
                    )
                }
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("关于", style = MaterialTheme.typography.titleSmall)
                Text("推理引擎: llama.cpp (GGUF) + mtmd 多模态", style = MaterialTheme.typography.bodySmall)
                Text("界面: Kotlin + Jetpack Compose", style = MaterialTheme.typography.bodySmall)
                Text("隐私: 全部推理在本机完成", style = MaterialTheme.typography.bodySmall)
            }
        }

        Card {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("数据管理", style = MaterialTheme.typography.titleSmall)
                OutlinedButton(
                    onClick = { ChatStore.deleteAll() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("删除全部对话记录（${conversations.size} 个）")
                }
            }
        }
    }
}

@Composable
private fun SliderRow(title: String, value: Double, range: ClosedFloatingPointRange<Double>, onChange: (Double) -> Unit) {
    Column {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(String.format("%.2f", value), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(
            value = value.toFloat().coerceIn(range.start.toFloat(), range.endInclusive.toFloat()),
            onValueChange = { onChange(it.toDouble()) },
            valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
        )
    }
}

@Composable
private fun StepperRow(
    title: String,
    value: Int,
    range: IntRange,
    step: Int,
    onChange: (Int) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = { onChange((value - step).coerceAtLeast(range.first)) }) { Text("-") }
        Text("$value", modifier = Modifier.padding(horizontal = 10.dp))
        OutlinedButton(onClick = { onChange((value + step).coerceAtMost(range.last)) }) { Text("+") }
    }
}
