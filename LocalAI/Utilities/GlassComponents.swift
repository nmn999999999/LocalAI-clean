import SwiftUI

// Liquid Glass 组件库（需要 Xcode 26+ SDK，iOS 26+）
// 参考: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct GlassIconButton: View {
    let systemImage: String
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                if let label {
                    Text(label)
                }
            }
        }
        .buttonStyle(.glass)
        .labelStyle(.titleAndIcon)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct ModelBadge: View {
    let text: String
    var tint: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
