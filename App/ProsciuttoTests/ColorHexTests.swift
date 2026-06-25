import XCTest
import SwiftUI
@testable import Prosciutto

final class ColorHexTests: XCTestCase {
    func testParseSixDigit() {
        XCTAssertEqual(Color(hex: "#FF0000")?.toHex(), "#FF0000")
        XCTAssertEqual(Color(hex: "#3FA9FF")?.toHex(), "#3FA9FF")
    }
    func testParseThreeDigitExpands() {
        XCTAssertEqual(Color(hex: "#fff")?.toHex(), "#FFFFFF")
        XCTAssertEqual(Color(hex: "#000")?.toHex(), "#000000")
    }
    func testParseWithoutHash() {
        XCTAssertEqual(Color(hex: "00FF00")?.toHex(), "#00FF00")
    }
    func testInvalidReturnsNil() {
        XCTAssertNil(Color(hex: "not-a-color"))
        XCTAssertNil(Color(hex: "#GG0000"))
        XCTAssertNil(Color(hex: "#12345"))
    }
}
