import 'dart:async';

// `show` on purpose: drift exports its own `isNotNull` expression builder,
// which would shadow the matcher of the same name.
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/notifications/scheduler.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../support/fake_notifications.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm(
  String id, {
  bool urgent = false,
  String title = 'Görev',
  Duration after = const Duration(hours: 1),
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: title,
  remindAt: now.add(after),
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
    expect(
      gateway.scheduled,
      hasLength(1 + ReminderProfile.factory.offsets.length),
    );

    // The urgent alarm gets acknowledged → its rows leave the active set →
    // the whole chain is cancelled, the normal reminder stays.
    alarms.add([alarm('R1')]);
    await pump();
    expect(gateway.scheduled, hasLength(1));
    expect(
      gateway.cancelled,
      hasLength(ReminderProfile.factory.offsets.length),
    );
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
        expect(
          gateway.scheduled,
          hasLength(ReminderProfile.factory.offsets.length),
        );
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
        expect(
          gateway.scheduled,
          hasLength(ReminderProfile.factory.offsets.length),
        );
        expect(alarmKit.scheduled, isEmpty);
      },
    );
  });

  group('AlarmKit lane limits and refusals (OPH-182)', () {
    late FakeAlarmKitHost alarmKit;
    late AwDatabase db;
    late AlarmLog log;

    NotificationScheduler build() => NotificationScheduler(
      gateway: gateway,
      alarmKit: alarmKit,
      alarms: alarms.stream,
      privacyMode: false,
      log: log,
      clock: () => now,
    );

    setUp(() {
      alarmKit = FakeAlarmKitHost();
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      log = AlarmLog(db);
    });

    tearDown(() => db.close());

    test('past the cap, urgent alarms keep the notification chain', () async {
      scheduler = build();
      await scheduler.start();

      alarms.add([
        for (var i = 0; i < kMaxAlarmKitAlarms + 2; i++)
          alarm('R$i', urgent: true, after: Duration(hours: i + 1)),
      ]);
      await pump();

      expect(alarmKit.scheduled, hasLength(kMaxAlarmKitAlarms));
      // The two that did not fit ring the OLD way rather than not at all.
      expect(
        gateway.scheduled,
        hasLength(2 * ReminderProfile.factory.offsets.length),
      );

      final rows = await log.recent();
      final overflow = rows.where(
        (e) =>
            e.lane == AlarmLogLane.alarmkit &&
            e.event == AlarmLogEvent.degraded &&
            (e.detail ?? '').contains('over-limit'),
      );
      expect(overflow, hasLength(2));
    });

    test('a refused alarm is logged as degraded, not as scheduled', () async {
      alarmKit.scheduleFailure = 'limit_reached';
      scheduler = build();
      await scheduler.start();

      alarms.add([alarm('R1', urgent: true)]);
      await pump();

      final rows = await log.recent();
      final akRows = rows.where((e) => e.lane == AlarmLogLane.alarmkit);
      expect(akRows, isNotEmpty);
      // The whole point of OPH-176's log: never claim a delivery the OS refused.
      expect(akRows.where((e) => e.event == AlarmLogEvent.scheduled), isEmpty);
      expect(
        akRows.singleWhere((e) => e.event == AlarmLogEvent.degraded).detail,
        // The detail now names the CONSEQUENCE as well as the cause, because
        // the consequence changed in round 19: the alarm keeps its chain.
        'limit_reached — notification chain keeps it',
      );
    });

    // ── Round 19 K1 — the report: "urgent alarms stopped ringing" ───────────
    //
    // The excluded set was computed from what we INTENDED to put on this lane,
    // so an alarm AlarmKit refused was scheduled on neither lane. The log said
    // `degraded` and nothing rang. These four pin the arbitration.
    test('a REFUSED alarm falls back to the notification chain', () async {
      alarmKit.scheduleFailure = 'limit_reached';
      scheduler = build();
      await scheduler.start();

      alarms.add([alarm('R1', urgent: true)]);
      await pump();

      expect(alarmKit.scheduled, isEmpty);
      expect(
        gateway.scheduled,
        hasLength(ReminderProfile.factory.offsets.length),
        reason: 'refused by AlarmKit → the notification chain must cover it',
      );
    });

    test('an ACCEPTED alarm is not also scheduled as notifications', () async {
      scheduler = build();
      await scheduler.start();

      alarms.add([alarm('R1', urgent: true)]);
      await pump();

      expect(alarmKit.scheduled, hasLength(1));
      expect(gateway.scheduled, isEmpty, reason: 'it would ring twice');
    });

    test(
      'authorization revoked mid-session returns the alarm to notifications',
      () async {
        scheduler = build();
        await scheduler.start();
        alarms.add([alarm('R1', urgent: true)]);
        await pump();
        expect(alarmKit.scheduled, hasLength(1));

        // The user turns it off in iOS Settings. Nothing tells the app; the next
        // apply has to notice by READING the grant (never by re-asking).
        alarmKit.authorized = false;
        alarms.add([alarm('R1', urgent: true), alarm('R2')]);
        await pump();

        expect(
          gateway.scheduled.values.where((n) => n.urgent),
          hasLength(ReminderProfile.factory.offsets.length),
        );
        expect(
          alarmKit.authorizationRequested,
          isTrue,
          reason: 'asked once at start…',
        );
      },
    );

    test(
      'an unreadable AlarmKit lane leaves every urgent alarm ringing',
      () async {
        // If we cannot say what this lane holds, we must not tell the other lane
        // to skip anything. Two quiet alarms is a worse failure than one loud one.
        alarmKit.scheduledIdsThrows = true;
        scheduler = build();
        await scheduler.start();

        alarms.add([alarm('R1', urgent: true)]);
        await pump();

        expect(
          gateway.scheduled,
          hasLength(ReminderProfile.factory.offsets.length),
        );
      },
    );

    // ── Round 19 K2 — one bad schedule used to abort the whole pass ─────────
    test('one failing schedule does not cancel the rest of the pass', () async {
      alarmKit = FakeAlarmKitHost(supported: false);
      gateway.failScheduleFor = (n) => n.reminderId == 'R2'.padRight(26, '0');
      scheduler = build();
      await scheduler.start();

      alarms.add([alarm('R1'), alarm('R2'), alarm('R3')]);
      await pump();

      expect(
        gateway.scheduled.values.map((n) => n.reminderId),
        containsAll(<String>['R1'.padRight(26, '0'), 'R3'.padRight(26, '0')]),
        reason: 'R2 threw; R1 and R3 must still be scheduled',
      );
      final rows = await log.recent();
      expect(
        rows.where(
          (e) =>
              e.event == AlarmLogEvent.degraded &&
              (e.detail ?? '').contains('schedule failed'),
        ),
        hasLength(1),
      );
    });

    test('the log records the sound the alarm actually carries', () async {
      scheduler = build();
      await scheduler.start();

      alarms.add([alarm('R1', urgent: true)]);
      await pump();

      final rows = await log.recent();
      final scheduled = rows.singleWhere(
        (e) =>
            e.lane == AlarmLogLane.alarmkit &&
            e.event == AlarmLogEvent.scheduled,
      );
      expect(scheduled.level, 'alarmkit');
      expect(scheduled.sound, isNotNull);
    });
  });

  // ── Round 19 / OPH-277 — "did it actually go off?" ────────────────────────
  //
  // iOS gives an app no delivery callback for a notification nobody tapped, so
  // this question has never been answerable and round 19's report could not be
  // investigated. It IS answerable indirectly: a request we scheduled and did
  // not cancel left the pending queue for exactly one of two reasons.
  group('delivery reconciliation', () {
    late FakeAlarmKitHost alarmKit;
    late AwDatabase db;
    late AlarmLog log;
    var clock = now;

    NotificationScheduler build() => NotificationScheduler(
      gateway: gateway,
      alarmKit: alarmKit,
      alarms: alarms.stream,
      privacyMode: false,
      log: log,
      clock: () => clock,
    );

    setUp(() {
      clock = now;
      alarmKit = FakeAlarmKitHost(supported: false);
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      log = AlarmLog(db);
    });

    tearDown(() => db.close());

    test(
      'a request that leaves the queue AFTER its time was delivered',
      () async {
        scheduler = build();
        await scheduler.start();
        alarms.add([alarm('R1', after: const Duration(minutes: 30))]);
        await pump();
        final id = gateway.scheduled.keys.single;

        // The OS presented it: it is gone from pending, and its instant passed.
        gateway.vanished.add(id);
        clock = now.add(const Duration(hours: 2));
        alarms.add([alarm('R1', after: const Duration(minutes: 30))]);
        await pump();

        final rows = await log.recent();
        expect(
          rows.where((e) => e.event == AlarmLogEvent.delivered),
          hasLength(1),
        );
        expect(rows.where((e) => e.event == AlarmLogEvent.dropped), isEmpty);
      },
    );

    test(
      'a request that vanishes BEFORE its time was dropped by the OS',
      () async {
        // iOS keeps only the 64 soonest pending requests and prunes the rest in
        // silence. This row is the first time the app can say that happened.
        scheduler = build();
        await scheduler.start();
        alarms.add([alarm('R1', after: const Duration(hours: 6))]);
        await pump();
        final id = gateway.scheduled.keys.single;

        gateway.vanished.add(id);
        alarms.add([alarm('R1', after: const Duration(hours: 6))]);
        await pump();

        final rows = await log.recent();
        expect(
          rows.where((e) => e.event == AlarmLogEvent.dropped),
          hasLength(1),
        );
      },
    );

    test('our own cancellation is not reported as a delivery', () async {
      scheduler = build();
      await scheduler.start();
      alarms.add([alarm('R1', after: const Duration(hours: 6))]);
      await pump();

      // The reminder leaves the active set — we cancel it ourselves.
      alarms.add(const []);
      await pump();

      final rows = await log.recent();
      expect(rows.where((e) => e.event == AlarmLogEvent.delivered), isEmpty);
      expect(rows.where((e) => e.event == AlarmLogEvent.dropped), isEmpty);
      expect(
        rows.where((e) => e.event == AlarmLogEvent.cancelled),
        hasLength(1),
      );
    });
  });

  // Round 19 K3: the window only ever moved when the replica emitted, so a
  // week with no task edits was a week with no re-fill.
  test('coming back to the foreground re-fills the window', () async {
    void Function()? resume;
    final scheduler = NotificationScheduler(
      gateway: gateway,
      alarms: alarms.stream,
      privacyMode: false,
      clock: () => now,
      onForeground: (callback) {
        resume = callback;
        return () => resume = null;
      },
    );
    addTearDown(scheduler.dispose);
    await scheduler.start();
    alarms.add([alarm('R1')]);
    await pump();

    // The OS quietly forgot it while the app was away.
    gateway.scheduled.clear();
    resume!();
    await pump();
    expect(gateway.scheduled, hasLength(1));
  });
}
