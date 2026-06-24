import AppKit
import ProsciuttoKit

final class SystemPasteboardReader: PasteboardReader {
    private let pb = NSPasteboard.general
    var changeCount: Int { pb.changeCount }

    func snapshot() -> PasteboardSnapshot? {
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
