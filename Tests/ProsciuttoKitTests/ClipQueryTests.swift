import XCTest
@testable import ProsciuttoKit

final class ClipQueryTests: XCTestCase {
    func mk(_ t: String, kind: ClipKind, app: String? = nil) -> ClipItem {
        var i = ClipItem.make(from: PasteboardSnapshot(plainText: t, sourceAppBundleID: app),
                              kind: kind, now: .init(timeIntervalSince1970: 0), ttl: 60)
        i.kind = kind
        return i
    }
    func testTextFilter() {
        var q = ClipQuery(); q.text = "hub"
        let items = [mk("github", kind: .link), mk("apple", kind: .text)]
        XCTAssertEqual(q.apply(to: items).map(\.textPlain), ["github"])
    }
    func testKindFilter() {
        var q = ClipQuery(); q.kinds = [.image]
        let items = [mk("a", kind: .text), mk("b", kind: .image)]
        XCTAssertEqual(q.apply(to: items).count, 1)
    }
    func testEmptyQueryReturnsAll() {
        let items = [mk("a", kind: .text), mk("b", kind: .image)]
        XCTAssertEqual(ClipQuery().apply(to: items).count, 2)
    }
}
