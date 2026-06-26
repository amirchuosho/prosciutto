import SwiftUI

/// Central design tokens. One source of truth for spacing, radius, typography,
/// and the neutral surface/stroke colors so the whole UI stays consistent.
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 12
        static let panel: CGFloat = 20
        static let control: CGFloat = 8
    }

    enum CardSize {
        static let width: CGFloat = 196
        static let height: CGFloat = 224
    }

    // Neutral surfaces / strokes (work on the dark glass panel)
    static let cardStroke = Color.white.opacity(0.08)
    static let cardStrokeSelected = Color.accentColor          // overridden with theme accent at call site
    static let hairline = Color.white.opacity(0.06)

    enum Font {
        static let brand = SwiftUI.Font.system(size: 15, weight: .bold, design: .rounded)
        static let typeLabel = SwiftUI.Font.system(size: 9.5, weight: .bold)   // tracked, uppercase
        static let meta = SwiftUI.Font.system(size: 10, weight: .medium)
        static let shortcut = SwiftUI.Font.system(size: 9.5, weight: .semibold, design: .rounded)
        static let content = SwiftUI.Font.system(size: 12.5)
        static let contentMono = SwiftUI.Font.system(size: 11, design: .monospaced)
        static let title = SwiftUI.Font.system(size: 12.5, weight: .semibold)
    }
}
