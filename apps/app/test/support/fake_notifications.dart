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

/// In-memory AlarmKit surface (OPH-141): records the schedule, replays
/// Onayla/Ertele through [emit]. [supported] / [authorized] drive the
/// scheduler's lane decision (iOS 26+ build, user grant).
class FakeAlarmKitHost implements AlarmKitHost {
  FakeAlarmKitHost({this.supported = true, this.authorized = true});

  bool supported;
  bool authorized;
  final Map<int, AlarmKitAlarm> scheduled = {};
  final List<int> cancelled = [];
  bool authorizationRequested = false;

  /// Set to make the next `schedule` calls fail the way the OS does when the
  /// undocumented per-app ceiling is hit (OPH-182).
  String? scheduleFailure;
  final _events = StreamController<NotificationEvent>.broadcast(sync: true);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequested = true;
    return authorized;
  }

  @override
  Future<bool> isAuthorized() async => authorized;

  /// Set to make `scheduledIds` throw the way a dead channel does — the case
  /// that must leave every urgent alarm on the notification chain (round 19).
  bool scheduledIdsThrows = false;

  @override
  Future<Set<int>> scheduledIds() async {
    if (scheduledIdsThrows) throw StateError('channel gone');
    return scheduled.keys.toSet();
  }

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
  }

  @override
  Stream<NotificationEvent> get events => _events.stream;

  void emit(NotificationEvent event) => _events.add(event);
}
