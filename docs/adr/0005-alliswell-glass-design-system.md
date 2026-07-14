# ADR-0005 — "AllisWell Glass" design system (permanent visual language)

- **Status:** Accepted
- **Date:** 2026-07-15
- **Related:** design round 1 (user request: modern 2026 "Liquid Glass" look,
  UX/contrast first, documented permanently); docs/DESIGN.md; AGENTS.md hard rule 11

## Context

Until now the app shipped on a bare `ColorScheme.fromSeed` Material 3 default —
functional, but generic ("kurumsal kalite" bar not met) and with real UX gaps:
amber icons at ~2:1 contrast on white, borderless-looking inputs, no dark-mode
tuning, no documented rules, so every new screen re-invented styling. The user
asked for a modern Apple-2026 Liquid-Glass-inspired redesign with an explicit
constraint: **visibility/contrast of inputs and clickable areas outranks the
aesthetic**, and the system must be documented so ALL future development keeps
visual continuity.

## Decision

1. **One binding design language, "AllisWell Glass",** specified in
   [docs/DESIGN.md](../DESIGN.md) and enforced as AGENTS.md hard rule 11.
   Design continuity is part of the Definition of Done for every future UI task.
2. **Glass is chrome-only.** Backdrop blur (`GlassSurface`, σ=18) is allowed for
   the navigation rail/bottom bar over a static `AuroraBackground` wash; body
   text, forms, lists, sheets and dialogs stay on solid surfaces. Rationale:
   text over live blur cannot guarantee WCAG contrast.
3. **Hand-tuned `ColorScheme` per brightness** (no `fromSeed`): every role pair
   is WCAG-verified (text ≥ 4.5:1, icons/interactive borders ≥ 3:1) by
   `scripts/design/contrast.py`, which must print `FAILURES: 0` before palette
   changes ship. Brand primary stays `#2563EB` (light) / `#8AB4FF` (dark).
4. **Design tokens as code:** `AwTokens` (`ThemeExtension`) +
   `AwSpace`/`AwRadius`/`AwMotion` in `apps/app/lib/src/theme/tokens.dart`;
   all component styling centralized in `buildAwTheme()` (`theme.dart`).
   Raw hex/`Colors.*` in widgets is banned (exceptions: user-picked entity
   colors, brand mark).
5. **Semantic colors adapt lightness per theme, never hue** — e.g. priorities
   stay green/amber/orange/red in both modes (`taskPriorityColor(priority,
   brightness)` replaced the old fixed palette; the old light-only values
   failed 3:1 on white). Favorite/pin stars use the `warning` token instead of
   `Colors.amber` (1.97:1 → 5.02:1 in light mode).
6. **System fonts, no webfonts:** SF Pro/Roboto/Segoe via platform defaults,
   tuned weights/tracking — native feel, fully offline, zero payload.
7. **UX floors baked into the theme:** filled inputs with visible outline +
   2 px focus ring, ≥ 44 px tap targets (`materialTapTargetSize.padded`,
   IconButtons for icon actions), circular checkboxes, drag handles on sheets,
   password visibility toggles, error banners with icon (never color-only),
   shared `AwEmptyState`/`AwErrorState`/`AwInlineError` widgets, motion capped
   at 150–320 ms.

## Consequences

- All 15+ screens/widgets were migrated in one pass; widget tests updated where
  the OLD contract was asserted (fixed priority hex values; "everything fits in
  a 600 px window without scrolling" assumptions became `dragUntilVisible`).
- The test-visible API of `task_visuals.dart` changed:
  `taskPriorityColor(String)` → `taskPriorityColor(String, Brightness)`.
- New screens inherit the language for free via `buildAwTheme` — deviating now
  requires editing docs/DESIGN.md in the same change, which keeps drift visible
  in review.
- Backdrop blur costs some GPU on low-end web targets; contained by using it
  only on two chrome surfaces and a static (non-animated) background wash.
- The aurora veil makes scaffold backgrounds translucent; any future
  full-screen custom painting must go through `AuroraBackground`/`veil` tokens
  instead of opaque `Scaffold.backgroundColor` overrides.
