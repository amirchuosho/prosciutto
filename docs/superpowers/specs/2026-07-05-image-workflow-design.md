# Image-workflow features — design

Date: 2026-07-05
Status: approved (brainstorm), not yet committed (repo is under a no-push freeze)

Two independent features that improve how Prosciutto handles images. They share no
state and can ship separately.

1. **Auto-copy screenshots** — when the user takes a screenshot, put it on the
   clipboard automatically (so it is ready to paste and shows up in the gallery).
   Gated behind a Settings toggle.
2. **Edit an image clip in Preview** — an edit button on single-image clips that
   opens the image in macOS Preview and round-trips the saved result back to the
   clipboard as a fresh clip.

---

## Feature 1 — Auto-copy screenshots to clipboard

### Goal

After a screenshot is saved to disk (⌘⇧3 / ⌘⇧4 / window capture), copy its image to
`NSPasteboard` so it is immediately pasteable and captured by Prosciutto as an image
clip. The screenshot file on disk is left untouched.

### Detection: NSMetadataQuery on `kMDItemIsScreenCapture`

macOS tags every screenshot file with the Spotlight attribute
`kMDItemIsScreenCapture == 1`. This is locale-independent (works regardless of the
"Screenshot"/"צילום מסך" filename prefix) and location-independent (works no matter
where `com.apple.screencapture location` points).

Use a live `NSMetadataQuery`:

- Predicate: `kMDItemIsScreenCapture == 1`.
- Search scope: `NSMetadataQueryLocalComputerScope` (screenshots can be saved
  anywhere; scope is broad but the predicate is precise).
- Enable live updates (`NSMetadataQueryDidUpdate`). On the initial
  `NSMetadataQueryDidFinishGathering`, record the start time and DO NOT copy the
  existing backlog — only screenshots created after the watcher started.
- On each update, for newly added items whose `kMDItemFSCreationDate` is at/after
  the watcher start time and whose path has not already been processed:
  1. Read the image file (`NSImage(contentsOf:)` / raw data).
  2. Write it to the pasteboard (see below).
  3. Record the path in a processed-set so it is never copied twice.

### Writing to the pasteboard

```
NSPasteboard.general.clearContents()
NSPasteboard.general.setData(pngData, forType: .png)   // + .tiff fallback if needed
```

Write image data (not the file URL) so it pastes as an image into apps. The existing
`ClipboardMonitor` poller then observes the pasteboard change and stores it as an
image clip via the normal capture path — no special-casing in the store.

No feedback loop: the watcher reacts to screenshot *files*, not to pasteboard changes.

### Component

`ScreenshotWatcher` (app target — depends on AppKit + Foundation Spotlight):

- `start()` — build + start the `NSMetadataQuery`, record start time.
- `stop()` — stop the query, clear observers and the processed-set.
- Owns: the query, the start timestamp, the processed-path set, a reference to the
  pasteboard writer.

Lives in the app target (not `ProsciuttoKit`) because it is AppKit/Spotlight bound.

### Setting

- `Preferences.autoCopyScreenshots` — key `capture.autoCopyScreenshots`, **default
  `false`**.
- Toggle in `SettingsView` (Capture section), labelled e.g. "Copy screenshots to
  clipboard automatically" with a one-line explanation.
- `AppEnvironment` starts the watcher when the pref is true, stops it when false,
  applied live on toggle (mirror the existing `applyCaptureSettings()` pattern).

### Edge cases

- **Spotlight index lag:** the metadata item may appear a moment before the file is
  fully flushed. If the read fails, retry a couple of times over ~1.5s before giving
  up on that path.
- **Screenshot-to-clipboard (⌘⇧⌃4):** produces no file → never seen by the query →
  no duplicate (it is already on the clipboard).
- **Capture paused (`isPaused`):** still copy to the clipboard (that IS the feature).
  Whether it becomes a stored clip is up to the normal capture path.
- **`saveImages` off:** screenshot is still pasteable; it just is not stored as a clip.
- **TCC:** the first file read may prompt for Desktop/Files access. One-time, expected.
- **Double-processing:** guarded by the processed-path set + the start-time cutoff.

### Testing

Mostly runtime (Spotlight + pasteboard are environmental). Extract any pure helper
(e.g. "should this metadata item be processed given start time + processed set") into
a testable function if it is non-trivial; otherwise verify by taking a screenshot with
the toggle on and confirming a new image clip appears.

---

## Feature 2 — Edit an image clip in Preview

### Goal

Add an edit button to single-image clips. It opens the image in macOS Preview; when
the user edits and saves, the edited image is written back to the clipboard as a fresh
clip. The original clip is left untouched.

### Trigger / UI

- New action button in `ClipCard.actionBar`, shown only when the clip is a single
  image: `item.kind == .image` (covers both `imageData`-backed and single
  file-backed image clips; excludes multi-file `.file` clips).
- Icon: `pencil.tip.crop.circle` (reads as "edit image"). Placed before the trash
  button in the action bar.

### Flow

1. **Materialize to a temp file.** Write the clip's image to a temp `.png` under a
   Prosciutto temp dir (e.g. `NSTemporaryDirectory()/prosciutto-edit/<uuid>.png`).
   - If the clip has `imageData`, write that.
   - If it is file-backed, COPY the file to the temp path (never edit the user's
     original screenshot in place).
2. **Open in Preview.** `NSWorkspace.shared.open(tempURL, ...)` forcing Preview; if
   Preview is unavailable, fall back to the default app for the file type.
3. **Watch the temp file for save.** A file-modification watch (DispatchSource vnode
   `.write`/`.extend`, or a small FSEvents/metadata watch) on the temp file. Preview
   saves in place on ⌘S (no dialog for an existing file), so a write event means the
   user saved an edit.
4. **Round-trip.** On save: read the edited image, `clearContents()` + write PNG to
   the pasteboard. The poller stores it as a NEW image clip (original clip unchanged).
   If the user saves multiple times, the last save wins (each save re-writes the
   clipboard).
5. **Teardown.** Stop watching and delete the temp file when Preview closes (or after
   an inactivity timeout). Best-effort cleanup; temp dir is disposable anyway.

### Component

`ImageEditService` (app target):

- `edit(_ item: ClipItem)` — runs the flow above.
- Owns: the temp file URL, the file watcher, and the pasteboard writer. One active
  edit session per invocation; concurrent edits get separate temp files.

Wiring: `ClipCard` exposes an `onEditImage: () -> Void` closure (following the
existing `onPin` / `onDelete` / `onEditBody` pattern). `GalleryView` binds it to a
`GalleryViewModel` hook that calls `AppEnvironment`'s `ImageEditService`.

### Edge cases

- **Multi-file / non-image clips:** button not shown.
- **Preview missing:** fall back to the system default image editor.
- **User never saves:** nothing is round-tripped; temp file cleaned up on close/timeout.
- **Multiple saves:** each save updates the clipboard (last wins). Acceptable.
- **Round-trip re-capture:** relies on the normal poller, so the edited image becomes a
  fresh clip exactly like any copy. Original clip is not modified.

### Testing

Runtime-dominant (Preview + pasteboard). The temp-file materialization (imageData →
file, file-backed → copied file) is pure-ish and can be unit-tested at the app level.
Verify end to end: edit an image clip, save in Preview, confirm a new edited clip
appears.

---

## Shared notes

- Both services live in the **app target**; `ProsciuttoKit` stays UI/AppKit-free.
- Neither feature changes the store schema or the capture protocol — both work purely
  by putting bytes on `NSPasteboard` and letting the existing pipeline capture them.
- Ship order is independent; Feature 1 and Feature 2 are separate units.
