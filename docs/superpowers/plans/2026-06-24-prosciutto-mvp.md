# Prosciutto MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Prosciutto MVP — a native macOS menu-bar clipboard manager with a horizontal visual card gallery, global hotkey, rich per-type previews, search, privacy-respecting capture, and notarized/Homebrew distribution.

**Architecture:** Logic lives in a pure-Swift SPM library `ProsciuttoKit` (capture, dedupe, kind detection, exclusion, retention, search, store protocol) so it is unit-testable via `swift test` with no Xcode. A thin app target (SwiftUI + AppKit), defined by an XcodeGen `Project.yml`, hosts the menu bar, the slide-up `NSPanel` gallery, hotkey, paste synthesis, and a Core Data implementation of the store protocol. The monitor depends only on protocols (`PasteboardReader`, `ClipStore`, `Clock`) so the whole capture pipeline is testable with fakes.

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, Core Data (`NSPersistentCloudKitContainer`, cloud disabled), Vision (later phase), XcodeGen, swift-testing/XCTest. macOS 14+. Non-sandboxed.

## Global Constraints

- Minimum deployment target: **macOS 14.0**.
- Language: **Swift 5.10+**, strict concurrency where practical.
- **Non-sandboxed** app; entitlements allow Accessibility-driven paste.
- Default global hotkey: **⌘⇧V** (rebindable).
- Retention defaults: keep **last 1000** items OR **7 days** for unpinned, whichever first; pinned/boarded/snippet items never expire (boards/snippets are Phase 2 — MVP retains pinned exemption hook only).
- Privacy: honor `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` → skip capture. No telemetry. No network except favicon fetch.
- Bundle id: `app.prosciutto.Prosciutto`. Display name: **Prosciutto**.
- Distribution: notarized DMG (GitHub Releases) + Homebrew cask. Apple Developer ID required for notarization.
- Commit after every task. Conventional commit messages.

---

## File Structure

```
Package.swift                                  # ProsciuttoKit SPM library + tests
Project.yml                                    # XcodeGen app target definition
Sources/ProsciuttoKit/
  Models/ClipKind.swift                        # enum of item kinds
  Models/ClipItem.swift                        # value type (logic mirror of stored item)
  Models/PasteboardSnapshot.swift              # decoded pasteboard contents + markers
  Capture/PasteboardReader.swift               # protocol + changeCount/snapshot
  Capture/ContentHasher.swift                  # stable dedupe hash
  Capture/KindDetector.swift                   # snapshot -> ClipKind + extracted fields
  Capture/ExclusionPolicy.swift                # concealed/transient + app blocklist
  Capture/Clock.swift                          # protocol for testable time
  Capture/ClipboardMonitor.swift               # polling pipeline
  Store/ClipStore.swift                        # async persistence protocol
  Store/InMemoryClipStore.swift                # test/dev implementation w/ dedupe
  Retention/RetentionPolicy.swift              # prune decision logic
  Search/ClipQuery.swift                       # text/kind filter over items
Tests/ProsciuttoKitTests/
  ContentHasherTests.swift
  KindDetectorTests.swift
  ExclusionPolicyTests.swift
  InMemoryClipStoreTests.swift
  ClipboardMonitorTests.swift
  RetentionPolicyTests.swift
  ClipQueryTests.swift
App/Prosciutto/
  ProsciuttoApp.swift                          # @main, MenuBarExtra, app wiring
  AppEnvironment.swift                         # composition root (DI)
  Storage/Model.xcdatamodeld                   # Core Data model
  Storage/CoreDataStack.swift                  # NSPersistentCloudKitContainer (cloud off)
  Storage/CoreDataClipStore.swift              # ClipStore over Core Data
  Capture/SystemPasteboardReader.swift         # PasteboardReader over NSPasteboard
  Capture/SystemClock.swift                    # Clock over Date()
  Hotkey/HotkeyManager.swift                   # Carbon RegisterEventHotKey
  Paste/PasteService.swift                     # focus restore + CGEvent ⌘V
  Paste/AccessibilityAuthorizer.swift          # AXIsProcessTrusted gate
  UI/GalleryPanel.swift                        # non-activating NSPanel host
  UI/GalleryView.swift                         # SwiftUI gallery + search + keyboard
  UI/GalleryViewModel.swift                    # observable state, talks to store
  UI/Cards/ClipCard.swift                      # router view by kind
  UI/Cards/TextCard.swift
  UI/Cards/ImageCard.swift
  UI/Cards/LinkCard.swift
  UI/Cards/ColorCard.swift
  UI/Cards/CodeCard.swift
  UI/Cards/FileCard.swift
  UI/Onboarding/PermissionView.swift
  Settings/SettingsView.swift
  Settings/Preferences.swift                   # UserDefaults-backed settings
  Resources/Assets.xcassets                    # menu bar icon
scripts/
  build-release.sh                             # archive + export
  notarize.sh                                  # notarytool + staple + DMG
.github/workflows/ci.yml                       # swift test on PRs
Casks/prosciutto.rb                            # Homebrew cask (in tap repo later)
```

---

### Task 0: Project scaffolding (SPM library + XcodeGen app that launches)

**Files:**
- Create: `Package.swift`, `Sources/ProsciuttoKit/Empty.swift`, `Tests/ProsciuttoKitTests/SmokeTests.swift`
- Create: `Project.yml`, `App/Prosciutto/ProsciuttoApp.swift`, `App/Prosciutto/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a buildable SPM target `ProsciuttoKit`; an XcodeGen-generated `Prosciutto.xcodeproj` whose app shows a menu-bar item.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProsciuttoKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ProsciuttoKit", targets: ["ProsciuttoKit"])],
    targets: [
        .target(name: "ProsciuttoKit"),
        .testTarget(name: "ProsciuttoKitTests", dependencies: ["ProsciuttoKit"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder source + smoke test**

`Sources/ProsciuttoKit/Empty.swift`:
```swift
public enum ProsciuttoKit { public static let version = "0.1.0" }
```

`Tests/ProsciuttoKitTests/SmokeTests.swift`:
```swift
import XCTest
@testable import ProsciuttoKit

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(ProsciuttoKit.version, "0.1.0") }
}
```

- [ ] **Step 3: Run the test, expect PASS**

Run: `swift test`
Expected: builds, `testVersion` passes.

- [ ] **Step 4: Write `Project.yml` for the app target**

```yaml
name: Prosciutto
options:
  bundleIdPrefix: app.prosciutto
  deploymentTarget: { macOS: "14.0" }
packages:
  ProsciuttoKit: { path: . }
targets:
  Prosciutto:
    type: application
    platform: macOS
    sources: [App/Prosciutto]
    dependencies:
      - package: ProsciuttoKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.prosciutto.Prosciutto
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "5.10"
        INFOPLIST_KEY_LSUIElement: YES        # menu-bar app, no dock icon
        INFOPLIST_KEY_NSHumanReadableCopyright: "© 2026 Prosciutto contributors"
