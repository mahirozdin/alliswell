import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ulid.dart';
import 'db/database.dart';

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
  if (operation == 'update' && entityType == 'note' && patch != null) {
    final existing =
        await (db.select(db.pendingMutations)..where(
              (m) =>
                  m.entityId.equals(entityId) &
                  m.entityType.equals(entityType) &
                  m.operation.equals('update'),
            ))
            .get();
    if (existing.isNotEmpty) {
      // Oldest row wins the identity — its clientMutationId may already be in
      // flight, and idempotency is keyed on it.
      existing.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final head = existing.first;
      final merged = <String, dynamic>{
        ...(head.patchJson == null
            ? const <String, dynamic>{}
            : jsonDecode(head.patchJson!) as Map<String, dynamic>),
        ...patch,
      };
      await (db.update(
        db.pendingMutations,
      )..where((m) => m.id.equals(head.id))).write(
        PendingMutationsCompanion(
          patchJson: Value(jsonEncode(merged)),
          localUpdatedAt: Value(DateTime.now().toUtc()),
          // The base stays the oldest one; a later save did not start from a
          // newer server state, it continued the same session.
          baseRevision: Value(head.baseRevision ?? baseRevision),
        ),
      );
      // Any extra rows beyond the head collapse into it.
      for (final row in existing.skip(1)) {
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
