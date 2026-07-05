# Image-workflow Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add (1) auto-copy of new screenshots to the clipboard behind a Settings toggle, and (2) an edit button on single-image clips that opens the image in Preview and round-trips the saved result to the clipboard.

**Architecture:** Two small, independent app-target services. `ScreenshotWatcher` uses a live `NSMetadataQuery` on `kMDItemIsScreenCapture` to detect screenshots and writes their image bytes to `NSPasteboard`. `ImageEditService` materializes an image clip to a temp PNG, opens it in Preview, watches for save, and writes the edited bytes back to `NSPasteboard`. Both rely on the existing `ClipboardMonitor` poller to turn pasteboard bytes into clips — no store/schema changes.

**Tech Stack:** Swift, AppKit, Foundation (Spotlight `NSMetadataQuery`), SwiftUI, XcodeGen, XCTest.

## Global Constraints

- Platform: macOS 14+. Language: Swift 5.10.
- `ProsciuttoKit` stays UI/AppKit-free. All AppKit code lives in the **app target** (`App/Prosciutto/…`); these new services and tests are app-target only (`@testable import Prosciutto`).
- **COMMIT FREEZE (session):** the repo is public and frozen. Do NOT `git add` / `git commit` / `git push` until the user explicitly lifts the freeze. Where a task says "Commit", HOLD it: instead build + verify, and leave the change staged-in-tree only. Resume real commits once authorized.
- Build/test loop (app-target tests need Xcode, not `swift test`):
  - Generate: `xcodegen generate`
  - Build: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build`
  - Test: `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS'` (add `-only-testing:ProsciuttoTests/<Class>` to scope)
  - Deploy for runtime checks: kill the app, `cp -R build/Build/Products/Debug/Prosciutto.app /Applications/`, relaunch, re-grant Accessibility if pasting.
- New Swift files must be added to `Project.yml` source globs implicitly (XcodeGen picks up files under `App/Prosciutto/` automatically — re-run `xcodegen generate` after creating files). Test files under `App/ProsciuttoTests/` are likewise auto-included.
- Follow existing patterns: `Preferences` (key in `Keys` enum + computed property with a default), `SettingsView` toggles, `ClipCard` `on…` closures wired in `GalleryView`.

---

## File Structure

**Feature 1 — auto-copy screenshots**
- Create `App/Prosciutto/Capture/ScreenshotWatcher.swift` — detect screenshots, copy image to pasteboard.
- Create `App/ProsciuttoTests/ScreenshotWatcherTests.swift` — pure `shouldProcess` decision test.
- Modify `App/Prosciutto/Settings/Preferences.swift` — `autoCopyScreenshots` pref (default false).
- Modify `App/Prosciutto/Settings/SettingsView.swift` — toggle in the Capture section.
- Modify `App/Prosciutto/AppEnvironment.swift` — own the watcher; start/stop on the pref.

**Feature 2 — edit image clip in Preview**
- Create `App/Prosciutto/Paste/ImageEditService.swift` — materialize + open Preview + watch + round-trip. Contains a pure `ImageMaterializer.pngData(for:)`.
- Create `App/ProsciuttoTests/ImageMaterializerTests.swift` — materialization test.
- Modify `App/Prosciutto/UI/Cards/ClipCard.swift` — `onEditImage` closure + button for `.image` clips.
- Modify `App/Prosciutto/UI/GalleryView.swift` — bind `onEditImage`.
- Modify `App/Prosciutto/UI/GalleryViewModel.swift` — `editImage(_:)` hook closure.
- Modify `App/Prosciutto/AppEnvironment.swift` — own `ImageEditService`; wire the VM hook.

---

## Task 1: ScreenshotWatcher (detection + copy)

**Files:**
- Create: `App/Prosciutto/Capture/ScreenshotWatcher.swift`
- Test: `App/ProsciuttoTests/ScreenshotWatcherTests.swift`

