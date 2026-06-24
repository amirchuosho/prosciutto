public protocol PasteboardReader {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot?
}
