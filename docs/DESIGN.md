# DESIGN — "AllisWell Glass" design system

> **This file is the single source of truth for how AllisWell looks and feels.**
> It is BINDING for every future UI change — web, mobile, desktop, all six
> Flutter targets. Visual consistency with this document is part of the
> Definition of Done (AGENTS.md hard rule 11). If a change needs to deviate,
> amend THIS file (and note why) in the same PR — never ship a one-off style.
>
> Established 2026-07-15 (design round 1, ADR-0005). Code home:
> `apps/app/lib/src/theme/` (tokens + theme) and `apps/app/lib/src/widgets/`
> (glass surfaces, shared states).

## 1. Design language in one paragraph

Apple-2026 "Liquid Glass" inspired, but **UX-first**: a calm aurora wash in
the background, frosted-glass **chrome** (navigation rail, bottom bar), and
**solid, high-contrast surfaces for everything users read or touch**. Rounded
geometry (10–24 px), hairline borders, circular checkboxes, one accent blue.
No decoration may ever cost legibility: if glass and readability conflict,
readability wins.

## 2. Non-negotiable principles

| # | Rule | Why |
| --- | --- | --- |
| G1 | **Glass is chrome-only.** Backdrop blur may be used for navigation bar/rail, and (sparingly) toolbars. Body text, forms, lists and sheets sit on SOLID surfaces. | Text over live blur can never guarantee contrast. |
| G2 | **Contrast floors:** body & control text ≥ 4.5:1; icons, borders of interactive controls, focus indicators ≥ 3:1 — in BOTH themes. | WCAG AA; the palette in `tokens.dart` is pre-verified. |
| G3 | **Inputs look like inputs.** Filled field + visible 1 px outline (`ColorScheme.outline`) + 2 px primary focus ring. Never borderless/ghost inputs for real forms. | Users must see where to click/type (Mahir, design round 1). |
| G4 | **Tap targets ≥ 44 px** (48 dp Android). Icon-only actions use `IconButton` (never a bare `InkWell` around a small icon). | Touch usability. |
| G5 | **Never color-only meaning.** Priority color + flag icon; status icon + label; error color + icon/text. | Colorblind users. |
| G6 | **Tokens only.** No raw hex/`Colors.*` in widgets — use `Theme.of(context).colorScheme` or `context.awTokens`. Exceptions: user-picked project/tag colors (data, not UI), and the brand mark gradient in `brand_mark.dart`. | Consistency + theme integrity. |
| G7 | **Both themes, always.** Every UI change is checked in light AND dark before it ships. Dark is not inverted light; it uses its own verified palette. | Half the users live in dark mode. |
| G8 | **Motion is quick and physical:** 150–320 ms, `easeOutCubic` in / `easeInCubic` out. No decorative/slow animation; static aurora (no animated blobs). | Perceived speed, reduced-motion friendliness. |

## 3. Tokens (source: `apps/app/lib/src/theme/tokens.dart`)

### 3.1 Color — light / dark

Roles come from the hand-tuned `ColorScheme` in `theme.dart` (NOT
`fromSeed`); extra semantic slots live in `AwTokens`:

| Token | Light | Dark | Used for |
| --- | --- | --- | --- |
| primary | `#2563EB` | `#8AB4FF` | buttons, selection, FAB |
| onSurface | `#101828` | `#E7ECF6` | body text |
| onSurfaceVariant | `#43516C` | `#A8B4CE` | secondary text, icons |
| surface (cards) | `#FFFFFF` | `#131C31` | list rows, cards, sheets |
| surfaceContainerHigh | `#E9EEF7` | `#1C2842` | input fill |
| outline (input border) | `#697D9E` | `#6A7CA5` | enabled input borders (≥3:1 vs fill) |
| error | `#B42318` | `#F97066` | errors, overdue, destructive |
| tertiary | `#0F766E` | `#2DD4BF` | calendar dots, positive accents |
| AwTokens.success | `#047857` | `#34D399` | done states, low priority |
| AwTokens.warning | `#B45309` | `#FBBF24` | favorite/pin stars, medium priority |
| AwTokens.link | `#1D4ED8` | `#8AB4FF` | text buttons, links |
| AwTokens.prioLow/Med/High/Urgent | `#047857 #B45309 #C2410C #DC2626` | `#34D399 #FBBF24 #FB923C #F87171` | priority flags |
| AwTokens.hairline | `#101828` @ 8% | `#E7ECF6` @ 12% | decorative card borders, dividers |
| AwTokens.glassTint / veil / aurora* | see file | see file | chrome + background wash |

**Priority hues are fixed** (low=green, medium=amber, high=orange,
urgent=red) — only lightness adapts per theme, so meaning never shifts
(BLUEPRINT §12.4). Same idea applies to any future semantic color: one hue,
two verified lightnesses.

### 3.2 Shape, spacing, motion

- Radius scale `AwRadius`: **10** chips/small · **14** inputs & list rows ·
  **18** cards · **24** sheets/dialogs. FAB uses 18.
