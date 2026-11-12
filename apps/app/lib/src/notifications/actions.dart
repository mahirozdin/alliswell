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
///
/// [onCommitted] hears a receipted event's id the moment its transaction
/// commits, before the alarm-log row: the scheduler's
/// `noteEventApplied` (OPH-454), so no plan pass can see the receipt
/// without knowing the replica list has not caught up yet.
Future<bool> handleNotificationEvent(
  NotificationEvent event, {
  required TaskStore tasks,
  required ReminderStore reminders,
  required void Function(String location) navigate,
  AlarmLog? log,
  AwDatabase? db,
  void Function(String eventId)? onCommitted,
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
      onCommitted: onCommitted,
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
  // A fallback notification (`aw.fallback.<eventId>`, §2b.3 native snooze
  // step 6) stands for a whole grouped alarm: its payload lists every member
  // in `taskIds`, and each button applies to all of them. An ordinary
  // notification carries only `taskId`.
  final listed = payload['taskIds'];
  final members = <String>{
    if (listed is List)
      for (final m in listed)
        if (m is String && m.isNotEmpty) m,
  }.toList();
  if (members.isEmpty) members.add(taskId);

  final action = event.actionId ?? '';
  // A touched notification is the ONLY delivery proof iOS ever gives us
  // (OPH-176) — record it, and never claim more than that.
  await log?.record(
    event: action.isEmpty ? AlarmLogEvent.interacted : AlarmLogEvent.action,
    lane: AlarmLogLane.notification,
    slotIndex: payload['chainIndex'] as int?,
    taskId: taskId,
    reminderId: reminderId,
    detail: action.isEmpty
        ? null
        : (members.length > 1 ? '$action members=${members.length}' : action),
  );
  if (action.isEmpty) {
    navigate('/tasks/$taskId');
    return true;
  }
  if (action == kActionComplete) {
    for (final m in members) {
      await tasks.complete(m);
    }
    return true;
  }
  if (action == kActionMute) {
    for (final m in members) {
      await tasks.muteAlarms(m);
    }
    return true;
  }
  if (action == kActionAcknowledge) {
    final listedReminders = payload['reminderIds'];
    if (reminderId != null && reminderId.isNotEmpty) {
      await reminders.acknowledge(reminderId);
    } else if (listedReminders is List) {
      // A merged urgent chain (OPH-440) names the reminders of its minute:
      // exactly those rang, synthetic ones included.
      for (final id in {...listedReminders.whereType<String>()}) {
        if (id.isNotEmpty) await reminders.acknowledge(id);
      }
    } else if (listed is List) {
      // A fallback names no reminder: every member's urgent reminder that is
      // due by the tap is the one that rang.
      final now = DateTime.now().toUtc();
      for (final m in members) {
        for (final id in await reminders.urgentReminderIdsAt(m, dueBy: now)) {
          await reminders.acknowledge(id);
        }
      }
    }
    return true;
  }
  if (action.startsWith(kActionSnoozePrefix)) {
    final preset = action.substring(kActionSnoozePrefix.length);
    // One target and one write for the whole group, so its members ring
    // again as one (OPH-439).
    await tasks.snoozeBatch(members, until: TaskStore.snoozeUntilFor(preset));
    return true;
  }
  return false;
}

/// One receipted event in ONE transaction (NOTIFICATIONS §2b.3): the receipt
/// first — already there means a redelivery, a no-op — then the model write
/// and its outbox mutation for every member. A throw anywhere rolls the
/// receipt back with the write, so the next pull applies the event again.
/// The alarm-log row is written once, after the commit, under the event's
/// lane; so is the one sync poke for the whole event.
Future<bool> _applyOnce(
  NotificationEvent event, {
  required AwDatabase db,
  required TaskStore tasks,
  required ReminderStore reminders,
  AlarmLog? log,
  void Function(String eventId)? onCommitted,
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
    // A group action is one batch write per store (OPH-439); complete and
    // mute keep their per-task update, inside the same transaction.
    switch (action) {
      case 'snooze':
        if (until != null) {
          await tasks.snoozeBatch(members, until: until, receiptId: eventId);
        }
      case kActionAcknowledge:
        final occurrence = event.occurrenceFireAtMs;
        final listedReminders = payload['reminderIds'];
        if (reminderId is String && reminderId.isNotEmpty) {
          await reminders.acknowledge(reminderId, receiptId: eventId);
        } else if (listedReminders is List) {
          // An in-app list spanning several minutes names the rows it hid:
          // exactly those rang, one listed before its own second included.
          for (final id in {...listedReminders.whereType<String>()}) {
            if (id.isNotEmpty) {
              await reminders.acknowledge(id, receiptId: eventId);
            }
          }
        } else if (occurrence != null) {
          await reminders.acknowledgeBatch(
            members,
            occurrenceMinute: occurrence ~/ 60000,
            receiptId: eventId,
          );
        } else {
          // An entry converted from v1 names no occurrence: every member's
          // urgent reminder due by the press is the one that rang.
          for (final taskId in members) {
            for (final id in await reminders.urgentReminderIdsAt(
              taskId,
              dueBy: pressedAt,
            )) {
              await reminders.acknowledge(id, receiptId: eventId);
            }
          }
        }
      case kActionComplete:
        for (final taskId in members) {
          await tasks.complete(taskId, receiptId: eventId);
        }
      case kActionMute:
        for (final taskId in members) {
          await tasks.muteAlarms(taskId, receiptId: eventId);
        }
    }
  });
  if (!applied) return false;
  // The stores do not poke from inside the receipt transaction (a sync
  // round born there would run against it once it closed): one poke
  // now, after the commit, carries every member's mutation.
  tasks.pokeSync();
  onCommitted?.call(eventId);

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

/// The notification id of the fallback a failed native snooze of [eventId]
/// leaves: FNV-1a over `aw.fallback.<eventId>`, the number the notification
/// plugin lists that request under (`AWAlarmFallback.notificationId`).
int alarmKitFallbackNotificationId(String eventId) =>
    notificationIdFor('aw.fallback.$eventId');

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
/// and clearing never would ring twice. Such an event is acked only once its
/// fallback is cleared: until then the native queue entry is what remembers
/// the clear, so a process killed in between redelivers it (a no-op through
/// its receipt) and the next launch clears it. [beforePlan] is the
/// scheduler's `drainActions` seam and [afterPlan] its post-plan hook.
///
/// The fallback is a notification the plugin lists like any other, under an
/// id no plan holds; [heldFallbackIds] is the scheduler's `keepPendingIds`
/// seam, so its diff leaves a fallback alone until [afterPlan] clears it.
class AlarmKitActionPump {
  AlarmKitActionPump({required this.host, required this.apply, this.log});

  final AlarmKitHost host;

  /// Applies one event; true when it changed something, false for a
  /// redelivery. Throws when the write failed (nothing committed).
  final Future<bool> Function(NotificationEvent event) apply;
  final AlarmLog? log;

  Future<void> _tail = Future<void>.value();

  /// Fallback event id → the tasks its notification rings for.
  final Map<String, List<String>> _fallbacksApplied = {};
  final Map<String, List<String>> _fallbacksArmed = {};

  /// Every failed native snooze a pull has seen whose fallback is not cleared
  /// yet — applied or not: one whose apply failed stays queued, and its
  /// fallback is then the only thing that rings it.
  final Set<String> _fallbacksHeld = {};

  /// The notification ids of the fallbacks still on the OS as far as this
  /// pump knows ([alarmKitFallbackNotificationId]).
  Set<int> heldFallbackIds() => {
    for (final eventId in _fallbacksHeld)
      alarmKitFallbackNotificationId(eventId),
  };

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

  /// After a plan pass: clear the fallbacks that pass planned for, then ack
  /// their events. A failed clear keeps them armed for the next pass, and so
  /// does a fallback for a task in [uncoveredTaskIds] — the pass could not
  /// put that task's own delivery on the OS, so the fallback may be all that
  /// still rings it.
  Future<void> afterPlan([Set<String> uncoveredTaskIds = const {}]) async {
    final ids = [
      for (final MapEntry(key: id, value: members) in _fallbacksArmed.entries)
        if (!members.any(uncoveredTaskIds.contains)) id,
    ];
    if (ids.isEmpty) return;
    try {
      await host.clearFallbacks(ids);
    } on Object catch (error) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail: 'clearFallbacks failed: $error',
      );
      return;
    }
    ids.forEach(_fallbacksArmed.remove);
    _fallbacksHeld.removeAll(ids);
    try {
      await host.ackActions(ids);
    } on Object {
      // Still queued: the next pull redelivers it, and clearing twice is
      // harmless.
    }
  }

  /// A native snooze whose own schedule failed left a fallback behind.
  static bool _leftFallback(AlarmKitActionEvent event) =>
      event.action == 'snooze' &&
      event.scheduleOutcome != null &&
      event.scheduleOutcome != 'ok';

  Future<void> _pullOnce() async {
    final List<AlarmKitActionEvent> events;
    try {
      events = await host.pullPendingActions();
    } on Object {
      return; // transient; the next resume or announcement pulls again
    }
    // Before any apply: an event that fails to apply breaks the loop, and
    // the ones behind it still have their fallback on the OS.
    for (final event in events) {
      if (_leftFallback(event)) _fallbacksHeld.add(event.eventId);
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
      // and clearing twice is harmless. Acked by [afterPlan], after the clear.
      if (_leftFallback(event)) {
        if (!_fallbacksArmed.containsKey(event.eventId)) {
          _fallbacksApplied[event.eventId] = event.taskIds;
        }
        continue;
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