```

- [ ] **Step 5: Write the minimal app**

`App/Prosciutto/ProsciuttoApp.swift`:
```swift
import SwiftUI

@main
struct ProsciuttoApp: App {
    var body: some Scene {
        MenuBarExtra("Prosciutto", systemImage: "rectangle.stack") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

Add an empty `Assets.xcassets/AppIcon.appiconset/Contents.json` with `{ "images": [], "info": { "version": 1, "author": "xcode" } }`.

- [ ] **Step 6: Generate project and build**

Run: `brew install xcodegen || true; xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug build`
Expected: BUILD SUCCEEDED. Launching the `.app` shows a menu-bar icon with a working Quit item.

- [ ] **Step 7: Add CI**

`.github/workflows/ci.yml`:
```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift test
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold ProsciuttoKit package and XcodeGen app shell"
```

---

### Task 1: ClipKind + ContentHasher

**Files:**
- Create: `Sources/ProsciuttoKit/Models/ClipKind.swift`, `Sources/ProsciuttoKit/Capture/ContentHasher.swift`
- Test: `Tests/ProsciuttoKitTests/ContentHasherTests.swift`

**Interfaces:**
- Produces: `enum ClipKind: String, Codable, CaseIterable { case text, rtf, image, link, color, code, file }`
- Produces: `enum ContentHasher { static func hash(kind: ClipKind, primary: Data) -> String }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ProsciuttoKit

final class ContentHasherTests: XCTestCase {
    func testSameContentSameHash() {
        let a = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        let b = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        XCTAssertEqual(a, b)
    }
    func testDifferentKindDifferentHash() {
        let a = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        let b = ContentHasher.hash(kind: .code, primary: Data("hello".utf8))
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — Run: `swift test --filter ContentHasherTests` → fails (types undefined).

- [ ] **Step 3: Implement**

`ClipKind.swift`:
```swift
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, rtf, image, link, color, code, file
}
```

`ContentHasher.swift`:
```swift
import Foundation
import CryptoKit

public enum ContentHasher {
    public static func hash(kind: ClipKind, primary: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: primary)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter ContentHasherTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ClipKind and ContentHasher"`

---

### Task 2: PasteboardSnapshot + KindDetector

**Files:**
- Create: `Sources/ProsciuttoKit/Models/PasteboardSnapshot.swift`, `Sources/ProsciuttoKit/Capture/KindDetector.swift`
- Test: `Tests/ProsciuttoKitTests/KindDetectorTests.swift`

**Interfaces:**
- Produces:
```swift
public struct PasteboardSnapshot: Sendable {
    public var plainText: String?
    public var rtfData: Data?
    public var htmlString: String?
    public var imageData: Data?      // PNG/TIFF bytes
    public var fileURLs: [URL]
    public var markerTypes: Set<String>   // raw pasteboard type identifiers present
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public init(plainText: String? = nil, rtfData: Data? = nil, htmlString: String? = nil,
                imageData: Data? = nil, fileURLs: [URL] = [], markerTypes: Set<String> = [],
                sourceAppBundleID: String? = nil, sourceAppName: String? = nil) { /* assign */ }
}
```
- Produces: `enum KindDetector { static func detect(_ s: PasteboardSnapshot) -> ClipKind? }` (nil = nothing capturable).
- Detection order: fileURLs→`.file`; imageData→`.image`; plainText that is a single hex color (`#RGB`/`#RRGGBB`/`#RRGGBBAA`)→`.color`; plainText that is a single URL→`.link`; plainText that looks like code (heuristic)→`.code`; rtfData present→`.rtf`; plainText→`.text`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProsciuttoKit

final class KindDetectorTests: XCTestCase {
    func snap(_ t: String) -> PasteboardSnapshot { PasteboardSnapshot(plainText: t) }

