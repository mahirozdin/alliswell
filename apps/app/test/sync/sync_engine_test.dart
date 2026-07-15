import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

Map<String, dynamic> taskSnapshot(
  String taskId, {
  String title = 'Görev',
  List<String> tagIds = const [],
  int revision = 1,
}) => {
  'id': taskId,
  'workspaceId': ws,
  'projectId': null,
  'parentTaskId': null,
  'title': title,
  'description': null,
  'status': 'open',
  'priority': 'none',
  'colorRgb': null,
  'startAt': null,
  'dueAt': '2026-07-20T09:30:15.123Z',
  'scheduledStartAt': null,
  'scheduledEndAt': null,
  'remindAt': null,
  'snoozedUntil': null,
  'timezone': 'Europe/Istanbul',
  'isUrgent': false,
  'requiresAcknowledgement': false,
  'repeatRule': null,
  'estimatedMinutes': null,
  'actualMinutes': null,
  'sortOrder': 0,
  'completedAt': null,
  'revision': revision,
  'createdAt': '2026-07-14T10:00:00.000Z',
  'updatedAt': '2026-07-14T10:00:00.000Z',
  'tagIds': tagIds,
};

Map<String, dynamic> noteSnapshot(
  String noteId, {
  String title = 'Not',
  List<Map<String, dynamic>> links = const [],
}) => {
  'id': noteId,
  'workspaceId': ws,
  'projectId': null,
  'createdFromTaskId': null,
  'title': title,
  'snippet': 'içerik',
  'plainText': 'içerik',
  'contentDelta': [
    {'insert': 'içerik\n'},
  ],
  'contentMarkdown': 'içerik',
  'isPinned': false,
  'isArchived': false,
  'revision': 1,
  'createdAt': '2026-07-14T10:00:00.000Z',
  'updatedAt': '2026-07-14T10:00:00.000Z',
  'links': links,
};

/// Scriptable stand-in for the sync endpoints.
class FakeSyncApi implements SyncApi {
  final List<List<SyncMutation>> pushedBatches = [];
  final List<String> pushedClientIds = [];
  List<SyncPushResult> Function(List<SyncMutation>)? onPush;
  List<SyncPullPage> pullPages = [];
  int pullCalls = 0;
  bool failNetwork = false;

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    if (failNetwork) throw Exception('offline');
    pullCalls += 1;
    if (pullPages.isEmpty) {
      return SyncPullPage(
        fromRevision: sinceRevision,
        toRevision: sinceRevision,
        hasMore: false,
        changes: const [],
      );
    }
    return pullPages.removeAt(0);
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async {
    if (failNetwork) throw Exception('offline');
    pushedBatches.add(mutations);
    pushedClientIds.add(clientId);
    final results =
        onPush?.call(mutations) ??
        [
          for (final (i, m) in mutations.indexed)
            SyncPushResult(
              clientMutationId: m.clientMutationId,
              status: 'applied',
              replayed: false,
              revision: baseRevision + i + 1,
            ),
        ];
    return SyncPushResponse(
      toRevision: baseRevision + mutations.length,
      results: results,
    );
  }
}

