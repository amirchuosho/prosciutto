import XCTest
import AppKit
import ProsciuttoKit
@testable import Prosciutto

final class PasteServiceImageTests: XCTestCase {
    private func pngBytes() throws -> Data {
        let img = NSImage(size: NSSize(width: 2, height: 2))
        img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2)); img.unlockFocus()
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
    private func imageClip(path: String?, bytes: Data?) -> ClipItem {
        ClipItem(id: UUID(), createdAt: Date(), lastUsedAt: Date(), useCount: 0, kind: .image,
                 textPlain: path, imageData: bytes, contentHash: "h")
    }
    private func makePB() -> NSPasteboard { NSPasteboard(name: .init("durable-test-\(UUID().uuidString)")) }

    func testPastesImageWhenFileMissingButBytesPresent() throws {
        let pb = makePB()
        PasteService(pasteboard: pb).write(imageClip(path: "/no/such.png", bytes: try pngBytes()), asPlainText: false)
        XCTAssertNotNil(NSImage(pasteboard: pb), "stored bytes still paste as an image with the file gone")
        XCTAssertNil(pb.readObjects(forClasses: [NSURL.self], options: nil)?.first, "no dead file URL written")
    }

    func testWritesFileURLWhenFileExists() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("pic.png"); try pngBytes().write(to: file)
        let pb = makePB()
        PasteService(pasteboard: pb).write(imageClip(path: file.path, bytes: try pngBytes()), asPlainText: false)
        let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.first?.path, file.path, "existing file is written so paste can drop the real file")
        XCTAssertNotNil(NSImage(pasteboard: pb))
    }
}
