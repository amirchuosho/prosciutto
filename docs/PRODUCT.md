# PRODUCT.md — Prosciutto

## Register
**Brand.** The primary surface here is the marketing landing page (`web/`). Design IS the
product: a visitor's impression is the thing being made.

## Product
Prosciutto is a free, open-source clipboard manager for macOS. It remembers everything you
copy and shows it as a fast, gorgeous horizontal gallery you summon with a hotkey; arrow to a
card, hit return, it pastes. The signature hook is **9 full named themes** (Synthwave, Matrix,
Dracula, Cyberpunk, Vaporwave, Nord, Gruvbox, Daylight, Prosciutto) — each re-skins the whole
app, not just an accent. Installs with one Homebrew command. No account, no subscription, no
cloud: everything stays on the Mac.

## Users & Purpose
Mac power users, developers, and designers who copy-paste constantly. They want their clipboard
history back, fast, without leaving the app they're in — and they enjoy software with taste and
a sense of humor. The page should evoke **delight, confidence, and a grin**: "this is fun, this
is fast, and it's free? installing now."

## Brand & Personality
Three words: **playful, bold, irreverent** (and secretly very well-crafted). Ham motif runs
through it (it's called Prosciutto). Humor is load-bearing: absurd fake endorsements from real
world leaders, deadpan copy. Confident, not corporate.

**Signature design idea:** the page demonstrates the product. It *dresses itself* in the app's
own themes — a switcher re-skins the entire page live (background, surfaces, accent, type
colors), so the visitor experiences the theme system instead of reading about it.

## References (the specific thing, not the category)
- **Liquid Death** — commits to a loud, funny, drenched-color voice without becoming a joke; the
  craft underneath the irreverence.
- **Vercel / Linear** — for the *restraint of the type system and motion timing* only (not the
  monochrome look).
- Arcade / synth / deli-signage energy for the maximal moments.

## Anti-references (do NOT look like)
- Generic SaaS landing: Inter/DM Sans/**Outfit**, `background-clip:text` gradient headings,
  glass cards by default, tiny uppercase tracked eyebrows over every section, identical
  icon+heading+text feature-card grids, the hero-metric template. The current v1 page fell into
  several of these — the redesign must break all of them.
- Sterile, corporate, "enterprise-grade" anything.
- Editorial-magazine serif-italic-broadsheet lane (wrong register for this brand).

## Design principles
1. **Show, don't tell** — the page is themeable, mirroring the app.
2. **Color is voice** — drenched / theme-reactive, never beige.
3. **Motion is part of the build** — orchestrated page-load + interaction motion, with a full
   `prefers-reduced-motion` alternative.
4. **Craft under the chaos** — loud but legible: AA contrast, sane hierarchy, responsive at every
   breakpoint.

## Accessibility
WCAG AA contrast for body/large text across every theme. Full reduced-motion fallback (crossfade
/ instant, no entrance-gated content). Keyboard-focusable controls with visible focus.
