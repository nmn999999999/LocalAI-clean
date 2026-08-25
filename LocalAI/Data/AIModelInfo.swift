import Foundation

struct AIModelInfo: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let repo: String
    let fileName: String
    let sizeDescription: String
    let description: String
    let templateType: TemplateType
    let supportsMultimodal: Bool
    let supportsToolCalling: Bool

    enum TemplateType: String, Codable, Hashable {
        case chatML
        case llama3
        case gemma
        case mistral
        case alpaca
    }

    var huggingFaceURL: URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)")
    }

    static let catalog: [AIModelInfo] = [
        AIModelInfo(
            id: "qwen3-0.6b-q4km",
            name: "Qwen3 0.6B",
            repo: "unsloth/Qwen3-0.6B-GGUF",
            fileName: "Qwen3-0.6B-Q4_K_M.gguf",
            sizeDescription: "~0.5 GB",
            description: "轻量级多语言模型，适合快速响应",
            templateType: .chatML,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
        AIModelInfo(
            id: "qwen3-1.7b-q4km",
            name: "Qwen3 1.7B",
            repo: "unsloth/Qwen3-1.7B-GGUF",
            fileName: "Qwen3-1.7B-Q4_K_M.gguf",
            sizeDescription: "~1.2 GB",
            description: "中等规模模型，平衡性能与质量",
            templateType: .chatML,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
        AIModelInfo(
            id: "gemma3-4b-it-q4km",
            name: "Gemma 3 4B",
            repo: "unsloth/gemma-3-4b-it-GGUF",
            fileName: "gemma-3-4b-it-Q4_K_M.gguf",
            sizeDescription: "~2.8 GB",
            description: "Google多模态模型，支持图片理解",
            templateType: .gemma,
            supportsMultimodal: true,
            supportsToolCalling: true
        ),
        AIModelInfo(
            id: "llama3.2-3b-q4km",
            name: "Llama 3.2 3B",
            repo: "unsloth/Llama-3.2-3B-GGUF",
            fileName: "Llama-3.2-3B-Q4_K_M.gguf",
            sizeDescription: "~2.0 GB",
            description: "Meta经典模型，稳定可靠",
            templateType: .llama3,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
        AIModelInfo(
            id: "qwen2.5-vl-3b-q4km",
            name: "Qwen2.5 VL 3B",
            repo: "lmstudio-community/Qwen2.5-VL-3B-Instruct-GGUF",
            fileName: "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
            sizeDescription: "~2.1 GB",
            description: "视觉语言模型，理解图片内容",
            templateType: .chatML,
            supportsMultimodal: true,
            supportsToolCalling: false
        ),
        AIModelInfo(
            id: "ministral-3b-q4km",
            name: "Ministral 3B",
            repo: "unsloth/Ministral-3B-v0.3-GGUF",
            fileName: "Ministral-3B-v0.3-Q4_K_M.gguf",
            sizeDescription: "~2.0 GB",
            description: "Mistral小型模型，推理速度快",
            templateType: .mistral,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
    ]
}

struct DownloadedModel: Identifiable, Hashable {
    let id: String
    let name: String
    let fileURL: URL
    let sizeBytes: Int64
    let downloadedAt: Date

    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

struct ModelSettings: Codable, Sendable {
    var temperature: Double
    var topP: Double
    var topK: Int
    var maxTokens: Int
    var contextLength: Int
    var systemPrompt: String

    init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        maxTokens: Int = 2048,
        contextLength: Int = 4096,
        systemPrompt: String = "你是一个有帮助的AI助手。请用中文回答。"
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.contextLength = contextLength
        self.systemPrompt = systemPrompt
    }

    static let `default` = ModelSettings()
}
