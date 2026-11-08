import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/recurrence.dart';
import 'package:alliswell/src/features/tasks/data/series_store.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

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

  Future<void> seed(
    String workspaceId,
    String seriesId,
    List<(String, String?, String)> rows,
  ) async {
    for (final (taskId, day, status) in rows) {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: taskId,
              workspaceId: workspaceId,
              title: 'Read mail',
              status: Value(status),
              seriesId: Value(seriesId),
              occurrenceDate: Value(day),
            ),
          );
    }
  }

  Future<TaskRecord?> task(String taskId) => (db.select(
    db.tasks,
  )..where((t) => t.id.equals(taskId))).getSingleOrNull();

  test('stopping on an open task cuts the replica the way the server will '
      '(#32, OPH-418)', () async {
    final workspaceId = 'W4'.padRight(26, '0');
    final overdue = 'T3'.padRight(26, '0');
    final head = 'T4'.padRight(26, '0');
    final later = 'T5'.padRight(26, '0');
    final doneLater = 'T6'.padRight(26, '0');
    final store = SeriesStore(db, () {});
    final id = await store.create(
      workspaceId: workspaceId,
      rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
      template: const {'title': 'Read mail'},
      anchorAt: DateTime.utc(2030, 6, 4, 9),
    );
    await seed(workspaceId, id, [
      (overdue, '2030-06-04', 'open'),
      (head, '2030-06-05', 'open'),
      (later, '2030-06-06', 'open'),
      (doneLater, '2030-06-07', 'completed'),
    ]);

    await store.stop(workspaceId: workspaceId, seriesId: id, keepTaskId: head);

    // The task the switch sat on and every earlier open one stay, unlinked:
    // the switch reads `seriesId`, so it is off before any round trip.
    for (final kept in [head, overdue]) {
      expect((await task(kept))!.seriesId, isNull);
      expect((await task(kept))!.occurrenceDate, isNull);
    }
    // Open occurrences after it are gone now, not after the pull.
    expect(await task(later), isNull);
    // A finished one is history and keeps its link (R7).
    expect((await task(doneLater))!.seriesId, id);
    expect(await store.byId(id), isNull);
    final stop = (await db.select(db.pendingMutations).get()).last;
    expect(stop.operation, 'delete');
    // The cut travels as a day — the day after the kept task — so the
    // server deletes exactly what the replica already dropped.
    expect(jsonDecode(stop.patchJson!), {
      'fromDay': '2030-06-06',
      'keepTaskId': head,
    });
  });

  test(
    'stopping on an overdue occurrence still keeps today\'s (OPH-417 rule)',
    () async {
      final workspaceId = 'WA'.padRight(26, '0');
      final overdue = 'TE'.padRight(26, '0');
      final today = 'TF'.padRight(26, '0');
      final tomorrow = 'TG'.padRight(26, '0');
      final store = SeriesStore(
        db,
        () {},
        clock: () => DateTime(2030, 6, 5, 12),
      );
      final id = await store.create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
        template: const {'title': 'Read mail'},
        anchorAt: DateTime.utc(2030, 6, 4, 9),
      );
      await seed(workspaceId, id, [
        (overdue, '2030-06-04', 'open'),
        (today, '2030-06-05', 'open'),
        (tomorrow, '2030-06-06', 'open'),
      ]);

      await store.stop(
        workspaceId: workspaceId,
        seriesId: id,
        keepTaskId: overdue,
      );

      expect((await task(overdue))!.seriesId, isNull);
      expect((await task(today))!.seriesId, isNull);
      expect(await task(tomorrow), isNull);
      final stop = (await db.select(db.pendingMutations).get()).last;
      expect(jsonDecode(stop.patchJson!), {
        'fromDay': '2030-06-06',
        'keepTaskId': overdue,
      });
    },
  );

  test(
    'the server answer to that stop changes nothing on the replica (OPH-418)',
    () async {
      final workspaceId = 'W7'.padRight(26, '0');
      final head = 'T8'.padRight(26, '0');
      final later = 'T9'.padRight(26, '0');
      final store = SeriesStore(db, () {});
      final id = await store.create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
        template: const {'title': 'Read mail'},
        anchorAt: DateTime.utc(2030, 6, 5, 9),
      );
      await seed(workspaceId, id, [
        (head, '2030-06-05', 'open'),
        (later, '2030-06-06', 'open'),
      ]);
      await db
          .into(db.syncStates)
          .insert(
            SyncStatesCompanion.insert(
              workspaceId: workspaceId,
              clientId: 'C1'.padRight(26, '0'),
            ),
          );
      await store.stop(
        workspaceId: workspaceId,
        seriesId: id,
        keepTaskId: head,
      );

      // What softDeleteSeries writes: the kept task unlinked, the later one
      // and the series as tombstones.
      await applyPulledChanges(
        db,
        workspaceId: workspaceId,
        toRevision: 9,
        changes: [
          SyncChange(
            revision: 7,
            entityType: 'task',
            entityId: head,
            operation: 'update',
            data: {
              'id': head,
              'workspaceId': workspaceId,
              'title': 'Read mail',
              'status': 'open',
              'seriesId': null,
              'occurrenceDate': null,
            },
          ),
          SyncChange(
            revision: 8,
            entityType: 'task',
            entityId: later,
            operation: 'delete',
          ),
          SyncChange(
            revision: 9,
            entityType: 'task_series',
            entityId: id,
            operation: 'delete',
          ),
        ],
      );

      expect((await task(head))!.seriesId, isNull);
      expect(await task(later), isNull);
      expect(await store.byId(id), isNull);
    },
  );

  test(
    'an after-completion stop keeps its open task and sends no day (OPH-375)',
    () async {
      final workspaceId = 'W8'.padRight(26, '0');
      final open = 'TA'.padRight(26, '0');
      final store = SeriesStore(db, () {});
      final id = await store.create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(
          freq: AwRepeatFreq.daily,
          interval: 90,
          basis: AwRepeatBasis.completion,
        ),
        template: const {'title': 'Su filtresi'},
        anchorAt: DateTime.utc(2030, 6, 5, 9),
      );
      await seed(workspaceId, id, [(open, '2030-06-05', 'open')]);

      await store.stop(
        workspaceId: workspaceId,
        seriesId: id,
        keepTaskId: open,
      );

      expect((await task(open))!.seriesId, isNull);
      final stop = (await db.select(db.pendingMutations).get()).last;
      expect(jsonDecode(stop.patchJson!), {'keepTaskId': open});
    },
  );

  test('a kept task without a day yet names only itself; later rows wait for '
      'the server (OPH-418)', () async {
    final workspaceId = 'W9'.padRight(26, '0');
    final adopted = 'TB'.padRight(26, '0');
    final other = 'TC'.padRight(26, '0');
    final store = SeriesStore(db, () {});
    final id = await store.create(
      workspaceId: workspaceId,
      rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
      template: const {'title': 'Read mail'},
      anchorAt: DateTime.utc(2030, 6, 5, 9),
    );
    await seed(workspaceId, id, [
      (adopted, null, 'open'),
      (other, '2030-06-06', 'open'),
    ]);

    await store.stop(
      workspaceId: workspaceId,
      seriesId: id,
      keepTaskId: adopted,
    );

    expect((await task(adopted))!.seriesId, isNull);
    expect((await task(other))!.seriesId, id);
    final stop = (await db.select(db.pendingMutations).get()).last;
    expect(jsonDecode(stop.patchJson!), {'keepTaskId': adopted});
  });

  test(
    '"this and future" drops the occurrence it names and the later ones',
    () async {
      final workspaceId = 'W5'.padRight(26, '0');
      final overdue = 'T6'.padRight(26, '0');
      final today = 'T7'.padRight(26, '0');
      final tomorrow = 'TD'.padRight(26, '0');
      final store = SeriesStore(db, () {});
      final id = await store.create(
        workspaceId: workspaceId,
        rule: const AwRepeatRule(freq: AwRepeatFreq.daily),
        template: const {'title': 'Read mail'},
        anchorAt: DateTime.utc(2030, 6, 4, 9),
      );
      await seed(workspaceId, id, [
        (overdue, '2030-06-04', 'open'),
        (today, '2030-06-05', 'open'),
        (tomorrow, '2030-06-06', 'open'),
      ]);

      await store.stop(
        workspaceId: workspaceId,
        seriesId: id,
        fromDay: '2030-06-05',
        keepTaskId: today,
      );

      expect(await task(today), isNull);
      expect(await task(tomorrow), isNull);
      expect((await task(overdue))!.seriesId, isNull);
      // "This and future" names a day, never a kept task.
      final stop = (await db.select(db.pendingMutations).get()).last;
      expect(jsonDecode(stop.patchJson!), {'fromDay': '2030-06-05'});
    },
  );

  test('the cut day crosses months and years', () {
    expect(nextStopDay('2030-06-30'), '2030-07-01');
    expect(nextStopDay('2030-12-31'), '2031-01-01');
    expect(nextStopDay('2032-02-28'), '2032-02-29');
    expect(nextStopDay('not a day'), isNull);
  });
}
