import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ulid.dart';
import 'db/database.dart';
import 'sync_contract.dart';

/// Records one local write in the outbox (OPH-055). Call inside the same
/// drift transaction as the optimistic local row change so the replica and
/// its outbox can never disagree. Returns the client mutation id.
///
/// `baseRevision` (OPH-268) is the entity revision this write started from —
/// what the editor saw. The server merges against it; without one it behaves
/// exactly as it did before.
Future<String> enqueueMutation(
  AwDatabase db, {
  required String workspaceId,
  required String entityType,
  required String entityId,
  required String operation,
  Map<String, dynamic>? patch,
  int? baseRevision,
}) async {
  // OPH-300 — the push contract, checked where EVERY write passes.
  //
  // The server refuses a whole mutation on the first key it does not know, and
  // answers `SYNC_UNKNOWN_FIELD` — a code that names neither the key nor the
  // entity. OPH-299 was six weeks of that: the app put `fromTaskId` in a
  // four-key patch and recurrence simply never worked, while the only thing
  // that could have caught it lived in a closure on the other side of the wire.
  //
  // An `assert` rather than a throw, and here rather than in a test of its own,
  // because the failure mode is coverage: a per-call-site test only guards the
  // sites somebody remembered to write one for. This runs for every write in
  // every test and every debug build, names the offending key, and is compiled
  // out of release — where a server that refuses is the right authority anyway.
  assert(() {
    final problem = awSyncPatchProblem(entityType, operation, patch);
    if (problem != null) throw AssertionError(problem);
    return true;
  }());

  // OPH-268 — coalesce a note's unpushed updates.
  //
  // The editor autosaves the WHOLE body on a 1.5 s idle debounce, so a typing
  // session that outruns the push queues one row per save, each carrying the
  // same base. That is finding #3's N-copy explosion seen from the client:
  // the server answers each of them separately, and the ones behind the first
  // are all "conflicts" against a note their own device just wrote.
  //
  // Merging them keeps the OLDEST base (what the editing session actually
  // started from) and the NEWEST body — which is precisely one edit.
  //
  // OPH-488 (ADR-0072): ONLY into a row no push has carried yet. The server
  // keys idempotency on the row's id, so a newer body merged into a row it had
  // already recorded came back as the old answer and was lost without a trace
  // — the second half of the 2026-11-18 report. A save behind a sent row is a
  // row of its own; the engine moves its base forward when the sent one is
  // applied, which is what keeps it from conflicting with its own device.
  if (operation == 'update' && entityType == 'note' && patch != null) {
    final unsent =
        await (db.select(db.pendingMutations)..where(
              (m) =>
                  m.entityId.equals(entityId) &
                  m.entityType.equals(entityType) &
                  m.sentAt.isNull(),
            ))
            .get();
    unsent.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // A note whose create has not left yet: the create carries the newest
    // body itself, so there is no update to send — and no base to get wrong
    // (H1, the base-0 false conflict).
    final create = unsent.where((m) => m.operation == 'create').firstOrNull;
    if (create != null) {
      await _mergeInto(db, create, patch, baseRevision: null);
      return create.id;
    }
    final updates = unsent.where((m) => m.operation == 'update').toList();
    if (updates.isNotEmpty) {
      final head = updates.first;
      // The base stays the oldest one; a later save did not start from a
      // newer server state, it continued the same session.
      await _mergeInto(
        db,
        head,
        patch,
        baseRevision: head.baseRevision ?? baseRevision,
      );
      // Any extra rows beyond the head collapse into it.
      for (final row in updates.skip(1)) {
        await (db.delete(
          db.pendingMutations,
        )..where((m) => m.id.equals(row.id))).go();
      }
      return head.id;
    }
  }

  final id = newUlid();
  await db
      .into(db.pendingMutations)
      .insert(
        PendingMutationsCompanion.insert(
          id: id,
          workspaceId: workspaceId,
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          patchJson: Value(patch == null ? null : jsonEncode(patch)),
          localUpdatedAt: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          baseRevision: Value(baseRevision),
        ),
      );
  return id;
}

/// Rewrites an UNSENT outbox row with [patch] layered over its own.
Future<void> _mergeInto(
  AwDatabase db,
  PendingMutation row,
  Map<String, dynamic> patch, {
  required int? baseRevision,
}) async {
  final merged = <String, dynamic>{
    ...(row.patchJson == null
        ? const <String, dynamic>{}
        : jsonDecode(row.patchJson!) as Map<String, dynamic>),
    ...patch,
  };
  await (db.update(
    db.pendingMutations,
  )..where((m) => m.id.equals(row.id) & m.sentAt.isNull())).write(
    PendingMutationsCompanion(
      patchJson: Value(jsonEncode(merged)),
      localUpdatedAt: Value(DateTime.now().toUtc()),
      baseRevision: Value(baseRevision),
    ),
  );
}

/// Whether an outbox row of a note carries its body or title — the rows that
/// decide the note's base (OPH-489). A pin, archive or project move does not.
bool isNoteContentRow(PendingMutation row) {
  if (row.operation == 'create') return true;
  if (row.operation != 'update' || row.patchJson == null) return false;
  final patch = jsonDecode(row.patchJson!) as Map<String, dynamic>;
  return patch.containsKey('contentMarkdown') ||
      patch.containsKey('contentDelta') ||
      patch.containsKey('title');
}

/// The note's queued creates and body/title updates (OPH-489, OPH-490): while
/// one exists, the replica's body is newer than anything the server sent.
Future<List<PendingMutation>> queuedNoteContentRows(
  AwDatabase db,
  String noteId,
) async {
  final rows =
      await (db.select(db.pendingMutations)..where(
            (m) =>
                m.entityType.equals('note') &
                m.entityId.equals(noteId) &
                m.operation.isIn(const ['create', 'update']),
          ))
          .get();
  return rows.where(isNoteContentRow).toList();
}

/// Whether any [queuedNoteContentRows] exists — stops at the first one.
Future<bool> hasQueuedNoteContent(AwDatabase db, String noteId) async {
  final rows =
      await (db.select(db.pendingMutations)..where(
            (m) =>
                m.entityType.equals('note') &
                m.entityId.equals(noteId) &
                m.operation.isIn(const ['create', 'update']),
          ))
          .get();
  return rows.any(isNoteContentRow);
}
