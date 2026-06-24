import XCTest
@testable import ProsciuttoKit

final class RetentionPolicyTests: XCTestCase {
    func item(_ name: String, age: TimeInterval, pinned: Bool, now: Date) -> ClipItem {
        var it = ClipItem.make(from: PasteboardSnapshot(plainText: name), kind: .text,
                               now: now.addingTimeInterval(-age), ttl: 60)
        it.lastUsedAt = now.addingTimeInterval(-age)
        it.isPinned = pinned
        return it
    }
    func testDropsOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 100, maxAge: 1000)
        let items = [item("old", age: 2000, pinned: false, now: now),
                     item("new", age: 100, pinned: false, now: now)]
        let s = p.survivors(of: items, now: now).map(\.textPlain)
        XCTAssertEqual(s, ["new"])
    }
    func testKeepsPinnedEvenOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 100, maxAge: 1000)
        let items = [item("oldpinned", age: 99999, pinned: true, now: now)]
        XCTAssertEqual(p.survivors(of: items, now: now).count, 1)
    }
    func testCapsCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 2, maxAge: 999999)
        let items = (0..<5).map { item("i\($0)", age: TimeInterval($0), pinned: false, now: now) }
        XCTAssertEqual(p.survivors(of: items, now: now).count, 2)
    }
}
