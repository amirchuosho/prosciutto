import XCTest
@testable import ProsciuttoKit

final class ClipKindTests: XCTestCase {
    func testEditableKinds() {
        for kind in [ClipKind.text, .rtf, .code, .link, .color] {
            XCTAssertTrue(kind.isEditable, "\(kind) should be editable")
        }
    }
    func testNonEditableKinds() {
        XCTAssertFalse(ClipKind.image.isEditable)
        XCTAssertFalse(ClipKind.file.isEditable)
    }
}
