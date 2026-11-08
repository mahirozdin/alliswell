# ADR-0066 — Phone navigation above 1.3× text: one labelled menu

- **Status:** Accepted
- **Date:** 2026-11-08
- **Related task:** OPH-396 (Epic 35, visual judge round 3, J-02)
- **Amends:** [ADR-0062](0062-phone-navigation-equal-slot-labelled-capsule.md) §1, its large-text
  clause ("above that a long press shows the name in a large-content bubble"), and DESIGN §43 N4.
  The rest of ADR-0062 (five equal labelled slots, "More", the action cluster, the grid) is unchanged.

## Context

ADR-0062 clamps the slot labels at 1.3× and, above that, offers a long press that shows the name in a
bubble (iOS's large content viewer). The bottom-bar review that chose B+ had already asked for more:
"above that scale or whenever names cannot fit, switch to a labeled bottom menu with rows at least
48 pt high that grow with text". The after-Home review (2026-11-08) scored the AX3 screen low for
exactly this: the body grows, the five navigation names stay at 14 pt in a 64 pt capsule, and a hidden
gesture is not a way to read them.

## Decision

1. **Up to 1.3× text nothing changes:** five equal labelled slots (ADR-0062 §1–§2).
2. **Above 1.3× the capsule is one button** (`awTabMenuMode`): the open section's glyph and whole name
   at the reader's size (shrunk only if the 64 pt capsule cannot hold it, never cut) and an unfold
   glyph, on the selection's `primaryContainer` pill. Semantics: one button, "Navigation, Home", hint
   "Shows every section".
3. **The button opens a sheet with every drawn section**, no "More" step: glyph and full name at the
   reader's text size, wrapping rather than ellipsized, rows from 56 pt that grow with the text, the
   open section selected (semantics) with a check. A solid sheet, never glass (G1). Choosing a row goes
   to that section's root, as a tab does.
4. **The long-press bubble is removed.** The Home tab's long press into Quick Access stays a slot
   gesture; above 1.3× Quick Access is reached through the ⚡ and the search palette (ADR-0062 §5).
5. The capsule keeps its 64 pt height and the search orb beside it, so the floating grid (§44) and the
   end-of-list clearance do not move.

## Alternatives considered

- **Keep the bubble** — rejected by both reviews: it is invisible, needs a press-and-slide, and leaves
  five 48 pt icons whose names cannot be read at AX sizes.
- **Let the capsule grow taller with the labels** — five names at 2–3× do not fit 360 dp in any
  height without shrinking or cutting, and a growing bar moves every floating object.
- **Two rows of slots** — halves the reading width again and eats the content height that large-text
  readers need most.

## Consequences

- One extra tap between sections at large text, in exchange for names that can be read and a target
  the whole capsule wide.
- `tab_capsule_test` measures the slots at 1.0/1.3 and the menu at 1.5/2.0/3.1 × five widths × TR/EN ×
  both themes × five and six sections.
- The onboarding tour anchors section steps on the menu button when the slots are not drawn.
