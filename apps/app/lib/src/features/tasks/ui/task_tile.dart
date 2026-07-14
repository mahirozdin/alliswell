import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/task.dart';
import '../providers.dart';
import 'task_visuals.dart';

/// Shared task row: checkbox (complete/reopen), due date, colored priority
/// flag, status icon and urgent marker (feedback round 3). `highlighted`
/// tints the row (selected calendar day); `dimmed` fades it.
class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.dimmed = false,
    this.highlighted = false,
  });

  final Task task;
  final bool dimmed;
  final bool highlighted;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await toggleTaskCompleted(ref, task);
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update "${task.title}": $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = task.dueAt?.toLocal();
    final priorityColor = taskPriorityColor(task.priority);

    final tile = ListTile(
      tileColor: highlighted
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
          : null,
      leading: Checkbox(
        value: task.isCompleted,
        onChanged: (_) => _toggle(context, ref),
      ),
      title: Text(
        task.title,
        style: task.isCompleted
            ? theme.textTheme.bodyLarge?.copyWith(
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: due == null
          ? null
          : Text('Due ${due.toString().split('.').first}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (priorityColor != null) ...[
            Icon(Icons.flag, size: 18, color: priorityColor),
            const SizedBox(width: 6),
          ],
          Icon(
            taskStatusIcon(task.status),
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          if (task.isUrgent) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.notification_important,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ],
        ],
      ),
      onTap: () => context.push('/tasks/${task.id}'),
    );

    return dimmed ? Opacity(opacity: 0.45, child: tile) : tile;
  }
}
