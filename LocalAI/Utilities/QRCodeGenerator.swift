import UIKit
import CoreImage

/// QR 码生成与识别（QR Code Sharing）
enum QRCodeGenerator {

    /// 由字符串生成 QR 码图片
    static func generate(from string: String, size: CGFloat = 280) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .utf8, allowLossyConversion: false)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scale = size / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 从图片中识别 QR 码内容
    static func decode(image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        for case let feature as CIQRCodeFeature in features {
            if let message = feature.messageString { return message }
        }
        return nil
    }
}

/// Provider 配置导出/导入编解码
enum ProviderShareCodec {

    static func export(_ providers: [ChatProvider]) -> String? {
        let payload: [String: Any] = [
            "localai_provider_export": 1,
            "providers": providers.map { p in
                [
                    "name": p.name,
                    "type": p.type.rawValue,
                    "baseURL": p.baseURL,
                    "apiKeys": p.apiKeys,
                    "headers": p.headers,
                    "extraBody": p.extraBody,
                    "models": p.models,
                ]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    /// 解析导入内容（兼容 QR 内容 / 粘贴文本 / 备份文件）
    static func parseImport(_ text: String) -> [ChatProvider] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var list: [[String: Any]] = []
        if let providers = json["providers"] as? [[String: Any]] {
            list = providers
        } else if let single = json["type"] as? String {
            list = [json]
        } else if let arr = json as? [String: Any], let _ = arr["name"] as? String {
            list = [json]
        } else {
            return []
        }

        return list.compactMap { dict -> ChatProvider? in
            guard let name = dict["name"] as? String else { return nil }
            let typeRaw = dict["type"] as? String ?? ""
            let type = ProviderType(rawValue: typeRaw) ?? .openAICompatible
            let baseURL = dict["baseURL"] as? String ?? ""
            let apiKeys = (dict["apiKeys"] as? [String]) ?? {
                if let k = dict["apiKey"] as? String, !k.isEmpty { return [k] }
                return []
            }()
            let headers = (dict["headers"] as? [String: String]) ?? [:]
            let extraBody = dict["extraBody"] as? String ?? ""
            let models = (dict["models"] as? [String]) ?? {
                if let m = dict["model"] as? String, !m.isEmpty { return [m] }
                return []
            }()
            return ChatProvider(
                name: name,
                type: type,
                baseURL: baseURL,
                apiKeys: apiKeys,
                headers: headers,
                extraBody: extraBody,
                models: models
            )
        }
    }
}
