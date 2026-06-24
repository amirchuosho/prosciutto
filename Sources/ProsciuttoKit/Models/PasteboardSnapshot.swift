import Foundation

public struct PasteboardSnapshot: Sendable {
    public var plainText: String?
    public var rtfData: Data?
    public var htmlString: String?
    public var imageData: Data?
    public var fileURLs: [URL]
    public var markerTypes: Set<String>
    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(plainText: String? = nil, rtfData: Data? = nil, htmlString: String? = nil,
                imageData: Data? = nil, fileURLs: [URL] = [], markerTypes: Set<String> = [],
                sourceAppBundleID: String? = nil, sourceAppName: String? = nil) {
        self.plainText = plainText
        self.rtfData = rtfData
        self.htmlString = htmlString
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.markerTypes = markerTypes
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }
}
