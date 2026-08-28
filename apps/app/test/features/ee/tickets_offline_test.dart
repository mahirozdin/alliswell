import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

/// EE-091 — the claim the whole epic is built on, with the server switched off.
///
/// "A service desk that keeps working on a factory floor with no signal" is the
/// product's distinguishing sentence, and D5 (ADR-0011 §1) is the technical
/// form of it: tickets are sync entities in the unit's workspace, so the queue
/// opens from the device's own replica. Everything else in E09 rests on that
/// being TRUE rather than intended, and until this file existed it was only
/// argued — the server tests prove the door an offline client uses, which is
/// not the same as proving the client survives the door being shut.
///
/// So every call to the server throws here, for the whole test. What is
/// asserted is the round trip a bad-Wi-Fi shift actually makes:
///
///   1. the queue still answers, from the replica, through the REAL provider
///      the screen watches — not a re-typed copy of its query;
///   2. a write made while offline is not lost but QUEUED;
///   3. when the signal comes back, it goes.
///
/// ── Why this is at the engine layer and not a widget test ─────────────────
///
/// The screen is a list of what the provider yields, and a golden of it proves
/// pixels, not persistence. The interesting failure — "the queue was empty
/// because the pull failed" — lives exactly where this test looks.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const otherWs = '01WSBBBBBBBBBBBBBBBBBBBBBB';
String id(String prefix) => prefix.padRight(26, '0');

/// A server that is simply not there. `pullThrows`/`pushThrows` are set for the
/// duration and cleared only where the test says the signal returned.
class OfflineApi implements SyncApi {
  Object? pullThrows;
  Object? pushThrows;
  int pushCalls = 0;
  List<SyncMutation> pushed = const [];

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
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
  }) async {
    pushCalls += 1;
    if (pushThrows != null) throw pushThrows!;
    pushed = mutations;
    return SyncPushResponse(
      toRevision: baseRevision + mutations.length,
      results: [
        for (final m in mutations)
          SyncPushResult(
            clientMutationId: m.clientMutationId,
            status: 'applied',
            replayed: false,
            revision: baseRevision + 1,
          ),
      ],
    );
  }
}

void main() {
  late AwDatabase db;
  late OfflineApi api;
  late SyncEngine engine;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = OfflineApi();
    engine = SyncEngine(db: db, api: api, workspaceId: ws);
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  /// Rows arriving the way a device receives them — through the same applier
  /// switch a real pull uses, not a private helper.
  Future<void> pulled(List<SyncChange> changes) => applyPulledChanges(
    db,
    workspaceId: ws,
    changes: changes,
    toRevision: changes.length,
  );

  Map<String, dynamic> ticket(
    String tid, {
    String workspaceId = ws,
    String subject = 'Pano ışıkları yanmıyor',
    String status = 'new',
    String priority = 'high',
  }) => {
    'id': tid,
    'workspaceId': workspaceId,
    'serviceId': null,
    'requesterId': null,
    'subject': subject,
    'body': 'Sigorta atmış olabilir.',
    'status': status,
    'priority': priority,
    'source': 'internal',
    'terminalAt': null,
    'revision': 1,
    'createdAt': '2026-08-01T08:00:00.000Z',
    'updatedAt': '2026-08-01T08:00:00.000Z',
  };

  /// The queue as the SCREEN gets it: the real provider, watched.
  Future<List<TicketRecord>> queue() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: ws,
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(ticketQueueProvider, (_, _) {});
    addTearDown(sub.close);
    return container.read(ticketQueueProvider.future);
  }

  Future<int> pendingCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM pending_mutations')
        .getSingle();
    return row.data['n'] as int;
  }

  test(
    'the queue opens with the server unreachable, and it is not empty',
    () async {
      await pulled([
        SyncChange(
          revision: 1,
          entityType: 'ee_ticket',
          entityId: id('T1'),
          operation: 'upsert',
          data: ticket(id('T1')),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_ticket',
          entityId: id('T2'),
          operation: 'upsert',
          data: ticket(id('T2'), subject: 'Kompresör sesi', priority: 'normal'),
        ),
        // Another unit's ticket, which this device should never have been given
        // and must not show even if it somehow arrives.
        SyncChange(
          revision: 3,
          entityType: 'ee_ticket',
          entityId: id('T3'),
          operation: 'upsert',
          data: ticket(id('T3'), workspaceId: otherWs, subject: 'Başka birim'),
        ),
      ]);

      // The shift starts. There is no signal, and there will not be one.
      api.pullThrows = Exception('offline');
      api.pushThrows = Exception('offline');
      await engine.syncNow();

      final rows = await queue();
      expect(
        rows,
        hasLength(2),
        reason: 'the unit queue reads from the replica',
      );
      expect(
        rows.map((t) => t.subject),
        containsAll(<String>['Pano ışıkları yanmıyor', 'Kompresör sesi']),
      );
      expect(
        rows.every((t) => t.workspaceId == ws),
        isTrue,
        reason: 'a unit boundary is not something the network enforces',
      );
    },
  );

  test('a write made offline is queued, not lost', () async {
    await pulled([
      SyncChange(
        revision: 1,
        entityType: 'ee_ticket',
        entityId: id('T1'),
        operation: 'upsert',
        data: ticket(id('T1')),
      ),
    ]);
    api.pullThrows = Exception('offline');
    api.pushThrows = Exception('offline');

    // An agent moves it along while standing in a metal building. The local
    // row changes and the outbox records the write, in ONE transaction — the
    // two must never be able to disagree.
    await db.transaction(() async {
      await (db.update(db.tickets)..where((t) => t.id.equals(id('T1')))).write(
        const TicketsCompanion(status: Value('in_progress')),
      );
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'ee_ticket',
        entityId: id('T1'),
        operation: 'update',
        patch: {'status': 'in_progress'},
        baseRevision: 1,
      );
    });

    await engine.syncNow(); // fails, and must fail HARMLESSLY

    expect(await pendingCount(), 1, reason: 'the write is still owed');
    final rows = await queue();
    expect(
      rows.single.status,
      'in_progress',
      reason: 'and the screen already shows it — that is what optimistic means',
    );
  });

  test('when the signal returns, what was owed is paid', () async {
    await pulled([
      SyncChange(
        revision: 1,
        entityType: 'ee_ticket',
        entityId: id('T1'),
        operation: 'upsert',
        data: ticket(id('T1')),
      ),
    ]);
    api.pullThrows = Exception('offline');
    api.pushThrows = Exception('offline');
    await db.transaction(() async {
      await (db.update(db.tickets)..where((t) => t.id.equals(id('T1')))).write(
        const TicketsCompanion(status: Value('in_progress')),
      );
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'ee_ticket',
        entityId: id('T1'),
        operation: 'update',
        patch: {'status': 'in_progress'},
        baseRevision: 1,
      );
    });
    await engine.syncNow();
    expect(await pendingCount(), 1);

    // Back in the yard.
    api.pullThrows = null;
    api.pushThrows = null;
    await engine.syncNow();

    expect(api.pushed.map((m) => m.entityType), contains('ee_ticket'));
    expect(
      await pendingCount(),
      0,
      reason: 'an outbox that never drains is a queue of silent data loss',
    );
  });
}
