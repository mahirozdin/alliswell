import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// EE-216 / OPH-330 — the offline half, on the device.
///
/// ── WHAT THIS PROVES THAT THE SERVER SUITE CANNOT ─────────────────────
///
/// The integration suite proves a draft becomes a request. It cannot prove
/// the part the feature is actually named after: that the writing works with
/// NOTHING on the other end. Every test here runs against an in-memory replica
/// and no network at all — there is no server to be unreachable, which is a
/// sharper version of airplane mode than mocking a failing client would be.
///
/// The claim under test is therefore narrow and total: after `write` returns,
/// the request exists on this device and is queued, and neither of those is
/// conditional on a connection.
void main() {
  late AwDatabase db;
  const ws = 'W1';

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    AwI18n.instance.setActiveCached(const Locale('en'));
  });
  tearDown(() => db.close());

  group('writing with no signal', () {
    test('a draft lands in the replica AND the outbox, in one go', () async {
      final store = TicketDraftStore(db);
      final id = await store.write(
        workspaceId: ws,
        subject: 'Kompresör gece durdu',
        body: 'Basınç düştü, ekranda E14 yazıyor.',
        serviceId: 'S1',
      );

      final rows = await db.select(db.ticketDrafts).get();
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Kompresör gece durdu');
      expect(rows.single.ticketId, null);
      // The device has no team to give — the server stamps the one its host
      // proves, and the next pull fills this in.
      expect(rows.single.teamId, null);

      final pending = await db.select(db.pendingMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityType, 'ee_ticket_draft');
      expect(pending.single.operation, 'create');
      expect(pending.single.entityId, id);
    });

    test('a draft with no service is written anyway', () async {
      // The case the whole design turns on: somebody knows what they saw and
      // not which service it files under — and the catalogue may not even be
      // on the device. Refusing here would make the offline path useless
      // exactly when it matters.
      final store = TicketDraftStore(db);
      await store.write(workspaceId: ws, subject: 'Ne olduğunu bilmiyorum');

      final row = await db.select(db.ticketDrafts).getSingle();
      expect(row.serviceId, null);
      final patch =
          (await db.select(db.pendingMutations).getSingle()).patchJson;
      // Absent, not null: a key the server does not expect on this shape is
      // better left off than sent empty.
      expect(patch, isNot(contains('serviceId')));
    });

    test(
      'naming the service later queues an update, not a second draft',
      () async {
        final store = TicketDraftStore(db);
        final id = await store.write(
          workspaceId: ws,
          subject: 'Sonra karar verdim',
        );
        expect(await store.edit(id, serviceId: 'S2'), isTrue);

        expect(await db.select(db.ticketDrafts).get(), hasLength(1));
        final ops = (await db.select(db.pendingMutations).get())
            .map((m) => m.operation)
            .toList();
        expect(ops, ['create', 'update']);
      },
    );
  });

  group('when the server has spoken', () {
    /// The tombstone, as pull delivers it.
    Future<void> pullTombstone(String id) => applyPulledChanges(
      db,
      workspaceId: ws,
      changes: [
        SyncChange(
          revision: 2,
          entityType: 'ee_ticket_draft',
          entityId: id,
          operation: 'delete',
        ),
      ],
      toRevision: 2,
    );

    test(
      'the tombstone removes it — which is how the device learns it was filed',
      () async {
        final store = TicketDraftStore(db);
        final id = await store.write(
          workspaceId: ws,
          subject: 'Vinç freni tutmuyor',
        );
        await db
            .into(db.syncStates)
            .insert(
              SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'),
            );

        await pullTombstone(id);
        // Gone, and that is the SUCCESS path rather than a loss: the text is on
        // the request now, and a second copy sitting on a phone nobody manages
        // is one more place it leaks from.
        expect(await db.select(db.ticketDrafts).get(), isEmpty);
      },
    );

    test('a draft the server already converted cannot be edited', () async {
      final store = TicketDraftStore(db);
      final id = await store.write(
        workspaceId: ws,
        subject: 'Pano sigortası attı',
      );
      await db
          .into(db.syncStates)
          .insert(SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'));

      // The replica catches up: the row comes back carrying its ticket, one
      // pull before the tombstone.
      await applyPulledChanges(
        db,
        workspaceId: ws,
        changes: [
          SyncChange(
            revision: 2,
            entityType: 'ee_ticket_draft',
            entityId: id,
            operation: 'update',
            data: {
              'id': id,
              'workspaceId': ws,
              'teamId': 'TEAM1',
              'serviceId': null,
              'subject': null,
              'body': null,
              'ticketId': 'TICKET1',
              'submittedAt': null,
              'createdAt': null,
              'revision': 2,
              'updatedAt': null,
            },
          ),
        ],
        toRevision: 2,
      );

      // Editing now would queue a mutation the server answers
      // SYNC_ENTITY_DELETED to, and would let somebody type into a note that
      // has already been filed. Nothing is queued.
      expect(await store.edit(id, subject: 'yine attı'), isFalse);
      final ops = (await db.select(db.pendingMutations).get())
          .map((m) => m.operation)
          .toList();
      expect(ops, ['create']);
    });

    test('the list shows only what is still waiting', () async {
      final store = TicketDraftStore(db);
      await store.write(workspaceId: ws, subject: 'Hâlâ bekliyor');
      final sent = await store.write(workspaceId: ws, subject: 'Gitti');
      await db
          .into(db.syncStates)
          .insert(SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'));
      await pullTombstone(sent);

      final waiting = await (db.select(
        db.ticketDrafts,
      )..where((d) => d.ticketId.isNull())).get();
      expect(waiting.map((d) => d.subject), ['Hâlâ bekliyor']);
    });
  });
}