**Interfaces:**
- Produces: `final class ScreenshotWatcher { init(pasteboard: NSPasteboard = .general); func start(); func stop(); static func shouldProcess(path: String, created: Date, startedAt: Date, processed: Set<String>) -> Bool }`

- [ ] **Step 1: Write the failing test**

```swift
// App/ProsciuttoTests/ScreenshotWatcherTests.swift
import XCTest
@testable import Prosciutto

final class ScreenshotWatcherTests: XCTestCase {
    func testShouldProcessRespectsStartTimeAndProcessedSet() {
        let start = Date()
        let older = start.addingTimeInterval(-5)
        let newer = start.addingTimeInterval(5)
        // created before the watcher started → ignore (backlog)
        XCTAssertFalse(ScreenshotWatcher.shouldProcess(path: "/a.png", created: older, startedAt: start, processed: []))
        // created after start, not seen → process
        XCTAssertTrue(ScreenshotWatcher.shouldProcess(path: "/a.png", created: newer, startedAt: start, processed: []))
        // already processed → ignore
        XCTAssertFalse(ScreenshotWatcher.shouldProcess(path: "/a.png", created: newer, startedAt: start, processed: ["/a.png"]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS' -only-testing:ProsciuttoTests/ScreenshotWatcherTests`
Expected: FAIL — `ScreenshotWatcher` is undefined.

- [ ] **Step 3: Write the implementation**

```swift
// App/Prosciutto/Capture/ScreenshotWatcher.swift
import AppKit
import Foundation

/// Watches for new screenshots (via the Spotlight attribute every screenshot
/// carries) and copies each one to the pasteboard, so it is ready to paste and
/// gets captured as an image clip. The screenshot file on disk is left untouched.
final class ScreenshotWatcher {
    private let pasteboard: NSPasteboard
    private let query = NSMetadataQuery()
    private var startedAt = Date()
    private var processed = Set<String>()

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Pure decision: a screenshot is handled once, and only if it appeared after
    /// the watcher started (never the pre-existing backlog).
    static func shouldProcess(path: String, created: Date, startedAt: Date, processed: Set<String>) -> Bool {
        created >= startedAt && !processed.contains(path)
    }

    func start() {
        stop()
        startedAt = Date()
        processed.removeAll()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(handle(_:)),
            name: .NSMetadataQueryDidUpdate, object: query)
        // The initial gather is the backlog — mark it seen without copying.
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
    }

    func stop() {
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
    }

    @objc private func gathered(_ note: Notification) {
        query.disableUpdates()
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                processed.insert(path)   // backlog: seen, not copied
            }
        }
        query.enableUpdates()
    }

    @objc private func handle(_ note: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  Self.shouldProcess(path: path, created: created, startedAt: startedAt, processed: processed)
            else { continue }
            processed.insert(path)
            copyToPasteboard(path: path)
        }
    }

    /// Read the screenshot and put PNG bytes on the pasteboard. Spotlight can index
    /// the item a beat before the file is flushed, so retry briefly.
    private func copyToPasteboard(path: String, attempt: Int = 0) {
        let url = URL(fileURLWithPath: path)
        if let img = NSImage(contentsOf: url),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        } else if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.copyToPasteboard(path: path, attempt: attempt + 1)
            }
        }
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS' -only-testing:ProsciuttoTests/ScreenshotWatcherTests`
Expected: PASS.

- [ ] **Step 5: Commit (HELD — freeze)**

Under the commit freeze, do not commit. Confirm `xcodegen generate` picks up the new files and the build succeeds:
`xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`.
When the freeze lifts: `git add App/Prosciutto/Capture/ScreenshotWatcher.swift App/ProsciuttoTests/ScreenshotWatcherTests.swift && git commit -m "feat: ScreenshotWatcher detects screenshots and copies them to the clipboard"`.

---

## Task 2: Wire Feature 1 (pref + toggle + start/stop)

**Files:**
- Modify: `App/Prosciutto/Settings/Preferences.swift`
- Modify: `App/Prosciutto/Settings/SettingsView.swift`
- Modify: `App/Prosciutto/AppEnvironment.swift`

