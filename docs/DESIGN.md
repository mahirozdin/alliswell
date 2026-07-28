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
  it is not currently earning.
- **H2 — Wide layouts are unchanged.** ≥720 px keeps the calendar side panel and
  its own column; the complaint (and the fix) is about the phone.
- **H3 — A view switch that scrolls away must still be reachable (deliberate
  deviation).** In **Pano** the board is a horizontal pager filling the
  viewport, so the Liste | Pano row stays pinned there — scrolling it away
  would strand the user in the board with no way back. List mode scrolls it.
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
