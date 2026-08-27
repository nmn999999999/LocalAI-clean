package com.localai.app.data

data class ModelSettings(
    var temperature: Double = 0.7,
    var topP: Double = 0.9,
    var topK: Int = 40,
    var maxTokens: Int = 2048,
    var contextLength: Int = 4096,
    var systemPrompt: String = "你是一个有帮助的AI助手。请用中文回答。",
    // 0 = 纯 CPU（Android 上最稳）；>0 部分层用 GPU 加速（需硬件支持）
    var gpuLayers: Int = 0,
    // 搜索服务："web"（设备直连网页搜索：Bing → DuckDuckGo → 维基百科）或 "wikipedia"（仅维基百科）
    var searchEngine: String = "web",
    var searxngURL: String = "",
)
