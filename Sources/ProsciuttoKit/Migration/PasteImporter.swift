import Foundation
import CryptoKit

/// Result of a migration run.
public struct PasteImportSummary: Sendable, Equatable {
    public var imported = 0          // newly written
    public var alreadyPresent = 0    // deduped (identical content already in the store)
    public var empties = 0           // Paste items with no usable content
    public var missingFiles = 0      // file items whose on-disk original is gone
    public var sectionsCreated = 0
}

/// Migrates a Paste store into any `ClipStore`. Pure orchestration — no Core Data, no UI —
/// so it runs identically from the app (against `CoreDataClipStore`) and from tests
/// (against `InMemoryClipStore`). File-backed media is copied into `filesDir` so it renders
/// and is self-contained.
public enum PasteImporter {

    /// Locate + open Paste's store (auto-detecting the distribution), or nil if Paste isn't
    /// installed. Pass `storeDir` to override detection.
    public static func makeReader(dbURL explicit: URL? = nil) throws -> PasteReader? {
        guard let db = explicit ?? PasteReader.locatePasteDB() else { return nil }
        guard FileManager.default.fileExists(atPath: db.path) else { return nil }
        let name = db.lastPathComponent
        // Copy the DB (+ wal/shm) to temp so a running Paste isn't disturbed.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pastemig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for s in ["", "-wal", "-shm"] {
            let src = db.path + s
            if FileManager.default.fileExists(atPath: src) {
                try? FileManager.default.copyItem(atPath: src, toPath: tmp.appendingPathComponent(name + s).path)
            }
        }
        return try PasteReader(dbPath: tmp.appendingPathComponent(name).path,
                               externalDir: PasteReader.externalDataDir(for: db))
    }

    /// Read everything from `reader` and write it into `store`. Idempotent (deterministic ids
    /// + content-hash dedup), so re-running is safe.
    public static func run(reader: PasteReader, into store: ClipStore, filesDir: URL) async throws -> PasteImportSummary {
        try reader.verifySchema()
        let lists = try reader.lists()
        let items = try reader.items()
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        // Existing content hashes → accurate imported/already-present counts.
        var seen = Set(try await store.all().map(\.contentHash))

        // Ensure a Section per pinboard (idempotent), incl. empty ones.
        var sectionID: [String: UUID] = [:]
        for s in try await store.sections() { sectionID[s.name.lowercased()] = s.id }
        var summary = PasteImportSummary()
        for list in lists where list.isPinboard {
            if sectionID[list.name.lowercased()] == nil {
                let s = try await store.createSection(name: list.name, colorHex: importColor(for: list.name))
                sectionID[list.name.lowercased()] = s.id
                summary.sectionsCreated += 1
            }
        }

        let clipboardPk = lists.first { !$0.isPinboard }?.pk
        let grouped = Dictionary(grouping: items, by: { $0.listPk ?? clipboardPk })

        for list in lists {
            let sID: UUID? = list.isPinboard ? sectionID[list.name.lowercased()] : nil
            let its = (grouped[list.pk] ?? []).sorted {
                list.isPinboard ? $0.order < $1.order
                                : ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            for it in its {
                var snap = pasteboardSnapshot(for: it)
                let id = deterministicUUID(from: it.identifier ?? "pk-\(it.pk)")

                if let src = snap.fileURLs.first {
                    if let dst = adoptFile(src, id: id, into: filesDir) { snap.fileURLs = [dst] }
                    else if !FileManager.default.fileExists(atPath: src.path) { summary.missingFiles += 1 }
                }
                guard let kind = KindDetector.detect(snap) else { summary.empties += 1; continue }
                let created = it.createdAt ?? Date()
                let m = ClipItem.make(from: snap, kind: kind, now: created, ttl: 0)
                let item = ClipItem(
                    id: id, createdAt: created, lastUsedAt: created, useCount: 1, kind: m.kind,
                    textPlain: m.textPlain, rtfData: m.rtfData, htmlString: m.htmlString, imageData: m.imageData,
                    sourceAppBundleID: m.sourceAppBundleID, sourceAppName: m.sourceAppName,
                    contentHash: m.contentHash, isPinned: false, expiresAt: nil,
                    sectionID: sID, title: it.title ?? m.title, pinOrder: it.order)

                if seen.contains(item.contentHash) { summary.alreadyPresent += 1 }
                else { seen.insert(item.contentHash); summary.imported += 1 }
                try await store.upsert(item)
            }
        }
        return summary
    }

    // MARK: helpers

    /// Copy a file-backed item's original into `filesDir` so it renders + is self-contained.
    /// Returns the new URL, or nil if the original is gone.
    static func adoptFile(_ src: URL, id: UUID, into filesDir: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let ext = src.pathExtension
        let dst = filesDir.appendingPathComponent(id.uuidString + (ext.isEmpty ? "" : ".\(ext)"))
        if !FileManager.default.fileExists(atPath: dst.path) {
            try? FileManager.default.copyItem(at: src, to: dst)
        }
        return FileManager.default.fileExists(atPath: dst.path) ? dst : nil
    }

    /// Deterministic UUID from a stable string → idempotent ids across re-runs.
    static func deterministicUUID(from s: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(s.utf8)))
        b[6] = (b[6] & 0x0F) | 0x40   // version 4
        b[8] = (b[8] & 0x3F) | 0x80   // variant
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }

    /// Deterministic-ish colour per pinboard name so migrated sections aren't all grey.
    static func importColor(for name: String) -> String {
        let palette = ["#8A7BFF", "#52CC85", "#FF9E5C", "#6FD3C7", "#C77DFF", "#FF6FB0", "#5C8FFF"]
        let idx = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return palette[idx]
    }
}
