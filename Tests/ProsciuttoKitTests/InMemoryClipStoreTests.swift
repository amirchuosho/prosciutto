import XCTest
@testable import ProsciuttoKit

final class InMemoryClipStoreTests: XCTestCase {
    func makeItem(_ text: String, now: Date) -> ClipItem {
        ClipItem.make(from: PasteboardSnapshot(plainText: text), kind: .text, now: now, ttl: 60)
    }

    func testUpsertDedup() async throws {
        let store = InMemoryClipStore()
        let t0 = Date(timeIntervalSince1970: 0)
        try await store.upsert(makeItem("hello", now: t0))
        try await store.upsert(makeItem("hello", now: t0.addingTimeInterval(10)))
        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].useCount, 2)
        XCTAssertEqual(items[0].lastUsedAt, t0.addingTimeInterval(10))
    }

    func testOrderingNewestFirst() async throws {
        let store = InMemoryClipStore()
        let t0 = Date(timeIntervalSince1970: 0)
        try await store.upsert(makeItem("a", now: t0))
        try await store.upsert(makeItem("b", now: t0.addingTimeInterval(5)))
        let items = try await store.all()
        XCTAssertEqual(items.map(\.textPlain), ["b", "a"])
    }
}
