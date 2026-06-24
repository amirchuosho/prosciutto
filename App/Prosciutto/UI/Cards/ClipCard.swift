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
    @State private var pinPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: KindStyle { KindStyle.of(item.kind) }
    private var showActions: Bool { hovering || isSelected }
    private var editable: Bool {
        switch item.kind { case .text, .rtf, .code, .link, .color: return true; default: return false }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: 196, height: 212)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(border)
        .overlay(alignment: .bottom) {
            if showActions {
                actionBar.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .shadow(color: isSelected ? accent.opacity(0.4) : .black.opacity(0.28),
                radius: isSelected ? 16 : 8, y: isSelected ? 7 : 4)
        .scaleEffect(isSelected ? 1.04 : (hovering ? 1.015 : 0.98))
        .offset(y: isSelected ? -6 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.7), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: Header band

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: style.icon).font(.system(size: 10, weight: .heavy))
            Text(style.label).font(.system(size: 10, weight: .heavy)).tracking(0.6)
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9))
                    .rotationEffect(.degrees(pinPulse ? -18 : 0))
                    .scaleEffect(pinPulse ? 1.35 : 1)
            }
            Text(relativeTime).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            LinearGradient(colors: [style.color, style.color.opacity(0.82)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 5) {
            Text(meta).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let index, index <= 9 {
                Text("⌘\(index)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(isSelected ? accent : Color.secondary.opacity(0.22)))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isSelected ? accent : style.color.opacity(0.35),
                          lineWidth: isSelected ? 2.5 : 1)
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 6) {
            actionButton(item.isPinned ? "pin.slash.fill" : "pin.fill", tint: accent) {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { pinPulse = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pinPulse = false }
                }
                onPin()
            }
            if editable, let onEdit { actionButton("pencil", tint: .white, action: onEdit) }
            Spacer(minLength: 0)
            actionButton("trash.fill", tint: .red, action: onDelete)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear],
                                   startPoint: .bottom, endPoint: .top))
    }

    private func actionButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Content + meta

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
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: item.lastUsedAt, relativeTo: Date())
    }

    private var meta: String {
        switch item.kind {
        case .text, .rtf, .code:
            let n = item.textPlain?.count ?? 0
            return "\(n) chars" + (item.sourceAppName.map { " · \($0)" } ?? "")
        case .link:
            return URL(string: item.textPlain ?? "")?.host ?? "Link"
        case .image:
            return ByteCountFormatter.string(fromByteCount: Int64(item.imageData?.count ?? 0), countStyle: .file)
        case .color:
            return item.textPlain ?? "Color"
        case .file:
            return item.sourceAppName ?? "File"
        }
    }
}
