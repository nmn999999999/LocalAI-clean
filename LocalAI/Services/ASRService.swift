import Foundation
import Speech
import AVFoundation
import Combine

/// 语音输入（ASR 能力，iOS 侧用 SFSpeechRecognizer）
/// 使用系统在线/离线识别，中英文自动跟随界面语言
///
/// Swift 6 strict concurrency 修复历史：
/// - v0.3.6：在 init() 直接调 requestAuthorization → TCC 后台 queue 触碰 @MainActor 状态 → trap。
/// - v0.3.7：在闭包内 `guard let self` + DispatchQueue.main.async → 仍 trap（closure escape 路径仍 leak）。
/// - v0.3.9：改 @unchecked Sendable → 关闭 actor 检查，仍可能被 SwiftUI 严格访问触发其他问题。
/// - v0.3.10（本版）：保留 `@MainActor`，把请求授权封到 `static` 函数 → 闭包**不接收 self**，
///                  `Task { @MainActor in ASRService.shared.isAuthorized = ... }` 安全切到主线程。
@MainActor
final class ASRService: ObservableObject {

    static let shared = ASRService()

    /// UI 订阅的 published 状态
    @Published private(set) var isAuthorized = false
    @Published var isListening = false
    @Published var partialText = ""

    /// 识别出最终文本（回调设置在主线程）
    var onFinal: ((String) -> Void)?
    /// 识别到中间结果（用于实时上屏）
    var onPartial: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private init() {
        updateLocale()
    }

    func updateLocale() {
        let lang = SettingsStorage.shared.settings.language == "en" ? "en-US" : "zh-CN"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang))
    }

    var permissionDenied: Bool { !isAuthorized }

    /// 开始/停止听写
    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }
        task?.cancel()
        task = nil
        guard isAuthorized else {
            // 主线程发起的请求；回调路径完全 self-contained，不捕获 self
            ASRService.requestPermissionAndStart()
            return
        }

        let lang = SettingsStorage.shared.settings.language == "en" ? "en-US" : "zh-CN"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang)),
              recognizer.isAvailable
        else { return }
        self.recognizer = recognizer

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.audioEngine = engine
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialText = text
                    self.onPartial?(text)
                    if result.isFinal {
                        if !text.isEmpty { self.onFinal?(text) }
                        self.stop()
                    }
                }
                if error != nil {
                    self.stop()
                }
            }
        }

        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isListening = true
            partialText = ""
        } catch {
            stop()
        }
    }

    func stop() {
        request?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        request = nil
        isListening = false
        partialText = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 静态、非隔离 —— 闭包路径**完全不捕获 self**，杜绝 actor isolation trap。
    /// 回调里 `Task { @MainActor in ... }` 切回主线程，单次主线程访问 `shared` 写 isAuthorized。
    nonisolated private static func requestPermissionAndStart() {
        SFSpeechRecognizer.requestAuthorization { rawStatus in
            // TCC 后台 queue：不碰 self，仅 Sendable 局部值
            let captured: SFSpeechRecognizerAuthorizationStatus = rawStatus
            Task { @MainActor in
                // 此处安全：通过单例访问 @MainActor 隔离状态
                let ok = (captured == .authorized)
                let svc = ASRService.shared
                svc.isAuthorized = ok
                if ok {
                    // start() 内部会 guard isListening / isAuthorized
                    svc.start()
                }
            }
        }
    }
}
