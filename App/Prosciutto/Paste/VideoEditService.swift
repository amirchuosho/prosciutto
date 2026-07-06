import AppKit
import Foundation
import os
import ProsciuttoKit

private let trimLog = Logger(subsystem: "app.prosciutto.Prosciutto", category: "VideoEditService")

/// Opens a recording clip in QuickTime Player to play or trim.
///
/// Unlike images (edited as a throwaway copy → new clip), a recording is edited IN
/// PLACE on the user's actual file. Two reasons: QuickTime's sandbox refuses to save
/// a trim into our temp dir (it forces a Save-As dialog), but saves in place fine over
/// a file it opened; and the Video clip is already file-backed to that path, so a trim
/// saved in place is reflected the next time the clip is pasted — no copy, watch, or
/// re-capture needed. (The tile's cached thumbnail may lag until the app restarts or
/// the cache evicts; the first frame usually doesn't change unless the start is cut.)
final class VideoEditService {
    /// Open the recording in QuickTime Player (play / manual edit).
    func edit(_ item: ClipItem) { openInQuickTime(item) }

    /// Open the recording and jump straight to QuickTime's Trim UI.
    func crop(_ item: ClipItem) {
        guard openInQuickTime(item) else { return }
        triggerTrim(attempt: 0)
    }

    @discardableResult
    private func openInQuickTime(_ item: ClipItem) -> Bool {
        // A video clip is file-backed: its path lives in textPlain.
        guard item.kind == .video, let path = item.textPlain,
              FileManager.default.fileExists(atPath: path) else { return false }
        let url = URL(fileURLWithPath: path)
        let cfg = NSWorkspace.OpenConfiguration()
        if let qt = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.QuickTimePlayerX") {
            NSWorkspace.shared.open([url], withApplicationAt: qt, configuration: cfg, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    /// Click Edit ▸ Trim… in QuickTime. Clicking the menu item is far more reliable
    /// than a ⌘T keystroke (no keyboard-focus race). Everything runs through System
    /// Events (one Automation target — System Events brings QuickTime front AND clicks
    /// its menu, so the app never needs a separate "control QuickTime" grant). The
    /// item is disabled until the movie finishes opening — and on first run the
    /// Automation consent dialog eats several seconds — so retry over a wide window
    /// until the click lands (a nil error).
    private func triggerTrim(attempt: Int) {
        guard attempt < 24 else {
            trimLog.error("trim gave up after \(attempt) attempts")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.8 : 0.5)) { [weak self] in
            guard let self else { return }
            let script = """
            tell application "System Events"
                tell process "QuickTime Player"
                    set frontmost to true
                    click menu item "Trim…" of menu "Edit" of menu bar 1
                end tell
            end tell
            """
            var err: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&err)
            if err == nil, result != nil {
                trimLog.log("trim opened on attempt \(attempt)")
                return   // success — stop retrying
            }
            // Non-nil error: item disabled (movie loading) or consent still pending —
            // log it and retry.
            trimLog.error("trim attempt \(attempt) error: \(String(describing: err))")
            self.triggerTrim(attempt: attempt + 1)
        }
    }
}
