# ADR-0063 — Platform tracking, Glass Type v1 and one formatter

- **Status:** Accepted
- **Date:** 2026-11-07
- **Related task:** OPH-399, OPH-400, OPH-407, OPH-408 (Epic 35)
- **Amends:** [DESIGN.md](../DESIGN.md) §3.3 ("weights/tracking tuned in `theme.dart`") — the tracking
  now comes from the platform's font, not from Material's Roboto-tuned geometry.
- **Keeps:** [ADR-0005](0005-alliswell-glass-design-system.md) #6 — system fonts, no webfonts. The font
  family does not change (owner decision 2026-11-07); on the web the app's own bundled Roboto is used
  instead of a Google download, which makes #6's "zero network fetch" true there too.

## Context

The owner's iPhone screen read "wide, ported from the web". Research measured why
([docs/research/2026-11-design-ux/](../research/2026-11-design-ux/README.md): `typography-system.md`,
`typography-sf-verification.md`):

- **Material's tracking applied to SF Pro.** `Typography.material2021(...).englishLike` brings
  bodyLarge +0.5, bodyMedium +0.25, labelMedium/Small +0.5 — values tuned for Roboto. SF Pro's own value
  at 16 pt is −0.31 (Apple HIG).
- **Flutter does not apply SF's dynamic tracking.** Measured on an iOS 27.2 simulator against UILabel:
  every 16 pt string fits "SF tracking 0 + Flutter letterSpacing" (−0.74…+0.08 pt, error ±0.67 pt), so
  the net excess on iOS is **+0.81 pt per glyph at 16 pt**, +0.40 at 14 pt, +0.4/+0.5 at 12 pt. Row
  titles are **9.4–11.3 % wider** than native, body 6.3 %, the bar label 5.7–7.4 %.
- **`letterSpacing: 0` alone is not enough:** it recovers only part of the gap (row titles stay ≈3.6 %
  wide). The HIG values reproduce native UILabel width within **0.02–0.15 pt**, with no double counting.
- **Goldens are drawn with Roboto**, so SF metrics are seen by no automated check (T-07).
- **The web downloads Roboto from `fonts.gstatic.com`** (T-04): self-hosted installs make the user's
  browser call Google.
- **Numbers and dates are formatted at least seven ways** across the app (persona finding U-09): numeric
  dates, US order for an English UI in a German region, `g`/`sa` abbreviations, `(56/58)` fractions.
- **Contrast misses on the page ground:** the red section header over an aurora peak is 4.32–4.39:1
  (light) and 4.34:1 (dark); the amber favourite star is 1.55:1 — `contrast.py` measures card pairs
  only (T-05, T-06).

## Decision

1. **`awTracking(size, family)`.** On Apple platforms the HIG SF Pro table (11 +0.06 · 12 0 · 13 −0.08 ·
   14 −0.15 · 15 −0.23 · 16 −0.31 · 17 −0.43 · 20 −0.45 · 22 −0.26 · 24 +0.07 · 28 +0.38 · 34 +0.40);
   elsewhere 0 (Roboto/Segoe/Linux/web keep their own metrics). Tracking is derived, never hand-picked
   per widget.
2. **Glass Type v1.** Sizes are kept; line height and rhythm are fixed: row title bodyLarge 16/22 w400,
   meta 13/18, section label 15/20, bar label 11/13 w600, weights only 400/500/600/700 (w800 only on the
   alarm label). Semantic roles (`sectionLabel`, `meta`, `metaStrong`, `rowTitle`, `numeric`) replace
   copied `copyWith` chains. Table: `typography-system.md` §4.2 and `mobbin-design.md` §1.2.
3. **Tabular figures** for dates, times, counters, badges, alarm time and import counts.
4. **Contrast is measured on the page ground too:** `scripts/design/contrast.py` gains text-on-aurora
   pairs; the red section header gets a page-safe tone (≥4.5:1 in both themes); the amber star becomes
   the `warning` token.
5. **A gate, `check:typography`:** counts raw `fontSize`, raw `TextStyle(` and off-grid spacing against a
   committed baseline that may only go down; it runs in `verify:batch`.
6. **One formatter, `awFormat*`:** date, time, duration, money, percent and file size come from one
   place. Order and 12/24 h follow the **region**, not the UI language (English UI + de-DE region →
   `7 Nov 2026, 13:47`). No numeric dates in the UI; relative time for activity; `·` as separator;
   denominator 0 → `—`. Every call site, the extension's screens included, moves to it.
7. **Web fonts are the app's own:** `assets/fonts/Roboto-*` registered by family name (with the 500 and
   600 weights) so the engine never fetches from Google.

## Alternatives considered

- **Change the font family** — Inter everywhere, Wix Madefor (the homepage's face), or a hybrid with a
  display face for headings. Rejected: breaks ADR-0005 #6 and ADR-0012 (SF is the Liquid Glass type),
  loses Dynamic Type and Bold Text behaviour on iOS, adds payload; and the measured problem is tracking,
  which this fixes. The owner kept the family (2026-11-07).
- **`letterSpacing: 0` everywhere** — simplest, but measured: still ≈3.6 % wide on iOS row titles.
- **Keep M3 tracking on Android only** — possible later with one table row; Roboto's own metrics with 0
  are the default here for one rule across non-Apple platforms.
- **Format per screen with `intl` calls** — what produced seven formats; rejected.

## Consequences

- SF Glass Type v1, recomputed from the measurements: row titles −10.5…−12.5 % width, meta −12…−15 %,
  bar label −14…−16 %; overdue meta lines go from two lines to one at the estimated column width.
- DESIGN §3.3 is rewritten; §44 (the task row) and §45 (text and format) follow in their tasks.
- Goldens still use Roboto, so the SF width check is a DEVICE-CHECKS row (simulator measurement, method
  in `typography-sf-verification.md` §1).
- `check:i18n` grows the tone and "open source" rules with the text pass (OPH-407); the formatter has
  unit tests for TR, EN-US and EN-DE.
- The web bundle grows by the two extra Roboto weights (≈2 × 170 KB, estimated) and stops calling Google.
