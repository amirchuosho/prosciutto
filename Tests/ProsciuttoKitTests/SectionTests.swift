import XCTest
@testable import ProsciuttoKit

final class SectionTests: XCTestCase {
    func testCreateAssignAndDelete() async throws {
        let store = InMemoryClipStore()
        let now = Date(timeIntervalSince1970: 0)
        let item = ClipItem.make(from: PasteboardSnapshot(plainText: "hi"), kind: .text, now: now, ttl: 60)
        try await store.upsert(item)

        let work = try await store.createSection(name: "Work", colorHex: "#FF0000")
        var sections = try await store.sections()
        XCTAssertEqual(sections.map(\.name), ["Work"])

        try await store.assign(itemID: item.id, to: work.id)
        var stored = try await store.all().first
        XCTAssertEqual(stored?.sectionID, work.id)

        try await store.deleteSection(id: work.id)
        sections = try await store.sections()
        XCTAssertTrue(sections.isEmpty)
        stored = try await store.all().first
        XCTAssertNil(stored?.sectionID)   // items un-filed, not deleted
    }
}
