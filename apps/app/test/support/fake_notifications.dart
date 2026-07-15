import 'dart:async';

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
