import Foundation

/// 应用更新检查（滚动更新引导）
/// iOS 侧载应用无法自更新，这里做到侧载场景下的最优形态：
/// 自动检查 GitHub Release → 提示新版本与更新说明 → 一键跳转下载新 IPA（用户手动重装）。
@MainActor
final class UpdateCheckerService: ObservableObject {

    static let shared = UpdateCheckerService()

    @Published private(set) var latestTag: String?
    @Published private(set) var latestName: String?
    @Published private(set) var releaseNotes: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked = false

    private let repoAPI = "https://api.github.com/repos/nmn999999999/LocalAI-clean/releases/latest"
    private let lastCheckKey = "update_last_check_ts"
    /// 自动检查最小间隔（秒）：1 天
    private let minInterval: TimeInterval = 86400

    /// 当前安装版本（来自 Info.plist MARKETING_VERSION）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 是否存在可更新的新版本
    var hasUpdate: Bool {
        guard let latestTag else { return false }
        return Self.compare(Self.stripV(latestTag), currentVersion) > 0
    }

    /// 启动静默检查：距上次成功检查 < 间隔则跳过（省流量）
    func checkIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= minInterval else { return }
        await check()
    }

    /// 执行检查（手动 / 自动）
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        defer { lastChecked = true }

        guard let url = URL(string: repoAPI) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LocalAI-iOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

            latestTag = json["tag_name"] as? String
            latestName = json["name"] as? String
            releaseNotes = json["body"] as? String
            if let html = json["html_url"] as? String {
                releaseURL = URL(string: html)
            }
            // 找 iOS 安装包资产（.ipa）
            downloadURL = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    let name = (asset["name"] as? String) ?? ""
                    if name.lowercased().hasSuffix(".ipa"),
                       let browserURL = asset["browser_download_url"] as? String {
                        downloadURL = URL(string: browserURL)
                        break
                    }
                }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        } catch {
            // 网络失败静默（用户手动检查时可通过 UI 感知无响应）
        }
    }

    /// 去掉 tag 的 "v" 前缀
    static func stripV(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// 语义化版本比较：a > b → 1，a < b → -1，相等 → 0
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