**Interfaces:**
- Consumes: `ScreenshotWatcher` from Task 1.
- Produces: `Preferences.autoCopyScreenshots: Bool` (default `false`); `AppEnvironment` starts/stops the watcher when it changes.

- [ ] **Step 1: Add the preference**

In `App/Prosciutto/Settings/Preferences.swift`, add to the `Keys` enum:
```swift
static let autoCopyScreenshots = "capture.autoCopyScreenshots"
```
and a computed property alongside the other capture prefs:
```swift
var autoCopyScreenshots: Bool {
    get { defaults.object(forKey: Keys.autoCopyScreenshots) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.autoCopyScreenshots) }
}
```

- [ ] **Step 2: Own + drive the watcher in AppEnvironment**

In `App/Prosciutto/AppEnvironment.swift`, add a stored property near the other services (e.g. next to `let paste = PasteService()`):
```swift
private let screenshotWatcher = ScreenshotWatcher()
```
Add a method (mirror `applyCaptureSettings()`):
```swift
/// Start/stop the screenshot watcher to match the current preference.
func applyScreenshotWatch() {
    if Preferences.shared.autoCopyScreenshots { screenshotWatcher.start() }
    else { screenshotWatcher.stop() }
}
```
Call `applyScreenshotWatch()` once during setup where `applyCaptureSettings()` is called (init/startup), and again whenever the toggle changes (Step 3 triggers it).

- [ ] **Step 3: Add the Settings toggle**

In `App/Prosciutto/Settings/SettingsView.swift`, in the Capture section, add a toggle bound to the pref, following the existing toggle pattern in that file. It must call `AppEnvironment`'s `applyScreenshotWatch()` on change (use the same mechanism sibling capture toggles use to push changes live, e.g. an `onChange`/action that calls into the environment). Label: `Copy screenshots to clipboard automatically`; caption: `New screenshots are copied so you can paste them right away.`

- [ ] **Step 4: Build + runtime verify**

Build and deploy:
```bash
xcodegen generate
xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -3
killall Prosciutto 2>/dev/null; sleep 1
cp -R build/Build/Products/Debug/Prosciutto.app /Applications/
open -a /Applications/Prosciutto.app
```
Manual check: Settings → enable the toggle → take a screenshot (⌘⇧4, select a region) → open the gallery (⌃V) → a new **image** clip is present, and ⌘V pastes the screenshot. Toggle OFF → take another screenshot → no new clip. (Grant the Desktop/Files TCC prompt if it appears.)

- [ ] **Step 5: Commit (HELD — freeze)**

Do not commit under the freeze; confirm the build + manual check pass. When lifted:
`git add App/Prosciutto/Settings/Preferences.swift App/Prosciutto/Settings/SettingsView.swift App/Prosciutto/AppEnvironment.swift && git commit -m "feat: Settings toggle to auto-copy screenshots to the clipboard"`.

---

## Task 3: ImageEditService (materialize + Preview + round-trip)

**Files:**
- Create: `App/Prosciutto/Paste/ImageEditService.swift`
- Test: `App/ProsciuttoTests/ImageMaterializerTests.swift`

**Interfaces:**
- Consumes: `ClipItem` (from `ProsciuttoKit`: has `kind: ClipKind`, `text: String?`, `imageData: Data?`).
- Produces: `enum ImageMaterializer { static func pngData(for item: ClipItem) -> Data? }` and `final class ImageEditService { init(pasteboard: NSPasteboard = .general); func edit(_ item: ClipItem) }`.

- [ ] **Step 1: Write the failing test**

