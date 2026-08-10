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
>
> **Rev. 2026-07-27 (feedback round 9, Epic 16):** §11 A3 rewritten (the alarm
> ring screen must MAKE SOUND) + A5/A6 added (mute state, alarm log); new
> §15 pull-to-refresh, §16 Home scroll layering, §17 date & time display,
> §18 reminder system settings.
>
> **Rev. 2026-07-28 (feedback round 10, Epic 17):** §4 "Backgrounds" **changed**
> (a route is opaque to the route beneath it — the old single-wash rule shipped
> the transition ghosting bug) and §8 W6 tightened + W9 added (widget date header
> + today's open count); §17 D5 added (one date *input* path — editing must not
> rewrite the time), §18 N6 extended (a preview must be stoppable, and every
> choosable sound is previewable); new **§19 destructive actions & swipe to
> delete**, **§20 completed work**, **§21 screen transitions**, **§22
> reachability**.

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
- **Backgrounds** _(rev. 2026-07-28, feedback round 10 #10 — OPH-194; this rule
  changed, see §21):_ every route paints its **own opaque backing** (aurora +
  `veil`, composited by the shared `AwPageBackground`). The wash still appears
  exactly once per screen — never stack a second one inside a screen — but it is
  **no longer painted below the Navigator**. The old rule (one `AuroraBackground`
  in `MaterialApp.builder` + translucent `veil` scaffolds) shipped a visible bug:
  the veil is ~50 % opaque, so during any push/pop the outgoing route showed
  through the incoming one and read as a stuck, ghosting screen. **A route must
  never be see-through to the route beneath it.**
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
  _(Rev. 2026-07-28, feedback round 10 #4A/#4B — OPH-187:)_ the day number and the
  weekday/month stack are **optically centred on each other**, not baseline-aligned:
  aligning a 34 pt number's baseline to a 14 pt label's baseline leaves the month
  line hanging below and reads as a typo. **iOS and Android must draw this header
  identically** (W1's parity rule applied to layout, not just color) — the two
  platforms disagreed for a whole release because nobody compared them side by side.
  The header's right edge carries **today's open count** (see W9); at 0 the badge
  is hidden, because a badge reading "0" is noise, not information.
- **W9 — One number, and it is the honest one.** The count next to the date is
  "what is on me today" = **overdue + due today**, including snoozed and muted
  tasks (they are still open work). Dateless tasks are excluded — they belong to
  every day, so they would inflate every day. The number is computed in the Dart
  snapshot (pure + unit-tested), never in native code, and its label ships
  pre-localized in `strings` like every other widget word.
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

_(Rules F7…F9 added 2026-07-20, feedback round 8 — the global Files section,
[ADR-0014](adr/0014-folders-and-global-files.md).)_

- **F7 — One anatomy everywhere, including the global manager.** The Files
  section reuses F1 rows and F5 confirmations verbatim. Its two layers are
  visually distinct but structurally identical lists: **Klasörlerim** (user
  folders + workspace files) and **Kaynaklar** (attached files with F4 source
  badges + a "go to source" affordance). No second file-row design exists.
- **F8 — Folders are rows, location is a breadcrumb.** A folder row = leading
  `folder` icon on the same soft tile as F1 kind icons + name + "N öğe" count
  subtitle; tap descends, the current path renders as a breadcrumb line under
  the header (root = "Dosyalar"). Moving uses an explicit target-picker sheet
  (folder tree, current location disabled) — drag-to-move is desktop sugar for
  v2, never the only path (same fallback philosophy as K3).
- **F9 — Deleting a folder states its blast radius.** The confirm dialog names
  the folder AND counts what dies with it ("3 klasör, 12 dosya silinecek") —
  an F5 extension; empty folders still confirm but say "boş klasör". Cascades
  must never surprise (G-honesty).

## 12. Search (round 8 — OPH-167)

_(Added 2026-07-20; engine architecture in
[ADR-0013](adr/0013-local-first-search.md). Search is a per-screen capability
— BLUEPRINT §12.10 — not a separate destination.)_

- **S1 — One search field pattern.** A body-level `TextField` under the app
  bar (the Notes screen shape): `search` prefix icon, clear (×) suffix when
  non-empty, `AwRadius.m` filled field, placed above the screen's filter chips
  and combining with them (AND). Never inside the glass app bar (G1 — glass is
  chrome, fields are content). One shared widget serves Home, Notes, Projects.
- **S2 — Folding is a product promise.** Case- and Turkish-diacritic-
  insensitive matching everywhere (`ı/i/İ/I`, `ü/u`, `ö/o`, `ş/s`, `ç/c`,
  `ğ/g`), via the single shared fold utility — a screen must never ship its own
  matcher. Multi-word queries AND their words, order-free.
- **S3 — Ranked tiers, honest match context.** Results order: title match >
  tag match > body/description match (stable within tiers by the screen's
  normal sort). When the hit is not in the title, the row's secondary line
  shows WHERE it hit: a body snippet with the matched word emphasized
  (`onSurface` w600 on the match, `onSurfaceVariant` around it) or the matched
  `#tag`. Rows themselves stay the screen's normal rows — search restyles
  nothing.
- **S4 — Loading only when it's real.** Results update as you type (debounce
  ~250 ms). A progress row appears only if the query takes ≥ 150 ms — no
  spinner flash on every keystroke. Zero hits = `AwEmptyState` ("'x' için
  sonuç yok") with a clear-search action; never a blank void.
- **S5 — Search never mutates state.** Entering/leaving search changes no
  filter, selection or view preference; clearing restores the exact prior
  list. External events surface as their normal read-only rows (§4) — search
  grants no new powers over them.

## 13. Tag input (round 8 — OPH-165)

_(Added 2026-07-20. The chip-input lives in the task create sheet and the task
detail Tags card — BLUEPRINT §12.4.)_

- **T1 — Type, commit, chip.** Tab / Enter / comma commits the typed text as a
  chip; the field clears and keeps focus (the quick-add serial-entry DNA).
  Chips render `#ad` with the tag's color as a leading dot (same dot idiom as
  project pickers — hex never shown), delete-× on each chip, ≥ 44 px targets.
- **T2 — Suggest first, create honestly.** While typing, existing tags match
  fold-insensitively (S2) in a suggestion row under the field; the exact-match
  suggestion is highlighted. If nothing matches, the first suggestion reads
  **"Oluştur: #ad"** — creation is explicit-but-frictionless (one tap / plain
  Enter), never a silent side effect the user can't see.
- **T3 — '#' is presentation.** Names are stored bare; a typed leading '#' is
  swallowed on commit. Tags keep their `colorRgb` (default neutral); recolor/
  rename/delete live in a "Etiketleri yönet" sheet (name field + the standard
  palette picker + delete with F5-style confirm naming affected task count).
- **T4 — Same component, both surfaces.** The create sheet and the detail card
  mount the identical widget — no divergent tag UIs. In lists, task rows show
  at most 2 tag chips + "+N" overflow (tooltip lists the rest); chips never
  wrap a list row taller than its card rhythm.

## 14. Kanban board (round 8 — OPH-168)

_(Added 2026-07-20. Interaction model synthesized from Trello/Jira/GitHub
mobile patterns and NN/g drag-and-drop guidance — sources in the OPH-168 task
entry; product decisions in BLUEPRINT §12.11.)_

- **K1 — The board is a view, not a place.** Home's Liste | Pano segmented
  toggle sits at the top; the choice is device-local and persistent. Board
  columns = task statuses, rendered with the §4 card language (columns are
  `surfaceContainer` wells at `AwRadius.l`; cards are the task-row DNA:
  status icon, priority flag, project badge, due).
- **K2 — Columns belong to the user.** "Görünümü düzenle" (app-bar action)
  opens a sheet with visibility toggles + drag-reorder of statuses; hidden
  columns stay reachable as move targets (K3). Default visible: open,
  in_progress, waiting, completed. Column headers pin name + count while the
  column scrolls.
- **K3 — Two coequal move paths, always.** (a) Drag: desktop/web full
  multi-column drag; phone long-press (~200 ms, haptic on lift) — feedback is
  the card scaled ~1.04 at ~85% opacity, origin dims to a placeholder; the
  WHOLE column body is the drop target (no precise slot demanded). (b) The
  sheet: tap card → detail, or long-press-release-in-place → context menu →
  "Durum değiştir" bottom sheet (all statuses, current checked, hidden ones
  included). The sheet path is the accessibility contract — every move must be
  completable with taps alone; drag is never the only way.
- **K4 — Phone = pager with a peek.** One column ≈ 90% viewport width so the
  neighbor peeks (~10%) as the "there's more" cue; a subtle "2/5" position
  label under the header, dots secondary. While dragging, hovering a screen
  edge (~48 dp zone, tinted `primary` at ~8%) for ~400 ms advances one column;
  vertical auto-scroll near column ends. Framework primitives only
  (`PageView` + `LongPressDraggable`/`DragTarget` + `EdgeDraggingAutoScroller`).
- **K5 — Drops are honest and reversible.** Drop = optimistic status change +
  snackbar with "Geri al"; a polite semantics announcement ("'X' → 'Yapılıyor'")
  fires for screen readers. If the drag can't complete (gesture eaten, sort
  active), the card snaps home visibly — never a silent no-op.
