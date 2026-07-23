import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/planner.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm(
  String id, {
  bool urgent = false,
  String status = 'scheduled',
  Duration offset = const Duration(hours: 1),
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: 'Görev $id',
  remindAt: now.add(offset),
  status: status,
  urgent: urgent,
  requiresAcknowledgement: urgent,
  snoozedUntil: snoozedUntil,
);

void main() {
  group('planAlarmKitAlarms (OPH-141)', () {
    test('emits one alarm per URGENT reminder, no chain', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true), alarm('R2')],
        now: now,
        privacyMode: false,
      );
      expect(
        out,
        hasLength(1),
      ); // urgent only, a single entry (no 5-slot chain)
      expect(out.single.taskId, 'TR1'.padRight(26, '0'));
      expect(out.single.fireAt, now.add(const Duration(hours: 1)));
    });

    test('skips past instants', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true, offset: const Duration(hours: -1))],
        now: now,
        privacyMode: false,
      );
      expect(out, isEmpty);
    });

    test('honours a snooze', () {
      final snoozed = now.add(const Duration(hours: 3));
      final out = planAlarmKitAlarms(
        alarms: [
          alarm('R1', urgent: true, status: 'snoozed', snoozedUntil: snoozed),
        ],
        now: now,
        privacyMode: false,
      );
      expect(out.single.fireAt, snoozed);
    });

    test('privacy mode hides the task title', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: true,
      );
      expect(out.single.title, 'AllisWell');
    });

    test('ids are stable for identical input and change with fire time', () {
      AlarmKitAlarm one(Duration offset) => planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true, offset: offset)],
        now: now,
        privacyMode: false,
      ).single;

      expect(
        one(const Duration(hours: 1)).id,
        one(const Duration(hours: 1)).id,
      );
      expect(
        one(const Duration(hours: 1)).id,
        isNot(one(const Duration(hours: 2)).id),
      );
    });
  });

  group('planNotifications routeUrgentToAlarmKit (OPH-141)', () {
    test('skips urgent alarms so they only ring on AlarmKit', () {
      final out = planNotifications(
        alarms: [alarm('R1', urgent: true), alarm('R2')],
        now: now,
        privacyMode: false,
        routeUrgentToAlarmKit: true,
      );
      expect(out, hasLength(1)); // only the non-urgent reminder survives
      expect(out.single.urgent, isFalse);
    });

    test('without the flag, urgent still produces its notification chain', () {
      final out = planNotifications(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
      );
      expect(out, hasLength(kUrgentChainOffsets.length));
    });
  });
}
