# Prosciutto — Design Spec

**Date:** 2026-06-24
**Status:** Approved (design), pending implementation plan
**One-liner:** Open-source, visual, native macOS clipboard manager — the delight of Paste+, the openness of Maccy.

---

## 1. Motivation

Maccy (OSS) is fast and keyboard-first but deliberately barebones: a vertical text list, no visual previews, no organization, no sync, weak filtering. Paste+ ($30/yr, closed) nails the experience power users love — a horizontal visual card timeline, pinboards, rich search — but is paid and proprietary. macOS 26 Tahoe now ships a basic native clipboard history, pressuring barebones tools to justify themselves.

**Prosciutto's gap:** an open-source app with Paste's *visual, organized, delightful* feel — the experience Maccy refuses to build.

Branding: 🐖 thin-sliced layers = clipboard history slices. Menu-bar icon = ham slice. Fun, memorable.

---

## 2. Locked Decisions

| Area | Decision | Rationale |
|---|---|---|
| Stack | Native Swift / SwiftUI | Best perf, deepest macOS integration, free iCloud path, native feel. Same family as Maccy. |
| Min OS | macOS 14 Sonoma+ | Mature SwiftUI, `Observation`, `MenuBarExtra`. |
| Sandbox | Non-sandboxed | Clipboard monitoring, global hotkey, Accessibility paste fight the App Store sandbox. |
| Core UI | Horizontal card gallery, slide-up panel | Paste's signature; the main thing Maccy lacks. |
| Sync | Local-first in v1, iCloud-ready schema | Ships fast, privacy-first; iCloud = flip a flag later. |
| Storage | Core Data via `NSPersistentCloudKitContainer` (cloud disabled v1) | Free iCloud sync path with near-zero rework when enabled. |
| Distribution | Notarized DMG (GitHub Releases) + Homebrew cask | Standard for OSS Mac power tools; no sandbox limits. Needs Apple Developer ID ($99/yr) for notarization. |
| Feature scope | Full Paste-parity feature set, phased delivery | User wants parity; plan ships core MVP first, layers extras. |

---

## 3. Architecture

Menu-bar resident app (`MenuBarExtra`), no dock icon by default. Modules:

| Module | Responsibility |
|---|---|
| **ClipboardMonitor** | Poll `NSPasteboard.changeCount` ~300ms. On change: read all type representations → build `ClipItem` → dedupe by hash → apply exclusion rules → save. |
| **Storage** | Core Data stack via `NSPersistentCloudKitContainer`. Cloud container disabled in v1. Image blobs use "Allows External Storage". |
| **PasteService** | Write selected item to `NSPasteboard`, restore frontmost-app focus, synthesize `⌘V` via `CGEvent` (requires Accessibility permission). Option: restore prior pasteboard contents afterward. |
| **HotkeyManager** | Global hotkey (default `⌘⇧V`) via Carbon `RegisterEventHotKey`. Rebindable in Settings. |
| **GalleryWindow** | Borderless, non-activating `NSPanel` sliding up from screen bottom. Hosts SwiftUI card gallery. Keyboard-driven. |
| **CardRenderers** | Per-`kind` preview views: text, image, link (favicon + title), color (swatch + hex), code (syntax highlight), file (icon + name + size). |
| **SearchIndex** | SQLite FTS5 over plain text + OCR text + link titles. |
| **OCRService** | Vision `VNRecognizeTextRequest`, async background on image items. Recognized text stored on item → searchable. |
| **MCPServer** | Local MCP server (stdio) exposing search / get / pin / list-pinboards to AI tools (Claude, Codex). Opt-in. |
| **Settings** | Hotkey, retention, exclusions, appearance, MCP toggle, permissions status. |
| **Onboarding** | First-run Accessibility permission flow + privacy explainer. |

**Storage choice note:** Core Data chosen over GRDB specifically for the free `NSPersistentCloudKitContainer` iCloud path, given iCloud-later is a goal. Trade-off accepted: less raw query control than GRDB.

---

## 4. Data Model