- **K6 — Empty columns stay alive.** An empty visible column renders a dashed
  `outlineVariant` placeholder well ("Buraya sürükleyin" while a drag is live,
  else a "+ Görev ekle" affordance that opens the create sheet with that
  status preset). Zero-height columns don't exist (drop targets must stay
  droppable).

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
- **A3 — Insistence is a seam, and it MUST include sound (shipped round 9,
  OPH-180).** Physical alerting (`AlarmFeedback`) is injected: production plays
  a **looping audio bed + haptic pulse** (`AudioAlarmFeedback`), tests inject
  silence. Round 9's device report proved the haptic-only version wrong: while
  the app is open the ring screen was the loudest surface the user had, and it
  made no sound at all. The bed uses the user's chosen alarm sound (§18 N6) and
  the iOS `.playback` audio session so it is audible with the mute switch on
  **while the app is in the foreground** — never a background audio session
  (NOTIFICATIONS.md §2b rejects that trick). On web, autoplay may be blocked:
  degrade to visual + haptic and offer an explicit "start sound" button — never
  pretend it rang.
- **A4 — Degradation banner is honest, at the top of Home.** When the OS can't
  ring reliably, `AlarmDegradationBanner` says so on `errorContainer`
  (`onErrorContainer` ink, `alarm_off` icon, radius `m`) with a one-tap fix —
  worst-problem-first (notifications off → exact-alarm denied), the same cascade
  as the Settings status row (OPH-139). Healthy delivery shows nothing: never
  nag a user whose alarms already work.
- **A5 — Silencing is a state, not a disappearance (round 9, OPH-178).** An
  alarm the user muted indefinitely ("Süresiz ertele") must keep saying so: the
  task row carries a `notifications_off` chip with a one-tap "Geri aç", the
  detail screen a switch, and the task stays **open** — muting is never
  completing. Same rule for a snoozed alarm: the row says "Ertelendi — 22:52"
  (OPH-177). An armed-looking task whose alarm is dead is the worst possible lie
  in this product.
- **A6 — The alarm log is a plain, honest list (round 9, OPH-176).** Settings →
  "Alarm günlüğü" renders the local ring buffer as read-only rows (instant,
  lane, slot, sound) plus one sentence of scope: iOS reports no "delivered"
  event for an untouched notification, so the log shows what was **scheduled**,
  what the user **interacted** with, and what rang **in-app** — it never claims
  delivery it cannot observe. Copy-to-clipboard, no charts: this surface exists
  to make the next device round evidence-based.

## 15. Pull to refresh (round 9 — OPH-171)

