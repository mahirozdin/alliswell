/// Which urgent alarms share a minute (#47, ADR-0068).
///
/// The planner rings every urgent alarm of one UTC minute as ONE alarm
/// (`planNotifications`, `planAlarmKitAlarms`). Creation is never blocked by a
/// taken minute (owner answer 3): a snooze that lands there simply joins that
/// minute's group, and the snooze tile says so before the tap —
/// "09:05’te çalar · başka alarmla birlikte".
///
/// Pure: no widget, no provider, no clock. The snooze tile (OPH-466) and the
/// creation hint (OPH-444) share [urgentAlarmsInMinute].
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
