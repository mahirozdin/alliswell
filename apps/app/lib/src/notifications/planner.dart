import 'dart:convert';

import '../i18n/i18n.dart';
import 'alarmkit.dart';
import 'alarmkit_identity.dart';
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
  // Urgent alarms in one UTC minute ring as ONE chain (ADR-0068, #47): two
  // chains a few seconds apart are two sounds and two full-screen intents,
  // and answering one leaves the other ringing.
  final urgentByMinute = <int, List<AlarmInput>>{};

  for (final alarm in alarms) {
    if (!_activeStatuses.contains(alarm.status)) continue;
    // On iOS 26+ the URGENT lane is AlarmKit ([planAlarmKitAlarms]); leaving it
    // on notifications too would ring twice. Non-urgent reminders stay here, and
    // so does any urgent alarm AlarmKit did not take.
    if (alarmKitReminderIds.contains(alarm.reminderId)) continue;
    if (alarm.urgent) {
      urgentByMinute
          .putIfAbsent(_minuteOf(_baseOf(alarm)), () => [])
          .add(alarm);
      continue;
    }
    _planChain(
      planned,
      lead: alarm,
      now: now,
      privacyMode: privacyMode,
      chain: const [Duration.zero],
      soundName: reminderSoundName,
    );
  }

  for (final rows in urgentByMinute.values) {
    rows.sort(_byInstant);
    final lead = rows.first;
    final members = alarmKitMembers(rows.map((a) => a.taskId));
    // The user's chain, with two honest exceptions: an alarm that needs no
    // acknowledgement rings once, and a post-snooze round rings once when the
    // user asked for that (OPH-179). A group re-alerts while any member would.
    final repeats = rows.any(
      (a) =>
          a.requiresAcknowledgement &&
          (a.status != 'snoozed' || profile.repeatAfterSnooze),
    );
    _planChain(
      planned,
      lead: lead,
      now: now,
      privacyMode: privacyMode,
      chain: repeats ? profile.offsets : const [Duration.zero],
      soundName: alarmSoundName,
      // One row is today's chain, byte for byte (same ids, same payload).
      group: rows.length == 1 ? null : (members: members, rows: rows),
    );
  }

  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return planned.length > maxPending ? planned.sublist(0, maxPending) : planned;
}

