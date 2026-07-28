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
    this.kind,
    this.slotIndex,
    this.taskId,
    this.reminderId,
    this.soundName,
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

  /// Diagnostics for the alarm log (OPH-176). NOT part of the content hash: the
  /// id already covers everything the OS renders, and a log label must never
  /// cause a reschedule.
  final String? kind;
  final int? slotIndex;
  final String? taskId;
  final String? reminderId;

  /// The platform sound name to play (OPH-181): a bundle/`Library/Sounds` file
  /// on iOS, a `res/raw` resource on Android, null for the OS's own sound. Part
  /// of the id seed — changing the sound must reschedule, not silently apply to
  /// the next alarm only.
  final String? soundName;
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

/// What the OS was actually asked for (OPH-176) — the loudness half of the
/// alarm log. Recorded straight from the layer that decided it, so a device
/// report never has to be argued from memory again (DESIGN §11 A6).
class ScheduledDelivery {
  const ScheduledDelivery({required this.sound, required this.level});

  /// The sound NAME we asked for: the bundled alarm bed, or the OS default.
  final String sound;

  /// iOS interruption level. Android's equivalent is the channel, which is
  /// implied by the event's `urgent` flag (alarm channel vs reminders channel).
  final String level;
}

/// The bundled 28 s alarm bed's name in the log (the file itself is per
/// platform: `aw_alarm.caf` on iOS, `res/raw/aw_alarm` on Android).
const kAwAlarmSoundName = 'aw_alarm';

/// The OS's own notification sound — what a non-urgent reminder gets until the
/// user picks one (OPH-181).
const kOsDefaultSoundName = 'os-default';

/// **The loudness contract** (round 9, NOTIFICATIONS §2): an urgent alarm's
/// EVERY slot — the first, each repeat, and every post-snooze round — asks for
/// the alarm bed and alarm-grade delivery. There is no "quiet first slot": that
/// shape was never designed, and no user can be expected to model it.
///
/// Pure on purpose: the decision is unit-tested here, and `gateway_local` only
/// carries it to the plugin.
ScheduledDelivery awDeliveryFor({
  required bool urgent,
  required bool criticalEnabled,

  /// The user's chosen sound for this lane (OPH-181); null = the OS's own.
  String? soundName,
}) => ScheduledDelivery(
  sound: soundName ?? (urgent ? kAwAlarmSoundName : kOsDefaultSoundName),
  // Critical is upgraded ONLY when Apple's entitlement + the user's grant are
  // both real (checked, never assumed — NOTIFICATIONS §2).
  level: urgent && criticalEnabled ? 'critical' : 'timeSensitive',
);

abstract class NotificationsGateway {
  /// Idempotent; safe to call before every use.
  Future<void> initialize();

  /// Ask the OS for notification (and Android exact-alarm) permission.
  /// Returns false when the user declined — callers degrade, never crash.
  Future<bool> requestPermissions();

  /// Probe what delivery the OS currently allows (see [AlarmSupport]).
  Future<AlarmSupport> alarmSupport();

  Future<Set<int>> pendingIds();

  /// Schedules [notification] and reports what it asked the OS for, for the
  /// alarm log (OPH-176).
  Future<ScheduledDelivery> schedule(PlannedNotification notification);

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
