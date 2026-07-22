import AppKit
import ProsciuttoKit

extension AppEnvironment {
    private static var importFilesDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Prosciutto/imported-files", isDirectory: true)
    }

    /// True if a Paste store is present (any distribution) — gates the menu.
    var pasteIsInstalled: Bool { PasteReader.locatePasteDB() != nil }

    /// Menu action: migrate a Paste install's clips + pinboards into Prosciutto. Safe to run
    /// repeatedly — the importer dedups by content hash.
    func importFromPaste() {
        Task { @MainActor in
            guard let reader = try? PasteImporter.makeReader() else {
                Self.alert(.warning, "Paste not found",
                           "Couldn't find a Paste install on this Mac to import from.")
                return
            }
            guard Self.confirm(
                "Import from Paste?",
                "This copies your Paste clipboard history and pinboards into Prosciutto. "
                + "It's safe to run more than once — duplicates are skipped."
            ) else { return }
            do {
                let s = try await PasteImporter.run(reader: reader, into: store, filesDir: Self.importFilesDir)
                let raised = try await Self.raiseRetentionCapIfNeeded(store: store)
                await vm.reload()
                Self.alert(.informational, "Import complete", Self.summaryText(s, retentionRaisedTo: raised))
            } catch {
                Self.alert(.critical, "Import failed", "\(error)")
            }
        }
    }

    /// The retention item-cap (`maxItems`) would sweep the oldest of a large imported
    /// history at the next 5-minute prune. Raise the cap — never lower it — so the whole
    /// import survives. Skips the "unlimited" sentinel (`maxItems == 0`). Returns the new
    /// cap if it was raised, else nil.
    private static func raiseRetentionCapIfNeeded(store: ClipStore) async throws -> Int? {
        let cap = Preferences.shared.maxItems
        guard cap > 0 else { return nil }                       // 0 = unlimited, nothing to raise
        let total = try await store.all().count
        guard total > cap else { return nil }
        Preferences.shared.maxItems = total
        return total
    }

    private static func summaryText(_ s: PasteImportSummary, retentionRaisedTo raised: Int?) -> String {
        var lines = ["Imported \(s.imported) item\(s.imported == 1 ? "" : "s")"
            + (s.sectionsCreated > 0 ? " into \(s.sectionsCreated) new pinboard\(s.sectionsCreated == 1 ? "" : "s")" : "")
            + "."]
        if s.alreadyPresent > 0 { lines.append("\(s.alreadyPresent) already present (skipped).") }
        if s.empties > 0 { lines.append("\(s.empties) item\(s.empties == 1 ? "" : "s") had no importable content.") }
        if s.missingFiles > 0 {
            lines.append("\(s.missingFiles) file\(s.missingFiles == 1 ? "" : "s") couldn't be copied (original moved or deleted).")
        }
        if let raised { lines.append("Kept all items — retention limit raised to \(raised) to fit your history.") }
        if let log = s.logPath { lines.append("\nDetails: \(log)") }
        return lines.joined(separator: "\n")
    }

    private static func confirm(_ title: String, _ msg: String) -> Bool {
        let a = NSAlert()
        a.messageText = title; a.informativeText = msg
        a.addButton(withTitle: "Import"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    private static func alert(_ style: NSAlert.Style, _ title: String, _ msg: String) {
        let a = NSAlert()
        a.alertStyle = style; a.messageText = title; a.informativeText = msg
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
