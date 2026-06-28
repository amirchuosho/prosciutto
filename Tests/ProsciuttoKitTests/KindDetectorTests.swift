import XCTest
@testable import ProsciuttoKit

final class KindDetectorTests: XCTestCase {
    func snap(_ t: String) -> PasteboardSnapshot { PasteboardSnapshot(plainText: t) }

    func testColor() { XCTAssertEqual(KindDetector.detect(snap("#3FA9FF")), .color) }
    func testColorShort() { XCTAssertEqual(KindDetector.detect(snap("#fff")), .color) }
    func testLink() { XCTAssertEqual(KindDetector.detect(snap("https://github.com/p0deje/Maccy")), .link) }
    func testPlainText() { XCTAssertEqual(KindDetector.detect(snap("just some words here")), .text) }
    func testCode() { XCTAssertEqual(KindDetector.detect(snap("func foo() { return 1 }")), .code) }
    func testMinifiedJSONObjectIsCode() {
        XCTAssertEqual(KindDetector.detect(snap("{\"a\":1,\"b\":[2,3]}")), .code)
    }
    func testJSONArrayIsCode() {
        XCTAssertEqual(KindDetector.detect(snap("[1, 2, 3]")), .code)
    }
    func testJSONScalarIsNotCode() {
        // A bare string/number is valid JSON-with-fragments but must not be code.
        XCTAssertEqual(KindDetector.detect(snap("hello world")), .text)
    }
    func testImage() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(imageData: Data([0x89, 0x50]))), .image)
    }
    func testFile() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/x")])), .file)
    }
    func testImageFileDetectedAsImage() {
        let png = PasteboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/Shot.PNG")])
        XCTAssertEqual(KindDetector.detect(png), .image)
        let jpg = PasteboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/pic.jpeg")])
        XCTAssertEqual(KindDetector.detect(jpg), .image)
    }
    func testEmpty() { XCTAssertNil(KindDetector.detect(PasteboardSnapshot())) }
}
