# DESIGN — "AllisWell Glass" design system

> **This file is the single source of truth for how AllisWell looks and feels.**
> It is BINDING for every future UI change — web, mobile, desktop, all six
> Flutter targets. Visual consistency with this document is part of the
> Definition of Done (AGENTS.md hard rule 11). If a change needs to deviate,
> amend THIS file (and note why) in the same PR — never ship a one-off style.
>
> Established 2026-07-15 (design round 1, ADR-0005). **v2 "Liquid" refresh
> 2026-07-18 (design round 8, ADR-0012)** — researched against Apple's Liquid
> Glass guidance (HIG Materials, Adopting Liquid Glass; sources in the ADR).
> Code home: `apps/app/lib/src/theme/` (tokens + theme) and
> `apps/app/lib/src/widgets/` (glass surfaces, shared states).

## 1. Design language in one paragraph

Apple-2026 **Liquid Glass**, UX-first. Navigation floats in its own glass
layer above the content — a **capsule bottom bar** on phones, a **rounded
glass panel rail** on wide layouts — built from blur + a saturation boost
(color bleeds through vividly, never gray fog), a gradient **lensing edge**,
a specular top catchlight and a soft ambient shadow. Beneath it: a colorful
but calm **aurora wash** (azure/violet/mint blobs) and **solid,
high-contrast surfaces for everything users read or touch**. Geometry is
round and concentric (12–28 px, capsule controls), checkboxes are circular,
and the palette is vivid Apple-flavored: azure primary, indigo secondary,
saturated semantic hues — every pair contrast-verified. No decoration may
ever cost legibility: if glass and readability conflict, readability wins.

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
| primary | `#0A5CFF` | `#3E9BFF` | buttons, selection, FAB (vivid azure) |
| secondary | `#5A50E0` | `#B9AFFF` | selected chips, secondary accents (indigo) |
| onSurface | `#0F1B2E` | `#EAF0FD` | body text |
| onSurfaceVariant | `#44536F` | `#AAB6D6` | secondary text, icons |
| surface (cards) | `#FFFFFF` | `#151F3C` | list rows, cards, sheets |
| surfaceContainerHigh | `#E7EEFA` | `#1F2C51` | input fill |
| outline (input border) | `#63789E` | `#7186B5` | enabled input borders (≥3:1 vs fill) |
| error | `#D70015` | `#FF5147` | errors, overdue, destructive (Apple red) |
| tertiary | `#0C7D6C` | `#35D6C2` | calendar dots, positive accents (teal) |
| AwTokens.success | `#0D7A33` | `#30D158` | done states, switches-on (Apple green) |
| AwTokens.warning | `#C77700` | `#FFC400` | favorite/pin stars, medium priority |
| AwTokens.link | `#0B54D0` | `#3E9BFF` | text buttons, links |
| AwTokens.prioLow/Med/High/Urgent | `#0F9D46 #C77700 #E8500A #E3261A` | `#30D158 #FFC400 #FF8A1E #FF453A` | priority flags (vivid, ≥3:1) |
| AwTokens.hairline | `#0F1B2E` @ 8% | `#EAF0FD` @ 12% | decorative card borders, dividers |
| AwTokens.glassTint/Stroke/Highlight/Shadow | see file | see file | glass material (tint, lens edge, catchlight, float shadow) |
| AwTokens.aurora* / blobA·B·C / veil | see file | see file | background wash (azure/violet/mint blobs under a translucent veil) |

**Priority hues are fixed** (low=green, medium=amber, high=orange,
urgent=red) — only lightness adapts per theme, so meaning never shifts
(BLUEPRINT §12.4). Same idea applies to any future semantic color: one hue,
two verified lightnesses.

### 3.2 Shape, spacing, motion

- Radius scale `AwRadius` (v2 — rounder, concentric: a nested shape's radius
  ≈ parent radius − padding): **12** chips/badges · **16** inputs & list
  rows · **20** cards · **28** sheets/dialogs · **32 (pill)** floating
  chrome. Buttons are **capsules** (`StadiumBorder`); the FAB is a circle.