- Spacing `AwSpace`: 4-pt grid (4/8/12/16/20/24/32/48). No off-grid values.
- Motion `AwMotion`: fast 150 ms · base 220 ms · slow 320 ms.
- Blur: `kAwGlassSigma = 18` (only inside `GlassSurface`).

### 3.3 Typography

Platform system fonts on purpose (SF Pro on Apple, Roboto/Segoe elsewhere,
Roboto on web) — zero network fetch, native feel. Weights/tracking tuned in
`theme.dart`: headlines w700 with negative tracking, titles w600, labels
w600, body 16/1.5. Use `textTheme` roles; never ad-hoc `fontSize`.
Tabular figures for day numbers and timers.

## 4. Component rules (all themed centrally in `theme.dart`)

- **Lists** are inset grouped cards: each row is a `Card` (radius 18,
  hairline border, solid surface) with 6 px vertical rhythm inside
  `awListPadding(context)` (clears glass bars + FAB). No full-width
  divider lists.
- **Checkboxes are circular** (Apple Reminders style); checked fill =
  `AwTokens.success`.
- **Buttons:** `FilledButton` = the one primary action per screen;
  `FilledButton` with error colors for destructive confirms; `OutlinedButton`
  secondary; `TextButton` tertiary/links. Min height 48.
- **Sheets:** modal bottom sheets with drag handle (theme default), top
  radius 24, `maxWidth 560` on wide screens, solid `surfaceContainerLow`.
  Tappable rows inside sheets get a filled `surfaceContainerHigh` backdrop +
  chevron affordance (see `_SheetTile` in `task_create_sheet.dart`).
- **Dialogs:** radius 24, solid, destructive action = error-colored
  `FilledButton`, cancel always present (escape route).
- **Empty/error states:** use `AwEmptyState` / `AwErrorState`
  (`widgets/status_views.dart`) — icon badge, title, guidance, and for
  errors ALWAYS a Retry action. Inline form errors use `AwInlineError`
  (icon + errorContainer band above the submit button).
- **Navigation:** `GlassSurface` wraps the `NavigationRail` (≥800 px) and
  the bottom `NavigationBar` (<800 px, `extendBody: true` so content scrolls
  under the glass). Selected item = primaryContainer pill; labels always
  visible.
- **App bars:** transparent over the wash, title left, `titleLarge` w700,
  no elevation/tint.
- **Backgrounds:** `AuroraBackground` is painted ONCE in `app.dart`
  (`MaterialApp.builder`); scaffolds use the translucent `veil` token.
  Never stack another wash inside a screen.
- **Overdue** dates render in `error` color w600 with the word "Overdue".
- **Stars (favorite/pin)** use `AwTokens.warning`, never `Colors.amber`.
- **Project badge (task rows — added 2026-07-17, feedback round 4, OPH-104):**
  a FILLED pill in the project's color, rightmost element of the row's
  trailing cluster. Radius 10 (`AwRadius.s`), padding 8×2, `labelSmall` w600,
  min height 22, tap-transparent (the row handles taps). Label = the project
  name, truncated to its first 6 characters + "…" when longer (grapheme-safe
  via `Characters`); the FULL name is always available through `Tooltip`
  (hover + long-press) and `semanticLabel` (`Project: <name>`). The foreground
  is computed, never fixed: relative luminance of the fill > 0.45 → ink
  `#101828`, otherwise white `#FFFFFF` — one shared helper (with a unit test
  sweeping `kProjectPalette` and the full color-grid) so the pair stays
  ≥ 4.5:1. Project colors are user data (G6 exception). The badge is HIDDEN
  inside a project's own Tasks tab, where it would be redundant.
- **Content width:** long-form/detail content is capped (`maxWidth` 720–760,
  centered) on wide screens; full-bleed lists cap via their own layout.

## 5. Accessibility checklist (per UI PR)

- [ ] Light + dark screenshots reviewed (no assumption from one theme).
- [ ] New color pairs verified ≥ 4.5:1 text / ≥ 3:1 icons-borders
      (script: `scripts/design/contrast.py`).
- [ ] Tap targets ≥ 44 px; icon buttons have `tooltip`; meaningful controls
      have semantic labels (`semanticLabel`, `Semantics`).
- [ ] Keyboard: focus visible (2 px ring on inputs, focus highlight on
      controls); tab order follows visual order.
- [ ] No color-only signaling; text truncation prefers wrap/ellipsis+tooltip.
- [ ] `flutter analyze` + `flutter test` green; existing widget-test keys
      (`Key('...')`) preserved.

## 6. How to extend the system

1. Need a new color? Add a slot to `AwTokens` (both palettes), verify both
   pairs with the contrast script, document it in §3.1.
2. Need a new component style? Theme it centrally in `theme.dart` if
   Material has a slot; otherwise add a reusable widget under
   `lib/src/widgets/` — never style one-off in a screen.
3. Deviating from a rule here requires updating this file + a line in the
   PR/commit explaining why (and an ADR if it changes the language itself).

## 7. Contrast verification

`scripts/design/contrast.py` re-checks every documented pair. Run:

```bash
python3 scripts/design/contrast.py
```

It must print `FAILURES: 0` before a palette change ships.
