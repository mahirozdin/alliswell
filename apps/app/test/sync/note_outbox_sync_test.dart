import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alliswell/src/features/notes/data/note_store.dart';
import 'package:alliswell/src/screens/home_shell.dart' show freshSyncConflict;
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

/// The client half of ADR-0072 (OPH-488, OPH-489), proven against a server
/// with the OLD rules — an id-only replay and a refusal for base 0 or any
/// stale base. A device must never need the server's leniency: an installed
/// self-hosted server may not have it yet.
///
/// The 2026-11-18 report's two causes, from the device's side:
/// - H1: a save queued before the note's create was answered carried base 0;
/// - H2: a newer body was coalesced into an outbox row a push had already
///   carried, and its resend was answered with the first answer.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';

/// The pre-ADR-0072 server, for notes: first answer per id wins forever; a
/// content update applies only with no base or a current one.
class StrictServer implements SyncApi {
  final recorded = <String, SyncPushResult>{};
  final bodies = <String, String>{};
  final revisions = <String, int>{};
  final processed = <SyncMutation>[];
  int revision = 10;
  Completer<void>? gate;
  final pulls = <SyncPullPage>[];

  /// The next content update is answered `merged` with this body.
  String? mergeNext;

  /// No connection at all: nothing reaches the server.
  bool unreachable = false;

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async => pulls.isEmpty
      ? SyncPullPage(
          fromRevision: sinceRevision,
          toRevision: sinceRevision,
          hasMore: false,
          changes: const [],
        )
      : pulls.removeAt(0);

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async {
    if (unreachable) throw const SyncPushNotSent();
    final results = <SyncPushResult>[];
    for (final m in mutations) {
      final prior = recorded[m.clientMutationId];
      if (prior != null) {
        results.add(
          SyncPushResult(
            clientMutationId: m.clientMutationId,
            status: prior.status,
            replayed: true,
            revision: prior.revision,
            errorCode: prior.errorCode,
          ),
        );
        continue;
      }
      processed.add(m);
      final body = m.patch?['contentMarkdown'] as String?;
      final current = revisions[m.entityId] ?? 0;
      SyncPushResult r;
      if (mergeNext != null && m.operation == 'update' && body != null) {
        revision += 1;
        bodies[m.entityId] = mergeNext!;
        revisions[m.entityId] = revision;
        r = SyncPushResult(
          clientMutationId: m.clientMutationId,
          status: 'merged',
          replayed: false,
          revision: revision,
          mergedMarkdown: mergeNext,
        );
        mergeNext = null;
      } else if (m.operation == 'update' &&
          body != null &&
          m.baseRevision != null &&
          m.baseRevision! < current) {
        r = SyncPushResult(
          clientMutationId: m.clientMutationId,
          status: 'conflict',
          replayed: false,
          errorCode: 'NOTE_CONTENT_CONFLICT',
          conflictVersionId: 'VERSION0000000000000000001',
          reason: 'BASE_MISSING',
        );
      } else {
        revision += 1;
        if (body != null) bodies[m.entityId] = body;
        revisions[m.entityId] = revision;
        r = SyncPushResult(
          clientMutationId: m.clientMutationId,
          status: 'applied',
          replayed: false,
          revision: revision,
        );
      }
      recorded[m.clientMutationId] = r;
      results.add(r);
    }
    final g = gate;
    if (g != null) await g.future; // answered server-side, still on the wire
    return SyncPushResponse(toRevision: revision, results: results);
  }
}

