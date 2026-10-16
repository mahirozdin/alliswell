# ADR-0053 — "When" and duration on tasks

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-372

## Context

A task can be done on one day and be due on another (the Things model; the strongest request in
the 2026-10-16 research). AllisWell already stored three times but asked for one:

- `due_at`: the deadline. It owns the alarm and Overdue, and it is the only date on the task screen.
- `scheduled_start_at` / `scheduled_end_at`: the calendar block. Only a drag in Google or Apple
  Calendar writes them (ADR-0007, ADR-0050).
- `start_at`: in MySQL, REST and sync since v1.0, but no screen ever asked for it.

`estimated_minutes` had no UI either. Every mirrored calendar block was a fixed 30 minutes
(ADR-0021), in two places that a shared fixture keeps equal.

## Decision

1. **Three times, never merged.** `start_at` is "when": the day the task enters Today. The
   deadline stays on `due_at`, and the alarm stays wherever it was. Overdue is computed from
   `due_at` only. If the fields were merged, pulling a Friday deadline's "when" to Monday would
   move the alarm too. A calendar drag or resize still writes only `scheduled_*`, never
   `start_at` or `estimated_minutes`.
2. **"When" is a day.** The app stores the chosen day's local 00:00 in UTC (`awWhenIso`) and picks
   it with a date-only picker (`awPickDate`; DESIGN §17 D5 is amended: D5 covers fields that store
   a time). Only the local date is ever read. For a device in a different timezone from the one
   that wrote the value, the day can shift by one. That is the same class of edge as a 23:59
   `due_at`, and it is accepted for v1.
3. **The filing rule (the plan day).** The app's `taskIsOverdueOn` and `taskPlanDay` apply it:
   - Overdue is decided first, and only by the deadline's day being before today.
   - Otherwise a task is filed under its "when" day. Once that day has come it rolls forward to
     today, and it is never later than the deadline's day.
   - A task with no "when" is filed under its due day. A task with neither date goes to No date.

   The same rule drives Home's buckets and per-day split, the month-grid dots (the "when" day is
   marked), the widget's buckets, `next` and `openToday`, the AI live context, and the MCP today
   view: due today, or started and not overdue.
4. **Recurring tasks.** "When" belongs to one occurrence. It is not a series template field, and
   editing it asks no scope question. Duration is already a server `TEMPLATE_FIELD` and
   `PROPAGATED_FIELD` (ADR-0020), so a duration edit asks the scope question, and the create
   sheet's new series template carries it.
5. **The block is as long as the task.**
   - The block length is `estimated_minutes` when it is above 0, capped at 1440. Otherwise it is
     30.
   - The block is clamped to its day: it ends by 23:59 and starts no earlier than 00:00.
   - A scheduled start with no end falls back to the same length.
   - "When" does not move the block. The anchor is still the scheduled start, then the due time,
     then the creation time.
   - `mirror.js` `blockMinutes` and `apple_mirror.dart` `appleBlockMinutes` are both held to
     `calendar_block_parity.json`, which now has a `minutes` field (ADR-0021).
6. **Exposure (rule 12).**
   - The public REST API already read and wrote both fields, so no route changed.
   - MCP gains `startAt` and `estimatedMinutes` on `create_task` (added after cloning the AI
     `TASK_ITEM`, which is not changed), `estimatedMinutes` on `update_task`, both fields in
     every task read, and the today view rule above (ADR-0022).

## Alternatives considered

- **Reuse `scheduled_start_at` for "when".** Rejected. A calendar drag would then change the day
  a task shows in Today. A day-only value would also derive a 00:00 block.
- **Store "when" as a plain date column.** Rejected. It would need a migration, a sync field
  type and a replica column, when `start_at` already flows end to end.
- **Let "when" move the calendar block.** Rejected. The calendar shows when the work happens
  (the due time or the dragged block), and "when" is a coarser planning day.
- **A "when" chip on task rows.** Rejected. The row is already filed under its "when" day, and
  the due chip keeps stating the deadline. Rows get a small duration chip instead.

## Consequences

- A task with a duration triggers a one-time Google and EventKit update on its next write. This
  includes tasks imported from Todoist with a duration. No backfill job runs: a task untouched
  since import keeps its 30-minute event until it changes.
- Inbound echo comparison uses the derived block, so a changed duration is our own write and
  not a user move (ADR-0007).
- OPH-373 (the natural-language parser) writes the same store body keys:
  `'startAt': awWhenIso(day)` and `'estimatedMinutes': int`.
