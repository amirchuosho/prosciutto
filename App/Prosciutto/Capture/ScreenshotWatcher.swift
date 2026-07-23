import AppKit
import Foundation
import ProsciuttoKit

/// Watches the folder macOS saves screen captures to and copies each new one to the
/// pasteboard, so it is ready to paste and gets captured as a clip. A screenshot is
/// copied as an image; a screen recording as a FILE (its URL, plus a first-frame
/// thumbnail for the tile). The file on disk is left untouched.
///
/// We watch the folder directly (rather than an `NSMetadataQuery`) for two reasons:
/// Spotlight results are TCC-filtered — a background app can't even *see* Desktop
/// screenshots that way — and a metadata query never reads a file, so it never
/// triggers the macOS folder-access prompt. Listing/reading the folder directly does
/// both: it prompts once for access, then sees every screenshot.
final class ScreenshotWatcher {
    private let pasteboard: NSPasteboard
    /// Per-type gates, set by `AppEnvironment` before `start()`. The watcher runs
    /// whenever EITHER is on; these decide which captures it actually copies.
    var copyScreenshots = false
    var copyRecordings = false
    private var startedAt = Date()
    private var processed = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var dirURL: URL?
    /// Bumped on every start/stop so a pending re-arm retry from a superseded run
    /// aborts instead of double-arming.
    private var armToken = 0