void main() {
  late AwDatabase db;
  late StrictServer api;
  late SyncEngine engine;
  late NoteStore store;
  late List<SyncConflict> conflicts;
  late StreamSubscription<SyncConflict> sub;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = StrictServer();
    engine = SyncEngine(db: db, api: api, workspaceId: ws);
    store = NoteStore(db, () {});
    conflicts = [];
    sub = engine.conflicts.listen(conflicts.add);
  });

  tearDown(() async {
    await sub.cancel();
    engine.dispose();
    await db.close();
  });

  Map<String, dynamic> body(String text) => {
    'title': 'Not',
    'contentMarkdown': text,
    'contentFormat': 'markdown',
  };

  Future<NoteRecord> local(String id) =>
      (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

  test('H1: saves queued before any push ride in the create itself', () async {
    final id = await store.create(ws, body(''));
    await store.update(id, body('Birinci'));
    await store.update(id, body('Birinci ikinci'));
    expect(await db.select(db.pendingMutations).get(), hasLength(1));

    await engine.syncNow();

    expect(api.processed.map((m) => m.operation), ['create']);
    expect(api.bodies[id], 'Birinci ikinci');
    expect(conflicts, isEmpty);
  });

  test(
    'H1: a save made while the create is in flight carries no base 0',
    () async {
      final id = await store.create(ws, body(''));
      api.gate = Completer<void>();
      final round = engine.syncNow();
      await pumpEventQueue();
      await store.update(id, body('Yazdığım metin'));
      api.gate!.complete();
      api.gate = null;
      await round;
      await engine.syncNow();

      final update = api.processed.singleWhere((m) => m.operation == 'update');
      expect(update.baseRevision, isNot(0));
      expect(api.bodies[id], 'Yazdığım metin');
      expect(conflicts, isEmpty);
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );

  test(
    'H2: a save behind an in-flight update is its own row, and lands',
    () async {
      final id = await store.create(ws, body(''));
      await engine.syncNow();
      await store.update(id, body('Paragraf A'));
      api.gate = Completer<void>();
      final round = engine.syncNow();
      await pumpEventQueue();
      await store.update(id, body('Paragraf A\n\nParagraf B'));
      final rows = await db.select(db.pendingMutations).get();
      expect(rows, hasLength(2), reason: 'never rewritten once sent');
      api.gate!.complete();
      api.gate = null;
      await round;
      await engine.syncNow();

      expect(api.bodies[id], 'Paragraf A\n\nParagraf B');
      final ids = api.processed.map((m) => m.clientMutationId).toSet();
      expect(ids, hasLength(api.processed.length), reason: 'no id reused');
      expect(conflicts, isEmpty, reason: 'its base moved past its own write');
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    },
  );

  Map<String, dynamic> pulled(String id, String text, int rev) => {
    'id': id,
    'workspaceId': ws,
    'title': 'Not',
    'contentMarkdown': text,
    'plainText': text,
    'isPinned': true,
    'revision': rev,
  };

  test('OPH-489: a pull keeps the body and base of a note whose save is '
      'still queued, and takes the rest', () async {
    final id = await store.create(ws, body('Sunucudaki'));
    await engine.syncNow();
    final settled = (await local(id)).revision;
    await store.update(id, body('Sunucudaki ve yenisi'));

    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: settled + 5,
      changes: [
        SyncChange(
          revision: settled + 5,
          entityType: 'note',
          entityId: id,
          operation: 'upsert',
          data: pulled(id, 'Eski', settled + 5),
        ),
      ],
    );

    final row = await local(id);
    expect(row.contentMarkdown, 'Sunucudaki ve yenisi');
    expect(row.revision, settled, reason: 'the base still matches the body');
    expect(row.isPinned, isTrue, reason: 'non-body fields still arrive');
  });

  test(
    'OPH-489: with nothing queued, a pull takes the body as before',
    () async {
      final id = await store.create(ws, body('Bir'));
      await engine.syncNow();
      await applyPulledChanges(
        db,
        workspaceId: ws,
        toRevision: 99,
        changes: [
          SyncChange(
            revision: 99,
            entityType: 'note',
            entityId: id,
            operation: 'upsert',
            data: pulled(id, 'Başka cihazdan', 99),
          ),
        ],
      );
      final row = await local(id);
      expect(row.contentMarkdown, 'Başka cihazdan');
      expect(row.revision, 99);
    },
  );

  test(
    'OPH-489: a merged answer does not overwrite a newer queued save',
    () async {
      final id = await store.create(ws, body('A'));
      await engine.syncNow();
      final settled = (await local(id)).revision;
      await store.update(id, body('A B'));
      api.mergeNext = 'X A B';
      api.gate = Completer<void>();
      final round = engine.syncNow();
      await pumpEventQueue();
      await store.update(id, body('A B C'));
      api.gate!.complete();
      api.gate = null;
      await round;

      // The queued save is the newest text; the merged one must not replace it
      // on the device — the server merges the queued save in its turn.
      final row = await local(id);
      expect(row.contentMarkdown, 'A B C');
      final queued = await db.select(db.pendingMutations).get();
      expect(queued, hasLength(1));
      expect(
        row.revision,
        settled,
        reason:
            'the merged revision has lines '
            'the device does not',
      );
      expect(queued.single.baseRevision, settled);
    },
  );

  test('OPH-489: a pin answer does not move the base past a body a pull '
      'held back', () async {
    final id = await store.create(ws, body('A'));
    await engine.syncNow();
    final settled = (await local(id)).revision;
    // Another device has rewritten the body on the server.
    api.revisions[id] = settled + 3;
    api.revision = settled + 3;
    await store.update(id, body('A B'));
    api.gate = Completer<void>();
    final round = engine.syncNow(); // the body save is on the wire
    await pumpEventQueue();
    await store.update(id, {'isPinned': true}); // its own row: one is sent
    // The foreign body arrives while the body save waits: it is held back.
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: settled + 3,
      changes: [
        SyncChange(
          revision: settled + 3,
          entityType: 'note',
          entityId: id,
          operation: 'upsert',
          data: pulled(id, 'A F', settled + 3),
        ),
      ],
    );
    api.gate!.complete();
    api.gate = null;
    await round;
    await engine.syncNow();

    // The body save was refused; the pin landed — and must not hand the
    // replica a revision whose body (A F) it does not have.
    expect(api.processed.map((m) => m.patch?.keys.first), contains('isPinned'));
    expect((await local(id)).revision, settled);
  });

  test('OPH-489: a replayed answer moves no revision — it may have been a '
      'merge', () async {
    final id = await store.create(ws, body('A'));
    await engine.syncNow();
    final settled = (await local(id)).revision;
    await store.update(id, body('A B'));
    final row = (await db.select(db.pendingMutations).get()).single;
    // The server already answered this id (the first answer was lost).
    api.recorded[row.id] = SyncPushResult(
      clientMutationId: row.id,
      status: 'applied',
      replayed: false,
      revision: settled + 7,
    );
    await engine.syncNow();
    expect((await local(id)).revision, settled);
    expect(await db.select(db.pendingMutations).get(), isEmpty);
  });

  test('OPH-488: a push that never connected leaves its rows unsent, so the '
      'next save still joins them', () async {
    final id = await store.create(ws, body('A'));
    await engine.syncNow();
    await store.update(id, body('A B'));
    api.unreachable = true;
    await engine.syncNow();
    final queued = (await db.select(db.pendingMutations).get()).single;
    expect(queued.sentAt, isNull);
    await store.update(id, body('A B C'));
    expect(await db.select(db.pendingMutations).get(), hasLength(1));
  });

  test('OPH-493: rebuilding the engines does not show the last conflict '
      'again', () async {
    final tick = NotifierProvider<_Tick, int>(_Tick.new);
    final container = ProviderContainer(
      overrides: [
        syncEnginesProvider.overrideWith((ref) {
          ref.watch(tick);
          return {ws: engine};
        }),
      ],
    );
    addTearDown(container.dispose);
    final shown = <SyncConflict>[];
    container.listen(syncConflictsProvider, (previous, next) {
      final c = freshSyncConflict(previous, next);
      if (c != null) shown.add(c);
    });

    final id = await store.create(ws, body('A'));
    await engine.syncNow();
    api.revisions[id] = api.revisions[id]! + 5; // another device moved it on
    await store.update(id, body('B'));
    await engine.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(shown, hasLength(1));

    for (var i = 0; i < 3; i++) {
      container.read(tick.notifier).bump();
      container.read(syncConflictsProvider);
      await Future<void>.delayed(Duration.zero);
    }
    expect(shown, hasLength(1));
  });
}

class _Tick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
