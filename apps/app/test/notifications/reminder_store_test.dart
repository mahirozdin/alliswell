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
        ),
      );

  Future<void> seedReminder({
    String rid = 'R1',
    String tid = 'T1',
    required DateTime remindAt,
    String status = 'scheduled',
  }) => db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          id: id(rid),
          taskId: id(tid),
          remindAt: remindAt,
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
      expect(alarms.single.reminderId, '$kSyntheticReminderPrefix${id('T1')}');
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

      await store.acknowledge('$kSyntheticReminderPrefix${id('T1')}');

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

      await store.acknowledge('$kSyntheticReminderPrefix${id('T1')}');

      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );
}
