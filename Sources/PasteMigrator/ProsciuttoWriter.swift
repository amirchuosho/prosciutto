import Foundation
import CoreData
import ProsciuttoKit

/// A `ClipStore` for the dev CLI that writes into Prosciutto's real Core Data store WITHOUT
/// the app: loads the installed app's compiled model (`Model.momd`) at runtime and inserts
/// `CDClipItem`/`CDSection` via KVC. The in-app path uses the app's own `CoreDataClipStore`;
/// this only exists so `PasteImporter.run` can be driven from the terminal.
final class ProsciuttoWriter: ClipStore, @unchecked Sendable {
    private let ctx: NSManagedObjectContext

    init(appPath: String, storePath: String) throws {
        let momd = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/Model.momd")
        guard let model = NSManagedObjectModel(contentsOf: momd) else {
            throw PasteMigrationError.msg("cannot load Prosciutto Core Data model at \(momd.path)")
        }
        let container = NSPersistentContainer(name: "Model", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: URL(fileURLWithPath: storePath))
        desc.type = NSSQLiteStoreType
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var loadErr: Error?
        container.loadPersistentStores { _, e in loadErr = e }
        if let loadErr { throw PasteMigrationError.msg("open Prosciutto store: \(loadErr)") }
        ctx = container.newBackgroundContext()
    }

    func upsert(_ i: ClipItem) async throws {
        try await ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "CDClipItem")
            req.predicate = NSPredicate(format: "contentHash == %@", i.contentHash)
            req.fetchLimit = 1
            if try self.ctx.fetch(req).first != nil { return }
            let cd = NSEntityDescription.insertNewObject(forEntityName: "CDClipItem", into: self.ctx)
            cd.setValue(i.id, forKey: "id")
            cd.setValue(i.createdAt, forKey: "createdAt")
            cd.setValue(i.lastUsedAt, forKey: "lastUsedAt")
            cd.setValue(Int64(i.useCount), forKey: "useCount")
            cd.setValue(i.kind.rawValue, forKey: "kind")
            cd.setValue(i.textPlain, forKey: "textPlain")
            cd.setValue(i.rtfData, forKey: "rtfData")
            cd.setValue(i.htmlString, forKey: "htmlString")
            cd.setValue(i.imageData, forKey: "imageData")
            cd.setValue(i.sourceAppBundleID, forKey: "sourceAppBundleID")
            cd.setValue(i.sourceAppName, forKey: "sourceAppName")
            cd.setValue(i.contentHash, forKey: "contentHash")
            cd.setValue(i.isPinned, forKey: "isPinned")
            cd.setValue(i.expiresAt, forKey: "expiresAt")
            cd.setValue(i.sectionID, forKey: "sectionID")
            cd.setValue(i.title, forKey: "title")
            cd.setValue(Int64(i.pinOrder), forKey: "pinOrder")
            try self.ctx.save()
        }
    }

    func all() async throws -> [ClipItem] {
        try await ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "CDClipItem")
            return try self.ctx.fetch(req).map {
                ClipItem(id: ($0.value(forKey: "id") as? UUID) ?? UUID(),
                         createdAt: Date(), lastUsedAt: Date(), useCount: 1,
                         kind: ClipKind(rawValue: ($0.value(forKey: "kind") as? String) ?? "text") ?? .text,
                         contentHash: ($0.value(forKey: "contentHash") as? String) ?? "")
            }
        }
    }

    func sections() async throws -> [ClipSection] {
        try await ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "CDSection")
            return try self.ctx.fetch(req).map {
                ClipSection(id: ($0.value(forKey: "id") as? UUID) ?? UUID(),
                            name: ($0.value(forKey: "name") as? String) ?? "",
                            colorHex: ($0.value(forKey: "colorHex") as? String) ?? "#888888",
                            sortIndex: Int(($0.value(forKey: "sortIndex") as? Int64) ?? 0))
            }
        }
    }

    func createSection(name: String, colorHex: String) async throws -> ClipSection {
        try await ctx.perform {
            let count = try self.ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: "CDSection"))
            let s = NSEntityDescription.insertNewObject(forEntityName: "CDSection", into: self.ctx)
            let section = ClipSection(name: name, colorHex: colorHex, sortIndex: count)
            s.setValue(section.id, forKey: "id")
            s.setValue(section.name, forKey: "name")
            s.setValue(section.colorHex, forKey: "colorHex")
            s.setValue(Int64(section.sortIndex), forKey: "sortIndex")
            try self.ctx.save()
            return section
        }
    }

    // Unused by the importer.
    func update(_ item: ClipItem) async throws {}
    func delete(id: UUID) async throws {}
    func setPinned(id: UUID, _ pinned: Bool) async throws {}
    func prune(keeping policy: RetentionPolicy, now: Date) async throws {}
    func updateSection(_ section: ClipSection) async throws {}
    func deleteSection(id: UUID) async throws {}
    func assign(itemID: UUID, to sectionID: UUID?) async throws {}
}
