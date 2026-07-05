import AppKit
import Foundation
import ProsciuttoKit

/// Turns a single-image clip into PNG bytes: its inline image data (normalized to
/// PNG) or the contents of its backing image file. nil for anything that is not a
/// single image.
enum ImageMaterializer {
    static func pngData(for item: ClipItem) -> Data? {
        guard item.kind == .image else { return nil }
        if let data = item.imageData {
            if let rep = NSBitmapImageRep(data: data),
               let png = rep.representation(using: .png, properties: [:]) { return png }
            return data
        }
        if let path = item.textPlain {   // file-backed image: textPlain holds the path
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return nil
    }
}

/// Opens an image clip in Preview and, when the user saves, writes the edited image
/// back to the pasteboard (the poller then stores it as a fresh clip). The original
/// clip is never modified; we edit a throwaway temp copy.
final class ImageEditService {
    private let pasteboard: NSPasteboard
    private var source: DispatchSourceFileSystemObject?
    private var tempURL: URL?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func edit(_ item: ClipItem) {
        guard let png = ImageMaterializer.pngData(for: item) else { return }
        cleanup()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prosciutto-edit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return }
        tempURL = url

        // Prefer Preview; fall back to the default app for the file type.
        let cfg = NSWorkspace.OpenConfiguration()
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: cfg, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        watchForSave(url)
    }

    private func watchForSave(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        // Read the event mask via self.source (set below, before resume) rather than
        // capturing `src` here — capturing the source inside its own handler would
        // retain-cycle the DispatchSource.
        src.setEventHandler { [weak self] in
            guard let self, let ev = self.source?.data else { return }
            // Copy whatever is now at the path. This covers an in-place write AND
            // Preview's atomic save (write-to-temp then rename over the original) —
            // the earlier version treated the rename as "gone" and bailed before
            // copying, so edits never reached the clipboard.
            if let img = NSImage(contentsOf: url) {
                self.pasteboard.clearContents()
                self.pasteboard.writeObjects([img])
            }
            // An atomic save replaces the inode we opened, so this fd stops
            // delivering events — re-arm on the new file to catch later saves.
            if ev.contains(.rename) || ev.contains(.delete) {
                self.source?.cancel(); self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, self.tempURL == url,
                          FileManager.default.fileExists(atPath: url.path) else { return }
                    self.watchForSave(url)
                }
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func cleanup() {
        source?.cancel(); source = nil
        if let u = tempURL { try? FileManager.default.removeItem(at: u); tempURL = nil }
    }

    deinit { cleanup() }
}
