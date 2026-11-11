import 'dart:async';

import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';

/// In-memory notification surface: records the schedule, replays user
/// interactions through [emit].
class FakeNotificationsGateway implements NotificationsGateway {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  bool permissionsRequested = false;

  /// Makes `schedule` throw for the notifications this says yes to — the
  /// round-19 K2 case, where ONE bad request used to abort the whole pass and
  /// leave every later alarm unscheduled.
  bool Function(PlannedNotification)? failScheduleFor;

  /// Ids the OS is pretending to have thrown away — round 19's `dropped`
  /// reconciliation, which is otherwise unobservable.
  final Set<int> vanished = {};
  final _events = StreamController<NotificationEvent>.broadcast(sync: true);

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionsRequested = true;
    return true;
  }

  @override
  Future<AlarmSupport> alarmSupport() async => const AlarmSupport(
    notificationsEnabled: true,
    criticalAlertsEnabled: false,
  );

  @override
  Future<Set<int>> pendingIds() async =>
      scheduled.keys.toSet().difference(vanished);

  @override
  Future<ScheduledDelivery> schedule(PlannedNotification notification) async {
    if (failScheduleFor?.call(notification) ?? false) {
      throw StateError('the OS refused ${notification.id}');
    }
    scheduled[notification.id] = notification;
    // The same pure decision the real gateway makes (OPH-176), so tests see the
    // loudness contract rather than a stub.
    return awDeliveryFor(urgent: notification.urgent, criticalEnabled: false);
  }

  @override
  Future<ScheduledDelivery> scheduleTestAlarm({
    required String title,
    required String body,
    required Duration after,
    String? soundName,
  }) async {
    testAlarms.add(after);
    return schedule(
      PlannedNotification(
        id: kAlarmTestNotificationId,
        title: title,
        body: body,
        fireAt: DateTime.now().toUtc().add(after),
        urgent: true,
        payload: '{"test":true}',
        kind: 'test',
        soundName: soundName,
      ),
    );
  }

  /// How far ahead each rehearsal was asked for.
  final List<Duration> testAlarms = [];

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Stream<NotificationEvent> get events => _events.stream;

  void emit(NotificationEvent event) => _events.add(event);
}

/// In-memory AlarmKit surface (OPH-141, contract v2 §2b.3): records the
/// schedule, holds a native action queue that only [ackActions] empties and a
/// failure ring that a pull empties. [supported] / [authorized] drive the
/// scheduler's lane decision (iOS 26+ build, user grant).
class FakeAlarmKitHost implements AlarmKitHost {
  FakeAlarmKitHost({this.supported = true, this.authorized = true});

  bool supported;
  bool authorized;
  final Map<int, AlarmKitAlarm> scheduled = {};
  final List<int> cancelled = [];
  final List<int> stopped = [];
  bool authorizationRequested = false;

  /// Ids the OS reports as `alerting`.
  final Set<int> alerting = {};

  /// Rows the OS holds that Dart did not schedule (a native snooze, an alarm
  /// from an older build), keyed by id.
  final Map<int, AlarmKitScheduled> foreign = {};

  /// The native pending-action queue and failure ring.
  final List<AlarmKitActionEvent> queue = [];
  final List<AlarmKitFailure> failures = [];
  final List<List<String>> acked = [];
  final List<List<String>> fallbacksCleared = [];

  /// Set to make the next `schedule` calls fail the way the OS does when the
  /// undocumented per-app ceiling is hit (OPH-182).
  String? scheduleFailure;
  final _pending = StreamController<void>.broadcast(sync: true);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequested = true;
    return authorized;
  }

  @override
  Future<bool> isAuthorized() async => authorized;

  /// Set to make `scheduledIds` / `scheduledAlarms` throw the way a dead
  /// channel does — the case that must leave every urgent alarm on the
  /// notification chain (round 19).
  bool scheduledIdsThrows = false;

  @override
  Future<List<AlarmKitScheduled>> scheduledAlarms() async {
    if (scheduledIdsThrows) throw StateError('channel gone');
    return [
      for (final a in scheduled.values)
        AlarmKitScheduled(
          id: a.id,
          fp: a.fp,
          state: alerting.contains(a.id)
              ? AlarmKitAlarmState.alerting
              : AlarmKitAlarmState.scheduled,
          members: a.members,
          fireAtMs: a.toArgs()['fireAtMs'] as int?,
        ),
      for (final f in foreign.values)
        if (!scheduled.containsKey(f.id)) f,
    ];
  }

  @override
  Future<Set<int>> scheduledIds() async => {
    for (final a in await scheduledAlarms()) a.id,
  };

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async {
    final failure = scheduleFailure;
    if (failure != null) return AlarmKitScheduleResult.failed(failure);
    scheduled[alarm.id] = alarm;
    return const AlarmKitScheduleResult.ok();
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
    foreign.remove(id);
    alerting.remove(id);
  }

  @override
  Future<AlarmKitStopResult> stop(int id) async {
    stopped.add(id);
    scheduled.remove(id);
    foreign.remove(id);
    alerting.remove(id);
    return const AlarmKitStopResult(stopped: true);
  }

  @override
  Future<List<AlarmKitActionEvent>> pullPendingActions() async =>
      [...queue]..sort((a, b) => a.pressedAtMs.compareTo(b.pressedAtMs));

  @override
  Future<void> ackActions(List<String> eventIds) async {
    acked.add([...eventIds]);
    queue.removeWhere((e) => eventIds.contains(e.eventId));
  }

  @override
  Future<void> clearFallbacks(List<String> eventIds) async {
    fallbacksCleared.add([...eventIds]);
  }

  @override
  Future<List<AlarmKitFailure>> pullFailures() async {
    final out = [...failures];
    failures.clear();
    return out;
  }

  @override
  Stream<void> get actionsPending => Stream<void>.multi((listener) {
    listener.add(null);
    final sub = _pending.stream.listen(listener.add);
    listener.onCancel = sub.cancel;
  });

  /// Native `onActionsPending`: queue [event] and announce it.
  void enqueue(AlarmKitActionEvent event) {
    queue.add(event);
    _pending.add(null);
  }
}
