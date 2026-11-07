# ADR-0062 — Phone navigation: an equal-slot labelled capsule and one action cluster

- **Status:** Accepted
- **Date:** 2026-11-07
- **Related task:** OPH-396, OPH-397, OPH-398 (Epic 35 — the design and UX round the owner asked for
  on 2026-11-07)
- **Amends:** [ADR-0055](0055-global-search-palette.md) (its phone consequence: "below 64 px per tab
  only the selected label is written") and [DESIGN.md](../DESIGN.md) §23 Q4 (the Quick Access bubble's
  docked factory position, OPH-362) and §24 AI1 ("two FABs, two corners, forever"). The accepted text of
  those decisions is not edited; this ADR is the newer word on the phone layout.
- **Unchanged:** the Glass identity ([ADR-0005](0005-alliswell-glass-design-system.md),
  [ADR-0012](0012-liquid-glass-v2-visual-refresh.md)): aurora ground, glass capsule, round search
  orb beside it (ADR-0055), azure accent, solid cards. The rail layouts are not touched.

## Context

The owner's complaint (2026-11-07): the phone bottom bar "slides", has no order and does not look
like a product a company would buy. The round measured the shell instead of arguing about taste
(research: [docs/research/2026-11-design-ux/](../research/2026-11-design-ux/README.md),
`ux-shell-mobile.md`, `android-shell-probe.md`, `mobbin-design.md` §0–§2).

Measured causes:

