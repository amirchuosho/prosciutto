import XCTest
import SwiftUI
import ProsciuttoKit
@testable import Prosciutto

final class ThemePaletteTests: XCTestCase {
    func testPaletteBuildsFromSpecAndResolvesKinds() {
        let palette = ThemePalette(AppTheme.dracula.spec(customAccentHex: "#F56B8C"))
        XCTAssertEqual(palette.accent.count, 2)
        // every kind resolves to a color (no crash, non-optional)
        for kind in [ClipKind.text, .rtf, .link, .image, .color, .code, .file, .location] {
            _ = palette.color(for: kind)
        }
        XCTAssertTrue(palette.isDark)
    }
}
