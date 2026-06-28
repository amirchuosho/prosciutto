# Settings Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Maccy-grade preferences — launch-at-login, configurable hotkeys, app-ignore UI, save-by-type, optional max-item-size, fuzzy search — and make all retention limits disable-able.

**Architecture:** Pure capture/search logic lives in `ProsciuttoKit` (unit-tested): `CaptureFilter` (type+size gate), `RetentionPolicy` (now supports "unlimited"), `FuzzyMatch` + `ClipQuery.fuzzy`. The app layer adds `Preferences` keys, a `KeyCombo`/`KeyRecorderField` for rebinding, an `SMAppService` `LoginItem`, an expanded 6-tab `SettingsView`, and `AppEnvironment.applyCaptureSettings()` that pushes live settings into the monitor.

**Tech Stack:** Swift, SwiftUI + AppKit, Core Data, Carbon hotkeys, `ServiceManagement` (SMAppService), XcodeGen, XCTest.

## Global Constraints

- macOS deployment target: **macOS 14** (SMAppService available).
- Spec: `docs/superpowers/specs/2026-06-28-settings-overhaul-design.md`.
- Sentinels: `maxItems = 0` → Unlimited; `maxAgeDays = 0` → Never expire; `maxItemSizeBytes = 0` → no size limit.
- Save-by-type mapping: `.image`→Images, `.file`→Files, everything else (`.text/.rtf/.link/.color/.code`)→Text.
- Byte size measured on the **stored** payload: `item.imageData?.count ?? item.textPlain?.utf8.count ?? 0`.
- `.xcodeproj` is generated — run `xcodegen generate` after adding files; never hand-edit the project.
- Kit tests: `swift test`. App build: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build`. Deploy to `/Applications` to test live (the running app is the deployed copy, not `build/`).
- Repo is on `main`; create a feature branch before committing.

---

### Task 1: RetentionPolicy — Unlimited support

**Files:**
- Modify: `Sources/ProsciuttoKit/Retention/RetentionPolicy.swift`
- Test: `Tests/ProsciuttoKitTests/RetentionPolicyTests.swift`

**Interfaces:**
- Produces: `RetentionPolicy.survivors(of:now:)` treating `maxItems <= 0` and `maxAge <= 0` as unlimited (unchanged signature).

- [ ] **Step 1: Add failing tests**

Append to `Tests/ProsciuttoKitTests/RetentionPolicyTests.swift` inside the class:

```swift
    func testMaxAgeZeroNeverExpires() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 100, maxAge: 0)
        let items = [item("ancient", age: 9_999_999, pinned: false, now: now)]
        XCTAssertEqual(p.survivors(of: items, now: now).count, 1)
    }
    func testMaxItemsZeroKeepsAll() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = RetentionPolicy(maxItems: 0, maxAge: 999_999)
        let items = (0..<50).map { item("i\($0)", age: TimeInterval($0), pinned: false, now: now) }
        XCTAssertEqual(p.survivors(of: items, now: now).count, 50)
    }
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test --filter RetentionPolicyTests`
Expected: FAIL — `testMaxItemsZeroKeepsAll` keeps 0 items (prefix(0)).

- [ ] **Step 3: Implement unlimited handling**

Replace the body of `survivors(of:now:)` in `RetentionPolicy.swift`:

```swift
    public func survivors(of items: [ClipItem], now: Date) -> [ClipItem] {
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }
        if maxAge > 0 {
            unpinned = unpinned.filter { now.timeIntervalSince($0.lastUsedAt) <= maxAge }
        }
        unpinned.sort { $0.lastUsedAt > $1.lastUsedAt }
        if maxItems > 0, unpinned.count > maxItems {
            unpinned = Array(unpinned.prefix(maxItems))
        }
        return pinned + unpinned
    }
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter RetentionPolicyTests`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add Sources/ProsciuttoKit/Retention/RetentionPolicy.swift Tests/ProsciuttoKitTests/RetentionPolicyTests.swift
git commit -m "feat(retention): treat 0 limits as unlimited (never-expire / keep-all)"
```

---

### Task 2: CaptureFilter — type + size gate

**Files:**
- Create: `Sources/ProsciuttoKit/Capture/CaptureFilter.swift`
- Test: `Tests/ProsciuttoKitTests/CaptureFilterTests.swift`

**Interfaces:**
- Produces:
  - `struct CaptureFilter { var enabledKinds: Set<ClipKind>; var maxBytes: Int }`
  - `CaptureFilter.shouldCapture(kind: ClipKind, byteSize: Int) -> Bool`
  - `static CaptureFilter.from(saveText: Bool, saveImages: Bool, saveFiles: Bool, maxBytes: Int) -> CaptureFilter`
  - `static let CaptureFilter.unrestricted: CaptureFilter`
  - `static let CaptureFilter.allKinds: Set<ClipKind>`

- [ ] **Step 1: Write failing tests**

Create `Tests/ProsciuttoKitTests/CaptureFilterTests.swift`:

```swift
import XCTest
@testable import ProsciuttoKit

final class CaptureFilterTests: XCTestCase {
    func testUnrestrictedAllowsEverything() {
        let f = CaptureFilter.unrestricted
        XCTAssertTrue(f.shouldCapture(kind: .image, byteSize: 99_000_000))
        XCTAssertTrue(f.shouldCapture(kind: .text, byteSize: 0))
    }
    func testTypeDisabledRejected() {
        let f = CaptureFilter.from(saveText: true, saveImages: false, saveFiles: true, maxBytes: 0)
        XCTAssertFalse(f.shouldCapture(kind: .image, byteSize: 10))
        XCTAssertTrue(f.shouldCapture(kind: .code, byteSize: 10))   // code maps to Text
        XCTAssertTrue(f.shouldCapture(kind: .file, byteSize: 10))
    }
    func testSizeCap() {
        let f = CaptureFilter.from(saveText: true, saveImages: true, saveFiles: true, maxBytes: 1000)
        XCTAssertTrue(f.shouldCapture(kind: .image, byteSize: 1000))
        XCTAssertFalse(f.shouldCapture(kind: .image, byteSize: 1001))
    }
    func testZeroMaxBytesMeansNoLimit() {
        let f = CaptureFilter.from(saveText: true, saveImages: true, saveFiles: true, maxBytes: 0)
        XCTAssertTrue(f.shouldCapture(kind: .text, byteSize: 5_000_000))
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter CaptureFilterTests`
Expected: FAIL — `CaptureFilter` undefined.

