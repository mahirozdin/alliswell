import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

import 'sync_engine_test.dart' show FakeSyncApi, id, ws;

/// A receipted alarm action (OPH-427) writes inside the receipt's
/// transaction, and the store pokes the engine before that transaction
/// commits. A debounce timer created there would inherit drift's transaction
/// zone, and its round would query a transaction that is already closed —
/// on the production remote executor that request never answers and the
/// engine stays "running" until a restart. The engine's own work must run in
/// its own zone, whoever pokes it.
void main() {
  late AwDatabase db;
  late FakeSyncApi api;
  late SyncEngine engine;

  setUp(() async {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = FakeSyncApi();
    engine = SyncEngine(
      db: db,
      api: api,
      workspaceId: ws,
      debounce: const Duration(milliseconds: 1),
    );
    await engine.start();
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  test('a poke from inside a committed transaction still pushes the write, '
      'and the next write syncs too', () async {
    Future<void> writeAndPoke(String taskId) => db.transaction(() async {
      // The store's own (nested) transaction, then its poke — still inside
      // the outer receipt transaction's zone.
      await db.transaction(() async {
        await enqueueMutation(
          db,
          workspaceId: ws,
          entityType: 'task',
          entityId: taskId,
          operation: 'update',
          patch: {'title': 'x'},
        );
      });
      engine.notifyLocalWrite();
    });

    await writeAndPoke(id('T1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.pushedBatches, hasLength(1));
    expect(await db.select(db.pendingMutations).get(), isEmpty);

    await writeAndPoke(id('T2'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.pushedBatches, hasLength(2));
    expect(await db.select(db.pendingMutations).get(), isEmpty);
  });

  test('a round asked for from inside a transaction runs outside it', () async {
    late Future<bool> round;
    await db.transaction(() async {
      round = engine.syncNow();
    });
    expect(await round.timeout(const Duration(seconds: 5)), isTrue);
  });
}
