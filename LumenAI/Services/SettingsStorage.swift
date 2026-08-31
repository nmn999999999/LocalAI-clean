import Foundation

/// 全局模型参数（持久化到 UserDefaults）
final class SettingsStorage: ObservableObject, @unchecked Sendable {
    static let shared = SettingsStorage()

    @Published var settings: ModelSettings {
        didSet { persist() }
    }

    private let key = "model.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(ModelSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
