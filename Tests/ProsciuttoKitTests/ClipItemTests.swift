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

    func testFileStoresPathAsText() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot.png")
        let snap = PasteboardSnapshot(fileURLs: [url])
        let item = ClipItem.make(from: snap, kind: .file, now: Date(), ttl: 60)
        XCTAssertEqual(item.textPlain, "/tmp/Screenshot.png")
    }

    // An image FILE copied from Finder carries the file's ICON as pasteboard
    // .png/.tiff. We must NOT keep that icon as imageData; the card renders the
    // real file from the path instead. Otherwise it shows the grey doc icon.
    // NOTE: image-FILE clips used to drop their imageData here. That icon-stripping now
    // lives in the capture reader (it supplies real file bytes or nil, never the icon),
    // so `make` keeps whatever the snapshot carries — see DurableImageTests
    // (make-keeps-bytes) and ImageFileBytesTests (reader strips the icon).

    // A real image-DATA clip (screenshot, no file) keeps its imageData.
    func testImageDataClipKeepsData() {
        let bytes = Data([1, 2, 3, 4])
        let snap = PasteboardSnapshot(imageData: bytes)
        let item = ClipItem.make(from: snap, kind: .image, now: Date(), ttl: 60)
        XCTAssertEqual(item.imageData, bytes)
    }
}
