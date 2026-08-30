import Foundation
import CryptoKit

/// 最小 S3 客户端（AWS Signature V4，纯 Swift 零依赖）
/// 支持 AWS S3 与兼容端点（MinIO / 腾讯云 COS / 阿里云 OSS 等 path-style）
enum S3Client {

    struct Config: Sendable {
        var endpoint: String   // 如 https://s3.amazonaws.com 或 http://localhost:9000
        var bucket: String
        var accessKey: String
        var secretKey: String
        var region: String     // 如 us-east-1
    }

    enum S3Error: LocalizedError {
        case invalidURL
        case missingConfig
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "S3 地址无效"
            case .missingConfig: return "S3 配置不完整（端点/桶/密钥）"
            case .httpError(let code, let body): return "S3 HTTP \(code): \(String(body.prefix(300)))"
            }
        }
    }

    // MARK: - 上传 / 下载

    static func upload(config: Config, objectKey: String, data: Data) async throws {
        let url = try makeURL(config: config, objectKey: objectKey)
        let amzDate = Self.amzDate()
        let dateStamp = String(amzDate.prefix(8))
        let payloadHash = SHA256.hash(data: data).hexString
        let host = hostHeader(for: url)

        let canonicalHeaders = [
            "content-type:application/octet-stream",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = "PUT\n\(url.path)\n\n\(canonicalHeaders)\(signedHeaders)\n\(payloadHash)"
        let signature = try sign(
            config: config, amzDate: amzDate, dateStamp: dateStamp,
            method: "PUT", canonicalRequest: canonicalRequest, signedHeaders: signedHeaders
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authHeader(config: config, amzDate: amzDate, dateStamp: dateStamp,
                                    signature: signature, signedHeaders: signedHeaders),
                         forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 120

        try await send(request)
    }

    static func download(config: Config, objectKey: String) async throws -> Data {
        let url = try makeURL(config: config, objectKey: objectKey)
        let amzDate = Self.amzDate()
        let dateStamp = String(amzDate.prefix(8))
        let payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // SHA256("")
        let host = hostHeader(for: url)

        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = "GET\n\(url.path)\n\n\(canonicalHeaders)\(signedHeaders)\n\(payloadHash)"
        let signature = try sign(
            config: config, amzDate: amzDate, dateStamp: dateStamp,
            method: "GET", canonicalRequest: canonicalRequest, signedHeaders: signedHeaders
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authHeader(config: config, amzDate: amzDate, dateStamp: dateStamp,
                                    signature: signature, signedHeaders: signedHeaders),
                         forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw S3Error.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            throw S3Error.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - SigV4

    private static func makeURL(config: Config, objectKey: String) throws -> URL {
        let key = objectKey
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(config.bucket)/\(key)")
        else { throw S3Error.invalidURL }
        return url
    }

    /// Host 头：非默认端口必须带上端口，否则 SigV4 签名不匹配
    private static func hostHeader(for url: URL) -> String {
        var host = url.host ?? ""
        if let port = url.port, port != 80, port != 443 {
            host += ":\(port)"
        }
        return host
    }

    private static func amzDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private static func sign(
        config: Config, amzDate: String, dateStamp: String,
        method: String, canonicalRequest: String, signedHeaders: String
    ) throws -> String {
        guard !config.accessKey.isEmpty, !config.secretKey.isEmpty else { throw S3Error.missingConfig }
        let scope = "\(dateStamp)/\(config.region)/s3/aws4_request"
        let hashedRequest = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(hashedRequest)"

        let kDate = HMAC<SHA256>.authenticationCode(
            for: Data(dateStamp.utf8),
            using: SymmetricKey(data: Data("AWS4\(config.secretKey)".utf8))
        )
        let kRegion = HMAC<SHA256>.authenticationCode(
            for: Data(config.region.utf8), using: SymmetricKey(data: Data(kDate))
        )
        let kService = HMAC<SHA256>.authenticationCode(
            for: Data("s3".utf8), using: SymmetricKey(data: Data(kRegion))
        )
        let kSigning = HMAC<SHA256>.authenticationCode(
            for: Data("aws4_request".utf8), using: SymmetricKey(data: Data(kService))
        )
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(kSigning))
        )
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private static func authHeader(
        config: Config, amzDate: String, dateStamp: String,
        signature: String, signedHeaders: String
    ) -> String {
        "AWS4-HMAC-SHA256 Credential=\(config.accessKey)/\(dateStamp)/\(config.region)/s3/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private static func send(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw S3Error.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            throw S3Error.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
