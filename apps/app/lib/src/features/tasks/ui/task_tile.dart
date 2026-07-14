import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/task.dart';
import '../providers.dart';

/// Shared task row: checkbox (complete/reopen), due date, urgent marker.
/// `highlighted` tints the row (selected calendar day); `dimmed` fades it.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = task.dueAt?.toLocal();

    final tile = ListTile(
      tileColor: highlighted
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
          : null,
      leading: Checkbox(
        value: task.isCompleted,
        onChanged: (_) => toggleTaskCompleted(ref, task),
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
      trailing: task.isUrgent
          ? Icon(Icons.notification_important, color: theme.colorScheme.error)
          : null,
      onTap: () => context.push('/tasks/${task.id}'),
    );

    return dimmed ? Opacity(opacity: 0.45, child: tile) : tile;
  }
}
