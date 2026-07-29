# ADR-0020 — Recurring tasks: a clamped RRULE subset, materialized as real rows

- **Status:** Accepted
- **Date:** 2026-07-29 (feedback round 12 #1)
- **Related task:** Epic 19 (OPH-204…OPH-208)
- **Related:** [ADR-0013](0013-local-first-search.md) (the cross-language parity-fixture
  pattern this reuses), [ADR-0004](0004-ids-timestamps-schema-conventions.md) (ULIDs, UTC
  `DATETIME(3)`), [ADR-0015](0015-alarm-delivery-and-reminder-profiles.md) (the alarm
  planner that must keep working without learning about recurrence),
  [ADR-0018](0018-quick-links-user-scoped-sync-entity.md) (the "no new sync verb" finding),
  BLUEPRINT §4.3 / §12.17, DESIGN §22 / §25. Sourced research tables: TASKS.md OPH-204.

## Context

Recurring tasks have been counted as a task type since BLUEPRINT §4.3 and have never
existed. The column is the evidence: `tasks.repeat_rule` has been in the schema since the
first migration (`20260714000200_create_projects_tags_tasks.js:100`) and is **not dead
code** — REST accepts it (`routes/tasks.js:131/158`), sync push writes it
(`routes/sync.js:130`), and `db/reminders.js:101` copies it onto reminder rows. It is
worse than dead: it is a live wire with **no human end** — precisely the lie DESIGN §22
("reachability") was written about. OPH-195 parked it as the single biggest missing
feature.

The user's requirement for this round is explicit and repeated: *"çok detaylı configure
edilebilir olmalı… maksimum esneklik… belkemiği özelliklerimizden biri"*, with three
scenario classes named as the acceptance bar — **(A)** "the 31st of every month" must not
break in short months, **(B)** "the 2nd Tuesday of the month", **(C)** "the first Monday
after the 22nd" and "the first/last Friday of the month" — plus "the next 12 months should
be visible in the calendar, nothing beyond".

Constraints that bound the design:

- **Local-first (Epic 06):** the app reads a drift replica; anything the server can compute
  but the client cannot would desynchronise the two.
- **Every downstream surface already reads task rows** — the alarm planner
  (`notifications/planner.dart`), the widget snapshot, search (`*_fold` columns), the home
  grouping and the calendar mirror. None of them know what recurrence is.
- **The sync protocol cannot grow a verb.** `sync_revisions.operation` and
  `client_mutations.operation` are `ENUM('create','update','delete')` and the push
  dispatcher routes anything else to `applyDelete` (ADR-0018's fifth lesson).
- MySQL stays canonical; migrations are append-only (AGENTS §1.8).

## Decision

### 1. The rule is structured JSON, not an RRULE string

`task_series.rule` stores an Ajv-validated object — an RFC 5545 subset with our clamping
semantics attached, never a raw `RRULE:` string:

```jsonc
{
  "freq": "daily|weekly|monthly|yearly",
  "interval": 1,                                   // 1..366
  "byWeekday": [{ "day": "MO", "ordinal": 2 }],    // ordinal: null | 1..5 | -1 (last)
  "byMonthDay": [31],                              // 1..31, or -1 = last day of month
  "byMonth": [1, 7],                               // yearly only
  "end": { "type": "never" }                       // | {"type":"until","until":"2027-01-01"}
                                                   // | {"type":"count","count":10}
}
```

A string would have to be parsed on both sides before it could be validated, shown or
edited; an object is validated by the same Ajv the rest of the API uses, diffed by the sync
layer field-by-field, and round-trips into the dialog without a parser. The RRULE *string*
remains the interchange format if we ever export iCalendar — a serializer, not a storage
format.

`bySetPos` is deliberately absent: the ordinal on `byWeekday` (RFC 5545 allows a numeric
prefix on `BYDAY` only for `MONTHLY`/`YEARLY`, which is exactly where we allow it) covers
every "Nth weekday" case we accept, and two overlapping ways to say the same thing is how
rule engines become untestable.

### 2. Invalid dates clamp backwards — the Outlook reading, not the RFC default

`FREQ=MONTHLY;BYMONTHDAY=31` under plain RFC 5545 produces **nothing** in February: such
instances "MUST be ignored and MUST NOT be counted as part of the recurrence set", which is
why Google Calendar shows a "day 31" series only in 31-day months, while Outlook clamps the
same intent to the last day. RFC 7529 names the behaviour we want — `SKIP=BACKWARD`,
*"a date with an invalid day-of-month is changed to the previous (valid) day-of-month"*.

**We clamp.** For a meeting, "the 31st" is a date; for a task, it is *month end* — a rent
payment or a report that silently skips February is a broken product, and the user said so
first ("kısa ayda sistem bozulmaz"). `byMonthDay: [-1]` ("the last day") is a first-class
value rather than a workaround, so the common case never needs clamping at all.

Two mechanical consequences, both load-bearing:

- Clamping is **per value, then deduplicated**: a window like `[23…29]` in a 28-day
  February clamps 29 onto 28, and the set collapses to `{23…28}` instead of producing a
  duplicate occurrence.
- We are borrowing RFC 7529's *semantics*, not its syntax. `SKIP` "MUST NOT be present
  unless `RSCALE` is present", and a clamped rule is exactly the shape Google flags as
  *"a recurrence rule that cannot be edited in Google Calendar"*. **A clamped rule
  therefore cannot be handed to Google as a recurring event** — which is an independent
  argument for §4 below: we send occurrences, not rules.

### 3. Scenario C is an intersection, not a new field

"The first Monday after the 22nd" is stored as `byWeekday: [{day:'MO', ordinal:null}]` +
`byMonthDay: [23,24,25,26,27,28,29]`. This is RFC 5545's own idiom — with `FREQ=MONTHLY`,
`BYDAY` *limits* `BYMONTHDAY` ("Limit if BYMONTHDAY is present"), and the spec's own
example builds "the first Tuesday after a Monday" from a seven-day `BYMONTHDAY` window.
Three primitives (day-of-month set, weekday set with optional ordinal, and their
intersection) express all three scenario classes; a bespoke `afterDay` field would have
been a fourth concept with its own bugs.

"After the 22nd" is **strictly after** (the window starts at 23) — "sonra" means after.
The dialog builds the window and the sentence layer recognises it (one weekday, ordinal
null, seven consecutive days starting at N+1 → "the first Monday after the 22nd"), so the
user never sees the encoding.

**Named limitation:** when the window runs past the end of a short month and the weekday
does not fall inside it (a February whose 22nd is itself a Monday), that month produces no
occurrence. A monthly rule cannot reach into March, and inventing a rollover would make
`occurrence_date` mean two different things. The "Next 5" preview shows this truthfully —
which is exactly why the preview exists.

### 4. Occurrences are real task rows, in a rolling 12-month window

`task_series` holds the rule; every occurrence is an ordinary row in `tasks` carrying
`series_id` + `occurrence_date`. The materialisation window is **today → +12 months**,
extended by a **daily sweep** as the window rolls forward; the ceiling is **400 rows per
series** (the model cannot exceed 366 by construction — daily/`interval:1` over a leap
year — so 400 is a guard rail, rejected with `TASK_SERIES_TOO_DENSE`).

The server is the only producer. Materialisation runs in one transaction, is idempotent on
`(series_id, occurrence_date)`, and clients never generate occurrences — the rows simply
arrive over the existing sync. This is the whole point: **the widget, search, the calendar
mirror, the alarm planner and the home grouping become correct for recurring tasks without
learning a single thing about recurrence.** The iOS 64-notification ceiling is already
handled upstream — `planner.dart` windows to the soonest `maxPending` fire times — so 400
extra rows cannot flood the OS.

Rule edits rebuild the **future** window in one transaction and never touch the past or
anything completed. Editing scope (`this` / `future` / `all`) rides an ordinary `update`
mutation with a **virtual `seriesScope` field** (the `orderedIds` idiom,
`routes/sync.js:165-176`), because the protocol has no room for a fourth verb.

### 5. The daily sweep is an interval, not a BullMQ repeatable

TASKS OPH-205 said "BullMQ repeatable job". We use the house pattern instead —
`setInterval` + `unref()` + skipped when `env === 'test'` + `app.decorate('seriesGc', …)`,
identical to `plugins/account-gc.js`, `storage-gc.js` and `calendar-sync.js`. Reasons:
`createJobRunner` (`queue/runner.js`) exposes `enqueue`/`idle`/`close` and no repeatable
API; the self-host compose path must work with Redis absent (the runner falls back to an
inline chain); and multi-replica safety already comes from `jobKey` dedupe plus idempotent
materialisation, which is the same guarantee the other three sweeps rely on. Tests call
`app.seriesGc.sweep(now)` directly — the API suite has **no fake-clock infrastructure**
(`vi.useFakeTimers` appears nowhere), and its convention is an injected `now` parameter.

### 6. One rule, two engines, one fixture

Generation is server-side, but the dialog's live "Next 5" preview must agree with it
offline. So the engine exists twice — `apps/api/src/lib/recurrence.js` (the only producer)
and `apps/app/lib/src/core/recurrence.dart` (preview only) — and both suites assert the
same `apps/app/test/fixtures/recurrence_parity.json`, exactly as ADR-0013 pinned the
Turkish fold. Edit one implementation alone and a suite fails.

Time is wall-clock, not elapsed: a series carries an IANA `timezone` (the convention
`tasks.timezone` already uses), occurrences are computed on that calendar, and the local
time-of-day comes from the series anchor. 09:00 stays 09:00 across a DST boundary;
`zonedWallTimeToUtc` (`src/lib/time.js`, two correction passes) does the conversion and is
reused rather than reimplemented.

### 7. `tasks.repeat_rule` is frozen

The column stays (migrations are append-only) but leaves every write path — `writableProps`
and `CAMEL_TO_SNAKE` in `routes/tasks.js`, `TASK_FIELDS` in `routes/sync.js` — and
`serializeTask` keeps returning `null`. The reminder copy in `db/reminders.js` therefore
goes quiet on its own. The series is the single home of "this repeats", and DESIGN §22's
lie ends here.

## Alternatives considered

- **Virtual expansion (compute occurrences on read).** No extra rows, and rule edits are
  free. Rejected: *every* surface would need the engine — including the native iOS/Android
  widget renderers, which read a JSON snapshot and cannot run Dart — and offline search
  over dates that do not exist as rows is not a thing local-first can do. This is the
  decision the whole design turns on.
- **Only the next occurrence, generated on completion (the Todoist model).** Cheapest, and
  genuinely good for habit tasks. Rejected on the stated requirement: the next twelve
  months must be *visible* in the calendar, and one row cannot be visible twelve months
  out. Todoist's `every!` (interval measured from completion, not from the due date) is
  parked as a future rule flavour, not a v1 model.
- **Storing a raw RRULE string** and shipping a library on each side. Rejected: the two
  libraries would disagree about our clamping (which is not in RFC 5545 at all), and Dart
  and JS would need pinned, matching implementations of a spec neither fully implements.
  Our JSON is smaller than the subset either library covers.
- **Skipping invalid dates (RFC 5545 / Google behaviour).** Standards-correct and one line
  simpler. Rejected in §2: for tasks it deletes exactly the occurrence the user cares about.
- **Materialising the full series (until `count`/`until`, no window).** Rejected: an
  endless daily series is unbounded, and the user's own rule was "nothing beyond 12 months".
- **A separate `occurrences` table instead of task rows.** Rejected for the same reason as
  virtual expansion — it recreates every join, filter and index `tasks` already has, and
  every downstream surface would need to union two tables.

## Consequences

- **Recurring tasks come with no new engine downstream.** Calendar dots, widget snapshots,
  search, alarms and completed-history all work because occurrences are ordinary rows.
  OPH-208 verifies each surface with a test rather than assuming it.
- **Row volume is real and bounded.** Up to ~366 rows per series per year, per workspace.
  Combined with the mirror-everything rule of ADR-0021 this means up to ~366 calendar
  events per series, which is why that ADR bounds the backfill to −30 days → +12 months and
  why a Google-side throttle became a prerequisite rather than a nicety.
- **`recordSyncWrite` serialises on the workspace row.** Materialising 366 occurrences
  means 366 sequential increment/select/insert round trips inside one transaction. OPH-205
  measures this first; if it is slow, the batched variant (one revision for the batch, one
  bulk `sync_revisions` insert) is the sanctioned follow-up and supersedes this paragraph.
- **A clamped series can never be represented as a single Google recurring event** (§2).
  We were already sending one event per task; now that is a documented requirement, not an
  accident.
- **The scope question is unavoidable UI.** Because occurrences are independent rows,
  editing one is ambiguous by construction — hence OPH-206's "this / this and future / all"
  and the field-based default (moving one date means *this*; renaming means *future*).
- **"Just this" does NOT detach the row (added 2026-07-29, OPH-206's implementation
  read).** The backlog called for cutting the edited occurrence loose from its series.
  That is wrong here for a mechanical reason: the row's `(series_id, occurrence_date)`
  pair is the **slot** that stops materialization from re-creating that day, so
  detaching frees the slot and the next sweep quietly produces a duplicate beside the
  edit. The row therefore stays in the series — which is also the honest description
  (it *is* that occurrence, modified) and matches Google's modified-instance model.
  The two columns divide the work: `occurrence_date` says *which* occurrence this is
  and never moves; `due_at` says when it actually happens and is free to.
- **A scoped date edit propagates as a time of day, not as a date.** Days come from the
  rule; "make it 14:00 from now on" moves the series anchor and the affected rows'
  hour. Propagating a whole date across occurrences would land every occurrence on the
  same day, which is not a series at all.
- Deleting a series tombstones its **future** materialised rows only; past and completed
  occurrences stay, because a finished task is a historical fact (DESIGN §20 C4).
- The app gains drift **v14** (`task_series` + two task columns) and a `SeriesStore`.
- A future "every! N days after completion" flavour, iCalendar export, and non-Gregorian
  `RSCALE` all remain additive on this model; none of them is v1.
