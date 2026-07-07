import Foundation
import SQLite3

public enum PasteMigrationError: Error, CustomStringConvertible {
    case msg(String)
    public var description: String { switch self { case .msg(let m): return m } }
}

/// A Paste list (Clipboard history or a pinboard).
public struct PasteList: Sendable {
    public let pk: Int64
    public let name: String
    public let isPinboard: Bool          // ZRAWTYPE 2 = pinboard, 1 = Clipboard history
}

/// One Paste item with its decoded pasteboard payload.
public struct PasteItem: Sendable {
    public let pk: Int64
    public let listPk: Int64?
    public let order: Int
    public let rawType: Int
    public let title: String?
    public let identifier: String?
    public let createdAt: Date?
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let dataByType: [String: Data]   // UTI → bytes
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Reads Paste's local Core Data store. Everything is plaintext SQLite; large
/// pasteboard blobs are stored either inline (flag 0x01) or externally (flag 0x02
/// → a UUID file under `_EXTERNAL_DATA`). Both resolve to a bplist of
/// `{ types: [...], dataByType: { UTI: <bytes> } }`.
public final class PasteReader {
    private var db: OpaquePointer?
    private let externalDir: URL

    private static let cachedDB: URL? = findPasteDB()

    /// The Paste store's DB file on this Mac, auto-detected across ALL distributions
    /// (direct download, Mac App Store/sandboxed, Setapp). The file can be named anything and
    /// live anywhere, so we identify it by SCHEMA — any `*.sqlite` with Paste's `ZITEMENTITY`
    /// table — never by name or path. Result is cached (scan is a bit expensive).
    public static func locatePasteDB() -> URL? { cachedDB }