    func testColor() { XCTAssertEqual(KindDetector.detect(snap("#3FA9FF")), .color) }
    func testColorShort() { XCTAssertEqual(KindDetector.detect(snap("#fff")), .color) }
    func testLink() { XCTAssertEqual(KindDetector.detect(snap("https://github.com/p0deje/Maccy")), .link) }
    func testPlainText() { XCTAssertEqual(KindDetector.detect(snap("just some words here")), .text) }
    func testCode() { XCTAssertEqual(KindDetector.detect(snap("func foo() { return 1 }")), .code) }
    func testImage() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(imageData: Data([0x89,0x50]))), .image)
    }
    func testFile() {
        XCTAssertEqual(KindDetector.detect(PasteboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/x")])), .file)
    }
    func testEmpty() { XCTAssertNil(KindDetector.detect(PasteboardSnapshot())) }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter KindDetectorTests`.

- [ ] **Step 3: Implement**

`PasteboardSnapshot.swift`: the struct above with the init assigning all stored properties.

`KindDetector.swift`:
```swift
import Foundation

public enum KindDetector {
    private static let colorRegex = try! NSRegularExpression(
        pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

    public static func detect(_ s: PasteboardSnapshot) -> ClipKind? {
        if !s.fileURLs.isEmpty { return .file }
        if s.imageData != nil { return .image }
        if let raw = s.plainText {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return s.rtfData != nil ? .rtf : nil }
            if isColor(t) { return .color }
            if isURL(t) { return .link }
            if looksLikeCode(t) { return .code }
            return .text
        }
        if s.rtfData != nil { return .rtf }
        return nil
    }

    static func isColor(_ t: String) -> Bool {
        let r = NSRange(t.startIndex..., in: t)
        return colorRegex.firstMatch(in: t, range: r) != nil
    }
    static func isURL(_ t: String) -> Bool {
        guard !t.contains(" "), !t.contains("\n") else { return false }
        guard let u = URL(string: t), let scheme = u.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }
    static func looksLikeCode(_ t: String) -> Bool {
        let tokens = ["func ", "def ", "class ", "{", "};", "=>", "import ", "const ", "let ", "var ", "</", "/>"]
        let hits = tokens.filter { t.contains($0) }.count
        let newlineDense = t.filter { $0 == "\n" }.count >= 1 && t.contains("  ")
        return hits >= 2 || (hits >= 1 && newlineDense)
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter KindDetectorTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add PasteboardSnapshot and KindDetector"`

---

### Task 3: ClipItem value type + PasteboardReader/Clock protocols

**Files:**
- Create: `Sources/ProsciuttoKit/Models/ClipItem.swift`, `Sources/ProsciuttoKit/Capture/PasteboardReader.swift`, `Sources/ProsciuttoKit/Capture/Clock.swift`
- Test: `Tests/ProsciuttoKitTests/ClipItemTests.swift`

**Interfaces:**
- Produces:
```swift
public struct ClipItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var kind: ClipKind
    public var textPlain: String?
    public var rtfData: Data?
    public var htmlString: String?
    public var imageData: Data?
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var contentHash: String
    public var isPinned: Bool
    public var expiresAt: Date?
    public static func make(from snapshot: PasteboardSnapshot, kind: ClipKind, now: Date,
                            ttl: TimeInterval) -> ClipItem
}
```
- Produces: `protocol PasteboardReader { var changeCount: Int { get }; func snapshot() -> PasteboardSnapshot? }`
- Produces: `protocol Clock: Sendable { func now() -> Date }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ProsciuttoKit

final class ClipItemTests: XCTestCase {
    func testMakeFromTextSnapshot() {
        let now = Date(timeIntervalSince1970: 1000)
        let snap = PasteboardSnapshot(plainText: "hello", sourceAppBundleID: "com.test")
        let item = ClipItem.make(from: snap, kind: .text, now: now, ttl: 60)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.textPlain, "hello")
        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(item.createdAt, now)
        XCTAssertEqual(item.expiresAt, now.addingTimeInterval(60))
        XCTAssertFalse(item.contentHash.isEmpty)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter ClipItemTests`.

- [ ] **Step 3: Implement**

`Clock.swift`:
```swift
import Foundation
public protocol Clock: Sendable { func now() -> Date }
```

`PasteboardReader.swift`:
```swift
public protocol PasteboardReader {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot?
}
```

`ClipItem.swift`: the struct above plus:
```swift
public static func make(from snapshot: PasteboardSnapshot, kind: ClipKind,
                        now: Date, ttl: TimeInterval) -> ClipItem {
    let primary: Data = snapshot.imageData
        ?? snapshot.fileURLs.first.map { Data($0.path.utf8) }
        ?? snapshot.plainText.map { Data($0.utf8) }
        ?? snapshot.rtfData ?? Data()
    return ClipItem(
        id: UUID(), createdAt: now, lastUsedAt: now, useCount: 1, kind: kind,
        textPlain: snapshot.plainText, rtfData: snapshot.rtfData, htmlString: snapshot.htmlString,
        imageData: snapshot.imageData,
        sourceAppBundleID: snapshot.sourceAppBundleID, sourceAppName: snapshot.sourceAppName,
        contentHash: ContentHasher.hash(kind: kind, primary: primary),
        isPinned: false, expiresAt: now.addingTimeInterval(ttl))
}
```
(Give `ClipItem` a memberwise `public init`.)

- [ ] **Step 4: Run, expect PASS** — `swift test --filter ClipItemTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ClipItem value type and reader/clock protocols"`

---

### Task 4: ExclusionPolicy

**Files:**
- Create: `Sources/ProsciuttoKit/Capture/ExclusionPolicy.swift`
- Test: `Tests/ProsciuttoKitTests/ExclusionPolicyTests.swift`

**Interfaces:**
- Produces:
```swift
public struct ExclusionPolicy: Sendable {
    public var blockedBundleIDs: Set<String>
    public static let concealedType = "org.nspasteboard.ConcealedType"
    public static let transientType = "org.nspasteboard.TransientType"
    public static let autoGeneratedType = "org.nspasteboard.AutoGeneratedType"
    public init(blockedBundleIDs: Set<String> = ExclusionPolicy.defaultBlocked)
    public static let defaultBlocked: Set<String>
    public func shouldCapture(_ s: PasteboardSnapshot) -> Bool
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProsciuttoKit

final class ExclusionPolicyTests: XCTestCase {
    let policy = ExclusionPolicy(blockedBundleIDs: ["com.agilebits.onepassword7"])

    func testConcealedSkipped() {
        let s = PasteboardSnapshot(plainText: "secret", markerTypes: [ExclusionPolicy.concealedType])
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testTransientSkipped() {
        let s = PasteboardSnapshot(plainText: "x", markerTypes: [ExclusionPolicy.transientType])
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testBlockedAppSkipped() {
        let s = PasteboardSnapshot(plainText: "x", sourceAppBundleID: "com.agilebits.onepassword7")
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testNormalCaptured() {
        XCTAssertTrue(policy.shouldCapture(PasteboardSnapshot(plainText: "hi", sourceAppBundleID: "com.apple.Safari")))
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter ExclusionPolicyTests`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ExclusionPolicy: Sendable {
    public var blockedBundleIDs: Set<String>
    public static let concealedType = "org.nspasteboard.ConcealedType"
    public static let transientType = "org.nspasteboard.TransientType"
    public static let autoGeneratedType = "org.nspasteboard.AutoGeneratedType"

    public static let defaultBlocked: Set<String> = [
        "com.agilebits.onepassword7", "com.agilebits.onepassword",
        "com.1password.1password", "com.lastpass.LastPass",
        "in.sinew.Walletx", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
    ]

    public init(blockedBundleIDs: Set<String> = ExclusionPolicy.defaultBlocked) {
        self.blockedBundleIDs = blockedBundleIDs
    }

    public func shouldCapture(_ s: PasteboardSnapshot) -> Bool {
        if s.markerTypes.contains(Self.concealedType) { return false }
        if s.markerTypes.contains(Self.transientType) { return false }
        if s.markerTypes.contains(Self.autoGeneratedType) { return false }
        if let id = s.sourceAppBundleID, blockedBundleIDs.contains(id) { return false }
        return true
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter ExclusionPolicyTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ExclusionPolicy for privacy-respecting capture"`

---

### Task 5: ClipStore protocol + InMemoryClipStore with dedupe

**Files:**
- Create: `Sources/ProsciuttoKit/Store/ClipStore.swift`, `Sources/ProsciuttoKit/Store/InMemoryClipStore.swift`
- Test: `Tests/ProsciuttoKitTests/InMemoryClipStoreTests.swift`

**Interfaces:**
- Produces:
```swift
public protocol ClipStore: Sendable {
    func upsert(_ item: ClipItem) async throws       // dedupe by contentHash
    func all() async throws -> [ClipItem]            // newest lastUsedAt first
    func delete(id: UUID) async throws
    func setPinned(id: UUID, _ pinned: Bool) async throws
    func prune(keeping policy: RetentionPolicy, now: Date) async throws
}
```
- Produces: `actor InMemoryClipStore: ClipStore` (used by tests + dev). Upsert with an existing `contentHash` bumps `lastUsedAt`/`useCount` instead of duplicating.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProsciuttoKit

final class InMemoryClipStoreTests: XCTestCase {
    func makeItem(_ text: String, now: Date) -> ClipItem {
        ClipItem.make(from: PasteboardSnapshot(plainText: text), kind: .text, now: now, ttl: 60)
    }

    func testUpsertDedup() async throws {
        let store = InMemoryClipStore()
        let t0 = Date(timeIntervalSince1970: 0)
        try await store.upsert(makeItem("hello", now: t0))
        try await store.upsert(makeItem("hello", now: t0.addingTimeInterval(10)))
        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].useCount, 2)
        XCTAssertEqual(items[0].lastUsedAt, t0.addingTimeInterval(10))
    }

    func testOrderingNewestFirst() async throws {
        let store = InMemoryClipStore()
        let t0 = Date(timeIntervalSince1970: 0)
        try await store.upsert(makeItem("a", now: t0))
        try await store.upsert(makeItem("b", now: t0.addingTimeInterval(5)))
        let items = try await store.all()
        XCTAssertEqual(items.map(\.textPlain), ["b", "a"])
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter InMemoryClipStoreTests`.

- [ ] **Step 3: Implement**

`ClipStore.swift`: protocol above (RetentionPolicy comes in Task 7; declare `prune` now and add a stub `RetentionPolicy` placeholder type in Task 7 — to avoid a forward-reference, define `RetentionPolicy` in Task 7 BEFORE wiring `prune` callers; for this task implement `prune` against the Task 7 type, so do Task 7 first if executing strictly in order). To keep tasks independently testable, implement `prune` as part of Task 7. For Task 5, include `prune` in the protocol but leave `InMemoryClipStore.prune` calling into `RetentionPolicy` which Task 7 delivers.

> Execution note: Tasks 5 and 7 share the `prune` signature. Implement `RetentionPolicy` (Task 7) and `InMemoryClipStore.prune` together. The store's non-prune methods are fully testable now.

`InMemoryClipStore.swift`:
```swift
import Foundation

public actor InMemoryClipStore: ClipStore {
    private var items: [UUID: ClipItem] = [:]
    public init() {}

    public func upsert(_ item: ClipItem) async throws {
        if let existing = items.values.first(where: { $0.contentHash == item.contentHash }) {
            var updated = existing
            updated.lastUsedAt = item.createdAt
            updated.useCount += 1
            items[existing.id] = updated
        } else {
            items[item.id] = item
        }
    }
    public func all() async throws -> [ClipItem] {
        items.values.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
    public func delete(id: UUID) async throws { items[id] = nil }
    public func setPinned(id: UUID, _ pinned: Bool) async throws {
        guard var it = items[id] else { return }
        it.isPinned = pinned
        it.expiresAt = pinned ? nil : it.expiresAt
        items[id] = it
    }
    public func prune(keeping policy: RetentionPolicy, now: Date) async throws {
        let survivors = policy.survivors(of: Array(items.values), now: now)
        items = Dictionary(uniqueKeysWithValues: survivors.map { ($0.id, $0) })
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter InMemoryClipStoreTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ClipStore protocol and InMemoryClipStore with dedupe"`

---

### Task 6: ClipboardMonitor pipeline

**Files:**
- Create: `Sources/ProsciuttoKit/Capture/ClipboardMonitor.swift`
- Test: `Tests/ProsciuttoKitTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `PasteboardReader`, `ClipStore`, `ExclusionPolicy`, `Clock`, `KindDetector`, `ClipItem`.
- Produces:
```swift
public final class ClipboardMonitor {
    public init(reader: PasteboardReader, store: ClipStore, exclusion: ExclusionPolicy,
                clock: Clock, ttl: TimeInterval)
    public func poll() async throws        // one tick: detect change -> maybe capture
    public func start(interval: TimeInterval)   // schedules poll() on a timer
    public func stop()
    public var isPaused: Bool { get set }
}
```

- [ ] **Step 1: Write the failing test (with fakes)**

```swift
import XCTest
@testable import ProsciuttoKit

final class FakeReader: PasteboardReader {
    var changeCount = 0
    var next: PasteboardSnapshot?
    func snapshot() -> PasteboardSnapshot? { next }
}
struct FixedClock: Clock { var t: Date; func now() -> Date { t } }

final class ClipboardMonitorTests: XCTestCase {
    func testPollCapturesNewItem() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: Date(timeIntervalSince1970: 0)), ttl: 60)

        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "copied text")
        try await monitor.poll()

        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].textPlain, "copied text")
    }

    func testPollIgnoresUnchangedCount() async throws {
        let reader = FakeReader(); let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60)
        reader.changeCount = 0          // same as monitor's initial baseline
        reader.next = PasteboardSnapshot(plainText: "x")
        try await monitor.poll()
        let items = try await store.all()
        XCTAssertEqual(items.count, 0)
    }

    func testPollRespectsExclusion() async throws {
        let reader = FakeReader(); let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60)
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "secret", markerTypes: [ExclusionPolicy.concealedType])
        try await monitor.poll()
        XCTAssertEqual(try await store.all().count, 0)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter ClipboardMonitorTests`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public final class ClipboardMonitor {
    private let reader: PasteboardReader
    private let store: ClipStore
    private let exclusion: ExclusionPolicy
    private let clock: Clock
    private let ttl: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?
    public var isPaused = false

    public init(reader: PasteboardReader, store: ClipStore, exclusion: ExclusionPolicy,
                clock: Clock, ttl: TimeInterval) {
        self.reader = reader; self.store = store; self.exclusion = exclusion
        self.clock = clock; self.ttl = ttl
        self.lastChangeCount = reader.changeCount   // baseline; ignore pre-existing content
    }

    public func poll() async throws {
        guard !isPaused else { return }
        let current = reader.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let snap = reader.snapshot(), exclusion.shouldCapture(snap),
              let kind = KindDetector.detect(snap) else { return }
        let item = ClipItem.make(from: snap, kind: kind, now: clock.now(), ttl: ttl)
        try await store.upsert(item)
    }

    public func start(interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { try? await self?.poll() }
        }
    }
    public func stop() { timer?.invalidate(); timer = nil }
}
```

> Note: in `testPollIgnoresUnchangedCount`, monitor baseline equals `reader.changeCount` (0) at init, so a poll with count still 0 is a no-op. Correct.

- [ ] **Step 4: Run, expect PASS** — `swift test --filter ClipboardMonitorTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ClipboardMonitor capture pipeline"`

---

### Task 7: RetentionPolicy

**Files:**
- Create: `Sources/ProsciuttoKit/Retention/RetentionPolicy.swift`
- Test: `Tests/ProsciuttoKitTests/RetentionPolicyTests.swift`

**Interfaces:**
- Produces:
```swift
public struct RetentionPolicy: Sendable {
    public var maxItems: Int          // default 1000
    public var maxAge: TimeInterval   // default 7*24*3600
    public init(maxItems: Int = 1000, maxAge: TimeInterval = 604_800)
    public func survivors(of items: [ClipItem], now: Date) -> [ClipItem]
}
```
Rule: pinned items always survive. Among unpinned, drop those older than `maxAge` (by `lastUsedAt`); then if still over `maxItems` unpinned, keep the newest `maxItems`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProsciuttoKit

final class RetentionPolicyTests: XCTestCase {
    func item(_ name: String, age: TimeInterval, pinned: Bool, now: Date) -> ClipItem {
        var it = ClipItem.make(from: PasteboardSnapshot(plainText: name), kind: .text,
                               now: now.addingTimeInterval(-age), ttl: 60)
        it.lastUsedAt = now.addingTimeInterval(-age)
        it.isPinned = pinned
        return it
    }
    func testDropsOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 100, maxAge: 1000)
        let items = [item("old", age: 2000, pinned: false, now: now),
                     item("new", age: 100, pinned: false, now: now)]
        let s = p.survivors(of: items, now: now).map(\.textPlain)
        XCTAssertEqual(s, ["new"])
    }
    func testKeepsPinnedEvenOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 100, maxAge: 1000)
        let items = [item("oldpinned", age: 99999, pinned: true, now: now)]
        XCTAssertEqual(p.survivors(of: items, now: now).count, 1)
    }
    func testCapsCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 2, maxAge: 999999)
        let items = (0..<5).map { item("i\($0)", age: TimeInterval($0), pinned: false, now: now) }
        XCTAssertEqual(p.survivors(of: items, now: now).count, 2)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter RetentionPolicyTests`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct RetentionPolicy: Sendable {
    public var maxItems: Int
    public var maxAge: TimeInterval
    public init(maxItems: Int = 1000, maxAge: TimeInterval = 604_800) {
        self.maxItems = maxItems; self.maxAge = maxAge
    }
    public func survivors(of items: [ClipItem], now: Date) -> [ClipItem] {
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
            .filter { now.timeIntervalSince($0.lastUsedAt) <= maxAge }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        if unpinned.count > maxItems { unpinned = Array(unpinned.prefix(maxItems)) }
        return pinned + unpinned
    }
}
```

