import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            content
            if message.role == .assistant || message.role == .tool {
                Spacer(minLength: 24)
            }
        }
        .contextMenu { copyButton }
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if !message.images.isEmpty {
                    imageRow
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(Color.accentColor, in: .rect(cornerRadius: 20))
            .frame(maxWidth: 320, alignment: .trailing)

        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                toolCallChips
                if let think = message.thinkContent, !think.isEmpty {
                    ThinkSection(think: think, isThinking: message.isThinking)
                }
                if !message.visibleContent.isEmpty {
                    Text(message.visibleContent)
                        .textSelection(.enabled)
                } else if message.isStreaming && message.thinkContent == nil {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("思考中…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 4)

        case .tool:
            VStack(alignment: .leading, spacing: 4) {
                Label("工具消息", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

        case .system:
            EmptyView()
        }
    }

    private var imageRow: some View {
        HStack(spacing: 6) {
            ForEach(message.images.indices, id: \.self) { idx in
                #if canImport(UIKit)
                if let img = UIImage(data: message.images[idx].data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 14))
                }
                #endif
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var toolCallChips: some View {
        if !message.toolCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(message.toolCalls) { call in
                    ToolCallChip(call: call)
                }
            }
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.content
            copied = true
        } label: {
            Label(copied ? "已复制" : "复制", systemImage: "doc.on.doc")
        }
    }
}

struct ToolCallChip: View {
    let call: ChatMessage.ToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                    Text("工具调用: \(call.name)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            if expanded {
                Group {
                    Text("参数")
                        .fontWeight(.semibold)
                    Text(prettyArguments)
                        .font(.system(.caption2, design: .monospaced))
                    if let result = call.result {
                        Text("结果")
                            .fontWeight(.semibold)
                        Text(result)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(12)
                    }
                }
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var prettyArguments: String {
        guard let data = call.arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let str = String(data: pretty, encoding: .utf8)
        else { return call.arguments }
        return str
    }
}

// MARK: - 思考内容折叠区（<think>…</think>）

struct ThinkSection: View {
    let think: String
    var isThinking: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.tint)
                    Text(isThinking ? "思考中" : "已深度思考")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    if isThinking {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(think)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
