import 'dart:async';
import 'dart:convert';

import '../features/tasks/data/task_store.dart';
import '../sync/db/database.dart';
import 'alarm_log.dart';
import 'alarmkit.dart';
import 'gateway.dart';
import 'reminder_store.dart';

/// Notification action ids (OPH-062/063). Snooze presets mirror the server's
/// (BLUEPRINT §4.9); "custom" is the plain tap — it opens the task detail
/// where every date control lives.
const kActionComplete = 'complete';
const kActionAcknowledge = 'acknowledge';

/// Silence this task's alarms indefinitely (OPH-178) — straight from the
/// notification, without opening the app and without completing the task.
const kActionMute = 'mute';
const kActionSnoozePrefix = 'snooze:';

String snoozeActionId(String preset) => '$kActionSnoozePrefix$preset';

/// Routes one notification interaction into the local-first stores — the
/// writes are ordinary outbox mutations, so they work identically online and
/// offline (the checklist's "call endpoint when online; enqueue when offline"
/// collapses into a single path since OPH-054).
///
/// An event with an `eventId` (a pulled AlarmKit action, OPH-427) is applied
/// exactly once — see [_applyOnce]; it needs [db]. True when the event
/// changed something or was handled, false when it was a redelivery of one
/// already applied (or not ours).
Future<bool> handleNotificationEvent(
  NotificationEvent event, {
  required TaskStore tasks,
  required ReminderStore reminders,
  required void Function(String location) navigate,
  AlarmLog? log,
  AwDatabase? db,
}) async {
  if (event.eventId != null) {
    if (db == null) {
      throw ArgumentError.notNull('db'); // a receipt needs its database
    }
    return _applyOnce(
      event,
      db: db,
      tasks: tasks,
      reminders: reminders,
      log: log,
    );
  }
  final raw = event.payload;
  if (raw == null || raw.isEmpty) return false;
  Map<String, dynamic> payload;
  try {
    payload = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return false; // not ours / corrupted — never crash on a notification tap
  }
  final taskId = payload['taskId'] as String?;
  final reminderId = payload['reminderId'] as String?;
  if (taskId == null) return false;

  final action = event.actionId ?? '';
  // A touched notification is the ONLY delivery proof iOS ever gives us
  // (OPH-176) — record it, and never claim more than that.
  await log?.record(
    event: action.isEmpty ? AlarmLogEvent.interacted : AlarmLogEvent.action,
    lane: AlarmLogLane.notification,
    slotIndex: payload['chainIndex'] as int?,
    taskId: taskId,
    reminderId: reminderId,
    detail: action.isEmpty ? null : action,
  );
  if (action.isEmpty) {
    navigate('/tasks/$taskId');
    return true;
  }
  if (action == kActionComplete) {
    await tasks.complete(taskId);
    return true;
  }
  if (action == kActionMute) {
    await tasks.muteAlarms(taskId);
    return true;
  }
  if (action == kActionAcknowledge) {
    if (reminderId != null) await reminders.acknowledge(reminderId);
    return true;
  }
  if (action.startsWith(kActionSnoozePrefix)) {
    await tasks.snooze(
      taskId,
      preset: action.substring(kActionSnoozePrefix.length),
    );
    return true;
  }
  return false;
}

/// One receipted event in ONE transaction (NOTIFICATIONS §2b.3): the receipt
/// first — already there means a redelivery, a no-op — then the model write
/// and its outbox mutation for every member. A throw anywhere rolls the
/// receipt back with the write, so the next pull applies the event again.
/// The alarm-log row is written once, after the commit, under the event's
/// lane.
Future<bool> _applyOnce(
  NotificationEvent event, {
  required AwDatabase db,
  required TaskStore tasks,
  required ReminderStore reminders,
  AlarmLog? log,
}) async {
  final eventId = event.eventId!;
  final raw = event.actionId ?? '';
  final action = raw.startsWith(kActionSnoozePrefix) ? 'snooze' : raw;
  final preset =
      event.preset ??
      (raw.startsWith(kActionSnoozePrefix)
          ? raw.substring(kActionSnoozePrefix.length)
          : null);
  final payload = _payloadOf(event.payload);
  final members = <String>{
    ...event.taskIds,
    if (event.taskIds.isEmpty && payload['taskId'] is String)
      payload['taskId'] as String,
  }.toList();
  final reminderId = payload['reminderId'];
  final now = DateTime.now().toUtc();
  final pressedAt = event.pressedAtMs == null
      ? now
      : DateTime.fromMillisecondsSinceEpoch(event.pressedAtMs!, isUtc: true);

  // A native target is written unchanged (owner answer 3); only an entry
  // converted from v1 computes one, from its press time.
  DateTime? until;
  if (action == 'snooze') {
    if (event.untilMs != null) {
      until = DateTime.fromMillisecondsSinceEpoch(event.untilMs!, isUtc: true);
    } else if (preset != null) {
      try {
        until = TaskStore.snoozeUntilFor(preset, now: pressedAt).toUtc();
      } on ArgumentError {
        until = null; // an unknown preset: recorded, nothing moved
      }
    }
  }

  var applied = false;
  await db.transaction(() async {
    final fresh = await db.insertReceiptIfAbsent(
      eventId: eventId,
      action: action,
      appliedAt: now,
    );
    if (!fresh) return;
    applied = true;
    for (final taskId in members) {
      switch (action) {
        case 'snooze':
          if (until != null) {
            await tasks.snooze(taskId, until: until, receiptId: eventId);
          }
        case kActionAcknowledge:
          final ids = reminderId is String && reminderId.isNotEmpty
              ? [reminderId]
              : await reminders.urgentReminderIdsAt(
                  taskId,
                  occurrenceFireAtMs: event.occurrenceFireAtMs,
                  dueBy: pressedAt,
                );
          for (final id in ids) {
            await reminders.acknowledge(id, receiptId: eventId);
          }
        case kActionComplete:
          await tasks.complete(taskId, receiptId: eventId);
        case kActionMute:
          await tasks.muteAlarms(taskId, receiptId: eventId);
      }
    }
  });
  if (!applied) return false;

  await log?.record(
    event: AlarmLogEvent.action,
    lane: event.lane,
    taskId: members.isEmpty ? null : members.first,
    detail: [
      action,
      if (members.length > 1) 'members=${members.length}',
      if (until != null) 'until=${until.toIso8601String()}',
      if (action == 'snooze' && until == null) 'no target',
      'origin=${event.origin}',
    ].join(' '),
  );
  return true;
}

