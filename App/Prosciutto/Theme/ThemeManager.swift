import SwiftUI
import ProsciuttoKit

@MainActor
final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme {
        didSet {
            Preferences.shared.themeRaw = theme.rawValue
            palette = ThemeManager.makePalette(theme, customAccentHex)
        }
    }
    @Published var customAccentHex: String {
        didSet {
            Preferences.shared.customAccentHex = customAccentHex
            palette = ThemeManager.makePalette(theme, customAccentHex)
        }
    }

    @Published private(set) var palette: ThemePalette

    init() {
        let t = AppTheme(rawValue: Preferences.shared.themeRaw) ?? .prosciutto
        let hex = Preferences.shared.customAccentHex
        theme = t
        customAccentHex = hex
        palette = ThemeManager.makePalette(t, hex)
    }

    private static func makePalette(_ t: AppTheme, _ hex: String) -> ThemePalette {
        ThemePalette(t.spec(customAccentHex: hex))
    }

    var accent: Color { palette.accent[0] }
    var accentColors: [Color] { palette.accent }
    var accentGradient: LinearGradient { palette.accentGradient }
    var colorScheme: ColorScheme? { palette.isDark ? .dark : .light }
}
