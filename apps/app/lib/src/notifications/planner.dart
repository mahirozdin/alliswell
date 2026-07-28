import 'dart:convert';

import '../i18n/i18n.dart';
import 'alarmkit.dart';
import 'gateway.dart';
import 'reminder_profile.dart';

/// What the planner needs to know about one alarm — a reminder row joined
/// with its task (title for rendering, urgency for the chain).
class AlarmInput {
  const AlarmInput({
    required this.reminderId,
    required this.taskId,
    required this.taskTitle,
    required this.remindAt,
    required this.status,
    required this.urgent,
    required this.requiresAcknowledgement,
    this.kind = 'remind',
    this.snoozeRound = 0,
    this.snoozedUntil,
  });

  final String reminderId;
  final String taskId;
  final String taskTitle;

  /// `remind` (the nudge the user asked for) or `due` (the task's own deadline,
  /// OPH-175). It only changes what the notification SAYS — a deadline alarm is
  /// as loud as any other urgent alarm.
  final String kind;

  /// How many times this alarm has been snoozed (OPH-177): a post-snooze ring
  /// names its round instead of impersonating a first alert.
  final int snoozeRound;
  final DateTime remindAt;

  /// scheduled | snoozed | delivered (anything else never reaches the planner,
  /// and gets filtered defensively if it does).
  final String status;
  final bool urgent;
  final bool requiresAcknowledgement;
  final DateTime? snoozedUntil;
}

const _activeStatuses = {'scheduled', 'snoozed', 'delivered'};

/// What the FIRST slot of an urgent alarm says. Honest about which alarm it is
/// (OPH-175) and about being a post-snooze round rather than a fresh alert
/// (OPH-176, round 9 #6.6 — the user read "still waiting for acknowledgement"
/// five minutes after snoozing and reasonably called it "the 1st again").
String _firstBody(AlarmInput alarm) {
  if (alarm.status == 'snoozed') {
    return 'notif.afterSnooze'.tr(
      args: {'count': '${alarm.snoozeRound > 0 ? alarm.snoozeRound : 1}'},
    );
  }
  if (alarm.kind == 'due') return 'notif.dueNow'.tr();
  return 'notif.urgentFirst'.tr();
}

String _repeatBody(int index) =>
    'notif.urgentRepeat'.tr(args: {'count': '${index + 1}'});