- **Material 3 `NavigationBar` inside a capsule that is too narrow.** Its indicator is a fixed 64 pt;
  at 393 pt a slot is ≈54.6 pt, and with the docked Quick Access bubble (72 pt lane) 39–50 pt on
  iPhones. On Android the probe measured **36 dp per tab at 360 dp, 46.4 dp at 412 dp** (30 dp with
  the extension's sixth section) — below DESIGN G4's 48 dp floor on every phone. The indicator does
  not clip, it squashes into a 36×32 blob.
- **The width-based label rule of ADR-0055 fires on every iPhone.** Only the selected tab is labelled;
  M3 then lifts that icon ≈10 pt, so the row has two icon centre lines. The bar is 64 pt tall (M3
  default 80) and the label has `overflow: visible`, so "Ana Sayfa" (59 dp, 75 dp at 1.3×) falls below
  the capsule and under the next icon.
- **Five floating objects without a grid.** Capsule, orb, "+" FAB, AI FAB on the left and the bubble;
  four different edge insets (8/12/16 and the bubble's dock) and two diameters. The left AI FAB sits on
  the section headers and the first column of check circles (R-07). No scrim where content runs under
  the bar (R-03). The docked bubble's intro card draws into Android's system navigation band (A-03).
- **Nothing caught it:** the design screenshots mount neither the bubble nor the safe area, run at 1.0×
  text only, and are not committed (R-13).

Four personas (a designer, a student, a small-business IT lead, a self-hoster) independently named
the same first three problems: the bar, the overlapping floating buttons and the month calendar. Two of
them could not tell unlabelled icons apart (Projects and Files share a folder silhouette).

## Decision

1. **`AwTabCapsule` replaces `NavigationBar` on phones.** A 64 pt glass capsule with **five equal
   slots**, each ≥48 dp / 44 pt at every width from 360 dp up. Every tab is labelled: icon 22–24 over an
   11/13 w600 label, one shared glyph centre line, a 40 pt-high selection that stays inside its slot.
   Selecting a tab moves nothing. A label never leaves the capsule (no `overflow: visible`); label text
   scaling is clamped at 1.3 and above that a long press shows the name in a large-content bubble.
   Semantics: selected state and "tab 2 of 5".
2. **A sixth section makes the fifth slot "More"**, which opens a page with the remaining sections —
   the grid never compresses past five.
3. **One action cluster on the right.** Microphone (48) and "+" (56) share a vertical centre line on the
   right gutter, "+" bottom 16 pt above the capsule top; the bottom-left corner is empty. On scroll the
   FABs drop 16 pt in 150 ms (instant with reduced motion). **This amends DESIGN §24 AI1**: the AI entry
   is no longer a separate bottom-left FAB on phones; the press-and-hold gesture machine (AI2) is
   unchanged, and a plain tap stays a visible path to voice.
4. **One grid.** One 16 pt gutter on phones (20 at ≥430 pt); capsule, orb (56, 8 pt gap, same centre
   line), FABs and cards align to it. A passive bottom scrim fades from the page colour (not glass). The
   end-of-list padding is bar + FAB + 24 pt; a screen without the bar ends at safe area + 24 pt.
5. **The Quick Access bubble is off by default on phones** (**amends DESIGN §23 Q4**'s docked factory
   position). Its ways in are the ⚡ in the app bar, a "Shortcuts" group in the empty search palette, and
   a long press on the Home tab; Settings can turn the bubble back on, and then it stays inside the safe
   area and hides on pushed pages; its intro card sits above the system bar.
6. **Phone app bar: at most three targets** — ⚡, "View ⌄" (list/board, calendar, sort in one menu),
   Settings. Home's local search magnifier goes; local filtering moves to a pull-down field. The global
   search entry of ADR-0055 (the orb beside the bar, ⌘K/Ctrl+K) is kept.
7. **The checks that were missing become tests:** a measurement matrix (360/375/393/412/430 ×
   1.0/1.3/2.0 × TR/EN × light/dark, bubble on and off) asserting slot width, label containment and that
   no floating object covers the first row's check circle or a section header.

## Alternatives considered

Four directions were drawn on the same demo screen and scored blind by an independent reviewer
(another model family) on clarity, craft, hierarchy, reachability/accessibility, identity and
corporate feel, 10 each:

| Direction | What it was | Score /60 |
| --- | --- | --- |
| Today | M3 bar, selected-only label, five floating objects | **23** |
| **A** "Align" | keep the layout, fix label containment and insets | **38** |
| **B** "Gather" | selected tab as a horizontal pill, other icons bare; mic + "+" together on the right | **44** |
| **C** "One row" | orb, capsule and "+" on one line; no separate mic, voice by holding "+" | **41** |
| **B+** | B with the reviewer's measured refinements: equal slots, every tab labelled, 64 pt capsule, 48 pt mic, one action-lane geometry | chosen |

- **Today** — rejected: containment and alignment failures are the owner's complaint, measured.
- **A** — the safest change, but the left corner stays covered and inactive tabs stay under 44 pt.
- **B** — best balanced, but its expanding selected pill still squeezes inactive targets (≈43.75 pt at
  393 pt) and leaves four destinations unnamed; two personas could not identify them.
- **C** — the calmest silhouette, but dictation hides behind a hold gesture a "+" does not
  communicate, and its slots measure 41.75 pt — under the floor even in its own spec.
- **B+** — B's grouping with every label visible and a fixed grid; the owner chose it (S-1, 2026-11-07).

Also rejected: keeping the docked bubble and narrowing the orb (G4 cannot be met at 360 dp with both in
the bar row), and an app-bar search icon (ADR-0055's reasoning still holds).

## Consequences

- G4 holds at every phone width, with or without the extension's sixth section.
- Every tab has a visible name; tests that tap a tab by its text work again at phone width.
- The bubble stops being the default phone entry to Quick Access; people who liked it turn it on.
- DESIGN gains §43 (the capsule) and the Q4 / AI1 rows point here; DEVICE-CHECKS gets the phone rows
  (iPhone 393/430, Android 360/412, 2.0× text).
- The extension's screens inherit the capsule and the "More" slot; which section moves into "More" is
  the extension's call.
- Font, colour, glass and motion tokens do not change; typography is
  [ADR-0063](0063-platform-tracking-glass-type-v1-one-formatter.md).
