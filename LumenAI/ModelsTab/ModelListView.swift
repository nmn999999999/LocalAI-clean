import SwiftUI
import UniformTypeIdentifiers
import Foundation

extension ModelManager.StoredModel {
    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

struct ModelListView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var llmService: LLMService
    @EnvironmentObject private var theme: LumenAIApp.ThemeObserver
    @Environment(\.colorScheme) private var colorScheme

    @State private var showImporter = false
    @State private var showCustomURL = false
    @State private var customName = ""
    @State private var customURLText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    loadedSection
                    downloadedSection
                    catalogSection
                }
                .padding(14)
            }
            .background(theme.current.pageBackground(for: colorScheme))
            // iOS 26 液态玻璃：滚动到顶部边界时导航栏恢复"浮动圆球"折叠效果
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle("模型")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showCustomURL = true
                    } label: {
                        Label("URL", systemImage: "link")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: ggufTypes,
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                do {
                    try modelManager.importFromFiles(url: url, name: nil)
                } catch {
                    modelManager.lastError = "导入失败: \(error.localizedDescription)"
                }
            }
            .alert("从 URL 下载 GGUF", isPresented: $showCustomURL) {
                TextField("模型名称", text: $customName)
                TextField("https://…/model.gguf", text: $customURLText)
                Button("下载") {
                    if let url = URL(string: customURLText.trimmingCharacters(in: .whitespaces)) {
                        modelManager.downloadCustom(name: customName, remoteURL: url)
                    }
                    customName = ""
                    customURLText = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("粘贴指向 .gguf 文件的直链")
            }
            .alert("出错了", isPresented: .init(
                get: { modelManager.lastError != nil },
                set: { if !$0 { modelManager.lastError = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(modelManager.lastError ?? "")
            }
        }
    }

    private var ggufTypes: [UTType] {
        var types: [UTType] = [.data]
        if let gguf = UTType(filenameExtension: "gguf") {
            types.insert(gguf, at: 0)
        }
        return types
    }

    // MARK: - 已加载

    @ViewBuilder
    private var loadedSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "当前引擎", systemImage: "bolt.horizontal.circle")
                switch llmService.state {
                case .idle:
                    statusRow("未加载模型", icon: "circle.dashed", color: .secondary)
                case .loading(let name):
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载 \(name)…")
                            .foregroundStyle(.secondary)
                    }
                case .ready(let name):
                    statusRow("\(name) 已就绪", icon: "checkmark.seal.fill", color: .green)
                case .apiMode(let name):
                    statusRow("API 模式: \(name)", icon: "cloud.fill", color: .purple)
                case .failed(let msg):
                    statusRow(msg, icon: "exclamationmark.triangle.fill", color: .red)
                }

                if llmService.isModelReady {
                    Button(role: .destructive) {
                        llmService.unload()
                    } label: {
                        Label("卸载模型（释放内存）", systemImage: "eject")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func statusRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).lineLimit(2)
        }
    }

    // MARK: - 已下载

    @ViewBuilder
    private var downloadedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "本地模型", systemImage: "internaldrive")
            if modelManager.downloadedModels.isEmpty {
                GlassCard(cornerRadius: 18) {
                    Text("暂无本地模型。可从下方目录下载，或通过右上角按钮从「文件」导入自行下载的 .gguf 文件。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(modelManager.downloadedModels) { stored in
                    StoredModelRow(stored: stored)
                }
            }
        }
    }

    // MARK: - 推荐目录

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "推荐模型（HuggingFace）", systemImage: "globe")
            ForEach(AIModelInfo.catalog) { model in
                CatalogModelRow(model: model)
            }
        }
    }
}

// MARK: - 行组件

struct StoredModelRow: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var llmService: LLMService
    let stored: ModelManager.StoredModel
    @State private var loadingNow = false

    var body: some View {
        GlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stored.name)
                            .font(.headline)
                        Text("\(stored.sizeFormatted) · \(stored.fileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if llmService.loadedModelName == stored.name {
                        ModelBadge(text: "使用中", tint: .green)
                    }
                }

                if loadingNow {
                    ProgressView("加载中，首次可能较慢…")
                } else {
                    HStack(spacing: 10) {
                        Button {
                            loadingNow = true
                            Task {
                                let url = modelManager.localFileURL(for: stored)
                                await llmService.load(url: url, displayName: stored.name)
                                loadingNow = false
                                if case .failed(let msg) = llmService.state {
                                    modelManager.lastError = msg
                                }
                            }
                        } label: {
                            Label(llmService.loadedModelName == stored.name ? "重新加载" : "加载",
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)

                        Button(role: .destructive) {
                            modelManager.delete(stored)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }
}

struct CatalogModelRow: View {
    @EnvironmentObject private var modelManager: ModelManager
    let model: AIModelInfo

    var body: some View {
        GlassCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name).font(.headline)
                        Text(model.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ModelBadge(text: model.sizeDescription)
                            ModelBadge(text: model.estimatedRAMDescription, tint: .blue)
                            if model.supportsMultimodal {
                                ModelBadge(text: "多模态", tint: .purple)
                            }
                            if model.supportsToolCalling {
                                ModelBadge(text: "工具调用", tint: .orange)
                            }
                        }
                    }
                    Spacer()
                }

                if let progress = modelManager.progressFor(model.id) {
                    ProgressView(value: progress) {
                        Text("下载中 \(Int(progress * 100))%")
                            .font(.caption)
                    }
                    Button("取消", role: .destructive) {
                        modelManager.cancelDownload(id: model.id)
                    }
                    .buttonStyle(.glass)
                } else if modelManager.isDownloaded(model) {
                    Label("已下载 · 在「本地模型」中加载", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        modelManager.download(model)
                    } label: {
                        Label("下载", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }
}
