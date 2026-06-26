import CoreData
import ProsciuttoKit

final class CoreDataClipStore: ClipStore {
    private let stack: CoreDataStack

    init(inMemory: Bool = false) {
        stack = CoreDataStack(inMemory: inMemory)
    }

    func upsert(_ item: ClipItem) async throws {
        try await perform { ctx in
            let req = CDClipItem.fetchRequest()
            req.predicate = NSPredicate(format: "contentHash == %@", item.contentHash)
            req.fetchLimit = 1
            if let existing = try ctx.fetch(req).first {
                existing.lastUsedAt = item.createdAt
                existing.useCount += 1
            } else {
                let cd = CDClipItem(context: ctx)
                Self.write(item, into: cd)
            }
            try ctx.save()
        }
    }

    func update(_ item: ClipItem) async throws {
        try await perform { ctx in
            if let cd = try Self.fetchItem(item.id, in: ctx) {
                Self.write(item, into: cd)
            }
            try ctx.save()
        }
    }

    func all() async throws -> [ClipItem] {
        try await perform { ctx in
            let req = CDClipItem.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: false)]
            return try ctx.fetch(req).map(Self.read)
        }
    }

    func delete(id: UUID) async throws {
        try await perform { ctx in
            if let cd = try Self.fetchItem(id, in: ctx) { ctx.delete(cd) }
            try ctx.save()
        }
    }

    func setPinned(id: UUID, _ pinned: Bool) async throws {
        try await perform { ctx in
            if let cd = try Self.fetchItem(id, in: ctx) {
                cd.isPinned = pinned
                if pinned { cd.expiresAt = nil }
            }
            try ctx.save()
        }
    }

    func prune(keeping policy: RetentionPolicy, now: Date) async throws {
        try await perform { ctx in
            let all = try ctx.fetch(CDClipItem.fetchRequest())
            let survivors = Set(policy.survivors(of: all.map(Self.read), now: now).map(\.id))
            for cd in all where !survivors.contains(cd.id ?? UUID()) { ctx.delete(cd) }
            try ctx.save()
        }
    }

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let ctx = stack.container.newBackgroundContext()
        return try await ctx.perform { try block(ctx) }
    }

    /// Fetch a single clip item by id within the given context.
    private static func fetchItem(_ id: UUID, in ctx: NSManagedObjectContext) throws -> CDClipItem? {
        let req = CDClipItem.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private static func write(_ i: ClipItem, into cd: CDClipItem) {
        cd.id = i.id
        cd.createdAt = i.createdAt
        cd.lastUsedAt = i.lastUsedAt
        cd.useCount = Int64(i.useCount)
        cd.kind = i.kind.rawValue
        cd.textPlain = i.textPlain
        cd.rtfData = i.rtfData
        cd.htmlString = i.htmlString
        cd.imageData = i.imageData
        cd.sourceAppBundleID = i.sourceAppBundleID
        cd.sourceAppName = i.sourceAppName
        cd.contentHash = i.contentHash
        cd.isPinned = i.isPinned
        cd.expiresAt = i.expiresAt
        cd.sectionID = i.sectionID
        cd.title = i.title
    }

    private static func read(_ cd: CDClipItem) -> ClipItem {
        ClipItem(
            id: cd.id ?? UUID(),
            createdAt: cd.createdAt ?? Date(),
            lastUsedAt: cd.lastUsedAt ?? Date(),
            useCount: Int(cd.useCount),
            kind: ClipKind(rawValue: cd.kind ?? "text") ?? .text,
            textPlain: cd.textPlain,
            rtfData: cd.rtfData,
            htmlString: cd.htmlString,
            imageData: cd.imageData,
            sourceAppBundleID: cd.sourceAppBundleID,
            sourceAppName: cd.sourceAppName,
            contentHash: cd.contentHash ?? "",
            isPinned: cd.isPinned,
            expiresAt: cd.expiresAt,
            sectionID: cd.sectionID,
            title: cd.title)
    }

    // MARK: Sections

    func sections() async throws -> [ClipSection] {
        try await perform { ctx in
            let req = CDSection.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
            return try ctx.fetch(req).map {
                ClipSection(id: $0.id ?? UUID(), name: $0.name ?? "",
                            colorHex: $0.colorHex ?? "#888888", sortIndex: Int($0.sortIndex))
            }
        }
    }

    func createSection(name: String, colorHex: String) async throws -> ClipSection {
        try await perform { ctx in
            let count = try ctx.count(for: CDSection.fetchRequest())
            let cd = CDSection(context: ctx)
            let section = ClipSection(name: name, colorHex: colorHex, sortIndex: count)
            cd.id = section.id
            cd.name = section.name
            cd.colorHex = section.colorHex
            cd.sortIndex = Int64(section.sortIndex)
            try ctx.save()
            return section
        }
    }

    func updateSection(_ section: ClipSection) async throws {
        try await perform { ctx in
            let req = CDSection.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", section.id as CVarArg)
            req.fetchLimit = 1
            if let cd = try ctx.fetch(req).first {
                cd.name = section.name
                cd.colorHex = section.colorHex
                cd.sortIndex = Int64(section.sortIndex)
            }
            try ctx.save()
        }
    }

    func deleteSection(id: UUID) async throws {
        try await perform { ctx in
            let sreq = CDSection.fetchRequest()
            sreq.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for s in try ctx.fetch(sreq) { ctx.delete(s) }

            let ireq = CDClipItem.fetchRequest()
            ireq.predicate = NSPredicate(format: "sectionID == %@", id as CVarArg)
            for item in try ctx.fetch(ireq) { item.sectionID = nil }
            try ctx.save()
        }
    }

    func assign(itemID: UUID, to sectionID: UUID?) async throws {
        try await perform { ctx in
            if let cd = try Self.fetchItem(itemID, in: ctx) { cd.sectionID = sectionID }
            try ctx.save()
        }
    }
}
