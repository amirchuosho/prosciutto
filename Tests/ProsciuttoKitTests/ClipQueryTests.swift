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
    func testMatchesTitle() {
        var item = mk("123456", kind: .text)
        item.title = "Instagram password"
        var q = ClipQuery(); q.text = "instagram"
        XCTAssertEqual(q.apply(to: [item]).count, 1)
        // and the body still doesn't match "instagram"
        var q2 = ClipQuery(); q2.text = "instagram"
        XCTAssertEqual(q2.apply(to: [mk("123456", kind: .text)]).count, 0)
    }
    func testEmptyQueryReturnsAll() {
        let items = [mk("a", kind: .text), mk("b", kind: .image)]
        XCTAssertEqual(ClipQuery().apply(to: items).count, 2)
    }
    func testFuzzyFiltersSubsequence() {
        var q = ClipQuery(); q.text = "prsc"; q.fuzzy = true
        let out = q.apply(to: [mk("prosciutto", kind: .text), mk("banana", kind: .text)]).map(\.textPlain)
        XCTAssertEqual(out, ["prosciutto"])
    }
    func testFuzzyRanksByScore() {
        var q = ClipQuery(); q.text = "pro"; q.fuzzy = true
        let out = q.apply(to: [mk("a p r o", kind: .text), mk("prologue", kind: .text)]).map(\.textPlain)
        XCTAssertEqual(out.first, "prologue")   // contiguous beats scattered
    }
    func testNonFuzzyStillSubstring() {
        var q = ClipQuery(); q.text = "ana"; q.fuzzy = false
        let out = q.apply(to: [mk("banana", kind: .text), mk("prosciutto", kind: .text)]).map(\.textPlain)
        XCTAssertEqual(out, ["banana"])
    }
}