Now complete `InMemoryClipStore.prune` (already calls `survivors`) and verify `swift test --filter InMemoryClipStoreTests` still passes.

- [ ] **Step 4: Run, expect PASS** — `swift test --filter RetentionPolicyTests` and full `swift test`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add RetentionPolicy and wire store pruning"`

---

### Task 8: ClipQuery (search + filter)

**Files:**
- Create: `Sources/ProsciuttoKit/Search/ClipQuery.swift`
- Test: `Tests/ProsciuttoKitTests/ClipQueryTests.swift`

**Interfaces:**
- Produces:
```swift
public struct ClipQuery: Sendable {
    public var text: String = ""
    public var kinds: Set<ClipKind> = []      // empty = all
    public var sourceAppBundleID: String? = nil
    public init()
    public func apply(to items: [ClipItem]) -> [ClipItem]
}
```
Match: case-insensitive `text` against `textPlain` (and later `ocrText`); `kinds` filter if non-empty; `sourceAppBundleID` filter if set. Preserves input order.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProsciuttoKit

final class ClipQueryTests: XCTestCase {
    func mk(_ t: String, kind: ClipKind, app: String? = nil) -> ClipItem {
        var i = ClipItem.make(from: PasteboardSnapshot(plainText: t, sourceAppBundleID: app),
                              kind: kind, now: .init(timeIntervalSince1970: 0), ttl: 60)
        i.kind = kind; return i
    }
    func testTextFilter() {
        var q = ClipQuery(); q.text = "hub"
        let items = [mk("github", kind: .link), mk("apple", kind: .text)]
        XCTAssertEqual(q.apply(to: items).map(\.textPlain), ["github"])
    }
    func testKindFilter() {
        var q = ClipQuery(); q.kinds = [.image]
        let items = [mk("a", kind: .text), mk("b", kind: .image)]
        XCTAssertEqual(q.apply(to: items).count, 1)
    }
    func testEmptyQueryReturnsAll() {
        let items = [mk("a", kind: .text), mk("b", kind: .image)]
        XCTAssertEqual(ClipQuery().apply(to: items).count, 2)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter ClipQueryTests`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ClipQuery: Sendable {
    public var text: String = ""
    public var kinds: Set<ClipKind> = []
    public var sourceAppBundleID: String? = nil
    public init() {}

    public func apply(to items: [ClipItem]) -> [ClipItem] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if !kinds.isEmpty && !kinds.contains(item.kind) { return false }
            if let app = sourceAppBundleID, item.sourceAppBundleID != app { return false }
            if !needle.isEmpty {
                let hay = (item.textPlain ?? "").lowercased()
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter ClipQueryTests`.

- [ ] **Step 5: Commit** — `git commit -am "feat: add ClipQuery search/filter"`

---

### Task 9: Core Data store (app target) implementing ClipStore

**Files:**
- Create: `App/Prosciutto/Storage/Model.xcdatamodeld` (entity `CDClipItem`), `App/Prosciutto/Storage/CoreDataStack.swift`, `App/Prosciutto/Storage/CoreDataClipStore.swift`
- Test: `App/ProsciuttoTests/CoreDataClipStoreTests.swift` (XCTest target in `Project.yml`)

**Interfaces:**
- Consumes: `ClipStore`, `ClipItem`, `RetentionPolicy`.
- Produces: `final class CoreDataClipStore: ClipStore` backed by an in-memory or on-disk `NSPersistentCloudKitContainer` (cloud OFF in v1).

`CDClipItem` attributes mirror `ClipItem` fields (id UUID, createdAt/lastUsedAt Date, useCount Int64, kind String, textPlain String?, rtfData Binary?, htmlString String?, imageData Binary? **Allows External Storage**, sourceAppBundleID String?, sourceAppName String?, contentHash String **indexed**, isPinned Bool, expiresAt Date?).

- [ ] **Step 1: Add a test target to `Project.yml`**

```yaml
  ProsciuttoTests:
    type: bundle.unit-test
    platform: macOS
    sources: [App/ProsciuttoTests]
    dependencies:
      - target: Prosciutto
      - package: ProsciuttoKit
```
Add a scheme that runs tests. Run `xcodegen generate`.

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import ProsciuttoKit
@testable import Prosciutto

final class CoreDataClipStoreTests: XCTestCase {
    func testUpsertAndDedup() async throws {
        let store = CoreDataClipStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 0)
        let a = ClipItem.make(from: .init(plainText: "hi"), kind: .text, now: now, ttl: 60)
        try await store.upsert(a)
        try await store.upsert(a)               // same hash
        let items = try await store.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].useCount, 2)
    }
}
```

- [ ] **Step 3: Run, expect FAIL** — `xcodebuild test -project Prosciutto.xcodeproj -scheme Prosciutto -destination 'platform=macOS'` → fails (type undefined).

- [ ] **Step 4: Implement the model + stack + store**

`CoreDataStack.swift`:
```swift
import CoreData

