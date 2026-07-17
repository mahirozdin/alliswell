import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/planner.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm({
  String id = 'R1',
  String status = 'scheduled',
  bool urgent = false,
  bool requiresAck = false,
  DateTime? remindAt,
  DateTime? snoozedUntil,
  String title = 'Görev',
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: title,
  remindAt: remindAt ?? now.add(const Duration(hours: 1)),
  status: status,
  urgent: urgent,
  requiresAcknowledgement: requiresAck,
  snoozedUntil: snoozedUntil,
);

void main() {
  test('a normal reminder plans exactly one exact notification', () {
    final plan = planNotifications(
      alarms: [alarm(title: 'Süt al')],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(1));
    expect(plan.single.title, 'Süt al');
    expect(plan.single.urgent, isFalse);
    expect(plan.single.fireAt, now.add(const Duration(hours: 1)));
    expect(plan.single.payload, contains('"chainIndex":0'));
  });

  test('urgent+ack reminders pre-schedule the full re-alert chain', () {
    final plan = planNotifications(
      alarms: [alarm(urgent: true, requiresAck: true)],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(kUrgentChainOffsets.length));
    final base = now.add(const Duration(hours: 1));
    expect(plan.map((n) => n.fireAt), [
      for (final offset in kUrgentChainOffsets) base.add(offset),
    ]);
    expect(plan.first.body, contains('waiting for acknowledgement'));
    expect(plan.last.body, contains('alert 5'));
    // Urgent WITHOUT ack requirement rings once.
    expect(
      planNotifications(
        alarms: [alarm(urgent: true)],
        now: now,
        privacyMode: false,
      ),
      hasLength(1),
    );
  });

  test('snoozed alarms fire at snoozedUntil; past instants are skipped', () {
    final plan = planNotifications(
      alarms: [
        alarm(
          id: 'R1',
          status: 'snoozed',
          remindAt: now.subtract(const Duration(hours: 2)),
          snoozedUntil: now.add(const Duration(minutes: 30)),
        ),
        alarm(id: 'R2', remindAt: now.subtract(const Duration(minutes: 1))),
        alarm(id: 'R3', status: 'acknowledged'),
        alarm(id: 'R4', status: 'cancelled'),
      ],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(1));
    expect(plan.single.fireAt, now.add(const Duration(minutes: 30)));
  });

  test('windows to the soonest maxPending fire-times (iOS 64 cap)', () {
    final plan = planNotifications(
      alarms: [
        for (var i = 0; i < 60; i++)
          alarm(
            id: 'R$i',
            remindAt: now.add(Duration(minutes: 10 + i)),
          ),
      ],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(40));
    expect(plan.first.fireAt, now.add(const Duration(minutes: 10)));
    expect(plan.last.fireAt, now.add(const Duration(minutes: 49)));
  });

  test('privacy mode hides task titles everywhere (OPH-064)', () {
    final plan = planNotifications(
      alarms: [alarm(title: 'Çok gizli iş', urgent: true, requiresAck: true)],
      now: now,
      privacyMode: true,
    );
    for (final n in plan) {
      expect(n.title, 'AllisWell');
      expect(n.body, 'You have a reminder');
      expect(n.title.contains('gizli'), isFalse);
      // The payload still routes taps by id — content stays off the lock screen.
      expect(n.payload, isNot(contains('gizli')));
    }
  });

  test('ids are stable for identical input and change with content', () {
    List<int> ids(bool privacy) => planNotifications(
      alarms: [alarm()],
      now: now,
      privacyMode: privacy,
    ).map((n) => n.id).toList();
    expect(ids(false), ids(false)); // deterministic
    expect(ids(false), isNot(ids(true))); // content change → new identity
  });
}
