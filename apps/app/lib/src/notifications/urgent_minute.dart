/// Which urgent alarms share a minute (#47, ADR-0068).
///
/// The planner rings every urgent alarm of one UTC minute as ONE alarm
/// (`planNotifications`, `planAlarmKitAlarms`). Creation is never blocked by a
/// taken minute (owner answer 3): a snooze that lands there simply joins that
/// minute's group, and the snooze tile says so before the tap —
/// "09:05’te çalar · başka alarmla birlikte".
///
/// Pure: no widget, no provider, no clock. The snooze tile (OPH-466) and the
/// creation hint (OPH-444, [sharedUrgentMinutes]) share
/// [urgentAlarmsInMinute].
library;

import '../core/date_format.dart';
import '../core/tr_locative.dart';
import '../i18n/i18n.dart';
import 'planner.dart';

/// The statuses that may still ring — the planner's own set. Acknowledged,
/// cancelled (a muted or closed task's reminder, OPH-178) and completed rows
/// never ring, so they never make a minute "taken".
const Set<String> _activeStatuses = {'scheduled', 'snoozed', 'delivered'};

/// The UTC minute an instant falls in: floor(ms / 60000). 09:00:59 and
/// 09:01:00 are different minutes, whatever the device's time zone.
int _utcMinute(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 60000;

/// Where an alarm rings now: a snoozed one at its snooze target, every other
/// at its own instant — the planner's base instant.
DateTime _ringsAt(AlarmInput alarm) =>
    ((alarm.status == 'snoozed' ? alarm.snoozedUntil : null) ?? alarm.remindAt)
        .toUtc();

/// How many OTHER tasks have an active urgent alarm in the UTC minute of [at].
///
/// A task counts once however many of its alarms (remind, due) sit in that
/// minute — the group's members are task ids. [exceptTaskIds] are left out:
/// the task being snoozed or created never counts itself. Normal reminders
/// ring as plain notifications and never join a group, so they do not count.
int urgentAlarmsInMinute(
  List<AlarmInput> alarms,
  DateTime at, {
  Set<String> exceptTaskIds = const {},
}) {
  final minute = _utcMinute(at);
  final tasks = <String>{};
  for (final alarm in alarms) {
    if (!alarm.urgent) continue;
    if (!_activeStatuses.contains(alarm.status)) continue;
    if (exceptTaskIds.contains(alarm.taskId)) continue;
    if (_utcMinute(_ringsAt(alarm)) != minute) continue;
    tasks.add(alarm.taskId);
  }
  return tasks.length;
}

/// The snooze tile's second line: "rings at 9:05 AM", or — when the target
/// minute already holds another urgent alarm ([joinsGroup]) — "rings at
/// 9:05 AM · with another alarm". Turkish puts the locative on the spoken time
/// (OPH-422): "09:05’te çalar · başka alarmla birlikte".
///
/// [format] is the user's date format id (`dateFormatProvider`);
/// [languageCode] defaults to the active app language.
String snoozeTileSubline(
  DateTime until, {
  required bool joinsGroup,
  String format = kAwSystemDateFormat,
  String? languageCode,
}) {
  final time = awAt(
    awFormatTime(until, format: format),
    languageCode: languageCode ?? AwI18n.instance.locale.languageCode,
  );
  return (joinsGroup ? 'alarm.snoozeJoinsGroup' : 'alarm.snoozeRingsAt').tr(
    args: {'time': time},
  );
}

/// One of the written task's own alarm instants that lands in a minute another
/// task's urgent alarm already holds (OPH-444): [kind] is `remind` or `due`,
/// [at] the instant, [count] how many urgent alarms ring together there —
/// this task included.
typedef SharedUrgentMinute = ({String kind, DateTime at, int count});

/// The minutes the task being written would share with other urgent alarms.
///
/// Owner answer 3: never block, never shift — the create sheet, the detail
/// screen and the quick-add confirmation only say it. The task's instants are
/// the ones `taskAlarmInstants` rings: the reminder, and the deadline while
/// the alarm is urgent. Two of them in one UTC minute ring as one alarm, so
/// that minute gets one line (the reminder's). Nothing when [urgent] is off (a
/// normal reminder rings alone, never in a group) and nothing for a minute
/// before [now]'s (it never rings again). [taskId] is the task itself when it
/// already exists: its own alarms in the feed never make a minute "taken".
List<SharedUrgentMinute> sharedUrgentMinutes(
  List<AlarmInput> feed, {
  required bool urgent,
  required DateTime now,
  DateTime? remindAt,
  DateTime? dueAt,
  String? taskId,
}) {
  if (!urgent) return const [];
  final nowMinute = _utcMinute(now);
  final seen = <int>{};
  final hits = <SharedUrgentMinute>[];
  for (final (kind, at) in [('remind', remindAt), ('due', dueAt)]) {
    if (at == null) continue;
    final minute = _utcMinute(at);
    if (minute < nowMinute || !seen.add(minute)) continue;
    final others = urgentAlarmsInMinute(feed, at, exceptTaskIds: {?taskId});
    if (others > 0) hits.add((kind: kind, at: at, count: others + 1));
  }
  return hits;
}

/// "09:00’da 2 acil alarm birlikte çalacak" — [count] includes the task being
/// written. The time goes through the OPH-422 locative like the snooze tile;
/// no other task's title is ever part of it.
String sharedMinuteLine(
  DateTime at,
  int count, {
  String format = kAwSystemDateFormat,
  String? languageCode,
}) {
  final time = awAt(
    awFormatTime(at.toLocal(), format: format),
    languageCode: languageCode ?? AwI18n.instance.locale.languageCode,
  );
  return 'alarm.sharedMinute'.tr(args: {'time': time, 'count': '$count'});
}
