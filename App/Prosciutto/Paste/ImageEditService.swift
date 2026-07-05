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

/// Opens an image clip in Preview and, when the user saves, puts the edited image on
/// the pasteboard (the poller then stores it as a fresh clip).
///
/// We edit a throwaway copy in the TEMP dir — NOT the user's original, and NOT
/// `~/Library/...`. Sandboxed Preview refuses to save in place inside `~/Library`
/// ("The original document can't be changed, so a duplicate has been created" → a
/// Save-As dialog we never see), so the edit never came back. A temp-dir file it can
/// write in place. On save we copy the result into a DURABLE folder and put that
/// file (URL + image) on the pasteboard, so the new clip is file-backed and survives
/// a reboot (the temp copy may not). The durable copy is kept only if an edit was
/// actually saved; the temp copy is always cleaned up.
final class ImageEditService {
    private let pasteboard: NSPasteboard
    private var source: DispatchSourceFileSystemObject?
    private var tempURL: URL?          // the file Preview edits (temp, writable in place)
    private var durableURL: URL?       // the saved copy that backs the clip

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func edit(_ item: ClipItem) {
        guard let png = ImageMaterializer.pngData(for: item) else { return }
        cleanup()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosciutto-edit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return }
        tempURL = url
        durableURL = nil

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
        // Read the event mask via self.source (set below, before resume) — capturing
        // `src` inside its own handler would retain-cycle the DispatchSource.
        src.setEventHandler { [weak self] in
            guard let self, let ev = self.source?.data else { return }
            // The user saved. Copy the edited bytes into a durable file and put THAT
            // (URL + image) on the pasteboard, so the new clip is file-backed and
            // survives a reboot. Covers in-place writes AND Preview's atomic save
            // (write-temp-then-rename over the file at this path).
            if let data = try? Data(contentsOf: url), let img = NSImage(data: data),
               let durable = self.persistDurably(data) {
                self.durableURL = durable
                self.pasteboard.writeFileBackedImage(durable, image: img)
            }
            // An atomic save swaps the inode we opened, so this fd goes silent —
            // re-arm on the file to catch later saves.
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

    /// Write the edited bytes to `~/Library/Application Support/Prosciutto/edited` —
    /// a durable home the clip's file-backing points at (Preview never writes here;
    /// we do).
    private func persistDurably(_ data: Data) -> URL? {
        guard let dir = Self.durableDir() else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Reuse the same durable file across repeated saves of one edit session.
        let url = durableURL ?? dir.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func durableDir() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Prosciutto/edited", isDirectory: true)
    }

    /// Stop watching and delete the throwaway temp copy. The durable copy (if any) is
    /// left in place — it backs a stored clip.
    private func cleanup() {
        source?.cancel(); source = nil
        if let u = tempURL { try? FileManager.default.removeItem(at: u) }
        tempURL = nil
        durableURL = nil
    }

    deinit { cleanup() }
}
