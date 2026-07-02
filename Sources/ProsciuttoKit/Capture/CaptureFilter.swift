import Foundation

/// Decides whether a captured clip should be stored, based on the save-by-type
/// toggles and an optional max stored-byte size. `maxBytes == 0` means no limit.
public struct CaptureFilter: Sendable {
    public var enabledKinds: Set<ClipKind>
    public var maxBytes: Int

    public init(enabledKinds: Set<ClipKind> = CaptureFilter.allKinds, maxBytes: Int = 0) {
        self.enabledKinds = enabledKinds
        self.maxBytes = maxBytes
    }

    public func shouldCapture(kind: ClipKind, byteSize: Int) -> Bool {
        guard enabledKinds.contains(kind) else { return false }
        if maxBytes > 0, byteSize > maxBytes { return false }
        return true
    }

    public static let allKinds: Set<ClipKind> = [.text, .rtf, .link, .color, .code, .image, .file, .location]

    public static let unrestricted = CaptureFilter()

    /// Build the enabled-kinds set from the three save-by-type toggles.
    public static func from(saveText: Bool, saveImages: Bool, saveFiles: Bool, maxBytes: Int) -> CaptureFilter {
        var kinds = Set<ClipKind>()
        if saveText { kinds.formUnion([.text, .rtf, .link, .color, .code, .location]) }
        if saveImages { kinds.insert(.image) }
        if saveFiles { kinds.insert(.file) }
        return CaptureFilter(enabledKinds: kinds, maxBytes: maxBytes)
    }
}
