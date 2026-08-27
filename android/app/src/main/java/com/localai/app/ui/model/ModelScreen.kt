package com.localai.app.ui.model

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.localai.app.data.AIModelInfo
import com.localai.app.llm.LLMService
import com.localai.app.store.ModelDownloader
import com.localai.app.store.ModelManager
import java.text.SimpleDateFormat
import java.util.Locale

@Composable
fun ModelScreen(modifier: Modifier = Modifier) {
    val models by ModelManager.models.collectAsState()
    val state by LLMService.state.collectAsState()
    val downloads by ModelDownloader.downloads.collectAsState()

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) ModelManager.importFromUri(uri, null)
    }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text("模型", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        }

        item { LoadStatusCard(state) }

        item {
            OutlinedButton(onClick = { ModelManager.scan() }, modifier = Modifier.fillMaxWidth()) {
                Text("扫描本地模型文件")
            }
        }
        item {
            Button(onClick = { importLauncher.launch(arrayOf("application/octet-stream")) }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.padding(4.dp))
                Text("从文件导入 GGUF 模型")
            }
        }

        item {
            Text(
                "在线模型（HuggingFace）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        items(AIModelInfo.catalog, key = { it.id }) { info ->
            OnlineModelRow(info, downloads[info.id], models)
        }

        item {
            Text(
                "本地模型（${models.size} 个）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        items(models, key = { it.id }) { stored ->
            LocalModelRow(stored, state)
        }
    }
}

@Composable
private fun LoadStatusCard(state: LLMService.State) {
    when (state) {
        is LLMService.State.Loading -> {
            Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
                Row(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 10.dp))
                    Text("正在加载模型: ${state.name}…")
                }
            }
        }
        is LLMService.State.Ready -> {
            Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.primaryContainer) {
                Row(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Memory, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                    Spacer(Modifier.padding(6.dp))
                    Text(
                        "已加载: ${state.name}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
        is LLMService.State.Failed -> {
            Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.errorContainer) {
                Text(
                    "加载失败: ${state.message}",
                    modifier = Modifier.padding(12.dp),
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        else -> {}
    }
}

@Composable
private fun OnlineModelRow(
    info: AIModelInfo,
    download: ModelDownloader.DownloadState?,
    localModels: List<ModelManager.StoredModel>,
) {
    val isDownloaded = localModels.any { it.fileName == info.fileName }
    val downloading = download?.isDownloading == true

    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(info.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                    Text(
                        "${info.sizeDescription} · ${info.description}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (isDownloaded) {
                    Text("已下载", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                } else if (downloading) {
                    IconButton(onClick = { ModelDownloader.cancel(info.id) }) {
                        Icon(Icons.Filled.Close, contentDescription = "取消", tint = MaterialTheme.colorScheme.error)
                    }
                } else {
                    IconButton(onClick = { ModelDownloader.download(info) }) {
                        Icon(Icons.Filled.Download, contentDescription = "下载")
                    }
                }
            }
            if (downloading && download != null) {
                Spacer(Modifier.padding(4.dp))
                LinearProgressIndicator(
                    progress = { download.progress },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "下载中 ${(download.progress * 100).toInt()}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            download?.error?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun LocalModelRow(stored: ModelManager.StoredModel, state: LLMService.State) {
    val isLoaded = state is LLMService.State.Ready && state.name == stored.name
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = if (isLoaded) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(stored.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(
                    "${formatSize(stored.sizeBytes)} · ${SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).format(java.util.Date(stored.addedAt))}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (isLoaded) {
                Text("已加载", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            } else {
                TextButton(onClick = {
                    val mmproj = detectMMProjNextTo(stored)
                    LLMService.load(ModelManager.fileFor(stored).absolutePath, stored.name, mmproj)
                    ModelManager.rememberLastUsed(stored)
                }) { Text("加载") }
            }
            IconButton(onClick = { ModelManager.delete(stored) }) {
                Icon(Icons.Filled.Delete, contentDescription = "删除", tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun detectMMProjNextTo(stored: ModelManager.StoredModel): String? {
    val dir = ModelManager.fileFor(stored).parentFile ?: return null
    return dir.listFiles()?.firstOrNull {
        it.extension.lowercase() == "gguf" && it.name.lowercase().contains("mmproj")
    }?.absolutePath
}

private fun formatSize(bytes: Long): String {
    if (bytes < 1024 * 1024) return "${bytes / 1024} KB"
    return String.format(Locale.CHINA, "%.1f GB", bytes / 1024.0 / 1024.0 / 1024.0)
}
