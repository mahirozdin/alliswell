import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ulid.dart';
import '../../sync/db/database.dart';
import '../../sync/outbox.dart';
import '../../sync/providers.dart';
import 'new_ticket_providers.dart';

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
  ///
  /// `assetId` (EE-281) is the machine it was written about, when it was
  /// written from a machine's card — the case this store exists for, since
  /// that card opens in a basement (EE-238). The server links it when the
  /// draft becomes a request, or leaves it behind if the machine is no longer
  /// the team's; either way the report itself arrives.
  Future<String> write({
    required String workspaceId,
    required String subject,
    String? body,
    String? serviceId,
    String? assetId,
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
              assetId: Value(assetId),
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
        patch: {
          'subject': subject,
          'body': ?body,
          'serviceId': ?serviceId,
          'assetId': ?assetId,
        },
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

  /// Puts a refusal away once its person has read it (EE-225). Local only:
  /// the parked row is this device's memory of what it was told, not
  /// anything the server holds.
  Future<void> forgetRejected(String rejectedId) => (_db.delete(
    _db.rejectedMutations,
  )..where((r) => r.id.equals(rejectedId))).go();
}

/// The drafts still waiting, newest first.
///
/// Filtered to the UNSENT ones: a row that has a `ticketId` has already become
/// a request and its tombstone is on the way, so showing it would tell somebody
/// their report is still sitting on the phone when it is not. The list is the
/// person's own — a draft lives in the author's workspace, so there is nobody
/// else's to leak.
///
/// EE-225 re-pointed it from the workspace ON SCREEN to the person's OWN one
/// (`draftWorkspaceIdProvider`): that is the only place a draft may live
/// (EE-243), and an agent looking at their unit would otherwise have seen an
/// empty list while their drafts sat in their own space.
final unsentTicketDraftsProvider = StreamProvider<List<TicketDraftRecord>>((
  ref,
) {
  final home = ref.watch(draftWorkspaceIdProvider);
  if (home == null) return Stream.value(const <TicketDraftRecord>[]);
  final db = ref.watch(databaseProvider);
  final query = db.select(db.ticketDrafts)
    ..where((d) => d.workspaceId.equals(home) & d.ticketId.isNull())
    ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
  return query.watch();
});

/// The drafts whose last write is still in the outbox — on the phone.
final pendingDraftIdsProvider = StreamProvider<Set<String>>((ref) {
  final home = ref.watch(draftWorkspaceIdProvider);
  if (home == null) return Stream.value(const <String>{});
  final db = ref.watch(databaseProvider);
  return (db.select(db.pendingMutations)..where(
        (m) =>
            m.workspaceId.equals(home) & m.entityType.equals('ee_ticket_draft'),
      ))
      .watch()
      .map((rows) => {for (final row in rows) row.entityId});
});

/// Drafts the server REFUSED (EE-051 parked them with their words), newest
/// first. A refused create is gone from the replica — the rebase removed it —
/// so this is the only place its subject still exists.
final rejectedDraftsProvider = StreamProvider<List<RejectedMutation>>((ref) {
  final home = ref.watch(draftWorkspaceIdProvider);
  if (home == null) return Stream.value(const <RejectedMutation>[]);
  final db = ref.watch(databaseProvider);
  return (db.select(db.rejectedMutations)
        ..where(
          (r) =>
              r.workspaceId.equals(home) &
              r.entityType.equals('ee_ticket_draft'),
        )
        ..orderBy([(r) => OrderingTerm.desc(r.rejectedAt)]))
      .watch();
});

/// Drafts that became requests THIS SESSION — remembered in memory only.
///
/// A converted draft comes back as a tombstone and leaves the device with its
/// text cleared (EE-216: two copies of a fault report is one more place it
/// leaks from). So "sent" is not something the replica can say afterwards;
/// it is a TRANSITION, seen here as it happens: a draft that was unsent and
/// is gone. The subject is held for the session and never written anywhere.
///
/// Gone is not yet SENT: a refused create is rebased away too. Which one it
/// was is asked of the refusals TABLE at the moment of vanishing — not of the
/// refusals' own stream, which can reach this notifier a beat after the row
/// is gone (measured: it listed a refused draft as sent). The table is never
/// too early, because the engine parks a refusal before its rebase removes
/// the row (`_parkRejection`). Only a refused CREATE counts: a refused edit
/// of a draft that then converted is still a request.
class SentDrafts extends Notifier<List<({String id, String subject})>> {
  Map<String, String> _seen = const {};

  @override
  List<({String id, String subject})> build() {
    // Another home is another list, not every draft of the last one "gone".
    final home = ref.watch(draftWorkspaceIdProvider);
    _seen = const {};
    ref.listen(unsentTicketDraftsProvider, (_, next) {
      final rows = next.value;
      if (rows == null) return;
      final now = {
        for (final row in rows)
          if (row.workspaceId == home) row.id: row.subject ?? '',
      };
      final gone = {
        for (final entry in _seen.entries)
          if (!now.containsKey(entry.key)) entry.key: entry.value,
      };
      _seen = now;
      if (gone.isNotEmpty) unawaited(_settle(gone));
    }, fireImmediately: true);
    return const [];
  }

  Future<void> _settle(Map<String, String> gone) async {
    final db = ref.read(databaseProvider);
    final refused =
        (await (db.select(db.rejectedMutations)..where(
                  (r) =>
                      r.entityId.isIn(gone.keys) & r.operation.equals('create'),
                ))
                .get())
            .map((r) => r.entityId)
            .toSet();
    if (!ref.mounted) return;
    final sent = [
      for (final entry in gone.entries)
        if (!refused.contains(entry.key)) (id: entry.key, subject: entry.value),
    ];
    if (sent.isNotEmpty) state = [...sent, ...state];
  }
}

final sentDraftsProvider =
    NotifierProvider<SentDrafts, List<({String id, String subject})>>(
      SentDrafts.new,
    );

/// EE-225 wires the poke EE-216 left for its first caller: a draft written
/// in the workspace on screen is pushed by that workspace's engine at once.
/// One written in the author's own space while another is on screen is the
/// courier's (`draftCourierProvider`), which starts on the outbox itself.
final ticketDraftStoreProvider = Provider<TicketDraftStore>((ref) {
  return TicketDraftStore(
    ref.watch(databaseProvider),
    onMutation: () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  );
});

/// Where a draft stands (EE-225).
enum EeDraftState {
  /// Its last write is still in the outbox: it has not left the phone.
  onDevice,

  /// The server has it and has not turned it into a request — see [EeDraftHold].
  held,

  /// The server refused it; the code says why.
  rejected,

  /// It became a request this session (see [SentDrafts]).
  sent,
}

/// Why a draft the server holds has not become a request yet.
///
/// Read from what the device knows — the draft and the catalogue — because
/// the server keeps a draft it cannot convert rather than refusing it
/// (EE-216) and says nothing about why. Each reason is one the conversion
/// actually stops on (`convertDraft`): no service, a service the door no
/// longer accepts, or several units and a draft that cannot name one.
enum EeDraftHold { noService, serviceClosed, needsUnit, waiting }

class EeDraftStatus {
  const EeDraftStatus({
    required this.id,
    required this.state,
    required this.subject,
    this.serviceId,
    this.hold,
    this.errorCode,
  });

  /// The draft's id — or, for a refusal, the parked row's (what to forget).
  final String id;
  final EeDraftState state;
  final String subject;
  final String? serviceId;
  final EeDraftHold? hold;

  /// The server's code for a refusal.
  final String? errorCode;
}

/// Every draft of this person's and where it stands, for the screen that
/// lists them above their requests: refusals first (they need reading), then
/// what is still on the phone or held, then what went through this session.
final draftStatusesProvider = Provider<List<EeDraftStatus>>((ref) {
  final unsent = ref.watch(unsentTicketDraftsProvider).value ?? const [];
  final pending = ref.watch(pendingDraftIdsProvider).value ?? const {};
  final rejected = ref.watch(rejectedDraftsProvider).value ?? const [];
  final sent = ref.watch(sentDraftsProvider);
  final catalog = ref.watch(eeCatalogProvider).value;

  EeDraftHold holdOf(TicketDraftRecord draft) {
    final serviceId = draft.serviceId;
    if (serviceId == null) return EeDraftHold.noService;
    // Without the catalogue the device cannot tell which reason it is, and
    // guessing one would be a sentence the screen cannot stand behind.
    if (catalog == null) return EeDraftHold.waiting;
    final service = catalog.services
        .where((candidate) => candidate.id == serviceId)
        .firstOrNull;
    if (service == null) return EeDraftHold.serviceClosed;
    if (service.units.length > 1) return EeDraftHold.needsUnit;
    return EeDraftHold.waiting;
  }

  return [
    for (final row in rejected)
      EeDraftStatus(
        id: row.id,
        state: EeDraftState.rejected,
        subject: _patchValue(row.patchJson, 'subject') ?? '',
        serviceId: _patchValue(row.patchJson, 'serviceId'),
        errorCode: row.errorCode,
      ),
    for (final draft in unsent)
      EeDraftStatus(
        id: draft.id,
        state: pending.contains(draft.id)
            ? EeDraftState.onDevice
            : EeDraftState.held,
        subject: draft.subject ?? '',
        serviceId: draft.serviceId,
        hold: pending.contains(draft.id) ? null : holdOf(draft),
      ),
    for (final done in sent)
      EeDraftStatus(
        id: done.id,
        state: EeDraftState.sent,
        subject: done.subject,
      ),
  ];
});

String? _patchValue(String? patchJson, String key) {
  if (patchJson == null) return null;
  try {
    final value = (jsonDecode(patchJson) as Map<String, dynamic>)[key];
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}
