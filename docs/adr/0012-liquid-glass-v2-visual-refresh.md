# ADR-0012 — "Liquid Glass v2" visual refresh (design round 8)

- **Status:** accepted
- **Date:** 2026-07-18
- **Amends:** ADR-0005 (AllisWell Glass design system) — same principles,
  refreshed execution. DESIGN.md §1/§3/§4/§5 updated in the same change.

## Context

Design rounds 1–7 shipped a cautious take on the Apple-2026 "Liquid Glass"
direction: a muted Tailwind-ish blue (`#2563EB`/`#8AB4FF`), a barely-visible
aurora, flat full-width frosted bars, and rectangular buttons. Feedback
round 8 (Mahir, 2026-07-18): **the colors are indistinct and it does not read
as Apple Liquid Glass**. Before redesigning, the actual Liquid Glass guidance
was researched; the load-bearing sources:

1. **Apple HIG — Materials** (developer.apple.com/design/human-interface-guidelines/materials):
   Liquid Glass is a *functional layer* for controls/navigation that **floats
   above the content layer**; content scrolls and peeks beneath it. Don't use
   it in the content layer; don't stack glass on glass; the *regular* variant
   (blurs + adjusts luminosity for legibility) is right for anything with
   text; *clear* is only for media backdrops.
2. **Apple — Adopting Liquid Glass** (developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass):
   controls get rounder and **concentric** with their containers (capsules);
   sheets get larger corner radii; tab bars/sidebars float; be judicious with
   color in controls so content shines; solid fills belong ON glass.
3. **Apple Newsroom — new software design announcement**
   (apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/):
   the material "reflects and refracts its surroundings", with specular
   highlights and **colorful light/dark tints** — vitality is explicit.
4. **Apple — Liquid Glass technology overview**
   (developer.apple.com/documentation/TechnologyOverviews/liquid-glass):
   hierarchy/harmony/consistency framing; leverage the system material for
   chrome, keep custom effects rare.
5. **Create with Swift — "Liquid Glass: hierarchy, harmony, consistency"**
   (createwithswift.com): glass elements group into a floating functional
   layer; components adapt instead of decorating.
6. **designedforhumans.tech — Liquid Glass accessibility guidance**: contrast
   can fall below WCAG AA over busy backdrops — enforce ≥ 4.5:1 *after* the
   material is applied, keep one glass sheet per view, respect
   reduce-transparency. (Wikipedia's Liquid Glass article documents Apple
   itself raising opacity after legibility complaints.)

Flutter has no system Liquid Glass, so the material must be rebuilt within
our constraints — WITHOUT giving up the G-rules (glass chrome-only, ≥ 4.5:1
text, both themes verified).

## Decision

1. **Vivid, verified palette.** Azure primary (`#0A5CFF` / `#3E9BFF`), indigo
   secondary (`#5A50E0` / `#B9AFFF`), Apple-red error (`#D70015` / `#FF5147`),
   Apple-green success (`#0D7A33` / `#30D158`), saturated priority ramp
   (green→amber→orange→red). Every pair re-verified by
   `scripts/design/contrast.py` (50 pairs, FAILURES: 0) — vividness came from
   *hue/chroma*, never from dropping below the contrast floors.
2. **Real glass material** (`GlassSurface` v2): backdrop blur σ22 **composed
   with a +55% saturation matrix** (color bleeds through vividly — the fog
   problem was the missing saturation), high-opacity tint for legibility
   (Apple's *regular* variant, matching their own post-beta opacity
   correction), gradient **lensing edge**, specular top catchlight, and a
   soft ambient shadow for floating chrome.
3. **Floating chrome.** Phone bottom bar → glass **capsule** (radius 32,
   12 px margins, content scrolls beneath via `extendBody`); wide-layout rail
   → floating glass **panel** (radius 28). Nav bars are the only glass in the
   app — one sheet per view, per source 6.
4. **Concentric, capsule geometry.** `AwRadius` 12/16/20/28 (+pill 32);
   buttons `StadiumBorder`, FAB circular, sheets/dialogs 28. Nested radii ≈
   parent − padding.
5. **Colorful aurora, honest legibility.** Three static blobs (azure, violet,
   mint) at higher alpha under a thinner veil; the contrast guard now models
   the *effective* veil-over-wash and tint-over-wash blends, so "more color"
   is provably compatible with 4.5:1 body text.
6. **iOS-flavored details.** Switches: `success` green track + near-white
   knob. Overdue/error text uses the vivid Apple red. System fonts stay
   (§3.3) — SF Pro on Apple hardware is the Liquid Glass typography.
7. **Screenshot harness as a permanent tool**
   (`apps/app/test/design_screenshots_test.dart`, `--dart-define=screenshots=true`):
   renders the real signed-in app (seeded replica) light+dark, phone+desktop,
   with real fonts and shadows — the §5 "screenshots reviewed" step is now
   reproducible. `buildAwTheme` gained a test-only `fontFamilyOverride`
   (null in production = byte-identical behavior).

## Consequences

- Every screen inherits the refresh through tokens/theme — no per-screen
  edits were needed; widget tests (306) stay green.
- Latent overflow hardening surfaced by real-font rendering: month header
  (`Expanded` + ellipsis) and dropdown labels (`FittedBox.scaleDown`) now
  survive narrow/mid-animation widths and long locales (DESIGN §9 L2).
- Native widget parity (DESIGN §8 W1): the Android Glance color tables
  (`values/colors.xml` + `values-night/`) moved to v2 in this change; the
  SwiftUI widget table does not exist yet (OPH-131 awaits the Xcode/device
  pass) and must be born with v2 values.
- Reduce-transparency accessibility setting: `GlassSurface` keeps a
  high-opacity tint so legibility never depends on the blur; a dedicated
  "solid chrome" fallback remains future work if user feedback asks for it.
