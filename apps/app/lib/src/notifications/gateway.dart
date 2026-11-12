/// The seam between notification LOGIC (planner/scheduler — pure, tested) and
/// the OS plugin (gateway_local.dart — thin, device-verified). Widget tests
/// swap in a fake gateway; no platform channels leak into the logic layer.
library;

import 'dart:convert';

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

/// A notification the OS is showing right now (OPH-445, #48 gap A).
///
/// An urgent one on Android loops its sound (FLAG_INSISTENT) until it is
/// cancelled, so an alarm handled on another device has to be taken off the
/// screen, not only out of the pending queue. [reminderIds] says which
/// reminders it rings for; empty when the gateway could not tell, and such a
/// notification is never touched.
class ActiveAlarmNotification {
  const ActiveAlarmNotification({
    required this.id,
    required this.urgent,
    this.reminderIds = const [],
    this.taskIds = const [],
  });

  /// From a planned payload (`planner.dart`): `{taskId, reminderId}` for one
  /// task, `{taskIds, reminderIds}` for a grouped minute. Anything else maps to
  /// no reminder.
  factory ActiveAlarmNotification.fromPayload({
    required int id,
    required bool urgent,
    String? payload,
  }) {
    Object? decoded;
    try {
      decoded = payload == null || payload.isEmpty ? null : jsonDecode(payload);
    } on FormatException {
      decoded = null;
    }
    List<String> ids(String one, String many) {
      if (decoded is! Map) return const [];
      final list = decoded[many];
      if (list is List) {
        return [
          for (final v in list)
            if (v is String) v,
        ];
      }
      final single = decoded[one];
      return single is String ? [single] : const [];
    }

    return ActiveAlarmNotification(
      id: id,
      urgent: urgent,
      reminderIds: ids('reminderId', 'reminderIds'),
      taskIds: ids('taskId', 'taskIds'),
    );
  }

  final int id;

  /// Posted on the urgent (alarm) channel.
  final bool urgent;
  final List<String> reminderIds;
  final List<String> taskIds;
}

/// A user interaction with a delivered notification (tap or action button),
/// or an action pulled from the AlarmKit queue (NOTIFICATIONS §2b.3 "Action
/// event").
///
/// An event with an [eventId] is applied exactly once: its `action_receipts`
/// row commits in the same transaction as the write. Without one (a plain
/// notification tap) it is handled the way it always was.
class NotificationEvent {
  const NotificationEvent({
    this.actionId,
    this.payload,
    this.eventId,
    this.taskIds = const [],
    this.untilMs,
    this.occurrenceFireAtMs,
    this.pressedAtMs,
    this.preset,
    this.origin = 'notification',
    this.lane = 'notification',
  });

  /// Null/empty = plain tap on the notification body. An AlarmKit event uses
  /// its v2 action: `snooze`, `acknowledge` or `complete`.
  final String? actionId;
  final String? payload;

  /// The `action_receipts` key; null for a receipt-less tap.
  final String? eventId;

  /// The members the action applies to (a grouped alarm has several).
  final List<String> taskIds;

  /// A snooze target fixed at press time, floored to the second — written
  /// unchanged, never recomputed from the time the app read it.
  final int? untilMs;

  /// The instant of the occurrence that rang: what `acknowledge` acknowledges.
  final int? occurrenceFireAtMs;
  final int? pressedAtMs;

  /// Only on an entry converted from v1 (no [untilMs]): the target is
  /// computed from [pressedAtMs].
  final String? preset;

  /// `alarmkit` · `widget` · `inapp` · `notification`.
  final String origin;

  /// The alarm-log lane the action is recorded under ([AlarmLogLane]).
  final String lane;
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
    this.webPushReady,
    this.webPushServerConfigured,
    this.webPermission,
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

