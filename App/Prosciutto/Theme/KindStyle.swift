import SwiftUI
import AppKit
import ProsciuttoKit

/// Per-content-kind visual identity: icon and short label.
/// Drives the colored card header and per-type accents.
struct KindStyle {
    let icon: String
    let label: String

    /// Title-case name for the header ("Text", "Link", "Code").
    var title: String { label.capitalized }

    static func of(_ kind: ClipKind) -> KindStyle {
        switch kind {
        case .text:
            return KindStyle(icon: "text.alignleft", label: "TEXT")
        case .rtf:
            return KindStyle(icon: "doc.richtext", label: "RICH")
        case .link:
            return KindStyle(icon: "link", label: "LINK")
        case .image:
            return KindStyle(icon: "photo", label: "IMAGE")
        case .color:
            return KindStyle(icon: "paintpalette", label: "COLOR")
        case .code:
            return KindStyle(icon: "chevron.left.forwardslash.chevron.right", label: "CODE")
        case .file:
            return KindStyle(icon: "doc", label: "FILE")
        case .location:
            return KindStyle(icon: "mappin.and.ellipse", label: "PLACE")
        }
    }
}
