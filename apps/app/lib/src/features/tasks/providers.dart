import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/task.dart';
import 'data/tasks_api.dart';

final tasksApiProvider = Provider<TasksApi>(
  (ref) => TasksApi(ref.watch(apiClientProvider)),
);

/// Statuses that belong on planning lists (terminal ones are filtered out).
const kOpenStatuses = ['inbox', 'open', 'scheduled', 'in_progress', 'waiting'];

/// Every open task of the workspace — feeds Home and Calendar (feedback
/// round 1). One page of 200 covers v1; local-first sync (Epic 06) replaces
/// this with a replica later.
final openTasksProvider = FutureProvider<List<Task>>((ref) async {
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) return const [];
  final page = await ref
      .watch(tasksApiProvider)
      .list(workspaces.first.id, statuses: kOpenStatuses, limit: 200);
  return page.items;
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
class InboxTasksController extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() async {
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) return const [];
    final page = await ref
        .watch(tasksApiProvider)
        .list(workspaces.first.id, statuses: const ['inbox'], limit: 100);
    return page.items;
  }

  Future<void> quickAdd(String title) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    await ref.read(tasksApiProvider).create(workspaces.first.id, {
      'title': title.trim(),
      'status': 'inbox',
    });
    ref.invalidateSelf();
    await future;
  }
}

final inboxTasksProvider =
    AsyncNotifierProvider<InboxTasksController, List<Task>>(
      InboxTasksController.new,
    );

/// Open tasks of one project — the project detail Tasks tab.
final projectTasksProvider = FutureProvider.family<List<Task>, String>((
  ref,
  projectId,
) async {
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) return const [];
  final page = await ref
      .watch(tasksApiProvider)
      .list(
        workspaces.first.id,
        statuses: kOpenStatuses,
        projectId: projectId,
        limit: 100,
      );
  return page.items;
});

/// Single-task detail (tags + checklist included). Mutating screens invalidate
/// this after writes.
final taskDetailProvider = FutureProvider.family<Task, String>(
  (ref, taskId) => ref.watch(tasksApiProvider).get(taskId),
);

/// Invalidate every task list + the given detail — call after any task write
/// from screen code (hence [WidgetRef]).
void invalidateTaskData(WidgetRef ref, {String? taskId}) {
  ref.invalidate(inboxTasksProvider);
  ref.invalidate(openTasksProvider);
  ref.invalidate(projectTasksProvider);
  if (taskId != null) ref.invalidate(taskDetailProvider(taskId));
}

/// Checkbox behavior shared by every task tile: complete an open task,
/// reopen a completed one, then refresh all task data.
Future<void> toggleTaskCompleted(WidgetRef ref, Task task) async {
  final api = ref.read(tasksApiProvider);
  if (task.isCompleted) {
    await api.reopen(task.id);
  } else {
    await api.complete(task.id);
  }
  invalidateTaskData(ref, taskId: task.id);
}
