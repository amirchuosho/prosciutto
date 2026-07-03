public enum BackgroundStyle: String, Sendable, Equatable {
    case solid, linear, radial
}

/// Pure, UI-free description of a theme. Colors are hex strings so the kit stays
/// free of SwiftUI; the app builds `Color`s from this.
public struct ThemeSpec: Sendable, Equatable {
    public let background: [String]      // 1 hex = solid; 2-3 = gradient stops
    public let backgroundStyle: BackgroundStyle
    public let surface: String           // card body
    public let foreground: String        // primary text
    public let secondary: String         // secondary/meta text
    public let hairline: String          // dividers + card stroke
    public let accent: [String]          // exactly 2 stops
    public let typeColors: [ClipKind: String]
    public let isDark: Bool

    // Param order matches every call site: … accent, isDark, typeColors.
    public init(background: [String], backgroundStyle: BackgroundStyle, surface: String,
                foreground: String, secondary: String, hairline: String,
                accent: [String], isDark: Bool, typeColors: [ClipKind: String]) {
        self.background = background; self.backgroundStyle = backgroundStyle
        self.surface = surface; self.foreground = foreground; self.secondary = secondary
        self.hairline = hairline; self.accent = accent
        self.typeColors = typeColors; self.isDark = isDark
    }

    /// Type color for a kind; `.rtf` shares the Text color; any missing kind
    /// falls back to `foreground`.
    public func hex(for kind: ClipKind) -> String {
        let k: ClipKind = (kind == .rtf) ? .text : kind
        return typeColors[k] ?? typeColors[.text] ?? foreground
    }
}
