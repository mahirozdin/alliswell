import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/api_exception.dart';
import '../../core/day_boundary.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart' show apiClientProvider;
import '../ee/assignments_providers.dart';
import '../workspaces/workspaces.dart';
import 'data/quick_add_apply.dart';
import 'data/series_store.dart';
import 'data/task.dart';
import 'data/task_scope.dart';
import 'data/task_store.dart';
import 'data/tasks_api.dart';

export 'data/task_store.dart' show kPlanningStatuses;
export 'data/task_scope.dart' show TaskScope;

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd, and the sync engine converges with the server in
/// the background.
final taskStoreProvider = Provider<TaskStore>(
  (ref) => TaskStore(
    ref.watch(databaseProvider),
    () => pokeSync(ref),
    userId: ref.watch(currentUserIdProvider),
  ),
);

/// The series store (OPH-207): rules are local-first like everything else, but
/// the OCCURRENCES are server-owned — the client never generates one.
final seriesStoreProvider = Provider<SeriesStore>(
  (ref) => SeriesStore(ref.watch(databaseProvider), () => pokeSync(ref)),
);

/// One series' rule, live from the replica — what the Repeat row's sentence and
/// the dialog's initial state read.
final taskSeriesProvider = StreamProvider.autoDispose
    .family<TaskSeriesModel?, String>((ref, seriesId) {
      ref.watch(syncEngineProvider);
      return ref.watch(seriesStoreProvider).watch(seriesId);
    });

/// Which tasks the person's OWN lists show — Home, the Board, Completed, the
/// Inbox (see [TaskScope]). Readers watch it through `selectAsync`: a reload
/// of the workspace list that lands on the same scope must not restart every
/// list and alarm built on it.
///
/// A person on their own: their one workspace, exactly what these lists read
/// before. A member of an organisation: their work across every workspace
/// they are in — Home is their list, not a shared view of a unit.
///
/// Every scope it resolves is also left for the background turn
/// ([rememberTaskScope]): alarms and the widget are built from it there too.
final taskScopeProvider = FutureProvider<TaskScope?>((ref) async {
  final all = await ref.watch(workspacesProvider.future);
  final me = ref.watch(currentUserIdProvider);
  final shared = sharedWorkspacesOf(all);
  final TaskScope? scope;
  if (shared.isNotEmpty) {
    if (me == null) return null;
    scope = TaskScope.mine([for (final w in shared) w.id], me);
  } else {
    final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
    scope = workspaceId == null ? null : TaskScope.workspace(workspaceId);
  }
  if (scope != null && me != null) {
    unawaited(rememberTaskScope(scope, userId: me));
  }
  return scope;
});

/// Every open task of the person's lists — feeds Home and the widget. Live
/// from the local replica; watching it keeps background sync running (every
/// synced workspace: a member's Home gathers from all of them).
///
/// Since OPH-185 it also carries **what was completed today** (DESIGN §20 C1):
/// finishing a task is feedback, not disappearance. The boundary comes from
/// [dayBoundaryProvider], so the list empties itself at the next local midnight
/// without anyone reopening the app.
final openTasksProvider = StreamProvider<List<Task>>((ref) async* {
  ref.watch(syncEnginesProvider);
  final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
  if (scope == null) {
    yield const [];
    return;
  }
  final dayStart = await ref.watch(dayBoundaryProvider.future);
  yield* ref
      .watch(taskStoreProvider)
      .watchOpenIn(scope, completedSince: dayStart);
});

/// Completed tasks, newest first, one page at a time (OPH-186).
/// The family value is the page COUNT — the screen grows it as the user
/// scrolls, so each request supersedes the previous one and the list never
/// jitters between pages.
final completedTasksProvider = StreamProvider.family<List<Task>, int>((
  ref,
  pages,
) async* {
  ref.watch(syncEnginesProvider);
  final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
  if (scope == null) {
    yield const [];
    return;
  }
  yield* ref
      .watch(taskStoreProvider)
      .watchCompletedIn(scope, limit: pages * kCompletedPageSize);
});

/// How many rows one scroll-step of the Completed archive adds.
const int kCompletedPageSize = 50;

