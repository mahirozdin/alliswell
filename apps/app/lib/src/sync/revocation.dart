import 'package:drift/drift.dart';

import 'db/database.dart';

/// What a device does when a workspace stops being its business
/// (EE-058 — ADR-0008's D2 addendum).
///
/// ## Why there is no new protocol field here
///
/// The backlog asked for a "resnapshot required" flag on the pull response.
/// Under D1 (a unit IS a workspace) that flag cannot exist and does not need
/// to:
///
///   • It cannot, because `requireWorkspaceMember` answers a UNIFORM 403 for
///     "exists, not yours" and for "never existed" — that uniformity is what
///     stops the endpoint being used to enumerate a company's workspaces. A
///     200 carrying a flag would leak exactly what the uniformity protects.
///   • It need not, because losing visibility and losing a workspace are the
///     SAME event under D1. The 403 is already the signal, already coded, and
///     on this route it has exactly one meaning: pull passes no `roles`, so
///     `AUTH_WORKSPACE_FORBIDDEN` here can only mean "you are not a member".
///
/// The defect this file fixes is on the client. The engine used to treat that
/// permanent 403 exactly like being offline — `catch (_)`, back off, retry —
/// so a person removed from a unit kept its entire replica on their device
/// indefinitely while looping against a condition that would never change.
///
/// ## The two halves
///
/// DROP the replica: the content is the server's, and access to it is gone.
/// KEEP what the person wrote: unsent mutations are parked in
/// `rejected_mutations` (EE-051's seam) rather than deleted, because "you lost
/// access" is a reason to stop syncing somebody's typing, never a reason to
/// destroy it.

/// The server's code for "this workspace is not yours".
const String kWorkspaceForbiddenCode = 'AUTH_WORKSPACE_FORBIDDEN';

/// Tables whose rows hang off a task and carry no workspace of their own.
/// Listed here rather than discovered, because a foreign key is a fact about
/// MEANING that the column names only hint at.
const Map<String, String> _taskChildren = {
  'reminders': 'task_id',
  'checklist_items': 'task_id',
  'task_tag_rows': 'task_id',
  'apple_event_links': 'task_id',
};

const Map<String, String> _noteChildren = {'note_link_rows': 'note_id'};

/// Device-local records that are NOT replicated content and therefore survive
/// a revocation: the person's own diagnostic logs. Losing access to a team's
/// workspace is not a reason to erase the evidence of what their own phone
/// did.
const Set<String> _deviceLocal = {'alarm_events', 'share_events'};

/// Every table this module has an opinion about. [revocationCoverage] compares
/// it with the live schema so a table added in a later version cannot quietly
/// escape the wipe — the failure mode of forgetting one is confidential
/// content left on a device that should no longer hold it.
Set<String> revocationCoverage(AwDatabase db) => {
  for (final table in db.allTables)
    if (table.columnsByName.containsKey('workspace_id')) table.actualTableName,
  ..._taskChildren.keys,
  ..._noteChildren.keys,
  ..._deviceLocal,
};

/// Parks this workspace's unsent mutations, then removes its replica.
///
/// Returns how many mutations were parked — the caller surfaces that, because
/// "your device stopped syncing X, and N unsent changes are waiting" is a
/// different sentence from "your device stopped syncing X".
///
/// One transaction: a half-wiped replica with a live sync cursor would pull
/// incrementally onto rubble.
Future<int> revokeWorkspaceReplica(AwDatabase db, String workspaceId) async {
  return db.transaction(() async {
    final pending = await (db.select(
      db.pendingMutations,
    )..where((m) => m.workspaceId.equals(workspaceId))).get();

    for (final row in pending) {
      await db
          .into(db.rejectedMutations)
          .insert(
            RejectedMutationsCompanion.insert(
              id: row.id,
              workspaceId: workspaceId,
              entityType: row.entityType,
              entityId: row.entityId,
              operation: row.operation,
              patchJson: Value(row.patchJson),
              errorCode: const Value(kWorkspaceForbiddenCode),
              rejectedAt: DateTime.now().toUtc(),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }

    // Everything the workspace owns, discovered from the schema rather than
    // from a list somebody has to remember to update.
    for (final table in db.allTables) {
      if (!table.columnsByName.containsKey('workspace_id')) continue;
      // `rejected_mutations` is the one workspace-scoped table that STAYS:
      // it is what the person wrote, and it is the whole point of parking.
      if (table.actualTableName == 'rejected_mutations') continue;
      await db.customStatement(
        'DELETE FROM ${table.actualTableName} WHERE workspace_id = ?',
        [workspaceId],
      );
    }

    // Children keyed by their parent, now orphaned. Deleting by "parent is
    // gone" rather than by workspace keeps this correct even for a row whose
    // parent was already missing.
    for (final entry in _taskChildren.entries) {
      await db.customStatement(
        'DELETE FROM ${entry.key} '
        'WHERE ${entry.value} NOT IN (SELECT id FROM tasks)',
      );
    }
    for (final entry in _noteChildren.entries) {
      await db.customStatement(
        'DELETE FROM ${entry.key} '
        'WHERE ${entry.value} NOT IN (SELECT id FROM notes)',
      );
    }

    return pending.length;
  });
}