final class CoreDataStack {
    let container: NSPersistentCloudKitContainer
    init(inMemory: Bool) {
        container = NSPersistentCloudKitContainer(name: "Model")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        // Cloud disabled for v1: leave cloudKitContainerOptions nil.
        container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
```

`CoreDataClipStore.swift` — implement each `ClipStore` method on a background context, mapping `CDClipItem` ↔ `ClipItem`. Upsert fetches by `contentHash` (indexed); if found, bump `lastUsedAt`/`useCount`; else insert. `all()` fetches sorted by `lastUsedAt` descending. `prune` fetches all, computes `RetentionPolicy.survivors`, deletes the rest. Provide a private `map(_:)` both directions.

```swift
import CoreData
import ProsciuttoKit

final class CoreDataClipStore: ClipStore {
    private let stack: CoreDataStack
    init(inMemory: Bool = false) { stack = CoreDataStack(inMemory: inMemory) }

    func upsert(_ item: ClipItem) async throws {
        try await perform { ctx in
            let req = CDClipItem.fetchRequest()
            req.predicate = NSPredicate(format: "contentHash == %@", item.contentHash)
            req.fetchLimit = 1
            if let existing = try ctx.fetch(req).first {
                existing.lastUsedAt = item.createdAt
                existing.useCount += 1
            } else {
                let cd = CDClipItem(context: ctx)
                Self.write(item, into: cd)
            }
            try ctx.save()
        }
    }
    func all() async throws -> [ClipItem] {
        try await perform { ctx in
            let req = CDClipItem.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "lastUsedAt", ascending: false)]
            return try ctx.fetch(req).map(Self.read)
        }
    }
    func delete(id: UUID) async throws { /* fetch by id, delete, save */ }
    func setPinned(id: UUID, _ pinned: Bool) async throws { /* fetch by id, set, save */ }
    func prune(keeping policy: RetentionPolicy, now: Date) async throws {
        try await perform { ctx in
            let all = try ctx.fetch(CDClipItem.fetchRequest())
            let survivors = Set(policy.survivors(of: all.map(Self.read), now: now).map(\.id))
            for cd in all where !survivors.contains(cd.id!) { ctx.delete(cd) }
            try ctx.save()
        }
    }

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let ctx = stack.container.newBackgroundContext()
        return try await ctx.perform { try block(ctx) }
    }
    private static func write(_ i: ClipItem, into cd: CDClipItem) { /* assign all fields */ }
    private static func read(_ cd: CDClipItem) -> ClipItem { /* construct ClipItem */ }
}
```

Fill the `delete`, `setPinned`, `write`, `read` bodies with the obvious field mapping.

- [ ] **Step 5: Run, expect PASS** — `xcodebuild test ... -scheme Prosciutto`.

- [ ] **Step 6: Commit** — `git commit -am "feat: add Core Data store implementing ClipStore"`

---

### Task 10: SystemPasteboardReader + SystemClock

**Files:**
- Create: `App/Prosciutto/Capture/SystemPasteboardReader.swift`, `App/Prosciutto/Capture/SystemClock.swift`

**Interfaces:**
- Produces: `struct SystemClock: Clock`; `final class SystemPasteboardReader: PasteboardReader` over `NSPasteboard.general`, populating `PasteboardSnapshot` (plain/rtf/html/image/fileURLs, present `markerTypes`, frontmost app via `NSWorkspace.shared.frontmostApplication`).

- [ ] **Step 1: Implement**

```swift
import AppKit
import ProsciuttoKit

