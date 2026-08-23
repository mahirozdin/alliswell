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
    this.snoozePreset = kDefaultSnoozePreset,
    this.maxPending = 40,
    this.onForeground,
    this.refillEvery = const Duration(hours: 6),
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

  /// The snooze the AlarmKit alert's secondary button applies — the first of the
  /// user's own snooze order (OPH-179 N4), so the OS alert and the in-app ring
  /// screen offer the same thing first.
  final String snoozePreset;

  /// iOS 26+ URGENT lane (OPH-141). Null (or unsupported/declined) leaves urgent
  /// alarms on the notification lane. When active, urgent alarms move here and
  /// the notification plan drops them so they never ring twice.
  final AlarmKitHost? alarmKit;
  final int maxPending;

  /// Installs an "app came to the foreground" callback and returns its
  /// disposer, or null where there is no such event (a pure test).
  ///
  /// Injected rather than reached for directly because `AppLifecycleListener`
  /// binds to `WidgetsBinding`, and a scheduler unit test has none.
  final void Function() Function(void Function() onResume)? onForeground;

  /// The safety net behind [onForeground]: how often to re-fill the window
  /// even if nothing happens at all.
  final Duration refillEvery;

  final DateTime Function() _now;

  StreamSubscription<List<AlarmInput>>? _subscription;
  Timer? _heartbeat;
  void Function()? _lifecycle;
  List<AlarmInput> _latest = const [];
  bool _applying = false;
  bool _reapplyWanted = false;
  bool _stopped = false;
  bool _alarmKitSupported = false;
  bool _alarmKitActive = false;

  /// What we asked the OS for last pass: id → (fire instant, urgency).
  ///
  /// The input to the reconciliation pass (OPH-277). Kept in memory rather than
  /// read back out of the log because the question it answers is about THIS
  /// process's own schedule, and a stale row from three launches ago would
  /// produce a confident wrong answer.
  final Map<int, ({DateTime fireAt, bool urgent, String? reminderId})>
  _announced = {};

  /// Permission refusals and platform-channel absence (widget tests, web)
  /// must never break the app — notifications degrade, tasks keep working.
  ///
  /// **Round 19 K3.** This used to `return` on any throw from `initialize` /
  /// `requestPermissions`, which meant the subscription was never created and
  /// the device scheduled NOTHING for the rest of the session — silently, and
  /// with no way to recover short of restarting the app. One transient plugin
  /// hiccup at launch was a whole day of missed alarms. It now records the
  /// failure and subscribes anyway: `_apply` retries `initialize` every pass.
  Future<void> start() async {
    try {
      await gateway.initialize();
      await gateway.requestPermissions();
    } catch (error) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.notification,
        detail: 'initialize failed: $error',
      );
    }
    // iOS 26+ takes the URGENT lane on AlarmKit (breaks through the mute
    // switch, no entitlement). If it's absent or the user declined, urgent
    // alarms stay on the time-sensitive notification lane — degraded, never
    // dropped. Asked ONCE here (this is the prompting call); re-READ on every
    // apply, so a later revocation is noticed (K4).
    try {
      _alarmKitSupported = alarmKit != null && await alarmKit!.isSupported();
      if (_alarmKitSupported) {
        _alarmKitActive = await alarmKit!.requestAuthorization();
      }
    } catch (_) {
      _alarmKitSupported = false;
      _alarmKitActive = false;
    }
    _subscription = alarms.listen((list) {
      _latest = list;
      unawaited(_apply());
    });

    // K3, the other half. The plan is a WINDOW over the soonest [maxPending]
    // fire times, and until now it only ever moved when the replica emitted.
    // A week in which no task changed was a week in which the window never
    // advanced — NOTIFICATIONS §2 has always said "re-fill on every app
    // foreground", and nothing was doing it.
    _lifecycle = onForeground?.call(() => unawaited(_apply()));
    _heartbeat = Timer.periodic(refillEvery, (_) => unawaited(_apply()));
  }

  void dispose() {
    _stopped = true;
    _heartbeat?.cancel();
    _lifecycle?.call();
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
      // K3: `start()` no longer aborts on a failed initialize, so every pass
      // gets another chance at it. Idempotent by contract.
      try {
        await gateway.initialize();
      } on Object {
        // Nothing to schedule onto yet; the diff below will simply fail loudly
        // into the log rather than silently doing nothing.
      }

      final now = _now();
      // Resolve the chosen sounds first: the name is part of each id's content
      // hash, so a sound change reschedules instead of applying "from the next
      // alarm on" (OPH-181).
      final alarm = await _resolve(alarmSound);
      final reminder = await _resolve(reminderSound);

      // The AlarmKit lane goes FIRST, and its result — not its plan — decides
      // what the notification lane may skip. See [_applyAlarmKit].
      final accepted = await _applyAlarmKit(now: now, soundName: alarm.name);

      final desired = planNotifications(
        alarms: _latest,
        now: now,
        privacyMode: privacyMode,
        maxPending: maxPending,
        alarmKitReminderIds: accepted,
        profile: profile,
        alarmSoundName: alarm.name,
        reminderSoundName: reminder.name,
      );
      final desiredById = {for (final n in desired) n.id: n};

      final Set<int> pending;
      try {
        pending = await gateway.pendingIds();
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.notification,
          detail: 'pendingIds failed: $error',
        );
        return; // a diff against an unknown pending set would cancel everything
      }

      await _reconcile(pending);

      for (final id in pending.difference(desiredById.keys.toSet())) {
        // K2: one failure used to abort the whole pass, so every alarm after
        // the first bad one was silently left unscheduled. Each call now stands
        // or falls on its own.
        try {
          await gateway.cancel(id);
          _announced.remove(id);
          await log?.record(
            event: AlarmLogEvent.cancelled,
            lane: AlarmLogLane.notification,
            detail: 'id=$id',
          );
        } on Object catch (error) {
          await log?.record(
            event: AlarmLogEvent.degraded,
            lane: AlarmLogLane.notification,
            detail: 'cancel id=$id failed: $error',
          );
        }
      }
      for (final id in desiredById.keys.toSet().difference(pending)) {
        final notification = desiredById[id]!;
        try {
          final delivery = await gateway.schedule(notification);
          _announced[id] = (
            fireAt: notification.fireAt,
            urgent: notification.urgent,
            reminderId: notification.reminderId,
          );
          await log?.recordScheduled(
            notification,
            lane: AlarmLogLane.notification,
            delivery: delivery,
            kind: notification.kind,
            slotIndex: notification.slotIndex,
            taskId: notification.taskId,
            reminderId: notification.reminderId,
          );
        } on Object catch (error) {
          await log?.record(
            event: AlarmLogEvent.degraded,
            lane: AlarmLogLane.notification,
            urgent: notification.urgent,
            fireAt: notification.fireAt,
            taskId: notification.taskId,
            reminderId: notification.reminderId,
            detail: 'schedule failed: $error',
          );
        }
      }
    } catch (_) {
      // Transient plugin failures self-heal on the next replica change — and
      // now also on the next foreground and the next heartbeat (K3).
    } finally {
      _applying = false;
    }
    if (_reapplyWanted && !_stopped) {
      _reapplyWanted = false;
      await _apply();
    }
  }

  /// Converges the AlarmKit lane and reports which reminders it **actually
  /// holds**.
  ///
  /// ## The bug this shape exists to prevent (round 19 K1)
  ///
  /// The excluded set used to be computed from `planAlarmKitAlarms`' output —
  /// the alarms we *intended* to put on this lane. `planNotifications` then
  /// dropped every one of them, so an alarm AlarmKit refused at runtime
  /// (`limit_reached`, a revoked grant, any `PlatformException`) was scheduled
  /// on NEITHER lane. It was written to the log as `degraded` and otherwise
  /// forgotten, and the file's own comment claimed the opposite was true.
  ///
  /// The comment was right about the CAP — `planAlarmKitAlarms` returns at most
  /// [kMaxAlarmKitAlarms], and the rest keep their chain — and wrong about
  /// every other way this lane can say no. Returning what was accepted rather
  /// than what was attempted closes both.
  Future<Set<String>> _applyAlarmKit({
    required DateTime now,
    required String? soundName,
  }) async {
    final host = alarmKit;
    if (host == null || !_alarmKitSupported) return const {};

    // K4: re-READ the grant (never re-ask). A permission revoked in Settings
    // mid-session used to leave urgent alarms routed to a lane that would
    // refuse them, for the rest of the session.
    try {
      final authorized = await host.isAuthorized();
      if (authorized != _alarmKitActive) {
        _alarmKitActive = authorized;
        await log?.record(
          event: authorized ? AlarmLogEvent.scheduled : AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'authorization=$authorized',
        );
      }
    } on Object {
      // Leave the cached answer alone rather than guessing in either direction.
    }
    if (!_alarmKitActive) return const {};

    final desired = planAlarmKitAlarms(
      alarms: _latest,
      now: now,
      privacyMode: privacyMode,
      snoozePreset: snoozePreset,
      soundName: soundName,
    );
    final desiredById = {for (final a in desired) a.id: a};

    final Set<int> scheduled;
    try {
      scheduled = await host.scheduledIds();
    } on Object catch (error) {
      // We cannot tell what this lane holds, so we must not tell the
      // notification lane to skip anything. Every urgent alarm keeps its chain.
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail:
            'scheduledIds failed: $error — urgent alarms stay on notifications',
      );
      return const {};
    }

    for (final id in scheduled.difference(desiredById.keys.toSet())) {
      try {
        await host.cancel(id);
        await log?.record(
          event: AlarmLogEvent.cancelled,
          lane: AlarmLogLane.alarmkit,
          detail: 'id=$id',
        );
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'cancel id=$id failed: $error',
        );
      }
    }

    // Everything still on the lane counts as accepted; only the new ones have
    // to prove themselves.
    final accepted = <String>{
      for (final entry in desiredById.entries)
        if (scheduled.contains(entry.key)) entry.value.reminderId,
    };

    for (final id in desiredById.keys.toSet().difference(scheduled)) {
      final alarm = desiredById[id]!;
      AlarmKitScheduleResult outcome;
      try {
        outcome = await host.schedule(alarm);
      } on Object catch (error) {
        outcome = AlarmKitScheduleResult.failed('$error');
      }
      if (outcome.ok) accepted.add(alarm.reminderId);
      await log?.record(
        // A refused alarm is a degradation, not a schedule — saying
        // "scheduled" for something the OS threw away is precisely the lie
        // OPH-176 built this log to catch.
        event: outcome.ok ? AlarmLogEvent.scheduled : AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        urgent: true,
        // AlarmKit rings until answered natively: one entry, no chain.
        sound: alarm.soundName ?? kAwAlarmSoundName,
        level: 'alarmkit',
        fireAt: alarm.fireAt,
        taskId: alarm.taskId,
        reminderId: alarm.reminderId,
        detail: outcome.ok
            ? null
            : '${outcome.reason} — notification chain keeps it',
      );
    }

    // Urgent alarms the CAP pushed back onto the notification chain. Said out
    // loud, because "why did this one sound different?" is unanswerable
    // otherwise.
    for (final a in _latest) {
      if (!a.urgent || accepted.contains(a.reminderId)) continue;
      if (!desiredById.values.any((d) => d.reminderId == a.reminderId)) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          urgent: true,
          taskId: a.taskId,
          reminderId: a.reminderId,
          detail: 'over-limit (max $kMaxAlarmKitAlarms) — notification chain',
        );
      }
    }
    return accepted;
  }

  /// Works out what happened to the requests we made last pass (OPH-277).
  ///
  /// iOS gives an app no delivery callback for a local notification it did not
  /// tap, so "did it actually go off?" has never been answerable — which is
  /// what made round 19's report impossible to investigate. It IS answerable
  /// indirectly: a request we scheduled and did not cancel is gone from the
  /// pending list for exactly one of two reasons.
  ///
  ///  * Its fire time has passed → the OS presented it. [AlarmLogEvent.delivered].
  ///  * Its fire time has NOT passed → the OS threw it away. iOS keeps only the
  ///    64 soonest pending requests and prunes the rest in silence.
  ///    [AlarmLogEvent.dropped] — the row that finally names that.
  ///
  /// Neither says how LOUD it was; nothing on iOS can. Paired with the
  /// permission probe in Settings, though, "scheduled → delivered, sound off"
  /// is a complete answer where there used to be none.
  Future<void> _reconcile(Set<int> pending) async {
    if (_announced.isEmpty) return;
    final now = _now();
    for (final id in _announced.keys.toList()) {
      // Still queued: nothing has happened to it yet.
      if (pending.contains(id)) continue;
      // Our OWN cancellations are removed from `_announced` by the cancel loop
      // below, and that loop only runs for ids the OS still had — so anything
      // reaching here left the queue without us asking.
      final entry = _announced.remove(id)!;
      await log?.record(
        event: entry.fireAt.isAfter(now)
            ? AlarmLogEvent.dropped
            : AlarmLogEvent.delivered,
        lane: AlarmLogLane.notification,
        urgent: entry.urgent,
        fireAt: entry.fireAt,
        reminderId: entry.reminderId,
        detail: 'id=$id',
      );
    }
  }
}
