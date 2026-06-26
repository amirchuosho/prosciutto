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
    private var showActions: Bool { hovering || isSelected }

    var body: some View {
        VStack(spacing: 0) {
            accentLine
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: DS.CardSize.width, height: DS.CardSize.height)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? accent : DS.cardStroke, lineWidth: isSelected ? 1.5 : 1)
        )
        .overlay(alignment: .bottom) {
            if showActions { actionBar.transition(.opacity) }
        }
        .shadow(color: isSelected ? accent.opacity(0.25) : .black.opacity(0.22),
                radius: isSelected ? 10 : 5, y: isSelected ? 5 : 3)
        .scaleEffect(isSelected ? 1.025 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: hovering)
        .onHover { hovering = $0 }
    }

    /// The single colour cue: a thin top accent in the kind colour.
    private var accentLine: some View {
        style.color.frame(height: 2.5)
    }

    private var header: some View {
        HStack(spacing: DS.Space.xs + 1) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.color)
            Text(style.label)
                .font(DS.Font.typeLabel).tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Space.xs)
            if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 8.5)).foregroundStyle(.tertiary)
            }
            Text(relativeTime).font(DS.Font.meta).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs + 2)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.xs) {
            Text(meta).font(DS.Font.meta).foregroundStyle(.tertiary).lineLimit(1)
            Spacer(minLength: DS.Space.xs)
            if let index, index <= 9 {
                Text("\(index)")
                    .font(DS.Font.shortcut)
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(isSelected ? accent.opacity(0.16) : Color.secondary.opacity(0.12)))
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm - 1)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private var actionBar: some View {
        HStack(spacing: DS.Space.sm) {
            actionButton(item.isPinned ? "pin.slash" : "pin", onPin)
            if item.kind.isEditable, let onEdit { actionButton("pencil", onEdit) }
            Spacer(minLength: 0)
            actionButton("trash", onDelete, role: .destructive)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm - 2)
        .background(.ultraThinMaterial)
    }

    private func actionButton(_ icon: String, _ action: @escaping () -> Void,
                              role: ButtonRole? = nil) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(role == .destructive ? Color.red.opacity(0.9) : .secondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
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

    private var relativeTime: String {
        let now = Date()
        if now.timeIntervalSince(item.lastUsedAt) < 5 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: item.lastUsedAt, relativeTo: now)
    }

    private var meta: String {
        switch item.kind {
        case .text, .rtf, .code:
            let n = item.textPlain?.count ?? 0
            return "\(n) chars" + (item.sourceAppName.map { " · \($0)" } ?? "")
        case .link:  return URL(string: item.textPlain ?? "")?.host ?? "Link"
        case .image: return ByteCountFormatter.string(fromByteCount: Int64(item.imageData?.count ?? 0), countStyle: .file)
        case .color: return item.textPlain ?? "Color"
        case .file:  return item.sourceAppName ?? "File"
        }
    }
}
