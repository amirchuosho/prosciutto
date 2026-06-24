import SwiftUI
import ProsciuttoKit

/// Per-content-kind visual identity: color, icon, and short label.
/// Drives the colored type badge and the card's kind tint.
struct KindStyle {
    let color: Color
    let icon: String
    let label: String

    static func of(_ kind: ClipKind) -> KindStyle {
        switch kind {
        case .text:
            return KindStyle(color: Color(.sRGB, red: 0.45, green: 0.62, blue: 1.0),
                             icon: "text.alignleft", label: "TEXT")
        case .rtf:
            return KindStyle(color: Color(.sRGB, red: 0.55, green: 0.60, blue: 0.95),
                             icon: "doc.richtext", label: "RICH")
        case .link:
            return KindStyle(color: Color(.sRGB, red: 0.30, green: 0.80, blue: 0.55),
                             icon: "link", label: "LINK")
        case .image:
            return KindStyle(color: Color(.sRGB, red: 0.74, green: 0.50, blue: 1.0),
                             icon: "photo", label: "IMAGE")
        case .color:
            return KindStyle(color: Color(.sRGB, red: 1.0, green: 0.58, blue: 0.40),
                             icon: "paintpalette", label: "COLOR")
        case .code:
            return KindStyle(color: Color(.sRGB, red: 0.30, green: 0.82, blue: 0.80),
                             icon: "chevron.left.forwardslash.chevron.right", label: "CODE")
        case .file:
            return KindStyle(color: Color(.sRGB, red: 1.0, green: 0.78, blue: 0.35),
                             icon: "doc", label: "FILE")
        }
    }
}
