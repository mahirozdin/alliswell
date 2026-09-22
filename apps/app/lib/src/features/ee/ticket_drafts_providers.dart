import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ulid.dart';
import '../../sync/db/database.dart';
import '../../sync/outbox.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

/// EE-216 — the request somebody writes with no signal.
///
/// ── WHY THIS STORE EXISTS AT ALL ──────────────────────────────────────
///
/// Every other requester-facing thing in this app is REST (`my_tickets_api`
/// has one method, `list`), and that is not an oversight — ADR-0011 measured
/// it. A sync type registers once and serializes one way, so a ticket cannot
/// have a requester's shape and an agent's shape; and the ticket push path
/// needs membership of the workspace the ticket lives in, which a requester
/// does not have and never will.
///
/// So the offline half is a DIFFERENT type, living in the person's OWN
/// workspace, and the server turns it into a real request when it arrives.
/// That is why this file writes to drift and the outbox while its neighbours
/// call HTTP: a draft is the one requester-side thing that has to survive
/// having no network, because that is the entire feature.
class TicketDraftStore {
  TicketDraftStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  /// Writes a draft locally and queues it. Returns its id.
  ///
  /// The optimistic row and its mutation go in ONE transaction, like every
  /// other local write here: a draft on screen with nothing queued behind it
  /// would be a note the person believes is safe and that nothing will ever
  /// send.
  ///
  /// `serviceId` is optional, and that is the point rather than a convenience.
  /// Somebody standing in front of a stopped machine knows what they saw; they
  /// may not know which service it files under, and the catalogue may not even
  /// be on the device. A draft with no service is KEPT — the server holds it
  /// unsent instead of refusing it, and it converts the moment they pick one.
  Future<String> write({
    required String workspaceId,
    required String subject,
    String? body,
    String? serviceId,
  }) async {
    final id = newUlid();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.ticketDrafts)
          .insert(
            TicketDraftsCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              // No team: the device has none to give. The server stamps the
              // one the host proves and the next pull fills this in.
              subject: Value(subject),
              body: Value(body),
              serviceId: Value(serviceId),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'ee_ticket_draft',
        entityId: id,
        operation: 'create',
        patch: {'subject': subject, 'body': ?body, 'serviceId': ?serviceId},
      );
    });
    _poke();
    return id;
  }

  /// Edits an unsent draft — including naming the service that finally lets it
  /// convert.
  ///
  /// Refuses to touch a draft that is already gone: the server tombstones one
  /// the moment it becomes a request, so a row still here with a `ticketId` is
  /// a replica that has not caught up, and editing it would queue a mutation
  /// the server answers `SYNC_ENTITY_DELETED` to. Better to do nothing than to
  /// let somebody type into a note that has already been filed.
  Future<bool> edit(
    String draftId, {
    String? subject,
    String? body,
    String? serviceId,
  }) async {
    final row = await (_db.select(
      _db.ticketDrafts,
    )..where((d) => d.id.equals(draftId))).getSingleOrNull();
    if (row == null || row.ticketId != null) return false;

    final patch = <String, dynamic>{
      'subject': ?subject,
      'body': ?body,
      'serviceId': ?serviceId,
    };
    if (patch.isEmpty) return false;

    await _db.transaction(() async {
      await (_db.update(
        _db.ticketDrafts,
      )..where((d) => d.id.equals(draftId))).write(
        TicketDraftsCompanion(
          subject: subject == null ? const Value.absent() : Value(subject),
          body: body == null ? const Value.absent() : Value(body),
          serviceId: serviceId == null
              ? const Value.absent()
              : Value(serviceId),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await enqueueMutation(
        _db,
        workspaceId: row.workspaceId,
        entityType: 'ee_ticket_draft',
        entityId: draftId,
        operation: 'update',
        patch: patch,
      );
    });
    _poke();
    return true;
  }
}

/// The drafts still waiting, newest first.
///
/// Filtered to the UNSENT ones: a row that has a `ticketId` has already become
/// a request and its tombstone is on the way, so showing it would tell somebody
/// their report is still sitting on the phone when it is not. The list is the
/// person's own — a draft lives in the author's workspace, so there is nobody
/// else's to leak.
final unsentTicketDraftsProvider = StreamProvider<List<TicketDraftRecord>>((
  ref,
) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) {
    return Stream.value(const <TicketDraftRecord>[]);
  }
  final db = ref.watch(databaseProvider);
  final query = db.select(db.ticketDrafts)
    ..where((d) => d.workspaceId.equals(workspace.id) & d.ticketId.isNull())
    ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
  return query.watch();
});

final ticketDraftStoreProvider = Provider<TicketDraftStore>((ref) {
  return TicketDraftStore(ref.watch(databaseProvider));
});
