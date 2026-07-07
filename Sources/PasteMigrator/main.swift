import Foundation
import ProsciuttoKit

// Dev/testing CLI around the shared PasteImporter (ProsciuttoKit). The in-app
// "Import from Paste…" is the shipping path; this drives the same code from the terminal.
//   swift run PasteMigrator --dry-run       # import into a throwaway store, print counts
//   swift run PasteMigrator                 # import into Prosciutto's real store
//   --app <path>        Prosciutto.app (default /Applications/Prosciutto.app)
//   --paste-dir <dir>   Paste store dir (default the standard location)

let args = CommandLine.arguments
let dryRun = args.contains("--dry-run")
func opt(_ n: String) -> String? {
    guard let i = args.firstIndex(of: n), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func fail(_ m: String) -> Never { FileHandle.standardError.write(Data("✗ \(m)\n".utf8)); exit(1) }

let appPath = opt("--app") ?? "/Applications/Prosciutto.app"
let pasteDB = opt("--paste-db").map { URL(fileURLWithPath: $0) }
let prosciuttoSupport = URL(fileURLWithPath:
    ("~/Library/Application Support/Prosciutto" as NSString).expandingTildeInPath)

do {
    guard let reader = try PasteImporter.makeReader(dbURL: pasteDB) else {
        fail("No Paste store found — is Paste installed? (scanned for any Paste DB by schema)")
    }
    let store: ClipStore
    let filesDir: URL
    if dryRun {
        store = InMemoryClipStore()
        filesDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pastemig-dry-\(UUID().uuidString)")
    } else {
        let storePath = prosciuttoSupport.appendingPathComponent("Model.sqlite").path
        store = try ProsciuttoWriter(appPath: appPath, storePath: storePath)
        filesDir = prosciuttoSupport.appendingPathComponent("imported-files")
    }

    print("▶ Paste → Prosciutto migration  (\(dryRun ? "DRY RUN" : "LIVE"))")
    let s = try await PasteImporter.run(reader: reader, into: store, filesDir: filesDir)
    print("""
        ✓ \(dryRun ? "would import" : "imported") \(s.imported) items\
        \(s.alreadyPresent > 0 ? ", \(s.alreadyPresent) already present" : "")\
        \(s.empties > 0 ? ", \(s.empties) empty skipped" : "")\
        \(s.missingFiles > 0 ? ", \(s.missingFiles) files whose originals are gone" : "").
          \(s.sectionsCreated) section(s) created.\(dryRun ? "  (throwaway store — nothing changed)" : "  Launch Prosciutto to see them.")
        """)
    if let log = s.logPath { print("  skip-breakdown log: \(log)") }
} catch {
    fail("\(error)")
}