```swift
// App/ProsciuttoTests/ImageMaterializerTests.swift
import XCTest
import AppKit
import ProsciuttoKit
@testable import Prosciutto

final class ImageMaterializerTests: XCTestCase {
    private func onePixelPNG() -> Data {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1)); img.unlockFocus()
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testImageDataBackedClipYieldsPNG() {
        let item = ClipItem(kind: .image, text: nil, imageData: onePixelPNG())
        let png = ImageMaterializer.pngData(for: item)
        XCTAssertNotNil(png)
        XCTAssertNotNil(NSImage(data: png!))
    }

    func testFileBackedImageClipReadsTheFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mat-\(UUID()).png")
        try onePixelPNG().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = ClipItem(kind: .image, text: url.path, imageData: nil)
        XCTAssertNotNil(ImageMaterializer.pngData(for: item))
    }

    func testTextClipYieldsNil() {
        let item = ClipItem(kind: .text, text: "hello", imageData: nil)
        XCTAssertNil(ImageMaterializer.pngData(for: item))
    }
}
```

> Note: confirm the `ClipItem` initializer signature in `Sources/ProsciuttoKit/Models/ClipItem.swift` and adjust argument labels/order in the test to match (it has defaulted params incl. `imageData:`); keep `kind`, `text`, `imageData` as used above.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS' -only-testing:ProsciuttoTests/ImageMaterializerTests`
Expected: FAIL — `ImageMaterializer` undefined.

- [ ] **Step 3: Write the implementation**

```swift
// App/Prosciutto/Paste/ImageEditService.swift
import AppKit
import Foundation
import ProsciuttoKit

/// Turns a single-image clip into PNG bytes: its inline image data (normalized to
/// PNG) or the contents of its backing image file. nil for anything that is not a
/// single image.
enum ImageMaterializer {
    static func pngData(for item: ClipItem) -> Data? {
        guard item.kind == .image else { return nil }
        if let data = item.imageData {
            if let rep = NSBitmapImageRep(data: data),
               let png = rep.representation(using: .png, properties: [:]) { return png }
            return data
        }
        if let path = item.text {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return nil
    }
}

/// Opens an image clip in Preview and, when the user saves, writes the edited image
/// back to the pasteboard (the poller then stores it as a fresh clip). The original
/// clip is never modified; we edit a throwaway temp copy.
final class ImageEditService {
    private let pasteboard: NSPasteboard
    private var source: DispatchSourceFileSystemObject?
    private var tempURL: URL?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func edit(_ item: ClipItem) {
        guard let png = ImageMaterializer.pngData(for: item) else { return }
        cleanup()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prosciutto-edit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return }
        tempURL = url

        // Prefer Preview; fall back to the default app for the file type.
        let cfg = NSWorkspace.OpenConfiguration()
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: cfg, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        watchForSave(url)
    }

    private func watchForSave(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let ev = src.data
            if ev.contains(.rename) || ev.contains(.delete) { self.cleanup(); return }
            if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                self.pasteboard.clearContents()
                self.pasteboard.setData(data, forType: .png)   // Preview saves PNG in place
            }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func cleanup() {
        source?.cancel(); source = nil
        if let u = tempURL { try? FileManager.default.removeItem(at: u); tempURL = nil }
    }

    deinit { cleanup() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS' -only-testing:ProsciuttoTests/ImageMaterializerTests`
Expected: PASS.

- [ ] **Step 5: Commit (HELD — freeze)**

Do not commit under the freeze. Verify `xcodegen generate` + build succeed. When lifted:
`git add App/Prosciutto/Paste/ImageEditService.swift App/ProsciuttoTests/ImageMaterializerTests.swift && git commit -m "feat: ImageEditService opens image clips in Preview and round-trips edits"`.

---

## Task 4: Wire Feature 2 (edit button + plumbing)

**Files:**
- Modify: `App/Prosciutto/UI/Cards/ClipCard.swift`
- Modify: `App/Prosciutto/UI/GalleryView.swift:239-252`
- Modify: `App/Prosciutto/UI/GalleryViewModel.swift`
- Modify: `App/Prosciutto/AppEnvironment.swift`

**Interfaces:**
- Consumes: `ImageEditService` (Task 3).
- Produces: `ClipCard.onEditImage: () -> Void`; `GalleryViewModel.editImage: (ClipItem) -> Void`.