- Spacing `AwSpace`: 4-pt grid (4/8/12/16/20/24/32/48). No off-grid values.
- Motion `AwMotion`: fast 150 ms · base 220 ms · slow 320 ms.
- Glass material: `kAwGlassSigma = 22` blur + `kAwGlassSaturation = 1.55`
  saturation boost on the backdrop (only inside `GlassSurface`) — the boost
  is what keeps blurred color vivid instead of gray.

### 3.3 Typography

Platform system fonts on purpose (SF Pro on Apple, Roboto/Segoe elsewhere,
Roboto on web) — zero network fetch, native feel. Weights/tracking tuned in
`theme.dart`: headlines w700 with negative tracking, titles w600, labels
w600, body 16/1.5. Use `textTheme` roles; never ad-hoc `fontSize`.
Tabular figures for day numbers and timers.

## 4. Component rules (all themed centrally in `theme.dart`)

- **Lists** are inset grouped cards: each row is a `Card` (radius 20,
  hairline border, solid surface) with 6 px vertical rhythm inside
  `awListPadding(context)` (clears glass bars + FAB). No full-width
  divider lists.
- **Checkboxes are circular** (Apple Reminders style); checked fill =
  `AwTokens.success`. **Switches read as iOS**: `AwTokens.success` track
  when on, near-white knob.
- **Buttons are capsules** (`StadiumBorder`, min height 48): `FilledButton`
  = the one primary action per screen; `FilledButton` with error colors for
  destructive confirms; `OutlinedButton` secondary; `TextButton`
  tertiary/links. The FAB is a solid-primary **circle** (solid fills on
  glass, per Apple guidance — glass is never stacked on glass).
- **Sheets:** modal bottom sheets with drag handle (theme default), top
  radius 28, `maxWidth 560` on wide screens, solid `surfaceContainerLow`.
  Tappable rows inside sheets get a filled `surfaceContainerHigh` backdrop +
  chevron affordance (see `_SheetTile` in `task_create_sheet.dart`).
- **Dialogs:** radius 28, solid, destructive action = error-colored
  `FilledButton`, cancel always present (escape route).
- **Empty/error states:** use `AwEmptyState` / `AwErrorState`
  (`widgets/status_views.dart`) — icon badge, title, guidance, and for
  errors ALWAYS a Retry action. Inline form errors use `AwInlineError`
  (icon + errorContainer band above the submit button).
- **Navigation floats** (Liquid Glass functional layer, v2): on phones
  (<800 px) the `NavigationBar` lives in a **floating glass capsule**
  (`GlassSurface(floating: true, radius: AwRadius.pill)`, 12 px side/bottom
  margins, `extendBody: true` so content scrolls and peeks beneath it); on
  wide layouts (≥800 px) the `NavigationRail` lives in a **floating glass
  panel** (radius 28, 12 px margins). Floating glass = blur + saturation
  boost + gradient lensing edge + specular catchlight + soft `glassShadow`.
  Selected item = primaryContainer pill; labels always visible. Glass is
  chrome-only (G1) — never under body text, never glass-on-glass.
- **App bars:** transparent over the wash, title left, `titleLarge` w700,
  no elevation/tint.
- **Backgrounds:** `AuroraBackground` is painted ONCE in `app.dart`
  (`MaterialApp.builder`); scaffolds use the translucent `veil` token.
  Never stack another wash inside a screen.
- **Overdue** dates render in `error` color w600 with the word "Overdue".
- **Stars (favorite/pin)** use `AwTokens.warning`, never `Colors.amber`.
- **Project badge (task rows — added 2026-07-17, feedback round 4, OPH-104):**
  a FILLED pill in the project's color, rightmost element of the row's
  trailing cluster. Radius `AwRadius.s`, padding 8×2, `labelSmall` w600,
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
      Generator: `cd apps/app && flutter test --update-goldens
      --dart-define=screenshots=true test/design_screenshots_test.dart`
      → PNGs in `apps/app/test/goldens/` (real fonts, real shadows,
      phone + desktop, both themes; skipped in CI without the define).
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

