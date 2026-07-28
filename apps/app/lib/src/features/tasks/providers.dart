import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/day_boundary.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/task.dart';
import 'data/task_store.dart';

export 'data/task_store.dart' show kPlanningStatuses;

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd, and the sync engine converges with the server in
/// the background.
final taskStoreProvider = Provider<TaskStore>(
  (ref) => TaskStore(
    ref.watch(databaseProvider),
    () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

/// Every open task of the workspace — feeds Home and the widget. Live from the
/// local replica; watching it keeps background sync running.
///
/// Since OPH-185 it also carries **what was completed today** (DESIGN §20 C1):
/// finishing a task is feedback, not disappearance. The boundary comes from
/// [dayBoundaryProvider], so the list empties itself at the next local midnight
/// without anyone reopening the app.
final openTasksProvider = StreamProvider<List<Task>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  final dayStart = await ref.watch(dayBoundaryProvider.future);
  yield* ref
      .watch(taskStoreProvider)
      .watchOpen(workspaces.first.id, completedSince: dayStart);
});

/// Completed tasks, newest first, one page at a time (OPH-186).
/// The family value is the page COUNT — the screen grows it as the user
/// scrolls, so each request supersedes the previous one and the list never
/// jitters between pages.
final completedTasksProvider = StreamProvider.family<List<Task>, int>((
  ref,
  pages,
) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  yield* ref
      .watch(taskStoreProvider)
      .watchCompleted(workspaces.first.id, limit: pages * kCompletedPageSize);
});

/// How many rows one scroll-step of the Completed archive adds.
const int kCompletedPageSize = 50;

/// EVERY status — the Board's source (OPH-168): its columns can include the
/// terminal statuses (completed/cancelled/archived) planning lists hide.
final boardTasksProvider = StreamProvider<List<Task>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  yield* ref.watch(taskStoreProvider).watchAll(workspaces.first.id);
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

/// The Inbox list (quick capture). Home covers the chronological views.
class InboxTasksController extends StreamNotifier<List<Task>> {
  @override
  Stream<List<Task>> build() async* {
    ref.watch(syncEngineProvider);
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) {
      yield const [];
      return;
    }
    yield* ref.watch(taskStoreProvider).watchInbox(workspaces.first.id);
  }

  Future<void> quickAdd(String title) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title.trim(),
      'status': 'inbox',
    });
  }
}

final inboxTasksProvider =
    StreamNotifierProvider<InboxTasksController, List<Task>>(
      InboxTasksController.new,
    );

/// Open tasks of one project — the project detail Tasks tab. Carries today's
/// completed rows too, on the same rule as Home (OPH-185).
final projectTasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  projectId,
) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  final dayStart = await ref.watch(dayBoundaryProvider.future);
  yield* ref
      .watch(taskStoreProvider)
      .watchProjectTasks(
        workspaces.first.id,
        projectId,
        completedSince: dayStart,
      );
});

/// Single-task detail (tags + checklist included) — live on every part.
final taskDetailProvider = StreamProvider.family<Task, String>((ref, taskId) {
  ref.watch(syncEngineProvider);
  return ref.watch(taskStoreProvider).watchDetail(taskId);
});

/// Checkbox behavior shared by every task tile: complete an open task,
/// reopen a completed one. The replica updates instantly; sync follows.
Future<void> toggleTaskCompleted(WidgetRef ref, Task task) {
  final store = ref.read(taskStoreProvider);
  return task.isCompleted ? store.reopen(task.id) : store.complete(task.id);
}