/// EVERY status — the Board's source (OPH-168): its columns can include the
/// terminal statuses (completed/cancelled/archived) planning lists hide.
final boardTasksProvider = StreamProvider<List<Task>>((ref) async* {
  ref.watch(syncEnginesProvider);
  final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
  if (scope == null) {
    yield const [];
    return;
  }
  yield* ref.watch(taskStoreProvider).watchAllIn(scope);
});

/// Whether this scope has ever held a task (OPH-404) — see
/// [TaskStore.watchHasAnyIn]. No scope yet answers true: the first-run face
/// is only for an account the replica KNOWS is empty.
final hasAnyTaskProvider = StreamProvider<bool>((ref) async* {
  ref.watch(syncEnginesProvider);
  final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
  if (scope == null) {
    yield true;
    return;
  }
  yield* ref.watch(taskStoreProvider).watchHasAnyIn(scope);
});

/// How long Home waits for a first pull before it trusts an empty replica
/// anyway (OPH-394). Long enough for a cold sync of a busy account; short
/// enough that a device with no server is not left on a skeleton forever —
/// the offline strip says the rest.
const kFirstPullWait = Duration(seconds: 10);

/// Whether a workspace of the task scope has not finished its first pull yet
/// (OPH-394, polish 2 R-06). A replica that has never pulled is empty because
/// nothing arrived, not because the account is: Home shows a skeleton then,
/// never "No tasks yet". Read from the sync state rows the engines write
/// (`lastPulledAt` is stamped by every applied pull), so it holds for every
/// engine of a member's scope. A scope still loading counts as waiting; no
/// scope at all (signed out, no workspace) does not.
final firstPullPendingProvider = StreamProvider.autoDispose<bool>((ref) {
  final scope = ref.watch(taskScopeProvider);
  if (!scope.hasValue) return Stream.value(!scope.hasError);
  final ids = scope.value?.workspaceIds ?? const <String>[];
  if (ids.isEmpty) return Stream.value(false);
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.syncStates,
  )..where((s) => s.workspaceId.isIn(ids))).watch().map((rows) {
    final pulled = {
      for (final r in rows)
        if (r.lastPulledAt != null) r.workspaceId,
    };
    return !ids.every(pulled.contains);
  }).distinct();
});

/// Turns true [kFirstPullWait] after Home first asked (OPH-394). Auto-dispose:
/// nobody watches it once the first pull has landed, and its timer goes with
/// it.
final firstPullWaitOverProvider = StreamProvider.autoDispose<bool>((ref) {
  final controller = StreamController<bool>()..add(false);
  final timer = Timer(kFirstPullWait, () => controller.add(true));
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The calendar day selected on Home/Calendar (shared so the selection is
/// consistent across both tabs). Null = no selection.
class SelectedDayController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void select(DateTime? day) => state = day;
}

final selectedDayProvider = NotifierProvider<SelectedDayController, DateTime?>(
  SelectedDayController.new,
);

/// Creates a task where the person's lists will find it: in the workspace on
/// screen, and — in an organisation's workspaces — ON the person who made it,
/// so it is their work from the first frame (the owner's rule for a task added
/// from Home: the selected workspace, assigned to its author).
///
/// [read] is a `ref.read` tear-off: this runs from widgets and from notifiers.
/// Returns the new id, or null when there is no workspace to write in.
Future<String?> createOwnTask(
  T Function<T>(ProviderListenable<T>) read,
  Map<String, dynamic> body,
) async {
  final workspaceId = await read(activeWorkspaceIdProvider.future);
  if (workspaceId == null) return null;
  final id = await read(taskStoreProvider).create(workspaceId, body);
  await claimIfShared(read, workspaceId: workspaceId, taskId: id);
  return id;
}

/// The second half of [createOwnTask], for a path that creates the task itself
/// (the AI quick add creates first and enriches after): in an organisation's
/// workspaces, put the author on it. A person on their own has no one to be
/// assigned by — nothing happens.
Future<void> claimIfShared(
  T Function<T>(ProviderListenable<T>) read, {
  required String workspaceId,
  required String taskId,
}) async {
  final me = read(currentUserIdProvider);
  if (me == null || !read(inSharedWorkspacesProvider)) return;
  await read(
    assignmentStoreProvider,
  ).assign(workspaceId: workspaceId, taskId: taskId, userId: me);
}

/// The Inbox list (quick capture). Home covers the chronological views.
class InboxTasksController extends StreamNotifier<List<Task>> {
  @override
  Stream<List<Task>> build() async* {
    ref.watch(syncEnginesProvider);
    final scope = await ref.watch(taskScopeProvider.selectAsync((s) => s));
    if (scope == null) {
      yield const [];
      return;
    }
    yield* ref.watch(taskStoreProvider).watchInboxIn(scope);
  }

  /// The capture rule lives in [createCapture], shared with voice capture
  /// (OPH-376).
  Future<void> quickAdd(QuickAddSubmission submission) async {
    final id = await createCapture(ref.read, submission);
    if (id == null) throw StateError('No workspace available');
  }
}

final inboxTasksProvider =
    StreamNotifierProvider<InboxTasksController, List<Task>>(
      InboxTasksController.new,
    );

/// Open tasks of one project — the project detail Tasks tab. Carries today's
/// completed rows too, on the same rule as Home (OPH-185). A project lives in
/// one workspace, the one on screen, and its tab shows every task in it.
final projectTasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  projectId,
) async* {
  ref.watch(syncEngineProvider);
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  if (workspaceId == null) {
    yield const [];
    return;
  }
  final dayStart = await ref.watch(dayBoundaryProvider.future);
  yield* ref
      .watch(taskStoreProvider)
      .watchProjectTasks(workspaceId, projectId, completedSince: dayStart);
});