    /// The feature is on when either capture type is enabled.
    private var isEnabled: Bool { copyScreenshots || copyRecordings }
    /// Armed = a live folder watch is running. `source` exists only once `arm` succeeds.
    var isArmed: Bool { source != nil }

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
        stop()                       // bumps armToken, cancels any live source
        startedAt = Date()
        Self.rotateLogIfLarge()
        log("watch start — screenshots=\(copyScreenshots) recordings=\(copyRecordings) dir=\(Self.screenshotDirectory().path)")
        arm(attempt: 0, token: armToken)
    }

    /// Re-attempt arming if the feature is enabled but not yet watching. Called from
    /// natural "user is back" moments (app becomes active, gallery opens) so a folder
    /// grant made LATER — in the prompt after our retry window, or by hand in System
    /// Settings — takes effect without an app restart. No-op once armed.
    func retryArmIfNeeded() {
        guard isEnabled, !isArmed else { return }
        armToken += 1                              // cancel any pending retry chain
        log("re-arm attempt (returned to app)")
        arm(attempt: 0, token: armToken)
    }

    /// Arm the folder watch. Listing the directory is the TCC-gated step (it also
    /// fires the one-time folder-access prompt); if it throws we don't have access
    /// yet. Access is often granted a beat AFTER launch (the user answers the prompt),
    /// so retry through a short window; if access is granted even later, the app-active
    /// / gallery-open triggers (`retryArmIfNeeded`) re-arm it — so it never stays dead
    /// until an app restart.
    private func arm(attempt: Int, token: Int) {
        guard token == armToken else { return }   // superseded by a newer start/stop
        let dir = Self.screenshotDirectory()
        guard let existing = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            if attempt == 0 { log("arm: no folder access to \(dir.path) — retrying, or grant it in Settings › Permissions") }
            guard attempt < 15 else {              // ~30s of 2s retries; then wait for a re-arm trigger
                log("arm: still no access after retries — waiting until you return to the app")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.arm(attempt: attempt + 1, token: token)
            }
            return
        }

        // Seed the processed-set with whatever is already there (backlog, never copied).
        dirURL = dir
        processed.removeAll()
        for name in existing { processed.insert(dir.appendingPathComponent(name).path) }

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { log("arm: could not open \(dir.path) for watching"); return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
        log("arm: watching \(dir.path)")
    }

    func stop() {
        armToken += 1                // invalidate any pending re-arm retry
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
        let name = (path as NSString).lastPathComponent
        if isScreenshot(path) {
            if copyScreenshots { log("screenshot detected → copying: \(name)"); copyImageToPasteboard(path: path) }
            else { log("screenshot detected but auto-copy is off: \(name)") }
        } else if isScreenRecording(path) {
            if copyRecordings { log("recording detected → copying: \(name)"); copyVideoToPasteboard(path: path) }
            else { log("recording detected but auto-copy is off: \(name)") }
        } else if attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.handleCandidate(path: path, attempt: attempt + 1)
            }
        } else {
            log("ignored (not a screen capture): \(name)")
        }
    }

    /// A screenshot carries this extended attribute, written at the same time as the
    /// file — unlike the Spotlight index, it is available immediately and does not
    /// depend on indexing. Presence of the attribute is the marker (locale- and
    /// location-independent).
    private func isScreenshot(_ path: String) -> Bool {
        getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// A screen RECORDING is a video file macOS tagged with the screen-capture
    /// metadata. Screenshots get `kMDItemIsScreenCapture`; recordings get
    /// `kMDItemScreenCaptureType` instead (verified on real recordings). Requiring
    /// the xattr means a random `.mov` the user drops in the folder is NOT copied.
    private func isScreenRecording(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard KindDetector.videoExtensions.contains(ext) else { return false }
        return getxattr(path, "com.apple.metadata:kMDItemScreenCaptureType", nil, 0, 0, 0) >= 0
    }

    /// Put the screenshot on the pasteboard the way copying it in Finder would: the
    /// file URL AND the image pixels. Pasting then yields the actual file (Finder,
    /// Mail, Slack, chat) or the image (editors). Because it carries a file URL, the
    /// captured clip is a file-backed image (hashed by path), so pasting it again
    /// dedupes instead of piling up re-encoded copies.
    private func copyImageToPasteboard(path: String, attempt: Int = 0) {
        let url = URL(fileURLWithPath: path)
        if let img = NSImage(contentsOf: url) {
            pasteboard.writeFileBackedImage(url, image: img)
            log("copied screenshot to clipboard: \((path as NSString).lastPathComponent)")
        } else if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.copyImageToPasteboard(path: path, attempt: attempt + 1)
            }
        } else {
            log("could not read screenshot file (never became readable): \((path as NSString).lastPathComponent)")
        }
    }

    /// Put the recording on the pasteboard as a FILE (its URL, so pasting drops the
    /// `.mov`), plus a first-frame thumbnail so the gallery tile previews. Thumbnail
    /// generation touches AVFoundation/disk, so do it off the main thread and hop
    /// back to write the pasteboard. If the thumbnail fails we still copy the file.
    private func copyVideoToPasteboard(path: String) {
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let thumb = VideoThumbnail.firstFrame(of: url)
            DispatchQueue.main.async {
                self?.pasteboard.writeFileBackedVideo(url, thumbnail: thumb)
                self?.log("copied recording to clipboard: \((path as NSString).lastPathComponent)")
            }
        }
    }

    // MARK: - Folder access

    /// Whether the app can currently read the screenshot folder (the TCC-gated step the
    /// watcher depends on). Calling it on a protected folder that hasn't been granted
    /// yet triggers the macOS "allow access" prompt — which is exactly what the
    /// Permissions UI's "Grant Access…" button wants.
    static func hasFolderAccess() -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: screenshotDirectory().path)) != nil
    }

    // MARK: - Diagnostics log

    /// Append-only log so a user for whom auto-copy "doesn't work" can send exactly what
    /// the watcher saw. Lives next to the store; rotated when it grows past ~256 KB.
    static var logURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Prosciutto/screenshot-watch.log")
    }

    private func log(_ message: String) {
        guard let url = Self.logURL else { return }
        let data = Data("\(Self.timestamp())  \(message)\n".utf8)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Create the file on first write; otherwise append. Never write(to:) an existing
        // file — that truncates it, losing the log we're trying to keep.
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? data.write(to: url)
            return
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    }

    /// A plain-text diagnostics report for the "auto-copy doesn't work" support loop —
    /// copied to the clipboard from Settings › Permissions so a user can paste it back.
    /// Covers the whole failure surface: what's enabled, where captures land, whether we
    /// have folder access, OS/app version, and the tail of the watch log (which records
    /// every arm/deny/detect/copy).
    static func diagnosticsReport() -> String {
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var lines = [
            "Prosciutto — screen-capture auto-copy diagnostics",
            "app version: \(app)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "auto-copy screenshots: \(Preferences.shared.autoCopyScreenshots)",
            "auto-copy recordings: \(Preferences.shared.autoCopyRecordings)",
            "capture folder: \(screenshotDirectory().path)",
            "folder access: \(hasFolderAccess() ? "granted" : "NOT granted")",
            "",
            "--- recent watch log ---",
            recentLog(lines: 50) ?? "(no log yet — the watcher has not run)",
        ]
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The last `n` lines of the watch log, or nil if there is none.
    private static func recentLog(lines n: Int) -> String? {
        guard let url = logURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(n).joined(separator: "\n")
    }

    private static func rotateLogIfLarge() {
        guard let url = logURL,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > 256_000 else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }

    deinit { stop() }
}
