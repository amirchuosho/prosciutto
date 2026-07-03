# Contributing to Prosciutto 🍖

Thanks for wanting to help! Prosciutto is a small, opinionated app, but issues and pull
requests are genuinely welcome.

## How it works

You **can't** push directly to this repo — and that's on purpose. The flow is:

1. **Fork** the repo (top-right on GitHub).
2. Create a branch on your fork: `git checkout -b my-fix`.
3. Make your change, commit, push to your fork.
4. Open a **Pull Request** against `amirchuosho/prosciutto:main`.

The maintainer (**@amirchuosho**) reviews and merges. You never need merge rights —
open the PR and it'll get looked at.

## Before you open a PR

- Run the logic suite: `swift test` (it must pass).
- **Add tests** for new behaviour. Pure logic lives in `Sources/ProsciuttoKit/` and is
  TDD-first — put the test in `Tests/ProsciuttoKitTests/`.
- For UI changes, keep them **focused** and match the existing SwiftUI patterns. Add a
  screenshot or short clip to the PR.
- Follow the app's conventions (see the [architecture note](README.md#architecture)).

## Building

```sh
brew install xcodegen
git clone https://github.com/<you>/prosciutto.git && cd prosciutto
swift test            # logic suite
xcodegen generate     # generate Prosciutto.xcodeproj
open Prosciutto.xcodeproj
```

## Good first contributions

- Bug reports with clear repro steps (open an issue).
- New capture kinds / detectors (with tests in `ProsciuttoKit`).
- New themes (they're pure data — `Sources/ProsciuttoKit/Theme/AppTheme.swift`).

## Ground rules

- Be kind. This is a hobby project made for fun.
- Big or architectural changes? Open an **issue first** to discuss before writing code —
  saves everyone time if the direction isn't a fit.

That's it. Copy something, fix something, send it over. 🍖
