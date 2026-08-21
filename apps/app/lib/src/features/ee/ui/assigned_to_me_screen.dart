import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../../../core/error_messages.dart';
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
class EeAssignedToMeScreen extends ConsumerWidget {
  const EeAssignedToMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myAssignedTaskIdsProvider).value ?? const <String>{};
    final tasks = ref.watch(openTasksProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.assign.mineTitle'.tr())),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (all) {
          final rows = all.where((task) => mine.contains(task.id)).toList();
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
