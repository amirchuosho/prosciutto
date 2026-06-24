import Foundation

public struct RetentionPolicy: Sendable {
    public var maxItems: Int
    public var maxAge: TimeInterval
    public init(maxItems: Int = 1000, maxAge: TimeInterval = 604_800) {
        self.maxItems = maxItems
        self.maxAge = maxAge
    }

    public func survivors(of items: [ClipItem], now: Date) -> [ClipItem] {
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
            .filter { now.timeIntervalSince($0.lastUsedAt) <= maxAge }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        if unpinned.count > maxItems { unpinned = Array(unpinned.prefix(maxItems)) }
        return pinned + unpinned
    }
}