- [ ] **Step 3: Implement CaptureFilter**

Create `Sources/ProsciuttoKit/Capture/CaptureFilter.swift`:

```swift
import Foundation

/// Decides whether a captured clip should be stored, based on the save-by-type
/// toggles and an optional max stored-byte size. `maxBytes == 0` means no limit.
public struct CaptureFilter: Sendable {
    public var enabledKinds: Set<ClipKind>
    public var maxBytes: Int

    public init(enabledKinds: Set<ClipKind> = CaptureFilter.allKinds, maxBytes: Int = 0) {
        self.enabledKinds = enabledKinds
        self.maxBytes = maxBytes
    }

    public func shouldCapture(kind: ClipKind, byteSize: Int) -> Bool {
        guard enabledKinds.contains(kind) else { return false }
        if maxBytes > 0, byteSize > maxBytes { return false }
        return true
    }

    public static let allKinds: Set<ClipKind> = [.text, .rtf, .link, .color, .code, .image, .file]

    public static let unrestricted = CaptureFilter()

    /// Build the enabled-kinds set from the three save-by-type toggles.
    public static func from(saveText: Bool, saveImages: Bool, saveFiles: Bool, maxBytes: Int) -> CaptureFilter {
        var kinds = Set<ClipKind>()
        if saveText { kinds.formUnion([.text, .rtf, .link, .color, .code]) }
        if saveImages { kinds.insert(.image) }
        if saveFiles { kinds.insert(.file) }
        return CaptureFilter(enabledKinds: kinds, maxBytes: maxBytes)
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter CaptureFilterTests`
Expected: PASS (4).

- [ ] **Step 5: Commit**

```bash
git add Sources/ProsciuttoKit/Capture/CaptureFilter.swift Tests/ProsciuttoKitTests/CaptureFilterTests.swift
git commit -m "feat(capture): add CaptureFilter (save-by-type + max item size)"
```

---

### Task 3: ClipboardMonitor — apply CaptureFilter

