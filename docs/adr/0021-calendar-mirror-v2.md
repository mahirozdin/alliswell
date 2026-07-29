# ADR-0021 — Calendar mirror v2: every task is on the calendar, and it is not a setting

- **Status:** Accepted
- **Date:** 2026-07-29 (feedback round 12 #2)
- **Related task:** Epic 19 (OPH-209 / OPH-210)
- **Related:** [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (the
  mirror queue), [ADR-0007](0007-google-inbound-sync-and-conflict-policy.md) (echo
  suppression, conflict policy), [ADR-0020](0020-recurring-tasks-and-materialization.md)
  (occurrences are rows, which is why they mirror at all), BLUEPRINT §7.1 (rewritten
  this round), DESIGN §17 D1

## Context

The owner's sentence was flat: *"eklenen her task takvimde gözükmeli, bu bir seçenek
bile olmamalı."* Today it is the opposite — twice over:

1. `tasks.calendar_mirror_enabled` is an **opt-in switch** (OPH-081), so a task
   mirrors only if the user found and flipped it; and
2. even with it on, `lib/mirror.js` returns an event only when the task has a
   `scheduled_*` block, a `due_at`, or an urgent reminder — the old §7.1 rule.

The result: an ordinary dated task, created the ordinary way, **never reaches the
calendar at all**. The feature reads as broken because the default is wrong, not
because the machinery is missing.

Two questions had to be answered before touching it. First, whether a task belongs on
a calendar as an **event** or as the provider's own **todo** (Google Tasks, Apple
Reminders) — the owner's preference was explicit: *"destekliyorsa birebir öyle."*
Second, what "every task" costs: today there is **no rate limiting and no 429 handling
anywhere** in `src/lib/google.js` (a bare `fetch`; the only backoff is BullMQ's five
attempts), and Epic 19 just made it possible for one series to own ~366 tasks.

## Decision

### 1. The switch dies; every task mirrors

`calendar_mirror_enabled` stops being a user-facing choice. No surface writes it, and
the mirror no longer asks. The block rule (BLUEPRINT §7.1, rewritten):

- `scheduled_start/end` wins when present — dragging our event in Google writes exactly
  that, and the user's drag outranks our derivation (OPH-192 behaviour, unchanged).
- Otherwise a dated task is a **30-minute block** starting at its time. A block that
  would cross midnight is clamped to the day, so a 23:59 due time reads **23:29–23:59**.
- An **undated** task lands on its **creation day**, same half-hour rule — the owner's
  explicit instruction ("ekleniş tarihi baz alınır").

### 2. Completed tasks keep their block, marked

A completed task's event **stays**, with its summary prefixed `✓`. This is the owner's
call and it matches how Google's own Tasks integration renders finished items. The
calendar then answers "what did I actually do that week", which is the question a
calendar is best at; the archive (DESIGN §20 C4) answers a different one.

`cancelled`, `archived` and deleted tasks still lose their event — those are not
records of work done, they are work withdrawn.

### 3. The column survives as a machine flag, not a switch

`calendar_mirror_enabled` is **not** dropped (migrations are append-only, and the value
is still needed): it becomes an internal **suppression** flag. This is load-bearing —
`lib/inbound.js` interprets the user deleting our event **in Google** as "stop
mirroring this task" and writes `false` into exactly this column. Kill the column and
that branch has nowhere to record the user's wish; kill the branch and we re-create an
event the user deliberately deleted, forever. So: no UI ever writes it, one inbound
path does, and the mirror keeps honouring it.

### 4. Backfill is a window, not a history sweep

Existing tasks are mirrored over **−30 days → +12 months**, the same horizon
recurrence materializes into (ADR-0020 §4). Rationale: an unbounded backfill on a
large workspace is tens of thousands of API calls for events nobody will scroll back
to, and the +12 month edge is where the rows stop existing anyway.

### 5. Rate limiting is a prerequisite, not a follow-up

Because §1 multiplies outbound calls, `src/lib/google.js` gains 429/`Retry-After`
handling, exponential backoff and a concurrency cap **before** the backfill exists.
Not doing this first would turn the first large workspace into a quota incident.

### 6. Native todo mapping (Google Tasks / Apple Reminders): rejected for v1, with
the condition for revisiting

The owner asked for a direct todo mapping *if the provider supports it properly*. It
does not:

- **Google Tasks discards the time.** The API reference says of `due`: *"Only date
  information is recorded; the time portion of the timestamp is discarded when setting
  this field"*, and — decisively — *"It isn't possible to read or write the time that a
  task is scheduled for using the API."* Every AllisWell task has a time (the default
  is 23:59, alarms fire on it, the 30-minute block derives from it). Mapping to Google
  Tasks would silently drop the one field the whole reminder system stands on, which is
  the false-claim rule DESIGN §11 A4 exists to prevent.