  /// Web only (OPH-313): is this browser actually reachable — permission AND a
  /// live subscription AND an instance with keys to send with.
  ///
  /// Separate from [notificationsEnabled] because on the web the two come
  /// apart: permission can be granted while the server has no VAPID keys, or
  /// while the subscription has been revoked, and in both cases nothing arrives
  /// once the tab is closed. Null off the web, where the OS is the clock and
  /// the question does not arise.
  final bool? webPushReady;

  /// Web only (OPH-393, E-14): does the SERVER do browser push at all.
  ///
  /// False only on the documented answer — `/api/v1/push/public-key` 404s
  /// when the instance has no VAPID keys (OPH-310). Null off the web, while a
  /// live subscription already proves the keys, and when the lookup could not
  /// get an answer: an offline server is not the admin's missing setup, and
  /// saying so would blame the wrong person a second time.
  final bool? webPushServerConfigured;

  /// Web only (#19): why a browser that has not granted notifications has
  /// not. Null off the web, and on the web once permission is granted.
  ///
  /// The three look identical from [notificationsEnabled] and need three
  /// different answers: only an unanswered prompt is fixed by asking, a
  /// refusal is undone in the browser's own site settings, and a browser with
  /// no web push has no permission to give at all.
  final WebPermissionState? webPermission;

  /// The worst thing wrong with delivery right now, or null when nothing is.
  ///
  /// One ordered cascade, in ONE place: the Home banner and the Settings row
  /// disagreed about which problem to name first for as long as there were two
  /// of them, and adding five more conditions to both would have guaranteed it.
  /// Ordered by how completely each one silences an alarm.
  AlarmProblem? get worstProblem {
    // First on the web (OPH-393): a server without keys silences every
    // browser, and nothing the person grants or sets up here changes that —
    // asking them to "allow" or "finish setup" was the server's gap shown as
    // their own fault (E-14).
    if (webPushServerConfigured == false) {
      return AlarmProblem.webPushUnconfigured;
    }
    if (!notificationsEnabled) {
      // On the web "off" is three problems, and naming the wrong one sent the
      // user to an iOS settings page from inside a browser (#19).
      return switch (webPermission) {
        null => AlarmProblem.notificationsOff,
        WebPermissionState.prompt => AlarmProblem.webPermissionPrompt,
        WebPermissionState.denied => AlarmProblem.webPermissionBlocked,
        WebPermissionState.unsupported => AlarmProblem.webUnsupported,
      };
    }
    // Second, because on the web it silences an alarm as completely as a
    // refused permission does — and unlike a refused permission it leaves the
    // browser looking healthy.
    if (webPushReady == false) return AlarmProblem.webPushOff;
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

  /// Web: nothing gets through, and the browser has not been asked yet — the
  /// one web refusal a button can fix, because the prompt is still there.
  webPermissionPrompt,

  /// Web: the user blocked notifications for this site. The browser will not
  /// ask again; only its own site settings can undo it.
  webPermissionBlocked,

  /// Web: this browser cannot receive a notification at all — Safari on an
  /// iPhone outside the Home Screen, a private window, an insecure origin.
  webUnsupported,

  /// Web: permission is granted and nothing can still reach this browser —
  /// no subscription, or an instance with no keys to send with (OPH-313).
  webPushOff,

  /// Web: the server has no keys to send a browser push with (OPH-393). The
  /// one problem only the server's admin can fix.
  webPushUnconfigured,

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

/// Where a browser's own notification permission stands when it is NOT
/// granted (#19) — the web gateway's answer, in words the platform-neutral
/// layer can hold. See [AlarmSupport.webPermission].
enum WebPermissionState {
  /// Never answered: asking shows the browser's prompt.
  prompt,

  /// Refused: asking returns at once and shows nothing.
  denied,

  /// No Notification API, service worker or push manager to ask with.
  unsupported,
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

  /// The notifications the OS is showing right now (OPH-445). Android only:
  /// every other platform returns an empty list, so its behaviour is
  /// unchanged.
  Future<List<ActiveAlarmNotification>> activeNotifications();

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
