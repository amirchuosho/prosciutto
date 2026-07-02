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
    func testCoordinatesAreLocation() {
        XCTAssertEqual(KindDetector.detect(snap("37.7749,-122.4194")), .location)
        XCTAssertEqual(KindDetector.detect(snap("40.7128, -74.0060")), .location)
    }
    func testInvalidCoordinatesNotLocation() {
        XCTAssertEqual(KindDetector.detect(snap("999.0, 500.0")), .text)   // out of range
        XCTAssertEqual(KindDetector.detect(snap("1,2,3")), .text)
    }
    func testAddressIsLocation() {
        XCTAssertEqual(KindDetector.detect(snap("1 Infinite Loop, Cupertino, CA 95014")), .location)
    }
    func testInternationalAddressIsLocation() {
        // NSDataDetector misses non-US formats; the heuristic (street word + digit
        // + comma) catches them.
        XCTAssertEqual(KindDetector.detect(snap("Rishon LeTsiyon St 1, Petah Tikva")), .location)
        XCTAssertEqual(KindDetector.detect(snap("רחוב הרצל 5, תל אביב")), .location)
    }
    func testCommaListIsNotLocation() {
        XCTAssertEqual(KindDetector.detect(snap("buy milk, eggs, 2 loaves of bread")), .text)
    }
    func testPlainSentenceNotLocation() {
        XCTAssertEqual(KindDetector.detect(snap("let us meet for lunch tomorrow")), .text)
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
