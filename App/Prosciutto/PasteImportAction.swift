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
                await vm.reload()
                Self.alert(.informational, "Import complete", Self.summaryText(s))
            } catch {
                Self.alert(.critical, "Import failed", "\(error)")
            }
        }
    }

    private static func summaryText(_ s: PasteImportSummary) -> String {
        var lines = ["Imported \(s.imported) item\(s.imported == 1 ? "" : "s")"
            + (s.sectionsCreated > 0 ? " into \(s.sectionsCreated) new pinboard\(s.sectionsCreated == 1 ? "" : "s")" : "")
            + "."]
        if s.alreadyPresent > 0 { lines.append("\(s.alreadyPresent) already present (skipped).") }
        if s.empties > 0 { lines.append("\(s.empties) item\(s.empties == 1 ? "" : "s") had no importable content.") }
        if s.missingFiles > 0 {
            lines.append("\(s.missingFiles) file\(s.missingFiles == 1 ? "" : "s") couldn't be copied (original moved or deleted).")
        }
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