- [ ] **Step 1: Add the closure + button to ClipCard**

In `App/Prosciutto/UI/Cards/ClipCard.swift`, add near the other `on…` closures (after line 23):
```swift
var onEditImage: () -> Void = {}
```
In `actionBar` (before the trash button, around line 266), add:
```swift
if item.kind == .image { actionButton("pencil.tip.crop.circle", onEditImage) }
```

- [ ] **Step 2: Add the VM hook**

In `App/Prosciutto/UI/GalleryViewModel.swift`, near `onPaste`/`onDismiss`, add:
```swift
/// Set by AppEnvironment. Opens the image clip in Preview for editing.
var editImage: (ClipItem) -> Void = { _ in }
```

- [ ] **Step 3: Bind in GalleryView**

In `App/Prosciutto/UI/GalleryView.swift`, in the `ClipCard(...)` call (after `onEditingChanged:` at line 252), add:
```swift
                                 onEditImage: { model.editImage(item) },
```

- [ ] **Step 4: Wire the service in AppEnvironment**

In `App/Prosciutto/AppEnvironment.swift`, add near the other services:
```swift
private let imageEditor = ImageEditService()
```
Where the other `vm.on…` closures are assigned (near `vm.onPaste = …`), add:
```swift
vm.editImage = { [weak self] item in self?.imageEditor.edit(item) }
```

- [ ] **Step 5: Build + runtime verify**

```bash
xcodegen generate
xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -3
killall Prosciutto 2>/dev/null; sleep 1
cp -R build/Build/Products/Debug/Prosciutto.app /Applications/
open -a /Applications/Prosciutto.app
```
Manual check: copy an image so an image card appears → open the gallery → hover the card → the new edit button (`pencil.tip.crop.circle`) shows on the image card only (not on text/code/link/multi-file) → click it → Preview opens the image → draw/crop → ⌘S → open the gallery again → a NEW image clip with the edit is present; the original image clip is unchanged.

- [ ] **Step 6: Commit (HELD — freeze)**

Do not commit under the freeze. Verify build + manual check. When lifted:
`git add App/Prosciutto/UI/Cards/ClipCard.swift App/Prosciutto/UI/GalleryView.swift App/Prosciutto/UI/GalleryViewModel.swift App/Prosciutto/AppEnvironment.swift && git commit -m "feat: edit button on image clips opens Preview and round-trips the result"`.

---

## Self-Review

**Spec coverage:**
- F1 detection via `kMDItemIsScreenCapture` NSMetadataQuery → Task 1. ✅
- F1 backlog exclusion (start-time cutoff) + processed-set → Task 1 (`shouldProcess`, `gathered`). ✅
- F1 write image data to pasteboard, poller captures → Task 1 `copyToPasteboard`. ✅
- F1 index-lag retry → Task 1 (retry up to 3× / 0.5s). ✅
- F1 pref default false + toggle + live start/stop → Task 2. ✅
- F1 leave file on disk → never written/moved (read-only). ✅
- F2 button only on single-image clips → Task 4 (`item.kind == .image`). ✅
- F2 materialize (imageData or file) to temp, open Preview, fallback default app → Task 3. ✅
- F2 watch save, round-trip to pasteboard as fresh clip, original untouched → Task 3. ✅
- F2 temp cleanup → Task 3 `cleanup()`. ✅

**Placeholder scan:** none — all steps carry concrete code/commands.

**Type consistency:** `ScreenshotWatcher.shouldProcess(path:created:startedAt:processed:)` identical in test + impl. `ImageMaterializer.pngData(for:)` identical across test/impl/service. `onEditImage` / `editImage(_:)` / `imageEditor.edit(_:)` consistent across Tasks 3–4. `applyScreenshotWatch()` defined + called in Task 2.

**Scope:** two independent features, four tasks; Tasks 1–2 (F1) and 3–4 (F2) are separable. Each task ends with an independently testable/verifiable deliverable.