- **Google Tasks has no push channel.** Calendar, Gmail and Drive support watch
  channels; Tasks does not — its own guidance is to poll. A second, poll-only lane
  beside the incremental Calendar sync is a whole subsystem for a strictly lossier
  representation.
- **Apple's `EKReminder` is a separate permission and device-local.** Since iOS 17 it
  needs `NSRemindersFullAccessUsageDescription` / `requestFullAccessToReminders`,
  distinct from calendar access, and it has no server side at all — a reminder written
  on one device is not a reminder our backend can reconcile.

**Revisit when** Google Tasks can carry a time of day *and* signal changes (push or a
real change token). Until then the event block is not a compromise, it is the only
representation that keeps the time — and the time is the product.

### 7. Consent says what leaves the device

Because "every task" now includes tasks the user never thought of as calendar items,
the Google connect screen states plainly that **all tasks** will be written to the
selected calendar. Consent for a broader flow has to be broader consent.

## Alternatives considered

- **Keep the switch, default it on.** Cheapest. Rejected: the owner asked for it not to
  be a setting, and a defaulted-on switch is still a switch to explain, to sync, and to
  get wrong on a second device.
- **Mirror only "important" tasks** (urgent, or with a project). Rejected: any
  heuristic here is us deciding what belongs on the user's calendar, which is exactly
  what the old rule did badly.
- **Google Tasks for undated tasks, events for dated ones.** Tempting — Tasks handles
  dateless items natively. Rejected: two representations of one task, two sync lanes,
  and a task that changes representation when it gains a date.
- **Full history backfill.** Rejected in §4.
- **Delete the event on completion (today's behaviour).** Rejected by the owner in §2.

## Consequences

- The mirror queue's volume rises sharply: every task write now derives an event.
  `enqueueWorkspaceMirrorSweep` loses its `calendar_mirror_enabled` filter and gains
  the window filter, and the throttle in §5 becomes the thing that keeps it civil.
- **Two mirrors must not contradict each other.** The Google mirror (server) and the
  Apple EventKit mirror (device, `features/calendar/apple/apple_mirror.dart`) implement
  the same rule in two languages, so they get the ADR-0013 treatment: a shared fixture
  both suites assert (`test/fixtures/calendar_block_parity.json`). Two platforms
  disagreeing in front of the user is what DESIGN §17 D1 forbids for dates.
- A completed task keeps an event, so the "gone" set in `mirror.js` shrinks to
  cancelled/archived/deleted — and the inbound side must not read a `✓` summary as a
  user edit (the echo rule already covers it: our own write stamps the etag).
- Recurring series become the heaviest calendar writers in the product: one series is
  up to ~366 events inside the window. That interaction is why §4 and §5 are in the
  same ADR as §1.
- The old opt-in behaviour disappears for existing users with the switch OFF: their
  tasks will appear on the calendar after the backfill. That is the intended change,
  and the connect-screen copy (§7) is where it is disclosed.
- **Suppression needed its own column (added 2026-07-29, OPH-210's implementation
  read).** §3 said `calendar_mirror_enabled` would carry the new meaning. It cannot:
  the column defaults to `false`, so the moment "false" started meaning "do not
  mirror", every task that already exists would have read as suppressed — the exact
  opposite of the change. `tasks.calendar_mirror_suppressed_at` (nullable) carries it
  instead, written only by `lib/inbound.js`; the old column stays where it is, dead
  but harmless, because migrations are append-only.
