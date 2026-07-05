import AppKit
import Foundation

/// Watches the folder macOS saves screenshots to and copies each new screenshot to
/// the pasteboard, so it is ready to paste and gets captured as an image clip. The
/// screenshot file on disk is left untouched.
///
/// We watch the folder directly (rather than an `NSMetadataQuery`) for two reasons:
/// Spotlight results are TCC-filtered — a background app can't even *see* Desktop
/// screenshots that way — and a metadata query never reads a file, so it never
/// triggers the macOS folder-access prompt. Listing/reading the folder directly does
/// both: it prompts once for access, then sees every screenshot.
final class ScreenshotWatcher {
    private let pasteboard: NSPasteboard
    private var startedAt = Date()
    private var processed = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var dirURL: URL?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Pure decision: a screenshot is handled once, and only if it appeared after
    /// the watcher started (never the pre-existing backlog).
    static func shouldProcess(path: String, created: Date, startedAt: Date, processed: Set<String>) -> Bool {
        created >= startedAt && !processed.contains(path)
    }

    /// Where macOS writes screenshots: `com.apple.screencapture location`, else the
    /// Desktop.
    static func screenshotDirectory() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !loc.isEmpty {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func start() {
        stop()
        startedAt = Date()
        processed.removeAll()
        let dir = Self.screenshotDirectory()
        dirURL = dir

        // Seed the processed-set with whatever is already there (backlog, never
        // copied). This directory read also triggers the one-time folder-access
        // (TCC) prompt if the app doesn't yet have permission.
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in existing { processed.insert(dir.appendingPathComponent(name).path) }
        }

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        dirURL = nil
    }

    /// A new entry appeared in the folder — copy any new screenshot.
    private func scan() {
        guard let dir = dirURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        else { return }
        for url in files {
            let path = url.path
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard Self.shouldProcess(path: path, created: created, startedAt: startedAt, processed: processed)
            else { continue }
            handleCandidate(path: path)
        }
    }

    /// Confirm the file is a screenshot and copy it. macOS sets the screenshot
    /// extended attribute when it writes the file, but the folder event can fire a
    /// hair before the xattr lands, so retry briefly. The path is claimed up front so
    /// repeated folder events don't handle it twice.
    private func handleCandidate(path: String, attempt: Int = 0) {
        if attempt == 0 { processed.insert(path) }   // claim it — re-scans will skip it
        if isScreenshot(path) {
            copyToPasteboard(path: path)
        } else if attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.handleCandidate(path: path, attempt: attempt + 1)
            }
        }
    }

    /// A screenshot carries this extended attribute, written at the same time as the
    /// file — unlike the Spotlight index, it is available immediately and does not
    /// depend on indexing. Presence of the attribute is the marker (locale- and
    /// location-independent).
    private func isScreenshot(_ path: String) -> Bool {
        getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// Put the screenshot on the pasteboard the way copying it in Finder would: the
    /// file URL AND the image pixels. Pasting then yields the actual file (Finder,
    /// Mail, Slack, chat) or the image (editors). Because it carries a file URL, the
    /// captured clip is a file-backed image (hashed by path), so pasting it again
    /// dedupes instead of piling up re-encoded copies.
    private func copyToPasteboard(path: String, attempt: Int = 0) {
        let url = URL(fileURLWithPath: path)
        if let img = NSImage(contentsOf: url) {
            pasteboard.writeFileBackedImage(url, image: img)
        } else if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.copyToPasteboard(path: path, attempt: attempt + 1)
            }
        }
    }

    deinit { stop() }
}