## 8. Widget design (home-screen / desktop — Epic 12)

_(Added 2026-07-17, feedback round 5. Full plan: [WIDGETS.md](WIDGETS.md);
decision [ADR-0010](adr/0010-home-screen-widgets-architecture.md).)_

Widgets render in **native views** (SwiftUI on Apple, Jetpack Glance on Android),
NOT Flutter — so they can't consume `AwTokens`/`theme.dart` directly. They must
still *read as AllisWell*. Rules:

- **W1 — Token parity, not token reuse.** Mirror the DESIGN §3.1 palette as a
  small native constant table (light + dark), keyed by the same roles
  (`primary`, `onSurface`, `surface`, `error`, `success`, priority hues). One
  source of truth in spirit; when a token moves, the widget table moves in the
  same change.
- **W2 — Contrast floors still apply** (G2): text ≥ 4.5:1, icons/borders ≥ 3:1,
  in light AND dark. The OS switches the widget's appearance — provide both.
- **W3 — No fake glass.** A widget can't blur live content behind it. Use a
  **solid tinted card** that evokes the aurora (a subtle vertical wash), never a
  translucent panel. Respect the OS `containerBackground` on iOS 26 so the system
  themes it.
- **W4 — Circular checkbox, same as the app** (§4): completing animates the row
  away after ~1–2 s. Hit target ≥ 44 pt and **generous** — the stock Reminders
  widget's biggest complaint is accidental completion.
- **W5 — Project color = data (G6 exception).** The row's project dot/badge uses
  the user's color; compute readable ink over it with the SAME luminance rule as
  the "Project badge" (§4) so it stays ≥ 4.5:1.
- **W6 — Date header** (large/extraLarge): weekday **name** + big **day number**,
  tabular figures, mirroring the Apple-Calendar reference and DESIGN §3.3.
- **W7 — Density per size** (WIDGETS.md §5): 4×2 = header + 3–4 rows, no bucket
  labels; 4×4 = bucketed scroll ~8–10 rows + labels/counts; extraLarge/4×6 =
  richest, optional week strip. Truncate with an honest "+N more", never silently.
