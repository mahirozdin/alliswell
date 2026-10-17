import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/day_boundary.dart';
import '../../sync/providers.dart';
import '../ee/assignments_providers.dart';
import '../workspaces/workspaces.dart';
import 'data/quick_add_apply.dart';
import 'data/series_store.dart';
import 'data/task.dart';
import 'data/task_scope.dart';
import 'data/task_store.dart';

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
final taskDetailProvider = StreamProvider.family<Task, String>((ref, taskId) {
  ref.watch(syncEnginesProvider);
  return ref.watch(taskStoreProvider).watchDetail(taskId);
});

/// Checkbox behavior shared by every task tile: complete an open task,
/// reopen a completed one. The replica updates instantly; sync follows.
Future<void> toggleTaskCompleted(WidgetRef ref, Task task) {
  final store = ref.read(taskStoreProvider);
  return task.isCompleted ? store.reopen(task.id) : store.complete(task.id);
}
