import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_badge.dart';
import '../data/task.dart';
import '../providers.dart';
import 'task_visuals.dart';

/// Locale-aware short date + 24h time (OPH-123). English renders identically to
/// the old hand-rolled format ("Jul 15, 09:30"); other locales get their own
/// month name and ordering via `intl` (date data initialized in `main()` /
/// `flutter_test_config.dart`).
String _formatDue(DateTime due) {
  final date = DateFormat.MMMd(
    AwI18n.instance.locale.toLanguageTag(),
  ).format(due);
  final time =
      '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  return '$date, $time';
}

/// Shared task row: a rounded surface card with checkbox (complete/reopen),
/// due date (overdue turns red), colored priority flag, status icon and
/// urgent marker. `highlighted` tints the row (selected calendar day);
/// `dimmed` fades it.
class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.dimmed = false,
    this.highlighted = false,
    this.showProjectBadge = true,
  });

  final Task task;
  final bool dimmed;
  final bool highlighted;

  /// Whether to show the project badge at the row's far right (OPH-104).
  /// Off inside a project's own Tasks tab, where every row is that project.
  final bool showProjectBadge;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await toggleTaskCompleted(ref, task);
    } on Object catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('task.couldNotUpdate'.tr(args: {'title': task.title})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = task.dueAt?.toLocal();
    final isOverdue =
        due != null && !task.isCompleted && due.isBefore(DateTime.now());
    final priorityColor = taskPriorityColorOf(context, task.priority);
    final project = (showProjectBadge && task.projectId != null)
        ? ref.watch(projectsByIdProvider)[task.projectId]
        : null;

    final tile = Card(
      clipBehavior: Clip.antiAlias,
      color: highlighted
          ? Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surface,
            )
          : null,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
            )
          : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (_) => _toggle(context, ref),
          semanticLabel: task.isCompleted
              ? 'task.reopenNamed'.tr(args: {'title': task.title})
              : 'task.completeNamed'.tr(args: {'title': task.title}),
        ),
        title: Text(
          task.title,
          style: task.isCompleted
              ? theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.lineThrough,
                  color: scheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: due == null
            ? null
            : Text(
                isOverdue
                    ? 'task.overdueDue'.tr(args: {'date': _formatDue(due)})
                    : 'task.dueOn'.tr(args: {'date': _formatDue(due)}),
                style: isOverdue
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
        // The STATUS icon is always the rightmost element so it forms a
        // consistent scan column; the badge, priority flag and urgent marker
        // fill in to its left (feedback round 5).
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (project != null) ...[
              ProjectBadge(name: project.name, color: project.color),
              const SizedBox(width: AwSpace.x2),
            ],
            if (priorityColor != null) ...[
              Icon(
                Icons.flag,
                size: 18,
                color: priorityColor,
                semanticLabel: 'task.prioritySemantic'.tr(
                  args: {'priority': taskPriorityLabel(task.priority)},
                ),
              ),
              const SizedBox(width: AwSpace.x2),
            ],
            if (task.isUrgent) ...[
              Icon(
                Icons.notification_important,
                size: 18,
                color: scheme.error,
                semanticLabel: 'task.urgent'.tr(),
              ),
              const SizedBox(width: AwSpace.x2),
            ],
            Icon(
              taskStatusIcon(task.status),
              size: 18,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'task.statusSemantic'.tr(
                args: {'status': taskStatusLabel(task.status)},
              ),
            ),
          ],
        ),
        onTap: () => context.push('/tasks/${task.id}'),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: tile,
    );
    return dimmed ? Opacity(opacity: 0.45, child: row) : row;
  }
}
