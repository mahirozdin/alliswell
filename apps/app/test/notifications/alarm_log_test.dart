import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/scheduler.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../support/fake_notifications.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm({
  String id = 'R1',
  bool urgent = false,
  bool requiresAck = false,
  String kind = 'remind',
  String status = 'scheduled',
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: 'Görev',
  kind: kind,
  remindAt: now.add(const Duration(hours: 1)),
  status: status,
  urgent: urgent,
  requiresAcknowledgement: requiresAck,
  snoozedUntil: snoozedUntil,
);

/// OPH-176 — the loudness contract and the alarm log (DESIGN §11 A6,
/// NOTIFICATIONS §2/§6). Round 9 was diagnosed from memory and could not be
/// settled; these are the two things that make the next report conclusive.
void main() {
  group('the loudness contract', () {
    test('an urgent alarm always asks for the alarm bed', () {
      final d = awDeliveryFor(urgent: true, criticalEnabled: false);
      expect(d.sound, kAwAlarmSoundName);
      expect(d.level, 'timeSensitive');
    });

    test('critical is upgraded ONLY when the grant is real', () {
      expect(
        awDeliveryFor(urgent: true, criticalEnabled: true).level,
        'critical',
      );
      // Never sent blind: an unentitled critical payload can lose the sound
      // outright (NOTIFICATIONS §2).
      expect(
        awDeliveryFor(urgent: true, criticalEnabled: false).level,
        'timeSensitive',
      );
    });

    test('a normal reminder takes the OS sound', () {
      final d = awDeliveryFor(urgent: false, criticalEnabled: true);
      expect(d.sound, kOsDefaultSoundName);
      expect(d.level, 'timeSensitive');
    });

    test('EVERY slot of a chain is urgent — there is no quiet first slot', () {
      final plan = planNotifications(
        alarms: [alarm(urgent: true, requiresAck: true)],
        now: now,
        privacyMode: false,
      );
      expect(plan, hasLength(kUrgentChainOffsets.length));
      expect(plan.every((n) => n.urgent), isTrue);
      // …so every slot resolves to the same delivery.
      final deliveries = plan
          .map((n) => awDeliveryFor(urgent: n.urgent, criticalEnabled: false))
          .map((d) => '${d.sound}/${d.level}')
          .toSet();
      expect(deliveries, {'$kAwAlarmSoundName/timeSensitive'});
    });

    test('a post-snooze ring is as loud, and says it is a snooze round', () {
      final plan = planNotifications(
        alarms: [
          alarm(
            urgent: true,
            requiresAck: true,
            status: 'snoozed',
            snoozedUntil: now.add(const Duration(minutes: 5)),
          ),
        ],
        now: now,
        privacyMode: false,
      );
      expect(plan.every((n) => n.urgent), isTrue);
      // Round 9 #6.6: it used to read "still waiting for acknowledgement",
      // which the user reasonably called "the 1st notification again".
      expect(plan.first.body, contains('Snoozed round'));
      expect(plan.first.body, isNot(contains('Urgent reminder')));
    });
  });

  group('AlarmLog', () {
    late AwDatabase db;
    late AlarmLog log;

    setUp(() {
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      log = AlarmLog(db);
    });

    tearDown(() => db.close());

    test('records an event and reads it back newest-first', () async {
      await log.record(
        event: AlarmLogEvent.scheduled,
        lane: AlarmLogLane.notification,
        at: now,
        urgent: true,
        sound: kAwAlarmSoundName,
        level: 'timeSensitive',
        slotIndex: 0,
        kind: 'due',
      );
      await log.record(
        event: AlarmLogEvent.ringShown,
        lane: AlarmLogLane.inapp,
        at: now.add(const Duration(minutes: 1)),
      );

      final rows = await log.recent();
      expect(rows.map((r) => r.event), [
        AlarmLogEvent.ringShown,
        AlarmLogEvent.scheduled,
      ]);
      final line = formatAlarmLogLine(rows.last);
      expect(line, contains('sound=$kAwAlarmSoundName'));
      expect(line, contains('level=timeSensitive'));
      expect(line, contains('slot 0'));
      expect(line, contains('due'));
    });

    test('is a ring buffer: the oldest rows fall out', () async {
      for (var i = 0; i < kAlarmLogLimit + 25; i++) {
        await log.record(
          event: AlarmLogEvent.scheduled,
          lane: AlarmLogLane.notification,
          at: now.add(Duration(minutes: i)),
        );
      }
      final rows = await log.recent(limit: kAlarmLogLimit * 2);
      expect(rows.length, lessThanOrEqualTo(kAlarmLogLimit));
      // The newest survived.
      expect(rows.first.at, now.add(Duration(minutes: kAlarmLogLimit + 24)));
    });

    test('a broken log never breaks the caller', () async {
      await db.close(); // every write from here on throws
      await expectLater(
        log.record(
          event: AlarmLogEvent.scheduled,
          lane: AlarmLogLane.notification,
        ),
        completes,
      );
    });
  });

  group('the scheduler writes what it did', () {
    late FakeNotificationsGateway gateway;
    late StreamController<List<AlarmInput>> alarms;
    late AwDatabase db;
    late AlarmLog log;
    late NotificationScheduler scheduler;

    setUp(() {
      gateway = FakeNotificationsGateway();
      alarms = StreamController<List<AlarmInput>>();
      db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      log = AlarmLog(db);
      scheduler = NotificationScheduler(
        gateway: gateway,
        alarms: alarms.stream,
        privacyMode: false,
        log: log,
        clock: () => now,
      );
    });

    tearDown(() async {
      scheduler.dispose();
      await alarms.close();
      await db.close();
    });

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('every scheduled slot lands in the log with its loudness', () async {
      await scheduler.start();
      alarms.add([
        alarm(id: 'R1', urgent: true, requiresAck: true, kind: 'due'),
      ]);
      await pump();
      await pump();

      final rows = await log.recent();
      final scheduled = rows
          .where((r) => r.event == AlarmLogEvent.scheduled)
          .toList();
      expect(scheduled, hasLength(kUrgentChainOffsets.length));
      expect(scheduled.every((r) => r.urgent), isTrue);
      expect(scheduled.every((r) => r.sound == kAwAlarmSoundName), isTrue);
      expect(
        scheduled.every((r) => r.lane == AlarmLogLane.notification),
        isTrue,
      );
      expect(scheduled.every((r) => r.kind == 'due'), isTrue);
      // Which slot each one was — the question round 9 could not answer.
      expect(scheduled.map((r) => r.slotIndex).toSet(), {
        for (var i = 0; i < kUrgentChainOffsets.length; i++) i,
      });
    });

    test('withdrawing an alarm is logged too', () async {
      await scheduler.start();
      alarms.add([alarm(id: 'R1', urgent: true, requiresAck: true)]);
      await pump();
      await pump();
      // The alarm leaves the feed (acknowledged / completed elsewhere).
      alarms.add([]);
      await pump();
      await pump();

      final cancelled = (await log.recent())
          .where((r) => r.event == AlarmLogEvent.cancelled)
          .toList();
      expect(cancelled, isNotEmpty);
      expect(cancelled.first.lane, AlarmLogLane.notification);
    });
  });
}
