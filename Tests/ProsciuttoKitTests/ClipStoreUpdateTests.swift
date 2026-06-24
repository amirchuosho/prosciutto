import XCTest
@testable import ProsciuttoKit

final class ClipStoreUpdateTests: XCTestCase {
    func testUpdateReplacesFields() async throws {
        let store = InMemoryClipStore()
        let now = Date(timeIntervalSince1970: 0)
        var item = ClipItem.make(from: PasteboardSnapshot(plainText: "old"), kind: .text, now: now, ttl: 60)
        try await store.upsert(item)

        item.textPlain = "new"
        try await store.update(item)

        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].textPlain, "new")
    }

    func testUpdateMissingIsNoOp() async throws {
        let store = InMemoryClipStore()
        let now = Date(timeIntervalSince1970: 0)
        let item = ClipItem.make(from: PasteboardSnapshot(plainText: "x"), kind: .text, now: now, ttl: 60)
        try await store.update(item)
        let items = try await store.all()
        XCTAssertTrue(items.isEmpty)
    }
}
