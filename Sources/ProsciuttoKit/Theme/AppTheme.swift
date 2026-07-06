public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case prosciutto, synthwave, matrix, dracula, nord, vaporwave, cyberpunk, gruvbox, daylight, custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .prosciutto: return "Prosciutto"
        case .synthwave:  return "Synthwave"
        case .matrix:     return "Matrix"
        case .dracula:    return "Dracula"
        case .nord:       return "Nord"
        case .vaporwave:  return "Vaporwave"
        case .cyberpunk:  return "Cyberpunk"
        case .gruvbox:    return "Gruvbox"
        case .daylight:   return "Daylight"
        case .custom:     return "Custom"
        }
    }

    /// Type-color ramp order: text, link, image, color, code, file, location.
    private static func ramp(_ t: String, _ l: String, _ i: String, _ c: String,
                             _ code: String, _ f: String, _ loc: String, _ vid: String) -> [ClipKind: String] {
        [.text: t, .link: l, .image: i, .color: c, .code: code, .file: f, .location: loc, .video: vid]
    }

    public func spec(customAccentHex: String) -> ThemeSpec {
        switch self {
        case .prosciutto:
            return ThemeSpec(background: ["#2A1622", "#141018"], backgroundStyle: .radial,
                surface: "#1E1B24", foreground: "#ECE8F0", secondary: "#A79FB0", hairline: "#2A2733",
                accent: ["#FF70A3", "#FF4566"], isDark: true,
                typeColors: Self.ramp("#5C8FFF", "#C77DFF", "#FF9E5C", "#FF6FB0", "#52CC85", "#6FD3C7", "#FF6B6B", "#8A7BFF"))
        case .synthwave:
            return ThemeSpec(background: ["#1A1033", "#2A1550", "#3D1A4D"], backgroundStyle: .linear,
                surface: "#241640", foreground: "#EDE0FF", secondary: "#B79EE6", hairline: "#3A2A5C",
                accent: ["#FF3CAC", "#7A2FF7"], isDark: true,
                typeColors: Self.ramp("#00E5FF", "#FF6AD5", "#FFB03C", "#FF3CAC", "#39FF9E", "#7AF0FF", "#FF4778", "#9D5CFF"))
        case .matrix:
            return ThemeSpec(background: ["#06120A", "#030603"], backgroundStyle: .radial,
                surface: "#0B140B", foreground: "#C6F5C6", secondary: "#6FBF6F", hairline: "#173717",
                accent: ["#39FF14", "#00C853"], isDark: true,
                typeColors: Self.ramp("#39FF14", "#A6FF00", "#B7FF3C", "#7CFFB0", "#00E676", "#4FD06A", "#E5FF3C", "#00FFC6"))
        case .dracula:
            return ThemeSpec(background: ["#282A36"], backgroundStyle: .solid,
                surface: "#343746", foreground: "#F8F8F2", secondary: "#A9AAC4", hairline: "#44475A",
                accent: ["#BD93F9", "#FF79C6"], isDark: true,
                typeColors: Self.ramp("#8BE9FD", "#FF79C6", "#FFB86C", "#BD93F9", "#50FA7B", "#8BE9FD", "#FF5555", "#D77BFF"))
        case .nord:
            return ThemeSpec(background: ["#2E3440"], backgroundStyle: .solid,
                surface: "#3B4252", foreground: "#ECEFF4", secondary: "#9AA6BC", hairline: "#434C5E",
                accent: ["#88C0D0", "#5E81AC"], isDark: true,
                typeColors: Self.ramp("#81A1C1", "#B48EAD", "#D08770", "#88C0D0", "#A3BE8C", "#8FBCBB", "#BF616A", "#9E8CC0"))
        case .vaporwave:
            return ThemeSpec(background: ["#2A1B3D", "#3A2352", "#1B3A4A"], backgroundStyle: .linear,
                surface: "#2E2246", foreground: "#F2E8FF", secondary: "#B9A9E6", hairline: "#3E3160",
                accent: ["#FF6AD5", "#8C6AFF"], isDark: true,
                typeColors: Self.ramp("#8CF0E8", "#FFB8E0", "#FFD08C", "#FF6AD5", "#C6A6FF", "#8CD8F0", "#FF8CC8", "#B0A0FF"))
        case .cyberpunk:
            return ThemeSpec(background: ["#0A0A0F"], backgroundStyle: .solid,
                surface: "#13131C", foreground: "#EAEAF2", secondary: "#8A8AA0", hairline: "#23233A",
                accent: ["#FCEE0A", "#00F0FF"], isDark: true,
                typeColors: Self.ramp("#00F0FF", "#FF00A0", "#FF6A00", "#FCEE0A", "#00FF9F", "#00F0FF", "#FF003C", "#B026FF"))
        case .gruvbox:
            return ThemeSpec(background: ["#282828"], backgroundStyle: .solid,
                surface: "#32302F", foreground: "#EBDBB2", secondary: "#A89984", hairline: "#3C3836",
                accent: ["#FE8019", "#D65D0E"], isDark: true,
                typeColors: Self.ramp("#83A598", "#D3869B", "#FE8019", "#D3869B", "#B8BB26", "#8EC07C", "#FB4934", "#B16286"))
        case .daylight:
            return ThemeSpec(background: ["#F6F3F7", "#EDE9F1"], backgroundStyle: .linear,
                surface: "#FFFFFF", foreground: "#2A2530", secondary: "#8A8290", hairline: "#E6E1EB",
                accent: ["#FF70A3", "#FF4566"], isDark: false,
                typeColors: Self.ramp("#4C82F5", "#A55CE0", "#F0913C", "#E85C9E", "#2FB765", "#2AA9A0", "#E5484D", "#6C5CE0"))
        case .custom:
            return ThemeSpec(background: ["#16141B"], backgroundStyle: .solid,
                surface: "#201D27", foreground: "#ECEAF0", secondary: "#A29AAC", hairline: "#2C2836",
                accent: [customAccentHex, customAccentHex], isDark: true,
                typeColors: Self.ramp("#5C8FFF", "#C77DFF", "#FF9E5C", "#FF6FB0", "#52CC85", "#6FD3C7", "#FF6B6B", "#8A7BFF"))
        }
    }
}
