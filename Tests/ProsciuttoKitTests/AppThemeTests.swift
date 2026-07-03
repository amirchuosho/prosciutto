// Tests/ProsciuttoKitTests/AppThemeTests.swift
import XCTest
@testable import ProsciuttoKit

final class AppThemeTests: XCTestCase {
    func testThemeSpecRtfFallsBackToText() {
        let spec = ThemeSpec(
            background: ["#000000"], backgroundStyle: .solid,
            surface: "#111111", foreground: "#FFFFFF", secondary: "#AAAAAA",
            hairline: "#222222", accent: ["#FF0000", "#AA0000"],
            isDark: true, typeColors: [.text: "#5C8FFF"])
        XCTAssertEqual(spec.hex(for: .rtf), "#5C8FFF")
        XCTAssertEqual(spec.hex(for: .text), "#5C8FFF")
    }
}

extension AppThemeTests {
    func testEveryThemeResolvesAll7Kinds() {
        let kinds: [ClipKind] = [.text, .link, .image, .color, .code, .file, .location]
        for theme in AppTheme.allCases {
            let spec = theme.spec(customAccentHex: "#F56B8C")
            for kind in kinds {
                let hex = spec.hex(for: kind)
                XCTAssertTrue(isValidHex(hex), "\(theme.rawValue) \(kind) -> \(hex)")
            }
            XCTAssertEqual(spec.accent.count, 2, "\(theme.rawValue) accent stops")
            XCTAssertFalse(spec.background.isEmpty, "\(theme.rawValue) background")
            XCTAssertTrue(isValidHex(spec.surface) && isValidHex(spec.foreground)
                          && isValidHex(spec.secondary) && isValidHex(spec.hairline))
        }
    }

    func testDaylightIsLightRestAreDark() {
        XCTAssertFalse(AppTheme.daylight.spec(customAccentHex: "#000000").isDark)
        for t in AppTheme.allCases where t != .daylight {
            XCTAssertTrue(t.spec(customAccentHex: "#000000").isDark, "\(t.rawValue)")
        }
    }

    func testCustomUsesProvidedAccent() {
        let spec = AppTheme.custom.spec(customAccentHex: "#123456")
        XCTAssertEqual(spec.accent.first, "#123456")
    }

    private func isValidHex(_ s: String) -> Bool {
        let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        return h.count == 6 && h.allSatisfy { $0.isHexDigit }
    }
}
