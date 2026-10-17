import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/swipe_actions.dart';
import '../../ai/data/ai_quick_add.dart';
import '../../ee/assignments_providers.dart';
import '../../ee/ticket_work_providers.dart';
import '../../ee/ui/assignee_avatars.dart';
import '../../ee/ui/ticket_work_section.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_badge.dart';
import '../../tags/tags.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../data/task_when.dart';
import '../providers.dart';
import 'repeat_row.dart';
import 'task_visuals.dart';
import '../../../widgets/status_views.dart';

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
    this.showUnit = true,
    this.swipeToDelete = true,
    this.trailingAction,
    this.onTagTap,
  });

  final Task task;
  final bool dimmed;
  final bool highlighted;

  /// Whether to show the project badge at the row's far right (OPH-104).
  /// Off inside a project's own Tasks tab, where every row is that project.
  final bool showProjectBadge;

  /// Whether to name the unit the task lives in, when the person works in
  /// several (EE-296, [unitLabelsProvider]). Off inside a project, which
  /// lives in one.
  final bool showUnit;

  /// OPH-184: the swipe-to-delete affordance. Off on the board, whose
  /// horizontal pager owns the horizontal gesture (DESIGN §19 D6).
  final bool swipeToDelete;

  /// An extra control before the status icon — the Completed screen's
  /// "Reopen", for instance. Rows without one are unchanged.
  final Widget? trailingAction;

  /// What a tap on an inline tag chip does (OPH-306), or null for a row whose
  /// chips are decoration.
  ///
  /// Nullable on purpose. The chips have been on every row since v0.4.0 and a
  /// user reported the obvious thing — that tapping one does nothing. The fix
  /// is not "make them all tappable": a chip that filters a list on a screen
  /// you are not looking at is worse than an inert one. Only the surfaces that
  /// can SHOW the resulting filter pass this (DESIGN §22).
  final ValueChanged<Tag>? onTagTap;

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
    // `select` keeps a change on one task from rebuilding the whole list.
    final assignees = ref.watch(
      workspaceAssigneesProvider.select(
        (value) => value.value?[task.id] ?? const <Assignee>[],
      ),
    );
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
    // OPH-372 (DESIGN §38 W3): how long it takes, while there is still work.
    // No "when" chip: the row is already filed under its "when" day, and the
    // due chip keeps saying the deadline.
    final duration = completed ? null : task.estimatedMinutes;
    final showDuration = duration != null && duration > 0;
    final isOverdue =
        due != null && !task.isCompleted && due.isBefore(DateTime.now());
    final priorityColor = taskPriorityColorOf(context, task.priority);
    final project = (showProjectBadge && task.projectId != null)
        ? ref.watch(projectsByIdProvider)[task.projectId]
        : null;
    // EE-297: the request this task is the work of, when it is one.
    final work = ref.watch(
      workTicketsByTaskProvider.select((value) => value.value?[task.id]),
    );
    // EE-296: Home gathers a member's work from every unit they are in, so a
    // row says which one — the same fact the switcher names for the screen.
    final unit = showUnit
        ? ref.watch(unitLabelsProvider.select((m) => m[task.workspaceId]))
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
          // C3, amended (OPH-301): the selected-day recession obeys the same rule. It
          // did not until a user reported the faded rows as unreadable — they
          // measured 2.13:1.
          : dimmed
          ? awRecededSurface(scheme)
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
        // Item 9's avatar row lives in the subtitle, so it sits UNDER the
        // title exactly as the mandate describes — and `assignees` joins the
        // subtitle's own emptiness test, because a task whose only extra fact
        // is "three people are on it" still owes the reader that row.
        subtitle:
            (due == null &&
                rowTags.isEmpty &&
                !snoozed &&
                !muted &&
                !recurring &&
                !showDuration &&
                assignees.isEmpty &&
                unit == null &&
                work == null)
            ? null
            : Wrap(
                spacing: AwSpace.x2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (work != null) AwTicketWorkChip(work: work),
                  if (unit != null)
                    Row(
                      key: Key('task-unit-${task.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspaces_outline,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            unit,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                  if (showDuration)
                    Semantics(
                      label: 'task.durationSemantic'.tr(
                        args: {'duration': awFormatDuration(duration)},
                      ),
                      excludeSemantics: true,
                      child: Row(
                        key: Key('task-duration-${task.id}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timelapse_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            awFormatDuration(duration),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final tag in rowTags.take(2))
                    _InlineTag(tag: tag, onTap: onTagTap),
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
                  // EE-068 — who is on it. Nothing at all when nobody is
                  // (item 9: "atanmamışsa boş"), and nothing ever on a build
                  // with no overlay, because the table is empty there.
                  if (assignees.isNotEmpty)
                    AwAssigneeAvatarRow(
                      key: Key('assignees-${task.id}'),
                      taskId: task.id,
                    ),
                ],
              ),
        // The STATUS icon is always the rightmost element so it forms a
        // consistent scan column; the badge, priority flag and urgent marker
        // fill in to its left (feedback round 5).
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Round 14: the ✨ quick add already created this row; the badge
            // is the async promise that the AI is still filling fields in.
            // `select` keeps the whole list from rebuilding per set change.
            if (ref.watch(
              aiEnrichingTasksProvider.select((s) => s.contains(task.id)),
            )) ...[
              Tooltip(
                message: 'ai.quickAdd.enriching'.tr(),
                child: SizedBox(
                  key: Key('ai-enriching-${task.id}'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                    semanticsLabel: 'ai.quickAdd.enriching'.tr(),
                  ),
                ),
              ),
              const SizedBox(width: AwSpace.x2),
            ],
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
    // EE-297: a request's work is not deleted — it is given back on the
    // request (the task detail's "Request" card); the server refuses it too.
    final swipeable = swipeToDelete && work == null
        ? AwSwipeToDelete(
            id: task.id,
            semanticLabel: 'task.deleteSemantic'.tr(
              args: {'title': task.title},
            ),
            onDelete: () => deleteTaskWithUndo(context, ref, task),
            child: tile,
          )
        : tile;

    // No `Opacity` here any more (DESIGN §20 C3): recession is the card's
    // colour, decided above, so the text keeps its full-strength token and
    // `contrast.py` can see the pair.
    return Padding(padding: kAwListRowPadding, child: swipeable);
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
  // completed occurrences are history (DESIGN §20 C3/§25 R7), and a delete
  // that quietly rewrote what the user already did would be the one thing
  // this feature must never do.
  // OPH-375 (DESIGN §25 R10): an after-completion series has one open
  // occurrence and nothing ahead of it, so there is no scope to ask about.
  // Deleting the open one stops the repeat in the same undoable commit — a
  // series without an open occurrence would never produce another. A finished
  // one is history and goes on its own.
  final afterCompletion =
      task.isRecurring && await isAfterCompletionTask(ref, task);
  if (afterCompletion && !task.isCompleted) {
    if (!context.mounted) return;
    final store = ref.read(taskStoreProvider);
    final seriesStore = ref.read(seriesStoreProvider);
    return awDeleteWithUndo(
      context,
      ref,
      id: task.id,
      message: 'task.deleted'.tr(args: {'title': task.title}),
      commit: () async {
        await store.delete(task.id);
        await seriesStore.stop(
          workspaceId: task.workspaceId,
          seriesId: task.seriesId!,
          fromDay: task.occurrenceDate,
        );
      },
    );
  }
  if (task.isRecurring && !afterCompletion) {
    if (!context.mounted) return;
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
  const _InlineTag({required this.tag, this.onTap});

  final Tag tag;
  final ValueChanged<Tag>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Row(
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
    final onTap = this.onTap;
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      label: 'tag.filterBySemantic'.tr(args: {'tag': tag.name}),
      child: InkWell(
        key: Key('tag-chip-${tag.id}'),
        onTap: () => onTap(tag),
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
        // A chip is a small target; the padding is what makes it a real one
        // without changing how the row reads.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: chip,
        ),
      ),
    );
  }
}
