import Foundation
import AppKit

/// Updates Prosciutto in place via `brew upgrade`. brew-locate and script generation are
/// pure/testable; `install()` launches a detached script and quits the app (hand-verified).
struct BrewUpdateInstaller {
    let cask = "amirchuosho/prosciutto/prosciutto"
    private let bundleID: String
    private let brewPaths: [String]
    private let fileExists: (String) -> Bool

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "app.prosciutto.Prosciutto",
         brewPaths: [String] = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
         fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.bundleID = bundleID
        self.brewPaths = brewPaths
        self.fileExists = fileExists
    }

    func locateBrew() -> String? { brewPaths.first(where: fileExists) }

    /// The detached script: wait for THIS app process (pid) to exit, upgrade the fixed
    /// cask, reopen, and tee everything to the log. `brew`, `pid`, `cask` are all ours —
    /// no remote data is interpolated here.
    func makeScript(brew: String, pid: Int32, logPath: String) -> String {
        """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        {
          echo "=== Prosciutto update $(date) ==="
          '\(brew)' update
          '\(brew)' upgrade --cask \(cask)
          open -a Prosciutto
        } >'\(logPath)' 2>&1
        """
    }

    /// Locate brew, write the script, launch it detached via nohup, then quit so the
    /// upgrade can replace the running app. Falls back to a copyable command if no brew.
    func install() {
        guard let brew = locateBrew() else { showFallback(); return }
        let fm = FileManager.default
        let logDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Prosciutto", isDirectory: true)
        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logPath = logDir.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970)).log").path
        let script = makeScript(brew: brew, pid: ProcessInfo.processInfo.processIdentifier, logPath: logPath)
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("prosciutto-update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", "nohup /bin/bash '\(scriptURL.path)' >/dev/null 2>&1 &"]
            try p.run()
        } catch {
            showFallback(); return
        }
        NSApplication.shared.terminate(nil)
    }

    /// Shown when brew isn't found: the exact command the user can run by hand.
    func showFallback() {
        let a = NSAlert()
        a.messageText = "Homebrew not found"
        a.informativeText = "Update Prosciutto by running this in Terminal:\n\nbrew upgrade --cask \(cask)"
        a.addButton(withTitle: "Copy Command")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew upgrade --cask \(cask)", forType: .string)
        }
    }
}
