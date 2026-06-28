import Foundation

public struct ClipItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var kind: ClipKind
    public var textPlain: String?
    public var rtfData: Data?
    public var htmlString: String?
    public var imageData: Data?
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var contentHash: String
    public var isPinned: Bool
    public var expiresAt: Date?
    public var sectionID: UUID?
    /// Optional user-given name, shown on the card and matched by search.
    public var title: String?
    /// Manual order among pinned items (lower = earlier). Ignored when unpinned.
    public var pinOrder: Int

    public init(id: UUID, createdAt: Date, lastUsedAt: Date, useCount: Int, kind: ClipKind,
                textPlain: String? = nil, rtfData: Data? = nil, htmlString: String? = nil,
                imageData: Data? = nil, sourceAppBundleID: String? = nil, sourceAppName: String? = nil,
                contentHash: String, isPinned: Bool = false, expiresAt: Date? = nil,
                sectionID: UUID? = nil, title: String? = nil, pinOrder: Int = 0) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.kind = kind
        self.textPlain = textPlain
        self.rtfData = rtfData
        self.htmlString = htmlString
        self.imageData = imageData
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.expiresAt = expiresAt
        self.sectionID = sectionID
        self.title = title
        self.pinOrder = pinOrder
    }

    public static func make(from snapshot: PasteboardSnapshot, kind: ClipKind,
                            now: Date, ttl: TimeInterval) -> ClipItem {
        let filePath = snapshot.fileURLs.first?.path
        // An image FILE copied from Finder also puts the file's ICON on the
        // pasteboard as .png/.tiff. That icon is unreliable (often the generic
        // grey doc icon), so for file-backed image clips we drop the inline data
        // and render the real file from its path instead.
        let isImageFile = kind == .image && filePath != nil
        let imageData: Data? = isImageFile ? nil : snapshot.imageData
        // Hash file-backed clips by their path, not the flaky pasteboard icon,
        // so dedupe is stable.
        let primary: Data = filePath.map { Data($0.utf8) }
            ?? snapshot.imageData
            ?? snapshot.plainText.map { Data($0.utf8) }
            ?? snapshot.rtfData ?? Data()
        // Persist the file path as textPlain for file clips and for image files
        // (no inline imageData) so the card can show the name / load a preview.
        let text: String?
        switch kind {
        case .file:  text = filePath ?? snapshot.plainText
        case .image: text = isImageFile ? filePath : snapshot.plainText
        default:     text = snapshot.plainText
        }
        return ClipItem(
            id: UUID(), createdAt: now, lastUsedAt: now, useCount: 1, kind: kind,
            textPlain: text, rtfData: snapshot.rtfData, htmlString: snapshot.htmlString,
            imageData: imageData,
            sourceAppBundleID: snapshot.sourceAppBundleID, sourceAppName: snapshot.sourceAppName,
            contentHash: ContentHasher.hash(kind: kind, primary: primary),
            isPinned: false, expiresAt: now.addingTimeInterval(ttl))
    }
}
