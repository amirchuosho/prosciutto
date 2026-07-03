# Full Named Themes — Design Spec

**Date:** 2026-07-03
**Issue:** #2 (Themes)
**Status:** Approved design, ready for implementation plan

## Goal

Replace the current theming (an Appearance toggle × 13 accent-only palettes that
only tint the selection accent) with a curated set of **full, self-contained named
themes**. Each theme is a complete visual world — background, card surfaces,
per-type header colors, and accent — not just an accent color.

## Decisions (from brainstorm)

- **Each theme recolors the per-TYPE card bands** (text/link/image/color/code/file/
  location). Type distinction survives, but inside the theme's palette.
- **Self-contained:** each theme defines its own background; picking a theme
  overrides Light/Dark. One look per theme (no light+dark variants).
- **Static only:** gradients, glow, colored surfaces — no animation. This is a hard
  requirement: the gallery panel has a tight GPU compositing budget at 120Hz (the
  2026-07-03 scroll-hiccup fix, commit 8d4b646, showed animated scroll already drops
  render-server frames); animated backgrounds would reintroduce scroll stutter.
- **Replace** the Appearance + 13 accent themes with **one Theme concept**: 9 named
  themes + a Custom option. Keep user-custom accent (via the Custom theme).

## Theme set (10 options)

8 dark + 1 light + Custom. Initial hex below — **tuned live during implementation**
(like the existing color-clip editor); the data model is the contract, not the exact
values.

| Theme | Vibe | Background | Surface | Accent (2-stop) | Dark |
|---|---|---|---|---|---|
| **Prosciutto** (default) | House ham-pink | radial `#2a1622`→`#141018` | `#1E1B24` | `#FF70A3`→`#FF4566` | ✓ |
| **Synthwave** | 80s neon sunset | `#1a1033`→`#2a1550`→`#3d1a4d` | `#241640` | `#FF3CAC`→`#7A2FF7` | ✓ |
| **Matrix** | Phosphor terminal | radial `#06120a`→`#030603` | `#0B140B` | `#39FF14`→`#00C853` | ✓ |
| **Dracula** | Dev-famous | `#282A36` | `#343746` | `#BD93F9`→`#FF79C6` | ✓ |
| **Nord** | Arctic, calm | `#2E3440` | `#3B4252` | `#88C0D0`→`#5E81AC` | ✓ |
| **Vaporwave** | Pastel dream | `#2a1b3d`→`#3a2352`→`#1b3a4a` | `#2E2246` | `#FF6AD5`→`#8C6AFF` | ✓ |
| **Cyberpunk** | Neon high-contrast | `#0A0A0F` | `#13131C` | `#FCEE0A`→`#00F0FF` | ✓ |
| **Gruvbox** | Warm retro | `#282828` | `#32302F` | `#FE8019`→`#D65D0E` | ✓ |
| **Daylight** | Clean light | `#F6F3F7`→`#EDE9F1` | `#FFFFFF` | `#FF70A3`→`#FF4566` | ✗ |
| **Custom** | User accent | neutral `#16141B` | `#201D27` | user hex (→ darker) | ✓ |

### Per-type header colors (Text, Link, Image, Color, Code, File, Location)

Initial ramps, tuned live. `.rtf` maps to Text.

- **Prosciutto:** `#5C8FFF` `#C77DFF` `#FF9E5C` `#FF6FB0` `#52CC85` `#6FD3C7` `#FF6B6B`
- **Synthwave:** `#00E5FF` `#FF6AD5` `#FFB03C` `#FF3CAC` `#39FF9E` `#7AF0FF` `#FF4778`
- **Matrix:** `#39FF14` `#A6FF00` `#B7FF3C` `#7CFFB0` `#00E676` `#4FD06A` `#E5FF3C` (green/amber ramp)
- **Dracula:** `#8BE9FD` `#FF79C6` `#FFB86C` `#BD93F9` `#50FA7B` `#8BE9FD` `#FF5555`
- **Nord:** `#81A1C1` `#B48EAD` `#D08770` `#88C0D0` `#A3BE8C` `#8FBCBB` `#BF616A`
- **Vaporwave:** `#8CF0E8` `#FFB8E0` `#FFD08C` `#FF6AD5` `#C6A6FF` `#8CD8F0` `#FF8CC8`
- **Cyberpunk:** `#00F0FF` `#FF00A0` `#FF6A00` `#FCEE0A` `#00FF9F` `#00F0FF` `#FF003C`
- **Gruvbox:** `#83A598` `#D3869B` `#FE8019` `#D3869B` `#B8BB26` `#8EC07C` `#FB4934`
- **Daylight:** `#4C82F5` `#A55CE0` `#F0913C` `#E85C9E` `#2FB765` `#2AA9A0` `#E5484D` (deeper for white bg)
- **Custom:** reuses Prosciutto's type ramp (functional, neutral against any accent).