```
ClipItem
  id: UUID
  createdAt, lastUsedAt: Date
  useCount: Int
  kind: enum (text | rtf | image | link | color | code | file)
  textPlain, textRTF, html: String?      (populated per kind)
  imageData: Data?  (external storage), imageW, imageH: Int?, byteSize: Int
  sourceAppBundleID, sourceAppName: String?
  contentHash: String                    (dedupe key)
  ocrText: String?
  isPinned: Bool
  expiresAt: Date?                        (nil when pinned/boarded/snippet)
  pinboard: Pinboard?                     (item → one board)

Pinboard
  id: UUID, name: String, icon: String, color: String, sortIndex: Int
  items: [ClipItem]

Snippet
  id: UUID, title: String, body: String, keyword: String?, sortIndex: Int
```

**Dedupe:** identical copy (same `contentHash`) bumps `lastUsedAt` / `useCount`, no duplicate row.

**Retention (configurable):** keep last `N = 1000` items OR `7 days` for unpinned, whichever first. Pinned items, items in a pinboard, and snippets never expire.

---

## 5. Privacy & Capture Rules (non-negotiable)

1. Honor `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` pasteboard markers → **skip capture** (the standard mechanism password managers like 1Password use to opt out).
2. App blocklist — default includes known password managers; user-editable.
3. Per-app pause + global pause toggle from menu bar.
4. All data local. No telemetry. Network used only for: favicon fetch (links), on-device OCR (no network), and opt-in local MCP. Nothing leaves the machine otherwise.

---

## 6. Core UX Behavior

- `⌘⇧V` → panel slides up from bottom, search field focused, frontmost app stays active (non-activating panel).
- Type → live search/filter.
- `←` / `→` or trackpad scroll → move selection.
- `↵` → paste selected: hide panel, restore prior app focus, synthesize `⌘V`.
- `⌘1`–`⌘9` → instant-paste card N.
- `⌘⌥V` → paste selected as plain text (strip formatting).
- `Space` / right-click → large Quick Look-style preview.
- Drag card onto a pinboard chip (top bar) → file it; drag card out → drop into any app.
- Top bar: pinboard chips + filter pills (type / source app / date).
- Hover pin toggle (`⌘P`).

ASCII reference of the gallery:

```
  Prosciutto  —  ⌘⇧V                    [search 🔍]
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│ def   │ │ #3FA9 │ │ [img] │ │ https:│ │ Lorem │
│ foo() │ │ █████ │ │ 🖼️    │ │ 🔗 git│ │ ipsum │
│ code  │ │ color │ │ 1.2MB │ │ link  │ │ text  │
└───────┘ └───────┘ └───────┘ └───────┘ └───────┘
  1        2        3        4        5
   ◀─ → scroll → ─▶     ↵ paste   ⌘1–9 quick
```

---

## 7. Error Handling & Edge Cases

| Case | Behavior |
|---|---|
| No Accessibility permission | Paste falls back to "item copied — press ⌘V yourself"; onboarding nudges to grant. |
| Huge image | Downsample for thumbnail; cap stored original size. |
| Pasteboard write race (app writing mid-read) | Skip this tick, retry next poll. |
| Corrupt/partial type representation | Store what reads cleanly, skip the rest. |
| OCR failure | Item still saved, just not OCR-searchable. |
| Favicon fetch fails | Show generic link icon. |

---

## 8. Testing Strategy

- **Unit:** dedupe hashing, retention/expiry logic, exclusion rules, type/kind detection, FTS query building, color/link/code detection heuristics.
- **Integration:** monitor → store pipeline driven by synthetic pasteboard writes; paste synthesis against a test target app.
- **Snapshot:** one per card renderer (text/image/link/color/code/file).
- **Manual QA checklist:** permission flows, hotkey rebinding, password-manager exclusion verification.

---

## 9. Delivery Phases

1. **MVP (Maccy-killer):** ClipboardMonitor + Core Data + GalleryWindow + HotkeyManager + all six card renderers + quick-paste + search + privacy/exclusion rules + Accessibility onboarding + menu bar + notarized DMG/Homebrew.
2. **Organization:** pinboards, pinned favorites, snippets, type/app/date filters, paste-as-plain-text.
3. **Smart:** OCR search-in-images (Vision), local MCP server.
4. **v2 (separate spec):** iCloud sync (enable CloudKit container, conflict handling, image asset sync), iOS companion app.

---

## 10. Out of Scope (v1)

- Windows / Linux / cross-platform.
- iCloud sync (schema ready, not wired).
- iOS app.
- Mac App Store build.
- Shared/collaborative pinboards.
- Telemetry / analytics.
