import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../screens/home_shell.dart';
import '../../../sections.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../notes/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../providers.dart';
import 'quick_add_bar.dart';
import 'task_create_sheet.dart';

/// Inbox (reworked in OPH-107): a CAPTURE box, not a task list. Thoughts are
/// jotted fast and stay OUT of Home's planning lists until triaged — each row
/// offers Plan / Convert-to-note / Delete rather than a completion checkbox.
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
            hintText: 'Capture a thought…',
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
                  ? const AwEmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Inbox is for capturing',
                      message:
                          'Type above and sort later — captures never show on '
                          'Home until you plan them.',
                    )
                  : ListView.builder(
                      padding: awListPadding(context),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _CaptureTile(task: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single captured thought. No checkbox — you don't "complete" an idea; you
/// triage it. Tapping the row (or Plan) opens the planning sheet; giving it a
/// date or project there promotes it to a real task and it leaves the Inbox.
class _CaptureTile extends ConsumerWidget {
  const _CaptureTile({required this.task});

  final Task task;

  Future<void> _plan(BuildContext context) =>
      showTaskCreateSheet(context, task: task);

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _toNote(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(
      context,
      title: 'Convert to a note?',
      body: 'This capture moves to Notes as a new note.',
      action: 'Convert',
    )) {
      return;
    }
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    await ref.read(noteStoreProvider).create(workspaces.first.id, {
      'title': task.title,
    });
    await ref.read(taskStoreProvider).delete(task.id);
    messenger.showSnackBar(const SnackBar(content: Text('Moved to Notes')));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await _confirm(
      context,
      title: 'Delete capture?',
      body: '“${task.title}” will be removed.',
      action: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await ref.read(taskStoreProvider).delete(task.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _plan(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x3,
              AwSpace.x1,
              AwSpace.x1,
              AwSpace.x1,
            ),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: AwSpace.x3),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('capture-plan'),
                  tooltip: 'Plan',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.event_outlined),
                  onPressed: () => _plan(context),
                ),
                IconButton(
                  key: const Key('capture-to-note'),
                  tooltip: 'Convert to note',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.description_outlined),
                  onPressed: () => _toNote(context, ref),
                ),
                IconButton(
                  key: const Key('capture-delete'),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