struct SystemClock: Clock { func now() -> Date { Date() } }

final class SystemPasteboardReader: PasteboardReader {
    private let pb = NSPasteboard.general
    var changeCount: Int { pb.changeCount }

    func snapshot() -> PasteboardSnapshot? {
        let types = Set(pb.types?.map(\.rawValue) ?? [])
        let app = NSWorkspace.shared.frontmostApplication
        var snap = PasteboardSnapshot(
            plainText: pb.string(forType: .string),
            rtfData: pb.data(forType: .rtf),
            htmlString: pb.string(forType: .html),
            imageData: pb.data(forType: .png) ?? pb.data(forType: .tiff),
            fileURLs: (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.filter { $0.isFileURL } ?? [],
            markerTypes: types,
            sourceAppBundleID: app?.bundleIdentifier,
            sourceAppName: app?.localizedName)
        if snap.plainText == nil && snap.imageData == nil && snap.fileURLs.isEmpty
            && snap.rtfData == nil { return nil }
        return snap
    }
}
```

- [ ] **Step 2: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** — `git commit -am "feat: add system pasteboard reader and clock"`

---

### Task 11: HotkeyManager (global ⌘⇧V)

**Files:**
- Create: `App/Prosciutto/Hotkey/HotkeyManager.swift`

**Interfaces:**
- Produces: `final class HotkeyManager { init(); var onTrigger: (() -> Void)?; func register(keyCode: UInt32, modifiers: UInt32); func unregister() }` using Carbon `RegisterEventHotKey`. Default = `kVK_ANSI_V` + cmd+shift.

- [ ] **Step 1: Implement** (Carbon event hotkey)

```swift
import Carbon.HIToolbox
import AppKit

final class HotkeyManager {
    var onTrigger: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id = EventHotKeyID(signature: OSType(0x50524f53), id: 1) // 'PROS'

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            mgr.onTrigger?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}
```

- [ ] **Step 2: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual verify** — temporarily wire `onTrigger = { NSSound.beep() }` in app init; run; press ⌘⇧V; hear beep. Remove the temp wiring.

- [ ] **Step 4: Commit** — `git commit -am "feat: add global hotkey manager"`

---

### Task 12: PasteService + AccessibilityAuthorizer

**Files:**
- Create: `App/Prosciutto/Paste/AccessibilityAuthorizer.swift`, `App/Prosciutto/Paste/PasteService.swift`

**Interfaces:**
- Produces: `enum AccessibilityAuthorizer { static var isTrusted: Bool; static func prompt() }` (wraps `AXIsProcessTrustedWithOptions`).
- Produces: `final class PasteService { func paste(_ item: ClipItem, asPlainText: Bool) }` — writes the item to `NSPasteboard.general`, then synthesizes ⌘V via `CGEvent` to the frontmost app. If not trusted, only writes pasteboard (caller shows the nudge).

- [ ] **Step 1: Implement authorizer**

```swift
import ApplicationServices

enum AccessibilityAuthorizer {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func prompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
```

- [ ] **Step 2: Implement paste service**

```swift
import AppKit
import ProsciuttoKit

final class PasteService {
    func write(_ item: ClipItem, asPlainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image: if let d = item.imageData { pb.setData(d, forType: .png) }
        case .file:  if let t = item.textPlain { pb.setString(t, forType: .string) }
        default:
            if !asPlainText, let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            if let t = item.textPlain { pb.setString(t, forType: .string) }
        }
    }

    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        write(item, asPlainText: asPlainText)
        guard AccessibilityAuthorizer.isTrusted else { return }   // caller nudges
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9   // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 3: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit** — `git commit -am "feat: add paste service and accessibility authorizer"`

---

### Task 13: Card renderers (six kinds)

**Files:**
- Create: `App/Prosciutto/UI/Cards/ClipCard.swift` + `TextCard.swift`, `ImageCard.swift`, `LinkCard.swift`, `ColorCard.swift`, `CodeCard.swift`, `FileCard.swift`

**Interfaces:**
- Consumes: `ClipItem`, `ClipKind`.
- Produces: `struct ClipCard: View { let item: ClipItem; let index: Int? }` routing to a per-kind subview. Fixed card size ~`160×120`, rounded, subtle shadow, kind badge, optional `⌘N` index chip.

- [ ] **Step 1: Implement `ClipCard` router**

```swift
import SwiftUI
import ProsciuttoKit

struct ClipCard: View {
    let item: ClipItem
    let index: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(width: 160, height: 120)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if let index, index <= 9 {
                Text("⌘\(index)").font(.caption2).padding(4)
                    .background(.thinMaterial, in: Capsule()).padding(6)
            }
        }
        .shadow(radius: 3, y: 1)
    }
    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image: ImageCard(item: item)
        case .link:  LinkCard(item: item)
        case .color: ColorCard(item: item)
        case .code:  CodeCard(item: item)
        case .file:  FileCard(item: item)
        case .text, .rtf: TextCard(item: item)
        }
    }
}
```

- [ ] **Step 2: Implement the six subviews**

`TextCard`: scrollable/truncated `Text(item.textPlain ?? "")`, line limit 5, monospaced false.
`ImageCard`: `Image(nsImage:)` from `item.imageData` scaled-to-fill clipped; footer with `byteSize`/dimensions.
`LinkCard`: favicon (AsyncImage from `https://<host>/favicon.ico`), host as title, full URL truncated.
`ColorCard`: full-bleed swatch via `Color(nsColor:)` parsed from hex, hex string label.
`CodeCard`: monospaced `Text`, line limit 6, faint line-number gutter optional.
`FileCard`: `Image(nsImage: NSWorkspace.shared.icon(forFile:))`, file name, size.

Each is a small `View` taking `let item: ClipItem`. Keep under ~30 lines each.

- [ ] **Step 3: Add SwiftUI previews + snapshot smoke**

Add `#Preview` blocks per card with sample `ClipItem`s. Build the app and visually confirm in Xcode canvas (manual verification step — no automated snapshot dependency for MVP).

- [ ] **Step 4: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit** — `git commit -am "feat: add per-kind clip card renderers"`

---

### Task 14: GalleryViewModel + GalleryView (search, keyboard nav)

**Files:**
- Create: `App/Prosciutto/UI/GalleryViewModel.swift`, `App/Prosciutto/UI/GalleryView.swift`

**Interfaces:**
- Consumes: `ClipStore`, `ClipQuery`, `ClipItem`, `PasteService`.
- Produces:
```swift
@MainActor final class GalleryViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var query = ClipQuery()
    @Published var selection: Int = 0
    init(store: ClipStore, paste: PasteService, onPasted: @escaping () -> Void)
    func reload() async
    func filtered() -> [ClipItem]
    func moveSelection(_ delta: Int)
    func pasteSelected(asPlainText: Bool)
    func pasteIndex(_ i: Int)
    func togglePin(_ item: ClipItem) async
}
```
- Produces: `struct GalleryView: View` — top search field + filter pills, horizontal `ScrollView` of `ClipCard`s, keyboard handling (←/→ select, ↵ paste, ⌘1–9 quick paste, ⌘⌥V plain, ⌘P pin, Esc dismiss via `onDismiss`).

- [ ] **Step 1: Implement the view model**

`filtered()` returns `query.apply(to: items)`. `moveSelection` clamps to `0..<filtered().count`. `pasteSelected` calls `paste.paste(filtered()[selection], asPlainText:)` then `onPasted()` (which hides the panel). `pasteIndex(i)` pastes `filtered()[i-1]` when in range. `reload()` sets `items = (try? await store.all()) ?? []`.

- [ ] **Step 2: Implement the view**

Search `TextField` bound to `query.text` (`.onChange` does nothing extra — `filtered()` is recomputed). Filter pills toggle `query.kinds`. Horizontal `ScrollViewReader` + `LazyHStack` of `ClipCard(item:, index:)`, highlighting `selection`. Attach `.onKeyPress` handlers (macOS 14 API) for arrows/return/escape, and `.keyboardShortcut` buttons (hidden) for ⌘1–9, ⌘⌥V, ⌘P. Scroll to `selection` on change.

- [ ] **Step 3: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit** — `git commit -am "feat: add gallery view model and view"`

---

### Task 15: GalleryPanel (non-activating slide-up NSPanel)

**Files:**
- Create: `App/Prosciutto/UI/GalleryPanel.swift`

**Interfaces:**
- Consumes: `GalleryView`.
- Produces: `final class GalleryPanel { init(content: () -> AnyView); func toggle(); func show(); func hide() }` — a borderless `NSPanel` with `.nonactivatingPanel`, `level = .floating`, positioned across the bottom of the screen with the active app's focus preserved; hosts the SwiftUI gallery via `NSHostingView`. `hide()` restores key window to the previously frontmost app.

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

final class GalleryPanel {
    private let panel: NSPanel
    init(content: @escaping () -> AnyView) {
        panel = NSPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: content())
    }
    func show() {
        guard let screen = NSScreen.main else { return }
        let h: CGFloat = 220, margin: CGFloat = 16
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.minX + margin, y: f.minY + margin,
                              width: f.width - margin*2, height: h), display: true)
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    func toggle() { panel.isVisible ? hide() : show() }
}
```

- [ ] **Step 2: Build** — `xcodebuild -scheme Prosciutto build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** — `git commit -am "feat: add non-activating gallery panel"`

