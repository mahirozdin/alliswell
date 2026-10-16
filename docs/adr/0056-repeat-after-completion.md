# ADR-0056 — Repeat N days/weeks/months after completion

- **Status:** Accepted
- **Date:** 2026-10-17
- **Related task:** OPH-375
- **Related:** amends [ADR-0020](0020-recurring-tasks-and-materialization.md) (the series
  model; its "every! N days after completion" flavour, parked as additive, is this),
  [ADR-0022](0022-remote-mcp-server.md) (no delete through MCP), DESIGN §25 R10, BLUEPRINT §12.17.

## Context

Recurrence was calendar-anchored only: a rule names days, the server materializes a rolling
12-month window of real task rows (ADR-0020 §4). The 2026-10-16 competitor research (Tasks.org
"repeat from completion date", Todoist `every!`) found the missing case: maintenance and
routines — change the water filter 90 days after you last changed it, descale the kettle a
month after the last time. A fixed calendar is wrong for these: if you do it late, the next
one must move with you.

Constraints: the server stays the only producer of occurrences (ADR-0020 §4); offline
completion must work; the calendar series, including the proof line (monthly on the 31st lands
on Feb 28), must not move by a byte.

## Decision

1. **A `basis` key inside the existing rule JSON.** Absent or `calendar` is ADR-0020's model,
   unchanged and never written; `completion` is "after completion". No new series column, no
   sync field, no replica migration — ADR-0020 chose JSON so rule flavours stay additive, and
   every existing rule stays byte-identical. A completion rule takes `freq` daily / weekly /
   monthly (the owner's list; 12 months says a year), `interval` 1..366, `end` never / until /
   count, and no `byWeekday` / `byMonthDay` / `byMonth`. Both engines validate it
   (`lib/recurrence.js`, `core/recurrence.dart`) and the parity fixture pins
   `nextAfterCompletion` in both.
2. **One open occurrence (the head), spawned by the server.** A completion series has no
   window. Its first occurrence is the task the user turned Repeat on (adopted on any day — there
   is no pattern to miss) or, without one, a row on the anchor. Once any row of the series exists,
   materialization creates nothing, so the daily sweep never resurrects a deleted head.
   Completing the head — through REST PATCH or `/complete`, MCP, or a sync push — calls one hook
   (`onTaskStatusChange`, `db/task-series.js`) inside the completing transaction, which inserts
   the next row through the same `insertOccurrence` the materializer uses (revision, tags, alarm
   reconcile; mirror and pull follow from `recordSyncWrite`).
3. **Next due = completion day on the series' wall clock + interval, at the completed row's own
   time of day** (`zonedWallTimeToUtc`, so 09:00 stays 09:00 across DST). Months clamp backwards
   like the rest of the engine. "When" keeps its day gap to the due date (a When-only task moves
   its When); the alarm keeps its offset from the due time.
4. **Copy semantics.** The next row copies the completed one: title, description, project,
   priority, colour, urgency, acknowledgement, duration, tags. An edit to the head therefore
   carries forward, which is why the app asks no this/future/all question for these series.
   Checklist items are not copied, as with calendar series.
5. **The completion moment comes from the device.** A completion that waited in the outbox
   happened when the user tapped it. The push's `localUpdatedAt` (already in the protocol)
   becomes `completed_at`, clamped to [task created, now]; missing or unparsable falls back to
   the server clock. This changes `completed_at` for every offline completion, series or not —
   it now records the real moment, so a task can move between days in the Completed timeline.
6. **Uncomplete withdraws exactly what completion made.** A server-only column
   `tasks.spawned_from_task_id` (migration `20261017120000`, not serialized, not a sync field)
   names the completed row a spawn came from. Leaving `completed` tombstones the live successor
   that is still unfinished — a successor already completed is history — and sets its
   `occurrence_date` to NULL, freeing the slot (MySQL's unique index skips NULLs) so completing
   again takes the same day. The same column makes a repeated completion (two devices, a retry)
   spawn nothing. Only `completed` advances a series; `cancelled` does not.
7. **The slot is bumped, the due date is the truth.** A daily task completed a day early is due
   on the day the completed one holds; the unique index `(series_id, occurrence_date)` must not
   turn that into an error, so the new row takes the day after the series' last slot.
   `occurrence_date` is a slot, `due_at` is when it happens (ADR-0020 consequences).
8. **Rule edits.** Switching a series to completion (or editing one) keeps the earliest open
   occurrence as the head and tombstones other open ones from today on; with none left, one is
   created at max(anchor, today) unless the rule has ended. A scoped date edit never rewrites a
   completion rule (it names no day), and an "all" edit keeps each row's own due day.
9. **Surfaces (rule 12).** Public API: the existing `/task-series` endpoints take `basis`; the
   Ajv rule schema documents it without constraining it, so a bad value still returns
   `TASK_SERIES_RULE_INVALID`. MCP: new `set_task_repeat` (create or replace a task's rule,
   either basis), `get_task.repeat`, `complete_task.next`. Stopping a repeat stays out of MCP:
   it deletes future occurrences (ADR-0022's delete class).
10. **Stopping keeps the task.** A completion series has nothing ahead of its head, so stopping
    it (Repeat switch off, `DELETE /task-series/{id}` without `fromDay`, a sync delete) removes
    no row: the open occurrence is detached — `series_id`, `occurrence_date` and
    `spawned_from_task_id` set to NULL in a synced update — and stays as an ordinary task.
    Only an explicit `fromDay` (the app deleting the head and stopping in one commit) reaches
    it. Calendar stops are unchanged.

**Named limitation.** Offline, the next occurrence and its alarm appear only after the device
next syncs: the device does not create rows. Completing a task offline and staying offline past
the next due date means that alarm rings late — on the next sync.

## Alternatives considered

- **Optimistic client spawn with a client-proposed id.** Rejected: it breaks "the server is the
  only producer", leaves ghost rows when the completion is rejected (LWW, archived task, stale
  series), and the device has no IANA timezone database to place 09:00 on the series' clock.
- **Count from the due date instead of the completion.** That is the calendar series; the owner
  asked for the completion moment ("late or early").
- **Template-based copy (like calendar series).** Rejected: an edit to the open occurrence
  would be lost on the next one unless the app asked the scope question — and there are no
  siblings for "this / future / all" to choose among.
- **A `basis` column on `task_series`.** Rejected: two writers for one rule, a sync field, a
  replica migration — for a value the JSON already carries whole.

## Consequences

- Easier: maintenance and routines are expressible; the series machinery, alarms, mirror and
  pull needed no new concept.
- Harder: three completing doors call the hook (`updateTask`, `applyStatusTransition`, the sync
  `task.afterUpdate`); a new door must call it too. The EE ticket work flow goes through
  `applyStatusTransition` / `updateTask` and is covered; the importer creates rows (already
  completed or not) rather than transitioning them, so an import never spawns.
- `completed_at` from offline pushes is the device moment (clamped), not the receipt time.
- Not built (follow-ups if wanted): mapping Todoist `every!` / TickTick from-completion in the
  importer, and quick-add syntax for after-completion.
