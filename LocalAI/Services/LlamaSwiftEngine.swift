import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

// 本地 llama.cpp + mtmd 推理引擎（替代 LLM.swift）。
// 通过 LlamaBridge.h 的 C API 调用，支持纯文本与多模态（图片）。

final class LlamaSwiftEngine: LLMEngine, @unchecked Sendable {
    let modelURL: URL
    private var bridge: OpaquePointer?          // llama_bridge *
    private var lastError: String?

    // iOS 上 Metal 后端存在兼容性问题（解码失败/输出退化），默认纯 CPU 推理最稳定。
    // 需要加速可在「设置」里调高 GPU 层数。
    private let nGpuLayers: Int32
    private let nThreads: Int32 = 4

    init(modelURL: URL, gpuLayers: Int32 = 0) async throws {
        self.modelURL = modelURL
        self.nGpuLayers = gpuLayers

        var b: OpaquePointer?
        guard llama_bridge_create(&b) == 0, let handle = b else {
            throw LLMError.loadFailed("无法创建推理上下文")
        }
        self.bridge = handle

        let mmproj = LlamaSwiftEngine.detectMMProj(nextTo: modelURL)
        let ok = llama_bridge_load_model(
            handle,
            modelURL.path,
            mmproj ?? "",
            Int32(SettingsStorage.shared.settings.contextLength),
            nGpuLayers,
            nThreads
        )
        if !ok {
            let err = String(cString: llama_bridge_last_error(handle))
            throw LLMError.loadFailed(err)
        }
    }

    deinit {
        if let b = bridge { llama_bridge_free(b) }
    }

    // 自动探测同目录下的 mmproj 文件
    private static func detectMMProj(nextTo modelURL: URL) -> String? {
        let dir = modelURL.deletingLastPathComponent()
        let name = modelURL.deletingPathExtension().lastPathComponent.lowercased()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        // 优先：同名 mmproj，其次任意 *mmproj*.gguf
        for f in files where f.lastPathComponent.lowercased().contains("mmproj") &&
            f.pathExtension.lowercased() == "gguf" {
            if f.deletingPathExtension().lastPathComponent.lowercased().contains(name) {
                return f.path
            }
        }
        for f in files where f.lastPathComponent.lowercased().contains("mmproj") &&
            f.pathExtension.lowercased() == "gguf" {
            return f.path
        }
        return nil
    }

    func stream(
        messages: [EngineMessage],
        settings: ModelSettings,
        images: [CGImage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let b = bridge else {
                continuation.finish(throwing: LLMError.modelNotLoaded)
                return
            }

            // 消息 JSON
            var msgArr: [[String: String]] = []
            for m in messages {
                msgArr.append(["role": m.role.rawValue, "content": m.content])
            }
            guard let msgData = try? JSONSerialization.data(withJSONObject: msgArr),
                  let msgJSON = String(data: msgData, encoding: .utf8) else {
                continuation.finish(throwing: LLMError.generationFailed("消息序列化失败"))
                return
            }

            let settingsDict: [String: Any] = [
                "temp": settings.temperature,
                "top_k": settings.topK,
                "top_p": settings.topP,
                "max_tokens": settings.maxTokens,
            ]
            guard let setData = try? JSONSerialization.data(withJSONObject: settingsDict),
                  let setJSON = String(data: setData, encoding: .utf8) else {
                continuation.finish(throwing: LLMError.generationFailed("设置序列化失败"))
                return
            }

            // 图片写入临时 PNG，传路径给 C 桥
            var imgPaths: [String] = []
            for img in images {
                if let url = LlamaSwiftEngine.writeTempPNG(img) {
                    imgPaths.append(url.path)
                }
            }
            let imgArr = imgPaths
            guard let imgData = try? JSONSerialization.data(withJSONObject: imgArr),
                  let imgJSON = String(data: imgData, encoding: .utf8) else {
                continuation.finish(throwing: LLMError.generationFailed("图片序列化失败"))
                return
            }

            let forwarder = TokenForwarder(continuation: continuation)
            let ud = Unmanaged.passRetained(forwarder).toOpaque()

            // 消费者取消（停止生成 / 离开页面）时，通知 C 桥在下一个 token 边界停止
            // OpaquePointer 非 Sendable，转成位模式在 @Sendable 闭包里传递
            let bridgeBits = UInt(bitPattern: b)
            continuation.onTermination = { _ in
                llama_bridge_stop(OpaquePointer(bitPattern: bridgeBits))
            }

            Task.detached(priority: .userInitiated) {
                let rc = llama_bridge_chat(
                    b,
                    msgJSON,
                    setJSON,
                    imgJSON,
                    llamaBridgeTokenCallback,
                    ud
                )
                Unmanaged<TokenForwarder>.fromOpaque(ud).release()
                if rc != 0 {
                    let err = String(cString: llama_bridge_last_error(b))
                    continuation.finish(throwing: LLMError.generationFailed(err))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    private static func writeTempPNG(_ img: CGImage) -> URL? {
        #if canImport(UIKit)
        let ui = UIImage(cgImage: img)
        guard let data = ui.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try? data.write(to: url)
        return url
        #else
        return nil
        #endif
    }
}

private final class TokenForwarder {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }
    func yield(_ piece: UnsafePointer<CChar>) {
        let s = String(cString: piece, encoding: .utf8) ?? String(cString: piece, encoding: .ascii) ?? ""
        continuation.yield(s)
    }
}

private let llamaBridgeTokenCallback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { piece, userdata in
    guard let userdata, let piece else { return }
    let fwd = Unmanaged<TokenForwarder>.fromOpaque(userdata).takeUnretainedValue()
    fwd.yield(piece)
}
