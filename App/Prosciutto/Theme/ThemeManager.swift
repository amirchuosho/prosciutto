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
    case prosciutto, midnight, forest, mono, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prosciutto: return "Prosciutto"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        case .mono: return "Mono"
        case .custom: return "Custom"
        }
    }

    func color(customHex: String) -> Color {
        switch self {
        case .prosciutto: return Color(.sRGB, red: 0.96, green: 0.42, blue: 0.55) // ham pink
        case .midnight:   return Color(.sRGB, red: 0.40, green: 0.56, blue: 1.00)
        case .forest:     return Color(.sRGB, red: 0.32, green: 0.80, blue: 0.52)
        case .mono:       return Color(.sRGB, red: 0.78, green: 0.80, blue: 0.85)
        case .custom:     return Color(hex: customHex) ?? .accentColor
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
    var colorScheme: ColorScheme? { appearance.colorScheme }
}
