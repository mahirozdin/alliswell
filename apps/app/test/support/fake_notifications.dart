import 'dart:async';

import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';

/// In-memory notification surface: records the schedule, replays user
/// interactions through [emit].
class FakeNotificationsGateway implements NotificationsGateway {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  bool permissionsRequested = false;
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
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  @override
  Future<void> schedule(PlannedNotification notification) async {
    scheduled[notification.id] = notification;
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
  final _events = StreamController<NotificationEvent>.broadcast(sync: true);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequested = true;
    return authorized;
  }

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<void> schedule(AlarmKitAlarm alarm) async {
    scheduled[alarm.id] = alarm;
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
