import XCTest
import ProsciuttoKit
@testable import Prosciutto

final class CoreDataClipStoreTests: XCTestCase {
    func testUpsertAndDedup() async throws {
        let store = CoreDataClipStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 0)
        let a = ClipItem.make(from: .init(plainText: "hi"), kind: .text, now: now, ttl: 60)
        try await store.upsert(a)
        try await store.upsert(a)
        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].useCount, 2)
    }
}