## Data model

A pure value type — the single source of truth for a theme's look:

```
struct ThemePalette {
    var background: ThemeFill      // solid | linearGradient | radialGradient
    var surface: Color             // card body
    var foreground: Color          // primary text
    var secondary: Color           // secondary/meta text
    var hairline: Color            // dividers/borders
    var accent: [Color]            // 2-stop gradient (accent[0] = flat accent)
    var typeColors: [ClipKind: Color]
    var isDark: Bool               // system text-contrast hint
    func color(for kind: ClipKind) -> Color
}

enum AppTheme: String, CaseIterable, Identifiable {  // the 10
    case prosciutto, synthwave, matrix, dracula, nord,
         vaporwave, cyberpunk, gruvbox, daylight, custom
    var label: String
    func palette(customAccentHex: String) -> ThemePalette
}
```

`ThemeFill` is a small enum so a background can be a solid color, a linear gradient
(Synthwave/Vaporwave/Daylight), or a radial (Prosciutto/Matrix). It exposes a
`View` (or `ShapeStyle`) for the panel background.

`ThemePalette`, `AppTheme`, `ThemeFill` live in **ProsciuttoKit** (pure, testable).
`ClipKind` already lives there.

## ThemeManager (app target)

```
final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme          { didSet { persist } }
    @Published var customAccentHex: String  { didSet { persist } }
    var palette: ThemePalette { theme.palette(customAccentHex: customAccentHex) }
    var accent: Color { palette.accent[0] }
    var accentGradient: LinearGradient { LinearGradient(palette.accent, …) }
    var colorScheme: ColorScheme? { palette.isDark ? .dark : .light }
}
```

Replaces the current `appearance` / `accentTheme` / `accentColors` API surface.
`colorScheme` is derived from the palette's `isDark` (so SwiftUI's own controls,
menus, text pick the right contrast) instead of a user Appearance setting.

## Scope — the refactor (bulk of the work)

Today these are keyed on `ColorScheme` (light/dark). They become **palette-driven**:

- `DesignSystem.cardBody(scheme)` → `palette.surface`
- `DS.hairline` / `DS.cardStroke` / `DS.footerMeta` / `DS.panelFill` → palette fields
- `GalleryView.panelBackground` → `palette.background` fill (+ keep the material layer
  for depth; the accent radial becomes part of the palette background)
- `KindStyle.of(kind).color` → `palette.color(for: kind)`. `KindStyle` keeps
  **icon + label**; only the color moves to the palette.
- `ClipCard` band/foreground/`readableText` → derived from the type color + palette.

Threading: views already have `@EnvironmentObject theme: ThemeManager`; add
`palette` reads. `KindStyle` color lookups that aren't in a view (if any) take the
palette as a parameter, or read `ThemeManager` where they're views. Audit all
`KindStyle.of(...).color` and `DS.*(scheme)` call sites.

## Settings UX

Replace the current Appearance + accent-preset controls with a **theme grid picker**:
a grid of live mini-mockups (each rendered from its `ThemePalette` — background, a
few type-banded cards, accent ring), selectable. A **Custom** cell opens the accent
color well (reuses the existing color editor). Selecting a theme applies instantly
(already live via `@Published`).

## Migration

Old `Preferences`: `appearanceRaw`, `accentThemeRaw`, `customAccentHex`. One-time
silent map on load: any old value → `AppTheme.prosciutto` (keep `customAccentHex` for
the Custom theme). New key: `themeRaw`. Old keys can be left dormant or cleaned up.

## Testing (ProsciuttoKit, pure)

- Every `AppTheme` returns a `ThemePalette` with a color for **all 7** `ClipKind`s.
- Accent has exactly 2 stops; all colors are valid.
- `isDark` set correctly (Daylight = false, rest = true).
- `color(for: .rtf) == color(for: .text)`.
- Custom: `palette(customAccentHex:)` uses the hex for accent; falls back sanely on
  bad hex.
UI stays thin (grid picker is a dumb render of palettes).

## Out of scope (YAGNI)

- Animation/motion of any kind (hard perf constraint).
- Light+dark variants per theme.
- Per-theme fonts, corner radii, or layout changes (palette = color only).
- User-authored full themes (only Custom accent is user-editable).

## Open items (decided defaults)

- Custom = neutral dark base + user accent; its type ramp = Prosciutto's.
- Migration defaults everyone to Prosciutto.
- Exact hex values are tuned live during implementation; this spec fixes the model
  and directions, not final colors.
