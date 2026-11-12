# ADR-0068 — Urgent alarms in the same minute ring as one alarm

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related task:** OPH-439, OPH-440, OPH-441, OPH-442, OPH-443, OPH-444, OPH-450, OPH-454
  (issue #47)
- **Amends:** [ADR-0015](0015-alarm-delivery-and-reminder-profiles.md) decision 9 (one AlarmKit
  alarm per reminder becomes one per minute; the cap of 8 counts minutes)

## Context

Issue #47: several urgent alarms in the same minute overlap on iOS. Snooze and closing the app
could not silence them. The owner proposed "one urgent alarm per minute": block the second one at
creation, offer to move it to the next free minute, and refuse it on the server (409) for REST and
MCP too.

What the platform and the product say:

1. **Same-minute AlarmKit alarms are unreliable.** Apple DTS: which of several alarms scheduled for
   the same time activates "is non-deterministic", and a physical button dismisses every alerting
   alarm. Developers report two alarms in one minute that both stayed silent.
2. **Alarms a few minutes apart are not safe either.** A report on iOS 26.6 shows each new AlarmKit
   alarm silencing the one before it while that one stays `.alerting`; stopping the earlier one
   makes the later one audible again. Spreading a collision over 09:00, 09:01 and 09:02 therefore
   trades one clash for three overlapping alerts and three separate silencing actions — the exact
   complaint of #47.
3. **Collisions are normal, not rare.** The default task time and the default urgent alarm (DESIGN
   §26 C1/C2) put many tasks on the same minute. A blocking rule would show its dialog constantly.
4. **The data is fine.** Two tasks at 09:00 are a correct plan; only the sound is the problem.

## Decision

1. **One minute, one alarm.** Every active urgent occurrence whose effective instant falls in the
   same UTC minute belongs to one group. A group is **one** AlarmKit alarm (members = the sorted,
   de-duplicated task ids; the instant = the earliest member's, floored to the second), **one**
   notification chain on iOS < 26 and Android (payload carries ids only, I-13) and **one** ring
   screen that lists every member. A group of several shows "3 acil alarm" and names no task on
   the lock screen. A task whose remind and due instants share the minute is one member.
2. **A group action is one batch.** "Tümünü ertele" and "Tümünü onayla" — in the app, on the
   AlarmKit alert or on the notification — write one event, one receipt and one transaction, with
   one outbox mutation per task. A row action moves only its own task.
3. **Creation is never blocked.** The create sheet, task detail and quick add show one info line
   when the chosen minute already holds another task's urgent alarm ("09:00’da 2 acil alarm
   birlikte çalacak" + "Saati değiştir"). Save is never disabled; there is no dialog and no
   automatic shift.
4. **No server rule.** REST, MCP and sync accept any minute: no 409, no shift, no minute table on
   the server. A task created by MCP, by REST or on another device is grouped on each device like
   any other — the grouping lives where the sound is made.
5. **A snooze joins the occupied minute.** An in-app or notification snooze writes its target
   unchanged. When that minute already rings for another task, the planner adds the snoozed task to
   that minute's group; the snooze tile says "09:05’te çalar · başka alarmla birlikte" before the
   tap.
6. **The native snooze is the one exception: +1 minute.** When the AlarmKit alert's snooze runs
   while Dart is not running, Swift schedules the new alarm itself and cannot regroup alarms it did
   not build. So, only there, while the App Group ledger already holds **another** alarm in the
   target minute, the target moves 60 s later, at most 30 times (then the last target is kept).
   Swift reads only its own ledger — there is no shared minute table. Dart writes the native
   `untilMs` **unchanged** when it applies the event, so the alarm, the task row and every other
   device agree on one instant. The exact rule is in [NOTIFICATIONS.md](../NOTIFICATIONS.md) §2b.3.

## Alternatives considered

- **Block, offer the next free minute, refuse with 409 (the owner's first proposal).** On
  2026-11-12 the owner chose grouping instead. Shifting spreads one collision over adjacent minutes,
  which is worse on AlarmKit (Context 2); the default flow would raise the dialog all day
  (Context 3); and a server rule would change REST and MCP behaviour for every client.
- **"Save as a normal reminder" when the minute is taken.** Quietly turns an alarm the user asked
  for into a notification that Focus can bury.
- **Dart shifts snoozes too, from a minute table Dart writes and Swift reads.** Two runtimes
  computing the same shift from a shared table is a second source of truth and a parity fixture to
  keep alive. Dart can always regroup, so it does not need to shift.
- **Several AlarmKit alarms in one minute, trusting the OS.** Context 1.

## Consequences

- **Easier:** one sound and one way to silence it, whatever created the alarms; nothing changes on
  the server, so older clients and the public API are unaffected; minutes with one member keep the
  id they had, so the upgrade causes no churn.
- **Harder:** the ring screen needs a list mode and row actions; the planner, the occurrence
  validity check and the overlay all reason per minute; the AlarmKit cap of 8 now counts minutes,
  not reminders.
- **Known edges:** a native snooze can ring up to 30 minutes after the preset when the following
  minutes are all taken — the task row shows the real time once the app runs. Two groups in
  adjacent minutes can still overlap on AlarmKit (Context 2); it is rarer than the clash it
  replaces and is a device check, not a rule.
- **Follow-up:** none required. A server-side minute rule would need a new ADR that answers
  Context 2 first.

## Note — 2026-11-12, as shipped (OPH-439…444, OPH-450, OPH-454)

The decision stands as written; checked against the code that shipped in Epic 36:

- Groups are keyed by `floor(ms / 60000)`. A minute with one task keeps its earlier id, title and
  body, so the update caused no churn (decision 1).
- The merged notification chain carries `taskId` (the first), `taskIds`, `reminderIds` and
  `chainIndex` — ids only. Its acknowledge button acknowledges exactly the listed `reminderIds`.
  The buttons of the fallback notification left by a failed native group snooze act on every
  member (decision 2).
- The native +1 minute shift reads only the ledger records other than the snoozed alarm, floors the
  target to the second and stops after 30 tries; a group snooze or stop parks one event carrying
  every member (decision 6).
- An action pulled outside a plan pass (on resume or on `onActionsPending`) commits before the
  replica list re-emits. Until it does, the next pass treats that event as having no receipt, so
  the natively snoozed group alarm is not cancelled in between. The rule is in NOTIFICATIONS §2b.3
  "Plan pass" (OPH-454).
