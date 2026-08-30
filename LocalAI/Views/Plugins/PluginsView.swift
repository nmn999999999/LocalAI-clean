import SwiftUI

/// 模块（JS 插件）管理：已安装模块 / 可更新模块 / 检查更新
/// 基础包（IPA）不动，模块在 App 内单独更新。
struct PluginsView: View {
    @ObservedObject private var pluginManager = PluginManager.shared
    @State private var installingID: String?
    @State private var toast: String?
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        List {
            installedSection
            remoteSection
        }
        .navigationTitle("模块 / JS 插件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                Button {
                    Task { await pluginManager.checkForUpdates() }
                } label: {
                    if pluginManager.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(pluginManager.isChecking)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                let data = try Data(contentsOf: url)
                let warning = try pluginManager.importBundle(data: data)
                toast(warning ?? "导入成功")
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .task { await pluginManager.checkForUpdates() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 12)
            }
        }
        .alert("模块更新", isPresented: .init(
            get: { pluginManager.lastCheckError != nil },
            set: { if !$0 { pluginManager.lastCheckError = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(pluginManager.lastCheckError ?? "")
        }
    }

    // MARK: - 已安装

    private var installedSection: some View {
        Section {
            if pluginManager.modules.isEmpty {
                Text("未安装任何模块。下方列表可一键安装免费模块。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(pluginManager.modules) { module in
                NavigationLink {
                    ModuleDetailView(module: module)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(module.manifest.name)
                                .font(.subheadline.weight(.semibold))
                            Text(module.manifest.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("v\(module.manifest.version) · \(module.toolCount) 个工具"
                                 + (module.engine.requiresApproval() ? " · 需授权" : ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pluginManager.remove(module)
                            toast("已删除模块")
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("已安装")
        } footer: {
            Text("模块存放于本机 Documents/Modules，删除不影响对话数据；卸载后 Agent 工具目录立即更新。")
                .font(.caption2)
        }
    }

    // MARK: - 远程模块

    private var remoteSection: some View {
        Section {
            if pluginManager.remoteIndex.isEmpty {
                Text(pluginManager.lastCheckError == nil ? "点击右上角「检查更新」获取可用模块。" : "索引拉取失败，请检查网络后重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(pluginManager.updateStates()) { update in
                Button {
                    installOrUpdate(update)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(update.entry.name)
                                .font(.subheadline.weight(.semibold))
                            Text(update.entry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(installedText(update))
                                .font(.caption2)
                                .foregroundStyle(update.hasUpdate ? .orange : .secondary)
                        }
                        Spacer()
                        if installingID == update.id {
                            ProgressView().controlSize(.mini)
                        } else if update.installedVersion == nil {
                            Label("安装", systemImage: "arrow.down.circle.fill")
                                .font(.caption.weight(.semibold))
                        } else if update.hasUpdate {
                            Label("更新", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Label("已是最新", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(installingID != nil || !update.hasUpdate && update.installedVersion != nil)
            }
        } header: {
            Text("可安装 / 可更新（免费）")
        } footer: {
            Text("模块 = manifest.json + tools.js（JavaScriptCore 纯计算沙箱），独立版本独立更新；基础包不需要重装。")
                .font(.caption2)
        }
    }

    private func installedText(_ update: ModuleUpdate) -> String {
        if let v = update.installedVersion {
            return update.hasUpdate ? "已安装 v\(v) → 可更新 v\(update.entry.version)" : "已安装 v\(v)（最新）"
        }
        return "v\(update.entry.version) · 未安装"
    }

    private func installOrUpdate(_ update: ModuleUpdate) {
        installingID = update.id
        Task {
            defer { installingID = nil }
            let error = await pluginManager.installOrUpdate(update.entry)
            toast = error ?? (update.installedVersion == nil ? "安装成功" : "已更新到 v\(update.entry.version)")
        }
    }

    private func toast(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.snappy) { toast = nil }
        }
    }
}
