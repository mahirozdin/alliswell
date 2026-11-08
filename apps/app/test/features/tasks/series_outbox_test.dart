import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/recurrence.dart';
import 'package:alliswell/src/features/tasks/data/series_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-299 — the CLIENT half of the `task_series` push contract.
///
/// Every other test in this repo asks what the server does with a body a test
/// wrote. This one asks what body the app actually sends, which is the question
/// nobody was asking while recurrence was dead: `SeriesStore.create` put a
/// `fromTaskId` in the patch, the server's field table had no such key, and the
/// push came back `SYNC_UNKNOWN_FIELD` for six weeks with 2394 tests green.
///
/// The literal key set below is deliberate and deliberately duplicated — it is
/// the app's side of an agreement whose other side lives in `TASK_SERIES_FIELDS`
/// (`apps/api/src/routes/sync.js`). OPH-300 replaces the literal with a fixture
/// generated from the server so the two can never drift silently again; until
/// then, a sixth key added here fails loudly instead of shipping.
void main() {
  late AwDatabase db;

  setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
  tearDown(() => db.close());

  test('the create patch carries only fields the server accepts', () async {
    final workspaceId = 'W1'.padRight(26, '0');
    final taskId = 'T1'.padRight(26, '0');

    await SeriesStore(db, () {}).create(
      workspaceId: workspaceId,
      rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
      template: const {'title': 'Günlük rapor'},
      anchorAt: DateTime.utc(2030, 6, 5, 9),
      timezone: 'Europe/Istanbul',
      fromTaskId: taskId,
    );

    final row = await db.select(db.pendingMutations).getSingle();
    expect(row.entityType, 'task_series');
    expect(row.operation, 'create');

    final patch = jsonDecode(row.patchJson!) as Map<String, dynamic>;
    expect(patch.keys.toSet(), {
      'rule',
      'template',
      'timezone',
      'anchorAt',
      'fromTaskId',
    });
    // The one the server used to refuse: it names the task the series adopts,
    // and it must survive the trip rather than being dropped on the way out.
    expect(patch['fromTaskId'], taskId);
  });

  test(
    'the timezone is omitted when the caller has none, not sent as null',
    () async {
      final workspaceId = 'W2'.padRight(26, '0');

      await SeriesStore(db, () {}).create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
        template: const {'title': 'Günlük rapor'},
        anchorAt: DateTime.utc(2030, 6, 5, 9),
      );

      final row = await db.select(db.pendingMutations).getSingle();
      final patch = jsonDecode(row.patchJson!) as Map<String, dynamic>;
      // A device can report "+03"; only the server knows that means
      // Europe/Istanbul (OPH-208). Absence is what makes the server fill it —
      // an explicit null would be a value, and `str(64)` would refuse it.
      expect(patch.containsKey('timezone'), isFalse);
      expect(patch.containsKey('fromTaskId'), isFalse);
    },
  );

  test(
    'an after-completion rule keeps its basis on the way out (OPH-375)',
    () async {
      final workspaceId = 'W3'.padRight(26, '0');
      final store = SeriesStore(db, () {});
      const after = AwRepeatRule(
        freq: AwRepeatFreq.daily,
        interval: 90,
        basis: AwRepeatBasis.completion,
      );
      final id = await store.create(
        workspaceId: workspaceId,
        rule: after,
        template: const {'title': 'Su filtresi'},
        anchorAt: DateTime.utc(2030, 6, 5, 9),
      );
      await store.updateRule(
        workspaceId: workspaceId,
        seriesId: id,
        rule: after.copyWith(interval: 60),
      );

      final rows = await db.select(db.pendingMutations).get();
      final rules = [
        for (final row in rows)
          (jsonDecode(row.patchJson!) as Map<String, dynamic>)['rule'] as Map,
      ];
      expect(rules.map((r) => r['basis']), ['completion', 'completion']);
      expect(rules.last['interval'], 60);
      // …and the local replica reads it back as the same kind of rule.
      expect((await store.byId(id))!.rule.isAfterCompletion, isTrue);
    },
  );

  test(
    'stopping on an open task detaches it locally, and only it (#32)',
    () async {
      final workspaceId = 'W4'.padRight(26, '0');
      final head = 'T4'.padRight(26, '0');
      final later = 'T5'.padRight(26, '0');
      final store = SeriesStore(db, () {});
      final id = await store.create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
        template: const {'title': 'Read mail'},
        anchorAt: DateTime.utc(2030, 6, 5, 9),
      );
      for (final (taskId, day) in [
        (head, '2030-06-05'),
        (later, '2030-06-06'),
      ]) {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: taskId,
                workspaceId: workspaceId,
                title: 'Read mail',
                seriesId: Value(id),
                occurrenceDate: Value(day),
              ),
            );
      }

      await store.stop(
        workspaceId: workspaceId,
        seriesId: id,
        keepTaskId: head,
      );

      Future<TaskRecord> task(String taskId) =>
          (db.select(db.tasks)..where((t) => t.id.equals(taskId))).getSingle();
      expect((await task(head)).seriesId, isNull);
      expect((await task(head)).occurrenceDate, isNull);
      // The rest is the server's call: the pull removes what it retires.
      expect((await task(later)).seriesId, id);
      expect(await store.byId(id), isNull);
      final rows = await db.select(db.pendingMutations).get();
      final stop = rows.last;
      expect(stop.operation, 'delete');
      // The wire body is unchanged — the server keeps the head by itself.
      expect(jsonDecode(stop.patchJson!), isEmpty);
    },
  );
}
