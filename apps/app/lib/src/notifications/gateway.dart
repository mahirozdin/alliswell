/// The seam between notification LOGIC (planner/scheduler — pure, tested) and
/// the OS plugin (gateway_local.dart — thin, device-verified). Widget tests
/// swap in a fake gateway; no platform channels leak into the logic layer.
library;

/// One OS notification we want to exist. The [id] is a content hash — any
/// change to when/what produces a different id, so diffing desired-vs-pending
/// reduces to set arithmetic on ids (cancel the extras, schedule the missing).
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.urgent,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;

  /// Absolute UTC instant — exactness is the whole point (NOTIFICATIONS.md).
  final DateTime fireAt;
  final bool urgent;

  /// JSON: {taskId, reminderId, chainIndex} — never task content beyond what
  /// the rendered notification itself shows (privacy mode empties even that).
  final String payload;
}

/// A user interaction with a delivered notification (tap or action button).
class NotificationEvent {
  const NotificationEvent({this.actionId, this.payload});

  /// Null/empty = plain tap on the notification body.
  final String? actionId;
  final String? payload;
}

/// What the OS currently lets us do — feeds the honest status row in
/// Settings (feedback round 6). Never cached across app runs; always probed.
class AlarmSupport {
  const AlarmSupport({
    required this.notificationsEnabled,
    required this.criticalAlertsEnabled,
    this.exactAlarmsEnabled,
  });

  final bool notificationsEnabled;

  /// iOS/macOS: true only when Apple granted the critical-alerts entitlement
  /// AND the user allowed them — the pair that lets sound bypass the mute
  /// switch. Always false without the entitlement (docs/NOTIFICATIONS.md §2).
  final bool criticalAlertsEnabled;

  /// Android: the "Alarms & reminders" special access (null elsewhere).
  final bool? exactAlarmsEnabled;
}

abstract class NotificationsGateway {
  /// Idempotent; safe to call before every use.
  Future<void> initialize();

  /// Ask the OS for notification (and Android exact-alarm) permission.
  /// Returns false when the user declined — callers degrade, never crash.
  Future<bool> requestPermissions();

  /// Probe what delivery the OS currently allows (see [AlarmSupport]).
  Future<AlarmSupport> alarmSupport();

  Future<Set<int>> pendingIds();

  Future<void> schedule(PlannedNotification notification);

  Future<void> cancel(int id);

  /// Taps and action-button presses, foreground-routed.
  Stream<NotificationEvent> get events;
}

/// FNV-1a over the seed string, masked positive — stable across runs and
/// isolates, int32-safe for Android notification ids.
int notificationIdFor(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
