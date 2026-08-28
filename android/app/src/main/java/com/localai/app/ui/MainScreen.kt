package com.localai.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.localai.app.data.AIModelInfo
import com.localai.app.llm.LLMService
import com.localai.app.store.ModelDownloader
import com.localai.app.store.ModelManager
import com.localai.app.ui.chat.ChatScreen
import com.localai.app.ui.model.ModelScreen
import com.localai.app.ui.settings.SettingsScreen

enum class MainTab(val label: String) {
    Chat("聊天"),
    Models("模型"),
    Settings("设置"),
}

@Composable
fun MainScreen() {
    var selectedTab by rememberSaveable { mutableStateOf(MainTab.Chat) }
    val downloads by ModelDownloader.downloads.collectAsState()
    val localModels by ModelManager.models.collectAsState()
    var autoLoaded by remember { mutableStateOf(false) }

    // 首启：本地无模型且未用过 → 自动下载默认模型（与 iOS 一致）
    LaunchedEffect(Unit) {
        if (ModelManager.models.value.isEmpty() && ModelManager.lastUsedModel() == null) {
            ModelDownloader.download(AIModelInfo.defaultModel)
        }
    }

    // 默认模型下载完成后自动加载到引擎（仅一次，防重入）
    LaunchedEffect(downloads, localModels) {
        if (autoLoaded) return@LaunchedEffect
        val st = LLMService.state.value
        if (st is LLMService.State.Ready || st is LLMService.State.Loading) return@LaunchedEffect
        val def = AIModelInfo.defaultModel
        val dstate = downloads[def.id]
        if (dstate?.isDownloading == true || dstate?.error != null) return@LaunchedEffect
        val stored = localModels.firstOrNull { it.fileName == def.fileName } ?: return@LaunchedEffect
        autoLoaded = true
        val mmproj = ModelManager.modelsDir.listFiles()
            ?.firstOrNull { it.extension.lowercase() == "gguf" && it.name.lowercase().contains("mmproj") }
            ?.absolutePath
        LLMService.load(ModelManager.fileFor(stored).absolutePath, stored.name, mmproj)
        ModelManager.rememberLastUsed(stored)
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                MainTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = {
                            Icon(
                                imageVector = when (tab) {
                                    MainTab.Chat -> Icons.Filled.ChatBubbleOutline
                                    MainTab.Models -> Icons.Filled.Memory
                                    MainTab.Settings -> Icons.Filled.Settings
                                },
                                contentDescription = tab.label
                            )
                        },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        val modifier = Modifier.padding(innerPadding)
        when (selectedTab) {
            MainTab.Chat -> ChatScreen(modifier)
            MainTab.Models -> ModelScreen(modifier)
            MainTab.Settings -> SettingsScreen(modifier)
        }
    }
}
