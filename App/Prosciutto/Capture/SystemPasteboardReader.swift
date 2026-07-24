import AppKit
import ProsciuttoKit

final class SystemPasteboardReader: PasteboardReader {
    private let pb = NSPasteboard.general

    // NSPasteboard / NSWorkspace are main-thread only. The monitor polls from a
    // background Task, so bounce every access onto the main thread.
    var changeCount: Int {
        Thread.isMainThread ? pb.changeCount : DispatchQueue.main.sync { pb.changeCount }
    }

    func snapshot() -> PasteboardSnapshot? {
        // Pasteboard access must be on main; the monitor calls this from a background Task.
        guard var snap = (Thread.isMainThread ? read() : DispatchQueue.main.sync { read() })
        else { return nil }

        // Replace a single image file's unreliable pasteboard icon with the file's real
        // bytes (or nil when unreadable / over the cap → path-only render), so the clip
        // survives the file moving. Read HERE, after the main-thread hop, so a big image
        // copy doesn't block the UI on the background poll.
        if let url = KindDetector.singleImageFileURL(in: snap) {
            snap.imageData = Self.imageFileBytes(url: url, maxBytes: Preferences.shared.maxItemSizeBytes)
        }
        return snap
    }

    private func read() -> PasteboardSnapshot? {
        let types = Set(pb.types?.map(\.rawValue) ?? [])
        let app = NSWorkspace.shared.frontmostApplication
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.filter { $0.isFileURL } ?? []
        let snap = PasteboardSnapshot(
            plainText: pb.string(forType: .string),
            rtfData: pb.data(forType: .rtf),
            htmlString: pb.string(forType: .html),
            imageData: pb.data(forType: .png) ?? pb.data(forType: .tiff),
            fileURLs: fileURLs,
            markerTypes: types,
            sourceAppBundleID: app?.bundleIdentifier,
            sourceAppName: app?.localizedName)

        if snap.plainText == nil && snap.imageData == nil && snap.fileURLs.isEmpty
            && snap.rtfData == nil { return nil }
        return snap
    }

    /// The image file's bytes, or nil if it can't be read or exceeds `maxBytes`
    /// (when `maxBytes > 0`). Pure so it is unit-testable without a pasteboard.
    static func imageFileBytes(url: URL, maxBytes: Int) -> Data? {
        if maxBytes > 0,
           let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > maxBytes {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