/// The instant an alarm rings: `snoozedUntil` while snoozed, else `remindAt`.
DateTime _baseOf(AlarmInput alarm) =>
    ((alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ?? alarm.remindAt)
        .toUtc();

int _minuteOf(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 60000;

/// Earliest instant first; the reminder id breaks a tie so the lead row (and
/// so every id derived from it) never depends on the replica's row order.
int _byInstant(AlarmInput a, AlarmInput b) {
  final byTime = _baseOf(a).compareTo(_baseOf(b));
  return byTime != 0 ? byTime : a.reminderId.compareTo(b.reminderId);
}

/// One notification chain: [lead]'s alone, or — with [group] — the chain a
/// whole urgent minute shares. A group of several tasks names none of them
/// (title and body say how many); a group of one task (its remind and due
/// rows in one minute) keeps the task's own wording. Either way the payload
/// lists every task and reminder id, so a button applies to all of them, and
/// nothing but ids (I-13).
void _planChain(
  List<PlannedNotification> planned, {
  required AlarmInput lead,
  required DateTime now,
  required bool privacyMode,
  required List<Duration> chain,
  required String? soundName,
  ({List<String> members, List<AlarmInput> rows})? group,
}) {
  final base = _baseOf(lead);
  final count = group?.members.length ?? 1;
  final reminderIds = group == null
      ? null
      : (group.rows.map((a) => a.reminderId).toSet().toList()..sort());

  for (final (index, offset) in chain.indexed) {
    final fireAt = base.add(offset).toUtc();
    if (!fireAt.isAfter(now)) continue;

    // Privacy mode (OPH-064, BLUEPRINT §8.3): nothing personal on the lock
    // screen — the tap still deep-links to the task.
    final String title;
    final String body;
    if (privacyMode) {
      title = 'AllisWell';
      body = 'notif.privateBody'.tr();
    } else if (!lead.urgent) {
      title = lead.taskTitle;
      body = 'notif.reminder'.tr();
    } else if (count > 1) {
      title = '⏰ ${'alarm.groupTitle'.tr(args: {'count': '$count'})}';
      body = index == 0
          ? 'notif.urgentMany'.tr(args: {'count': '$count'})
          : _repeatBody(index);
    } else {
      title = '⏰ ${lead.taskTitle}';
      body = index == 0 ? _firstBody(lead) : _repeatBody(index);
    }

    final taskId = group?.members.first ?? lead.taskId;
    final payload = jsonEncode(
      group == null
          ? {
              'taskId': lead.taskId,
              'reminderId': lead.reminderId,
              'chainIndex': index,
            }
          : {
              'taskId': taskId,
              'taskIds': group.members,
              'reminderIds': reminderIds,
              'chainIndex': index,
            },
    );
    final contentSeed =
        '$index|${fireAt.millisecondsSinceEpoch}|$title|$body|${lead.urgent}|$soundName';
    planned.add(
      PlannedNotification(
        // One task keeps the seed it always had, so an upgrade or a second
        // row of the same task does not churn its chain.
        id: notificationIdFor(
          count > 1
              ? 'group|${reminderIds!.join(',')}|$contentSeed'
              : '${lead.reminderId}|$contentSeed',
        ),
        title: title,
        body: body,
        fireAt: fireAt,
        urgent: lead.urgent,
        payload: payload,
        // Diagnostics only (OPH-176): what the alarm log names this slot.
        kind: lead.kind,
        slotIndex: index,
        taskId: taskId,
        reminderId: lead.reminderId,
        soundName: soundName,
      ),
    );
  }
}

/// Pure AlarmKit lane (OPH-141, NOTIFICATIONS.md §2b): the URGENT alarms, one
/// AlarmKit alarm per UTC minute — several tasks due in one minute share it
/// (OPH-440, ADR-0068), and a minute with one task keeps that task's own
/// OPH-424 id. AlarmKit rings-until-answered natively, so there is NO
/// re-alert chain here — a single entry per occurrence replaces the
/// notification lane's 5 slots. Ids are occurrence ids (task + instant,
/// [alarmKitOccurrenceId]) so the scheduler's set-diff cancels them on
/// acknowledge and replaces them when the time moves; a renamed task keeps its
/// id and changes only its fingerprint. Non-urgent reminders never enter this lane. Windowed and
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

  // Every urgent occurrence in one UTC minute is ONE alarm (ADR-0068, #47):
  // AlarmKit gives no order to alarms due together, and two of them in one
  // minute have been seen to leave both silent.
  final byMinute = <int, List<AlarmInput>>{};
  for (final alarm in alarms) {
    if (!_activeStatuses.contains(alarm.status)) continue;
    if (!alarm.urgent) continue; // AlarmKit is the URGENT surface only.
    final fireAt = _baseOf(alarm);
    if (!fireAt.isAfter(now)) continue;
    byMinute.putIfAbsent(_minuteOf(fireAt), () => []).add(alarm);
  }

  for (final rows in byMinute.values) {
    rows.sort(_byInstant);
    // The member key is the task (NOTIFICATIONS.md §2b.3): a task's remind and
    // due rows in one minute are one member, and both ride on this alarm so
    // the notification lane knows AlarmKit covers them.
    final members = alarmKitMembers(rows.map((a) => a.taskId));
    final lead = rows.first;
    final first = rows.firstWhere((a) => a.taskId == members.first);
    final fireAt = _baseOf(lead);
    final count = members.length;

    final title = privacyMode
        ? 'AllisWell'
        : (count == 1
              ? lead.taskTitle
              : 'alarm.groupTitle'.tr(args: {'count': '$count'}));
    final body = privacyMode
        ? 'notif.privateBody'.tr()
        : (count == 1
              ? _firstBody(lead)
              : 'notif.urgentMany'.tr(args: {'count': '$count'}));

    planned.add(
      AlarmKitAlarm(
        id: alarmKitOccurrenceId(members, alarmKitFireAtMs(fireAt)),
        members: members,
        fp: alarmKitFingerprint(
          title: title,
          body: body,
          soundName: soundName,
          stopLabel: stopLabel,
          snoozeLabel: snoozeLabel,
          snoozePreset: snoozePreset,
        ),
        title: title,
        body: body,
        fireAt: fireAt,
        taskId: first.taskId,
        reminderId: first.reminderId,
        reminderIds: {for (final a in rows) a.reminderId}.toList(),
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
