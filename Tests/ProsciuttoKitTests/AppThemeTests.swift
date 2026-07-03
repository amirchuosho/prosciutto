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
