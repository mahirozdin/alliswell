import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/sync_contract.dart';

/// OPH-300 — the push contract, asserted where every write passes.
///
/// OPH-299's lesson was not "somebody forgot a field". It was that the client
/// and the server each held half of an agreement and nothing compared the
/// halves: the app put a fifth key in a four-key patch, the server refused the
/// whole mutation, and 2394 tests stayed green because none of them ever sent
/// the body the client actually sends.
///
/// A per-call-site test would have the same blind spot — it only covers the
/// sites somebody remembered. The check therefore lives inside
/// `enqueueMutation` itself, behind an `assert`: every write in every test, and
/// every write a developer makes in a debug build, is checked against the
/// generated contract, and release builds pay nothing.
void main() {
  late AwDatabase db;

  setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
  tearDown(() => db.close());

  final workspaceId = 'W1'.padRight(26, '0');
  final entityId = 'T1'.padRight(26, '0');

  Future<String> enqueue(
    String entityType,
    String operation,
    Map<String, dynamic> patch,
  ) => enqueueMutation(
    db,
    workspaceId: workspaceId,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    patch: patch,
  );

  test('a key the server does not accept never reaches the outbox', () async {
    await expectLater(
      enqueue('task', 'update', {'title': 'ok', 'warp': 9}),
      throwsA(isA<AssertionError>()),
    );
    expect(await db.select(db.pendingMutations).get(), isEmpty);
  });

  test('a create-only key on an update is refused too', () async {
    // `taskId` on a checklist item is create-only: the server would answer
    // SYNC_UNKNOWN_FIELD, which reads like a typo rather than "you cannot move
    // a checklist item between tasks".
    await expectLater(
      enqueue('checklist_item', 'update', {'taskId': entityId}),
      throwsA(isA<AssertionError>()),
    );
  });

  test('an entity type the server has never heard of is refused', () async {
    await expectLater(
      enqueue('wormhole', 'create', {'spin': 1}),
      throwsA(isA<AssertionError>()),
    );
  });

  test('the contract lets real writes through untouched', () async {
    await enqueue('task', 'update', {'title': 'ok', 'snoozedUntil': null});
    await enqueue('task_series', 'create', {
      'rule': {'freq': 'daily'},
      'template': {'title': 'x'},
      'anchorAt': '2030-06-05T09:00:00.000Z',
      'fromTaskId': entityId,
    });
    expect(await db.select(db.pendingMutations).get(), hasLength(2));
  });

  test('EE entity types are out of scope, not violations', () async {
    // The EE overlay registers its entities at runtime
    // (`app.ee.registerSyncEntity`), so the generated contract cannot list
    // them. Silence here is deliberate: "not mine to check" must not read the
    // same as "nobody accepts this".
    await enqueue('ee_task_assignment', 'create', {'assigneeId': entityId});
    expect(await db.select(db.pendingMutations).get(), hasLength(1));
  });

  test('the generated contract covers every entity the server declares', () {
    // A cheap canary on the generator: if this drops to a handful, the Dart was
    // regenerated from something that failed to import the server's map.
    expect(kAwSyncFields.keys, contains('task'));
    expect(kAwSyncFields.keys, contains('task_series'));
    expect(kAwSyncFields['task_series']!.all, contains('fromTaskId'));
    expect(kAwSyncFields['task_series']!.createOnly, contains('fromTaskId'));
  });
}
