import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../../../core/error_messages.dart';
import '../../../core/list_sort.dart';
import '../../../core/persisted_prefs.dart';
import '../../../widgets/sort_menu.dart';
import '../../home/task_grouping.dart' show orderTasks;
import '../../tasks/data/task_sort.dart';
import '../../tasks/providers.dart';
import '../../tasks/ui/task_tile.dart';
import '../assignments_providers.dart';

/// "Assigned to me" (EE-068) — item 9's filter, as its own list.
///
/// It NARROWS the workspace's tasks rather than querying its own: the task
/// list already knows how to sort, group and render a task, and a second
/// source would eventually disagree with the first about what a task looks
/// like. So this watches the ordinary task provider and keeps the ids the
/// assignment table names.
///
/// Read entirely from the replica, so it works with no connection — which is
/// the point of having delivered assignments through sync at all.
///
/// ── ORDERED THE WAY EVERY OTHER TASK LIST IS (EE-241) ──────────────────
///
/// Home's choices (`kTaskSortChoices`), Home's comparator (`orderTasks` —
/// finished work still sinks, DESIGN §20 C1) and Home's PREFERENCE
/// (`tasksSortProvider`): the project Tasks tab already shares that one choice
/// (OPH-338, §34 L6), and a third task list ordered a third way would be the
/// thing to explain. Until now this list came in whatever order the workspace
/// query happened to return, which nobody chose.
class EeAssignedToMeScreen extends ConsumerWidget {
  const EeAssignedToMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myAssignedTaskIdsProvider).value ?? const <String>{};
    final tasks = ref.watch(openTasksProvider);
    final sort = AwSortState.parse(
      ref.watch(tasksSortProvider),
      kTaskSortChoices,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('ee.assign.mineTitle'.tr()),
        actions: [
          AwSortMenuButton(
            key: const Key('assigned-to-me-sort'),
            choices: kTaskSortChoices,
            sort: sort,
            onChanged: (next) =>
                ref.read(tasksSortProvider.notifier).set(next.encode()),
          ),
        ],
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (all) {
          final rows = orderTasks(
            all.where((task) => mine.contains(task.id)),
            sort,
          );
          if (rows.isEmpty) {
            return AwEmptyState(
              icon: Icons.assignment_ind_outlined,
              title: 'ee.assign.mineEmptyTitle'.tr(),
              message: 'ee.assign.mineEmptyBody'.tr(),
            );
          }
          return ListView.builder(
            padding: awListPadding(context),
            itemCount: rows.length,
            itemBuilder: (context, index) => TaskTile(task: rows[index]),
          );
        },
      ),
    );
  }
}
