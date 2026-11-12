import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/gateway_local.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/scheduler.dart';

/// OPH-445 (#48 gap A): a delivered urgent notification on Android loops its
/// sound (FLAG_INSISTENT) until it is cancelled. The scheduler's set-diff only
/// sees PENDING requests, so an alarm acknowledged or snoozed on another
/// device stopped its future slots and kept ringing the one on screen.
final now = DateTime.utc(2030, 6, 1, 12);
const window = Duration(minutes: 30);

AlarmInput alarm(
  String rid, {
  Duration ago = const Duration(minutes: 1),
  String status = 'delivered',
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: rid,
  taskId: 'T-$rid',
  taskTitle: 'Task $rid',
  remindAt: now.subtract(ago),
  status: status,
  urgent: true,
  requiresAcknowledgement: true,
  snoozedUntil: snoozedUntil,
);

ActiveAlarmNotification shown(int id, String rid, {bool urgent = true}) =>
    ActiveAlarmNotification(id: id, urgent: urgent, reminderIds: [rid]);

void main() {
  group('activeToCancel (pure)', () {
    test(
      'cancels the delivered urgent notification of a reminder acknowledged elsewhere',
      () {
        // R1 was acknowledged on the other device: the sync dropped it from the
        // active set, so the model no longer has it at all.
        expect(activeToCancel([shown(11, 'R1')], const [], now, window), {11});

        // A remote snooze moves the occurrence: the old one is no longer ringing.
        final snoozed = alarm(
          'R2',
          status: 'snoozed',
          snoozedUntil: now.add(const Duration(minutes: 10)),
        );
        expect(activeToCancel([shown(12, 'R2')], [snoozed], now, window), {12});
      },
    );

    test(
      'leaves the delivered notification of a still ringing reminder alone',
      () {
        final ringing = alarm('R1');
        expect(
          activeToCancel([shown(11, 'R1')], [ringing], now, window),
          isEmpty,
        );

        // A grouped minute keeps ringing while any member still rings.
        const group = ActiveAlarmNotification(
          id: 13,
          urgent: true,
          reminderIds: ['R1', 'R9'],
        );
        expect(activeToCancel([group], [ringing], now, window), isEmpty);
      },
    );

    test('ignores delivered notifications it cannot map to a reminder', () {
      expect(
        activeToCancel(
          [
            // A row the gateway could not tie to a reminder.
            const ActiveAlarmNotification(id: 21, urgent: true),
            // The rehearsal alarm is a diagnostic, not a reminder.
            const ActiveAlarmNotification(
              id: kAlarmTestNotificationId,
              urgent: true,
              reminderIds: ['R1'],
            ),
            // A normal reminder does not loop; it stays in the tray.
            shown(22, 'R1', urgent: false),
          ],
          const [],
          now,
          window,
        ),
        isEmpty,
      );
    });

    test('is idempotent across two passes', () {
      final active = [shown(11, 'R1'), shown(12, 'R2')];
      final alarms = [alarm('R2')];
      final first = activeToCancel(active, alarms, now, window);
      expect(first, {11});
      // The OS removed what was cancelled; the second pass finds nothing new.
      final left = active.where((n) => !first.contains(n.id)).toList();
      expect(activeToCancel(left, alarms, now, window), isEmpty);
    });
  });

  group('payload mapping', () {
    test('a planned payload names its reminders and tasks', () {
      final single = ActiveAlarmNotification.fromPayload(
        id: 1,
        urgent: true,
        payload: jsonEncode({'taskId': 'T1', 'reminderId': 'R1'}),
      );
      expect(single.reminderIds, ['R1']);
      expect(single.taskIds, ['T1']);

      final group = ActiveAlarmNotification.fromPayload(
        id: 2,
        urgent: true,
        payload: jsonEncode({
          'taskId': 'T1',
          'taskIds': ['T1', 'T2'],
          'reminderIds': ['R1', 'R2'],
        }),
      );
      expect(group.reminderIds, ['R1', 'R2']);
      expect(group.taskIds, ['T1', 'T2']);

      for (final payload in [null, '', 'not json', '[1]', '{"test":true}']) {
        expect(
          ActiveAlarmNotification.fromPayload(
            id: 3,
            urgent: true,
            payload: payload,
          ).reminderIds,
          isEmpty,
        );
      }
    });

    test(
      'Android omits the payload of a shown notification, the stored one maps it',
      () {
        final stored = rememberUrgentPayload(
          null,
          id: 7,
          payload: jsonEncode({'reminderId': 'R1'}),
          fireAt: now,
          now: now,
        );
        final active = activeAlarmsFrom([
          const ActiveNotification(id: 7, channelId: 'urgent_alarms_v2_aw'),
          const ActiveNotification(id: 8, channelId: 'reminders_default'),
          const ActiveNotification(id: 9, channelId: 'urgent_alarms_v2_aw'),
        ], readUrgentPayloads(stored));

        expect(active.map((n) => n.id), [7, 8, 9]);
        expect(active[0].urgent, isTrue);
        expect(active[0].reminderIds, ['R1']);
        expect(active[1].urgent, isFalse);
        // Scheduled before the record existed: nothing to map it with.
        expect(active[2].reminderIds, isEmpty);
      },
    );

    test('the stored record forgets old entries and survives junk', () {
      var json = rememberUrgentPayload(
        'not json',
        id: 1,
        payload: '{"reminderId":"R1"}',
        fireAt: now.subtract(const Duration(days: 3)),
        now: now,
      );
      json = rememberUrgentPayload(
        json,
        id: 2,
        payload: '{"reminderId":"R2"}',
        fireAt: now,
        now: now,
      );
      expect(readUrgentPayloads(json).keys, [2]);
      expect(readUrgentPayloads(null), isEmpty);
      expect(readUrgentPayloads('{"x":1}'), isEmpty);
    });
  });
}
