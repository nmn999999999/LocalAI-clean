import Foundation

/// 提示词策略（按模型能力自动适配）
/// - 本地小模型（≤3B）：简洁直接，避免复杂格式把小模型搞晕
/// - 云端轻量模型（mini/flash/lite 等）：标准专业
/// - 云端旗舰模型（GPT-4o/Claude/Gemini-Pro 等）：深度专业
enum PromptStrategy: String, CaseIterable, Sendable {
    case auto = "auto"     // 自动识别
    case simple = "simple" // 强制简洁（小模型）
    case standard = "standard"
    case pro = "pro"       // 强制专业（大模型）
    case off = "off"       // 关闭

    var displayName: String {
        switch self {
        case .auto: return "自动（按模型能力）"
        case .simple: return "简洁（小模型）"
        case .standard: return "标准"
        case .pro: return "专业（大模型）"
        case .off: return "关闭"
        }
    }
}

/// 策略解析器：识别当前模型能力 → 选择策略 → 生成注入模板
enum PromptStrategyResolver {

    /// 词边界匹配（避免 "gemini" 误命中 "mini"）
    private static let liteRegex: NSRegularExpression? = {
        let pattern = #"\b(?:mini|flash|lite|air|haiku|small|nano|turbo|8k|fast|light)\b"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    // MARK: - 识别

    /// 根据使用场景与模型名自动判断策略
    /// - isCloud: 是否云端模型
    /// - modelName: 模型名（本地为 GGUF 显示名，云端为 API 模型名）
    /// - forced: 用户设置（off 直接返回 off）
    static func detect(isCloud: Bool, modelName: String?, forced: PromptStrategy) -> PromptStrategy {
        if forced == .off { return .off }
        if forced != .auto { return forced }

        guard let name = modelName?.lowercased(), !name.isEmpty else {
            // 无法识别时：云端给标准，本地给简洁（保守）
            return isCloud ? .standard : .simple
        }

        if isCloud {
            // 云端：轻量关键词（词边界）→ 标准；其余（旗舰）→ 专业
            let ns = name as NSString
            if let regex = Self.liteRegex,
               regex.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) != nil {
                return .standard
            }
            return .pro
        }

        // 本地 GGUF：从模型名提取参数规模（如 1.1b / 3.8b / 0.6b / 14b）
        if let scale = parameterScale(from: name) {
            return scale <= 3.0 ? .simple : .standard
        }
        // 提取不到规模：保守给简洁（小模型策略对小模型友好，对大模型也无害）
        return .simple
    }

    /// 从模型名提取参数规模（十亿）。如 "phi-4-mini-3.8b-q4km" → 3.8
    static func parameterScale(from modelName: String) -> Double? {
        // 匹配 "X.Xb" / "Xb"（不区分大小写，b 后必须是单词边界）
        let pattern = #"(\d+(?:\.\d+)?)\s*[bB](?![a-zA-Z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: modelName, range: NSRange(location: 0, length: (modelName as NSString).length)),
              let range = Range(match.range(at: 1), in: modelName)
        else { return nil }
        return Double(modelName[range])
    }

    // MARK: - 模板

    /// 生成注入系统提示词末尾的策略模板
    static func template(for strategy: PromptStrategy, language: String, assistantName: String) -> String {
        switch strategy {
        case .off, .auto:
            return ""
        case .simple:
            return language == "en" ? simpleEN : simpleZH
        case .standard:
            return language == "en" ? standardEN : standardZH
        case .pro:
            return language == "en"
                ? proEN.replacingOccurrences(of: "{assistant}", with: assistantName)
                : proZH.replacingOccurrences(of: "{assistant}", with: assistantName)
        }
    }

    // MARK: 文案（简洁 / 标准 / 专业，中英双版）

    private static let simpleZH = """
    ## 回答风格（重要）
    1. 回答尽量简短，先给结论，再补充必要的说明。
    2. 用简单的句子和常见词，不要堆砌术语。
    3. 分步骤时用 1. 2. 3. 编号，不要用表格和复杂格式。
    4. 一次只回答一个问题；不确定就明确说不知道。
    5. 严格按用户的指示执行，不要自行扩展。
    """

    private static let simpleEN = """
    ## Response Style (Important)
    1. Keep answers short; give the conclusion first, then brief details.
    2. Use simple sentences and common words.
    3. Use numbered steps (1. 2. 3.); avoid tables and complex formatting.
    4. Answer one question at a time; say so when unsure.
    5. Follow the user's instruction strictly; do not over-elaborate.
    """

    private static let standardZH = """
    ## 回答要求
    - 准确、条理清晰；可适当使用 Markdown（标题、列表、代码块）组织内容。
    - 复杂问题先拆解再回答；需要计算时给出过程。
    - 对不确定的信息明确标注，不编造。
    - 使用与用户相同的语言回复；专业术语首次出现可附英文。
    """

    private static let standardEN = """
    ## Requirements
    - Be accurate and well-organized; use Markdown (headings, lists, code blocks) when helpful.
    - Break down complex questions; show working steps for calculations.
    - Flag uncertainty explicitly; never fabricate facts.
    - Reply in the user's language; add English for key technical terms when first used.
    """

    private static let proZH = """
    ## 专业要求（{assistant} 模式）
    1. 深度思考：对复杂问题先分析需求与约束，再给出结构化解答；关键推理步骤可展示。
    2. 格式：善用 Markdown（多级标题、表格、代码块、引用）让答案清晰可扫读；代码给出可直接运行版本并附必要说明。
    3. 严谨：区分事实与推断，不确定处给出置信度或备选方案；拒绝编造数据与引用。
    4. 语言：默认使用用户使用的语言回复；专业术语首次出现附英文原名。
    5. 主动澄清：需求模糊时先给出最合理假设并说明，再作答。
    """

    private static let proEN = """
    ## Professional Requirements ({assistant} mode)
    1. Think deeply: analyze the question's requirements and constraints first, then answer with a clear structure; show key reasoning steps.
    2. Formatting: use Markdown (multi-level headings, tables, code blocks, blockquotes) for scannability; provide runnable code with brief notes.
    3. Rigor: distinguish facts from inference; state confidence or alternatives when unsure; never fabricate data or citations.
    4. Language: reply in the user's language; add English for key technical terms when first used.
    5. Clarify proactively: if the request is ambiguous, state the most reasonable assumption before answering.
    """
}
