import XCTest
@testable import ProsciuttoKit

final class FakeReader: PasteboardReader {
    var changeCount = 0
    var next: PasteboardSnapshot?
    func snapshot() -> PasteboardSnapshot? { next }
}

struct FixedClock: Clock { var t: Date; func now() -> Date { t } }

final class ClipboardMonitorTests: XCTestCase {
    func testPollCapturesNewItem() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: Date(timeIntervalSince1970: 0)), ttl: 60)

        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "copied text")
        try await monitor.poll()

        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].textPlain, "copied text")
    }

    func testAcknowledgeSelfWriteSkipsOurOwnPaste() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60)
        // The app writes to the pasteboard (e.g. a paste) and acknowledges it.
        reader.changeCount = 5
        reader.next = PasteboardSnapshot(plainText: "pasted")
        monitor.acknowledgeSelfWrite()
        try await monitor.poll()
        // That write must NOT become a new clip.
        let count = try await store.all().count
        XCTAssertEqual(count, 0)
    }

    func testPollIgnoresUnchangedCount() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60)
        reader.changeCount = 0
        reader.next = PasteboardSnapshot(plainText: "x")
        try await monitor.poll()
        let items = try await store.all()
        XCTAssertEqual(items.count, 0)
    }

    func testPollRespectsExclusion() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60)
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "secret", markerTypes: [ExclusionPolicy.concealedType])
        try await monitor.poll()
        let count = try await store.all().count
        XCTAssertEqual(count, 0)
    }

    func testSkipsDisabledType() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60,
            captureFilter: CaptureFilter.from(saveText: false, saveImages: true, saveFiles: true, saveVideos: true, maxBytes: 0))
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "some text")
        try await monitor.poll()
        let count = try await store.all().count
        XCTAssertEqual(count, 0)
    }
    func testSkipsOversized() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60,
            captureFilter: CaptureFilter(enabledKinds: CaptureFilter.allKinds, maxBytes: 4))
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "way too long")
        try await monitor.poll()
        let count = try await store.all().count
        XCTAssertEqual(count, 0)
    }
}
