import XCTest
@testable import ProsciuttoKit

/// Imported Paste items must not be swept away by recency-based retention. The
/// importer keeps each clip's ORIGINAL creation date (honest display) but marks it as
/// just-used, so a history full of months-old items survives the age prune. These
/// tests pin that timestamp logic.
final class PasteImportTimestampTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testKeepsOriginalCreatedAt() {
        let original = Date(timeIntervalSince1970: 500)   // ancient
        let t = PasteImporter.importTimestamps(originalCreatedAt: original, index: 0, now: now)
        XCTAssertEqual(t.createdAt, original, "original creation date preserved for honest display")
    }

    func testNilCreatedAtFallsBackToNow() {
        let t = PasteImporter.importTimestamps(originalCreatedAt: nil, index: 0, now: now)
        XCTAssertEqual(t.createdAt, now)
    }

    func testLastUsedIsRecentRegardlessOfAge() {
        let ancient = Date(timeIntervalSince1970: 500)
        let t = PasteImporter.importTimestamps(originalCreatedAt: ancient, index: 0, now: now)
        // Marked just-used: within the default 7-day retention window, so it survives prune.
        XCTAssertLessThanOrEqual(t.lastUsedAt, now)
        XCTAssertGreaterThan(t.lastUsedAt, now.addingTimeInterval(-RetentionPolicy().maxAge))
    }

    func testStaggerPreservesImportOrder() {
        let a = PasteImporter.importTimestamps(originalCreatedAt: nil, index: 0, now: now)
        let b = PasteImporter.importTimestamps(originalCreatedAt: nil, index: 1, now: now)
        let c = PasteImporter.importTimestamps(originalCreatedAt: nil, index: 2, now: now)
        // Earlier import index (newer clip) sorts ahead by lastUsedAt — no ties to scramble.
        XCTAssertGreaterThan(a.lastUsedAt, b.lastUsedAt)
        XCTAssertGreaterThan(b.lastUsedAt, c.lastUsedAt)
    }

    func testLargeImportStaysWithinRetentionWindow() {
        // Even a very large history keeps its oldest imported item well inside 7 days.
        let t = PasteImporter.importTimestamps(originalCreatedAt: nil, index: 5000, now: now)
        XCTAssertGreaterThan(t.lastUsedAt, now.addingTimeInterval(-RetentionPolicy().maxAge))
    }
}
