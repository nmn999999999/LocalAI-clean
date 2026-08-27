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
