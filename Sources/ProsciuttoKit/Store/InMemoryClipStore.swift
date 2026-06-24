import Foundation

public actor InMemoryClipStore: ClipStore {
    private var items: [UUID: ClipItem] = [:]
    private var sectionStore: [UUID: ClipSection] = [:]
    public init() {}

    public func upsert(_ item: ClipItem) async throws {
        if let existing = items.values.first(where: { $0.contentHash == item.contentHash }) {
            var updated = existing
            updated.lastUsedAt = item.createdAt
            updated.useCount += 1
            items[existing.id] = updated
        } else {
            items[item.id] = item
        }
    }

    public func update(_ item: ClipItem) async throws {
        guard items[item.id] != nil else { return }
        items[item.id] = item
    }

    public func all() async throws -> [ClipItem] {
        items.values.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    public func delete(id: UUID) async throws { items[id] = nil }

    public func setPinned(id: UUID, _ pinned: Bool) async throws {
        guard var it = items[id] else { return }
        it.isPinned = pinned
        if pinned { it.expiresAt = nil }
        items[id] = it
    }

    public func prune(keeping policy: RetentionPolicy, now: Date) async throws {
        let survivors = policy.survivors(of: Array(items.values), now: now)
        items = Dictionary(uniqueKeysWithValues: survivors.map { ($0.id, $0) })
    }

    public func sections() async throws -> [ClipSection] {
        sectionStore.values.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func createSection(name: String, colorHex: String) async throws -> ClipSection {
        let section = ClipSection(name: name, colorHex: colorHex, sortIndex: sectionStore.count)
        sectionStore[section.id] = section
        return section
    }

    public func deleteSection(id: UUID) async throws {
        sectionStore[id] = nil
        for (key, var item) in items where item.sectionID == id {
            item.sectionID = nil
            items[key] = item
        }
    }

    public func assign(itemID: UUID, to sectionID: UUID?) async throws {
        guard var item = items[itemID] else { return }
        item.sectionID = sectionID
        items[itemID] = item
    }
}
