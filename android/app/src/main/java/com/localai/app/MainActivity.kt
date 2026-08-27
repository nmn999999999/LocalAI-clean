package com.localai.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.localai.app.data.AppContextHolder
import com.localai.app.store.ChatStore
import com.localai.app.store.ModelManager
import com.localai.app.store.SettingsStorage
import com.localai.app.ui.MainScreen
import com.localai.app.ui.theme.LocalAITheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        AppContextHolder.context = applicationContext
        SettingsStorage.init(applicationContext)
        ChatStore.init(applicationContext)
        ModelManager.init(applicationContext)
        setContent {
            LocalAITheme {
                MainScreen()
            }
        }
    }
}
