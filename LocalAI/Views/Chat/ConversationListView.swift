import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(chatStore.conversations) { conv in
                    Button {
                        chatStore.currentConversationID = conv.id
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conv.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let model = conv.modelName {
                                    ModelBadge(text: model)
                                }
                                Text("\(conv.messages.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { chatStore.conversations[$0].id }
                    for id in ids {
                        if let conv = chatStore.conversation(id: id) {
                            chatStore.delete(conv)
                        }
                    }
                }
            }
            .overlay {
                if chatStore.conversations.isEmpty {
                    ContentUnavailableView(
                        "暂无对话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("点击右上角新建对话")
                    )
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        chatStore.createNew()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(t("新建对话"))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
