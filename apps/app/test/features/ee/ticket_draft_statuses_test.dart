import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

/// EE-225 — where each draft stands, from what the device actually holds.
///
/// Every state here is driven by the same events the sync engine produces —
/// an outbox row, a pushed write, a parked refusal, a pulled tombstone —
/// written straight into the database rather than mocked, because the whole
/// question is whether the list reads THOSE correctly.
const _catalog = EeCatalog(
  services: [
    EeCatalogService(
      id: 'S-ONE',
      name: 'Pres arızası',
      units: [EeCatalogUnit(id: 'U1', name: 'Bakım')],
    ),
    EeCatalogService(
      id: 'S-TWO',
      name: 'Elektrik arızası',
      units: [
        EeCatalogUnit(id: 'U1', name: 'Bakım'),
        EeCatalogUnit(id: 'U2', name: 'Tesis'),
      ],
    ),
  ],
);

/// The person's own space, as a test moves it.
class _Home extends Notifier<String?> {
  @override
  String? build() => 'W-OWN';

  void set(String? next) => state = next;
}

final _home = NotifierProvider<_Home, String?>(_Home.new);

void main() {
  late AwDatabase db;
  late ProviderContainer container;
  late TicketDraftStore store;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    store = TicketDraftStore(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        draftWorkspaceIdProvider.overrideWith((ref) => ref.watch(_home)),
        eeCatalogProvider.overrideWith((ref) async => _catalog),
      ],
    );
    // Keep the tracker and the list alive, as the shell and the screen do.
    container.listen(sentDraftsProvider, (_, _) {});
    container.listen(draftStatusesProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<EeDraftStatus>> settle() async {
    await container.read(eeCatalogProvider.future);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();
    return container.read(draftStatusesProvider);
  }

  /// What a successful push leaves behind: the outbox row, gone.
  Future<void> pushed(String draftId) => (db.delete(
    db.pendingMutations,
  )..where((m) => m.entityId.equals(draftId))).go();

  EeDraftStatus only(List<EeDraftStatus> all, String id) =>
      all.singleWhere((s) => s.id == id);

  test('written and not yet sent: on the phone', () async {
    final id = await store.write(workspaceId: 'W-OWN', subject: 'Durdu');
    expect(only(await settle(), id).state, EeDraftState.onDevice);
  });

  test(
    'pushed and kept by the server: waiting, and the row says which reason',
    () async {
      final none = await store.write(
        workspaceId: 'W-OWN',
        subject: 'Servissiz',
      );
      final two = await store.write(
        workspaceId: 'W-OWN',
        subject: 'Hangi birim',
        serviceId: 'S-TWO',
      );
      final gone = await store.write(
        workspaceId: 'W-OWN',
        subject: 'Kapanmış servis',
        serviceId: 'S-OLD',
      );
      for (final id in [none, two, gone]) {
        await pushed(id);
      }
      final all = await settle();
      expect(only(all, none).state, EeDraftState.held);
      expect(only(all, none).hold, EeDraftHold.noService);
      expect(only(all, two).hold, EeDraftHold.needsUnit);
      expect(only(all, gone).hold, EeDraftHold.serviceClosed);
    },
  );

  test(
    'a refusal is listed with its subject and code — the draft row itself is gone',
    () async {
      final id = await store.write(workspaceId: 'W-OWN', subject: 'Bir fazla');
      // What the engine does with a refused create (EE-051): park it with the
      // person's words, then rebase — the local row goes.
      final pending = await db.select(db.pendingMutations).getSingle();
      await db
          .into(db.rejectedMutations)
          .insert(
            RejectedMutationsCompanion.insert(
              id: pending.id,
              workspaceId: 'W-OWN',
              entityType: 'ee_ticket_draft',
              entityId: id,
              operation: 'create',
              patchJson: Value(pending.patchJson),
              errorCode: const Value('DRAFT_LIMIT_REACHED'),
              rejectedAt: DateTime.now().toUtc(),
            ),
          );
      await pushed(id);
      await (db.delete(db.ticketDrafts)..where((d) => d.id.equals(id))).go();

      final all = await settle();
      final refused = only(all, pending.id);
      expect(refused.state, EeDraftState.rejected);
      expect(refused.subject, 'Bir fazla');
      expect(refused.errorCode, 'DRAFT_LIMIT_REACHED');
      // And a refused draft is NOT "sent", though it vanished from the list.
      expect(all.where((s) => s.state == EeDraftState.sent), isEmpty);

      await store.forgetRejected(pending.id);
      expect(await settle(), isEmpty);
    },
  );

  test(
    'a tombstone with no refusal behind it is a request now: sent',
    () async {
      final id = await store.write(
        workspaceId: 'W-OWN',
        subject: 'Kompresör gece durdu',
        serviceId: 'S-ONE',
      );
      await settle();
      // The conversion: the push applied, the pull brought the tombstone.
      await pushed(id);
      await (db.delete(db.ticketDrafts)..where((d) => d.id.equals(id))).go();

      final all = await settle();
      expect(all.single.state, EeDraftState.sent);
      expect(all.single.subject, 'Kompresör gece durdu');
    },
  );

  test(
    'a refused EDIT of a draft that then became a request: both are said',
    () async {
      final id = await store.write(
        workspaceId: 'W-OWN',
        subject: 'Kompresör',
        serviceId: 'S-ONE',
      );
      await settle();
      // The edit reached a desk that had already filed the draft.
      await db
          .into(db.rejectedMutations)
          .insert(
            RejectedMutationsCompanion.insert(
              id: 'M-EDIT',
              workspaceId: 'W-OWN',
              entityType: 'ee_ticket_draft',
              entityId: id,
              operation: 'update',
              patchJson: const Value('{"subject":"Kompresör durdu"}'),
              errorCode: const Value('SYNC_ENTITY_DELETED'),
              rejectedAt: DateTime.now().toUtc(),
            ),
          );
      await pushed(id);
      await (db.delete(db.ticketDrafts)..where((d) => d.id.equals(id))).go();

      final all = await settle();
      expect(
        all.singleWhere((s) => s.state == EeDraftState.sent).subject,
        'Kompresör',
      );
      expect(
        all.singleWhere((s) => s.state == EeDraftState.rejected).subject,
        'Kompresör durdu',
      );
    },
  );

  test(
    'another home is another list — not every draft of the last one sent',
    () async {
      await store.write(workspaceId: 'W-OWN', subject: 'Eski alan');
      expect(await settle(), hasLength(1));
      container.read(_home.notifier).set('W-NEW');
      expect(await settle(), isEmpty);
    },
  );

  test("another workspace's drafts are not this person's list", () async {
    await store.write(workspaceId: 'W-UNIT', subject: 'Başka çekmece');
    expect(await settle(), isEmpty);
  });
}
