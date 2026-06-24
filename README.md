# 🐖 Prosciutto

> Open-source visual clipboard manager for macOS — the delight of Paste+, fully open.

Prosciutto keeps a rich, visual history of everything you copy: text, images,
links, colors, code, and files. Hit a global hotkey and a horizontal gallery of
cards slides up from the bottom of your screen. Scroll, search, and paste — without
leaving the app you're in.

Built because [Maccy](https://github.com/p0deje/Maccy) is great but minimal, and
Paste+ is wonderful but closed and paid.

## Features (v1)

- **Visual card gallery** — horizontal, scrollable, rich previews per type
- **Global hotkey** — `⌘⇧V` to summon, rebindable
- **Six content kinds** — text, image, link (with favicon), color (with swatch), code, file
- **Quick paste** — `⌘1`–`⌘9` paste a card instantly
- **Search & filter** — live search, filter by type
- **Paste as plain text** — `⌘⌥V`
- **Privacy-first** — honors `org.nspasteboard.Concealed/Transient` markers and a
  password-manager blocklist; everything stored locally, no telemetry
- **Pinning** — pin items so they never expire

Roadmap (later phases): pinboards & snippets, OCR search-in-images, an AI/MCP
server, and iCloud sync across Mac/iPhone/iPad.

## Install

```sh
brew install --cask prosciutto   # via the tap (coming soon)
```

Or download the notarized DMG from [Releases](https://github.com/OWNER/prosciutto/releases).

### Permissions

Prosciutto asks for **Accessibility** access so it can paste into the frontmost
app. Without it, items are copied to the clipboard and you press ⌘V yourself.
Grant via System Settings → Privacy & Security → Accessibility.

## Privacy

All clipboard data lives in a local Core Data store on your Mac. Nothing is sent
anywhere. The only network requests are favicon fetches for link cards.

## Build from source

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
swift test                                   # run the ProsciuttoKit logic suite
xcodegen generate                            # generate Prosciutto.xcodeproj
open Prosciutto.xcodeproj                     # build & run the app in Xcode
```

Architecture: pure logic lives in the `ProsciuttoKit` Swift package (capture,
dedupe, kind detection, exclusion, retention, search) and is fully unit-tested
with `swift test`. The app target (SwiftUI + AppKit) provides the Core Data store,
menu bar, gallery panel, hotkey, and paste synthesis. The Xcode project is
generated from `Project.yml` — never edit `.xcodeproj` by hand.

## Contributing

Issues and PRs welcome. Run `swift test` before submitting. The logic layer is
TDD-first; please add tests for new behavior in `ProsciuttoKit`.

## License

MIT — see [LICENSE](LICENSE).
