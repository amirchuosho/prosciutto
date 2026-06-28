import XCTest
import Carbon.HIToolbox
@testable import Prosciutto

final class KeyComboTests: XCTestCase {
    func testCarbonModifiersForCommandShift() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | shiftKey))
    }
    func testCarbonModifiersForCommandOption() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | optionKey))
    }
    func testDisplayStringOrdersGlyphs() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(c.displayString, "⇧⌘V")
    }
    func testRoundTripStored() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        let r = KeyCombo(storedKeyCode: Int(c.keyCode), storedModifiers: Int(c.modifiers.rawValue))
        XCTAssertEqual(c, r)
    }
}
