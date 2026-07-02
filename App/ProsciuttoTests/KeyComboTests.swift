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
    func testMatchesSameKeyAndMods() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        XCTAssertTrue(c.matches(keyCode: 9, modifiers: [.command, .option]))
    }
    func testMatchesIgnoresDeviceFlags() {
        // A real event may carry .function / capsLock bits; only the
        // device-independent modifiers should be compared.
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        XCTAssertTrue(c.matches(keyCode: 9, modifiers: [.command, .option, .function]))
    }
    func testMatchesRejectsDifferentMods() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        XCTAssertFalse(c.matches(keyCode: 9, modifiers: [.command]))
        XCTAssertFalse(c.matches(keyCode: 8, modifiers: [.command, .option]))
    }
    // A plain-paste combo WITHOUT command must still match (the bug: the old
    // key monitor only checked plain-paste inside `if mods.contains(.command)`).
    func testMatchesNonCommandCombo() {
        let c = KeyCombo(keyCode: 9, modifiers: [.option, .shift])
        XCTAssertTrue(c.matches(keyCode: 9, modifiers: [.option, .shift]))
    }
}
