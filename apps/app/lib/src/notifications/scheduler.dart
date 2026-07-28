import 'dart:async';

import 'alarm_log.dart';
import 'alarmkit.dart';
import 'planner.dart';
import 'gateway.dart';
import 'alarm_sound.dart';
import 'reminder_profile.dart';

/// Keeps the OS notification schedule equal to the plan (OPH-061): every
/// replica change re-plans (window ≤[maxPending], urgent chains) and the diff
/// is applied as cancel-the-extras + schedule-the-missing — ids are content
/// hashes, so any change reschedules and convergence is idempotent. Alarms
/// disappear from the plan when acknowledged/completed/cancelled (their rows
/// leave the active set), which cancels their remaining chain.
class NotificationScheduler {
  NotificationScheduler({
    required this.gateway,
    required this.alarms,
    required this.privacyMode,
    this.alarmKit,
    this.log,
    this.profile = ReminderProfile.factory,
    this.sounds,
    this.alarmSound = const AwSoundChoice.bundled('aw_alarm'),
    this.reminderSound = const AwSoundChoice.os(),
    this.maxPending = 40,
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  final NotificationsGateway gateway;
  final Stream<List<AlarmInput>> alarms;
  final bool privacyMode;

  /// The device's alarm record (OPH-176). Optional so a pure scheduler test can
  /// leave it out; production always passes one.
  final AlarmLog? log;

  /// The user's re-alert chain (OPH-179). The provider rebuilds the scheduler
  /// when it changes, so a new profile re-plans everything pending.
  final ReminderProfile profile;

  /// Turns the two sound choices into what this platform can play (OPH-181).
  /// Null keeps the OS defaults — a pure scheduler test needs no filesystem.
  final AlarmSoundResolver? sounds;
  final AwSoundChoice alarmSound;
  final AwSoundChoice reminderSound;

  /// iOS 26+ URGENT lane (OPH-141). Null (or unsupported/declined) leaves urgent
  /// alarms on the notification lane. When active, urgent alarms move here and
  /// the notification plan drops them so they never ring twice.
  final AlarmKitHost? alarmKit;
  final int maxPending;
  final DateTime Function() _now;

  StreamSubscription<List<AlarmInput>>? _subscription;
  List<AlarmInput> _latest = const [];
  bool _applying = false;
  bool _reapplyWanted = false;
  bool _stopped = false;
  bool _alarmKitActive = false;

  /// Permission refusals and platform-channel absence (widget tests, web)
  /// must never break the app — notifications degrade, tasks keep working.
  Future<void> start() async {
    try {
      await gateway.initialize();
      await gateway.requestPermissions();
    } catch (_) {
      return; // no notification surface here — stay dormant
    }
    // iOS 26+ takes the URGENT lane on AlarmKit (breaks through the mute
    // switch, no entitlement). If it's absent or the user declined, urgent
    // alarms stay on the time-sensitive notification lane — degraded, never
    // dropped.
    try {
      if (alarmKit != null && await alarmKit!.isSupported()) {
        _alarmKitActive = await alarmKit!.requestAuthorization();
      }
    } catch (_) {
      _alarmKitActive = false;
    }
    _subscription = alarms.listen((list) {
      _latest = list;
      unawaited(_apply());
    });
  }

  void dispose() {
    _stopped = true;
    unawaited(_subscription?.cancel());
  }

  /// Resolves one lane's sound, recording a degradation rather than letting the
  /// OS quietly substitute its own ding (OPH-176's guard, OPH-181's subject).
  Future<AwResolvedSound> _resolve(AwSoundChoice choice) async {
    final resolver = sounds;
    if (resolver == null) return const AwResolvedSound();
    final resolved = await resolver.resolve(choice);
    final reason = resolved.degradedReason;
    if (reason != null) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.notification,
        detail: 'sound=${choice.encode()} $reason',
      );
    }
    return resolved;
  }

  Future<void> _apply() async {
    if (_stopped) return;
    if (_applying) {
      _reapplyWanted = true;
      return;
    }
    _applying = true;
    try {
      final now = _now();
      // Resolve the chosen sounds first: the name is part of each id's content
      // hash, so a sound change reschedules instead of applying "from the next
      // alarm on" (OPH-181).
      final alarm = await _resolve(alarmSound);
      final reminder = await _resolve(reminderSound);
      final desired = planNotifications(
        alarms: _latest,
        now: now,
        privacyMode: privacyMode,
        maxPending: maxPending,
        routeUrgentToAlarmKit: _alarmKitActive,
        profile: profile,
        alarmSoundName: alarm.name,
        reminderSoundName: reminder.name,
      );
      final desiredById = {for (final n in desired) n.id: n};
      final pending = await gateway.pendingIds();

      for (final id in pending.difference(desiredById.keys.toSet())) {
        await gateway.cancel(id);
        await log?.record(
          event: AlarmLogEvent.cancelled,
          lane: AlarmLogLane.notification,
          detail: 'id=$id',
        );
      }
      for (final id in desiredById.keys.toSet().difference(pending)) {
        final notification = desiredById[id]!;
        final delivery = await gateway.schedule(notification);
        await log?.recordScheduled(
          notification,
          lane: AlarmLogLane.notification,
          delivery: delivery,
          kind: notification.kind,
          slotIndex: notification.slotIndex,
          taskId: notification.taskId,
          reminderId: notification.reminderId,
        );
      }

      // The AlarmKit lane (OPH-141): identical set-diff against its own host,
      // so acknowledge/complete/snooze cancels an AlarmKit alarm exactly like a
      // notification (the row leaves the active set → the desired set shrinks).
      if (_alarmKitActive && alarmKit != null) {
        final desiredAk = planAlarmKitAlarms(
          alarms: _latest,
          now: now,
          privacyMode: privacyMode,
          maxPending: maxPending,
        );
        final desiredAkById = {for (final a in desiredAk) a.id: a};
        final scheduled = await alarmKit!.scheduledIds();

        for (final id in scheduled.difference(desiredAkById.keys.toSet())) {
          await alarmKit!.cancel(id);
          await log?.record(
            event: AlarmLogEvent.cancelled,
            lane: AlarmLogLane.alarmkit,
            detail: 'id=$id',
          );
        }
        for (final id in desiredAkById.keys.toSet().difference(scheduled)) {
          final alarm = desiredAkById[id]!;
          await alarmKit!.schedule(alarm);
          await log?.record(
            event: AlarmLogEvent.scheduled,
            lane: AlarmLogLane.alarmkit,
            urgent: true,
            // AlarmKit rings until answered natively: one entry, no chain, and
            // the OS owns the sound presentation.
            sound: kAwAlarmSoundName,
            level: 'alarmkit',
            fireAt: alarm.fireAt,
            taskId: alarm.taskId,
            reminderId: alarm.reminderId,
          );
        }
      }
    } catch (_) {
      // Transient plugin failures self-heal on the next replica change.
    } finally {
      _applying = false;
    }
    if (_reapplyWanted && !_stopped) {
      _reapplyWanted = false;
      await _apply();
    }
  }
}
