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

/// The three task list flavors of the shell (OPH-037).
enum TaskListKind {
  inbox,
  today,
  upcoming;

  /// Server-side filters for this list. `today` includes overdue work
  /// (no lower bound); `upcoming` starts tomorrow.
  Map<String, dynamic> describe(DateTime now) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return switch (this) {
      TaskListKind.inbox => {
        'statuses': const ['inbox'],
      },
      TaskListKind.today => {'statuses': kOpenStatuses, 'dueTo': endOfToday},
      TaskListKind.upcoming => {
        'statuses': kOpenStatuses,
        'dueFrom': endOfToday.add(const Duration(seconds: 1)),
      },
    };
  }

  /// What the quick-add bar creates in this list context.
  Map<String, dynamic> quickAddBody(String title, DateTime now) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return switch (this) {
      TaskListKind.inbox => {'title': title, 'status': 'inbox'},
      TaskListKind.today => {
        'title': title,
        'dueAt': endOfToday.toUtc().toIso8601String(),
      },
      TaskListKind.upcoming => {
        'title': title,
        'dueAt': DateTime(
          now.year,
          now.month,
          now.day + 1,
          9,
        ).toUtc().toIso8601String(),
      },
    };
  }
}

class TasksController extends AsyncNotifier<List<Task>> {
  TasksController(this.kind);

  final TaskListKind kind;

  @override
  Future<List<Task>> build() async {
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) return const [];
    final filters = kind.describe(DateTime.now());
    final page = await ref
        .watch(tasksApiProvider)
        .list(
          workspaces.first.id,
          statuses: (filters['statuses'] as List?)?.cast<String>(),
          dueFrom: filters['dueFrom'] as DateTime?,
          dueTo: filters['dueTo'] as DateTime?,
          limit: 100,
        );
    return page.items;
  }

  Future<String> _workspaceId() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    return workspaces.first.id;
  }

  Future<void> _refetch() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> quickAdd(String title) async {
    final body = kind.quickAddBody(title.trim(), DateTime.now());
    await ref.read(tasksApiProvider).create(await _workspaceId(), body);
    await _refetch();
  }

  /// Checkbox toggle: complete an open task, reopen a completed one.
  Future<void> toggleCompleted(Task task) async {
    final api = ref.read(tasksApiProvider);
    if (task.isCompleted) {
      await api.reopen(task.id);
    } else {
      await api.complete(task.id);
    }
    await _refetch();
  }
}

final inboxTasksProvider = AsyncNotifierProvider<TasksController, List<Task>>(
  () => TasksController(TaskListKind.inbox),
);
final todayTasksProvider = AsyncNotifierProvider<TasksController, List<Task>>(
  () => TasksController(TaskListKind.today),
);
final upcomingTasksProvider =
    AsyncNotifierProvider<TasksController, List<Task>>(
      () => TasksController(TaskListKind.upcoming),
    );

AsyncNotifierProvider<TasksController, List<Task>> taskListProvider(
  TaskListKind kind,
) => switch (kind) {
  TaskListKind.inbox => inboxTasksProvider,
  TaskListKind.today => todayTasksProvider,
  TaskListKind.upcoming => upcomingTasksProvider,
};

/// Single-task detail (tags + checklist included). Mutating screens invalidate
/// this after writes.
final taskDetailProvider = FutureProvider.family<Task, String>(
  (ref, taskId) => ref.watch(tasksApiProvider).get(taskId),
);

/// Invalidate every task list + the given detail — call after any task write
/// from screen code (hence [WidgetRef]).
void invalidateTaskData(WidgetRef ref, {String? taskId}) {
  ref.invalidate(inboxTasksProvider);
  ref.invalidate(todayTasksProvider);
  ref.invalidate(upcomingTasksProvider);
  if (taskId != null) ref.invalidate(taskDetailProvider(taskId));
}
