import 'dart:convert';

import 'package:drift/drift.dart';
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
}
