import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// Feedback round 6: alarms must not wait for the server's reminder row.
/// `watchAlarms` merges real rows with task-derived synthetic alarms
/// (explicit remindAt, or urgent + dueAt — the server's effectiveRemindAt
/// rule), and the synthetic twin disappears the moment ANY row exists.
void main() {
  late AwDatabase db;
  late ReminderStore store;

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = ReminderStore(db, () {});
  });

  tearDown(() => db.close());

  Future<void> seedTask({
    String tid = 'T1',
    DateTime? remindAt,
    DateTime? dueAt,
    bool urgent = false,
    String status = 'open',
    DateTime? snoozedUntil,
    DateTime? alarmsMutedAt,
  }) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id(tid),
          workspaceId: ws,
          title: 'Görev $tid',
          status: Value(status),
          isUrgent: Value(urgent),
          requiresAcknowledgement: Value(urgent),
          remindAt: Value(remindAt),
          dueAt: Value(dueAt),
          snoozedUntil: Value(snoozedUntil),
          alarmsMutedAt: Value(alarmsMutedAt),
        ),
      );

  Future<void> seedReminder({
    String rid = 'R1',
    String tid = 'T1',
    required DateTime remindAt,
    String status = 'scheduled',
    String kind = 'remind',
  }) => db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          id: id(rid),
          taskId: id(tid),
          remindAt: remindAt,
          kind: Value(kind),
          status: Value(status),
          alarmLevel: const Value('urgent'),
          requiresAcknowledgement: const Value(true),
        ),
      );

  test(
    'a task with remindAt and no reminder row yields a synthetic alarm',
    () async {
      final at = DateTime.utc(2030, 6, 1, 9);
      await seedTask(remindAt: at);

      final alarms = await store.watchAlarms(ws).first;
      expect(alarms, hasLength(1));
      expect(alarms.single.reminderId, syntheticReminderId('remind', id('T1')));
      expect(alarms.single.remindAt, at);
      expect(alarms.single.status, 'scheduled');
      expect(alarms.single.urgent, isFalse);
    },
  );

  test(
    'an urgent task alarms at its deadline without any reminder row',
    () async {
      final due = DateTime.utc(2030, 6, 2, 14);
      await seedTask(dueAt: due, urgent: true);

      final alarms = await store.watchAlarms(ws).first;
      expect(alarms, hasLength(1));
      expect(alarms.single.remindAt, due);
      expect(alarms.single.urgent, isTrue);
      expect(alarms.single.requiresAcknowledgement, isTrue);
    },
  );

  test('a plain due date synthesizes nothing', () async {
    await seedTask(dueAt: DateTime.utc(2030, 6, 2, 14));
    expect(await store.watchAlarms(ws).first, isEmpty);
  });

  test('a snoozed task carries its snooze into the synthetic alarm', () async {
    final due = DateTime.utc(2030, 6, 2, 14);
    final until = DateTime.utc(2030, 6, 2, 15);
    await seedTask(dueAt: due, urgent: true, snoozedUntil: until);

    final alarm = (await store.watchAlarms(ws).first).single;
    expect(alarm.status, 'snoozed');
    expect(alarm.snoozedUntil, until);
  });

  test('the real reminder row replaces the synthetic twin', () async {
    final at = DateTime.utc(2030, 6, 1, 9);
    await seedTask(remindAt: at, urgent: true);
    await seedReminder(remindAt: at);

    final alarms = await store.watchAlarms(ws).first;
    expect(alarms, hasLength(1));
    expect(alarms.single.reminderId, id('R1'));
  });

  test(
    'a terminal reminder row never resurrects as a synthetic alarm',
    () async {
      // The server acknowledged this alarm; the task still carries remindAt.
      final at = DateTime.utc(2030, 6, 1, 9);
      await seedTask(remindAt: at, urgent: true);
      await seedReminder(remindAt: at, status: 'acknowledged');

      expect(await store.watchAlarms(ws).first, isEmpty);
    },
  );

  test('completed and archived tasks synthesize nothing', () async {
    await seedTask(
      tid: 'T1',
      remindAt: DateTime.utc(2030, 6, 1, 9),
      status: 'completed',
    );
    await seedTask(
      tid: 'T2',
      dueAt: DateTime.utc(2030, 6, 2, 9),
      urgent: true,
      status: 'archived',
    );
    expect(await store.watchAlarms(ws).first, isEmpty);
  });

  test(
    'acknowledging a synthetic id resolves to the task’s active row',
    () async {
      final at = DateTime.utc(2030, 6, 1, 9);
      await seedTask(remindAt: at, urgent: true);
      await seedReminder(remindAt: at);

      await store.acknowledge(syntheticReminderId('remind', id('T1')));

      final row = await db.select(db.reminders).getSingle();
      expect(row.status, 'acknowledged');
      final outbox = await db.select(db.pendingMutations).get();
      expect(outbox.single.entityId, id('R1'));
    },
  );

  test(
    'acknowledging a synthetic id with no row yet is a safe no-op',
    () async {
      await seedTask(dueAt: DateTime.utc(2030, 6, 2, 14), urgent: true);

      await store.acknowledge(syntheticReminderId('remind', id('T1')));

      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );

  // ── OPH-175 (round 9 #6.3): a reminder does NOT replace the deadline ───────

  group('two alarm kinds', () {
    test('an urgent task with BOTH times yields two alarms', () async {
      final remind = DateTime.utc(2030, 6, 5, 21, 42);
      final due = DateTime.utc(2030, 6, 5, 21, 45);
      await seedTask(remindAt: remind, dueAt: due, urgent: true);

      final alarms = await store.watchAlarms(ws).first;
      expect(alarms, hasLength(2));
      final byKind = {for (final a in alarms) a.kind: a};
      expect(byKind['remind']!.remindAt, remind);
      expect(byKind['due']!.remindAt, due);
      // The deadline alarm is urgent too — round 9's whole point.
      expect(byKind['due']!.urgent, isTrue);
      expect(byKind['due']!.reminderId, syntheticReminderId('due', id('T1')));
    });

    test('one instant never rings twice (equal times collapse)', () async {
      final at = DateTime.utc(2030, 6, 5, 21, 45);
      await seedTask(remindAt: at, dueAt: at, urgent: true);

      final alarms = await store.watchAlarms(ws).first;
      expect(alarms, hasLength(1));
      expect(alarms.single.kind, 'remind');
    });

    test('a non-urgent task never gets a deadline alarm', () async {
      await seedTask(
        remindAt: DateTime.utc(2030, 6, 5, 21, 42),
        dueAt: DateTime.utc(2030, 6, 5, 21, 45),
      );
      final alarms = await store.watchAlarms(ws).first;
      expect(alarms.map((a) => a.kind), ['remind']);
    });

    test('a synced row replaces only ITS kind, not the other', () async {
      final remind = DateTime.utc(2030, 6, 5, 21, 42);
      final due = DateTime.utc(2030, 6, 5, 21, 45);
      await seedTask(remindAt: remind, dueAt: due, urgent: true);
      // Only the reminder row has arrived from the server.
      await seedReminder(rid: 'R1', remindAt: remind, kind: 'remind');

      final alarms = await store.watchAlarms(ws).first;
      expect(alarms, hasLength(2));
      final byKind = {for (final a in alarms) a.kind: a};
      expect(byKind['remind']!.reminderId, id('R1')); // canonical
      expect(
        byKind['due']!.reminderId,
        syntheticReminderId('due', id('T1')),
      ); // still synthetic
    });

    test('acknowledging the nudge leaves the deadline alarm armed', () async {
      final remind = DateTime.utc(2030, 6, 5, 21, 42);
      final due = DateTime.utc(2030, 6, 5, 21, 45);
      await seedTask(remindAt: remind, dueAt: due, urgent: true);
      await seedReminder(rid: 'R1', remindAt: remind, kind: 'remind');
      await seedReminder(rid: 'R2', remindAt: due, kind: 'due');

      await store.acknowledge(syntheticReminderId('remind', id('T1')));

      final rows = await db.select(db.reminders).get();
      final byKind = {for (final r in rows) r.kind: r};
      expect(byKind['remind']!.status, 'acknowledged');
      expect(
        byKind['due']!.status,
        'scheduled',
        reason:
            'answering the 21:42 nudge says nothing about the 21:45 deadline',
      );
    });

    test(
      'an acknowledged kind does not come back as a synthetic twin',
      () async {
        final remind = DateTime.utc(2030, 6, 5, 21, 42);
        final due = DateTime.utc(2030, 6, 5, 21, 45);
        await seedTask(remindAt: remind, dueAt: due, urgent: true);
        await seedReminder(
          rid: 'R1',
          remindAt: remind,
          kind: 'remind',
          status: 'acknowledged',
        );

        final alarms = await store.watchAlarms(ws).first;
        expect(alarms.map((a) => a.kind), ['due']);
      },
    );
  });

  // ── OPH-178 (round 9 #6.7): silence without completing ─────────────────────

  group('silenced tasks', () {
    test('a muted task synthesizes no alarms at all', () async {
      await seedTask(
        remindAt: DateTime.utc(2030, 6, 5, 21, 42),
        dueAt: DateTime.utc(2030, 6, 5, 21, 45),
        urgent: true,
        alarmsMutedAt: DateTime.utc(2030, 6, 1),
      );
      expect(await store.watchAlarms(ws).first, isEmpty);
    });

    test('giving the alarms back brings them straight back', () async {
      await seedTask(
        remindAt: DateTime.utc(2030, 6, 5, 21, 42),
        urgent: true,
        alarmsMutedAt: DateTime.utc(2030, 6, 1),
      );
      expect(await store.watchAlarms(ws).first, isEmpty);

      await (db.update(db.tasks)..where((t) => t.id.equals(id('T1')))).write(
        const TasksCompanion(alarmsMutedAt: Value(null)),
      );
      final alarms = await store.watchAlarms(ws).first;
      expect(alarms.map((a) => a.kind), ['remind']);
    });

    test('a muted task stays a normal, open task', () async {
      await seedTask(
        remindAt: DateTime.utc(2030, 6, 5, 21, 42),
        alarmsMutedAt: DateTime.utc(2030, 6, 1),
      );
      final task = await db.select(db.tasks).getSingle();
      // Silence is not completion (DESIGN §11 A5): the row keeps its status and
      // its times, it just has no alarms.
      expect(task.status, 'open');
      expect(task.remindAt, isNotNull);
    });
  });

  // OPH-439 (#47, NOTIFICATIONS §2b.3): a grouped stop acknowledges every
  // member's urgent alarm in the minute that rang — one write.
  group('acknowledgeBatch', () {
    final nineAm = DateTime.utc(2030, 6, 1, 9);
    final minute = nineAm.millisecondsSinceEpoch ~/ 60000;

    Future<void> seedGroup() async {
      await seedTask(tid: 'T1', remindAt: nineAm, urgent: true);
      await seedTask(tid: 'T2', remindAt: nineAm, urgent: true);
      await seedTask(tid: 'T3', remindAt: nineAm, urgent: true);
      await seedTask(tid: 'T4', remindAt: nineAm, urgent: true);
      await seedReminder(rid: 'R1', tid: 'T1', remindAt: nineAm);
      // Same task, another minute: its own alarm, not this occurrence.
      await seedReminder(
        rid: 'R1DUE',
        tid: 'T1',
        kind: 'due',
        remindAt: DateTime.utc(2030, 6, 1, 10),
      );
      await seedReminder(
        rid: 'R2',
        tid: 'T2',
        remindAt: nineAm.add(const Duration(seconds: 30)),
      );
      // Snoozed INTO the minute: its effective instant is the snooze target.
      await seedReminder(
        rid: 'R4',
        tid: 'T4',
        remindAt: DateTime.utc(2030, 6, 1, 8),
        status: 'snoozed',
      );
      await (db.update(db.reminders)..where((r) => r.id.equals(id('R4'))))
          .write(RemindersCompanion(snoozedUntil: Value(nineAm)));
      // In the minute but not a member of the batch.
      await seedReminder(rid: 'R3', tid: 'T3', remindAt: nineAm);
    }

    Future<Map<String, String>> statuses() async => {
      for (final r in await db.select(db.reminders).get()) r.id: r.status,
    };

    test(
      'acknowledgeBatch acknowledges every member of the minute in one transaction',
      () async {
        await seedGroup();
        // Injected fault: the second member's row refuses the write — the
        // first member's acknowledgement must roll back with it.
        await db.customStatement(
          "CREATE TRIGGER boom BEFORE UPDATE ON reminders "
          "WHEN OLD.id = '${id('R2')}' "
          "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
        );
        await expectLater(
          store.acknowledgeBatch([
            id('T1'),
            id('T2'),
            id('T4'),
          ], occurrenceMinute: minute),
          throwsA(anything),
        );
        expect((await statuses()).values.toSet(), {'scheduled', 'snoozed'});
        expect(await db.select(db.pendingMutations).get(), isEmpty);

        await db.customStatement('DROP TRIGGER boom');
        await store.acknowledgeBatch([
          id('T1'),
          id('T2'),
          id('T2'),
          id('T4'),
        ], occurrenceMinute: minute);

        expect(await statuses(), {
          id('R1'): 'acknowledged',
          id('R1DUE'): 'scheduled',
          id('R2'): 'acknowledged',
          id('R4'): 'acknowledged',
          id('R3'): 'scheduled',
        });
        final outbox = await db.select(db.pendingMutations).get();
        expect(outbox.map((m) => m.entityId).toList()..sort(), [
          id('R1'),
          id('R2'),
          id('R4'),
        ]);
        expect(outbox.every((m) => m.entityType == 'reminder'), isTrue);

        // A redelivery finds nothing left to acknowledge.
        await store.acknowledgeBatch([id('T1')], occurrenceMinute: minute);
        expect(await db.select(db.pendingMutations).get(), hasLength(3));
      },
    );

    test('acknowledgeBatch refuses a receipt it does not hold', () async {
      await seedGroup();
      await expectLater(
        store.acknowledgeBatch(
          [id('T1')],
          occurrenceMinute: minute,
          receiptId: 'ev-missing',
        ),
        throwsStateError,
      );
      expect((await statuses())[id('R1')], 'scheduled');
    });
  });
}
