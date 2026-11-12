import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/urgent_minute.dart';

// #47 / OPH-442: a snooze that lands on a minute another urgent alarm already
// holds joins that alarm's group (the planner rings one alarm per UTC minute).
// The snooze tile says so before the tap: "09:05’te çalar · başka alarmla
// birlikte". These are the two pure pieces the tile (OPH-466) and the
// creation hint (OPH-444) share.

AlarmInput _alarm(
  String taskId,
  DateTime at, {
  String status = 'scheduled',
  bool urgent = true,
  DateTime? snoozedUntil,
  String kind = 'remind',
}) => AlarmInput(
  reminderId: 'r-$taskId-$kind',
  taskId: taskId,
  taskTitle: 'Task $taskId',
  kind: kind,
  remindAt: at,
  status: status,
  urgent: urgent,
  requiresAcknowledgement: urgent,
  snoozedUntil: snoozedUntil,
);

void main() {
  final nine = DateTime.utc(2030, 6, 1, 9);

  test('same task never counts itself; acknowledged, muted and normal '
      'reminders do not count', () {
    final at = nine.add(const Duration(minutes: 5));
    final alarms = [
      // The task being snoozed: its own remind AND due alarm in that minute.
      _alarm('self', at),
      _alarm('self', at.add(const Duration(seconds: 20)), kind: 'due'),
      // Already answered.
      _alarm('acked', at, status: 'acknowledged'),
      // A muted task's reminder is cancelled (OPH-178); so is a done task's.
      _alarm('muted', at, status: 'cancelled'),
      _alarm('done', at, status: 'completed'),
      // A normal reminder rings as a plain notification, never in the group.
      _alarm('normal', at, urgent: false),
    ];
    expect(urgentAlarmsInMinute(alarms, at, exceptTaskIds: {'self'}), 0);

    // One real other urgent alarm, anywhere in the minute, counts once per
    // task — its remind and due alarm in the same minute are one alarm.
    final withOther = [
      ...alarms,
      _alarm('other', at.add(const Duration(seconds: 42))),
      _alarm('other', at.add(const Duration(seconds: 50)), kind: 'due'),
    ];
    expect(urgentAlarmsInMinute(withOther, at, exceptTaskIds: {'self'}), 1);
    // Without the exception the task's own alarm counts too.
    expect(urgentAlarmsInMinute(withOther, at), 2);
    // A delivered (ringing) and a snoozed alarm are still active; a snoozed
    // one sits at its snooze target, not at its original instant.
    final more = [
      ...withOther,
      _alarm('ringing', at, status: 'delivered'),
      _alarm(
        'snoozedHere',
        nine,
        status: 'snoozed',
        snoozedUntil: at.add(const Duration(seconds: 5)),
      ),
      _alarm(
        'snoozedAway',
        at,
        status: 'snoozed',
        snoozedUntil: at.add(const Duration(minutes: 10)),
      ),
    ];
    expect(urgentAlarmsInMinute(more, at, exceptTaskIds: {'self'}), 3);
  });

  test('minutes are UTC minutes: 09:00:59 and 09:01:00 are different '
      'groups', () {
    final alarms = [
      _alarm('a', nine.add(const Duration(seconds: 59))),
      _alarm('b', nine.add(const Duration(minutes: 1))),
    ];
    expect(urgentAlarmsInMinute(alarms, nine), 1);
    expect(
      urgentAlarmsInMinute(alarms, nine.add(const Duration(minutes: 1))),
      1,
    );
    expect(
      urgentAlarmsInMinute(
        alarms,
        nine.add(const Duration(minutes: 1, seconds: 59, milliseconds: 999)),
      ),
      1,
    );
    expect(
      urgentAlarmsInMinute(alarms, nine.add(const Duration(minutes: 2))),
      0,
    );
    // A local DateTime is the same instant: the minute is taken in UTC.
    expect(urgentAlarmsInMinute(alarms, nine.toLocal()), 1);
    // Sub-minute offsets in the alarm and in `at` floor to the same minute.
    expect(
      urgentAlarmsInMinute([
        _alarm('c', nine.add(const Duration(milliseconds: 1))),
      ], nine.add(const Duration(seconds: 59, milliseconds: 999))),
      1,
    );
  });

  test('the snooze sub-line says it rings with another alarm only when the '
      'minute is taken', () {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

    // Local wall-clock 09:05, so the line reads the same on any machine.
    final until = DateTime(2030, 6, 1, 9, 5);
    final taken = [_alarm('other', until.toUtc())];
    final free = [
      _alarm('other', until.add(const Duration(minutes: 1)).toUtc()),
    ];

    String line(List<AlarmInput> alarms) => snoozeTileSubline(
      until,
      joinsGroup:
          urgentAlarmsInMinute(alarms, until, exceptTaskIds: {'self'}) > 0,
    );

    expect(line(taken), '09:05’te çalar · başka alarmla birlikte');
    expect(line(free), '09:05’te çalar');
    // The locative follows the spoken time (OPH-422), not a fixed suffix.
    expect(
      snoozeTileSubline(DateTime(2030, 6, 1, 9, 30), joinsGroup: true),
      '09:30’da çalar · başka alarmla birlikte',
    );
    // The snoozed task's own alarm in that minute is not "another alarm".
    expect(
      snoozeTileSubline(
        until,
        joinsGroup:
            urgentAlarmsInMinute(
              [_alarm('self', until.toUtc())],
              until,
              exceptTaskIds: {'self'},
            ) >
            0,
      ),
      '09:05’te çalar',
    );

    AwI18n.instance.setActiveCached(const Locale('en'));
    // intl puts a narrow no-break space before AM/PM (CLDR); compare words.
    String plain(String s) => s.replaceAll('\u202f', ' ');
    expect(
      plain(snoozeTileSubline(until, joinsGroup: true)),
      'rings at 9:05 AM · with another alarm',
    );
    expect(
      plain(snoozeTileSubline(until, joinsGroup: false)),
      'rings at 9:05 AM',
    );
    // A chosen 24-hour format is honoured.
    expect(
      snoozeTileSubline(until, joinsGroup: false, format: 'iso'),
      'rings at 09:05',
    );
  });
}
