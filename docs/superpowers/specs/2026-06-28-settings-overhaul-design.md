# Settings Overhaul — Design

Date: 2026-06-28
Status: Approved (pending implementation plan)

## Goal

Expand Prosciutto's preferences from the current minimal set into a Maccy-grade
settings surface, cherry-picking the configs that fit a card-based clipboard
manager. Make all retention limits optional ("a huge clipboard is the user's
choice").

## Scope

Six features, plus making existing limits disable-able:

1. **Launch at login**
2. **Configurable hotkeys** — open-gallery + plain-paste (key recorder)
3. **App-ignore list UI** — manage the existing `blockedBundleIDs` (currently
   stored but uneditable)
4. **Save by type** — capture toggles for Text / Images / Files
5. **Max item size** — cap stored bytes per clip; **off by default** (no limit)
6. **Fuzzy search** — toggle in General; substring stays the default

Plus: **Keep N items** gains an *Unlimited* state; **Expire after N days** gains
a *Never* state.

### Out of scope (separate future tasks)
- Pause-via-global-hotkey, in-panel keybinds (⌘F/⌘N/⌘E/⌘R)
- Paste Stack (multi-paste in order)
- Image quick-preview (Space → Quick Look) — already a roadmap item
- Cloud/iCloud sync — shelved (see decisions/2026-06-28-no-cloud-sync)
- Sort-by, image-height (don't fit the fixed-size card model)

## Information Architecture (Settings tabs)

| Tab | Contents |
|-----|----------|
| **General** | Launch at login · Paste-on-select · Capture sound · Fuzzy search |
| **Hotkeys** | Open-gallery recorder · Plain-paste recorder |
| **History** | Keep N items (+ Unlimited) · Expire after N days (+ Never) · Max item size (+ Off) · Save by type: Text / Images / Files |
| **Privacy** | App-ignore list (add/remove apps) |
| **Appearance** | Theme · Accent *(unchanged)* |
| **Permissions** | *(unchanged)* |

`SettingsView` grows from 3 tabs to 6. Each tab is a `Form`/`.grouped` like today.
If `SettingsView` gets large, split each tab into its own `*SettingsTab.swift`
view for clarity.

## Data Model — `Preferences` additions

All UserDefaults-backed except Launch-at-login.

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `openHotkey` | keyCode: Int + modifiers: Int | ⌘⇧V | modifiers = Cocoa `NSEvent.ModifierFlags` rawValue |
| `plainPasteHotkey` | keyCode: Int + modifiers: Int | ⌘⌥V | same encoding |
| `saveText` / `saveImages` / `saveFiles` | Bool | true | capture toggles |
| `maxItemSizeBytes` | Int | 0 | 0 = no limit |
| `maxItems` | Int | 1000 | 0 = Unlimited (existing key, new sentinel) |
| `maxAgeDays` | Int | 7 | 0 = Never expire (existing key, new sentinel) |
| `useFuzzySearch` | Bool | false | opt in to fuzzy |
| `launchAtLogin` | — | — | NOT UserDefaults: reads/writes `SMAppService.mainApp`; OS is source of truth |
| `blockedBundleIDs` | Set<String> | defaultBlocked | already exists |

`KeyCombo { keyCode: UInt16, modifiers: NSEvent.ModifierFlags }` is the in-memory
representation, with a glyph display string and a Cocoa→Carbon modifier
conversion. Lives in the app target (AppKit-bound). `Preferences` stores/loads it
as the two ints.

## Capture Pipeline (ProsciuttoKit — unit-testable)

- **`CaptureFilter { enabledKinds: Set<ClipKind>, maxBytes: Int }`** with
  `shouldCapture(kind: ClipKind, byteSize: Int) -> Bool`:
  - `maxBytes == 0` → no size limit; else reject `byteSize > maxBytes`.
  - reject if `kind` not in `enabledKinds`.
  - Type mapping for the three toggles: `.image` → Images; `.file` → Files;
    everything else (`.text/.rtf/.link/.color/.code`) → Text. (A `CaptureFilter`
    factory builds `enabledKinds` from the three bools.)
- **`ClipboardMonitor`**: `exclusion` becomes `var`; add `var captureFilter`.
  In `poll()`, build the `ClipItem` via `make(...)` first, then measure the
  **stored payload** size — `byteSize = item.imageData?.count ?? item.textPlain?.utf8.count ?? 0`
  — and skip `upsert` when `!captureFilter.shouldCapture(kind:byteSize:)`.
  Measuring the made item (not the raw snapshot) matters: image *files* store only
  a path (the icon `imageData` is dropped), so they're never size-capped — the cap
  targets what actually bloats the store (large image *data*, huge text).
- **`RetentionPolicy`**: treat `maxItems <= 0` and `maxAge <= 0` as unlimited
  (no count cap / no age expiry). Update `survivors(of:now:)` accordingly.

### Live updates (fixes a real gap)
The blocklist is built once at launch today, so edits never take effect. Add
`AppEnvironment.applyCaptureSettings()` that rebuilds `ExclusionPolicy` +
`CaptureFilter` from `Preferences` and assigns them to the monitor's mutable
vars. Called at launch and whenever Settings change (Settings view invokes a
callback / posts a notification the AppEnvironment observes). No restart needed.
This also makes save-by-type and max-size changes take effect immediately.

## Hotkey Recorder

- **`KeyRecorderField`** (`NSViewRepresentable`): wraps an `NSView` that becomes
  first responder on click and captures one `keyDown`. Reports a `KeyCombo`.
  - Requires ≥1 modifier (rejects bare keys so plain typing can't be hijacked).
  - `esc` cancels recording; `⌫` clears to empty.
  - Renders the current combo as glyphs (⌘⇧V).
- **Open-gallery**: on change, `Preferences.openHotkey` saves; `AppEnvironment`
  re-registers `HotkeyManager` (`unregister()` then `register(keyCode:modifiers:)`
  with Cocoa→Carbon-converted modifiers). `HotkeyManager.register` already takes
  these params.
- **Plain-paste**: stored combo; the in-panel `NSEvent` key monitor in
  `AppEnvironment.installKeyMonitor` compares `event.keyCode` + modifier flags
  against `Preferences.plainPasteHotkey` instead of the hardcoded ⌘⌥V.

## Launch at Login

`LoginItem` helper wrapping `SMAppService.mainApp`:
- `var isEnabled: Bool { SMAppService.mainApp.status == .enabled }`
- `setEnabled(_:)` → `register()` / `unregister()` (throws handled, surfaced as a
  revert + brief error in the toggle).
- macOS 14 deployment target supports `SMAppService`.

## Fuzzy Search

- **`FuzzyMatch.score(_ needle: String, _ haystack: String) -> Int?`** in
  ProsciuttoKit: case-insensitive subsequence match; `nil` when not all needle
  chars appear in order; higher score = better (contiguous runs / early matches
  score higher). Pure, unit-tested.
- **`ClipQuery`** gains `fuzzy: Bool`. When `fuzzy` and `text` non-empty: keep
  items with a non-nil score against (title + textPlain), and **rank by score
  descending** (relevance order for searches). When `fuzzy` is false: current
  substring `contains` filter, existing order.
- The VM sets `query.fuzzy = Preferences.useFuzzySearch`.

## App-Ignore List UI (Privacy tab)

- List the current `blockedBundleIDs` with app name + icon (resolve via
  `AppIconProvider` / `NSWorkspace`).
- **Add**: pick from running apps (`NSWorkspace.shared.runningApplications`,
  filtered to regular apps) and/or a `.app` file picker → append bundle ID.
- **Remove**: per-row delete.
- Writes `Preferences.blockedBundleIDs`; triggers `applyCaptureSettings()` so the
  monitor picks it up live.

## Testing

**Unit (ProsciuttoKit, `swift test`):**
- `CaptureFilter` — type include/exclude; size cap on/off boundary.
- `RetentionPolicy` — `maxItems = 0` keeps everything; `maxAge = 0` never expires;
  normal limits still trim.
- `FuzzyMatch` / `ClipQuery` — subsequence hits/misses, ranking order, fuzzy-off
  falls back to substring.
- `KeyCombo` Cocoa→Carbon modifier conversion (if extractable as pure logic).

**Manual / screenshot-verify (app):**
- Each Settings tab renders; toggles persist.
- Launch-at-login reflects/sets `SMAppService` state.
- Recording a new open hotkey re-registers and works globally; new plain-paste
  combo works in-panel.
- Save-by-type and max-size take effect on the next copy without restart.
- App-ignore add/remove blocks/unblocks capture from that app live.

## Risks / Notes

- `SMAppService` registration can fail on unsigned/ad-hoc builds in some macOS
  versions — verify on the dev build; surface failures by reverting the toggle.
- Cocoa↔Carbon modifier mapping must be exact (cmd/shift/option/control); cover
  with a test.
- Fuzzy ranking reorders search results (intended); pinned-first ordering applies
  only when there is no active fuzzy query.
