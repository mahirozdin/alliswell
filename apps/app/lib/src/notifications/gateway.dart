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
    this.soundEnabled,
    this.alertEnabled,
    this.provisionalOnly = false,
    this.timeSensitiveEnabled,
    this.alarmKitAuthorized,
    this.pendingCount,
  });

  final bool notificationsEnabled;

  /// iOS/macOS: true only when Apple granted the critical-alerts entitlement
  /// AND the user allowed them — the pair that lets sound bypass the mute
  /// switch. Always false without the entitlement (docs/NOTIFICATIONS.md §2).
  final bool criticalAlertsEnabled;

  /// Android: the "Alarms & reminders" special access (null elsewhere).
  final bool? exactAlarmsEnabled;

  // ── Round 19 (OPH-277) ──────────────────────────────────────────────────
  //
  // The probe already ASKED the OS for all of these — `checkPermissions()`
  // returns them in one object — and then threw every one away except
  // `isEnabled` and `isCriticalEnabled`. So a phone with notifications ON and
  // sounds OFF reported "ready to ring", which is the exact sentence round 19
  // proved wrong. Each is nullable because only Darwin can answer it.

  /// iOS/macOS: may a notification make a SOUND. Off means the alarm still
  /// arrives and is still silent — the failure mode with no symptom.
  final bool? soundEnabled;

  /// iOS/macOS: may a notification draw a banner. Off means it lands in
  /// Notification Center and nowhere else.
  final bool? alertEnabled;

  /// iOS: authorization is PROVISIONAL — granted quietly, delivered quietly.
  /// No banner, no sound, straight to Notification Center, by design.
  final bool provisionalOnly;

  /// iOS 15+: the per-app Time Sensitive allowance. Without it the OS silently
  /// demotes `.timeSensitive` to `.active` and every Focus mode buries the
  /// alarm — NOTIFICATIONS §2 calls this "the most common silent failure", and
  /// nothing was checking it. Null where the platform cannot say.
  final bool? timeSensitiveEnabled;

  /// iOS 26+: the AlarmKit grant. Null off iOS 26, false when the user
  /// declined or revoked it — in which case urgent alarms are back on the
  /// notification lane, which the mute switch can silence.
  final bool? alarmKitAuthorized;

  /// How many requests the OS is holding for us. iOS keeps only the 64
  /// soonest; a number near that ceiling is a warning in its own right.
  final int? pendingCount;

  /// The worst thing wrong with delivery right now, or null when nothing is.
  ///
  /// One ordered cascade, in ONE place: the Home banner and the Settings row
  /// disagreed about which problem to name first for as long as there were two
  /// of them, and adding five more conditions to both would have guaranteed it.
  /// Ordered by how completely each one silences an alarm.
  AlarmProblem? get worstProblem {
    if (!notificationsEnabled) return AlarmProblem.notificationsOff;
    if (provisionalOnly) return AlarmProblem.provisional;
    if (soundEnabled == false) return AlarmProblem.soundOff;
    if (alertEnabled == false) return AlarmProblem.alertOff;
    if (exactAlarmsEnabled == false) return AlarmProblem.exactAlarmsOff;
    if (timeSensitiveEnabled == false) return AlarmProblem.timeSensitiveOff;
    if (alarmKitAuthorized == false) return AlarmProblem.alarmKitOff;
    return null;
  }
}

/// What is stopping an alarm from being heard (OPH-277).
///
/// An enum rather than a pre-rendered sentence: the banner, the Settings row
/// and the "how do I fix this" sheet each say it at a different length, and a
/// string decided in the gateway would have to be all three.
enum AlarmProblem {
  /// Nothing gets through at all.
  notificationsOff,

  /// iOS granted us the quiet kind of permission: no banner, no sound.
  provisional,

  /// It arrives, on time, in silence.
  soundOff,

  /// It makes a sound with nothing on screen to explain it.
  alertOff,

  /// Android's "Alarms & reminders" special access.
  exactAlarmsOff,

  /// iOS demotes our time-sensitive alarms; any Focus mode then buries them.
  timeSensitiveOff,

  /// iOS 26+ AlarmKit declined — urgent alarms drop back to a lane the mute
  /// switch can silence.
  alarmKitOff,
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

/// How far ahead a rehearsal alarm is armed (OPH-277).
///
/// Long enough to lock the phone and put it down — which is the state most
/// silent-alarm reports are actually about — and short enough that nobody has
/// to remember they started one.
const Duration kAlarmTestDelay = Duration(seconds: 15);

/// The id every test alarm reuses (OPH-277).
///
/// Fixed rather than hashed, and negative so it can never collide with a
/// planned notification: a second rehearsal replaces the first instead of
/// stacking. The scheduler's set-diff SKIPS this id — it cancels every pending
/// id it did not plan, and the rehearsal is by definition not in the plan, so
/// without the exemption the system under test could quietly delete the
/// diagnostic during the 15 seconds it is waiting to prove something.
const int kAlarmTestNotificationId = -424242;

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

  /// Schedules a real alarm [after] from now, through the real lane, and
  /// returns what it asked the OS for (OPH-277).
  ///
  /// The one thing a bug report about a silent alarm never had: a way to make
  /// the failure happen on purpose, right now, with the log watching. It is a
  /// gateway method rather than a call the settings screen assembles, so the
  /// rehearsal cannot accidentally take a different code path from the thing it
  /// is rehearsing.
  Future<ScheduledDelivery> scheduleTestAlarm({
    required String title,
    required String body,
    required Duration after,
    String? soundName,
  });

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