- **W8 — Both themes + all sizes reviewed** before ship, on device (the native
  layer isn't covered by `flutter test`).

## 9. Localization & text (Epic 11)

_(Added 2026-07-17, feedback round 5 — [ADR-0009](adr/0009-localization-i18n-architecture.md).)_

- **L1 — No hardcoded user-facing strings.** Every label comes from the i18n
  facade (`lib/src/i18n/`); a CI grep guards against raw `Text('literal')`.
- **L2 — Layouts survive text expansion.** Turkish/German strings run longer than
  English — never assume a fixed width; prefer wrap or ellipsis + tooltip (already
  the §4 badge rule). Check the longest supported locale, not just `en`.
- **L3 — Tabular figures + locale-aware dates.** Numbers/dates format through the
  active locale (`intl`); day/month names come localized.
- **L4 — RTL is v1-out-of-scope but not precluded.** en + tr are LTR; don't bake
  in `EdgeInsets.only(left:)` where `.start`/`.end` (directional) is meant, so an
  RTL locale can drop in later without a layout rewrite.
- **L5 — Bottom-bar labels stay short (~≤10 chars, ideally one word).** The phone
  `NavigationBar` bolds the selected label (w700); a long label wraps to two lines
  and breaks the bar (feedback round 6: TR "Gelen Kutusu" wrapped when selected →
  renamed "Fikirler"). Every locale must pick tab labels that fit one line at
  `labelMedium` w700 on a five-tab 390 px bar.

## 10. Files & attachments (Epic 14)

_(Added 2026-07-18, feedback round 7 — [ATTACHMENTS.md](ATTACHMENTS.md),
[ADR-0011](adr/0011-attachments-r2-s3-storage.md).)_

- **F1 — One file row, three homes.** Task attachments, note attachments and the
  project Files tab all render the SAME row anatomy: leading 40 px square —
  image thumbnail (rounded `AwRadius.s`, `BoxFit.cover`) or a kind icon on a
  soft `surfaceContainerHighest` tile (video → `movie`, audio → `audiotrack`,
  archive → `folder_zip`, else `insert_drive_file`) — then filename (1 line,
  ellipsis), then a `size · date` subtitle in `onSurfaceVariant`. `Card` +
  `ListTile`, `awListPadding` lists, tap targets ≥ 44 px — the §4 card-row
  idiom, no new shapes.
- **F2 — Uploads are visible state, not chrome.** An uploading row shows a
  determinate `LinearProgressIndicator` under the subtitle + a cancel action.
  Failure flips the row to the inline-error treatment (`AwInlineError` colors)
  with a retry — never a silent disappearance (G-honesty).
- **F3 — Previews stay honest offline.** Metadata is local; bytes are not. An
  image that can't fetch renders a placeholder tile (kind icon + filename), not
  a broken-image glyph, not an endless shimmer. Shimmer only while a fetch is
  actually in flight.
- **F4 — Source badges on the Files tab.** Aggregated rows carry a small badge
  naming their origin (Project / task title / note title) with the same
  luminance-ink rule as the Project badge (§4) when tinted by project color.
- **F5 — Destructive = confirm.** Delete always confirms with the filename in
  the dialog (`AlertDialog`, error-colored action); rename uses the standard
  modal sheet with a prefilled `TextField`.
- **F6 — No raw storage talk in UI.** Users see filenames, sizes (`KB/MB`,
  locale-formatted) and dates — never storage keys, presigned URLs, bucket or
  MIME strings. Configuration problems speak product language ("File storage
  isn't set up on this server") with a docs pointer, in an `AwEmptyState`.

## 11. Alarm surfaces (Epic 13 — OPH-143)

The urgent alarm has two in-app surfaces. Both obey rule G1 (glass is
chrome-only): the ring screen is a **solid** takeover, never live glass under
its text.

- **A1 — Ring screen = solid takeover, urgency-colored.** When an urgent alarm
  is due while the app is open, `AlarmRingScreen` fills the shell (above the
  onboarding tour). Background is `surface` with a faint `prioUrgent` wash
  (`Color.alphaBlend`, ~10% — never a saturated red field under text); the
  pulsing ring, the `label` and the primary button carry the urgency. Ink stays
  `onSurface`/`onSurfaceVariant` for ≥ 4.5:1. The primary "Onayla" uses the
  Material `error`/`onError` pair (contrast-guaranteed); snooze presets are
  `OutlinedButton` capsules, secondary actions are `TextButton`s. Radii/spacing
  from tokens; the pulse uses an `AnimationController` (repeat), so ring tests
  drive it with `pump()`, never `pumpAndSettle`.
- **A2 — It must be answered, not dismissed.** `PopScope(canPop:false)`: system
  back/ESC does nothing; only Onayla / snooze / complete / open clears it. This
  is the product's "insistent, must be acknowledged" rule (BLUEPRINT §8.2) made
  visual.
- **A3 — Insistence is a seam.** Physical alerting (`AlarmFeedback`) is
  injected: `HapticAlarmFeedback` (a haptic pulse loop) in production, silence
  in tests. A looping audio bed is a follow-up behind the same seam — on mobile
  the OS notification already carries it (OPH-139); desktop/web are best-effort
  (NOTIFICATIONS.md §3).
- **A4 — Degradation banner is honest, at the top of Home.** When the OS can't
  ring reliably, `AlarmDegradationBanner` says so on `errorContainer`
  (`onErrorContainer` ink, `alarm_off` icon, radius `m`) with a one-tap fix —
  worst-problem-first (notifications off → exact-alarm denied), the same cascade
  as the Settings status row (OPH-139). Healthy delivery shows nothing: never
  nag a user whose alarms already work.