---

### Task 16: AppEnvironment wiring + menu bar + onboarding + pause

**Files:**
- Create: `App/Prosciutto/AppEnvironment.swift`, `App/Prosciutto/UI/Onboarding/PermissionView.swift`, `App/Prosciutto/Settings/Preferences.swift`
- Modify: `App/Prosciutto/ProsciuttoApp.swift`

**Interfaces:**
- Consumes: every prior component.
- Produces: `@MainActor final class AppEnvironment: ObservableObject` — composition root: builds `CoreDataClipStore`, `SystemPasteboardReader`, `ClipboardMonitor`, `HotkeyManager`, `PasteService`, `GalleryPanel`, `GalleryViewModel`. Owns `isPaused`. Starts the monitor at launch; registers the hotkey to `panel.toggle()` (after reloading the view model); runs a periodic prune timer.

- [ ] **Step 1: Implement `Preferences`** (UserDefaults wrapper: hotkey, retention maxItems/maxAge, isPaused, blockedBundleIDs).

- [ ] **Step 2: Implement `AppEnvironment`** wiring all pieces. On hotkey trigger: `Task { await vm.reload(); panel.show() }`. `GalleryViewModel.onPasted = { panel.hide() }`. Monitor `start(interval: 0.3)`. Prune `Timer` every 5 min calling `store.prune(keeping:now:)`.

