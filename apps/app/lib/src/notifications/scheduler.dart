import 'dart:async';

import 'alarm_log.dart';
import 'alarm_overlay.dart'
    show alarmFireAt, alarmStaleWindowFor, ringingAlarms;
import 'alarmkit.dart';
import 'alarmkit_identity.dart';
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
    this.onPermissionAsk,
    this.drainActions,
    this.afterPlan,
    this.appliedEventIds,
    Duration? staleWindow,
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc()),
       staleWindow = staleWindow ?? alarmStaleWindowFor(profile);

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

  /// Told `true` just before [start] asks the OS for permission and `false`
  /// once every prompt it shows has been answered (OPH-393): the Home strip
  /// waits for the answer instead of naming the problem behind the prompt.
  final void Function(bool asking)? onPermissionAsk;

  /// Pulls the native action queue and applies it (NOTIFICATIONS §2b.3), run
  /// before every AlarmKit plan so a native snooze is in the model before the
  /// plan judges the alarm it left behind. Null is a no-op.
  final Future<void> Function()? drainActions;

  /// Runs after a pass has executed both lanes' plans (OPH-427): what the
  /// pass planned is now on the OS, so a native snooze's fallback
  /// notification can go. Not called when the pass gave up half-way.
  final Future<void> Function()? afterPlan;

  /// The event ids `action_receipts` holds. A native alarm whose event is not
  /// among them is left alone: the model does not know about it yet. Null
  /// treats every event as applied (the id diff of before #49).
  final Future<Set<String>> Function()? appliedEventIds;

  /// How long after its instant a ringing alarm may still be current — the
  /// ring screen's window ([alarmStaleWindowFor]).
  final Duration staleWindow;

  final DateTime Function() _now;

  StreamSubscription<List<AlarmInput>>? _subscription;
  Timer? _heartbeat;
  void Function()? _lifecycle;
  List<AlarmInput> _latest = const [];

  /// Events applied since [_latest] arrived; see [noteEventApplied].
  final Set<String> _appliedUnseen = {};
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
  /// Schedule one set and stop (OPH-321) — the whole of what a background
  /// turn does.
  ///
  /// Deliberately NOT [start]: that one calls `requestPermissions()`, which on
  /// Android reaches for the `mainActivity` and gets `null` in a background
  /// engine, and installs a subscription, a heartbeat timer and a lifecycle
  /// listener that a process about to exit has no use for. Everything AFTER
  /// those — the plan, the diff, the OS calls — is `_apply`, and that is what
  /// this exposes.
  Future<void> applyOnce(List<AlarmInput> alarms) async {
    _latest = alarms;
    _appliedUnseen.clear(); // the caller's list was read after them
    await _apply();
  }

  Future<void> start() async {
    onPermissionAsk?.call(true);
    try {
      await _askForPermissions();
    } finally {
      onPermissionAsk?.call(false);
    }
    _subscription = alarms.listen((list) {
      _latest = list;
      _appliedUnseen.clear();
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

  /// Every prompt [start] shows, in order: notifications, then AlarmKit.
  Future<void> _askForPermissions() async {
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
  }

  /// [eventId]'s write just committed outside this scheduler's own drain —
  /// a pull on resume or on `onActionsPending` (OPH-454). Until the replica
  /// next emits, [_latest] is the list from before that write, so a pass in
  /// between must not judge the event's native alarm by it: the receipt is
  /// there, the model is not. The next list clears the note.
  void noteEventApplied(String eventId) => _appliedUnseen.add(eventId);

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
        // The rehearsal is not part of the plan, so the set-diff would cancel
        // it — within the 15 seconds it is waiting to prove something, if any
        // replica change or foreground lands in between. A diagnostic the
        // system under test can quietly delete diagnoses nothing.
        if (id == kAlarmTestNotificationId) continue;
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
      await _cancelHandledActive(now);
      try {
        await afterPlan?.call();
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'after-plan step failed: $error',
        );
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
  /// holds** (NOTIFICATIONS §2b.3 "Plan pass").
  ///
  /// ## The bug this shape exists to prevent (round 19 K1)
  ///
  /// The excluded set used to be computed from `planAlarmKitAlarms`' output —
  /// the alarms we *intended* to put on this lane. `planNotifications` then
  /// dropped every one of them, so an alarm AlarmKit refused at runtime
  /// (`limit_reached`, a revoked grant, any `PlatformException`) was scheduled
  /// on NEITHER lane. Returning what was accepted rather than what was
  /// attempted closes that; the cap ([kMaxAlarmKitAlarms]) leaves the rest on
  /// their chain.
  ///
  /// ## Occurrences, not ids (#49)
  ///
  /// The plan is [planAlarmKitPass]; this method only reads, executes and
  /// logs. A ringing alarm is never `cancel`led: it stays while its occurrence
  /// is current and is `stop`ped once it is superseded.
  Future<Set<String>> _applyAlarmKit({
    required DateTime now,
    required String? soundName,
  }) async {
    final host = alarmKit;
    if (host == null || !_alarmKitSupported) return const {};

    // Read BEFORE the drain: an event the drain applies now is not in
    // [_latest] until the replica emits, so its alarm waits for that pass.
    Set<String>? applied;
    try {
      applied = await appliedEventIds?.call();
    } on Object catch (error) {
      applied = const {};
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail: 'receipts unreadable: $error — native alarms kept',
      );
    }
    try {
      await drainActions?.call();
    } on Object catch (error) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail: 'drain failed: $error',
      );
    }

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

    final List<AlarmKitScheduled> current;
    try {
      current = await host.scheduledAlarms();
    } on Object catch (error) {
      // We cannot tell what this lane holds, so we must not tell the
      // notification lane to skip anything. Every urgent alarm keeps its chain.
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.alarmkit,
        detail:
            'scheduledAlarms failed: $error — urgent alarms stay on notifications',
      );
      return const {};
    }

    final plan = planAlarmKitPass(
      desired: desired,
      current: current,
      alarms: _latest,
      // A receipt counts only once [_latest] carries its write (OPH-454).
      appliedEventIds:
          (applied ??
                  {
                    for (final row in current)
                      if (row.eventId != null) row.eventId!,
                  })
              .difference(_appliedUnseen),
      now: now,
      staleWindow: staleWindow,
    );

    // Everything left as it is counts as accepted; changes have to prove
    // themselves.
    final accepted = <String>{...plan.held};

    for (final row in plan.toStop) {
      try {
        final result = await host.stop(row.id);
        await log?.record(
          event: result.error == null
              ? AlarmLogEvent.cancelled
              : AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          urgent: true,
          fireAt: _instant(row.fireAtMs),
          detail:
              'stop id=${row.id} superseded '
              '(stopped=${result.stopped} cancelled=${result.cancelled}'
              '${result.error == null ? '' : ' error=${result.error}'})',
        );
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'stop id=${row.id} failed: $error',
        );
      }
    }

    for (final row in plan.toCancel) {
      try {
        await host.cancel(row.id);
        await log?.record(
          event: AlarmLogEvent.cancelled,
          lane: AlarmLogLane.alarmkit,
          detail: 'id=${row.id}',
        );
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'cancel id=${row.id} failed: $error',
        );
      }
    }

    for (final alarm in plan.toReschedule) {
      try {
        await host.cancel(alarm.id);
      } on Object catch (error) {
        // The old presentation still rings: better than none.
        accepted.addAll(alarm.reminderIds);
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.alarmkit,
          detail: 'reschedule id=${alarm.id} cancel failed: $error',
        );
        continue;
      }
      await _scheduleOne(host, alarm, accepted);
    }

    for (final alarm in plan.toSchedule) {
      await _scheduleOne(host, alarm, accepted);
    }

    // Urgent alarms the CAP pushed back onto the notification chain. Said out
    // loud, because "why did this one sound different?" is unanswerable
    // otherwise.
    for (final a in _latest) {
      if (!a.urgent || accepted.contains(a.reminderId)) continue;
      if (!desired.any((d) => d.reminderIds.contains(a.reminderId))) {
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

  Future<void> _scheduleOne(
    AlarmKitHost host,
    AlarmKitAlarm alarm,
    Set<String> accepted,
  ) async {
    AlarmKitScheduleResult outcome;
    try {
      outcome = await host.schedule(alarm);
    } on Object catch (error) {
      outcome = AlarmKitScheduleResult.failed('$error');
    }
    if (outcome.ok) accepted.addAll(alarm.reminderIds);
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

  /// Takes a shown urgent notification off the screen once its alarm no
  /// longer rings (OPH-445): the set-diff above only sees PENDING requests,
  /// and Android loops a shown one's sound until it is cancelled. Every pass
  /// runs it, the headless turn's [applyOnce] included.
  Future<void> _cancelHandledActive(DateTime now) async {
    final List<ActiveAlarmNotification> active;
    try {
      active = await gateway.activeNotifications();
    } on Object catch (error) {
      await log?.record(
        event: AlarmLogEvent.degraded,
        lane: AlarmLogLane.notification,
        detail: 'activeNotifications failed: $error',
      );
      return;
    }
    for (final id in activeToCancel(active, _latest, now, staleWindow)) {
      try {
        await gateway.cancel(id);
        _announced.remove(id);
        await log?.record(
          event: AlarmLogEvent.cancelled,
          lane: AlarmLogLane.notification,
          urgent: true,
          detail: 'id=$id shown, no longer ringing',
        );
      } on Object catch (error) {
        await log?.record(
          event: AlarmLogEvent.degraded,
          lane: AlarmLogLane.notification,
          detail: 'cancel shown id=$id failed: $error',
        );
      }
    }
  }

  static DateTime? _instant(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

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

/// What one AlarmKit pass does to the lane (NOTIFICATIONS §2b.3 "Plan pass").
class AlarmKitPassPlan {
  const AlarmKitPassPlan({
    this.toStop = const [],
    this.toCancel = const [],
    this.toSchedule = const [],
    this.toReschedule = const [],
    this.held = const {},
  });

  /// Ringing alarms whose occurrence is superseded: `stop`, never `cancel`.
  final List<AlarmKitScheduled> toStop;

  /// Alarms the plan no longer wants and that are not ringing.
  final List<AlarmKitScheduled> toCancel;

  /// Desired alarms the lane does not hold.
  final List<AlarmKitAlarm> toSchedule;

  /// Desired alarms the lane holds under the same id with another
  /// fingerprint: `cancel` + `schedule` under that id.
  final List<AlarmKitAlarm> toReschedule;

  /// Reminder ids covered by alarms the pass leaves exactly as they are — the
  /// notification lane must not ring them a second time.
  final Set<String> held;
}

/// The pure AlarmKit pass (#49, NOTIFICATIONS §2b.3): [desired] from
/// `planAlarmKitAlarms`, [current] from `scheduledAlarms`, [alarms] the model
/// the plan was built from, [appliedEventIds] the receipts.
///
/// Per [current] row, in this order:
/// 1. `alerting` — kept while some member task still has an active urgent
///    occurrence in the alarm's UTC minute and `now - fireAtMs` is inside
///    [staleWindow]; otherwise stopped. An `origin: native` row whose event
///    has no receipt is kept inside [staleWindow] whatever the model says: the
///    model has not heard about that snooze yet (receipts are read before the
///    drain, so this covers an event the same pass's drain applied). A row with no ledger record cannot be
///    judged and is stopped only once it is older than [staleWindow].
/// 2. `origin: native` whose event has no receipt — kept: the model has not
///    heard about that snooze yet.
/// 3. not desired — cancelled.
/// 4. desired with another fingerprint — rescheduled under the same id. A row
///    with no ledger record has no fingerprint to compare and is kept.
///
/// Then every desired id the lane does not hold is scheduled.
AlarmKitPassPlan planAlarmKitPass({
  required List<AlarmKitAlarm> desired,
  required List<AlarmKitScheduled> current,
  required List<AlarmInput> alarms,
  required Set<String> appliedEventIds,
  required DateTime now,
  required Duration staleWindow,
}) {
  final desiredById = {for (final a in desired) a.id: a};
  final nowMs = now.toUtc().millisecondsSinceEpoch;
  final toStop = <AlarmKitScheduled>[];
  final toCancel = <AlarmKitScheduled>[];
  final toReschedule = <AlarmKitAlarm>[];
  final held = <String>{};
  final handled = <int>{};

  // The active urgent reminders of [row]'s members that fall in [minute].
  Iterable<AlarmInput> occurrences(
    AlarmKitScheduled row,
    bool Function(AlarmInput) at,
  ) => alarms.where(
    (a) =>
        a.urgent &&
        _kActive.contains(a.status) &&
        row.members.contains(a.taskId) &&
        at(a),
  );

  int minuteOf(int ms) => ms ~/ 60000;
  int instantMs(AlarmInput a) => alarmKitFireAtMs(alarmFireAt(a));

  bool unapplied(AlarmKitScheduled row) =>
      row.origin == 'native' &&
      row.eventId != null &&
      !appliedEventIds.contains(row.eventId);

  // The snooze that made a native [row] is still on its way into the model,
  // which may yet say the old instant: whatever is due by now, or rang in this
  // alarm's minute, is this alarm's to ring.
  Iterable<AlarmInput> heldByNative(AlarmKitScheduled row) => occurrences(
    row,
    (a) =>
        instantMs(a) <= nowMs ||
        (row.fireAtMs != null &&
            minuteOf(instantMs(a)) == minuteOf(row.fireAtMs!)),
  );

  for (final row in current) {
    handled.add(row.id);
    final fireAtMs = row.fireAtMs;

    if (row.state == AlarmKitAlarmState.alerting) {
      if (!row.hasLedger || fireAtMs == null) {
        // An alarm from before the ledger: nothing says what it rings for.
        if (fireAtMs != null &&
            nowMs - fireAtMs >= staleWindow.inMilliseconds) {
          toStop.add(row);
        }
        continue;
      }
      final fresh = nowMs - fireAtMs < staleWindow.inMilliseconds;
      if (fresh && unapplied(row)) {
        // A native snooze ringing before the model heard of it (its event is
        // unapplied, or applied by this very drain and not yet in [alarms]):
        // the model still says the old instant, so no member matches this
        // minute. It is current all the same.
        held.addAll(heldByNative(row).map((a) => a.reminderId));
        continue;
      }
      final live = fresh
          ? occurrences(
              row,
              (a) => minuteOf(instantMs(a)) == minuteOf(fireAtMs),
            ).toList()
          : const <AlarmInput>[];
      if (live.isEmpty) {
        toStop.add(row);
      } else {
        held.addAll(live.map((a) => a.reminderId));
      }
      continue;
    }

    if (unapplied(row)) {
      held.addAll(heldByNative(row).map((a) => a.reminderId));
      final wanted = desiredById[row.id];
      if (wanted != null) held.addAll(wanted.reminderIds);
      continue;
    }

    final wanted = desiredById[row.id];
    if (wanted == null) {
      toCancel.add(row);
    } else if (row.hasLedger && row.fp != wanted.fp) {
      toReschedule.add(wanted);
    } else {
      held.addAll(wanted.reminderIds);
    }
  }

  return AlarmKitPassPlan(
    toStop: toStop,
    toCancel: toCancel,
    toSchedule: [
      for (final a in desired)
        if (!handled.contains(a.id)) a,
    ],
    toReschedule: toReschedule,
    held: held,
  );
}

const _kActive = {'scheduled', 'snoozed', 'delivered'};

/// The shown notifications to take off the screen (OPH-445, #48 gap A): an
/// urgent one whose reminders no longer ring — acknowledged, snoozed,
/// completed or deleted on another device, or past [staleWindow] — by the
/// same decision as [ringingAlarms]. A grouped minute stays while any of its
/// reminders rings. A notification mapped to no reminder, a normal reminder
/// (it does not loop) and the rehearsal alarm are never touched.
///
/// Idempotent: a cancelled notification is gone from the next [active].
Set<int> activeToCancel(
  List<ActiveAlarmNotification> active,
  List<AlarmInput> alarms,
  DateTime now,
  Duration staleWindow,
) {
  final ringing = {
    for (final a in ringingAlarms(alarms, now, staleAfter: staleWindow))
      a.reminderId,
  };
  return {
    for (final n in active)
      if (n.urgent &&
          n.id != kAlarmTestNotificationId &&
          n.reminderIds.isNotEmpty &&
          !n.reminderIds.any(ringing.contains))
        n.id,
  };
}
