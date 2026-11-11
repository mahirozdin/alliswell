import 'dart:async';

// `show` on purpose: drift exports its own `isNotNull` expression builder,
// which would shadow the matcher of the same name.
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';
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

  // OPH-277: the rehearsal is not in the plan, so the set-diff would cancel it
  // — during the 15 seconds it is waiting to prove something.
  test('a test alarm survives the next planning pass', () async {
    await scheduler.start();
    await gateway.scheduleTestAlarm(
      title: 'test',
      body: 'test',
      after: kAlarmTestDelay,
    );
    expect(gateway.scheduled.containsKey(kAlarmTestNotificationId), isTrue);

    // Anything at all makes the scheduler re-plan.
    alarms.add([alarm('R1')]);
    await pump();

    expect(gateway.cancelled, isNot(contains(kAlarmTestNotificationId)));
    expect(gateway.scheduled.containsKey(kAlarmTestNotificationId), isTrue);
  });

  // ── OPH-393: the strip waits for the prompt (U-05, ios/05) ──────────────
  group('says when it is asking for permission', () {
    test('brackets the OS prompt, and only the prompt', () async {
      final asks = <bool>[];
      final asking = _AskingGateway();
      final s = NotificationScheduler(
        gateway: asking,
        // The group's own stream: `tearDown` closes it, which waits for a
        // listener on a single-subscription controller.
        alarms: alarms.stream,
        privacyMode: false,
        clock: () => now,
        onPermissionAsk: asks.add,
      );
      addTearDown(s.dispose);
      await s.start();
      expect(asks, [true, false]);
      expect(asking.requested, 1);
    });

    test('a prompt that throws still ends the ask', () async {
      final asks = <bool>[];
      final s = NotificationScheduler(
        gateway: _AskingGateway(fail: true),
        // The group's own stream: `tearDown` closes it, which waits for a
        // listener on a single-subscription controller.
        alarms: alarms.stream,
        privacyMode: false,
        clock: () => now,
        onPermissionAsk: asks.add,
      );
      addTearDown(s.dispose);
      await s.start();
      expect(asks, [true, false], reason: 'a stuck "asking" hides the strip');
    });
  });

  // ── #49: the AlarmKit pass works on occurrences (NOTIFICATIONS §2b.3) ─────
  group('AlarmKit occurrence pass (OPH-426)', () {
    late FakeAlarmKitHost alarmKit;
    late DateTime clock;
    late Set<String> receipts;
    late int drains;
    void Function()? onDrain;

    NotificationScheduler build() => NotificationScheduler(
      gateway: gateway,
      alarmKit: alarmKit,
      alarms: alarms.stream,
      privacyMode: false,
      clock: () => clock,
      drainActions: () async {
        drains += 1;
        onDrain?.call();
      },
      appliedEventIds: () async => {...receipts},
    );

    setUp(() {
      alarmKit = FakeAlarmKitHost();
      clock = now;
      receipts = {};
      drains = 0;
      onDrain = null;
    });

    AlarmInput urgent({
      String taskId = 'TASK1',
      String reminderId = 'REM1',
      String title = 'Görev',
      required DateTime at,
      String status = 'scheduled',
      DateTime? snoozedUntil,
      int snoozeRound = 0,
    }) => AlarmInput(
      reminderId: reminderId,
      taskId: taskId,
      taskTitle: title,
      remindAt: at,
      status: status,
      urgent: true,
      requiresAcknowledgement: true,
      snoozeRound: snoozeRound,
      snoozedUntil: snoozedUntil,
    );

    /// The alarm the planner would build for [input] — what a native snooze
    /// computes for itself byte for byte (same id, same fingerprint).
    AlarmKitAlarm planned(AlarmInput input) => planAlarmKitAlarms(
      alarms: [input],
      now: DateTime.utc(2000),
      privacyMode: false,
    ).single;

    int fireAtMs(DateTime t) => t.millisecondsSinceEpoch;

    test(
      'moving an urgent task from 09:00 to 10:00 replaces its AlarmKit alarm and leaves nothing at 09:00',
      () async {
        final nine = DateTime.utc(2026, 7, 15, 9);
        clock = DateTime.utc(2026, 7, 15, 8);
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        alarms.add([urgent(at: nine, snoozeRound: 2)]);
        await pump();
        final oldId = alarmKit.scheduled.keys.single;

        // The server rebuilds the row on a new remind_at with snooze_count 0.
        alarms.add([urgent(at: nine.add(const Duration(hours: 1)))]);
        await pump();

        expect(alarmKit.cancelled, [oldId]);
        expect(alarmKit.scheduled, hasLength(1));
        expect(
          alarmKit.scheduled.values.single.fireAt,
          nine.add(const Duration(hours: 1)),
        );
        expect(
          alarmKit.scheduled.values.where((a) => a.fireAt == nine),
          isEmpty,
        );
        expect(gateway.scheduled, isEmpty, reason: 'one lane, one ring');
      },
    );

    test(
      'two native snoozes in a row converge to the second alarm only',
      () async {
        // A rang at 11:59; Ertele → B (12:04, e1); B rang; Ertele → C (12:09,
        // e2). Each native snooze stopped the one before it. Dart was not
        // running, so the model still says 11:59.
        final a = DateTime.utc(2026, 7, 15, 11, 59);
        final c = DateTime.utc(2026, 7, 15, 12, 9);
        clock = DateTime.utc(2026, 7, 15, 12, 5);
        final after = urgent(
          at: a,
          status: 'snoozed',
          snoozedUntil: c,
          snoozeRound: 2,
        );
        final native = planned(after);
        alarmKit.foreign[native.id] = AlarmKitScheduled(
          id: native.id,
          fp: native.fp,
          members: native.members,
          fireAtMs: fireAtMs(c),
          origin: 'native',
          eventId: 'e2',
        );
        onDrain = () => receipts.addAll(['e1', 'e2']);
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        // Pass 1: the drain applies e1 and e2, but the replica has not emitted
        // the snooze yet — the plan still sees 11:59.
        alarms.add([urgent(at: a, status: 'delivered')]);
        await pump();
        expect(drains, greaterThan(0));
        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.stopped, isEmpty);
        expect(
          gateway.scheduled,
          isEmpty,
          reason: 'the 11:59 chain must not ring over the native snooze',
        );

        // Pass 2: the write lands in the replica.
        alarms.add([after]);
        await pump();

        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.stopped, isEmpty);
        expect(alarmKit.scheduled, isEmpty, reason: 'no duplicate of C');
        final rows = await alarmKit.scheduledAlarms();
        expect(rows.map((r) => r.fireAtMs), [fireAtMs(c)]);
        expect(gateway.scheduled, isEmpty);
      },
    );

    test(
      'a native alarm whose event is not yet applied survives a plan pass',
      () async {
        clock = DateTime.utc(2026, 7, 15, 12, 5);
        final c = DateTime.utc(2026, 7, 15, 12, 30);
        final native = planned(
          urgent(at: c, status: 'snoozed', snoozedUntil: c, snoozeRound: 1),
        );
        alarmKit.foreign[native.id] = AlarmKitScheduled(
          id: native.id,
          fp: native.fp,
          members: native.members,
          fireAtMs: fireAtMs(c),
          origin: 'native',
          eventId: 'e9',
        );
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        // The model does not know about the snooze (nothing active for it).
        alarms.add(const []);
        await pump();
        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.stopped, isEmpty);
        expect(alarmKit.foreign, contains(native.id));

        // Once its event has a receipt, an alarm the model does not want goes.
        receipts.add('e9');
        alarms.add(const []);
        await pump();
        expect(alarmKit.cancelled, [native.id]);
        expect(alarmKit.stopped, isEmpty);
      },
    );

    test(
      'a ringing native snooze survives the pass whose drain applies its event',
      () async {
        // A rang at 11:59; Ertele → B (12:04, e1). The app opens at 12:04:30
        // while B rings. The drain applies e1, but the replica has not emitted
        // yet, so the plan still sees 11:59 delivered.
        final a = DateTime.utc(2026, 7, 15, 11, 59);
        final b = DateTime.utc(2026, 7, 15, 12, 4);
        clock = DateTime.utc(2026, 7, 15, 12, 4, 30);
        final after = urgent(
          at: a,
          status: 'snoozed',
          snoozedUntil: b,
          snoozeRound: 1,
        );
        final native = planned(after);
        alarmKit.foreign[native.id] = AlarmKitScheduled(
          id: native.id,
          fp: native.fp,
          state: AlarmKitAlarmState.alerting,
          members: native.members,
          fireAtMs: fireAtMs(b),
          origin: 'native',
          eventId: 'e1',
        );
        onDrain = () => receipts.add('e1');
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        alarms.add([urgent(at: a, status: 'delivered')]);
        await pump();
        expect(drains, greaterThan(0));
        expect(
          alarmKit.stopped,
          isEmpty,
          reason: 'the snoozed ring is current',
        );
        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.foreign, contains(native.id));
        expect(gateway.scheduled, isEmpty);

        // The write lands in the replica: the occurrence is B, still current.
        alarms.add([after]);
        await pump();
        expect(alarmKit.stopped, isEmpty);
        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.scheduled, isEmpty, reason: 'no duplicate of B');
        expect(alarmKit.foreign, contains(native.id));
        expect(gateway.scheduled, isEmpty);
      },
    );

    test(
      'a synthetic alarm keeps its AlarmKit id when its reminder row syncs down',
      () async {
        final at = now.add(const Duration(hours: 1));
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        alarms.add([urgent(reminderId: 'syn:remind:TASK1', at: at)]);
        await pump();
        final id = alarmKit.scheduled.keys.single;

        alarms.add([urgent(reminderId: '01JREALROW0000000000000000', at: at)]);
        await pump();

        expect(alarmKit.scheduled.keys, [id]);
        expect(alarmKit.cancelled, isEmpty);
        expect(
          gateway.scheduled,
          isEmpty,
          reason: 'the real row is covered by the alarm already on the lane',
        );
      },
    );

    test(
      'a renamed task is rescheduled under the same id with the new fingerprint',
      () async {
        final at = now.add(const Duration(hours: 1));
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();

        alarms.add([urgent(title: 'Eski ad', at: at)]);
        await pump();
        final before = alarmKit.scheduled.values.single;

        alarms.add([urgent(title: 'Yeni ad', at: at)]);
        await pump();
        final after = alarmKit.scheduled.values.single;

        expect(after.id, before.id);
        expect(after.fp, isNot(before.fp));
        expect(after.title, 'Yeni ad');
        expect(alarmKit.cancelled, [before.id]);
        expect(gateway.scheduled, isEmpty);
      },
    );

    test(
      'an alerting alarm whose occurrence another device snoozed is stopped and the new time is scheduled',
      () async {
        final noon = DateTime.utc(2026, 7, 15, 12);
        clock = DateTime.utc(2026, 7, 15, 11, 50);
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();
        alarms.add([urgent(at: noon)]);
        await pump();
        final ringing = alarmKit.scheduled.keys.single;

        clock = DateTime.utc(2026, 7, 15, 12, 1);
        alarmKit.alerting.add(ringing);
        final later = DateTime.utc(2026, 7, 15, 12, 30);
        alarms.add([urgent(at: noon, status: 'snoozed', snoozedUntil: later)]);
        await pump();

        expect(alarmKit.stopped, [ringing]);
        expect(alarmKit.cancelled, isNot(contains(ringing)));
        expect(alarmKit.scheduled.values.single.fireAt, later);
        expect(gateway.scheduled, isEmpty);
      },
    );

    test(
      'an alerting alarm whose occurrence is still current is never stopped or cancelled',
      () async {
        final noon = DateTime.utc(2026, 7, 15, 12);
        clock = DateTime.utc(2026, 7, 15, 11, 50);
        final scheduler = build();
        addTearDown(scheduler.dispose);
        await scheduler.start();
        alarms.add([urgent(at: noon)]);
        await pump();
        final ringing = alarmKit.scheduled.keys.single;

        // It rings; the instant is now in the past, so it is no longer in the
        // plan's future window — and that must not read as "not wanted".
        clock = DateTime.utc(2026, 7, 15, 12, 3);
        alarmKit.alerting.add(ringing);
        alarms.add([
          urgent(at: noon, status: 'delivered'),
          urgent(
            taskId: 'OTHER',
            reminderId: 'REM2',
            at: noon.add(const Duration(hours: 2)),
          ),
        ]);
        await pump();

        expect(alarmKit.stopped, isEmpty);
        expect(alarmKit.cancelled, isEmpty);
        expect(alarmKit.scheduled, contains(ringing));
        expect(
          gateway.scheduled,
          isEmpty,
          reason: 'the ringing alarm covers its reminder; no chain behind it',
        );
      },
    );

    test('an acknowledged occurrence stops its alerting alarm', () async {
      final noon = DateTime.utc(2026, 7, 15, 12);
      clock = DateTime.utc(2026, 7, 15, 11, 50);
      final scheduler = build();
      addTearDown(scheduler.dispose);
      await scheduler.start();
      alarms.add([urgent(at: noon)]);
      await pump();
      final ringing = alarmKit.scheduled.keys.single;

      clock = DateTime.utc(2026, 7, 15, 12, 1);
      alarmKit.alerting.add(ringing);
      alarms.add(const []); // acknowledged: the row leaves the active set
      await pump();

      expect(alarmKit.stopped, [ringing]);
      expect(alarmKit.cancelled, isEmpty);
    });

    test('every pass drains the pulled actions before it plans', () async {
      // The drain lands a snooze in the lane's ledger; the plan that follows
      // must see it, so the drain has to come first.
      final at = now.add(const Duration(hours: 1));
      final native = planned(urgent(at: at));
      onDrain = () => alarmKit.foreign[native.id] = AlarmKitScheduled(
        id: native.id,
        fp: native.fp,
        members: native.members,
        fireAtMs: fireAtMs(at),
      );
      final scheduler = build();
      addTearDown(scheduler.dispose);
      await scheduler.start();
      alarms.add([urgent(at: at)]);
      await pump();
      expect(drains, 1);
      expect(alarmKit.scheduled, isEmpty, reason: 'already on the lane');
      expect(alarmKit.cancelled, isEmpty);
    });
  });

  group('planAlarmKitPass (OPH-426)', () {
    final noon = DateTime.utc(2026, 7, 15, 12);
    const stale = Duration(minutes: 15);

    // Pure: no scheduler subscribes, and the shared tearDown's close() waits
    // for a listener.
    setUp(() => alarms.stream.listen(null));

    AlarmInput row(DateTime at, {String status = 'delivered'}) => AlarmInput(
      reminderId: 'REM1',
      taskId: 'TASK1',
      taskTitle: 'Görev',
      remindAt: at,
      status: status,
      urgent: true,
      requiresAcknowledgement: true,
    );

    AlarmKitScheduled alerting(
      DateTime at, {
      List<String> members = const ['TASK1'],
    }) => AlarmKitScheduled(
      id: 42,
      fp: 7,
      state: AlarmKitAlarmState.alerting,
      members: members,
      fireAtMs: at.millisecondsSinceEpoch,
    );

    test('a current alerting alarm past the stale window is stopped', () {
      final plan = planAlarmKitPass(
        desired: const [],
        current: [alerting(noon)],
        alarms: [row(noon)],
        appliedEventIds: const {},
        now: noon.add(stale + const Duration(seconds: 1)),
        staleWindow: stale,
      );
      expect(plan.toStop.map((r) => r.id), [42]);
      expect(plan.toCancel, isEmpty);
    });

    test(
      'an alerting alarm with no ledger record waits for the stale window',
      () {
        AlarmKitPassPlan at(Duration after) => planAlarmKitPass(
          desired: const [],
          current: [alerting(noon, members: const [])],
          alarms: const [],
          appliedEventIds: const {},
          now: noon.add(after),
          staleWindow: stale,
        );
        final early = at(const Duration(minutes: 5));
        expect(early.toStop, isEmpty);
        expect(early.toCancel, isEmpty);
        expect(at(stale + const Duration(minutes: 1)).toStop.map((r) => r.id), [
          42,
        ]);
      },
    );

    test(
      'an alerting native alarm whose event has no receipt is kept until the stale window',
      () {
        final b = noon.add(const Duration(minutes: 4));
        AlarmKitPassPlan at(Duration after, {Set<String> applied = const {}}) =>
            planAlarmKitPass(
              desired: const [],
              current: [
                AlarmKitScheduled(
                  id: 42,
                  fp: 7,
                  state: AlarmKitAlarmState.alerting,
                  members: const ['TASK1'],
                  fireAtMs: b.millisecondsSinceEpoch,
                  origin: 'native',
                  eventId: 'e1',
                ),
              ],
              // The model still says the pre-snooze 12:00.
              alarms: [row(noon)],
              appliedEventIds: applied,
              now: b.add(after),
              staleWindow: stale,
            );
        final early = at(const Duration(seconds: 30));
        expect(early.toStop, isEmpty);
        expect(early.toCancel, isEmpty);
        expect(early.held, contains('REM1'));
        expect(at(stale + const Duration(seconds: 1)).toStop.map((r) => r.id), [
          42,
        ]);
        // Once applied, a model that disagrees supersedes it.
        expect(
          at(
            const Duration(seconds: 30),
            applied: const {'e1'},
          ).toStop.map((r) => r.id),
          [42],
        );
      },
    );

    test('a ledger-less scheduled row is never rescheduled for its fp', () {
      final alarm = planAlarmKitAlarms(
        alarms: [row(noon, status: 'scheduled')],
        now: noon.subtract(const Duration(hours: 1)),
        privacyMode: false,
      ).single;
      final plan = planAlarmKitPass(
        desired: [alarm],
        current: [AlarmKitScheduled(id: alarm.id)],
        alarms: [row(noon, status: 'scheduled')],
        appliedEventIds: const {},
        now: noon.subtract(const Duration(hours: 1)),
        staleWindow: stale,
      );
      expect(plan.toReschedule, isEmpty);
      expect(plan.toSchedule, isEmpty);
      expect(plan.toCancel, isEmpty);
    });
  });
}

class _AskingGateway extends FakeNotificationsGateway {
  _AskingGateway({this.fail = false});

  final bool fail;
  int requested = 0;

  @override
  Future<bool> requestPermissions() async {
    requested += 1;
    if (fail) throw StateError('no platform');
    return true;
  }
}
