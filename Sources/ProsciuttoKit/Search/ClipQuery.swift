import Foundation

public struct ClipQuery: Sendable {
    public var text: String = ""
    public var kinds: Set<ClipKind> = []
    public var sourceAppBundleID: String? = nil
    public init() {}

    public func apply(to items: [ClipItem]) -> [ClipItem] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if !kinds.isEmpty && !kinds.contains(item.kind) { return false }
            if let app = sourceAppBundleID, item.sourceAppBundleID != app { return false }
            if !needle.isEmpty {
                let hay = [item.title, item.textPlain]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: "\n")
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }
}
