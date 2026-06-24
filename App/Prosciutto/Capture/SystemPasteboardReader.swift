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
        Thread.isMainThread ? read() : DispatchQueue.main.sync { read() }
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
}
