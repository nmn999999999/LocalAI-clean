import Foundation

/// 提示词变量（Prompt Variables）
/// 支持：{model} {provider} {date} {time} {datetime}
enum PromptVariableResolver {

    static func resolve(
        _ text: String,
        model: String?,
        providerName: String?
    ) -> String {
        var result = text
        let now = Date()
        let dateFormatter = DateFormatter()
        let timeFormatter = DateFormatter()
        let datetimeFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        timeFormatter.dateFormat = "HH:mm"
        datetimeFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        result = result.replacingOccurrences(of: "{model}", with: model ?? "unknown")
        result = result.replacingOccurrences(of: "{provider}", with: providerName ?? "unknown")
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
        result = result.replacingOccurrences(of: "{datetime}", with: datetimeFormatter.string(from: now))
        return result
    }
}
