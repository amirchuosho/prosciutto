import SwiftUI
import ProsciuttoKit

struct ClipCard: View {
    let item: ClipItem
    let index: Int?
    var isSelected: Bool = false
    var accent: Color = .accentColor
    var accentGradient: LinearGradient = LinearGradient(colors: [.accentColor], startPoint: .top, endPoint: .bottom)
    /// Overrides the header colour (used for section colours); nil = kind colour.
    var headerColor: Color? = nil
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var onEdit: (() -> Void)? = nil

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: KindStyle { KindStyle.of(item.kind) }
    private var bandColor: Color { headerColor ?? style.color }
    private var onBand: Color { bandColor.readableText }
    private var showActions: Bool { hovering || isSelected }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DS.cardBody(scheme))
                .clipped()
                .overlay(alignment: .bottomTrailing) { if showActions { actionBar } }
            footer
        }
        .frame(width: DS.CardSize.width, height: DS.CardSize.height)
        .background(DS.cardBody(scheme))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(accentGradient) : AnyShapeStyle(DS.cardStroke(scheme)),
                              lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: isSelected ? accent.opacity(0.5) : .black.opacity(scheme == .dark ? 0.4 : 0.12),
                radius: isSelected ? 24 : 14, y: isSelected ? 12 : 8)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.8), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }

    // MARK: Header band

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(style.title).font(DS.Font.cardTitle).foregroundStyle(onBand)
                Text(relativeTime).font(DS.Font.cardTime).foregroundStyle(onBand.opacity(0.78))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(onBand.opacity(0.9))
                }
                appIcon
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm + 2)
        .frame(height: DS.CardSize.header)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            bandColor
            // glossy top sheen for depth
            LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let icon = AppIconProvider.icon(forBundleID: item.sourceAppBundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: DS.CardSize.appIcon, height: DS.CardSize.appIcon)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        } else {
            Image(systemName: style.icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(onBand.opacity(0.85))
                .frame(width: DS.CardSize.appIcon, height: DS.CardSize.appIcon)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.Space.sm) {
            Text(meta).font(DS.Font.meta).foregroundStyle(DS.footerMeta(scheme)).lineLimit(1)
            Spacer(minLength: 0)
            if let index, index <= 9 {
                Text("\(index)")
                    .font(DS.Font.shortcut)
                    .foregroundStyle(isSelected ? accent : DS.footerMeta(scheme))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(isSelected ? accent.opacity(0.18)
                                                          : Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline(scheme)).frame(height: 1) }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton(item.isPinned ? "pin.slash.fill" : "pin.fill", onPin)
            if item.kind.isEditable, let onEdit { actionButton("pencil", onEdit) }
            actionButton("trash.fill", onDelete, destructive: true)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
        .padding(DS.Space.sm)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func actionButton(_ icon: String, _ action: @escaping () -> Void,
                              destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : .primary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
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
        let now = Date()
        if now.timeIntervalSince(item.lastUsedAt) < 5 { return "now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: item.lastUsedAt, relativeTo: now)
    }

    private var meta: String {
        switch item.kind {
        case .text, .rtf, .code: return "\(item.textPlain?.count ?? 0) characters"
        case .link:  return URL(string: item.textPlain ?? "")?.host ?? "Link"
        case .image: return ByteCountFormatter.string(fromByteCount: Int64(item.imageData?.count ?? 0), countStyle: .file)
        case .color: return item.textPlain ?? "Color"
        case .file:  return item.sourceAppName ?? "File"
        }
    }
}
