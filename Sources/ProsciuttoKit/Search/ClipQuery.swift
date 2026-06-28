import Foundation

public struct ClipQuery: Sendable {
    public var text: String = ""
    public var kinds: Set<ClipKind> = []
    public var sourceAppBundleID: String? = nil
    public var fuzzy: Bool = false
    public init() {}

    public func apply(to items: [ClipItem]) -> [ClipItem] {
        let prefiltered = items.filter { item in
            if !kinds.isEmpty && !kinds.contains(item.kind) { return false }
            if let app = sourceAppBundleID, item.sourceAppBundleID != app { return false }
            return true
        }
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return prefiltered }

        if fuzzy {
            let scored = prefiltered.compactMap { item -> (ClipItem, Int)? in
                let hay = [item.title, item.textPlain].compactMap { $0 }.joined(separator: "\n")
                guard let s = FuzzyMatch.score(needle, hay) else { return nil }
                return (item, s)
            }
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        } else {
            let lowered = needle.lowercased()
            return prefiltered.filter { item in
                let hay = [item.title, item.textPlain].compactMap { $0?.lowercased() }.joined(separator: "\n")
                return hay.contains(lowered)
            }
        }
    }
}
