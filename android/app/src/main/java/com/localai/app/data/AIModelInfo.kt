package com.localai.app.data

/** 在线模型目录（与 iOS 版对齐，下载走国内可达的 hf-mirror.com 镜像）。 */
data class AIModelInfo(
    val id: String,
    val name: String,
    val repo: String,
    val fileName: String,
    val sizeDescription: String,
    val description: String,
    val supportsMultimodal: Boolean = false,
    val mmprojFileName: String? = null,
) {
    /** 下载地址：统一走国内可达的 hf-mirror.com 镜像（全 catalog 受益，与 iOS 版一致）。 */
    val huggingFaceURL: String
        get() = "https://hf-mirror.com/$repo/resolve/main/$fileName"

    val mmprojURL: String?
        get() = mmprojFileName?.let { "https://hf-mirror.com/$repo/resolve/main/$it" }

    companion object {
        val catalog: List<AIModelInfo> = listOf(
            AIModelInfo(
                id = "qwen3-0.6b-q4km",
                name = "Qwen3 0.6B",
                repo = "unsloth/Qwen3-0.6B-GGUF",
                fileName = "Qwen3-0.6B-Q4_K_M.gguf",
                sizeDescription = "~0.5 GB",
                description = "轻量级多语言模型，适合快速响应",
            ),
            AIModelInfo(
                id = "qwen3-1.7b-q4km",
                name = "Qwen3 1.7B",
                repo = "unsloth/Qwen3-1.7B-GGUF",
                fileName = "Qwen3-1.7B-Q4_K_M.gguf",
                sizeDescription = "~1.2 GB",
                description = "中等规模模型，平衡性能与质量",
            ),
            AIModelInfo(
                id = "qwen2.5-vl-3b-q4km",
                name = "Qwen2.5 VL 3B",
                repo = "lmstudio-community/Qwen2.5-VL-3B-Instruct-GGUF",
                fileName = "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
                mmprojFileName = "mmproj-Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
                sizeDescription = "~2.1 GB",
                description = "视觉语言模型，理解图片内容（含 mmproj）",
                supportsMultimodal = true,
            ),
            AIModelInfo(
                id = "llama3.2-3b-q4km",
                name = "Llama 3.2 3B",
                repo = "unsloth/Llama-3.2-3B-GGUF",
                fileName = "Llama-3.2-3B-Q4_K_M.gguf",
                sizeDescription = "~2.0 GB",
                description = "Meta经典模型，稳定可靠",
            ),
            AIModelInfo(
                id = "gemma3-4b-it-q4km",
                name = "Gemma 3 4B",
                repo = "unsloth/gemma-3-4b-it-GGUF",
                fileName = "gemma-3-4b-it-Q4_K_M.gguf",
                sizeDescription = "~2.8 GB",
                description = "Google多模态模型，支持图片理解",
                supportsMultimodal = true,
            ),
            AIModelInfo(
                id = "ministral-3b-q4km",
                name = "Ministral 3B",
                repo = "unsloth/Ministral-3B-v0.3-GGUF",
                fileName = "Ministral-3B-v0.3-Q4_K_M.gguf",
                sizeDescription = "~2.0 GB",
                description = "Mistral小型模型，推理速度快",
            ),
            // —— v0.2.8/v0.2.9 新增：国内镜像 + Apple/非 Qwen 默认模型（与 iOS 版对齐）——
            AIModelInfo(
                id = "phi-4-mini-3.8b-q4km",
                name = "Phi-4-mini 3.8B",
                repo = "unsloth/Phi-4-mini-instruct-GGUF",
                fileName = "Phi-4-mini-instruct-Q4_K_M.gguf",
                sizeDescription = "~2.0 GB",
                description = "Microsoft 小钢炮：工具调用/指令遵循顶级，最适合 Agent（需 ≥4GB 内存）",
            ),
            AIModelInfo(
                id = "minicpm5-1b-q4km",
                name = "MiniCPM5 1B",
                repo = "openbmb/MiniCPM5-1B-GGUF",
                fileName = "MiniCPM5-1B-Q4_K_M.gguf",
                sizeDescription = "~0.65 GB",
                description = "OpenBMB/清华系，非 Qwen 里中文最强，任意机型可跑；长 Agent 循环偏脆",
            ),
            AIModelInfo(
                id = "openelm-1.1b-q4km",
                name = "OpenELM 1.1B (Apple)",
                repo = "RichardErkhov/apple_-_OpenELM-1_1B-Instruct-gguf",
                fileName = "OpenELM-1_1B-Instruct.Q4_K_M.gguf",
                sizeDescription = "~0.63 GB",
                description = "Apple 官方开源，体量最小，给低内存机型兜底（英文向、无工具调用）",
            ),
        )

        /** 首启优先下载并自动加载的默认模型（Phi-4-mini：工具调用最稳）。 */
        val defaultModel: AIModelInfo
            get() = catalog.firstOrNull { it.id == "phi-4-mini-3.8b-q4km" } ?: catalog[0]
    }
}