    private static func findPasteDB() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // (root, maxDepth) — where different Paste distributions keep their store.
        var roots: [(URL, Int)] = [
            (home.appendingPathComponent("Library/Application Support"), 6),  // direct, Setapp (nested)
            (home.appendingPathComponent("Library/Group Containers"), 5),
        ]
        // Mac App Store (sandboxed) builds live in a container. Only dip into containers
        // whose name identifies Paste — scanning every app's container could trip macOS
        // cross-app-data prompts, and Setapp/direct don't use containers anyway.
        let containers = home.appendingPathComponent("Library/Containers")
        for c in (try? fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil)) ?? [] {
            let n = c.lastPathComponent.lowercased()
            if n.contains("paste") || n.contains("wiheads") {
                roots.append((c.appendingPathComponent("Data/Library/Application Support"), 4))
            }
        }
        var best: (URL, Int)?
        for (root, depth) in roots {
            for db in sqliteFiles(under: root, maxDepth: depth) {
                guard let n = pasteItemCount(dbPath: db.path) else { continue }
                if best == nil || n > best!.1 { best = (db, n) }
            }
        }
        return best?.0
    }

    /// All `*.sqlite` files under `root`, bounded depth, silently skipping unreadable dirs.
    private static func sqliteFiles(under root: URL, maxDepth: Int) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        func walk(_ dir: URL, _ depth: Int) {
            guard depth <= maxDepth,
                  let entries = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { return }
            for e in entries {
                if (try? e.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    walk(e, depth + 1)
                } else if e.pathExtension.lowercased() == "sqlite" {
                    out.append(e)
                }
            }
        }
        walk(root, 0)
        return out
    }

    /// The Core Data external-binary dir that sits beside a store file
    /// (`<stem>.sqlite` → `.<stem>_SUPPORT/_EXTERNAL_DATA`).
    public static func externalDataDir(for db: URL) -> URL {
        db.deletingLastPathComponent()
            .appendingPathComponent(".\(db.deletingPathExtension().lastPathComponent)_SUPPORT/_EXTERNAL_DATA")
    }

    /// Open a candidate DB read-only and return its Paste item count, or nil if it isn't a
    /// Paste store (no `ZITEMENTITY`). Cheap validation used by `locateStoreDir`.
    static func pasteItemCount(dbPath: String) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZITEMENTITY", -1, &st, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : nil
    }

    public init(dbPath: String, externalDir: URL) throws {
        self.externalDir = externalDir
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let m = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw PasteMigrationError.msg("cannot open Paste DB: \(m)")
        }
    }
    deinit { sqlite3_close(db) }

    /// Fail early with a clear message if Paste's schema isn't what we reverse-engineered
    /// (e.g. a future Paste version renamed tables/columns), so we never write garbage.
    public func verifySchema() throws {
        let required: [String: [String]] = [
            "ZLISTENTITY": ["ZNAME", "ZRAWTYPE"],
            "ZITEMENTITY": ["ZLIST", "ZDISPLAYORDERINPINBOARD", "ZRAWTYPE",
                            "ZIDENTIFIER", "ZCREATEDAT", "ZSOURCEAPPLICATION"],
            "ZITEMDATAENTITY": ["ZITEM", "ZRAWPASTEBOARDITEMS"],
            "ZAPPLICATIONENTITY": ["ZBUNDLEIDENTIFIER", "ZNAME"],
        ]
        for (table, cols) in required {
            var present = Set<String>()
            try query("PRAGMA table_info(\(table))") { st in
                if let c = text(st, 1) { present.insert(c) }   // col 1 = column name
            }
            guard !present.isEmpty else {
                throw PasteMigrationError.msg("""
                    Paste's database is missing the '\(table)' table — this Paste version's \
                    layout isn't supported (its schema changed). Nothing was written.
                    """)
            }
            let missing = cols.filter { !present.contains($0) }
            guard missing.isEmpty else {
                throw PasteMigrationError.msg("""
                    Paste's '\(table)' table is missing column(s) \(missing.joined(separator: ", ")) \
                    — this Paste version's layout isn't supported (its schema changed). \
                    Nothing was written.
                    """)
            }
        }
    }

    public func lists() throws -> [PasteList] {
        var out: [PasteList] = []
        try query("SELECT Z_PK, ZNAME, ZRAWTYPE FROM ZLISTENTITY") { st in
            let pk = sqlite3_column_int64(st, 0)
            let name = text(st, 1) ?? "Untitled"
            let raw = sqlite3_column_int64(st, 2)
            out.append(PasteList(pk: pk, name: name, isPinboard: raw == 2))
        }
        return out
    }

    public func items() throws -> [PasteItem] {
        var out: [PasteItem] = []
        let sql = """
            SELECT i.Z_PK, i.ZLIST, i.ZDISPLAYORDERINPINBOARD, i.ZRAWTYPE, i.ZTITLE,
                   i.ZIDENTIFIER, i.ZCREATEDAT, d.ZRAWPASTEBOARDITEMS,
                   a.ZBUNDLEIDENTIFIER, a.ZNAME
            FROM ZITEMENTITY i
            LEFT JOIN ZITEMDATAENTITY d ON d.ZITEM = i.Z_PK
            LEFT JOIN ZAPPLICATIONENTITY a ON i.ZSOURCEAPPLICATION = a.Z_PK
            """
        try query(sql) { st in
            let pk = sqlite3_column_int64(st, 0)
            let listPk: Int64? = sqlite3_column_type(st, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(st, 1)
            let order = Int(sqlite3_column_int64(st, 2))
            let raw = Int(sqlite3_column_int64(st, 3))
            let title = text(st, 4)
            let ident = text(st, 5)
            let created: Date? = sqlite3_column_type(st, 6) == SQLITE_NULL
                ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 6))
            let blob = blobData(st, 7)
            let dbt = blob.map { decode($0) } ?? [:]
            out.append(PasteItem(pk: pk, listPk: listPk, order: order, rawType: raw,
                                 title: title, identifier: ident, createdAt: created,
                                 sourceBundleID: text(st, 8), sourceAppName: text(st, 9),
                                 dataByType: dbt))
        }
        return out
    }

    // MARK: blob → dataByType

    private func decode(_ blob: Data) -> [String: Data] {
        guard let flag = blob.first else { return [:] }
        let bpl: Data
        switch flag {
        case 1:
            bpl = blob.subdata(in: 1..<blob.count)
        case 2:
            let end = min(37, blob.count)
            let uuid = String(data: blob.subdata(in: 1..<end), encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            guard !uuid.isEmpty,
                  let ext = try? Data(contentsOf: externalDir.appendingPathComponent(uuid))
            else { return [:] }
            bpl = ext
        default:
            return [:]
        }
        guard let obj = try? PropertyListSerialization.propertyList(from: bpl, options: [], format: nil)
        else { return [:] }
        let dict: [String: Any]?
        if let arr = obj as? [[String: Any]] { dict = arr.first }
        else { dict = obj as? [String: Any] }
        guard let dbt = dict?["dataByType"] as? [String: Any] else { return [:] }
        var out: [String: Data] = [:]
        for (k, v) in dbt where v is Data { out[k] = (v as! Data) }
        return out
    }

    // MARK: sqlite helpers

    private func query(_ sql: String, _ each: (OpaquePointer) -> Void) throws {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            throw PasteMigrationError.msg("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { each(st!) }
    }

    private func text(_ st: OpaquePointer, _ col: Int32) -> String? {
        guard sqlite3_column_type(st, col) != SQLITE_NULL,
              let c = sqlite3_column_text(st, col) else { return nil }
        return String(cString: c)
    }

    private func blobData(_ st: OpaquePointer, _ col: Int32) -> Data? {
        guard sqlite3_column_type(st, col) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(st, col) else { return nil }
        let n = Int(sqlite3_column_bytes(st, col))
        return Data(bytes: bytes, count: n)
    }
}

/// Map a Paste item's `dataByType` onto Prosciutto's `PasteboardSnapshot`. The UTIs
/// line up 1:1, so Prosciutto's own `KindDetector` then classifies it.
public func pasteboardSnapshot(for item: PasteItem) -> PasteboardSnapshot {
    let d = item.dataByType
    func str(_ keys: [String]) -> String? {
        for k in keys {
            if let v = d[k] {
                if let s = String(data: v, encoding: .utf8), !s.isEmpty { return s }
                if let s = String(data: v, encoding: .utf16), !s.isEmpty { return s }
            }
        }
        return nil
    }
    let plain = str(["public.utf8-plain-text", "public.utf16-external-plain-text", "public.text"])
    let html  = str(["public.html"])
    let rtf   = d["public.rtf"]
    let image = d["public.png"] ?? d["public.tiff"] ?? d["public.jpeg"] ?? d["public.jpg"]

    var fileURLs: [URL] = []
    if let fu = d["public.file-url"] {
        if let s = String(data: fu, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
           let u = URL(string: s), u.isFileURL {
            fileURLs = [u]
        } else if let u = URL(dataRepresentation: fu, relativeTo: nil), u.isFileURL {
            fileURLs = [u]
        }
    }
    return PasteboardSnapshot(plainText: plain, rtfData: rtf, htmlString: html,
                              imageData: image, fileURLs: fileURLs,
                              sourceAppBundleID: item.sourceBundleID, sourceAppName: item.sourceAppName)
}
