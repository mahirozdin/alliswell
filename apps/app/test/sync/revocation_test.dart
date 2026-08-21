import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/revocation.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

/// EE-058 — what a device does when a workspace stops being its business.
///
/// The acceptance is "one pull and the unit's data is off the device", and the
/// dangerous half is the OTHER direction: a wipe triggered by the wrong error
/// would be data loss caused by a flaky network. So the two claims are tested
/// side by side — the permanent refusal wipes, and everything else still
/// backs off exactly as it did.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const otherWs = '01WSBBBBBBBBBBBBBBBBBBBBBB';
String id(String prefix) => prefix.padRight(26, '0');

class ScriptedApi implements SyncApi {
  Object? pullThrows;
  int pullCalls = 0;

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    pullCalls += 1;
    if (pullThrows != null) throw pullThrows!;
    return SyncPullPage(
      fromRevision: sinceRevision,
      toRevision: sinceRevision,
      hasMore: false,
      changes: const [],
    );
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async => SyncPushResponse(toRevision: baseRevision, results: const []);
}

void main() {
  late AwDatabase db;
  late ScriptedApi api;
  late SyncEngine engine;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = ScriptedApi();
    engine = SyncEngine(db: db, api: api, workspaceId: ws);
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  /// A replica with a task, its children, a note with a link, and a second
  /// workspace that must survive untouched.
  Future<void> seed() async {
    for (final (tag, w, taskId, noteId) in [
      ('A', ws, id('T1'), id('N1')),
      ('B', otherWs, id('T2'), id('N2')),
    ]) {
      await db.customStatement(
        'INSERT INTO tasks (id, workspace_id, title, status, priority, timezone, '
        'is_urgent, requires_acknowledgement, sort_order, calendar_mirror_enabled, '
        'title_fold, revision, created_at, updated_at) '
        "VALUES (?, ?, 'Görev', 'open', 'none', 'Europe/Istanbul', 0, 0, 0, 0, 'gorev', 1, 0, 0)",
        [taskId, w],
      );
      await db.customStatement(
        'INSERT INTO notes (id, workspace_id, title, plain_text, content_markdown, '
        'is_pinned, is_archived, title_fold, body_fold, revision, created_at, updated_at) '
        "VALUES (?, ?, 'Not', 'p', 'm', 0, 0, 'not', 'p', 1, 0, 0)",
        [noteId, w],
      );
      await db.customStatement(
        "INSERT INTO checklist_items (id, task_id, title, is_done, sort_order, revision, "
        'created_at, updated_at) VALUES (?, ?, ?, 0, 0, 1, 0, 0)',
        [id('C$tag'), taskId, 'adım'],
      );
      await db.customStatement(
        'INSERT INTO note_link_rows (id, note_id, entity_type, entity_id) VALUES (?, ?, ?, ?)',
        [id('L$tag'), noteId, 'task', taskId],
      );
      await db
          .into(db.pendingMutations)
          .insert(
            PendingMutationsCompanion.insert(
              id: id('M$tag'),
              workspaceId: w,
              entityType: 'task',
              entityId: taskId,
              operation: 'update',
              patchJson: const Value('{"title":"yazdığım şey"}'),
              localUpdatedAt: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              baseRevision: const Value(1),
            ),
          );
    }
  }

  Future<int> count(String table, [String? where, List<Object?>? args]) async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
          variables: [for (final a in args ?? const []) Variable(a)],
        )
        .getSingle();
    return rows.data['n'] as int;
  }

  test(
    'THE ACCEPTANCE: one refused pull and the workspace is off the device',
    () async {
      await seed();
      api.pullThrows = const ApiException(
        kWorkspaceForbiddenCode,
        'You do not have access to this workspace',
      );

      await engine.syncNow();

      // ONE pull. Not "eventually", not "after a backoff".
      expect(api.pullCalls, 1);
      expect(await count('tasks', 'workspace_id = ?', [ws]), 0);
      expect(await count('notes', 'workspace_id = ?', [ws]), 0);
      expect(await count('sync_states', 'workspace_id = ?', [ws]), 0);
      // Orphans go with their parents.
      expect(await count('checklist_items'), 1); // only the other workspace's
      expect(await count('note_link_rows'), 1);
      // The other workspace is untouched — a revocation is about ONE workspace.
      expect(await count('tasks', 'workspace_id = ?', [otherWs]), 1);
      expect(
        await count('pending_mutations', 'workspace_id = ?', [otherWs]),
        1,
      );
    },
  );

  test('what the person wrote survives the revocation', () async {
    await seed();
    api.pullThrows = const ApiException(kWorkspaceForbiddenCode, 'nope');

    await engine.syncNow();

    // The unsent mutation is PARKED, not deleted: losing access is a reason
    // to stop syncing somebody's typing, never a reason to destroy it.
    expect(await count('pending_mutations', 'workspace_id = ?', [ws]), 0);
    final parked = await (db.select(
      db.rejectedMutations,
    )..where((r) => r.workspaceId.equals(ws))).get();
    expect(parked, hasLength(1));
    expect(parked.single.patchJson, '{"title":"yazdığım şey"}');
    expect(parked.single.errorCode, kWorkspaceForbiddenCode);
    expect(engine.revokedParkedCount, 1);
  });

  test(
    'the engine stops instead of looping on a permanent condition',
    () async {
      await seed();
      api.pullThrows = const ApiException(kWorkspaceForbiddenCode, 'nope');

      await engine.syncNow();
      expect(engine.revoked, isTrue);

      // A second round does nothing: the engine is stopped, so the device is
      // not retrying an answer that will never change.
      await engine.syncNow();
      expect(api.pullCalls, 1);
    },
  );

  test(
    'SAFETY: any OTHER failure still backs off and keeps the replica',
    () async {
      await seed();
      // Offline.
      api.pullThrows = Exception('offline');
      await engine.syncNow();
      expect(engine.revoked, isFalse);
      expect(await count('tasks', 'workspace_id = ?', [ws]), 1);
      expect(await count('pending_mutations', 'workspace_id = ?', [ws]), 1);

      // A DIFFERENT coded refusal — e.g. an API key bound to another workspace.
      // Close enough to be confused with revocation, and it must not wipe: the
      // key is wrong, the person's membership is not.
      api.pullThrows = const ApiException('AUTH_APIKEY_WORKSPACE', 'wrong key');
      await engine.syncNow();
      expect(engine.revoked, isFalse);
      expect(await count('tasks', 'workspace_id = ?', [ws]), 1);

      // A 401 is a token problem, not an access problem.
      api.pullThrows = const ApiException('HTTP_401', 'expired');
      await engine.syncNow();
      expect(engine.revoked, isFalse);
      expect(await count('tasks', 'workspace_id = ?', [ws]), 1);
    },
  );

  test(
    'the wipe follows the SCHEMA, so a new table cannot escape it',
    () async {
      // The failure mode of forgetting a table is confidential content left on
      // a device that should no longer hold it — which nothing else would
      // notice. So the classification is compared with the live schema.
      final known = revocationCoverage(db);
      final actual = {for (final t in db.allTables) t.actualTableName};
      final unclassified = actual.difference(known);
      expect(
        unclassified,
        isEmpty,
        reason:
            'these tables are neither workspace-scoped, a declared child, nor '
            'declared device-local — classify them in revocation.dart: '
            '$unclassified',
      );
    },
  );
}