Map<String, Object?> _payloadOf(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  } catch (_) {
    return const {};
  }
}

/// A pulled AlarmKit action as the handler's event: its own `eventId`, the
/// v2 action as [NotificationEvent.actionId], lane `alarmkit`. The legacy
/// path's `reminderId` (macOS, an older bridge) rides in the payload.
NotificationEvent notificationEventForAlarmKit(AlarmKitActionEvent event) =>
    NotificationEvent(
      eventId: event.eventId,
      actionId: event.action,
      taskIds: event.taskIds,
      untilMs: event.untilMs,
      occurrenceFireAtMs: event.occurrenceFireAtMs,
      pressedAtMs: event.pressedAtMs,
      preset: event.preset,
      origin: event.origin,
      lane: AlarmLogLane.alarmkit,
      payload: event.reminderId == null
          ? null
          : jsonEncode({'reminderId': event.reminderId}),
    );

/// The Dart side of the AlarmKit pull model (NOTIFICATIONS §2b.3): pull →
/// apply each event in press order → ack it only after its transaction
/// committed → copy native failures into the alarm log. A failed apply stops
/// the pull there: the event stays queued, and the ones after it wait so the
/// order holds.
///
/// Fallback notifications: a native snooze whose own schedule failed left an
/// `aw.fallback.<eventId>` notification behind. It is cleared after the
/// first plan pass that STARTED after the event was applied — that plan rings
/// the snoozed alarm itself, so clearing earlier could leave nothing ringing
/// and clearing never would ring twice. [beforePlan] is the scheduler's
/// `drainActions` seam and [afterPlan] its post-plan hook.
class AlarmKitActionPump {
  AlarmKitActionPump({required this.host, required this.apply, this.log});

  final AlarmKitHost host;

  /// Applies one event; true when it changed something, false for a
  /// redelivery. Throws when the write failed (nothing committed).
  final Future<bool> Function(NotificationEvent event) apply;
  final AlarmLog? log;

  Future<void> _tail = Future<void>.value();
  final List<String> _fallbacksApplied = [];
  final List<String> _fallbacksArmed = [];

  /// One pull, serialized behind any pull already running.
  Future<void> pull() {
    final run = _tail.then((_) => _pullOnce());
    _tail = run.catchError((Object _) {});
    return run;
  }

  /// The scheduler's drain: every fallback applied so far is now in the
  /// model this pass plans from, then whatever is queued is pulled.
  Future<void> beforePlan() async {
    await _tail;
    _fallbacksArmed.addAll(_fallbacksApplied);
    _fallbacksApplied.clear();
    await pull();
  }

  /// After a plan pass: clear the fallbacks that pass planned for.
  Future<void> afterPlan() async {
    if (_fallbacksArmed.isEmpty) return;
    final ids = [..._fallbacksArmed];
    _fallbacksArmed.clear();
    try {
      await host.clearFallbacks(ids);
    } on Object catch (error) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail: 'clearFallbacks failed: $error',
      );
    }
  }

  Future<void> _pullOnce() async {
    final List<AlarmKitActionEvent> events;
    try {
      events = await host.pullPendingActions();
    } on Object {
      return; // transient; the next resume or announcement pulls again
    }
    for (final event in events) {
      try {
        await apply(notificationEventForAlarmKit(event));
      } on Object catch (error) {
        try {
          await log?.record(
            event: AlarmLogEvent.degraded,
            lane: AlarmLogLane.alarmkit,
            detail: 'action ${event.eventId} not applied: $error',
          );
        } on Object {
          // The log shares the database that just failed.
        }
        break; // stays queued; later presses wait behind it
      }
      // A redelivery too: its first apply may have died before the plan,
      // and clearing twice is harmless.
      if (event.action == 'snooze' &&
          event.scheduleOutcome != null &&
          event.scheduleOutcome != 'ok') {
        _fallbacksApplied.add(event.eventId);
      }
      try {
        await host.ackActions([event.eventId]);
      } on Object {
        // Still queued: the next pull finds its receipt and acks it then.
      }
    }
    final alarmLog = log;
    if (alarmLog == null) return;
    try {
      await host.copyNativeFailures(alarmLog);
    } on Object {
      // A failure ring we cannot read now is read on the next pull.
    }
  }
}
