import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../screens/home_shell.dart';
import '../../../sections.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import 'quick_add_bar.dart';
import 'task_tile.dart';

/// Inbox (OPH-037, slimmed in feedback round 1): quick capture without dates —
/// the chronological views live on Home/Calendar now.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(inboxTasksProvider);
    return Scaffold(
      appBar: buildSectionAppBar(context, AppSection.inbox.title),
      body: Column(
        children: [
          QuickAddBar(
            key: const Key('quick-add'),
            hintText: 'Quick add to Inbox…',
            onAdd: (title) =>
                ref.read(inboxTasksProvider.notifier).quickAdd(title),
          ),
          Expanded(
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: '$error',
                onRetry: () => ref.invalidate(inboxTasksProvider),
              ),
              data: (items) => items.isEmpty
                  ? AwEmptyState(
                      icon: AppSection.inbox.selectedIcon,
                      title: 'Inbox zero',
                      message: AppSection.inbox.description,
                    )
                  : ListView.builder(
                      padding: awListPadding(context),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          TaskTile(task: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