**Files:**
- Modify: `Sources/ProsciuttoKit/Capture/ClipboardMonitor.swift`
- Test: `Tests/ProsciuttoKitTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `CaptureFilter` (Task 2).
- Produces: `ClipboardMonitor.captureFilter: CaptureFilter` (mutable `var`); `exclusion` becomes a mutable `var`; new init param `captureFilter: CaptureFilter = .unrestricted`.

- [ ] **Step 1: Write failing tests**

Append to `Tests/ProsciuttoKitTests/ClipboardMonitorTests.swift` inside the class:

```swift
    func testSkipsDisabledType() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60,
            captureFilter: CaptureFilter.from(saveText: false, saveImages: true, saveFiles: true, maxBytes: 0))
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "some text")
        try await monitor.poll()
        XCTAssertEqual(try await store.all().count, 0)
    }
    func testSkipsOversized() async throws {
        let reader = FakeReader()
        let store = InMemoryClipStore()
        let monitor = ClipboardMonitor(reader: reader, store: store,
            exclusion: ExclusionPolicy(blockedBundleIDs: []),
            clock: FixedClock(t: .init(timeIntervalSince1970: 0)), ttl: 60,
            captureFilter: CaptureFilter(enabledKinds: CaptureFilter.allKinds, maxBytes: 4))
        reader.changeCount = 1
        reader.next = PasteboardSnapshot(plainText: "way too long")
        try await monitor.poll()
        XCTAssertEqual(try await store.all().count, 0)
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter ClipboardMonitorTests`
Expected: FAIL — `captureFilter:` arg undefined.

- [ ] **Step 3: Implement**

In `ClipboardMonitor.swift`, change the stored properties (make `exclusion` a `var`, add `captureFilter`):

```swift
    private let reader: PasteboardReader
    private let store: ClipStore
    public var exclusion: ExclusionPolicy
    public var captureFilter: CaptureFilter
    private let clock: Clock
```

Update the initializer signature + body:

```swift
    public init(reader: PasteboardReader, store: ClipStore, exclusion: ExclusionPolicy,
                clock: Clock, ttl: TimeInterval, captureFilter: CaptureFilter = .unrestricted) {
        self.reader = reader
        self.store = store
        self.exclusion = exclusion
        self.captureFilter = captureFilter
        self.clock = clock
        self.ttl = ttl
        self.lastChangeCount = reader.changeCount
    }
```

Update `poll()` to gate on the filter after building the item:

```swift
    public func poll() async throws {
        guard !isPaused else { return }
        let current = reader.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let snap = reader.snapshot(), exclusion.shouldCapture(snap),
              let kind = KindDetector.detect(snap) else { return }
        let item = ClipItem.make(from: snap, kind: kind, now: clock.now(), ttl: ttl)
        let byteSize = item.imageData?.count ?? item.textPlain?.utf8.count ?? 0
        guard captureFilter.shouldCapture(kind: kind, byteSize: byteSize) else { return }
        try await store.upsert(item)
        onCapture?()
    }
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test`
Expected: PASS (all kit tests, including the 3 prior ClipboardMonitor tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ProsciuttoKit/Capture/ClipboardMonitor.swift Tests/ProsciuttoKitTests/ClipboardMonitorTests.swift
git commit -m "feat(capture): gate ClipboardMonitor on CaptureFilter (type + size)"
```

---

### Task 4: FuzzyMatch scorer

**Files:**
- Create: `Sources/ProsciuttoKit/Search/FuzzyMatch.swift`
- Test: `Tests/ProsciuttoKitTests/FuzzyMatchTests.swift`

**Interfaces:**
- Produces: `FuzzyMatch.score(_ needle: String, _ haystack: String) -> Int?` (nil = no subsequence match; higher = better).

- [ ] **Step 1: Write failing tests**

Create `Tests/ProsciuttoKitTests/FuzzyMatchTests.swift`:

```swift
import XCTest
@testable import ProsciuttoKit

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatch.score("prsc", "prosciutto"))
        XCTAssertNotNil(FuzzyMatch.score("clip", "Clipboard Manager"))
    }
    func testNonSubsequenceFails() {
        XCTAssertNil(FuzzyMatch.score("xyz", "prosciutto"))
        XCTAssertNil(FuzzyMatch.score("ppp", "prosciutto"))
    }
    func testEmptyNeedleScoresZero() {
        XCTAssertEqual(FuzzyMatch.score("", "anything"), 0)
    }
    func testContiguousScoresHigher() {
        let contiguous = FuzzyMatch.score("pros", "prosciutto")!
        let scattered = FuzzyMatch.score("psct", "prosciutto")!
        XCTAssertGreaterThan(contiguous, scattered)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter FuzzyMatchTests`
Expected: FAIL — `FuzzyMatch` undefined.

- [ ] **Step 3: Implement**

Create `Sources/ProsciuttoKit/Search/FuzzyMatch.swift`:

```swift
import Foundation

public enum FuzzyMatch {
    /// Case-insensitive subsequence match. Returns nil when `needle` is not a
    /// subsequence of `haystack`; otherwise a score where contiguous runs and
    /// early matches score higher.
    public static func score(_ needle: String, _ haystack: String) -> Int? {
        let n = Array(needle.lowercased())
        guard !n.isEmpty else { return 0 }
        let h = Array(haystack.lowercased())
        var ni = 0, score = 0, lastMatch = -2
        for (hi, ch) in h.enumerated() where ni < n.count {
            if ch == n[ni] {
                score += (hi == lastMatch + 1) ? 3 : 1   // contiguity bonus
                if hi < 8 { score += 1 }                  // early-match bonus
                lastMatch = hi
                ni += 1
            }
        }
        return ni == n.count ? score : nil
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter FuzzyMatchTests`
Expected: PASS (4).

- [ ] **Step 5: Commit**

```bash
git add Sources/ProsciuttoKit/Search/FuzzyMatch.swift Tests/ProsciuttoKitTests/FuzzyMatchTests.swift
git commit -m "feat(search): add FuzzyMatch subsequence scorer"
```

---

### Task 5: ClipQuery — fuzzy mode

**Files:**
- Modify: `Sources/ProsciuttoKit/Search/ClipQuery.swift`
- Test: `Tests/ProsciuttoKitTests/ClipQueryTests.swift`

**Interfaces:**
- Consumes: `FuzzyMatch.score` (Task 4).
- Produces: `ClipQuery.fuzzy: Bool` (default false). When true + non-empty `text`, filters by fuzzy match and ranks by score descending.

- [ ] **Step 1: Write failing tests**

Append to `Tests/ProsciuttoKitTests/ClipQueryTests.swift` inside the class (helper `mk` for a text item shown below — if the file already has an item helper, reuse it and skip `mk`):

```swift
    private func mk(_ t: String) -> ClipItem {
        ClipItem.make(from: PasteboardSnapshot(plainText: t), kind: .text,
                      now: Date(timeIntervalSince1970: 0), ttl: 60)
    }
    func testFuzzyFiltersSubsequence() {
        var q = ClipQuery(); q.text = "prsc"; q.fuzzy = true
        let out = q.apply(to: [mk("prosciutto"), mk("banana")]).map(\.textPlain)
        XCTAssertEqual(out, ["prosciutto"])
    }
    func testFuzzyRanksByScore() {
        var q = ClipQuery(); q.text = "pro"; q.fuzzy = true
        let out = q.apply(to: [mk("a p r o"), mk("prologue")]).map(\.textPlain)
        XCTAssertEqual(out.first, "prologue")   // contiguous beats scattered
    }
    func testNonFuzzyStillSubstring() {
        var q = ClipQuery(); q.text = "ana"; q.fuzzy = false
        let out = q.apply(to: [mk("banana"), mk("prosciutto")]).map(\.textPlain)
        XCTAssertEqual(out, ["banana"])
    }
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter ClipQueryTests`
Expected: FAIL — `fuzzy` member undefined.

- [ ] **Step 3: Implement**

Replace the contents of `ClipQuery.swift`:

```swift
import Foundation

public struct ClipQuery: Sendable {
    public var text: String = ""
    public var kinds: Set<ClipKind> = []
    public var sourceAppBundleID: String? = nil
    public var fuzzy: Bool = false
    public init() {}

    public func apply(to items: [ClipItem]) -> [ClipItem] {
        let prefiltered = items.filter { item in
            if !kinds.isEmpty && !kinds.contains(item.kind) { return false }
            if let app = sourceAppBundleID, item.sourceAppBundleID != app { return false }
            return true
        }
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return prefiltered }

        if fuzzy {
            let scored = prefiltered.compactMap { item -> (ClipItem, Int)? in
                let hay = [item.title, item.textPlain].compactMap { $0 }.joined(separator: "\n")
                guard let s = FuzzyMatch.score(needle, hay) else { return nil }
                return (item, s)
            }
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        } else {
            let lowered = needle.lowercased()
            return prefiltered.filter { item in
                let hay = [item.title, item.textPlain].compactMap { $0?.lowercased() }.joined(separator: "\n")
                return hay.contains(lowered)
            }
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test`
Expected: PASS (all kit tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ProsciuttoKit/Search/ClipQuery.swift Tests/ProsciuttoKitTests/ClipQueryTests.swift
git commit -m "feat(search): add fuzzy mode to ClipQuery (rank by score)"
```

---

### Task 6: Preferences — new keys

**Files:**
- Modify: `App/Prosciutto/Settings/Preferences.swift`

**Interfaces:**
- Produces on `Preferences.shared`: `openHotkeyKeyCode: Int`, `openHotkeyModifiers: Int`, `plainPasteKeyCode: Int`, `plainPasteModifiers: Int`, `saveText/saveImages/saveFiles: Bool`, `maxItemSizeBytes: Int`, `useFuzzySearch: Bool`, and `captureFilter: CaptureFilter` convenience.

- [ ] **Step 1: Add the keys + accessors**

In `Preferences.swift`, add to the `Keys` enum:

```swift
        static let openKeyCode = "hotkey.open.keyCode"
        static let openModifiers = "hotkey.open.modifiers"
        static let plainKeyCode = "hotkey.plain.keyCode"
        static let plainModifiers = "hotkey.plain.modifiers"
        static let saveText = "capture.saveText"
        static let saveImages = "capture.saveImages"
        static let saveFiles = "capture.saveFiles"
        static let maxItemSizeBytes = "capture.maxItemSizeBytes"
        static let useFuzzySearch = "search.useFuzzy"
```

Add these accessors to the `Preferences` class (defaults: open ⌘⇧V = keyCode 9 / Cocoa cmd+shift raw `1_310_720 + 131_072`… use the raw computed at runtime instead — store via KeyCombo; see note). Use plain Int defaults via `NSEvent.ModifierFlags` raw values referenced from the app:

```swift
    // Hotkeys are stored as keyCode + Cocoa NSEvent.ModifierFlags rawValue.
    // Defaults: open = ⌘⇧V, plain-paste = ⌘⌥V (kVK_ANSI_V == 9).
    var openHotkeyKeyCode: Int {
        get { defaults.object(forKey: Keys.openKeyCode) as? Int ?? 9 }
        set { defaults.set(newValue, forKey: Keys.openKeyCode) }
    }
    var openHotkeyModifiers: Int {
        get { defaults.object(forKey: Keys.openModifiers) as? Int ?? Preferences.defaultCmdShift }
        set { defaults.set(newValue, forKey: Keys.openModifiers) }
    }
    var plainPasteKeyCode: Int {
        get { defaults.object(forKey: Keys.plainKeyCode) as? Int ?? 9 }
        set { defaults.set(newValue, forKey: Keys.plainKeyCode) }
    }
    var plainPasteModifiers: Int {
        get { defaults.object(forKey: Keys.plainModifiers) as? Int ?? Preferences.defaultCmdOption }
        set { defaults.set(newValue, forKey: Keys.plainModifiers) }
    }
    var saveText: Bool {
        get { defaults.object(forKey: Keys.saveText) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveText) }
    }
    var saveImages: Bool {
        get { defaults.object(forKey: Keys.saveImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveImages) }
    }
    var saveFiles: Bool {
        get { defaults.object(forKey: Keys.saveFiles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveFiles) }
    }
    var maxItemSizeBytes: Int {
        get { defaults.object(forKey: Keys.maxItemSizeBytes) as? Int ?? 0 }   // 0 = no limit
        set { defaults.set(newValue, forKey: Keys.maxItemSizeBytes) }
    }
    var useFuzzySearch: Bool {
        get { defaults.bool(forKey: Keys.useFuzzySearch) }                     // default false
        set { defaults.set(newValue, forKey: Keys.useFuzzySearch) }
    }

    var captureFilter: CaptureFilter {
        CaptureFilter.from(saveText: saveText, saveImages: saveImages,
                           saveFiles: saveFiles, maxBytes: maxItemSizeBytes)
    }

    // NSEvent.ModifierFlags rawValues (avoids importing AppKit here):
    // .command = 1<<20 = 1_048_576, .shift = 1<<17 = 131_072, .option = 1<<19 = 524_288
    static let defaultCmdShift = 1_048_576 | 131_072
    static let defaultCmdOption = 1_048_576 | 524_288
```

Add `import ProsciuttoKit` if not already present (it is). `CaptureFilter` comes from ProsciuttoKit.

- [ ] **Step 2: Build the kit + app to type-check**

Run: `swift build`
Then: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Prosciutto/Settings/Preferences.swift
git commit -m "feat(prefs): add hotkey, save-by-type, max-size, fuzzy keys"
```

---

### Task 7: KeyCombo + Cocoa→Carbon conversion

**Files:**
- Create: `App/Prosciutto/Hotkey/KeyCombo.swift`
- Test: `App/ProsciuttoTests/KeyComboTests.swift`
- Modify: `Project.yml` is unaffected (files auto-included by XcodeGen globs); run `xcodegen generate` after creating files.

**Interfaces:**
- Produces:
  - `struct KeyCombo: Equatable { var keyCode: UInt16; var modifiers: NSEvent.ModifierFlags }`
  - `KeyCombo.carbonModifiers: UInt32`
  - `KeyCombo.displayString: String`
  - `KeyCombo(keyCode:modifiers:)`; `KeyCombo(storedKeyCode: Int, storedModifiers: Int)`
  - `static KeyCombo.keyName(_ code: UInt16) -> String`

- [ ] **Step 1: Write failing test**

Create `App/ProsciuttoTests/KeyComboTests.swift`:

```swift
import XCTest
import Carbon.HIToolbox
@testable import Prosciutto

final class KeyComboTests: XCTestCase {
    func testCarbonModifiersForCommandShift() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | shiftKey))
    }
    func testCarbonModifiersForCommandOption() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | optionKey))
    }
    func testDisplayStringOrdersGlyphs() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(c.displayString, "⇧⌘V")
    }
    func testRoundTripStored() {
        let c = KeyCombo(keyCode: 9, modifiers: [.command, .option])
        let r = KeyCombo(storedKeyCode: Int(c.keyCode), storedModifiers: Int(c.modifiers.rawValue))
        XCTAssertEqual(c, r)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build test 2>&1 | grep -E "error:|KeyCombo" | head`
Expected: compile failure — `KeyCombo` undefined.

- [ ] **Step 3: Implement KeyCombo**

Create `App/Prosciutto/Hotkey/KeyCombo.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code plus Cocoa modifier flags. Persisted
/// as two Ints; converts to a Carbon modifier mask for global hotkey registration
/// and to a glyph string for display.
struct KeyCombo: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    init(storedKeyCode: Int, storedModifiers: Int) {
        self.init(keyCode: UInt16(storedKeyCode),
                  modifiers: NSEvent.ModifierFlags(rawValue: UInt(storedModifiers)))
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift)   { m |= UInt32(shiftKey) }
        if modifiers.contains(.option)  { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Glyphs in the conventional macOS order: ⌃⌥⇧⌘ then the key.
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyCombo.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        if let named = specialKeys[code] { return named }
        // Letters / digits / punctuation via the current keyboard layout.
        if let s = charForKeyCode(code)?.uppercased(), !s.isEmpty { return s }
        return "key\(code)"
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
    ]

    private static func charForKeyCode(_ code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let result = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
```

- [ ] **Step 4: Regenerate project + run test**

Run: `xcodegen generate`
Run: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: KeyComboTests pass; `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App/Prosciutto/Hotkey/KeyCombo.swift App/ProsciuttoTests/KeyComboTests.swift
git commit -m "feat(hotkey): add KeyCombo with Carbon conversion + glyph display"
```

---

### Task 8: LoginItem (launch at login)

**Files:**
- Create: `App/Prosciutto/Settings/LoginItem.swift`

**Interfaces:**
- Produces: `LoginItem.isEnabled: Bool`; `LoginItem.setEnabled(_ on: Bool) throws`.

- [ ] **Step 1: Implement**

Create `App/Prosciutto/Settings/LoginItem.swift`:

```swift
import ServiceManagement

/// Launch-at-login backed by SMAppService. The OS is the source of truth, so the
/// settings toggle reads `isEnabled` and writes via `setEnabled`.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Prosciutto/Settings/LoginItem.swift
git commit -m "feat(settings): add LoginItem (SMAppService launch-at-login)"
```

---

### Task 9: KeyRecorderField

**Files:**
- Create: `App/Prosciutto/Settings/KeyRecorderField.swift`

**Interfaces:**
- Consumes: `KeyCombo` (Task 7).
- Produces: `KeyRecorderField(combo: Binding<KeyCombo>)` — a SwiftUI view; clicking it records the next modifier+key chord.

- [ ] **Step 1: Implement the recorder**

Create `App/Prosciutto/Settings/KeyRecorderField.swift`:

```swift
import SwiftUI
import AppKit

/// A click-to-record shortcut field. Requires at least one modifier (so plain
/// typing can't be captured). Esc cancels; ⌫ clears to ⌘⇧V-less empty (keeps the
/// previous value). Reports the recorded chord via the binding.
struct KeyRecorderField: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let v = RecorderButton()
        v.onRecord = { combo = $0 }
        v.combo = combo
        return v
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.combo = combo
    }

    final class RecorderButton: NSButton {
        var onRecord: ((KeyCombo) -> Void)?
        var combo = KeyCombo(keyCode: 9, modifiers: [.command, .shift]) { didSet { refresh() } }
        private var recording = false { didSet { refresh() } }
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
            refresh()
        }
        required init?(coder: NSCoder) { fatalError() }

        private func refresh() {
            title = recording ? "Type shortcut…  (esc to cancel)" : combo.displayString
        }

        @objc private func toggleRecording() {
            recording ? stop() : start()
        }

        private func start() {
            recording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
                return nil   // swallow while recording
            }
        }

        private func stop() {
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == UInt16(53) { stop(); return }   // esc cancels
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.option)
                  || mods.contains(.control) else { return }    // need a modifier
            let new = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            combo = new
            onRecord?(new)
            stop()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/Prosciutto/Settings/KeyRecorderField.swift
git commit -m "feat(settings): add KeyRecorderField shortcut recorder"
```

---

### Task 10: AppEnvironment wiring (live settings, hotkey reload, plain-paste, fuzzy)

**Files:**
- Modify: `App/Prosciutto/AppEnvironment.swift`
- Modify: `App/Prosciutto/Hotkey/HotkeyManager.swift`
- Modify: `App/Prosciutto/UI/GalleryViewModel.swift`

**Interfaces:**
- Consumes: `Preferences.captureFilter`, `Preferences.open*`, `Preferences.plainPaste*`, `Preferences.useFuzzySearch`, `KeyCombo`, `Notification.Name.prosciuttoSettingsChanged`.
- Produces: `AppEnvironment.applyCaptureSettings()`, `AppEnvironment.reloadHotkey()`; `Notification.Name.prosciuttoSettingsChanged`; `GalleryViewModel` honours `Preferences.useFuzzySearch`.

- [ ] **Step 1: Add the settings-changed notification name**

In `AppEnvironment.swift` (top level, near other extensions), add:

```swift
extension Notification.Name {
    static let prosciuttoSettingsChanged = Notification.Name("prosciutto.settingsChanged")
}
```

- [ ] **Step 2: Build the monitor with the live filter + add apply/reload**

In `AppEnvironment.init()`, change the monitor construction to pass the filter:

```swift
        monitor = ClipboardMonitor(reader: reader, store: store,
                                   exclusion: ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs),
                                   clock: SystemClock(), ttl: ttl,
                                   captureFilter: Preferences.shared.captureFilter)
```

Replace `hotkey.register()` in `init()` with `reloadHotkey()` (defined below). After `installKeyMonitor()`, add a settings observer:

```swift
        NotificationCenter.default.addObserver(forName: .prosciuttoSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyCaptureSettings()
                self?.reloadHotkey()
                self?.vm.query.fuzzy = Preferences.shared.useFuzzySearch
                await self?.vm.reload()
            }
        }
```

Add these methods to `AppEnvironment`:

```swift
    /// Rebuild capture policy from Preferences and push it into the live monitor.
    func applyCaptureSettings() {
        monitor.exclusion = ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs)
        monitor.captureFilter = Preferences.shared.captureFilter
    }

    /// (Re)register the global open-gallery hotkey from Preferences.
    func reloadHotkey() {
        let combo = KeyCombo(storedKeyCode: Preferences.shared.openHotkeyKeyCode,
                             storedModifiers: Preferences.shared.openHotkeyModifiers)
        hotkey.unregister()
        hotkey.onTrigger = { [weak self] in self?.toggleGallery() }
        hotkey.register(keyCode: UInt32(combo.keyCode), modifiers: combo.carbonModifiers)
    }
```

Set the initial fuzzy flag once in `init()` after `vm` is created:

```swift
        vm.query.fuzzy = Preferences.shared.useFuzzySearch
```

- [ ] **Step 3: Make HotkeyManager re-registrable**

In `HotkeyManager.register`, guard against a leaked handler when re-registering — at the top of `register(...)` add:

```swift
        unregister()
```

(`unregister()` already nils `ref`/`handler`; this makes repeated `register` calls safe.)

- [ ] **Step 4: Honour the configurable plain-paste combo in the key monitor**

In `AppEnvironment.installKeyMonitor()`, replace the hardcoded ⌘⌥V branch:

```swift
                if mods == [.command, .option],
                   event.charactersIgnoringModifiers?.lowercased() == "v" {
                    self.vm.pasteSelected(asPlainText: true); return nil  // ⌘⌥V plain paste
                }
```

with a comparison against the stored combo:

```swift
                let plain = KeyCombo(storedKeyCode: Preferences.shared.plainPasteKeyCode,
                                     storedModifiers: Preferences.shared.plainPasteModifiers)
                if event.keyCode == plain.keyCode,
                   mods == plain.modifiers.intersection([.command, .option, .control, .shift]) {
                    self.vm.pasteSelected(asPlainText: true); return nil  // plain paste
                }
```

- [ ] **Step 5: Build, deploy, smoke-test**

Run: `xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`.
Run: `pkill -x Prosciutto; sleep 1; rm -rf /Applications/Prosciutto.app; cp -R build/Build/Products/Debug/Prosciutto.app /Applications/Prosciutto.app; open /Applications/Prosciutto.app`
Verify: ⌘⇧V still opens the gallery; copy a text item — still captured.

- [ ] **Step 6: Commit**

```bash
git add App/Prosciutto/AppEnvironment.swift App/Prosciutto/Hotkey/HotkeyManager.swift App/Prosciutto/UI/GalleryViewModel.swift
git commit -m "feat(app): live capture settings, hotkey reload, configurable plain-paste, fuzzy wiring"
```

Note: `GalleryViewModel.swift` is listed because `vm.query` must be settable — it already is (`@Published var query`). If the fuzzy flag needs a re-filter on its own, no code change is required beyond setting `vm.query.fuzzy`; include the file in the commit only if you touched it.

---

### Task 11: SettingsView — six tabs

**Files:**
- Modify: `App/Prosciutto/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `Preferences`, `KeyCombo`, `KeyRecorderField`, `LoginItem`, `Notification.Name.prosciuttoSettingsChanged`.
- Produces: General / Hotkeys / History / Privacy / Appearance / Permissions tabs. (Privacy body is filled in Task 12; here it is a placeholder `Text` replaced next task.)

- [ ] **Step 1: Rewrite SettingsView**

Replace `App/Prosciutto/Settings/SettingsView.swift` with:

```swift
import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager

    // General
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var pasteAutomatically = Preferences.shared.pasteAutomatically
    @State private var soundEnabled = Preferences.shared.captureSoundEnabled
    @State private var soundName = Preferences.shared.captureSoundName
    @State private var useFuzzy = Preferences.shared.useFuzzySearch
    // Hotkeys
    @State private var openCombo = KeyCombo(storedKeyCode: Preferences.shared.openHotkeyKeyCode,
                                            storedModifiers: Preferences.shared.openHotkeyModifiers)
    @State private var plainCombo = KeyCombo(storedKeyCode: Preferences.shared.plainPasteKeyCode,
                                             storedModifiers: Preferences.shared.plainPasteModifiers)
    // History
    @State private var limitItems = Preferences.shared.maxItems > 0
    @State private var maxItems = max(Preferences.shared.maxItems, 100)
    @State private var expire = Preferences.shared.maxAgeDays > 0
    @State private var maxAgeDays = max(Preferences.shared.maxAgeDays, 1)
    @State private var limitSize = Preferences.shared.maxItemSizeBytes > 0
    @State private var maxSizeMB = max(Preferences.shared.maxItemSizeBytes / 1_000_000, 1)
    @State private var saveText = Preferences.shared.saveText
    @State private var saveImages = Preferences.shared.saveImages
    @State private var saveFiles = Preferences.shared.saveFiles

    private let systemSounds = ["Pop", "Tink", "Glass", "Bottle", "Frog", "Submarine", "Morse"]

    private func changed() { NotificationCenter.default.post(name: .prosciuttoSettingsChanged, object: nil) }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            hotkeys.tabItem { Label("Hotkeys", systemImage: "command") }
            history.tabItem { Label("History", systemImage: "clock") }
            PrivacyTab().tabItem { Label("Privacy", systemImage: "hand.raised") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            PermissionView().tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: General
    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        do { try LoginItem.setEnabled(v) }
                        catch { launchAtLogin = LoginItem.isEnabled }   // revert on failure
                    }
            }
            Section("Behavior") {
                Toggle("Paste automatically on select", isOn: $pasteAutomatically)
                    .onChange(of: pasteAutomatically) { _, v in Preferences.shared.pasteAutomatically = v }
                Toggle("Fuzzy search", isOn: $useFuzzy)
                    .onChange(of: useFuzzy) { _, v in Preferences.shared.useFuzzySearch = v; changed() }
            }
            Section("Sound") {
                Toggle("Play a sound when copying", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, v in Preferences.shared.captureSoundEnabled = v }
                Picker("Sound", selection: $soundName) {
                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!soundEnabled)
                .onChange(of: soundName) { _, v in Preferences.shared.captureSoundName = v; NSSound(named: v)?.play() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Hotkeys
    private var hotkeys: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Open gallery") {
                    KeyRecorderField(combo: $openCombo).frame(width: 180, height: 24)
                        .onChange(of: openCombo) { _, c in
                            Preferences.shared.openHotkeyKeyCode = Int(c.keyCode)
                            Preferences.shared.openHotkeyModifiers = Int(c.modifiers.rawValue)
                            changed()
                        }
                }
                LabeledContent("Paste as plain text") {
                    KeyRecorderField(combo: $plainCombo).frame(width: 180, height: 24)
                        .onChange(of: plainCombo) { _, c in
                            Preferences.shared.plainPasteKeyCode = Int(c.keyCode)
                            Preferences.shared.plainPasteModifiers = Int(c.modifiers.rawValue)
                            changed()
                        }
                }
            }
            Text("Click a field, then press the new shortcut. A modifier (⌘/⌥/⌃) is required.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: History
    private var history: some View {
        Form {
            Section("Storage") {
                Toggle("Limit number of items", isOn: $limitItems)
                    .onChange(of: limitItems) { _, v in Preferences.shared.maxItems = v ? maxItems : 0; changed() }
                if limitItems {
                    Stepper("Keep up to \(maxItems) items", value: $maxItems, in: 100...10_000, step: 100)
                        .onChange(of: maxItems) { _, v in Preferences.shared.maxItems = v; changed() }
                }
                Toggle("Expire unpinned items", isOn: $expire)
                    .onChange(of: expire) { _, v in Preferences.shared.maxAgeDays = v ? maxAgeDays : 0; changed() }
                if expire {
                    Stepper("After \(maxAgeDays) days", value: $maxAgeDays, in: 1...365)
                        .onChange(of: maxAgeDays) { _, v in Preferences.shared.maxAgeDays = v; changed() }
                }
            }
            Section("Size") {
                Toggle("Skip items larger than a size", isOn: $limitSize)
                    .onChange(of: limitSize) { _, v in Preferences.shared.maxItemSizeBytes = v ? maxSizeMB * 1_000_000 : 0; changed() }
                if limitSize {
                    Stepper("Max \(maxSizeMB) MB", value: $maxSizeMB, in: 1...500)
                        .onChange(of: maxSizeMB) { _, v in Preferences.shared.maxItemSizeBytes = v * 1_000_000; changed() }
                }
            }
            Section("Save which types") {
                Toggle("Text", isOn: $saveText).onChange(of: saveText) { _, v in Preferences.shared.saveText = v; changed() }
                Toggle("Images", isOn: $saveImages).onChange(of: saveImages) { _, v in Preferences.shared.saveImages = v; changed() }
                Toggle("Files", isOn: $saveFiles).onChange(of: saveFiles) { _, v in Preferences.shared.saveFiles = v; changed() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Appearance
    private var appearance: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $theme.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent") {
                accentSwatches
                if theme.accentTheme == .custom {
                    ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accentSwatches: some View {
        HStack(spacing: 12) {
            ForEach(AccentTheme.allCases) { t in
                let color = t.color(customHex: theme.customAccentHex)
                Button { theme.accentTheme = t } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().fill(color).frame(width: 28, height: 28)
                            if t == .custom {
                                Image(systemName: "eyedropper").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            if theme.accentTheme == t {
                                Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 34, height: 34)
                            }
                        }
                        .frame(width: 34, height: 34)
                        Text(t.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: theme.customAccentHex) ?? .pink },
            set: { theme.customAccentHex = $0.toHex() ?? theme.customAccentHex }
        )
    }
}
```

- [ ] **Step 2: Add a temporary PrivacyTab stub (replaced in Task 12)**

Create `App/Prosciutto/Settings/PrivacyTab.swift`:

```swift
import SwiftUI

struct PrivacyTab: View {
    var body: some View { Form { Text("Ignored apps — coming in next task") }.formStyle(.grouped) }
}
```

- [ ] **Step 3: Build, deploy, screenshot-verify the tabs**

Run: `xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`. Deploy, open Settings (menu-bar → Settings…), confirm 6 tabs render and toggles persist across relaunch.

- [ ] **Step 4: Commit**

```bash
git add App/Prosciutto/Settings/SettingsView.swift App/Prosciutto/Settings/PrivacyTab.swift
git commit -m "feat(settings): six-tab settings (general/hotkeys/history/privacy/appearance/permissions)"
```

---

### Task 12: Privacy tab — app-ignore list UI

**Files:**
- Modify: `App/Prosciutto/Settings/PrivacyTab.swift`

**Interfaces:**
- Consumes: `Preferences.blockedBundleIDs`, `Notification.Name.prosciuttoSettingsChanged`, `AppIconProvider`.
- Produces: a list of ignored apps with add (running-app menu) / remove.

- [ ] **Step 1: Implement the ignore-list UI**

Replace `App/Prosciutto/Settings/PrivacyTab.swift`:

```swift
import SwiftUI
import AppKit

struct PrivacyTab: View {
    @State private var blocked: [String] = Array(Preferences.shared.blockedBundleIDs).sorted()

    private func persist() {
        Preferences.shared.blockedBundleIDs = Set(blocked)
        NotificationCenter.default.post(name: .prosciuttoSettingsChanged, object: nil)
    }

    private var addableApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !blocked.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Form {
            Section("Don't capture from these apps") {
                if blocked.isEmpty {
                    Text("No ignored apps.").foregroundStyle(.secondary)
                }
                ForEach(blocked, id: \.self) { id in
                    HStack {
                        if let icon = AppIconProvider.icon(forBundleID: id) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(appName(for: id))
                        Spacer()
                        Button(role: .destructive) {
                            blocked.removeAll { $0 == id }; persist()
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Menu("Add app…") {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            if let id = app.bundleIdentifier, !blocked.contains(id) {
                                blocked.append(id); blocked.sort(); persist()
                            }
                        }
                    }
                }
                Text("Useful for password managers and other sensitive apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let name = FileManager.default.displayName(atPath: url.path) as String? {
            return name.replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
```

- [ ] **Step 2: Build, deploy, verify live blocking**

Run: `xcodegen generate && xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`. Deploy. In Settings → Privacy, Add app… → pick an app, copy from it → verify it is NOT captured (no restart). Remove it → copy again → verify it IS captured.

- [ ] **Step 3: Commit**

```bash
git add App/Prosciutto/Settings/PrivacyTab.swift
git commit -m "feat(settings): app-ignore list UI (live add/remove)"
```

---

### Task 13: More accent presets

**Files:**
- Modify: `App/Prosciutto/Theme/ThemeManager.swift`
- Modify: `App/Prosciutto/Settings/SettingsView.swift` (appearance swatches → wrapping grid)

**Interfaces:**
- Produces: 8 new `AccentTheme` cases (sunset, grape, ocean, gold, rose, lime, crimson, slate) each with a 2-stop gradient. `AccentTheme.allCases` order: presets first, `custom` last.

- [ ] **Step 1: Add the new accent cases**

In `ThemeManager.swift`, extend the `AccentTheme` enum declaration (keep `custom` last so it stays the trailing swatch):

```swift
enum AccentTheme: String, CaseIterable, Identifiable {
    case prosciutto, midnight, forest, mono, sunset, grape, ocean, gold, rose, lime, crimson, slate, custom
```

Add their labels to the `label` switch:

```swift
        case .sunset: return "Sunset"
        case .grape: return "Grape"
        case .ocean: return "Ocean"
        case .gold: return "Gold"
        case .rose: return "Rose"
        case .lime: return "Lime"
        case .crimson: return "Crimson"
        case .slate: return "Slate"
```

Add their gradients to the `colors(customHex:)` switch (before the `.custom` case):

```swift
        case .sunset:   return [Color(.sRGB, red: 1.00, green: 0.55, blue: 0.26),
                                Color(.sRGB, red: 1.00, green: 0.30, blue: 0.45)]
        case .grape:    return [Color(.sRGB, red: 0.66, green: 0.40, blue: 1.00),
                                Color(.sRGB, red: 0.50, green: 0.25, blue: 0.95)]
        case .ocean:    return [Color(.sRGB, red: 0.30, green: 0.80, blue: 0.85),
                                Color(.sRGB, red: 0.20, green: 0.55, blue: 0.85)]
        case .gold:     return [Color(.sRGB, red: 1.00, green: 0.80, blue: 0.30),
                                Color(.sRGB, red: 0.95, green: 0.60, blue: 0.15)]
        case .rose:     return [Color(.sRGB, red: 1.00, green: 0.45, blue: 0.75),
                                Color(.sRGB, red: 0.85, green: 0.30, blue: 0.60)]
        case .lime:     return [Color(.sRGB, red: 0.70, green: 0.90, blue: 0.30),
                                Color(.sRGB, red: 0.45, green: 0.78, blue: 0.25)]
        case .crimson:  return [Color(.sRGB, red: 1.00, green: 0.40, blue: 0.40),
                                Color(.sRGB, red: 0.80, green: 0.15, blue: 0.25)]
        case .slate:    return [Color(.sRGB, red: 0.55, green: 0.62, blue: 0.72),
                                Color(.sRGB, red: 0.36, green: 0.42, blue: 0.52)]
```

- [ ] **Step 2: Wrap the swatches into a grid (they no longer fit one row)**

In `SettingsView.swift`, replace the `accentSwatches` body's `HStack(spacing: 12) { ForEach… }` container with a wrapping grid. Replace:

```swift
    private var accentSwatches: some View {
        HStack(spacing: 12) {
            ForEach(AccentTheme.allCases) { t in
```

with:

```swift
    private var accentSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 6), spacing: 12) {
            ForEach(AccentTheme.allCases) { t in
```

(The closing `}` / `.padding(.vertical, 4)` stay as-is; only the container type and its arguments change. Each swatch already renders a fixed 34pt circle + label, which fits a 40pt grid cell.)

- [ ] **Step 3: Build, deploy, screenshot-verify**

Run: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`. Deploy; open Settings → Appearance; confirm all 13 swatches render in a wrapping grid, each selectable, selection ring shows, and the panel selection-glow reflects the chosen accent.

- [ ] **Step 4: Commit**

```bash
git add App/Prosciutto/Theme/ThemeManager.swift App/Prosciutto/Settings/SettingsView.swift
git commit -m "feat(theme): add 8 accent presets + wrapping swatch grid"
```

---

### Task 14: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Kit tests**

Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: all pass (≈ 51 tests: 40 prior + RetentionPolicy×2, CaptureFilter×4, ClipboardMonitor×2, FuzzyMatch×4, ClipQuery×3 — adjust count to actual).

- [ ] **Step 2: App tests**

Run: `xcodebuild -project Prosciutto.xcodeproj -scheme Prosciutto -configuration Debug -derivedDataPath build test 2>&1 | grep -E "Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **` (prior 5 + KeyComboTests×4).

- [ ] **Step 3: Manual matrix (deployed build)**

Verify each, no restart between changes:
- Launch-at-login toggle flips `SMAppService` state (check System Settings → Login Items).
- Rebind open hotkey → new combo opens the gallery; old one no longer does.
- Rebind plain-paste → new combo plain-pastes from the panel.
- History: turn off item limit + expiry → old/over-limit items are kept after a prune cycle.
- Max size on (e.g. 1 MB) → a large screenshot is not captured; off → it is.
- Save-by-type: uncheck Images → copying an image is not captured; re-check → it is.
- Fuzzy on → typing "prsc" matches "prosciutto"; off → it doesn't.
- Privacy: ignore an app → its copies are skipped live.
- Appearance: all 13 accent swatches render and apply (selection glow follows the accent).

- [ ] **Step 4: Update the vault**

Add a decision note `~/Vaults/brain/projects/prosciutto/decisions/2026-06-28-settings-overhaul.md` summarizing the shipped settings + the live-settings mechanism, and move the item to Done in `execution-plan.md`.

---

## Self-Review Notes

- **Spec coverage:** launch-at-login (T8/T11), configurable hotkeys (T6/T7/T9/T10/T11), app-ignore UI (T12), save-by-type (T2/T3/T6/T11), max-item-size off-by-default (T2/T3/T6/T11), fuzzy (T4/T5/T6/T10/T11), unlimited retention (T1/T11), live updates (T10). All covered.
- **Types consistent:** `CaptureFilter`, `KeyCombo`, `FuzzyMatch.score`, `ClipQuery.fuzzy`, `applyCaptureSettings`, `reloadHotkey`, `prosciuttoSettingsChanged` used identically across tasks.
- **No placeholders:** every code step contains complete code; the only intentional stub (PrivacyTab in T11) is explicitly replaced in T12.
