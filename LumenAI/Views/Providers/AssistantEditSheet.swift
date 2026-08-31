import SwiftUI

/// 新建 / 编辑自定义助手（Custom Assistants）
struct AssistantEditSheet: View {
    let existing: AIAssistant?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AssistantStore.shared
    @ObservedObject private var providerStore = ProviderStore.shared

    @State private var name: String
    @State private var emoji: String
    @State private var systemPrompt: String
    @State private var providerID: UUID?
    @State private var model: String
    @State private var temperature: String

    init(existing: AIAssistant? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🤖")
        _systemPrompt = State(initialValue: existing?.systemPrompt ?? "你是一个有帮助的AI助手。请用中文回答。")
        _providerID = State(initialValue: existing?.providerID)
        _model = State(initialValue: existing?.model ?? "")
        _temperature = State(initialValue: existing?.temperature.map { String($0) } ?? "")
    }

    private var boundModels: [String] {
        guard let id = providerID,
              let p = providerStore.provider(id: id)
        else { return [] }
        return p.models
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("头像与名称") {
                    HStack {
                        Text(emoji.isEmpty ? "🤖" : emoji)
                            .font(.system(size: 32))
                        TextField(t("头像 emoji"), text: $emoji)
                            .font(.title3)
                    }
                    TextField(t("助手名称"), text: $name)
                }

                Section {
                    TextField(t("系统提示词"), text: $systemPrompt, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("支持变量：{model} {provider} {date} {time} {datetime}")
                        .font(.caption2)
                }

                Section("绑定（可选）") {
                    Picker(t("绑定 Provider（可选）"), selection: $providerID) {
                        Text(t("跟随当前选择")).tag(UUID?.none)
                        ForEach(providerStore.providers.filter(\.enabled)) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .onChange(of: providerID) { _, _ in
                        if !boundModels.contains(model) {
                            model = boundModels.first ?? ""
                        }
                    }

                    if !boundModels.isEmpty {
                        Picker(t("绑定模型（可选）"), selection: $model) {
                            Text(t("跟随当前选择")).tag("")
                            ForEach(boundModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                    }

                    HStack {
                        Text("Temperature")
                        Spacer()
                        TextField("0.7", text: $temperature)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle(existing == nil ? t("添加助手") : t("编辑"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("保存")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let assistant = AIAssistant(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: emoji.isEmpty ? "🤖" : emoji,
            systemPrompt: systemPrompt,
            providerID: providerID,
            model: model.isEmpty ? nil : model,
            temperature: Double(temperature),
            enabled: true,
            createdAt: existing?.createdAt ?? Date()
        )
        store.upsert(assistant)
        dismiss()
    }
}
