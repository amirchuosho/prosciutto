import XCTest
@testable import ProsciuttoKit

final class KindDetectorTests: XCTestCase {
    func snap(_ t: String) -> PasteboardSnapshot { PasteboardSnapshot(plainText: t) }

    func testColor() { XCTAssertEqual(KindDetector.detect(snap("#3FA9FF")), .color) }
    func testColorShort() { XCTAssertEqual(KindDetector.detect(snap("#fff")), .color) }
    func testLink() { XCTAssertEqual(KindDetector.detect(snap("https://github.com/p0deje/Maccy")), .link) }
    func testPlainText() { XCTAssertEqual(KindDetector.detect(snap("just some words here")), .text) }
    func testCode() { XCTAssertEqual(KindDetector.detect(snap("func foo() { return 1 }")), .code) }
    func testImage() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(imageData: Data([0x89, 0x50]))), .image)
    }
    func testFile() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/x")])), .file)
    }
    func testEmpty() { XCTAssertNil(KindDetector.detect(PasteboardSnapshot())) }
}
