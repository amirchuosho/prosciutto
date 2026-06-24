import XCTest
@testable import ProsciuttoKit

final class ClipItemTests: XCTestCase {
    func testMakeFromTextSnapshot() {
        let now = Date(timeIntervalSince1970: 1000)
        let snap = PasteboardSnapshot(plainText: "hello", sourceAppBundleID: "com.test")
        let item = ClipItem.make(from: snap, kind: .text, now: now, ttl: 60)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.textPlain, "hello")
        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(item.createdAt, now)
        XCTAssertEqual(item.expiresAt, now.addingTimeInterval(60))
        XCTAssertFalse(item.contentHash.isEmpty)
    }
}
