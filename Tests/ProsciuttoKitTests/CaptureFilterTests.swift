import XCTest
@testable import ProsciuttoKit

final class CaptureFilterTests: XCTestCase {
    func testUnrestrictedAllowsEverything() {
        let f = CaptureFilter.unrestricted
        XCTAssertTrue(f.shouldCapture(kind: .image, byteSize: 99_000_000))
        XCTAssertTrue(f.shouldCapture(kind: .text, byteSize: 0))
    }
    func testTypeDisabledRejected() {
        let f = CaptureFilter.from(saveText: true, saveImages: false, saveFiles: true, saveVideos: true, maxBytes: 0)
        XCTAssertFalse(f.shouldCapture(kind: .image, byteSize: 10))
        XCTAssertTrue(f.shouldCapture(kind: .code, byteSize: 10))   // code maps to Text
        XCTAssertTrue(f.shouldCapture(kind: .file, byteSize: 10))
    }
    func testSizeCap() {
        let f = CaptureFilter.from(saveText: true, saveImages: true, saveFiles: true, saveVideos: true, maxBytes: 1000)
        XCTAssertTrue(f.shouldCapture(kind: .image, byteSize: 1000))
        XCTAssertFalse(f.shouldCapture(kind: .image, byteSize: 1001))
    }
    func testZeroMaxBytesMeansNoLimit() {
        let f = CaptureFilter.from(saveText: true, saveImages: true, saveFiles: true, saveVideos: true, maxBytes: 0)
        XCTAssertTrue(f.shouldCapture(kind: .text, byteSize: 5_000_000))
    }
    func testVideoFollowsItsOwnToggle() {
        // Video is a first-class type with its own toggle, independent of Files.
        let onlyVideos = CaptureFilter.from(saveText: false, saveImages: false, saveFiles: false, saveVideos: true, maxBytes: 0)
        XCTAssertTrue(onlyVideos.shouldCapture(kind: .video, byteSize: 10))
        XCTAssertFalse(onlyVideos.shouldCapture(kind: .file, byteSize: 10))
        let noVideos = CaptureFilter.from(saveText: true, saveImages: true, saveFiles: true, saveVideos: false, maxBytes: 0)
        XCTAssertFalse(noVideos.shouldCapture(kind: .video, byteSize: 10))
        XCTAssertTrue(noVideos.shouldCapture(kind: .file, byteSize: 10))
    }
}
