import SwiftUI
import ProsciuttoKit

struct ClipCard: View {
    let item: ClipItem
    let index: Int?
    var isSelected: Bool = false
    var accent: Color = .accentColor
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var onEdit: (() -> Void)? = nil

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: KindStyle { KindStyle.of(item.kind) }
    private var editable: Bool {
        switch item.kind { case .text, .rtf, .code, .link, .color: return true; default: return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(width: 168, height: 128)
        .background(cardBackground)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomTrailing) { if hovering { actions } }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? accent : style.color.opacity(0.18),
                              lineWidth: isSelected ? 2.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: isSelected ? accent.opacity(0.35) : .black.opacity(0.25),
                radius: isSelected ? 12 : 6, y: 3)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : (isSelected ? 1.0 : 0.985))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                   value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
            LinearGradient(colors: [style.color.opacity(0.16), style.color.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: style.icon).font(.system(size: 9, weight: .bold))
                Text(style.label).font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(style.color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(style.color.opacity(0.18), in: Capsule())

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(accent)
            }
            if let index, index <= 9 {
                Text("⌘\(index)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(7)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            actionButton(item.isPinned ? "pin.slash" : "pin", onPin)
            if editable, let onEdit { actionButton("pencil", onEdit) }
            actionButton("xmark", onDelete, destructive: true)
        }
        .padding(6)
    }

    private func actionButton(_ icon: String, _ action: @escaping () -> Void,
                              destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(destructive ? Color.red : .primary)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image: ImageCard(item: item)
        case .link:  LinkCard(item: item)
        case .color: ColorCard(item: item)
        case .code:  CodeCard(item: item)
        case .file:  FileCard(item: item)
        case .text, .rtf: TextCard(item: item)
        }
    }
}
