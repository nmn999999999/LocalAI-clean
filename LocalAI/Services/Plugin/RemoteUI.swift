import SwiftUI

// MARK: - 远程 UI 定义（插件 manifest.settingsUI）
// 不换底包即可改变界面：App 内置 JSON→SwiftUI 渲染器，插件下发界面定义。

/// 行类型：开关 / 按钮 / 文本输入 / 密文输入 / 信息 / 选择器
struct RemoteUIRow: Codable, Identifiable, Sendable {
    enum RowType: String, Codable, Sendable {
        case toggle, button, text, secureText, info, picker
    }

    let id: String
    let type: RowType
    let title: String
    let subtitle: String?
    /// storage key（toggle/text/secureText/picker 读写插件本地存储）
    let key: String?
    let defaultValue: String?
    /// picker 选项
    let options: [String]?
    /// 按钮动作：test:<toolName> | open:<url> | reset（清空插件存储）
    let action: String?
    let confirm: String?
}

struct RemoteUIGroup: Codable, Identifiable, Sendable {
    let id: String
    let title: String?
    let rows: [RemoteUIRow]
}

// MARK: - 渲染器

/// 把插件的 settingsUI 渲染成设置页分组（值与插件本地存储双向绑定）
struct RemoteUIView: View {
    let module: PluginManager.InstalledModule
    let groups: [RemoteUIGroup]
    @State private var results: [String: String] = [:]

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.rows) { row in
                    rowView(row)
                }
            } header: {
                if let title = group.title {
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: RemoteUIRow) -> some View {
        switch row.type {
        case .toggle:
            Toggle(isOn: bindingForToggle(row)) {
                rowLabel(row)
            }
        case .button:
            Button {
                runAction(row)
            } label: {
                HStack {
                    rowLabel(row)
                    Spacer()
                    if results[row.id] == "running" {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
            .disabled(results[row.id] == "running")
            .confirmationDialog(row.title, isPresented: confirmBinding(row), titleVisibility: .visible) {
                Button(row.title, role: .destructive) {
                    executeAction(row)
                }
                Button("取消", role: .cancel) {}
            }
        case .text, .secureText:
            HStack {
                rowLabel(row)
                if row.type == .secureText {
                    SecureField(row.defaultValue ?? "", text: textBinding(row))
                        .multilineTextAlignment(.trailing)
                } else {
                    TextField(row.defaultValue ?? "", text: textBinding(row))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        case .info:
            rowLabel(row)
                .foregroundStyle(.secondary)
        case .picker:
            Picker(row.title, selection: pickerBinding(row)) {
                ForEach(row.options ?? [], id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
        }
    }

    @ViewBuilder
    private func rowLabel(_ row: RemoteUIRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.subheadline)
            if let subtitle = row.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 绑定

    private func storage(_ key: String) -> String? {
        PluginManager.shared.storageValue(module: module, key: key)
    }
    private func setStorage(_ key: String, _ value: String) {
        PluginManager.shared.setStorageValue(module: module, key: key, value: value)
    }

    private func bindingForToggle(_ row: RemoteUIRow) -> Binding<Bool> {
        Binding(
            get: { (storage(row.key ?? "") ?? row.defaultValue ?? "false") == "true" },
            set: { setStorage(row.key ?? "", $0 ? "true" : "false") }
        )
    }

    private func textBinding(_ row: RemoteUIRow) -> Binding<String> {
        Binding(
            get: { storage(row.key ?? "") ?? row.defaultValue ?? "" },
            set: { setStorage(row.key ?? "", $0) }
        )
    }

    private func pickerBinding(_ row: RemoteUIRow) -> Binding<String> {
        Binding(
            get: { storage(row.key ?? "") ?? row.defaultValue ?? row.options?.first ?? "" },
            set: { setStorage(row.key ?? "", $0) }
        )
    }

    private func confirmBinding(_ row: RemoteUIRow) -> Binding<Bool> {
        Binding(
            get: { pendingConfirm == row.id },
            set: { if !$0 { pendingConfirm = nil } }
        )
    }

    // MARK: 动作

    @State private var pendingConfirm: String?

    private func runAction(_ row: RemoteUIRow) {
        if let confirm = row.confirm, !confirm.isEmpty {
            pendingConfirm = row.id
        } else {
            executeAction(row)
        }
    }

    private func executeAction(_ row: RemoteUIRow) {
        guard let action = row.action else { return }
        if action.hasPrefix("test:") {
            let toolName = String(action.dropFirst(5))
            results[row.id] = "running"
            Task {
                defer { results[row.id] = nil }
                let result = await module.engine.call(name: toolName, argumentsJSON: "{}")
                results[row.id] = result
            }
        } else if action.hasPrefix("open:") {
            let urlString = String(action.dropFirst(5))
            if let url = URL(string: urlString) {
                #if canImport(UIKit)
                UIApplication.shared.open(url)
                #endif
            }
        } else if action == "reset" {
            PluginManager.shared.resetStorage(module: module)
        }
    }
}
