import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// OPH-439 (#47, NOTIFICATIONS §2b.3): a group snooze is ONE write — one
/// transaction, every member once, one outbox mutation per task — and the
/// single-task snooze is its one-element case.
void main() {
  late AwDatabase db;
  late TaskStore store;
  var pokes = 0;
  final nineAm = DateTime.utc(2030, 6, 1, 9);
  final until = DateTime.utc(2030, 6, 1, 9, 5, 7);

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    pokes = 0;
    store = TaskStore(db, () => pokes++);
  });

  tearDown(() => db.close());

  Future<void> addTask(String tid, {String status = 'open'}) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id(tid),
          workspaceId: ws,
          title: 'Acil $tid',
          status: Value(status),
          isUrgent: const Value(true),
          remindAt: Value(nineAm),
          dueAt: Value(nineAm),
        ),
      );

  Future<void> addReminder(
    String rid,
    String tid, {
    String kind = 'remind',
    int snoozeCount = 0,
  }) => db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          id: id(rid),
          taskId: id(tid),
          remindAt: nineAm,
          kind: Value(kind),
          snoozeCount: Value(snoozeCount),
          alarmLevel: const Value('urgent'),
          requiresAcknowledgement: const Value(true),
        ),
      );

  test(
    'snoozeBatch dedupes task ids and writes one outbox mutation per task',
    () async {
      await addTask('T1');
      await addTask('T2');
      await addTask('T3', status: 'completed');
      await addReminder('R1', 'T1');
      await addReminder('R2', 'T2');

      await store.snoozeBatch([
        id('T1'),
        id('T2'),
        id('T1'),
        id('T3'),
        id('NOPE'),
      ], until: until);

      final tasks = {
        for (final t in await db.select(db.tasks).get()) t.id: t.snoozedUntil,
      };
      expect(tasks, {id('T1'): until, id('T2'): until, id('T3'): null});
      final outbox = await db.select(db.pendingMutations).get();
      expect(outbox.map((m) => m.entityId).toList()..sort(), [
        id('T1'),
        id('T2'),
      ]);
      for (final m in outbox) {
        expect(m.entityType, 'task');
        expect(jsonDecode(m.patchJson!), {
          'snoozedUntil': until.toIso8601String(),
        });
      }
      expect(pokes, 1, reason: 'one write, one sync poke');
    },
  );

  test('snoozeCount rises by exactly one per task per batch', () async {
    // T1's reminder and deadline ring in the same minute: the grouped alarm
    // lists T1 once per occurrence, and the snooze must not count it twice.
    await addTask('T1');
    await addTask('T2');
    await addReminder('R1', 'T1');
    await addReminder('R1DUE', 'T1', kind: 'due');
    await addReminder('R2', 'T2', snoozeCount: 2);

    await store.snoozeBatch([id('T1'), id('T1'), id('T2')], until: until);

    Future<Map<String, int>> counts() async => {
      for (final r in await db.select(db.reminders).get()) r.id: r.snoozeCount,
    };
    expect(await counts(), {id('R1'): 1, id('R1DUE'): 1, id('R2'): 3});
    for (final r in await db.select(db.reminders).get()) {
      expect(r.status, 'snoozed');
      expect(r.snoozedUntil, until);
    }

    // The single-task snooze is the one-element batch: same rule.
    await store.snooze(id('T1'), until: until.add(const Duration(hours: 1)));
    expect(await counts(), {id('R1'): 2, id('R1DUE'): 2, id('R2'): 3});
    expect(await db.select(db.pendingMutations).get(), hasLength(3));
  });

  test(
    'snoozeBatch is one transaction: a failing member writes nothing',
    () async {
      await addTask('T1');
      await addTask('T2');
      await addReminder('R1', 'T1');
      await addReminder('R2', 'T2');
      // Injected fault: the second member's alarm row refuses the write.
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE UPDATE ON reminders WHEN OLD.id = '${id('R2')}' "
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );

      await expectLater(
        store.snoozeBatch([id('T1'), id('T2')], until: until),
        throwsA(anything),
      );

      for (final t in await db.select(db.tasks).get()) {
        expect(t.snoozedUntil, isNull);
      }
      for (final r in await db.select(db.reminders).get()) {
        expect(r.snoozeCount, 0);
        expect(r.status, 'scheduled');
      }
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );

  test('snoozeBatch refuses a receipt the transaction does not hold', () async {
    await addTask('T1');
    await addReminder('R1', 'T1');

    await expectLater(
      store.snoozeBatch([id('T1')], until: until, receiptId: 'ev-missing'),
      throwsStateError,
    );
    expect((await db.select(db.tasks).getSingle()).snoozedUntil, isNull);

    await db.transaction(() async {
      await db.insertReceiptIfAbsent(
        eventId: 'ev-1',
        action: 'snooze',
        appliedAt: DateTime.utc(2030),
      );
      await store.snoozeBatch([id('T1')], until: until, receiptId: 'ev-1');
    });
    expect((await db.select(db.tasks).getSingle()).snoozedUntil, until);
  });
}
