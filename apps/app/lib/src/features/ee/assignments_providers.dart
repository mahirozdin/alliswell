import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ulid.dart';
import '../../sync/db/database.dart';
import '../../sync/outbox.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

/// Who is on a task, and what an avatar needs to draw them (EE-068).
///
/// Two rows joined: the assignment (EE-066) says WHO, the roster profile
/// (EE-017) says what they look like. The join may MISS, and that miss is a
/// state rather than an error — somebody removed from the unit keeps their
/// assignment until the server releases it, so their avatar becomes a neutral
/// tombstone instead of disappearing. A task that silently lost an assignee
/// would be worse than one that shows an unknown person: the work is still
/// theirs until somebody decides otherwise.
class Assignee {
  const Assignee({
    required this.assignmentId,
    required this.userId,
    this.displayName,
    this.initials,
    this.colorRgb,
  });

  final String assignmentId;
  final String userId;
  final String? displayName;
  final String? initials;
  final String? colorRgb;

  /// False when the roster has no row for this person any more.
  bool get isKnown => colorRgb != null;
}

/// Everyone on every task in the current workspace, keyed by task id.
///
/// ONE stream for the whole list, deliberately. A `family` per task would open
/// a query per visible row — two hundred of them on a long list — and the app
/// already has the answer to this shape: `aiEnrichingTasksProvider` is watched
/// with `select` so a change to one task does not rebuild the others. Rows do
/// the same here.
///
/// It is also the entitlement gate, by construction rather than by a check: on
/// a build with no overlay these tables are simply empty, so every row draws
/// nothing and no screen has to ask whether the feature exists.
final workspaceAssigneesProvider = StreamProvider<Map<String, List<Assignee>>>((
  ref,
) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) {
    return Stream.value(const <String, List<Assignee>>{});
  }
  final db = ref.watch(databaseProvider);
  final assignments = db.select(db.taskAssignments)
    ..where((a) => a.workspaceId.equals(workspace.id))
    ..orderBy([(a) => OrderingTerm.asc(a.assignedAt)]);
  return assignments
      .join([
        leftOuterJoin(
          db.memberProfiles,
          db.memberProfiles.userId.equalsExp(db.taskAssignments.userId) &
              db.memberProfiles.workspaceId.equalsExp(
                db.taskAssignments.workspaceId,
              ),
        ),
      ])
      .watch()
      .map((rows) {
        final out = <String, List<Assignee>>{};
        for (final row in rows) {
          final a = row.readTable(db.taskAssignments);
          final p = row.readTableOrNull(db.memberProfiles);
          (out[a.taskId] ??= []).add(
            Assignee(
              assignmentId: a.id,
              userId: a.userId,
              displayName: p?.displayName,
              initials: p?.initials,
              colorRgb: p?.colorRgb,
            ),
          );
        }
        return out;
      });
});

/// Everyone currently on ONE task — the detail screen's view, where a single
/// query is the right shape.
final taskAssigneesProvider = StreamProvider.family<List<Assignee>, String>((
  ref,
  taskId,
) {
  final db = ref.watch(databaseProvider);
  final assignments = db.select(db.taskAssignments)
    ..where((a) => a.taskId.equals(taskId))
    ..orderBy([(a) => OrderingTerm.asc(a.assignedAt)]);
  // A join, not two queries: drift watches BOTH tables through it, so a rename,
  // a colour change or a departure re-emits without the assignment row moving.
  return assignments
      .join([
        leftOuterJoin(
          db.memberProfiles,
          db.memberProfiles.userId.equalsExp(db.taskAssignments.userId) &
              db.memberProfiles.workspaceId.equalsExp(
                db.taskAssignments.workspaceId,
              ),
        ),
      ])
      .watch()
      .map(
        (rows) => rows.map((row) {
          final a = row.readTable(db.taskAssignments);
          final p = row.readTableOrNull(db.memberProfiles);
          return Assignee(
            assignmentId: a.id,
            userId: a.userId,
            displayName: p?.displayName,
            initials: p?.initials,
            colorRgb: p?.colorRgb,
          );
        }).toList(),
      );
});

/// The set of task ids assigned to the signed-in person, for the list filter.
///
/// A SET rather than a list of tasks: the Tasks screen already has its own
/// query with its own sorting and paging, and a second source of tasks would
/// be a second answer to "what is in this list". This only narrows it.
final myAssignedTaskIdsProvider = StreamProvider<Set<String>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (userId == null || workspace == null) {
    return Stream.value(const <String>{});
  }
  final db = ref.watch(databaseProvider);
  return (db.select(db.taskAssignments)..where(
        (a) => a.userId.equals(userId) & a.workspaceId.equals(workspace.id),
      ))
      .watch()
      .map((rows) => rows.map((r) => r.taskId).toSet());
});

/// The people this workspace can assign to — the roster, as the picker reads it.
final workspaceRosterProvider = StreamProvider<List<MemberProfile>>((ref) {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return const Stream.empty();
  final db = ref.watch(databaseProvider);
  return (db.select(db.memberProfiles)
        ..where((p) => p.workspaceId.equals(workspace.id))
        ..orderBy([(p) => OrderingTerm.asc(p.displayName)]))
      .watch();
});

/// Assign and release, offline-first (EE-066 made the type push-capable).
///
/// The optimistic row and its outbox mutation go in ONE transaction, the way
/// every other local write in this app does: a replica that showed an avatar
/// with no queued mutation behind it would be a promise nothing keeps.
///
/// Authority is NOT checked here. The server decides on arrival and a refusal
/// comes back as an ordinary rejection, which EE-051 parks rather than drops —
/// so a member who tries to assign somebody they may not gets their write
/// back, not silence. The UI still hides the control it knows is not allowed
/// (DESIGN §22: no dead buttons), but hiding is a courtesy and the server is
/// the rule.
class AssignmentStore {
  AssignmentStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  Future<String> assign({
    required String workspaceId,
    required String taskId,
    required String userId,
  }) async {
    final id = newUlid();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.taskAssignments)
          .insert(
            TaskAssignmentsCompanion.insert(
              id: id,
              workspaceId: workspaceId,
              taskId: taskId,
              userId: userId,
              assignedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await enqueueMutation(
        _db,
        workspaceId: workspaceId,
        entityType: 'ee_task_assignment',
        entityId: id,
        operation: 'create',
        patch: {'taskId': taskId, 'userId': userId},
      );
    });
    _poke();
    return id;
  }

  Future<void> release(String assignmentId) async {
    final row = await (_db.select(
      _db.taskAssignments,
    )..where((a) => a.id.equals(assignmentId))).getSingleOrNull();
    if (row == null) {
      return;
    }
    await _db.transaction(() async {
      // Deleted locally, not flagged: a release IS a tombstone on the server
      // too, so the replica takes the same shape rather than inventing a
      // second one that the next pull would have to reconcile.
      await (_db.delete(
        _db.taskAssignments,
      )..where((a) => a.id.equals(assignmentId))).go();
      await enqueueMutation(
        _db,
        workspaceId: row.workspaceId,
        entityType: 'ee_task_assignment',
        entityId: assignmentId,
        operation: 'delete',
      );
    });
    _poke();
  }
}

final assignmentStoreProvider = Provider<AssignmentStore>(
  (ref) => AssignmentStore(
    ref.watch(databaseProvider),
    onMutation: () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);
