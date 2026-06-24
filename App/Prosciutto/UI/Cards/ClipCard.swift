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
    private var glow: Color { isSelected ? accent : style.color }
    private var showActions: Bool { hovering || isSelected }
    private var editable: Bool {
        switch item.kind { case .text, .rtf, .code, .link, .color: return true; default: return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(width: 182, height: 134)
            .background(cardBackground)
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { if showActions { actionBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: glow.opacity(isSelected ? 0.55 : (hovering ? 0.4 : 0.0)),
                    radius: isSelected ? 18 : 12, y: 4)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
            .scaleEffect(isSelected ? 1.05 : (hovering ? 1.02 : 0.97))
            .offset(y: isSelected ? -4 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.68), value: isSelected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            LinearGradient(colors: [style.color.opacity(isSelected ? 0.38 : 0.24),
                                    style.color.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // top sheen
            LinearGradient(colors: [.white.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [glow.opacity(isSelected ? 0.95 : 0.4),
                                        glow.opacity(isSelected ? 0.5 : 0.12)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: isSelected ? 2.5 : 1.2)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: style.icon).font(.system(size: 9, weight: .heavy))
                Text(style.label).font(.system(size: 9, weight: .heavy)).tracking(0.5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3.5)
            .background(
                Capsule().fill(style.color.gradient)
                    .shadow(color: style.color.opacity(0.6), radius: 4, y: 1)
            )

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 10))
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(pinPulse ? -12 : 0))
                    .scaleEffect(pinPulse ? 1.3 : 1.0)
            }
            if let index, index <= 9 {
                Text("⌘\(index)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(isSelected ? accent : Color.secondary.opacity(0.25)))
            }
        }
        .padding(8)
    }

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
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
        )
    }

    private func actionButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
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
