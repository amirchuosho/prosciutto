import Foundation

public protocol ClipStore: Sendable {
    func upsert(_ item: ClipItem) async throws
    func update(_ item: ClipItem) async throws
    func all() async throws -> [ClipItem]
    func delete(id: UUID) async throws
    func setPinned(id: UUID, _ pinned: Bool) async throws
    func prune(keeping policy: RetentionPolicy, now: Date) async throws

    // Sections ("tabs")
    func sections() async throws -> [ClipSection]
    func createSection(name: String, colorHex: String) async throws -> ClipSection
    func deleteSection(id: UUID) async throws
    func assign(itemID: UUID, to sectionID: UUID?) async throws
}