void main() {
  late AwDatabase db;
  late FakeSyncApi api;
  late SyncEngine engine;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = FakeSyncApi();
    engine = SyncEngine(db: db, api: api, workspaceId: ws);
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  group('pull applier (OPH-054)', () {
    test('applies snapshots with joins, then tombstones them away', () async {
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 3,
        changes: [
          SyncChange(
            revision: 1,
            entityType: 'task',
            entityId: id('T1'),
            operation: 'create',
            data: taskSnapshot(id('T1'), tagIds: [id('G1')]),
          ),
          SyncChange(
            revision: 2,
            entityType: 'note',
            entityId: id('N1'),
            operation: 'create',
            data: noteSnapshot(
              id('N1'),
              links: [
                {'id': id('L1'), 'entityType': 'task', 'entityId': id('T1')},
              ],
            ),
          ),
          SyncChange(
            revision: 3,
            entityType: 'checklist_item',
            entityId: id('C1'),
            operation: 'create',
            data: {
              'id': id('C1'),
              'taskId': id('T1'),
              'title': 'adım',
              'isDone': false,
              'sortOrder': 0,
              'revision': 3,
            },
          ),
        ],
      );

      // Engine state row does not exist yet — applier only updates when present.
      final task = await db.select(db.tasks).getSingle();
      expect(task.title, 'Görev');
      expect(task.dueAt!.toUtc().millisecond, 123); // DATETIME(3) precision
      expect(await db.select(db.taskTagRows).get(), hasLength(1));
      expect(await db.select(db.noteLinkRows).get(), hasLength(1));
      expect(await db.select(db.checklistItems).get(), hasLength(1));

      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 4,
        changes: [
          SyncChange(
            revision: 4,
            entityType: 'task',
            entityId: id('T1'),
            operation: 'delete',
          ),
        ],
      );
      expect(await db.select(db.tasks).get(), isEmpty);
      // A task tombstone sweeps its local join/detail rows too.
      expect(await db.select(db.taskTagRows).get(), isEmpty);
      expect(await db.select(db.checklistItems).get(), isEmpty);
    });

    test(
      're-applying the same snapshot upserts instead of duplicating',
      () async {
        for (final title in ['v1', 'v2']) {
          await applyPulledChanges(
            db,
            workspaceId: ws,
            toRevision: 1,
            changes: [
              SyncChange(
                revision: 1,
                entityType: 'task',
                entityId: id('T1'),
                operation: 'update',
                data: taskSnapshot(id('T1'), title: title),
              ),
            ],
          );
        }
        final rows = await db.select(db.tasks).get();
        expect(rows, hasLength(1));
        expect(rows.single.title, 'v2');
      },
    );
  });

  group('outbox push (OPH-055)', () {
    test('drains the outbox in order and clears applied mutations', () async {
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: id('T1'),
        operation: 'create',
        patch: {'title': 'offline görev'},
      );
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: id('T1'),
        operation: 'update',
        patch: {'priority': 'high'},
      );

      await engine.start();

      expect(api.pushedBatches, hasLength(1));
      final batch = api.pushedBatches.single;
      expect(batch.map((m) => m.operation), ['create', 'update']);
      expect(batch.first.patch, {'title': 'offline görev'});
      expect(batch.first.localUpdatedAt, isNotNull);
      expect(await db.select(db.pendingMutations).get(), isEmpty);

      // The engine's client identity is stable across rounds.
      final state = await db.select(db.syncStates).getSingle();
      expect(api.pushedClientIds.single, state.clientId);
    });

    test('keeps the outbox and backs off exponentially when offline', () async {
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: id('T1'),
        operation: 'create',
        patch: {'title': 'bekleyen'},
      );
      api.failNetwork = true;

      await engine.start();
      await engine.syncNow();

      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.attempts, greaterThanOrEqualTo(2));
      expect(engine.consecutiveFailures, 2);

      // 1s, 2s, 4s… capped.
      expect(syncBackoffDelay(1), const Duration(seconds: 1));
      expect(syncBackoffDelay(2), const Duration(seconds: 2));
      expect(syncBackoffDelay(5), const Duration(seconds: 16));
      expect(syncBackoffDelay(99), const Duration(seconds: 60));

      // Back online: the retained mutation goes through.
      api.failNetwork = false;
      await engine.syncNow();
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    });

    test('pulls all pages after pushing', () async {
      api.pullPages = [
        SyncPullPage(
          fromRevision: 0,
          toRevision: 1,
          hasMore: true,
          changes: [
            SyncChange(
              revision: 1,
              entityType: 'task',
              entityId: id('T1'),
              operation: 'create',
              data: taskSnapshot(id('T1'), title: 'sayfa 1'),
            ),
          ],
        ),
        SyncPullPage(
          fromRevision: 1,
          toRevision: 2,
          hasMore: false,
          changes: [
            SyncChange(
              revision: 2,
              entityType: 'task',
              entityId: id('T2'),
              operation: 'create',
              data: taskSnapshot(id('T2'), title: 'sayfa 2'),
            ),
          ],
        ),
      ];

      await engine.start();

      expect(await db.select(db.tasks).get(), hasLength(2));
      final state = await db.select(db.syncStates).getSingle();
      expect(state.lastRevision, 2);
      expect(api.pullCalls, 2);
    });
  });

  group('conflicts (OPH-056)', () {
    test('surfaces conflicts and rejections, drops the outbox row', () async {
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: id('T1'),
        operation: 'update',
        patch: {'title': 'bayat'},
      );
      api.onPush = (mutations) => [
        SyncPushResult(
          clientMutationId: mutations.single.clientMutationId,
          status: 'conflict',
          replayed: false,
          errorCode: 'SYNC_STALE_MUTATION',
        ),
      ];

      final surfaced = <SyncConflict>[];
      final sub = engine.conflicts.listen(surfaced.add);
      await engine.start();
      await Future<void>.delayed(Duration.zero);

      expect(await db.select(db.pendingMutations).get(), isEmpty);
      expect(surfaced, hasLength(1));
      expect(surfaced.single.status, 'conflict');
      expect(surfaced.single.errorCode, 'SYNC_STALE_MUTATION');
      await sub.cancel();
    });

    test('reports partially-discarded fields on applied mutations', () async {
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: id('T1'),
        operation: 'update',
        patch: {'title': 'bayat', 'priority': 'high'},
      );
      api.onPush = (mutations) => [
        SyncPushResult(
          clientMutationId: mutations.single.clientMutationId,
          status: 'applied',
          replayed: false,
          revision: 5,
          discardedFields: const ['title'],
        ),
      ];

      final surfaced = <SyncConflict>[];
      final sub = engine.conflicts.listen(surfaced.add);
      await engine.start();
      await Future<void>.delayed(Duration.zero);

      expect(surfaced.single.status, 'applied');
      expect(surfaced.single.discardedFields, ['title']);
      await sub.cancel();
    });

    test(
      'note content conflict spawns a local conflicted copy that syncs up',
      () async {
        // The local replica holds the user's version of the note.
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: id('N1'),
                workspaceId: ws,
                title: 'Ortak not',
                contentDelta: Value(
                  jsonEncode([
                    {'insert': 'benim halim\n'},
                  ]),
                ),
                contentMarkdown: const Value('benim halim'),
                plainText: const Value('benim halim'),
              ),
            );
        await enqueueMutation(
          db,
          workspaceId: ws,
          entityType: 'note',
          entityId: id('N1'),
          operation: 'update',
          patch: {
            'contentDelta': [
              {'insert': 'benim halim\n'},
            ],
          },
        );
        api.onPush = (mutations) => [
          for (final m in mutations)
            if (m.entityType == 'note' && m.operation == 'update')
              SyncPushResult(
                clientMutationId: m.clientMutationId,
                status: 'conflict',
                replayed: false,
                errorCode: 'NOTE_CONTENT_CONFLICT',
              )
            else
              SyncPushResult(
                clientMutationId: m.clientMutationId,
                status: 'applied',
                replayed: false,
                revision: 9,
              ),
        ];

        final surfaced = <SyncConflict>[];
        final sub = engine.conflicts.listen(surfaced.add);
        await engine.start();
        // The copy's own create lands in the outbox and pushes on the follow-up
        // round the engine queues; give the microtask queue a beat.
        await engine.syncNow();
        await Future<void>.delayed(Duration.zero);

        final notes = await db.select(db.notes).get();
        expect(notes, hasLength(2));
        final copy = notes.singleWhere((n) => n.id != id('N1'));
        expect(copy.title, 'Ortak not (çakışan kopya)');
        expect(copy.contentDelta, contains('benim halim'));

        // The copy synced up as a note create.
        final pushedCreates = api.pushedBatches
            .expand((b) => b)
            .where((m) => m.operation == 'create' && m.entityType == 'note');
        expect(pushedCreates, hasLength(1));
        expect(pushedCreates.single.entityId, copy.id);
        expect(await db.select(db.pendingMutations).get(), isEmpty);

        expect(surfaced.single.errorCode, 'NOTE_CONTENT_CONFLICT');
        expect(surfaced.single.conflictCopyNoteId, copy.id);
        await sub.cancel();
      },
    );
  });
}