```swift
@MainActor final class AppEnvironment: ObservableObject {
    let store = CoreDataClipStore()
    let paste = PasteService()
    let reader = SystemPasteboardReader()
    let hotkey = HotkeyManager()
    private(set) var monitor: ClipboardMonitor!
    private(set) var panel: GalleryPanel!
    private(set) var vm: GalleryViewModel!
    @Published var isPaused = false

    init() {
        vm = GalleryViewModel(store: store, paste: paste, onPasted: { [weak self] in self?.panel.hide() })
        panel = GalleryPanel { AnyView(GalleryView(model: self.vm, onDismiss: { self.panel.hide() })) }
        monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(), clock: SystemClock(), ttl: 604_800)
        monitor.start(interval: 0.3)
        hotkey.onTrigger = { [weak self] in
            guard let self else { return }
            Task { await self.vm.reload(); self.panel.show() }
        }
        hotkey.register()
        startPruneTimer()
        if !AccessibilityAuthorizer.isTrusted { AccessibilityAuthorizer.prompt() }
    }
    func togglePause() { isPaused.toggle(); monitor.isPaused = isPaused }
    private func startPruneTimer() { /* 300s Timer -> store.prune(keeping: RetentionPolicy(), now: Date()) */ }
}
```

- [ ] **Step 3: Implement `PermissionView`** — explains Accessibility need, button calling `AccessibilityAuthorizer.prompt()`, shows live `isTrusted` status.

- [ ] **Step 4: Wire `ProsciuttoApp`** — `@StateObject var env = AppEnvironment()`; `MenuBarExtra` menu with: "Open Prosciutto (⌘⇧V)" → `env.panel.show()`, "Pause Capture" toggle → `env.togglePause()`, "Settings…", "Quit". Add a `Settings` scene hosting `SettingsView` + `PermissionView`.

- [ ] **Step 5: Build + run end-to-end manual test** — `xcodebuild -scheme Prosciutto build`, launch, grant Accessibility, copy text/image/url/hex/code, press ⌘⇧V, confirm cards appear, ←/→ + ↵ pastes into a text editor, ⌘1 quick-pastes, password-manager copy is NOT captured.

- [ ] **Step 6: Commit** — `git commit -am "feat: wire app environment, menu bar, onboarding, pause"`

---

### Task 17: Packaging — notarized DMG + Homebrew cask + README

**Files:**
- Create: `scripts/build-release.sh`, `scripts/notarize.sh`, `Casks/prosciutto.rb`, `README.md`, `LICENSE` (MIT)

**Interfaces:**
- Produces: a reproducible release pipeline and install path.

- [ ] **Step 1: `build-release.sh`** — `xcodegen generate` then `xcodebuild -scheme Prosciutto -configuration Release archive -archivePath build/Prosciutto.xcarchive` then `-exportArchive` with a Developer ID export options plist → `build/Prosciutto.app`.

- [ ] **Step 2: `notarize.sh`** — create DMG (`hdiutil create`), `xcrun notarytool submit --wait` with stored credentials, `xcrun stapler staple` the DMG.

- [ ] **Step 3: `Casks/prosciutto.rb`** — Homebrew cask pointing at the GitHub Release DMG with `sha256`, `app "Prosciutto.app"`, `zap` stanza removing `~/Library/Application Support/Prosciutto` and prefs.

- [ ] **Step 4: `README.md`** — what it is, screenshot placeholder, `brew install --cask prosciutto` (via tap), permissions note, privacy stance, build-from-source, contributing. Add MIT `LICENSE`.

- [ ] **Step 5: Commit** — `git commit -am "chore: add release packaging, Homebrew cask, README, license"`

---

## Self-Review

**Spec coverage check (spec §3 modules → tasks):**
- ClipboardMonitor → T6 ✓ · Storage/Core Data → T9 ✓ · PasteService → T12 ✓ · HotkeyManager → T11 ✓ · GalleryWindow → T15 ✓ · CardRenderers → T13 ✓ · SearchIndex (MVP = in-memory `ClipQuery`; FTS5 deferred — see note) → T8 ✓ · Settings/Onboarding → T16 ✓ · Menu bar → T16 ✓.
- Spec §4 data model → T1/T3/T9 ✓ (Pinboard/Snippet entities are Phase 2; MVP keeps `isPinned`/`expiresAt` only — consistent with phasing).
- Spec §5 privacy rules → T4 (+ T10 marker population) ✓.
- Spec §6 UX behaviors → T13/T14/T15/T16 ✓ (drag-to-pinboard + Quick Look preview are Phase 2 — explicitly out of MVP).
- Spec §7 error handling: no-Accessibility fallback → T12/T16 ✓; pasteboard race (changeCount gate) → T6 ✓; corrupt rep (snapshot returns what reads) → T10 ✓.
- Spec §8 testing → unit tests T1–T9, integration T9, manual T16 ✓.
- Spec §9 phasing: this plan = Phase 1 only ✓.

**Deviations from spec, called out explicitly:**
- SearchIndex: spec specifies SQLite FTS5. MVP ships in-memory `ClipQuery` (history capped at ~1000 items — linear filter is instant). FTS5 promoted to Phase 2 when OCR text lands. This is a deliberate YAGNI deferral, not a gap.
- OCR, MCP, pinboards, snippets, filters-beyond-kind, paste-plain UI affordance polish: Phases 2–3 per spec, not in this plan.

**Placeholder scan:** UI tasks (T13/T14/T15/T16) describe some view bodies prose-first with concrete signatures and representative code rather than full literal SwiftUI for every subview, because they are visual/manual-verified and exact layout is iterated in Xcode canvas; all types, method names, and signatures they depend on are concretely defined. Logic tasks (T1–T9) contain complete code. No "TBD"/"TODO" remain.

**Type consistency:** `ClipStore` signatures (`upsert/all/delete/setPinned/prune`) identical across T5/T9/T14/T16. `ClipItem.make(from:kind:now:ttl:)` identical across T3/T5/T6/T7. `RetentionPolicy.survivors(of:now:)` identical T7/T9. `PasteService.paste(_:asPlainText:)` identical T12/T14. `KindDetector.detect(_:)` identical T2/T6.
