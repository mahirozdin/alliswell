import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/scheduler.dart';

import '../support/fake_notifications.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm(String id, {bool urgent = false, String title = 'Görev'}) =>
    AlarmInput(
      reminderId: id.padRight(26, '0'),
      taskId: 'T$id'.padRight(26, '0'),
      taskTitle: title,
      remindAt: now.add(const Duration(hours: 1)),
      status: 'scheduled',
      urgent: urgent,
      requiresAcknowledgement: urgent,
      snoozedUntil: null,
    );

void main() {
  late FakeNotificationsGateway gateway;
  late StreamController<List<AlarmInput>> alarms;
  late NotificationScheduler scheduler;

  setUp(() {
    gateway = FakeNotificationsGateway();
    alarms = StreamController<List<AlarmInput>>();
    scheduler = NotificationScheduler(
      gateway: gateway,
      alarms: alarms.stream,
      privacyMode: false,
      clock: () => now,
    );
  });

  tearDown(() async {
    scheduler.dispose();
    await alarms.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('schedules the plan, then cancels what disappears', () async {
    await scheduler.start();
    expect(gateway.permissionsRequested, isTrue);

    alarms.add([alarm('R1'), alarm('R2', urgent: true)]);
    await pump();
    // 1 normal + 5-slot urgent chain.
    expect(gateway.scheduled, hasLength(1 + kUrgentChainOffsets.length));

    // The urgent alarm gets acknowledged → its rows leave the active set →
    // the whole chain is cancelled, the normal reminder stays.
    alarms.add([alarm('R1')]);
    await pump();
    expect(gateway.scheduled, hasLength(1));
    expect(gateway.cancelled, hasLength(kUrgentChainOffsets.length));
  });

  test('content changes reschedule under a new identity', () async {
    await scheduler.start();
    alarms.add([alarm('R1', title: 'Eski ad')]);
    await pump();
    final oldId = gateway.scheduled.keys.single;

    alarms.add([alarm('R1', title: 'Yeni ad')]);
    await pump();
    final newId = gateway.scheduled.keys.single;
    expect(newId, isNot(oldId));
    expect(gateway.cancelled, contains(oldId));
    expect(gateway.scheduled[newId]!.title, 'Yeni ad');
  });

  test('an unchanged plan is a no-op (no cancel/schedule churn)', () async {
    await scheduler.start();
    alarms.add([alarm('R1')]);
    await pump();
    final schedulesBefore = gateway.scheduled.length;

    alarms.add([alarm('R1')]);
    await pump();
    expect(gateway.scheduled, hasLength(schedulesBefore));
    expect(gateway.cancelled, isEmpty);
  });

  group('AlarmKit lane (OPH-141)', () {
    late FakeAlarmKitHost alarmKit;

    NotificationScheduler build() => NotificationScheduler(
      gateway: gateway,
      alarmKit: alarmKit,
      alarms: alarms.stream,
      privacyMode: false,
      clock: () => now,
    );

    setUp(() => alarmKit = FakeAlarmKitHost());

    test(
      'urgent → AlarmKit (single alarm), non-urgent → notifications',
      () async {
        scheduler = build();
        await scheduler.start();
        expect(alarmKit.authorizationRequested, isTrue);

        alarms.add([alarm('R1'), alarm('R2', urgent: true)]);
        await pump();

        // Non-urgent stays a notification; urgent moves to AlarmKit as ONE alarm,
        // not the 5-slot notification chain.
        expect(gateway.scheduled, hasLength(1));
        expect(alarmKit.scheduled, hasLength(1));
        expect(alarmKit.scheduled.values.single.taskId, alarm('R2').taskId);
      },
    );

    test('acknowledge cancels the AlarmKit alarm via the set-diff', () async {
      scheduler = build();
      await scheduler.start();
      alarms.add([alarm('R2', urgent: true)]);
      await pump();
      final akId = alarmKit.scheduled.keys.single;

      // The urgent reminder leaves the active set → desired AlarmKit set is
      // empty → the alarm is cancelled (same convergence as notifications).
      alarms.add(const []);
      await pump();
      expect(alarmKit.scheduled, isEmpty);
      expect(alarmKit.cancelled, contains(akId));
    });

    test(
      'unsupported AlarmKit → urgent stays the notification chain',
      () async {
        alarmKit = FakeAlarmKitHost(supported: false);
        scheduler = build();
        await scheduler.start();

        alarms.add([alarm('R2', urgent: true)]);
        await pump();
        expect(gateway.scheduled, hasLength(kUrgentChainOffsets.length));
        expect(alarmKit.scheduled, isEmpty);
      },
    );

    test(
      'declined AlarmKit also falls back — urgent is never dropped',
      () async {
        alarmKit = FakeAlarmKitHost(authorized: false);
        scheduler = build();
        await scheduler.start();

        alarms.add([alarm('R2', urgent: true)]);
        await pump();
        expect(gateway.scheduled, hasLength(kUrgentChainOffsets.length));
        expect(alarmKit.scheduled, isEmpty);
      },
    );
  });
}
