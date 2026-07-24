import XCTest
@testable import ProsciuttoKit

final class DurableImageTests: XCTestCase {
    private func snap(files: [URL] = [], imageData: Data? = nil) -> PasteboardSnapshot {
        PasteboardSnapshot(imageData: imageData, fileURLs: files)
    }

    func testSingleImageFileReturnsURL() {
        let u = URL(fileURLWithPath: "/tmp/pic.png")
        XCTAssertEqual(KindDetector.singleImageFileURL(in: snap(files: [u])), u)
    }

    func testSingleNonImageFileReturnsNil() {
        XCTAssertNil(KindDetector.singleImageFileURL(in: snap(files: [URL(fileURLWithPath: "/tmp/a.pdf")])))
    }

    func testMultipleFilesReturnsNil() {
        let a = URL(fileURLWithPath: "/tmp/a.png"), b = URL(fileURLWithPath: "/tmp/b.png")
        XCTAssertNil(KindDetector.singleImageFileURL(in: snap(files: [a, b])))
    }

    func testBytesOnlySnapshotReturnsNil() {
        XCTAssertNil(KindDetector.singleImageFileURL(in: snap(imageData: Data([1, 2, 3]))))
    }

    func testExtensionMatchIsCaseInsensitive() {
        let u = URL(fileURLWithPath: "/tmp/Photo.JPG")
        XCTAssertEqual(KindDetector.singleImageFileURL(in: snap(files: [u])), u)
    }

    private func imageFileSnap(bytes: Data?) -> PasteboardSnapshot {
        PasteboardSnapshot(imageData: bytes, fileURLs: [URL(fileURLWithPath: "/tmp/pic.png")])
    }

    func testMakeKeepsRealBytesForImageFile() {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let clip = ClipItem.make(from: imageFileSnap(bytes: bytes), kind: .image,
                                 now: Date(timeIntervalSince1970: 0), ttl: 0)
        XCTAssertEqual(clip.imageData, bytes, "image-file clip keeps the real bytes the reader supplied")
        XCTAssertEqual(clip.textPlain, "/tmp/pic.png", "path still stored for paste-as-file + dedupe")
    }

    func testMakeImageFileWithNilBytesStaysPathOnly() {
        let clip = ClipItem.make(from: imageFileSnap(bytes: nil), kind: .image,
                                 now: Date(timeIntervalSince1970: 0), ttl: 0)
        XCTAssertNil(clip.imageData, "no bytes supplied → path-only, as before")
        XCTAssertEqual(clip.textPlain, "/tmp/pic.png")
    }

    func testMakeDropsImageDataForVideo() {
        let snap = PasteboardSnapshot(imageData: Data([1, 2]), fileURLs: [URL(fileURLWithPath: "/tmp/v.mov")])
        let clip = ClipItem.make(from: snap, kind: .video, now: Date(timeIntervalSince1970: 0), ttl: 0)
        XCTAssertNil(clip.imageData, "video handling unchanged: thumbnail regenerated from disk, not stored here")
    }

    func testMakeImageFileDedupeHashIsByPath() {
        let a = ClipItem.make(from: imageFileSnap(bytes: Data([1])), kind: .image, now: Date(), ttl: 0)
        let b = ClipItem.make(from: imageFileSnap(bytes: Data([2, 2])), kind: .image, now: Date(), ttl: 0)
        XCTAssertEqual(a.contentHash, b.contentHash, "same path → same hash regardless of bytes (dedupe unchanged)")
    }
}
