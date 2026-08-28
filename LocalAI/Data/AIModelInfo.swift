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

    /// 下载地址。使用国内可直连的 HuggingFace 镜像（hf-mirror.com），
    /// 避免 huggingface.co 在国内网络环境下拉不动/被墙。
    var downloadURL: URL? {
        URL(string: "https://hf-mirror.com/\(repo)/resolve/main/\(fileName)")
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
        AIModelInfo(
            id: "openelm-1.1b-q4km",
            name: "OpenELM 1.1B (Apple)",
            repo: "RichardErkhov/apple_-_OpenELM-1_1B-Instruct-gguf",
            fileName: "OpenELM-1_1B-Instruct.Q4_K_M.gguf",
            sizeDescription: "~0.63 GB",
            description: "Apple 官方开源高效语言模型，体量极小，任意 iPhone 都能离线跑；适合低内存设备的轻量备用（非默认）",
            templateType: .chatML,
            supportsMultimodal: false,
            supportsToolCalling: false
        ),
        AIModelInfo(
            id: "phi-4-mini-3.8b-q4km",
            name: "Phi-4-mini 3.8B",
            repo: "unsloth/Phi-4-mini-instruct-GGUF",
            fileName: "Phi-4-mini-instruct-Q4_K_M.gguf",
            sizeDescription: "~2.0 GB",
            description: "微软「小钢炮」：非 Qwen 里工具调用/指令遵循最稳，适合长期跑 Agent；中文一般但可用（首启默认自动下载并加载）",
            templateType: .llama3,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
        AIModelInfo(
            id: "minicpm5-1b-q4km",
            name: "MiniCPM5 1B",
            repo: "openbmb/MiniCPM5-1B-GGUF",
            fileName: "MiniCPM5-1B-Q4_K_M.gguf",
            sizeDescription: "~0.66 GB",
            description: "面壁/清华系 1B 小模型，非 Qwen 里中文最强，任意 iPhone 可跑；长 Agent 循环工具调用偏脆",
            templateType: .llama3,
            supportsMultimodal: false,
            supportsToolCalling: true
        ),
    ]

    /// 首启时优先下载并自动加载的默认模型（Phi-4-mini 3.8B：非 Qwen 里工具调用/指令遵循最稳，国内镜像可直连）。
    static var defaultModel: AIModelInfo {
        catalog.first { $0.id == "phi-4-mini-3.8b-q4km" } ?? catalog[0]
    }
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
    /// GPU offload 层数。0 = 纯 CPU（iPhone 上最稳定）；>0 部分/全部层走 Metal。
    var gpuLayers: Int
    /// 搜索服务："web"（设备直连网页搜索：Bing → DuckDuckGo → 维基百科）或 "wikipedia"（仅维基百科）
    var searchEngine: String
    /// SearXNG 实例地址（如 https://searx.be 或自建 http://192.168.1.10:8080）
    var searxngURL: String
    /// 是否显示模型的思考过程（<think> 标签内容）
    var showThinking: Bool
    /// 是否显示工具调用过程
    var showToolCalls: Bool
    /// 使用内存映射(mmap)加载模型，减少内存占用（仅访问的页面才加载到RAM）
    var useMmap: Bool
    
    // MARK: - API 模式设置
    /// 是否启用 API 模式（使用外部 API 而非本地模型）
    var apiEnabled: Bool
    /// API 端点地址（OpenAI 兼容格式）
    var apiEndpoint: String
    /// API 密钥
    var apiKey: String
    /// API 模型名称
    var apiModel: String
    /// API 温度参数
    var apiTemperature: Double
    /// API 最大 token 数
    var apiMaxTokens: Int

    // MARK: - SSH 配置（Agent `ssh` 工具默认连接）
    /// 默认 SSH 主机
    var sshHost: String
    /// 默认 SSH 端口
    var sshPort: Int
    /// 默认 SSH 用户名
    var sshUser: String
    /// 认证方式："password" 或 "key"
    var sshAuthType: String
    /// 密码（authType == "password" 时使用）
    var sshPassword: String
    /// 私钥 PEM（authType == "key" 时使用）
    var sshPrivateKey: String
    /// 私钥口令（可选）
    var sshPassphrase: String

    init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        maxTokens: Int = 2048,
        contextLength: Int = 2048,
        systemPrompt: String = "你是一个有帮助的AI助手。请用中文回答。",
        gpuLayers: Int = 0,
        searchEngine: String = "web",
        searxngURL: String = "",
        showThinking: Bool = true,
        showToolCalls: Bool = true,
        useMmap: Bool = true,
        apiEnabled: Bool = false,
        apiEndpoint: String = "https://api.openai.com/v1/chat/completions",
        apiKey: String = "",
        apiModel: String = "gpt-4o-mini",
        apiTemperature: Double = 0.7,
        apiMaxTokens: Int = 4096,
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        sshAuthType: String = "password",
        sshPassword: String = "",
        sshPrivateKey: String = "",
        sshPassphrase: String = ""
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.contextLength = contextLength
        self.systemPrompt = systemPrompt
        self.gpuLayers = gpuLayers
        self.searchEngine = searchEngine
        self.searxngURL = searxngURL
        self.showThinking = showThinking
        self.showToolCalls = showToolCalls
        self.useMmap = useMmap
        self.apiEnabled = apiEnabled
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
        self.apiModel = apiModel
        self.apiTemperature = apiTemperature
        self.apiMaxTokens = apiMaxTokens
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshAuthType = sshAuthType
        self.sshPassword = sshPassword
        self.sshPrivateKey = sshPrivateKey
        self.sshPassphrase = sshPassphrase
    }

    static let `default` = ModelSettings()

    // 兼容旧存档：新字段缺失时使用默认值，避免整个设置被重置
    enum CodingKeys: String, CodingKey {
        case temperature, topP, topK, maxTokens, contextLength, systemPrompt,
             gpuLayers, searchEngine, searxngURL, showThinking, showToolCalls, useMmap,
             apiEnabled, apiEndpoint, apiKey, apiModel, apiTemperature, apiMaxTokens,
             sshHost, sshPort, sshUser, sshAuthType, sshPassword, sshPrivateKey, sshPassphrase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        topP = try c.decodeIfPresent(Double.self, forKey: .topP) ?? 0.9
        topK = try c.decodeIfPresent(Int.self, forKey: .topK) ?? 40
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength) ?? 2048
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? "你是一个有帮助的AI助手。请用中文回答。"
        gpuLayers = try c.decodeIfPresent(Int.self, forKey: .gpuLayers) ?? 0
        // 旧存档兼容：曾用 "searxng"（已废弃）一律归一化为 "web"
        switch try c.decodeIfPresent(String.self, forKey: .searchEngine) ?? "web" {
        case "wikipedia": searchEngine = "wikipedia"
        default: searchEngine = "web"
        }
        searxngURL = try c.decodeIfPresent(String.self, forKey: .searxngURL) ?? ""
        showThinking = try c.decodeIfPresent(Bool.self, forKey: .showThinking) ?? true
        showToolCalls = try c.decodeIfPresent(Bool.self, forKey: .showToolCalls) ?? true
        useMmap = try c.decodeIfPresent(Bool.self, forKey: .useMmap) ?? true
        apiEnabled = try c.decodeIfPresent(Bool.self, forKey: .apiEnabled) ?? false
        apiEndpoint = try c.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? "https://api.openai.com/v1/chat/completions"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiModel = try c.decodeIfPresent(String.self, forKey: .apiModel) ?? "gpt-4o-mini"
        apiTemperature = try c.decodeIfPresent(Double.self, forKey: .apiTemperature) ?? 0.7
        apiMaxTokens = try c.decodeIfPresent(Int.self, forKey: .apiMaxTokens) ?? 4096
        sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshAuthType = try c.decodeIfPresent(String.self, forKey: .sshAuthType) ?? "password"
        sshPassword = try c.decodeIfPresent(String.self, forKey: .sshPassword) ?? ""
        sshPrivateKey = try c.decodeIfPresent(String.self, forKey: .sshPrivateKey) ?? ""
        sshPassphrase = try c.decodeIfPresent(String.self, forKey: .sshPassphrase) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(topP, forKey: .topP)
        try c.encode(topK, forKey: .topK)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(contextLength, forKey: .contextLength)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(gpuLayers, forKey: .gpuLayers)
        try c.encode(searchEngine, forKey: .searchEngine)
        try c.encode(searxngURL, forKey: .searxngURL)
        try c.encode(showThinking, forKey: .showThinking)
        try c.encode(showToolCalls, forKey: .showToolCalls)
        try c.encode(useMmap, forKey: .useMmap)
        try c.encode(apiEnabled, forKey: .apiEnabled)
        try c.encode(apiEndpoint, forKey: .apiEndpoint)
        try c.encode(apiKey, forKey: .apiKey)
        try c.encode(apiModel, forKey: .apiModel)
        try c.encode(apiTemperature, forKey: .apiTemperature)
        try c.encode(apiMaxTokens, forKey: .apiMaxTokens)
        try c.encode(sshHost, forKey: .sshHost)
        try c.encode(sshPort, forKey: .sshPort)
        try c.encode(sshUser, forKey: .sshUser)
        try c.encode(sshAuthType, forKey: .sshAuthType)
        try c.encode(sshPassword, forKey: .sshPassword)
        try c.encode(sshPrivateKey, forKey: .sshPrivateKey)
        try c.encode(sshPassphrase, forKey: .sshPassphrase)
    }
}
