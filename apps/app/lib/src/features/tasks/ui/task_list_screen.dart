import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../screens/home_shell.dart';
import '../../../sections.dart';
import '../../../sync/refresh.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/refreshable.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart';
import '../../notes/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../providers.dart';
import 'quick_add_bar.dart';
import 'task_create_sheet.dart';
import 'task_tile.dart' show deleteTaskWithUndo;

/// Inbox (reworked in OPH-107): a CAPTURE box, not a task list. Thoughts are
/// jotted fast and stay OUT of Home's planning lists until triaged — each row
/// offers Plan / Convert-to-note / Delete rather than a completion checkbox.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(inboxTasksProvider);
    Future<bool> refresh() => refreshSection(ref, AppSection.inbox);
    return Scaffold(
      appBar: buildSectionAppBar(
        context,
        AppSection.inbox.title,
        onRefresh: refresh,
      ),
      body: Column(
        children: [
          QuickAddBar(
            key: const Key('quick-add'),
            hintText: 'inbox.captureHint'.tr(),
            onAdd: (title) =>
                ref.read(inboxTasksProvider.notifier).quickAdd(title),
          ),
          Expanded(
            // OPH-171: the capture box is pullable — including its empty and
            // error states, which become the scrollable themselves (§15).
            child: AwRefresh(
              indicatorKey: const Key('inbox-refresh'),
              onRefresh: refresh,
              child: tasks.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AwErrorState(
                  message: localizedError(error),
                  onRetry: () => ref.invalidate(inboxTasksProvider),
                  physics: const AlwaysScrollableScrollPhysics(),
                ),
                data: (items) => items.isEmpty
                    ? AwEmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'inbox.captureTitle'.tr(),
                        message: 'inbox.captureBody'.tr(),
                        physics: const AlwaysScrollableScrollPhysics(),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: awListPadding(context),
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _CaptureTile(task: items[index]),
                      ),
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
            child: Text('common.cancel'.tr()),
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
      title: 'inbox.convertTitle'.tr(),
      body: 'inbox.convertBody'.tr(),
      action: 'inbox.convert'.tr(),
    )) {
      return;
    }
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    await ref.read(noteStoreProvider).create(workspaces.first.id, {
      'title': task.title,
    });
    await ref.read(taskStoreProvider).delete(task.id);
    messenger.showSnackBar(SnackBar(content: Text('inbox.movedToNotes'.tr())));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // OPH-184: delete moved out of the row's icon cluster and onto the swipe
      // — the same gesture and the same undo every other list now has. The
      // confirm dialog went with it (D3: a leaf delete you can take back does
      // not need one).
      child: AwSwipeToDelete(
        id: task.id,
        semanticLabel: 'task.deleteSemantic'.tr(args: {'title': task.title}),
        onDelete: () => deleteTaskWithUndo(context, ref, task),
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
                    tooltip: 'inbox.plan'.tr(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.event_outlined),
                    onPressed: () => _plan(context),
                  ),
                  IconButton(
                    key: const Key('capture-to-note'),
                    tooltip: 'inbox.convertToNote'.tr(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.description_outlined),
                    onPressed: () => _toNote(context, ref),
                  ),
                  // Kept, and it must be (DESIGN §19 D2): a mouse cannot swipe
                  // and neither can switch control. Same handler as the swipe.
                  IconButton(
                    key: const Key('capture-delete'),
                    tooltip: 'common.delete'.tr(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => deleteTaskWithUndo(context, ref, task),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
