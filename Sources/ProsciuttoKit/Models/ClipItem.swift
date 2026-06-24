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

    public init(id: UUID, createdAt: Date, lastUsedAt: Date, useCount: Int, kind: ClipKind,
                textPlain: String? = nil, rtfData: Data? = nil, htmlString: String? = nil,
                imageData: Data? = nil, sourceAppBundleID: String? = nil, sourceAppName: String? = nil,
                contentHash: String, isPinned: Bool = false, expiresAt: Date? = nil,
                sectionID: UUID? = nil) {
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
    }

    public static func make(from snapshot: PasteboardSnapshot, kind: ClipKind,
                            now: Date, ttl: TimeInterval) -> ClipItem {
        let primary: Data = snapshot.imageData
            ?? snapshot.fileURLs.first.map { Data($0.path.utf8) }
            ?? snapshot.plainText.map { Data($0.utf8) }
            ?? snapshot.rtfData ?? Data()
        return ClipItem(
            id: UUID(), createdAt: now, lastUsedAt: now, useCount: 1, kind: kind,
            textPlain: snapshot.plainText, rtfData: snapshot.rtfData, htmlString: snapshot.htmlString,
            imageData: snapshot.imageData,
            sourceAppBundleID: snapshot.sourceAppBundleID, sourceAppName: snapshot.sourceAppName,
            contentHash: ContentHasher.hash(kind: kind, primary: primary),
            isPinned: false, expiresAt: now.addingTimeInterval(ttl))
    }
}
