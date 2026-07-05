import XCTest
import AppKit
import ProsciuttoKit
@testable import Prosciutto

final class ImageMaterializerTests: XCTestCase {
    private func onePixelPNG() -> Data {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1)); img.unlockFocus()
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func clip(kind: ClipKind, textPlain: String? = nil, imageData: Data? = nil) -> ClipItem {
        ClipItem(id: UUID(), createdAt: Date(), lastUsedAt: Date(), useCount: 0, kind: kind,
                 textPlain: textPlain, imageData: imageData, contentHash: "h")
    }

    func testImageDataBackedClipYieldsPNG() {
        let png = ImageMaterializer.pngData(for: clip(kind: .image, imageData: onePixelPNG()))
        XCTAssertNotNil(png)
        XCTAssertNotNil(NSImage(data: png!))
    }

    func testFileBackedImageClipReadsTheFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mat-\(UUID()).png")
        try onePixelPNG().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNotNil(ImageMaterializer.pngData(for: clip(kind: .image, textPlain: url.path)))
    }

    func testTextClipYieldsNil() {
        XCTAssertNil(ImageMaterializer.pngData(for: clip(kind: .text, textPlain: "hello")))
    }
}
