import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';

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

  group('the alert carries the app\'s own words and sound (OPH-182)', () {
    test('buttons are localized here, and the snooze says what it will do', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        snoozePreset: '30_min',
      ).single;

      // Whatever the fixture locale resolves these to, they must be the app's
      // strings — never empty, and never a Swift-side literal.
      expect(out.stopLabel, isNotEmpty);
      expect(out.snoozeLabel, isNotEmpty);
      expect(out.snoozeLabel, isNot(out.stopLabel));
      expect(out.snoozePreset, '30_min');
    });

    test('an unknown preset still gets a button rather than an empty one', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        snoozePreset: 'from_a_future_version',
      ).single;
      expect(out.snoozeLabel, isNotEmpty);
    });

    test('the sound name rides along AND reschedules when it changes', () {
      AlarmKitAlarm withSound(String? sound) => planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        soundName: sound,
      ).single;

      expect(withSound('aw_chime.caf').soundName, 'aw_chime.caf');
      expect(withSound('aw_chime.caf').id, withSound('aw_chime.caf').id);
      // OPH-181's rule, applied to this lane too: changing the sound must
      // re-schedule, not quietly apply "from the next alarm on".
      expect(withSound('aw_chime.caf').id, isNot(withSound('aw_ping.caf').id));
    });
  });

  group(
    'the AlarmKit lane is capped, and the overflow is not lost (OPH-182)',
    () {
      List<AlarmInput> urgentAlarms(int count) => [
        for (var i = 0; i < count; i++)
          alarm('R$i', urgent: true, offset: Duration(hours: i + 1)),
      ];

      test('keeps the NEAREST maxAlarms and drops the far ones', () {
        final out = planAlarmKitAlarms(
          alarms: urgentAlarms(kMaxAlarmKitAlarms + 3),
          now: now,
          privacyMode: false,
        );
        expect(out, hasLength(kMaxAlarmKitAlarms));
        expect(out.first.fireAt, now.add(const Duration(hours: 1)));
        expect(out.last.fireAt, now.add(Duration(hours: kMaxAlarmKitAlarms)));
      });

      test('what did not fit keeps its notification chain', () {
        final alarms = urgentAlarms(kMaxAlarmKitAlarms + 2);
        final ak = planAlarmKitAlarms(
          alarms: alarms,
          now: now,
          privacyMode: false,
        );
        final covered = {for (final a in ak) a.reminderId};

        final notifications = planNotifications(
          alarms: alarms,
          now: now,
          privacyMode: false,
          alarmKitReminderIds: covered,
        );

        // The two alarms past the cap are the ONLY ones still on notifications —
        // an urgent alarm must never fall between the two lanes.
        final onNotifications = notifications.map((n) => n.reminderId).toSet();
        expect(onNotifications, hasLength(2));
        expect(onNotifications.intersection(covered), isEmpty);
        expect(
          notifications.where((n) => n.reminderId == onNotifications.first),
          hasLength(ReminderProfile.factory.offsets.length),
        );
      });
    },
  );

  group('planNotifications alarmKitReminderIds (OPH-141)', () {
    test('skips the alarms AlarmKit took so they only ring there', () {
      final urgent = alarm('R1', urgent: true);
      final out = planNotifications(
        alarms: [urgent, alarm('R2')],
        now: now,
        privacyMode: false,
        alarmKitReminderIds: {urgent.reminderId},
      );
      expect(out, hasLength(1)); // only the non-urgent reminder survives
      expect(out.single.urgent, isFalse);
    });

    test('without the set, urgent still produces its notification chain', () {
      final out = planNotifications(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
      );
      expect(out, hasLength(ReminderProfile.factory.offsets.length));
    });
  });
}
