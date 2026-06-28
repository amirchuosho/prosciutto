import SwiftUI

/// App appearance: light/dark/system.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A named accent palette. `custom` reads a user-picked hex from Preferences.
enum AccentTheme: String, CaseIterable, Identifiable {
    case prosciutto, midnight, forest, mono, sunset, grape, ocean, gold, rose, lime, crimson, slate, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prosciutto: return "Prosciutto"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        case .mono: return "Mono"
        case .sunset: return "Sunset"
        case .grape: return "Grape"
        case .ocean: return "Ocean"
        case .gold: return "Gold"
        case .rose: return "Rose"
        case .lime: return "Lime"
        case .crimson: return "Crimson"
        case .slate: return "Slate"
        case .custom: return "Custom"
        }
    }

    func color(customHex: String) -> Color { colors(customHex: customHex)[0] }

    /// Two-stop gradient [start, end] for selection rings / accents.
    func colors(customHex: String) -> [Color] {
        switch self {
        case .prosciutto: return [Color(.sRGB, red: 1.00, green: 0.44, blue: 0.64),   // hot pink
                                  Color(.sRGB, red: 1.00, green: 0.27, blue: 0.40)]   // red
        case .midnight:   return [Color(.sRGB, red: 0.40, green: 0.60, blue: 1.00),
                                  Color(.sRGB, red: 0.36, green: 0.36, blue: 0.98)]
        case .forest:     return [Color(.sRGB, red: 0.36, green: 0.84, blue: 0.56),
                                  Color(.sRGB, red: 0.09, green: 0.64, blue: 0.40)]
        case .mono:       return [Color(.sRGB, red: 0.86, green: 0.88, blue: 0.92),
                                  Color(.sRGB, red: 0.62, green: 0.64, blue: 0.70)]
        case .sunset:   return [Color(.sRGB, red: 1.00, green: 0.55, blue: 0.26),
                                Color(.sRGB, red: 1.00, green: 0.30, blue: 0.45)]
        case .grape:    return [Color(.sRGB, red: 0.66, green: 0.40, blue: 1.00),
                                Color(.sRGB, red: 0.50, green: 0.25, blue: 0.95)]
        case .ocean:    return [Color(.sRGB, red: 0.30, green: 0.80, blue: 0.85),
                                Color(.sRGB, red: 0.20, green: 0.55, blue: 0.85)]
        case .gold:     return [Color(.sRGB, red: 1.00, green: 0.80, blue: 0.30),
                                Color(.sRGB, red: 0.95, green: 0.60, blue: 0.15)]
        case .rose:     return [Color(.sRGB, red: 1.00, green: 0.45, blue: 0.75),
                                Color(.sRGB, red: 0.85, green: 0.30, blue: 0.60)]
        case .lime:     return [Color(.sRGB, red: 0.70, green: 0.90, blue: 0.30),
                                Color(.sRGB, red: 0.45, green: 0.78, blue: 0.25)]
        case .crimson:  return [Color(.sRGB, red: 1.00, green: 0.40, blue: 0.40),
                                Color(.sRGB, red: 0.80, green: 0.15, blue: 0.25)]
        case .slate:    return [Color(.sRGB, red: 0.55, green: 0.62, blue: 0.72),
                                Color(.sRGB, red: 0.36, green: 0.42, blue: 0.52)]
        case .custom:     let c = Color(hex: customHex) ?? .accentColor; return [c, c]
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var appearance: Appearance {
        didSet { Preferences.shared.appearanceRaw = appearance.rawValue }
    }
    @Published var accentTheme: AccentTheme {
        didSet { Preferences.shared.accentThemeRaw = accentTheme.rawValue }
    }
    @Published var customAccentHex: String {
        didSet { Preferences.shared.customAccentHex = customAccentHex }
    }

    init() {
        appearance = Appearance(rawValue: Preferences.shared.appearanceRaw) ?? .system
        accentTheme = AccentTheme(rawValue: Preferences.shared.accentThemeRaw) ?? .prosciutto
        customAccentHex = Preferences.shared.customAccentHex
    }

    var accent: Color { accentTheme.color(customHex: customAccentHex) }
    var accentColors: [Color] { accentTheme.colors(customHex: customAccentHex) }
    var accentGradient: LinearGradient {
        LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var colorScheme: ColorScheme? { appearance.colorScheme }
}