_(Added 2026-07-27. Round 9 #1: "Home, Fikirler, Projeler, Notlar, Dosyalar —
hepsinde aşağı çekip yenileme istiyorum.")_

- **R1 — One indicator, one place: between the pinned filters and the list.**
  A single `AwRefresh` wrapper (`widgets/refreshable.dart`) wraps the screen's
  **scrollable**, never the whole body — so the spinner is born under whatever
  stays pinned (filter chips, segmented buttons) and above the first row, which
  is exactly where the user looks. Track color `colorScheme.primary` on
  `surfaceContainerHigh`, no shadow, no glass (G1: this is content chrome, and
  it sits over content).
- **R2 — Never blink.** The replica answers in milliseconds; a spinner that
  appears and vanishes reads as "nothing happened". The gesture holds the
  indicator for a **minimum ~450 ms**, then slides up. That is the whole
  animation contract: pull → spin in place → release → slide up.
- **R3 — Refresh means "sync now", per screen.** `syncNow()` plus the screen's
  own external truth (Home: calendar events + alarm permission probe; Dosyalar:
  storage status). It never re-mounts the list, never scrolls it, never clears a
  filter or a search query (the S5 rule for search applies here too).
- **R4 — Failure is a snackbar, not an empty screen.** A failed refresh leaves
  the visible data exactly as it was and says why (`localizedError`). Offline is
  not an error state in a local-first app.
- **R5 — Pointer-only platforms get a button.** The wheel does not overscroll,
  so on wide layouts (≥800 px) the section app bar carries a `refresh` action.
  Same capability everywhere, expressed in each platform's idiom — never a phone
  gesture the desktop user cannot perform.

## 16. Home's scroll layering (round 9 — OPH-172)

_(Added 2026-07-27. Round 9 #2 — the OPH-103 philosophy taken to its end:
"sabit kalıp yukarıda listeyi daraltmamalı".)_

- **H1 — On phones, exactly one thing is pinned: the app bar.** The section
  title and the settings button stay; **everything else scrolls** — the
  degradation banner, the Liste | Pano toggle, the quick-add field, the search
  field, the month calendar and the calendar toggle are all slivers of the one
  `home-scroll` view, in that order. Chrome does not get to eat a phone screen
  it is not currently earning. _Rev. 2026-07-29 (round 12 #5 — OPH-213): the
  view toggle and the calendar show/hide leave the scroll entirely — they become
  **app-bar icons** (the Notes pattern), placed left of settings, on phones and
  wide layouts alike. The sliver order becomes: banner, quick-add, search, month
  calendar. H1 gets stronger: the app bar earns its pin by carrying the view
  controls._
- **H2 — Wide layouts are unchanged.** ≥720 px keeps the calendar side panel and
  its own column; the complaint (and the fix) is about the phone.
- **H3 — A view switch that scrolls away must still be reachable (deliberate
  deviation).** In **Pano** the board is a horizontal pager filling the
  viewport, so the Liste | Pano row stays pinned there — scrolling it away
  would strand the user in the board with no way back. List mode scrolls it.
  _Rev. 2026-07-29 (OPH-213): dissolved — the switch now lives in the
  always-pinned app bar, so there is nothing left for this deviation to
  protect._
- **H4 — A scrolling text field keeps its text.** Quick-add's controller lives
  in the parent (a sliver scrolled past the cache extent is disposed), and
  focusing it scrolls it back into view (`Scrollable.ensureVisible`). Typed text
  surviving a scroll is a correctness requirement, not a nicety.

## 17. Date & time display (round 9 — OPH-174)

_(Added 2026-07-27. Round 9 #5: "format 31.12.2026 23:59 olacak … hatta
ayarlardan kullanıcı seçebilecek".)_

- **D1 — One formatter, no exceptions.** Every user-visible instant goes through
  `core/date_format.dart`. `DateTime.toString()` in UI is a bug (round 9 found
  "2026-07-31 23:59:00" in two sheets); hand-rolled `padLeft` formats are a bug
  too — they cannot follow a preference or a locale.
- **D2 — The setting shows results, never patterns.** The picker lists the same
  sample instant rendered in each option (31.12.2026 23:59 · 31/12/2026 23:59 ·
  31 Aralık 2026 23:59 …). A user never sees `dd.MM.yyyy` — the round-1 rule
  (no technical concepts in end-user UI) applies to format strings exactly as it
  applies to hex codes.
- **D3 — "System" is the default and it is honest.** Factory setting follows the
  app language (tr → 31.12.2026 23:59, en → 12/31/2026 11:59 PM). An explicit
  pick overrides it everywhere — including the home-screen widget snapshot, or
  the widget and the app would disagree in front of the user.
- **D4 — Rows stay short.** List rows use the short form (no year inside the
  current year, time always 24h/12h per the chosen format); detail rows and
  pickers use the full form. Same source, two lengths.
- **D5 — One date *input* path, the way there is one date *formatter*** _(added
  2026-07-28, feedback round 10 #6 — OPH-191):_ any field that STORES a time must
  ASK for a time. Task date fields call the shared `awPickDateTime`
  (`core/date_input.dart`): date picker → time picker; an empty field opens on
  tomorrow (OPH-173); backing out of the DATE step changes nothing, while
  dismissing only the CLOCK is not a cancel — the day was chosen, so the time
  falls back to **the existing value first**, then the user's default task time
  (OPH-161). That fallback order is the fix itself: round 10 found the create
  sheet asking for date+time while the detail screen asked for a date and then
  stamped the default on it, **silently rewriting 14:30 to 23:59**. The same
  field, two behaviours, and the destructive one was invisible. **Editing a value
  must never change a part of it the user did not touch.** The rule is what is
  shared, not necessarily the function: the alarm ring screen's custom snooze
  keeps its own picker because its constraints differ (no past instants, "+30
  min" default) — it already asks for a time, which is what D5 requires.

## 18. Reminder system settings (round 9 — OPH-179 / OPH-181)

_(Added 2026-07-27. Round 9 #7: "kaç hatırlatıcı gelecek, sıklığı, zil sesi —
kurumsal, adım adım tasarlanabilir bir alan".)_

- **N1 — One destination: Settings → "Hatırlatıcı Sistemi Ayarları".** Chain,
  sounds, snooze presets and the alarm log live behind one row, not scattered
  across the settings list. Reachable from the alarm status row too (the user
  who just found a problem is already looking there).
- **N2 — Presets first, steps second.** Sakin (1 step) · Standart (5) · Israrcı
  (10) as segmented choices; the step editor is the escape hatch, pre-filled
  from the chosen preset. Most users must never touch a stepper.
- **N3 — The chain is a step list, and it says when each step rings.** Each row
  is "N. hatırlatma · +M dakika" with a minute stepper, delete, and "araya adım
  ekle". Above it, a live timeline in the user's own date format
  ("22:42 → 22:44 → 22:47 → 22:52") — the answer to "5 dk sonra ne olacak?" is
  visible before it is experienced.
- **N4 — No drag where drag is a lie (deliberate deviation).** The chain is
  sorted by definition, so dragging step 3 above step 1 would be undone
  instantly; the editor does not offer it (NN/g: never offer a gesture whose
  result the system immediately reverses). Drag-to-reorder IS offered where
  order is the user's to choose: the **snooze presets** shown on the alarm.
- **N5 — Limits are stated, never enforced silently.** Minimum 1 minute between
  steps (the user's own anti-collision rule) shown inline when violated; max 20
  steps; and the live OS-capacity line ("bu profille aynı anda ~N alarm tam
  kapsanır" — iOS keeps only the soonest 64 pending). A silently trimmed chain
  would look like the product losing alarms.
- **N6 — Sounds are chosen by hearing them.** Alarm sound and reminder sound are
  separate rows, each with a preview play button, bundled options first, then the
  workspace's uploaded ringtones. Upload says up front what a file can be used
  for (≤30 s + caf/wav/aiff for OS notifications; anything else can still serve
  the in-app bed) — an unusable file is refused with a reason at upload time,
  not by silence at alarm time.
  _(Rev. 2026-07-28, feedback round 10 #5 — OPH-190:)_ **hearing it means being
  able to stop it.** Three rules, each one a defect round 10 hit: a preview MUST
  be stoppable by the control that offers it — **a control always does what its
  icon says**, and an icon showing "stop" while `onPressed` is null is a lie;
  tapping another sound MUST switch immediately rather than queue behind the
  first (one preview may never disable the others); and leaving the screen MUST
  silence it — audio that outlives the surface that started it is the one outcome
  this section forbids. That last one has a mechanical consequence worth stating:
  the auto-stop is a **cancellable timer**, never an awaited delay, or it keeps
  running after the preview it belongs to is gone. **Every sound the user can
  choose is previewable, including their own uploads** — a library you can only
  audition half of is not a library.
- **N7 — The whole area obeys the alarm-honesty rules.** Every claim here is
  checked against what the OS actually allows (§11 A4/A6): a profile the device
  cannot deliver exactly, a sound iOS cannot resolve, or a mute switch that will
  silence the lane must be said in words, on this screen.

## 19. Destructive actions & swipe to delete (round 10 — OPH-184)

_(Added 2026-07-28. Round 10 #1: "Task silme? Yok. Sağa kaydırma, listeden ya da
detayın en altında — ikisinde de olmalı … ayrıca eklemesi düzenlemesi olan ama
silinmesi unutulmuş başka bişey var mı, iyice bakılması lazım".)_

The audit that produced this section found the delete **engine** complete —
optimistic local delete, outbox mutation, server subtree tombstone, attachment
cascade, reminder reconcile — and **no button anywhere on a task row**. That is
the failure mode this section exists to prevent: a capability nobody can reach is
not a shipped capability.

- **D1 — Every list row that can be created can be deleted, from the list.**
  Reaching a detail screen to delete is a fallback, not the path. Deletion is
  offered by a **swipe from the trailing edge that half-opens and waits** — the
  Apple idiom the user described: the swipe reveals a `Sil` button, and the
  button is what deletes. A single fling must not destroy anything.
- **D2 — Gestures are never the only way.** Every swipe action also exists as a
  visible control: the row's overflow menu, the detail screen's app-bar action,
  or a long-press equivalent. Mice do not swipe (the §15 R5 lesson) and neither
  do switch-control users. A destructive action reachable **only** by gesture is
  an accessibility defect, not a design choice.
- **D3 — Two grades of confirmation, chosen by consequence.** A leaf delete
  (task, note) uses **no dialog**: the row leaves and an **Undo** snackbar takes
  its place. A delete that **cascades or cannot be reasoned about from the row**
  (project, folder, tag) keeps its confirmation dialog, because the cascade
  question must never be skipped (the OPH-110 rule generalized).
- **D4 — Undo is real, not cosmetic.** "Undo" means the mutation has not
  happened yet: the row is hidden optimistically and the actual delete commits
  when the snackbar closes or the screen is left. If the app dies in between,
  **nothing was deleted** — the safe direction. An "Undo" that must re-create the
  record is not offered, because it cannot restore identity.
- **D5 — Destructive visuals are the error role, everywhere.** The revealed
  action pane uses `colorScheme.error` / `onError`, the confirm button is the
  error-colored `FilledButton` of §4, and both are contrast-checked in light and
  dark like any other surface.
- **D6 — Deliberate exception: horizontally paged surfaces.** Board cards live
  inside a horizontal `PageView` that owns the horizontal gesture; a swipe action
  there would either fight the pager or kill the way back to the List. The board
  offers delete in the card's status sheet instead — stated here so the gap is a
  decision, not an oversight.

## 20. Completed work: it stays, then it moves (round 10 — OPH-185 / OPH-186)

_(Added 2026-07-28. Round 10 #2 and #3: "tamamlandı olarak işaretlediğimde
kayboluyor — hayır, aynı gün içinde aynı gününde gözükmeli … tüm tamamlananları
bir yerden görmek gibi bişey olabilmeli".)_

- **C1 — Completing is feedback, not disappearance.** A task completed today
  stays in its own group for the rest of the local day, sorted to the **end** of
  that group. Vanishing at the instant of the tap makes the user doubt what they
  just did, removes the only natural undo (tap it again) and hides the day's
  progress. At the next local midnight it leaves the planning lists.
  _Rev. 2026-07-29 (round 12 #3 — OPH-211): the stay applies **only when the
  task's due date is today, or it has none**. An overdue task completed today
  leaves the planning lists immediately — "Geciken" holding a struck-through row
  says nothing ("the task was late, and now it is done" is the archive's
  sentence, not the planner's). Its address is §C4 from the moment of the tap._
- **C2 — Done work is quiet, not dead.** The whole row calms down together:
  `surfaceContainerLow` card, struck-through title in `onSurfaceVariant`, muted
  date/subtitle, and the alarm chips (urgent marker, snoozed, muted) **removed** —
  a finished task has no alarms, so showing them would be a false claim (§11 A5),
  not just noise. The check circle keeps its **full-strength** `success` fill:
  muting it toward the surface was measured and drops the check glyph to ~2.3:1,
  under the §5 floor. The calm comes from the row, not from weakening the one
  mark that says "done" — which is also how Apple Reminders reads.
- **C3 — Calm is built from tokens, never from `Opacity`.** An opacity wrapper
  makes contrast unmeasurable and silently voids the §5 floors (≥ 4.5:1 text,
  ≥ 3:1 icons). Every muted value is an explicit token pair that `contrast.py`
  checks — the completed row contributes eight of them (title/body ink and the
  success fill + its glyph, in both themes). The completed treatment must also
  stay visually distinct from the selected-day `dimmed` treatment — two
  different meanings may not share one look.
- **C4 — Yesterday's work has an address.** Everything completed lives in
  **Settings → Tamamlananlar**: a reverse-chronological timeline, day-headed,
  paged as the user scrolls, sorted by **the task's own date when it has one and
  by its completion time when it does not**. It reads from the local replica —
  the data is already there, and an archive that needs the network is an archive
  you cannot trust. Its scope is stated above the data (v1: `completed` only),
  the way the alarm log states its own.
- **C5 — The widget agrees with the app.** The same day-long persistence and the
  same muted row apply to the home-screen widget (§8 W6/W9). A task the app shows
  as done today and the widget shows as gone is the contradiction §17 D3 already
  rules out for dates.

## 21. Screen transitions (round 10 — OPH-194)

_(Added 2026-07-28. Round 10 #10: "sola doğru kayarak başka sayfaya geçerken
önceki sayfanın silueti kalıyor, 1 sn sonra siliniyor — donma takılma gibi
duruyor". It was not a performance problem; it was this design system's own
background rule.)_

- **T1 — A route is opaque to the route beneath it.** During a push or pop both
  routes are mounted; if the incoming screen's background is translucent, the
  outgoing screen shows through it and reads as lag. Screen backgrounds are
  therefore composited **per route** (§4 "Backgrounds"), not inherited from a
  single wash under the Navigator. This is testable and must be tested: pump a
  transition halfway and assert the outgoing screen's content is **not** on
  screen.
- **T2 — One transition family, all platforms.** `pageTransitionsTheme` is set
  explicitly, at `AwMotion.base` (220 ms). Leaving it unset means Android gets
  Zoom, iOS gets a Cupertino slide and desktop gets a third thing — three
  different products wearing one design system. Reduced-motion settings are
  respected.
- **T3 — Tabs are not a stack.** Switching sections in the shell
  (`StatefulShellRoute.indexedStack`) is instant and animation-free; sections are
  places, not pages you travel between (OPH-108). Only pushed routes — detail,
  settings, editor — animate.
- **T4 — Glass is measured during motion, not only at rest.** `BackdropFilter`
  samples whatever is painted behind it, so a transition is where blur costs the
  most and where it can sample the wrong thing. Any change to the glass chrome or
  the background composition is profiled mid-transition on a real device.

## 22. Reachability: the rule this round exists because of

_(Added 2026-07-28, feedback round 10 #9.)_

**A field in the schema, a method on the store or an endpoint on the server is
not a feature until a person can reach it.** Round 10 was mostly not about
missing code: task deletion, subtasks (`parent_task_id`, cascading server-side),
manual ordering (`sort_order`), task color (`color_rgb`) and widget
interactivity were all built, wired and tested at the layers below the UI — and
invisible above it.

Two consequences, binding on every future task:

- **R1 — Every task that adds a capability names its surface.** "Where does the
  user touch this, on phone and on desktop?" is part of Definition of Done, not
  a follow-up. If the answer is "nowhere yet", that is written down in the task
  and in the parking lot — never left implied.
- **R2 — CRUD is audited as a matrix, not per feature.** Entities × {create,
  read, update, **delete**, undo, empty state, error state, offline} is walked
  deliberately (OPH-195). Delete is the cell that goes missing, because it is the
  only one no happy-path demo ever exercises.

## 23. Quick Access: the sidebar section and the floating button (round 11 — Epic 18)

_(Added 2026-07-29, request round 11 #1: "Notion'daki sol menü gibi… mobilde iPhone'un
o beyaz noktası gibi sürüklenip bırakılan, tıklayınca aynı listeyi açan bir düğme."
Entity: BLUEPRINT §4.12; sync decision: ADR-0018. **Calibrated 2026-07-29 by OPH-196's
research pass** — the revised numbers and the three resolved conflicts are marked
"(OPH-196)" below; sources sit under OPH-196 in TASKS.md.)_

- **Q1 — One list, three surfaces.** The extended rail section (≥1160), the narrow
  rail's popover and the phone's floating-button panel render the **same store in
  the same order**. A shortcut added on the desktop appears in the phone bubble
  after sync, in the same position. The surfaces may differ in chrome, never in
  content or order.
- **Q2 — Quick Access is not the favorite star.** The warning-colored star
  (projects, notes) sorts a list in place; Quick Access composes a personal,
  cross-entity navigation list. Distinct affordance, distinct glyph: Quick Access
  uses `bolt` everywhere (menu items, rail header, app-bar fallback), never the
  star, never `AwTokens.warning` as its identity color.
- **Q3 — Rows read left to right: identity, name, hints.** Emoji if set, else the
  kind icon (project → the project's folder glyph tinted by project color, task →
  check circle, note → description, folder → folder, file → file, url → link);
  then the user's title; then, when applicable, a color dot and — for `url` rows —
  an external-link glyph. The glyph is mandatory for external links (G5: color
  alone never carries meaning; leaving the app is meaning).
- **Q4 — Bubble physics (phone).** The button drags freely under the finger and,
  on release, snaps to the nearest vertical edge with `AwMotion.base` and the
  standard emphasized curve. Diameter 56 px (≥44 px target, §5). Position persists
  device-locally as edge + height fraction, clamped inside safe areas and above
  the keyboard inset. Factory position: right edge, 35 % height — deliberately far
  from the quick-add FAB's corner. After 3 s idle it half-recedes into the edge and
  dims to **40 % opacity — the platform's own default, not a taste call (OPH-196:
  AssistiveTouch "fades to 40 % opacity a few seconds after you stop using it")**;
  any touch restores it fully. While a modal route (dialog, sheet) is open, and on
  auth/onboarding screens, the bubble is hidden entirely — a floating control over
  a modal is two competing surfaces.
- **Q4a — The recede is paint, never the hit box (OPH-196).** Q4's two clauses
  fight: a 56 px control translated half off-screen leaves a 28 px target and
  breaks §5's 44 px floor. So the gesture/`Semantics` box stays fully on-screen at
  56×56 and never moves; only the painted circle inside it slides toward the edge
  and is clipped by it. This is what AssistiveTouch and Messenger's chat heads
  actually do ("partially moved outside of the screen", snap-with-bounce on
  release) and it keeps the target legal while the button still looks parked.
- **Q4b — The 40 % dim is a named exception to §20 C3 (OPH-196).** C3 bans
  `Opacity` for calm because dimmed text stops being measurable. The receded
  bubble carries no text anyone is asked to read and returns to full strength on
  first touch, so it is the one place an opacity animation is correct. Its own
  colour pair (glyph on container) is contrast-checked at **full** opacity in
  `scripts/design/contrast.py`; the exception is written in the code that
  implements it, never re-derived.
- **Q4c — The bubble is not a FAB (OPH-196).** Material's rule is one FAB per
  screen for the screen's single most important action; the quick-add FAB owns
  that slot and does not move. The bubble is a persistent *navigation* control,
  which is why it must live on the opposite side of the screen, must be
  switch-off-able (Q5), and must never render while a FAB-bearing modal is up.
- **Q5 — The bubble is optional and never the only way.** Settings owns a toggle
  (factory: on). The bubble only appears when the list is non-empty. When the
  toggle is off — or on platforms without the bubble — the entry point is a `bolt`
  icon in the Home app bar. A gesture-only or overlay-only feature would repeat
  the mistake §19 D2 exists to prevent.
- **Q6 — Empty states are micro, not monumental.** The rail section shows a single
  hint line ("add from any ⚡ menu" in spirit), not an `AwEmptyState` card; the
  phone panel may use the standard empty state since it owns the whole sheet.
- **Q7 — Emoji is input, not a dependency.** The picker is: recents (device-local)
  + a curated ~48 grid + a free single-grapheme text field (the system keyboard's
  emoji page is the real picker; the field also serves desktop). No emoji-picker
  package — that dependency would need an ADR it cannot justify. "Remove" returns
  the row to its kind icon.
- **Q8 — Color is an accent, never a text color.** The user's color renders as a
  10 px dot (and the panel row's leading tint at most); titles and subtitles keep
  their normal `onSurface` roles so the ≥4.5:1 floor never depends on user input.
  The swatch set is the project palette, reused verbatim — no second palette is
  invented.
- **Q8a — The dot carries its contrast in a ring, not in its fill (OPH-196).**
  "≥3:1 against the surface" and "the project palette verbatim" cannot both hold
  for a bare fill: measured against the real surfaces, **5 of the 10 palette
  colours fail in light** (#F59E0B 2.15, #14B8A6 2.49, #10B981 2.54, #0EA5E9 2.77,
  #F97316 2.80 on `#FFFFFF`; worse on glass) — and project colour is not even
  bounded to the palette, since the full grid offers any `Colors.primaries` shade.
  So the dot is the user's colour filled, with a 1 px `outline`-token ring
  (`#63789E` light 4.46:1, `#7186B5` dark — both already guarded). WCAG 1.4.11
  measures the *boundary* of a non-text control, and the ring is that boundary;
  the fill stays honest to what the user picked. Quick Access therefore offers the
  10-swatch palette only — the unbounded grid stays in the parking lot, because
  no ring can rescue a fill nobody bounded.
- **Q9 — Dragging is never the only way to reorder (OPH-196).** Drag-and-drop is
  the one interaction a screen-reader user cannot aim: the accessibility
  literature's standing answer is a parallel path — per-row "Move up" / "Move
  down" actions plus a live-region announcement of the new position. Every Quick
  Access surface therefore carries both: the pointer/touch drag handle **and**
  `quick.moveUp` / `quick.moveDown` in the row's own menu. Same rule, same reason
  as §19 D2 and the K3 board lesson; the bubble's *position* needs no such twin,
  because position is a preference and the panel is the function.

## 24. AI surfaces: the FAB, the bubble, the confirm card (round 11 — Epic 20)

_(Added 2026-07-29, request round 11 #2. Architecture: [AI.md](AI.md) + ADR-0019;
spec: BLUEPRINT §12.16. The owner's rule that shaped the gesture: "when the bubble
opens I can lift my finger and it stays open.")_

- **AI1 — Two FABs, two corners, forever.** The quick-create FAB stays bottom-right;
  the AI FAB lives bottom-left. Neither moves, neither replaces the other, and no
  screen shows a third floating action. On rail layouts the AI entry sits at the
  rail's bottom; desktop gets click-to-talk plus a keyboard shortcut.
- **AI2 — The gesture machine is fixed:** press-and-hold (≥250 ms) opens the bubble
  and records with a live partial transcript; dragging left ≥80 px cancels (haptic);
  **releasing the finger locks recording and keeps the bubble open** — lift-to-lock,
  the owner's rule. Stop, or 2 s of silence (VAD), finalizes. A plain tap opens the
  bubble in text + mic-toggle mode — the hold gesture is never the only path (§19 D2,
  the K3 lesson).
- **AI3 — The bubble is an opaque content surface.** Streamed answers, transcripts
  and cards render on opaque panels; glass stays chrome-only (G1). All bubble text
  meets the §5 floors in both themes like any other surface.
- **AI4 — Every state has a face, and no state lies.** Listening (waveform),
  thinking (indicator), streaming (tokens + a live Stop), error (the
  `status_views.dart` idiom + retry), offline/unconfigured (honest copy + "save to
  Inbox" — voice capture works with zero AI). Latency budgets: partials <300 ms
  cadence, finalize ≤500 ms, first token <2 s, full card <4 s; exceeding them shows
  progress, never a frozen surface.
- **AI5 — Proposals are cards, commits are human.** Extraction output renders as a
  confirm card reusing the create sheet's field rows (one date-input path — §17 D5),
  one row per proposed task, each independently toggleable, with the model's source
  phrase ("yarın 15:00") shown beside the resolved value. Nothing writes until the
  user accepts; accepted tasks go through the store's optimistic+outbox path and get
  the §19 undo idiom. **One deliberate exception since round 14 (owner decision,
  OPH-230): the quick-add ✨ rider auto-applies — see AI11.** Everywhere the AI
  proposes work that does not exist yet (bubble, voice, share), the card stays the
  law.
- **AI11 — The ✨ rider is optimistic, and failure means "plain quick add".**
  Tapping ✨ commits the typed text IMMEDIATELY as a normal quick-add task (round-14
  defaults included, §26) — the row itself is the feedback, marked with a small
  "AI is filling this in" progress badge (`ai-enriching-*`). Extraction runs in the
  background and lands as an UPDATE to that row (extra proposed tasks are created
  whole); the confirm card never appears on this path. Any failure — offline, slow
  provider, nothing extractable — simply clears the badge and leaves the plain task
  standing: the user never loses text, never waits, never reads an error for a task
  that already exists. Auto-applied proposals still report accept/reject to the
  `ai_action_log` (audit parity with the card). The card-first rule (AI5) is
  untouched wherever the AI would CREATE new work from nothing; here the human
  already committed the entry by typing it — the AI only decorates it.
- **AI6 — AI output is text, not surface.** Answers render as plain text / limited
  markdown — no HTML, no auto-opened links, no embedded webviews; `alliswell://`
  links route through the ADR-0016 resolver (navigation-only by construction).
- **AI7 — Provenance is visible.** Every AI message carries a context chip that
  expands to exactly what was packed and sent (T0/T1/T2 tiers, AI.md §7); shared-in
  text is visually framed as quoted external content. Trust is a UI feature.
- **AI8 — Consent is a screen, not a checkbox.** Per provider, before first use:
  what leaves the device, where the key lives, the provider's retention/training
  stance in one honest sentence — and an amber warning where the truth is
  uncomfortable (Gemini free tier trains on data). No AI surface is reachable
  pre-consent.
- **AI9 — Voice respects language.** STT locale follows the app language with a
  per-utterance override chip; the transcript is always editable before anything is
  sent; extraction is told the transcript language so titles stay in the user's
  words ("Ahmet projesine…" is never translated).
- **AI10 — Accessibility parity.** VoiceOver/TalkBack users get the tap path, typed
  input, labeled states and 44 px targets; press-and-hold, swipe-to-cancel and VAD
  are conveniences, never requirements; the bubble spring has a reduced-motion
  variant.

## 25. Recurrence: the switch, the dialog, the sentence (round 12 — Epic 19)

_(Added 2026-07-29, feedback round 12 #1: "çok detaylı configure edilebilir olmalı…
maksimum esneklik… belkemiği özelliklerimizden biri." Rule model and materialization:
[ADR-0020](adr/0020-recurring-tasks-and-materialization.md); product spec: BLUEPRINT
§12.17. The dialog the user pointed at is Google Calendar's custom-recurrence sheet.)_

- **R1 — The switch opens the dialog exactly once.** "Tekrarla" is a `SwitchListTile`
  in the detailed create sheet and in task detail, in the same Column as the other
  switches (urgent, mute alarms). Turning it **on for the first time opens the
  configuration dialog immediately** — a switch that can leave a half-configured rule
  behind is a lie about state (§11 A4). Cancelling the dialog turns the switch back
  off; there is no "on but unconfigured". Turning it off later is R7, not a silent
  reset.
- **R2 — A configured rule reads as a sentence, not as a form summary.** Under the
  switch sits one line — "Her ayın 22'sinden sonraki ilk Pazartesi · bitiş yok" — with
  **Değiştir** beside it. The sentence is **generated from the rule per language**, not
  assembled from translated fragments: Turkish and English build their own word order
  from the same object. i18n has no plural machinery (ADR-0009), so every count form is
  its own key (`repeat.everyNWeeks.one` / `.other`), never a runtime `+ 's'`.
- **R3 — Presets first, "Gelişmiş" second.** The dialog opens on five presets (her gün /
  her hafta / her ay / her yıl / hafta içi). Everything the three scenario classes need
  lives one disclosure deeper: **day of month** (with the clamp stated in plain words —
  "kısa aylarda ayın son gününe çekilir"), **Nth weekday** (1..5 + "son"), **"ayın
  X'inden sonraki ilk {gün}"** and **first/last {weekday}**, plus the end condition
  (asla / tarihe kadar / N kez). The advanced section is a disclosure, never a second
  screen — the user must see the preview change as they build the rule.
- **R4 — "Sonraki 5" is the proof, and it is never hidden.** The dialog shows the next
  five real dates, recomputed on every edit from the Dart engine port (ADR-0020 §6), and
  it shows **clamping and skipped months truthfully**: pick the 31st and February reads
  28/29. This preview is the only place a user can confirm the system did not quietly
  break their rule, so it stays visible above the fold — no scrolling to reach the
  answer, on the narrowest supported width.
- **R5 — The dialog owns its controllers.** Round 11 shipped this bug three times: a
  `TextEditingController` disposed the instant `showDialog` returned, while the route
  was still animating out, rebuilds the field and throws. Any dialog with a field owns
  its controllers for its whole lifetime.
- **R6 — The badge is quiet and everywhere the task is.** A recurring occurrence carries
  a small ↻ next to its metadata in list rows, task detail and the board card — same
  weight as the other row chips, never a colour of its own, with the rule sentence as
  its tooltip/semantics label. It disappears in the completed treatment along with the
  alarm chips (§20 C2): a finished occurrence does not repeat.
- **R7 — Stopping is honest about the past.** "Tekrarı durdur" removes the **future**
  occurrences and keeps every past and completed one, and says so in the confirm copy.
  A finished task is a historical fact (§20 C4); deleting history to tidy a rule would
  rewrite what the user actually did.
- **R8 — Scope is a question with a default, and the default follows the field.**
  Editing an occurrence asks "Yalnız bu / **Bu ve gelecektekiler** / Tümü" with the
  middle option preselected — the user's own rule ("birinden değiştirilince
  gelecektekilerin hepsi"). One exception, stated in the dialog: **moving a single
  date defaults to "Yalnız bu"**, because rescheduling one appointment is not
  rescheduling the series. Two things the answer means, decided in code
  (OPH-206) and visible to the user: **"Yalnız bu" keeps the row inside the
  series** — it stays a modified occurrence, badge and all, rather than
  becoming a loose task — and a date edit under the wider scopes moves **the
  time of day**, never the pattern ("bundan sonra 14:00'te"), because the days
  belong to the rule.
- **R9 — Accessibility parity.** The whole dialog is reachable by keyboard and screen
  reader: presets are radio semantics, the advanced builders are labelled fields (never
  bare dropdown glyphs), the preview is readable as text rather than as a chart, and
  every control clears the 44 px floor. Contrast is checked in both themes like any
  other surface — the dialog introduces no new colour.

## 26. Creation defaults & the quick-add deadline ask (round 14 — Epic 21)

_(Added 2026-08-05, feedback round 14. The owner's stance: a task worth writing
down deserves a deadline, a reminder and an alarm by default — friction belongs
at capture time, not at 02:00 when nothing rang.)_

- **C1 — A new task is born medium + urgent-armed.** The create sheet opens with
  priority **medium** and the **urgent-alarm switch ON**; both are visible fields
  the user can flip before saving — defaults, never hidden behavior. Editing an
  existing task shows the task's own truth, untouched.
- **C2 — A deadline auto-arms its reminder, one hour before.** Picking a due date
  (create sheet, quick add, ✨ rider) sets the reminder to **due − 1 h**
  (`kAwAutoReminderGap`) — visibly. The derived value FOLLOWS the deadline while
  it stays derived; the moment the user hand-picks or clears the reminder it is
  theirs, and no due-date edit ever overwrites it again (§17 D5's "editing must
  not change what the user didn't touch", applied to derivation). Clearing the
  due date takes a still-derived reminder with it.
- **C3 — Home quick add asks for the deadline, once, skippably.** Submitting the
  Home quick-add bar opens the one shared date+time picker (§17 D5) prefilled
  with the selected calendar day. Backing out is the skip path: the task still
  lands instantly — on the selected day at the default task time when one is
  picked (the bar's own promise), dateless otherwise. Inbox capture stays a
  dateless capture box (§10) — the ask exists only where the user is planning,
  not where they are unloading.
- **C4 — Defaults apply at every birth point identically.** Sheet, quick add and
  ✨ rider share `task_defaults.dart`; a surface that creates tasks and skips it
  is a bug (§22 reachability logic applied to behavior parity).

## 27. Exporting a note, and the app's own mark (round 16 — Epic 23)

### E1 — Export is a menu item, not a fifth icon bar button

The note editor's app bar is already at the phone's limit (§ OPH-201), so
"Export as PDF" lives in the overflow menu — alongside Quick Access, above it,
with a `picture_as_pdf_outlined` leading icon. The menu is NOT gated on the note
having been saved: the document being exported is the one in the editor.

### E2 — Producing a file is slow enough to need a face

Fonts have to be decoded and embedded media fetched, so the export shows a
BLOCKING, non-dismissible progress dialog ("Preparing the PDF…") and only then a
sheet. Silence while an app works is the failure mode this rule exists to
prevent — the same reason uploads got visible state (§10 F2).

### E3 — Name the way out after what actually happens

The result sheet offers what the platform really does, never a label for
something that does not happen:

| Platform | Actions |
| --- | --- |
| iOS / Android | **Share** (the OS sheet — which is also where "Save to Files" lives, so the subtitle says so) · **Save to Files** (system document picker) · **Print** |
| Web | **Download** · **Print** (the browser's print preview) |
| Desktop | **Save** · **Print** |

Backing out of the save dialog leaves the sheet open. Closing it silently would
read as success.

### E4 — The page is always light, and always legible

A PDF is print: it uses a fixed light palette derived from the tokens
(`#0F1B2E` ink, `#44536F` muted, `#0A5CFF` accent), never the dark theme. This
is the ONE place a raw colour is allowed outside `tokens.dart` (G6), because the
`pdf` package has no access to the Flutter theme — and the values are pinned in
`note_pdf.dart` next to the reason.

### E5 — Structure survives, and so does Turkish

The exporter renders the note's STRUCTURE (headings, lists, checklists, quotes,
code panels, figures, clickable links), not flattened text. Completed checklist
items keep their strikethrough on paper (§20), and media that could not be
fetched prints an honest placeholder (§10 F3).

The exporter EMBEDS its fonts, and this is a correctness requirement rather
than a style choice:

- **Roboto** for the text. The `pdf` package's built-in Helvetica is
  WinAnsi-encoded and has no `ı ğ ş İ`, so a Turkish note would export as
  mojibake.
- **DejaVu Sans** as a per-glyph fallback. Roboto's cmap is 896 code points and
  carries none of `→ ← ↔ ⇒ ✓ ✗ ★ ☆ ▪ ▫ ☐ ☑` — all things people type — so they
  drew as hollow boxes. PDF's base-14 Symbol and ZapfDingbats were tried first
  and measured to rescue none of them.

Both are PDF-only assets: the UI keeps system fonts (§3.3). Every `TextStyle`
the exporter builds must carry the fallback — `NotePdfFonts.fallback` exists so
that is one list, not seven copies.

Remaining limit, pinned by a test so nobody re-opens it as a bug: modern
pictographic emoji have no glyph in any monochrome face, and a PDF cannot embed
a colour emoji font.

### E6 — The app icon's layers are GENERATED, and verified

An Android adaptive icon's foreground layer must be TRANSPARENT with the mark
inside the safe zone — an opaque foreground covers the background layer and the
launcher draws a blank tile (round 16 #1, shipped for months). So the layers are
never hand-made: `scripts/design/branding_icons.py` derives all three
(foreground, background, monochrome) from the one master `icon.png` and asserts
the invariants — corners transparent, mark inside Google's 66 dp safe zone,
centred. Run it, then `dart run flutter_launcher_icons`; `--check` verifies the
committed layers without rewriting them.

Android's background layer is the brand GRADIENT, not a flat colour, so the icon
is the same artwork on both stores. Android 13+ themed icons get the monochrome
layer, or the launcher shrinks the whole icon into a grey circle.

**`flutter_launcher_icons` is configured `ios: false`, and REPLACED.** v0.14.4
rewrites every `ASSETCATALOG_COMPILER_*` build setting it finds to the icon name,
which corrupted the widget extension's accent and background colour names.
Reverting `project.pbxproj` after each run would be a landmine, so the same
script generates the iOS AppIcon set: from the same master, at the sizes the
catalog's own `Contents.json` declares, flattened to no alpha (App Store Connect
rejects a marketing icon that has one). It never rewrites that JSON — Xcode stays
the owner of which slots exist.

## 28. Markdown in, note out (round 16b — OPH-241)

AllisWell reads `.md` files: the OS can hand it one ("Open with"), or the user
picks one from the Notes tab.

| # | Rule | Why |
| --- | --- | --- |
| M1 | **The preview IS the import.** The viewer renders the exact delta a save would write, in a read-only editor — never a second markdown renderer. | A separate preview drifts from the importer and shows the user something they will not get. |
| M2 | **Nothing is dropped.** Markup the reader does not understand (tables, footnotes, HTML) survives as plain text. | A lossy import of somebody's own file is worse than an ugly one. |
| M3 | **Provenance is visible.** The source file name sits above the title. | This is an external document; the user decides to keep it, so they must see which one. |
| M4 | **The title comes from the document**, its leading `# H1` if it has one, otherwise the file name — and that heading is then removed from the body. | Apple-Notes rule (round 1): the title is the document's first block, not a repeated line. |
| M5 | **Filing is the create sheet's own control.** Choosing a project uses `ProjectPickerField`, not a new picker. | Importing must not invent a second way to do an existing thing. |
| M6 | **Reachable from inside the app**, not only when the OS starts it. | A feature only an OS handler can trigger is one most people never find (§22). |
| M7 | **Refuse honestly.** Over 2 MB is declined with the size in the message; a file the OS names but cannot deliver leaves the app where it was. | Silence and a spinner are the failure modes this rule exists to prevent. |

The converter (`markdown_delta.dart`) is the exact inverse of `deltaToMarkdown`,
which is what lets the tests assert a ROUND TRIP instead of hand-written
fixtures. It is not a CommonMark implementation and does not try to be — nested
lists are out because Quill's own model is flat.

> **Round 17 supersedes the scope of this section, not its rules.** §28's seven
> rules stay true for *importing*; §29 below covers reading, editing and owning
> a markdown document. The survey and the scope decision behind §29 live in
> [MARKDOWN.md](MARKDOWN.md).

## 29. The markdown workspace (round 17 — Epic 24, OPH-246…OPH-252)

A note is a document. Round 17 makes AllisWell good enough at documents that a
person stops leaving the app to read a `README.md`. The feature survey, the
take/later/reject inventory and the model decision are in
[MARKDOWN.md](MARKDOWN.md); this section is the binding UI contract.

### 29.1 The three modes

| # | Rule | Why |
| --- | --- | --- |
| D1 | **Exactly three modes: Reading · Live · Source.** One control switches them; the control shows which one is active and never hides. | Obsidian's triple is the only mental model users already have. A fourth mode is a design failure, not a feature. |
| D2 | **Reading is the default for a document that arrived from outside**; Live is the default for a note the user wrote here. | The first thing you do with someone else's file is read it. The first thing you do with yours is keep writing. |
| D3 | **A mode switch preserves the caret, the scroll position and the undo history.** | A switch that loses your place is a switch nobody uses twice. |
| D4 | **Reading is never editable-looking.** No caret, no placeholder, no toolbar — but checkboxes in task lists ARE tappable, and ticking one writes to the document. | The one interaction people genuinely expect from a rendered task list. Everything else pretending to be editable is a lie. |
| D5 | **Split view (Source ⇄ Reading, scroll-synced both ways) appears only ≥ 900 px** and is a toggle inside Source mode, not a fourth mode. | Zettlr/VS Code behaviour. On a phone a split pane gives two useless columns. |

### 29.2 Rendering

| # | Rule | Why |
| --- | --- | --- |
| D6 | **GFM is the dialect.** If GitHub renders it, AllisWell renders it: tables, task lists, footnotes, strikethrough, autolinks, alerts (`> [!NOTE]`), fenced code, `$…$`/`$$…$$` math. | Every file our users already own is written for that renderer. Anything narrower is a broken viewer. |
| D7 | **Rendered markdown is themed from tokens, never from the package.** Headings use the type scale; code panels, tables and callouts use `AwTokens`; `contrast.py` passes in both themes. | Rule 11 has no carve-out for third-party widgets. |
| D8 | **Wide content scrolls inside its own box.** Tables and code blocks get horizontal scroll; the page never scrolls sideways. | The single most common markdown-on-mobile failure. |
| D9 | **Every code block carries its language label and a copy button.** | GitHub/VS Code baseline; the copy button is the reason people open a README on a phone. |
| D10 | **A document is untrusted input.** HTML blocks render as escaped source, never live. `javascript:`/`data:` URIs are inert text. Remote images follow the note-embed rules. Diagrams render from a parsed AST — no web view, no JS engine on the reading path. | §24 AI6 is not about AI; it is about untrusted documents, and a `.md` from a stranger's repo is exactly that. |
| D11 | **When a block cannot be drawn, show the source and say why** — never a blank, never a silent drop. | §10 F3. A missing diagram that leaves a gap is indistinguishable from a bug. |
| D12 | **Front matter is a properties header, not text.** A leading YAML block renders as a compact key/value strip that can be collapsed. | Every Jekyll/Hugo file starts with one; dumping it as body text makes the app look broken on the first screen. |

### 29.3 Navigating a long document

| # | Rule | Why |
| --- | --- | --- |
| D13 | **The outline is one tap away and follows you.** A heading tree, current section highlighted, scroll-synced. Sheet on phones, side panel ≥ 900 px. | Obsidian's auto-scroll-to-current-section; a 2 000-line README is unusable without it. |
| D14 | **Headings fold.** Collapse state is per-session, never persisted into the document. | VS Code. Folding must never mutate somebody's file. |
| D15 | **Find & replace exists and is reachable by keyboard.** The toolbar's search button stops being disabled. | It is currently switched off in `QuillSimpleToolbarConfig` — a control that exists and does nothing (§22). |
| D16 | **In-document anchors work.** `[link](#heading)` scrolls to that heading. | Otherwise every table of contents in every imported file is dead. |

### 29.4 Writing comfort

| # | Rule | Why |
| --- | --- | --- |
| D17 | **Lists continue themselves**, renumber themselves, and nest with Tab / Shift-Tab. | The biggest single typing-comfort win, and it is the thing the flat Delta model blocked. |
| D18 | **On a phone, a scrolling markdown toolbar sits above the keyboard.** On desktop/web, keyboard shortcuts and a command palette do the same job. | Obsidian, Bear and iA Writer all converged here; the phone has no room for a palette. |
| D19 | **Slash commands are the second path to every toolbar action**, never the only one. | §22 reachability: an invisible command surface is not a feature. |
| D20 | **Paste is smart and reversible.** HTML pastes as markdown; a URL over a selection makes a link; a clipboard image uploads as an attachment. One undo restores the raw paste. | "Smart" paste without one-step undo is hostile. |
| D21 | **Save state is visible.** Autosave keeps working; a small, non-blocking indicator says saved / saving / failed. | Silent autosave plus an eventual failure is how people lose work and trust. |
| D22 | **Word and character count are always available, never in the way.** | Ulysses; a status affordance, not a panel. |
| D23 | **Focus mode dims, it does not hide.** Everything but the current paragraph fades; nothing is removed from the layout. | iA Writer. Hiding causes reflow; dimming does not. |

### 29.5 Somebody else's file (W-rules)

These govern writing back to a file the app did not create. This is the only
feature in the round that can destroy a user's data.

| # | Rule | Why |
| --- | --- | --- |
| W1 | **An external document is permanently marked as external** — a banner with the real file name, visible in every mode, for the whole session. | §28 M3 extended: the moment editing is possible, "which file am I changing" stops being a nicety. |
| W2 | **Writing back is explicit.** Autosave belongs to AllisWell's own notes; an external file changes only on a deliberate save. | Auto-writing somebody's repo file is indefensible. |
| W3 | **Editability is probed, not assumed.** If the OS gave us read-only access or an expired security scope, the banner says "read-only" and the save action is absent — not present and failing. | A dead button is worse than a missing one (§22). |
| W4 | **Byte-faithful or refuse.** If the note's canonical form is not markdown text, AllisWell offers "Save as a note", not "Save to file". | A WYSIWYG round-trip reflows a hand-formatted file; doing that silently to somebody's document is data loss with good intentions. |
| W5 | **Changed underneath = never silently overwritten.** If the file changed on disk since it was opened, the save is a choice: reload, overwrite, or save a copy. | The conflict-copy stance the sync layer already takes (AGENTS §6). |
| W6 | **Recently opened files are listed in the app.** | A file the OS handed us once is otherwise unreachable forever — §22 again. |

## 30. Attaching a photo, and looking at it (round 17 — OPH-244 / OPH-245)

Round 17 #2: on an iPhone, "Add file" opened the document browser, photos were
nowhere, and no permission was ever asked for.

| # | Rule | Why |
| --- | --- | --- |
| A1 | **Three named ways in, not one generic one: Photos · Camera · Files.** The attach control opens a small menu; each item says what it opens. | "Dosya seç" is a promise about the Files app. Someone looking for a photo has no reason to tap it, and if they do, their photos are not there. |
| A2 | **Photos means the system photo picker** (iOS `PHPickerViewController`, Android Photo Picker) — which needs **no permission at all** and shows no dialog. | Measured: `file_picker` 12 routes `FileType.image/video/media` to `PHPicker` and everything else to `UIDocumentPickerViewController`. The missing permission prompt was not a bug — the wrong picker was being opened. **Correction (OPH-244, measured):** `file_picker` cannot honour this on Android — its `FileUtils.kt` builds `ACTION_GET_CONTENT` for media too, never `PickVisualMedia`. The media sources therefore go through `image_picker` on mobile ([ADR-0027](adr/0027-attachment-capture-image-picker.md)), whose Android Photo Picker must be switched **on** explicitly. |
| A3 | **No broad media permission is ever requested.** If a path needs `READ_MEDIA_IMAGES` or full-library access, that path is wrong. | Play policy rejects apps that declare `READ_MEDIA_IMAGES` when the Photo Picker would do; a permission dialog is also a worse experience than no dialog. |
| A4 | **The description area carries the attach affordance too**, not just a section further down the screen. | Round 17: the owner looked for it in the description first. That is where people expect it, because that is where notes put it. |
| A5 | **Image attachments show as thumbnails**, other files as rows. | A grid of file names is not how anyone reviews photos. **Already true** (`FileLeadingThumb`) — the owner never saw it because they could not attach a photo in the first place. Moved to OPH-245 (a real grid, rather than the 40 px leading square). |
| A6 | **Tapping an image opens a real viewer: pinch-zoom, double-tap zoom, pan, swipe between the images of that task, share/save, and the file name in the bar.** | The round's literal ask. **Pinch-zoom already shipped** (`showFileImageViewer` → `InteractiveViewer(maxScale: 6)`); OPH-245 adds double-tap, gallery paging and the merge below. |
| A7 | **One viewer, everywhere.** Task attachments, note embeds and the Files section all open the same component. | There are TWO today — `showFileImageViewer` (files) and `_EmbedImageViewer`, private to `note_media.dart` — which is the §22 problem in its clearest form. OPH-245. |
| A9 | **A camera capture is renamed** the way a gallery names one (`IMG_20260810_003215.jpg`). | `image_picker` hands back its own temp path (`image_picker_5B1F….jpg`); raw plumbing must not reach a file row (§10 F6). |
| A10 | **No camera in the note toolbar.** Those two buttons insert formats; they are not the attach control. | A1 is about the attach control. Widening a format button into a capture menu would blur what each button means. |
| A8 | **Failure is a stated reason, not a spinner.** Storage unconfigured, upload failed, file gone: each says which. | §10 F3, already the rule for attachments. |

## 31. The widget header: date, clock, count (round 17 — OPH-253)

Round 17 #4: the widget's header has the date on the left and today's open-task
count on the right; the owner wants the **system clock** above that count, bold
and readable.

| # | Rule | Why |
| --- | --- | --- |
| C1 | **The header's right column is two stacked lines: the clock on top (bold, prominent), the open count under it.** The left column (day number, weekday, month) is unchanged. | The requested layout; the date block is already load-bearing and stays put. |
| C2 | **The clock respects the device's 12/24-hour setting and locale**, and is drawn with tabular figures so it does not jitter. | A clock that shows 24-hour time to someone who set 12-hour is not their clock. |
| C3 | **The clock is never a stale number pretending to be live.** On Android it ticks (`TextClock` is a `@RemoteView`, so it updates itself with no refresh budget). On iOS a widget cannot tick: `Text(date, style: .time)` renders the value from the timeline entry and holds it, and only `.timer`/`.relative`/`.offset` update live. iOS therefore gets minute-granular timeline entries — and if the system stops honouring them, the header must degrade to something that is *true* (the date block alone), never to a wrong time. | A wrong clock is worse than no clock, and this repo has already paid for "it looks right, so it is right" once (the white Android icon, round 16). |
| C4 | **The clock never costs a data refresh, and its reload cost is measured, not assumed.** No extra snapshot writes, ever. On Android it is free (`TextClock` ticks itself). On iOS it is not free and cannot be: see the measurement below. The rule is a budget — the clock may spend **at most a fifth** of the reload floor, and the horizon that buys is computed at runtime, not hardcoded. | WidgetKit budgets a widget to roughly 40–70 reloads a day; spending them on a clock would starve the task list. |
| C5 | **At zero open tasks the count still hides** (existing behaviour) and the clock moves to the vertical centre of the right column. | The count already hides at zero; a clock hanging off a missing second line looks broken. |

### What building it actually measured (2026-08-10)

Three things were checked before writing this section and three more were only
learned by putting the widget on a real Home Screen. Recording both, because the
difference between them is the point.

**Confirmed by research.** There is no self-updating wall clock on iOS, in any
version including 26. `Text(date, style: .time)` prints its timeline entry's
instant and freezes; only `.relative`, `.offset` and `.timer` update themselves,
and all three render *durations*. iOS 18's `TimeDataSource<Date>.currentDate`
auto-updates only with duration-shaped format styles. WWDC25's widget session
adds nothing here. C3's premise was right.

**Rejected, with reasons, so nobody re-proposes it.** A `Text(timerInterval:)`
counting up from midnight *is* a live 24-hour clock at literally zero reloads.
It is not usable: the seconds cannot be hidden, the twelve-o'clock hour renders
as `0:05` for anyone on a 12-hour clock, there is no AM/PM marker, and `.timer`
has a history of breaking outright (it did in iOS 16.0b7). C2 outranks the
saving.

**How every clock widget on the App Store actually does it** — and the number
that matters: *entries are free*. The 40–70/day budget is spent by **asking for
a new timeline**, not by rendering entries that already exist. So the cost of a
live clock is `1440 / horizon-in-minutes` reloads a day, and the engineering
question is how long a horizon you can afford to bake.

**The ceiling is the archive, not the budget — measured the hard way.** 241
minute entries of a `systemLarge` list archived to **16,665,560 bytes** and
chronod threw the whole timeline away (`failed with too large timeline archive`,
`CHSErrorDomain 1050`). The widget then sat on its placeholder — two grey bars,
no error anywhere a user could see it. ~69 KB per entry, scaling with the **rows
drawn**, so a fixed entry count fails precisely for the people with the most
tasks. The horizon is therefore derived from a byte budget at runtime: a
ten-row list settles at ~115 minutes (≈13 reloads/day), an empty one takes the
full 240 (6/day).

**And the header was being clipped off the top.** A full list is taller than a
`systemLarge` card, an oversized child centres itself, and the widget was losing
pixels at *both* ends — the day number came out sliced in half and the new clock
was cut off the card entirely. `.frame(maxHeight: .infinity, alignment: .top)`
does not fix this: a max frame only grows to the proposal, so when the child is
bigger the frame reports the child's size and the alignment has nothing to do.
Clamping to the geometry's exact height is what makes `.top` bite. **Rule: when
a widget has to lose something, it loses it at the bottom** — the list already
has a vocabulary for being cut short ("+N") and the header does not.

