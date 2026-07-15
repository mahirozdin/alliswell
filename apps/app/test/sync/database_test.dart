import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/ulid.dart';
import 'package:alliswell/src/sync/db/database.dart';

void main() {
  late AwDatabase db;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await db.close();
  });

  test('ULIDs are 26 Crockford chars, time-ordered and unique', () {
    final a = newUlid(now: DateTime.utc(2026, 1, 1));
    final b = newUlid(now: DateTime.utc(2026, 6, 1));
    expect(a, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
    expect(b.compareTo(a), greaterThan(0)); // later time sorts later
    final many = {for (var i = 0; i < 500; i++) newUlid()};
    expect(many, hasLength(500));
  });

  test('round-trips a task with millisecond timestamps intact', () async {
    final due = DateTime.utc(2026, 7, 20, 9, 30, 15, 123);
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'T1'.padRight(26, '0'),
            workspaceId: 'W1'.padRight(26, '0'),
            title: 'Süt al',
            dueAt: Value(due),
            revision: const Value(3),
          ),
        );

    final row = await db.select(db.tasks).getSingle();
    expect(row.title, 'Süt al');
    expect(row.revision, 3);
    // store_date_time_values_as_text keeps DATETIME(3) precision.
    expect(row.dueAt!.toUtc(), due);
    expect(row.status, 'open'); // column default
  });

  test('outbox rows keep insertion order and the sync state upserts', () async {
    for (final (i, op) in ['create', 'update', 'delete'].indexed) {
      await db
          .into(db.pendingMutations)
          .insert(
            PendingMutationsCompanion.insert(
              id: 'M$i'.padRight(26, '0'),
              workspaceId: 'W1'.padRight(26, '0'),
              entityType: 'task',
              entityId: 'T1'.padRight(26, '0'),
              operation: op,
              localUpdatedAt: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    }
    final pending = await (db.select(
      db.pendingMutations,
    )..orderBy([(m) => OrderingTerm.asc(m.id)])).get();
    expect(pending.map((m) => m.operation), ['create', 'update', 'delete']);

    await db
        .into(db.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            workspaceId: 'W1'.padRight(26, '0'),
            clientId: newUlid(),
            lastRevision: const Value(42),
          ),
        );
    final state = await db.select(db.syncStates).getSingle();
    expect(state.lastRevision, 42);
  });
}
