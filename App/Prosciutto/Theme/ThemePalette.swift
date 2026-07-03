import SwiftUI
import ProsciuttoKit

enum ThemeFill {
    case solid(Color)
    case linear([Color])
    case radial([Color])

    var style: AnyShapeStyle {
        switch self {
        case .solid(let c): return AnyShapeStyle(c)
        case .linear(let cs):
            return AnyShapeStyle(LinearGradient(colors: cs, startPoint: .top, endPoint: .bottom))
        case .radial(let cs):
            return AnyShapeStyle(RadialGradient(colors: cs, center: .bottom, startRadius: 4, endRadius: 520))
        }
    }
}

/// SwiftUI view of a `ThemeSpec`: hex strings resolved to `Color`s once.
struct ThemePalette {
    let background: ThemeFill
    let surface: Color
    let foreground: Color
    let secondary: Color
    let hairline: Color
    let accent: [Color]
    let typeColors: [ClipKind: Color]
    let isDark: Bool

    init(_ spec: ThemeSpec) {
        let bg = spec.background.map { Color(hex: $0) ?? .black }
        switch spec.backgroundStyle {
        case .solid:  background = .solid(bg.first ?? .black)
        case .linear: background = .linear(bg)
        case .radial: background = .radial(bg)
        }
        surface    = Color(hex: spec.surface) ?? .gray
        foreground = Color(hex: spec.foreground) ?? .primary
        secondary  = Color(hex: spec.secondary) ?? .secondary
        hairline   = Color(hex: spec.hairline) ?? .gray.opacity(0.2)
        accent     = spec.accent.map { Color(hex: $0) ?? .accentColor }
        var tc: [ClipKind: Color] = [:]
        for kind in ClipKind.allCases { tc[kind] = Color(hex: spec.hex(for: kind)) ?? foreground }
        typeColors = tc
        isDark = spec.isDark
    }

    func color(for kind: ClipKind) -> Color {
        typeColors[kind == .rtf ? .text : kind] ?? foreground
    }

    var accentGradient: LinearGradient {
        LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
