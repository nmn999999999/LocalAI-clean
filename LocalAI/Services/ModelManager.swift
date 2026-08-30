import Foundation

@MainActor
final class ModelManager: ObservableObject {

    static let shared = ModelManager()

    /// 已下载到本地的模型
    @Published private(set) var downloadedModels: [StoredModel] = []
    /// 下载进度（key = AIModelInfo.id 或自定义 key）
    @Published private(set) var progress: [String: Double] = [:]
    @Published var lastError: String?
    /// 最近一次「下载完成」的模型 id（供启动引导在默认模型下载完后自动加载）。
    @Published private(set) var lastCompletedDownloadID: String?

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var sessions: [String: URLSession] = [:]
    private static let lastModelKey = "model.last.used.v1"

    struct StoredModel: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let fileName: String
        let sizeBytes: Int64
        let addedAt: Date
    }

    // MARK: - 目录

    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL {
        Self.modelsDirectory.appendingPathComponent("index.json")
    }

    private init() {
        loadIndex()
    }

    // MARK: - 查询

    func isDownloaded(_ model: AIModelInfo) -> Bool {
        downloadedModels.contains { $0.id == model.id }
    }

    func progressFor(_ id: String) -> Double? {
        progress[id]
    }

    func localFileURL(fileName: String) -> URL {
        Self.modelsDirectory.appendingPathComponent(fileName)
    }

    func localFileURL(for stored: StoredModel) -> URL {
        localFileURL(fileName: stored.fileName)
    }

    // MARK: - 最后使用的模型（退出后自动记住）

    private static func lastModelID() -> String? {
        UserDefaults.standard.string(forKey: lastModelKey)
    }

    /// 记录最近一次加载的模型，供下次启动自动加载。
    func rememberLastUsed(_ stored: StoredModel) {
        UserDefaults.standard.set(stored.id, forKey: Self.lastModelKey)
    }

    /// 最近使用的模型（若文件还在则返回）。
    var lastUsedModel: StoredModel? {
        guard let id = Self.lastModelID() else { return nil }
        return downloadedModels.first(where: { $0.id == id })
    }

    /// 自动检测：扫描 Models 目录把未被索引的 .gguf 文件补进列表。
    private func rescanModelsDirectory() {
        let dir = Self.modelsDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "gguf" || ext == "ggml" || ext == "bin" else { continue }
            let fileName = fileURL.lastPathComponent
            let baseName = (fileName as NSString).deletingPathExtension
            if !downloadedModels.contains(where: { $0.fileName == fileName }) {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                downloadedModels.append(StoredModel(
                    id: "scan-\(fileName)",
                    name: baseName,
                    fileName: fileName,
                    sizeBytes: Int64(size),
                    addedAt: Date()
                ))
            }
        }
        saveIndex()
    }

    // MARK: - 下载（HuggingFace）

    func download(_ model: AIModelInfo) {
        guard let url = model.downloadURL else { return }
        startDownload(id: model.id, name: model.name, fileName: model.fileName, from: url)
    }

    func downloadCustom(name: String, remoteURL: URL) {
        let fileName = remoteURL.lastPathComponent
        let id = "custom-\(fileName)"
        startDownload(id: id, name: name.isEmpty ? fileName : name, fileName: fileName, from: remoteURL)
    }

    /// 基于 URLSessionDownloadDelegate 的下载器（提供真实进度回调）
    private final class Downloader: NSObject, URLSessionDownloadDelegate {
        let id: String
        let name: String
        let fileName: String
        let destination: URL
        let onFinish: @Sendable () -> Void

        init(id: String, name: String, fileName: String, destination: URL, onFinish: @escaping @Sendable () -> Void) {
            self.id = id
            self.name = name
            self.fileName = fileName
            self.destination = destination
            self.onFinish = onFinish
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                Task { @MainActor in
                    ModelManager.shared.addOrUpdate(stored: StoredModel(
                        id: id, name: name, fileName: fileName,
                        sizeBytes: ModelManager.shared.fileSize(at: destination),
                        addedAt: Date()
                    ))
                    ModelManager.shared.lastCompletedDownloadID = id
                }
            } catch {
                Task { @MainActor in
                    ModelManager.shared.lastError = "保存文件失败: \(error.localizedDescription)"
                }
            }
            onFinish()
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                ModelManager.shared.progress[self.id] = value
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            Task { @MainActor in
                ModelManager.shared.lastError = "下载失败: \(nsError.localizedDescription)"
                ModelManager.shared.finishDownload(id: self.id)
            }
        }
    }

    private func startDownload(id: String, name: String, fileName: String, from remote: URL) {
        guard activeTasks[id] == nil else { return }
        let destination = localFileURL(fileName: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            addOrUpdate(stored: StoredModel(
                id: id, name: name, fileName: fileName,
                sizeBytes: fileSize(at: destination), addedAt: Date()
            ))
            return
        }

        progress[id] = 0
        let downloader = Downloader(
            id: id, name: name, fileName: fileName,
            destination: destination
        ) { [weak self] in
            Task { @MainActor in
                self?.finishDownload(id: id)
            }
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 60 * 60 * 12
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let session = URLSession(configuration: config, delegate: downloader, delegateQueue: nil)
        sessions[id] = session
        let task = session.downloadTask(with: remote)
        activeTasks[id] = Task { task.resume() }
    }

    fileprivate func finishDownload(id: String) {
        sessions[id]?.invalidateAndCancel()
        sessions[id] = nil
        activeTasks[id] = nil
        progress[id] = nil
    }

    func cancelDownload(id: String) {
        sessions[id]?.invalidateAndCancel()
        sessions[id] = nil
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        progress[id] = nil
    }

    // MARK: - 从「文件」导入（用户自行下载的 gguf）

    func importFromFiles(url: URL, name: String?) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let destination = localFileURL(fileName: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        addOrUpdate(stored: StoredModel(
            id: "import-\(fileName)",
            name: name ?? (fileName as NSString).deletingPathExtension,
            fileName: fileName,
            sizeBytes: fileSize(at: destination),
            addedAt: Date()
        ))
    }

    // MARK: - 删除

    func delete(_ stored: StoredModel) {
        let fileURL = localFileURL(for: stored)
        try? FileManager.default.removeItem(at: fileURL)
        downloadedModels.removeAll { $0.id == stored.id }
        saveIndex()
    }

    // MARK: - 持久化

    private func addOrUpdate(stored: StoredModel) {
        if let idx = downloadedModels.firstIndex(where: { $0.id == stored.id }) {
            downloadedModels[idx] = stored
        } else {
            downloadedModels.append(stored)
        }
        saveIndex()
    }

    fileprivate func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func loadIndex() {
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // 与 saveIndex 一致，否则 addedAt 解码失败导致索引被清空
            let list = try? decoder.decode([StoredModel].self, from: data)
            downloadedModels = list ?? []
        }
        // 自动检测：把目录里未被索引的 .gguf 文件补进来
        rescanModelsDirectory()
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(downloadedModels) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