/// Pure planning (OPH-061/063/064): alarms in, desired OS notifications out.
/// Windowed to [maxPending] soonest fire-times — iOS silently drops beyond 64
/// pending requests, so we keep well under (NOTIFICATIONS.md §2) and re-fill
/// as time passes. Past instants are skipped (the OS cannot schedule them; if
/// they were scheduled earlier, they already fired).
List<PlannedNotification> planNotifications({
  required List<AlarmInput> alarms,
  required DateTime now,
  required bool privacyMode,
  int maxPending = 40,

  /// The reminders AlarmKit has taken over (OPH-182). Was a bare "urgent alarms
  /// live elsewhere" flag; it has to be a SET, because the AlarmKit lane is
  /// capped — an urgent alarm that did not fit there must keep its notification
  /// chain instead of falling between the two lanes.
  Set<String> alarmKitReminderIds = const {},

  /// The user's re-alert chain (OPH-179). Defaults to what shipped before it
  /// was configurable, so a caller that does not care behaves as it always did.
  ReminderProfile profile = ReminderProfile.factory,

  /// The resolved sound names for the two lanes (OPH-181). Null = OS default.
  String? alarmSoundName,
  String? reminderSoundName,
}) {
  final planned = <PlannedNotification>[];

  for (final alarm in alarms) {
    if (!_activeStatuses.contains(alarm.status)) continue;
    // On iOS 26+ the URGENT lane is AlarmKit ([planAlarmKitAlarms]); leaving it
    // on notifications too would ring twice. Non-urgent reminders stay here, and
    // so does any urgent alarm AlarmKit did not take.
    if (alarmKitReminderIds.contains(alarm.reminderId)) continue;
    final base =
        (alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ??
        alarm.remindAt;
    // The user's chain, with two honest exceptions: an alarm that needs no
    // acknowledgement rings once, and a post-snooze round rings once when the
    // user asked for that (OPH-179).
    final repeats =
        alarm.urgent &&
        alarm.requiresAcknowledgement &&
        (alarm.status != 'snoozed' || profile.repeatAfterSnooze);
    final chain = repeats ? profile.offsets : const [Duration.zero];

    for (final (index, offset) in chain.indexed) {
      final fireAt = base.add(offset).toUtc();
      if (!fireAt.isAfter(now)) continue;

      // Privacy mode (OPH-064, BLUEPRINT §8.3): nothing personal on the lock
      // screen — the tap still deep-links to the task.
      final title = privacyMode
          ? 'AllisWell'
          : (alarm.urgent ? '⏰ ${alarm.taskTitle}' : alarm.taskTitle);
      final body = privacyMode
          ? 'notif.privateBody'.tr()
          : (alarm.urgent
                ? (index == 0 ? _firstBody(alarm) : _repeatBody(index))
                : 'notif.reminder'.tr());

      final soundName = alarm.urgent ? alarmSoundName : reminderSoundName;
      final payload = jsonEncode({
        'taskId': alarm.taskId,
        'reminderId': alarm.reminderId,
        'chainIndex': index,
      });
      planned.add(
        PlannedNotification(
          id: notificationIdFor(
            '${alarm.reminderId}|$index|${fireAt.millisecondsSinceEpoch}|$title|$body|${alarm.urgent}|$soundName',
          ),
          title: title,
          body: body,
          fireAt: fireAt,
          urgent: alarm.urgent,
          payload: payload,
          // Diagnostics only (OPH-176): what the alarm log names this slot.
          kind: alarm.kind,
          slotIndex: index,
          taskId: alarm.taskId,
          reminderId: alarm.reminderId,
          soundName: soundName,
        ),
      );
    }
  }

  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return planned.length > maxPending ? planned.sublist(0, maxPending) : planned;
}

/// Pure AlarmKit lane (OPH-141, NOTIFICATIONS.md §2b): the URGENT alarms, one
/// AlarmKit alarm each. AlarmKit rings-until-answered natively, so there is NO
/// re-alert chain here — a single entry per reminder replaces the notification
/// lane's 5 slots. Ids are content hashes in their OWN namespace (`|alarmkit|`)
/// so the scheduler's set-diff cancels them on acknowledge, exactly like
/// notifications. Non-urgent reminders never enter this lane. Windowed and
/// past-skipped on the same rules as [planNotifications].
///
/// Capped at [maxAlarms] NEAREST alarms (OPH-182): the per-app AlarmKit ceiling
/// is undocumented, so the far future is left to the notification chain rather
/// than gambling on a limit we cannot read. Whatever this returns is what the
/// scheduler then EXCLUDES from the notification lane — an alarm that does not
/// fit here keeps its chain, so the cap degrades delivery instead of losing it.
List<AlarmKitAlarm> planAlarmKitAlarms({
  required List<AlarmInput> alarms,
  required DateTime now,
  required bool privacyMode,
  int maxAlarms = kMaxAlarmKitAlarms,

  /// Which snooze the alert's secondary button applies — the first of the user's
  /// own snooze order (OPH-179 N4). Its label becomes the button's text, so the
  /// button says what it will do ("30 dk"), the way OPH-177 made the in-app
  /// buttons say it.
  String snoozePreset = kDefaultSnoozePreset,
  String? soundName,
}) {
  final planned = <AlarmKitAlarm>[];
  // Localized HERE, not in Swift: the bridge has no translations, and a
  // hard-coded "Onayla" is how the alert ended up Turkish-only for every user.
  final stopLabel = 'notif.action.acknowledge'.tr();
  final snoozeLabelKey = kSnoozePresetLabels[snoozePreset];
  final snoozeLabel = (snoozeLabelKey ?? 'alarm.ringing.snooze').tr();

  for (final alarm in alarms) {
    if (!_activeStatuses.contains(alarm.status)) continue;
    if (!alarm.urgent) continue; // AlarmKit is the URGENT surface only.

    final base =
        (alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ??
        alarm.remindAt;
    final fireAt = base.toUtc();
    if (!fireAt.isAfter(now)) continue;

    final title = privacyMode ? 'AllisWell' : alarm.taskTitle;
    final body = privacyMode ? 'notif.privateBody'.tr() : _firstBody(alarm);

    planned.add(
      AlarmKitAlarm(
        id: notificationIdFor(
          '${alarm.reminderId}|alarmkit|${fireAt.millisecondsSinceEpoch}|$title'
          '|$soundName',
        ),
        title: title,
        body: body,
        fireAt: fireAt,
        taskId: alarm.taskId,
        reminderId: alarm.reminderId,
        stopLabel: stopLabel,
        snoozeLabel: snoozeLabel,
        snoozePreset: snoozePreset,
        soundName: soundName,
      ),
    );
  }

  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return planned.length > maxAlarms ? planned.sublist(0, maxAlarms) : planned;
}
