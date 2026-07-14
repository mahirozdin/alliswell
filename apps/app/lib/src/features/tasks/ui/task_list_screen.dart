import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../screens/home_shell.dart';
import '../../../sections.dart';
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
          const Divider(height: 1),
          Expanded(
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(inboxTasksProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyInbox()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppSection.inbox.selectedIcon,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('Inbox zero', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(AppSection.inbox.description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