/// Single-task detail (tags + checklist included) — live on every part.
/// Null while the row is absent from the replica (OPH-419): the screen tells
/// "not pulled yet" from "deleted while open".
final taskDetailProvider = StreamProvider.family<Task?, String>((ref, taskId) {
  ref.watch(syncEnginesProvider);
  return ref.watch(taskStoreProvider).watchDetail(taskId);
});

/// The subtasks a task's detail lists (OPH-394, E-07).
final subtasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  parentTaskId,
) {
  ref.watch(syncEnginesProvider);
  return ref.watch(taskStoreProvider).watchSubtasks(parentTaskId);
});

/// Why a task's detail has nothing to show (OPH-392, E-17).
enum TaskAbsence {
  /// The server has no such task for this person: deleted, or never theirs.
  gone,

  /// The task is not on this device and the server could not be asked.
  unreachable,
}

/// The detail screen's answer while its row is absent from the replica.
///
/// A link to a task that is not on the device used to wait on its row forever: a cold web start on `/#/tasks/<id>`
/// for a task deleted since, or not yet pulled, was an endless spinner. Asked
/// once: when the server still has the task, null — the pull brings it, and
/// the spinner is the truth; otherwise the reason, which the screen says.
/// A malformed id (400) counts as gone too.
final taskAbsenceProvider = FutureProvider.autoDispose
    .family<TaskAbsence?, String>((ref, taskId) async {
      final store = ref.watch(taskStoreProvider);
      if (await store.detailOnce(taskId) != null) return null;
      try {
        await TasksApi(ref.watch(apiClientProvider)).get(taskId);
        return null;
      } on ApiException catch (error) {
        return switch (error.statusCode) {
          // 400: the id is not a task id at all (a mistyped `/tasks/typo`
          // link) — the API rejects it before looking, and no pull will ever
          // bring it, so it is as gone as a deleted one.
          400 || 403 || 404 => TaskAbsence.gone,
          null => TaskAbsence.unreachable,
          _ => null,
        };
      }
    });

/// Checkbox behavior shared by every task tile: complete an open task,
/// reopen a completed one. The replica updates instantly; sync follows.
Future<void> toggleTaskCompleted(WidgetRef ref, Task task) {
  final store = ref.read(taskStoreProvider);
  return task.isCompleted ? store.reopen(task.id) : store.complete(task.id);
}
