import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/swipe_actions.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_badge.dart';
import '../../tags/tags.dart';
import '../data/task.dart';
import '../providers.dart';
import 'repeat_row.dart';
import 'task_visuals.dart';

/// The row form of the user's chosen format (OPH-174, DESIGN §17 D4): short
/// date + time, no year — "Jul 15, 09:30" in English, "15 Tem 09:30" in Turkish,
/// and whatever the user picked when they picked one.
String _formatDue(DateTime due, String dateFormat) =>
    awFormatShort(due, format: dateFormat);

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
    this.swipeToDelete = true,
    this.trailingAction,
  });

  final Task task;
  final bool dimmed;
  final bool highlighted;

  /// Whether to show the project badge at the row's far right (OPH-104).
  /// Off inside a project's own Tasks tab, where every row is that project.
  final bool showProjectBadge;

  /// OPH-184: the swipe-to-delete affordance. Off on the board, whose
  /// horizontal pager owns the horizontal gesture (DESIGN §19 D6).
  final bool swipeToDelete;

  /// An extra control before the status icon — the Completed screen's
  /// "Reopen", for instance. Rows without one are unchanged.
  final Widget? trailingAction;

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
    final dateFormat = ref.watch(dateFormatProvider);
    final due = task.dueAt?.toLocal();
    // OPH-185 (DESIGN §20 C2): a completed row stays, but it goes quiet — the
    // whole row, not just the title. Everything below reads this flag.
    final completed = task.isCompleted;
    // OPH-177: a snoozed alarm must SAY it is snoozed. Until now `snoozedUntil`
    // was invisible everywhere, so a silenced task looked like an armed one.
    // A finished task has no alarms at all (`alarmInstantsFor` returns none for
    // terminal statuses), so these chips would be claims that are not true.
    final snoozedUntil = task.snoozedUntil?.toLocal();
    final snoozed =
        !completed &&
        snoozedUntil != null &&
        snoozedUntil.isAfter(DateTime.now());
    // OPH-178: silenced-for-good says so, and offers the way back. An armed
    // looking task whose alarms are dead is the lie A5 forbids.
    final muted = !completed && task.alarmsMutedAt != null;
    // DESIGN §25 R6: one occurrence of a series says so — quietly, and never on
    // a finished row (a completed occurrence does not repeat; §20 C2).
    final recurring = !completed && task.isRecurring;
    final isOverdue =
        due != null && !task.isCompleted && due.isBefore(DateTime.now());
    final priorityColor = taskPriorityColorOf(context, task.priority);
    final project = (showProjectBadge && task.projectId != null)
        ? ref.watch(projectsByIdProvider)[task.projectId]
        : null;
    // OPH-165 (DESIGN T4): at most 2 inline tags + "+N" — typographic, so the
    // row never grows past its card rhythm.
    final tagsById = task.tagIds.isEmpty
        ? const <String, Tag>{}
        : ref.watch(tagsByIdProvider);
    final rowTags = [
      for (final id in task.tagIds)
        if (tagsById[id] case final Tag tag) tag,
    ];

    final tile = Card(
      clipBehavior: Clip.antiAlias,
      color: highlighted
          ? Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surface,
            )
          // C3: the calm treatment is a TOKEN, never an `Opacity` wrapper —
          // opacity makes contrast unmeasurable and silently voids §5's floors.
          // It is also deliberately distinct from `dimmed` (selected-day), so
          // two different meanings never share one look.
          : completed
          ? scheme.surfaceContainerLow
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
        subtitle:
            (due == null && rowTags.isEmpty && !snoozed && !muted && !recurring)
            ? null
            : Wrap(
                spacing: AwSpace.x2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (recurring)
                    Tooltip(
                      message: 'repeat.badgeTooltip'.tr(),
                      child: Icon(
                        Icons.repeat,
                        key: Key('repeat-badge-${task.id}'),
                        size: 16,
                        color: scheme.onSurfaceVariant,
                        semanticLabel: 'repeat.badgeTooltip'.tr(),
                      ),
                    ),
                  if (muted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'task.alarmsMuted'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          key: Key('unmute-${task.id}'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AwSpace.x2,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () => unmuteTaskAlarms(context, ref, task),
                          child: Text('task.unmuteAlarms'.tr()),
                        ),
                      ],
                    ),
                  if (snoozed)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.snooze,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'task.snoozedUntil'.tr(
                            args: {
                              'time': awFormatTime(
                                snoozedUntil,
                                format: dateFormat,
                              ),
                            },
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  if (due != null)
                    Text(
                      isOverdue
                          ? 'task.overdueDue'.tr(
                              args: {'date': _formatDue(due, dateFormat)},
                            )
                          : 'task.dueOn'.tr(
                              args: {'date': _formatDue(due, dateFormat)},
                            ),
                      style: isOverdue
                          ? theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            )
                          : completed
                          ? theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                  for (final tag in rowTags.take(2)) _InlineTag(tag: tag),
                  if (rowTags.length > 2)
                    Tooltip(
                      message: [
                        for (final tag in rowTags.skip(2)) '#${tag.name}',
                      ].join('  '),
                      child: Text(
                        '+${rowTags.length - 2}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
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
            // Hidden once done: the urgent marker is an ALARM state, and a
            // completed task has no alarms — leaving it on would be the kind of
            // claim DESIGN §11 A5 forbids, not just visual noise.
            if (task.isUrgent && !completed) ...[
              Icon(
                Icons.notification_important,
                size: 18,
                color: scheme.error,
                semanticLabel: 'task.urgent'.tr(),
              ),
              const SizedBox(width: AwSpace.x2),
            ],
            if (trailingAction != null) ...[
              trailingAction!,
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

    // OPH-184: the row's own delete affordance. `AwSwipeToDelete` also hides
    // the row while its delete is undoable, so every list agrees at once.
    final swipeable = swipeToDelete
        ? AwSwipeToDelete(
            id: task.id,
            semanticLabel: 'task.deleteSemantic'.tr(
              args: {'title': task.title},
            ),
            onDelete: () => deleteTaskWithUndo(context, ref, task),
            child: tile,
          )
        : tile;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: swipeable,
    );
    return dimmed ? Opacity(opacity: 0.45, child: row) : row;
  }
}

/// Delete a task the recoverable way (OPH-184, DESIGN §19 D3/D4) — shared by
/// the row swipe, the Inbox capture row and the detail screen's app bar, so
/// all three behave identically.
Future<void> deleteTaskWithUndo(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  // OPH-208: deleting ONE occurrence of a series is ambiguous, so it asks —
  // with two answers, not three. "Tümü" is deliberately absent: past and
  // completed occurrences are history (DESIGN §20 C4/§25 R7), and a delete
  // that quietly rewrote what the user already did would be the one thing
  // this feature must never do.
  if (task.isRecurring) {
    final scope = await showOccurrenceDeleteScope(context);
    if (scope == null) return;
    if (scope == 'future') {
      await ref
          .read(seriesStoreProvider)
          .stop(
            workspaceId: task.workspaceId,
            seriesId: task.seriesId!,
            fromDay: task.occurrenceDate,
          );
      return;
    }
  }
  if (!context.mounted) return;
  // Resolve the store NOW, while this widget is still mounted. The commit runs
  // ~5 s later from a timer, and by then the row is gone from the list and its
  // element is disposed — a captured `WidgetRef` would throw "Using ref when a
  // widget is about to or has been unmounted" and the delete would never
  // happen. (The repo has met this before: OPH-170's UnmountedRef lesson.)
  final store = ref.read(taskStoreProvider);
  return awDeleteWithUndo(
    context,
    ref,
    id: task.id,
    message: 'task.deleted'.tr(args: {'title': task.title}),
    commit: () => store.delete(task.id),
  );
}

/// Compact inline tag for list rows (T4): color dot + `#name` in caption ink.
/// Typography only — no pill container, so contrast and row height are the
/// subtitle's own.
class _InlineTag extends StatelessWidget {
  const _InlineTag({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(backgroundColor: tag.color, radius: 4),
        const SizedBox(width: 3),
        // Flexible so a long tag ellipsizes in a tight column (board cards,
        // narrow phones) instead of overflowing the row.
        Flexible(
          child: Text(
            '#${tag.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
