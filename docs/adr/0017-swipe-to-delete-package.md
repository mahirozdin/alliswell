# ADR-0017 — `flutter_slidable` for the reveal-then-tap delete affordance

- **Status:** Accepted
- **Date:** 2026-07-28
- **Related task:** OPH-184 (feedback round 10 #1)
- **Related:** [DESIGN.md](../DESIGN.md) §19, AGENTS.md hard rule 6 (a new
  dependency category needs an ADR)

## Context

Round 10's first complaint was that a task could be created, edited, scheduled,
tagged, attached to, mirrored to a calendar and alarmed — but **not deleted**.
The engine was complete from v1 (optimistic local delete, outbox mutation,
server-side subtree tombstone, attachment cascade); no list ever grew a button.

The user described the interaction precisely, and it matters:

> "listeden sağa kaydırınca Apple'da açılan sağda silme ikonu oluyor ya onunla
> silme — **ama önce yarım açılıyor, sonra adam tıklıyor** şeklinde"

That is the iOS list idiom: the swipe **reveals** a destructive button and
waits; the button is what deletes. It is deliberately not a swipe-through.

Flutter's built-in `Dismissible` implements the *other* thing — one gesture and
the row is gone. It can be bolted into shape with `confirmDismiss` (a dialog
after the fling), but that is a different interaction with a different feel, and
it puts a modal in the path of the app's most repeated destructive action.

So the choice was: adopt a package, or hand-roll the pane.

## Decision

**Use `flutter_slidable` (4.0.3), wrapped in our own `AwSwipeToDelete`.**

The package supplies exactly the part that is hard and boring: drag tracking,
the open/close snap with fling velocity, `closeOnScroll`, RTL handling via
`useTextDirection`, and cross-row auto-close through `groupTag` +
`SlidableAutoCloseBehavior` (one ancestor in `app.dart` covers every list in the
app). Everything a user actually sees stays ours — `AwSwipeToDelete` owns the
pane's colors (`colorScheme.error` / `onError`), the radius, the icon, the
label, the semantics, and the pending-delete hiding that makes undo work.

It is about as small a dependency as exists: **zero transitive packages**
(`dependencies: [flutter]`), and its constraints (`sdk >=3.6.0 <4.0.0`,
`flutter >=3.27.0`) sit comfortably under this repo's Dart 3.12 / Flutter 3.44.

## Alternatives considered

- **Hand-roll it** (`Stack` + `GestureDetector` + `AnimationController`).
  Tempting — the visuals are ours anyway and it is maybe 150 lines. Rejected
  because the 150 lines are the wrong 150: fling thresholds, velocity-based
  snapping, closing when the list scrolls, closing when a sibling opens, and the
  gesture-arena interaction with a horizontal `PageView` (the board) are exactly
  the things that are subtly wrong for months. This widget will carry every
  destructive action in the product; "boring and proven" (AGENTS §8) points at
  the package here, not away from it.
- **`Dismissible` + `confirmDismiss`.** Free, in-framework. Rejected: it is a
  swipe-through with a modal, not a reveal-and-wait, so it answers a different
  request — and it makes the most repeated destructive action modal, which
  DESIGN §19 D3 deliberately avoids for leaf deletes.
- **`Dismissible` with no confirmation.** Rejected outright: one careless flick
  in a list would destroy a task. The user asked for two steps for a reason.
- **A long-press context menu instead of a swipe.** Already taken — the board's
  long-press is drag-to-move (OPH-168), and overloading it would break that.

## Consequences

**Easier.** One `AwSwipeToDelete` now serves tasks, captures, notes, projects
and files; adding it to a new list is one wrapper. Cross-list auto-close came
free with a single ancestor widget. And the pane composes with the undo model:
because the widget also hides its row while the id is pending, "the row is
gone but nothing is written" needed no per-list bookkeeping.

**Harder / accepted costs.**

- One more package to keep current. It is unlikely to churn (no transitive
  deps, stable API since 3.x), but a Flutter breaking change lands on us.
- `groupTag` auto-close only works below a `SlidableAutoCloseBehavior`. Ours is
  in `app.dart`; a future surface rendered outside the app tree (a screenshot
  harness, an isolated golden) will not get it, and that is a silent
  degradation rather than an error.
- Swipe is a gesture, and gestures are not universal. DESIGN §19 D2 makes the
  visible equivalent mandatory — row menus, the detail app bar, the board's
  move sheet — precisely so this package is never the only way to delete.

**Deliberate limit.** Board cards are NOT swipeable (DESIGN §19 D6): the phone
board is a horizontal `PageView`, and a horizontal action pane there would
either fight the pager or cost the way back to the List. The board's move sheet
carries delete instead.
