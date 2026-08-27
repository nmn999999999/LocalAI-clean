package com.localai.app.data

/** 在线模型目录（与 iOS 版对齐，HuggingFace 源）。 */
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
    val huggingFaceURL: String
        get() = "https://huggingface.co/$repo/resolve/main/$fileName"

    val mmprojURL: String?
        get() = mmprojFileName?.let { "https://huggingface.co/$repo/resolve/main/$it" }

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
        )
    }
}
