import XCTest
@testable import Prosciutto

final class ImageFileBytesTests: XCTestCase {
    private func tempFile(bytes: Data) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pic.png")
        try bytes.write(to: url)
        return url
    }

    func testReadsBytesWhenNoCap() throws {
        let bytes = Data(repeating: 7, count: 1000)
        let url = try tempFile(bytes: bytes)
        XCTAssertEqual(SystemPasteboardReader.imageFileBytes(url: url, maxBytes: 0), bytes)
    }

    func testReturnsNilWhenOverCap() throws {
        let url = try tempFile(bytes: Data(repeating: 7, count: 1000))
        XCTAssertNil(SystemPasteboardReader.imageFileBytes(url: url, maxBytes: 500))
    }

    func testReadsWhenUnderCap() throws {
        let bytes = Data(repeating: 7, count: 400)
        let url = try tempFile(bytes: bytes)
        XCTAssertEqual(SystemPasteboardReader.imageFileBytes(url: url, maxBytes: 500), bytes)
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(SystemPasteboardReader.imageFileBytes(url: URL(fileURLWithPath: "/no/such.png"), maxBytes: 0))
    }
}
