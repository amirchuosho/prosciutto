import SwiftUI

/// Central design tokens. One source of truth for spacing, radius, typography,
/// and surfaces so the whole UI stays consistent. Paste-grade sizing.
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    enum Radius {
        static let card: CGFloat = 18
        static let panel: CGFloat = 24
        static let control: CGFloat = 10
        static let pill: CGFloat = 20
    }

    enum CardSize {
        static let width: CGFloat = 236
        static let height: CGFloat = 300
        static let header: CGFloat = 62
        static let appIcon: CGFloat = 30
    }

    enum Typeface {
        /// Custom display font (bundled). Falls back to system if missing.
        static func display(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            SwiftUI.Font.custom("Outfit", size: size).weight(weight)
        }
    }

    enum Font {
        static let brand = Typeface.display(16, .bold)
        static let cardTitle = Typeface.display(16.5, .bold)      // header type name
        static let cardTime = SwiftUI.Font.system(size: 11.5, weight: .medium)
        static let sectionPill = Typeface.display(13, .semibold)
        static let meta = SwiftUI.Font.system(size: 11, weight: .medium)
        static let shortcut = SwiftUI.Font.system(size: 11, weight: .bold, design: .rounded)
        static let content = SwiftUI.Font.system(size: 14)
        static let contentMono = SwiftUI.Font.system(size: 12.5, design: .monospaced)
        static let title = SwiftUI.Font.system(size: 14, weight: .semibold)
    }
}
