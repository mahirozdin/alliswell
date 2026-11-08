import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format.dart';
import '../../../core/linkify.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/list_detail.dart';
import '../../../widgets/meta_line.dart';
import '../../../widgets/swipe_actions.dart';
import '../../ai/data/ai_quick_add.dart';
import '../../ee/assignments_providers.dart';
import '../../ee/ticket_work_providers.dart';
import '../../ee/ui/assignee_avatars.dart';
import '../../ee/ui/ticket_work_section.dart';
import '../../projects/data/project.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_badge.dart';
import '../../tags/tags.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../data/task_defaults.dart';
import '../providers.dart';
import 'repeat_row.dart';
import 'task_visuals.dart';
import '../../../widgets/status_views.dart';
import '../../../theme/typography.dart';

/// The row form of the user's chosen format (OPH-174, DESIGN §17 D4): short
/// date + time, no year — "Jul 15, 09:30" in English, "15 Tem 09:30" in Turkish,
/// and whatever the user picked when they picked one.
String _formatDue(DateTime due, String dateFormat) =>
    awFormatShort(due, format: dateFormat);

/// Shared task row (DESIGN §46): check circle on the title's first line, a
/// title of at most two lines, ONE meta line that only shows what differs from
/// a new task's defaults, and at most one item on the right. `highlighted`
/// tints the row (selected calendar day); `dimmed` recedes it.
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

  /// The screen's own control for this row — the Completed screen's
  /// "Reopen", the board's "Move". It takes the row's one right-hand slot
  /// (§46 R6); the project then moves into the meta line.
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
    // OPH-405: the desktop's task pane, when this row is under one.
    final pane = AwListDetailScope.maybeOf(context, kAwTaskPane);
    final inPane = pane != null && pane.selectedId == task.id;
    AwListOrder.registerRow(context, task.id);
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
    // OPH-165 (DESIGN T4), amended by OPH-400: the first tag + "+N" —
    // typographic, so the meta line stays one line.
    final tagsById = task.tagIds.isEmpty
        ? const <String, Tag>{}
        : ref.watch(tagsByIdProvider);
    final rowTags = [
      for (final id in task.tagIds)
        if (tagsById[id] case final Tag tag) tag,
    ];

    // OPH-400 (DESIGN §46): the row's anatomy. Everything below is measured
    // by `task_row_test.dart`; read §46 before moving a piece.
    final roles = context.awText;
    final scaler = MediaQuery.textScalerOf(context);
    // R5: above 1.3× the row goes vertical — the title takes the full width
    // and the meta line wraps under it (U-12).
    final vertical = scaler.scale(1) > kAwRowVerticalTextScale;
    final metaStyle = roles.meta.copyWith(color: scheme.onSurfaceVariant);
    final glyph = scaler.clamp(maxScaleFactor: 1.5).scale(14);
    final titleStyle = completed
        ? roles.rowTitle.copyWith(
            decoration: TextDecoration.lineThrough,
            color: scheme.onSurfaceVariant,
          )
        : roles.rowTitle;
    final rowTitle = awRowTitle(task.title);
    // R1: the check circle sits on the title's FIRST line, not the card's
    // middle. Its 48 pt target is centred on that line; the title starts 12 pt
    // down, or lower when a large line would push the target off the card.
    final lineHeight =
        scaler.scale(titleStyle.fontSize!) * (titleStyle.height ?? 1.0);
    final lineCenter = math.max(
      kMinInteractiveDimension / 2,
      AwSpace.x3 + lineHeight / 2,
    );
    final titleTop = lineCenter - lineHeight / 2;

    final Widget titleText = Text(
      rowTitle.text,
      key: Key('task-title-${task.id}'),
      // R4: two lines and "…" (three in the vertical row); the detail screen
      // shows the rest. A bare link is one line.
      maxLines: rowTitle.isLink ? 1 : (vertical ? 3 : 2),
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );
    final Widget title = rowTitle.isLink
        ? Row(
            children: [
              Icon(
                Icons.link,
                key: Key('task-link-${task.id}'),
                size: scaler.clamp(maxScaleFactor: 1.5).scale(16),
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AwSpace.x1),
              Expanded(child: titleText),
            ],
          )
        : titleText;

    // R6: at most ONE thing on the right. A screen's own action wins (the
    // Completed screen's "Reopen", the board's "Move"), then who is on it,
    // then the project. Whatever loses its place moves into the meta line.
    final Widget? right =
        trailingAction ??
        (assignees.isNotEmpty
            ? AwAssigneeAvatarRow(
                key: Key('assignees-${task.id}'),
                taskId: task.id,
              )
            // Polish 3 J-03: the badge only when the WHOLE name fits a
            // compact pill; a longer name goes to the meta line, never cut.
            : project != null && ProjectBadge.fits(context, project.name)
            ? ProjectBadge(name: project.name, color: project.color)
            : null);
    final projectInMeta = project != null && (right is! ProjectBadge);
    final assigneesInMeta = assignees.isNotEmpty && trailingAction != null;

    // R3: one meta line — date · repeat · alarm · status · priority · first
    // tag +N, then the rest — and only what differs from a new task's
    // defaults (open, medium, urgent-armed; §26 C1) earns a glyph.
    Widget glyphIcon(IconData icon, {Key? key, Color? color, String? label}) =>
        Icon(
          icon,
          key: key,
          size: glyph,
          color: color ?? scheme.onSurfaceVariant,
          semanticLabel: label,
        );
    final enriching = ref.watch(
      aiEnrichingTasksProvider.select((s) => s.contains(task.id)),
    );
    final meta = <Widget>[
      if (due != null)
        Text.rich(
          key: Key('task-due-${task.id}'),
          // Polish 4 T-06: in the large-text row the date wraps between its
          // words ("Son tarih 14 Kas, / 12:30") instead of ending in "12:…";
          // the one-line row keeps squeezing it (R3, [AwMetaLine]).
          maxLines: vertical ? 3 : 1,
          softWrap: vertical,
          overflow: TextOverflow.ellipsis,
          style: metaStyle,
          // ADR-0063 #3: a date is data — tabular figures ([metaStyle]).
          // R3: the WORD is red, the date beside it stays neutral (G5: the
          // word, not only the colour, says it).
          isOverdue
              ? TextSpan(
                  children: [
                    TextSpan(
                      text: 'task.overdueWord'.tr(),
                      style: roles.metaStrong.copyWith(color: scheme.error),
                    ),
                    TextSpan(
                      text: ' ${_formatDue(due, dateFormat)}',
                      style: metaStyle,
                    ),
                  ],
                )
              : TextSpan(
                  text: 'task.dueOn'.tr(
                    args: {'date': _formatDue(due, dateFormat)},
                  ),
                ),
        ),
      // DESIGN §25 R6: one occurrence of a series says so, quietly.
      if (recurring)
        Tooltip(
          message: 'repeat.badgeTooltip'.tr(),
          excludeFromSemantics: true,
          child: glyphIcon(
            Icons.repeat,
            key: Key('repeat-badge-${task.id}'),
            label: 'repeat.badgeTooltip'.tr(),
          ),
        ),
      // §11 A5: a snoozed or silenced alarm keeps saying so, with its one-tap
      // way back. Otherwise the urgent alarm is the default and draws nothing;
      // an alarm that will NOT ring through silent is the deviation.
      // E35 G-B review r3: in the vertical row a long "Snoozed — 11:50 PM"
      // (2.0×, 12-hour, 360 pt) is wider than its own line, so the text wraps
      // under the glyph's line instead of overflowing the card. IntrinsicWidth
      // lets the meta line measure it unbounded (one line, its natural width)
      // and still hand the Flexible text a bounded width when it must wrap.
      if (snoozed)
        IntrinsicWidth(
          key: Key('task-alarm-${task.id}'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyphIcon(Icons.snooze),
              const SizedBox(width: AwSpace.x1),
              Flexible(
                child: Text(
                  'task.snoozedUntil'.tr(
                    args: {
                      'time': awFormatTime(snoozedUntil, format: dateFormat),
                    },
                  ),
                  maxLines: vertical ? 2 : 1,
                  softWrap: vertical,
                  overflow: TextOverflow.ellipsis,
                  style: roles.metaStrong.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        )
      else if (muted)
        // E35 G-B review r1: a muted row that drew nothing looked armed, so
        // the glyph and its way back are never dropped. Polish 3 J-04: nor
        // cut — "Alarmı geri…" was an imperative with its verb missing. The
        // row says the short complete action ("Sesi aç"), a reader hears the
        // same words (OPH-407), the target is 48 pt, and when it does not fit after the
        // others it takes a line of its own. At AX3 on a phone the glyph and
        // the action may not share even that line: the action then moves
        // under the glyph rather than breaking "Unmute" inside the word.
        AwMetaWrap(
          child: Wrap(
            key: Key('task-alarm-${task.id}'),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              glyphIcon(
                Icons.notifications_off,
                label: 'task.alarmsMuted'.tr(),
              ),
              // OPH-407 (T-07): heard as what it says (WCAG 2.5.3, label
              // in name) — "Sesi aç", not "Alarmı geri aç". The long wording
              // stays a tooltip for the eye.
              Tooltip(
                message: 'task.unmuteAlarms'.tr(),
                excludeFromSemantics: true,
                child: TextButton(
                  key: Key('unmute-${task.id}'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
                    minimumSize: const Size.square(kMinInteractiveDimension),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: roles.metaStrong,
                  ),
                  onPressed: () => unmuteTaskAlarms(context, ref, task),
                  child: Text('task.unmuteShort'.tr()),
                ),
              ),
            ],
          ),
        )
      else if (!completed && !task.isUrgent && task.remindAt != null)
        Tooltip(
          key: Key('task-alarm-${task.id}'),
          message: 'task.alarmNotUrgent'.tr(),
          excludeFromSemantics: true,
          child: glyphIcon(
            Icons.notifications_none,
            label: 'task.alarmNotUrgent'.tr(),
          ),
        ),
      // R3: "open" is what every task starts as — an hourglass on it said
      // nothing. Only another state earns its glyph.
      if (!completed && task.status != 'open')
        Tooltip(
          key: Key('task-status-${task.id}'),
          message: taskStatusLabel(task.status),
          excludeFromSemantics: true,
          child: glyphIcon(
            taskStatusIcon(task.status),
            label: 'task.statusSemantic'.tr(
              args: {'status': taskStatusLabel(task.status)},
            ),
          ),
        ),
      // G5: colour AND a flag — and only off the default (medium).
      if (priorityColor != null && task.priority != kAwDefaultPriority)
        glyphIcon(
          Icons.flag,
          key: Key('task-priority-${task.id}'),
          color: priorityColor,
          label: 'task.prioritySemantic'.tr(
            args: {'priority': taskPriorityLabel(task.priority)},
          ),
        ),
      if (showDuration)
        Semantics(
          label: 'task.durationSemantic'.tr(
            args: {'duration': awFormatDuration(duration, days: false)},
          ),
          excludeSemantics: true,
          child: Row(
            key: Key('task-duration-${task.id}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              glyphIcon(Icons.timelapse_outlined),
              const SizedBox(width: AwSpace.x1),
              Text(
                awFormatDuration(duration, days: false),
                maxLines: 1,
                softWrap: false,
                style: metaStyle,
              ),
            ],
          ),
        ),
      // T4, amended by R3: the first tag, then "+N".
      if (rowTags.isNotEmpty) _InlineTag(tag: rowTags.first, onTap: onTagTap),
      if (rowTags.length > 1)
        Tooltip(
          message: [
            for (final tag in rowTags.skip(1)) '#${tag.name}',
          ].join('  '),
          child: Text(
            '+${rowTags.length - 1}',
            maxLines: 1,
            style: roles.metaStrong.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      // Polish 3 J-03: the full name, never dropped — on a line of its own,
      // wrapping between words, when it does not fit after the others.
      if (projectInMeta)
        AwMetaWrap(
          child: _ProjectDot(
            key: Key('task-project-${task.id}'),
            project: project,
          ),
        ),
      if (unit != null)
        Row(
          key: Key('task-unit-${task.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            glyphIcon(Icons.workspaces_outline),
            const SizedBox(width: AwSpace.x1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
            ),
          ],
        ),
      if (work != null) AwTicketWorkChip(work: work),
      if (assigneesInMeta)
        AwAssigneeAvatarRow(key: Key('assignees-${task.id}'), taskId: task.id),
      // Round 14: the ✨ quick add already created this row; the spinner is
      // the promise that the AI is still filling fields in. Last, so it never
      // pushes a fact off the line.
      if (enriching)
        Tooltip(
          message: 'ai.quickAdd.enriching'.tr(),
          child: SizedBox(
            key: Key('ai-enriching-${task.id}'),
            width: glyph,
            height: glyph,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
              semanticsLabel: 'ai.quickAdd.enriching'.tr(),
            ),
          ),
        ),
    ];

    final check = SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: Center(
        child: Checkbox(
          value: task.isCompleted,
          onChanged: (_) => _toggle(context, ref),
          semanticLabel: task.isCompleted
              ? 'task.reopenNamed'.tr(args: {'title': task.title})
              : 'task.completeNamed'.tr(args: {'title': task.title}),
        ),
      ),
    );
    final rightSlot = right == null
        ? null
        : KeyedSubtree(key: Key('task-right-${task.id}'), child: right);

    final Widget body;
    if (!vertical) {
      body = Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AwSpace.x1,
          end: AwSpace.x3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OnFirstLine(center: lineCenter, child: check),
            const SizedBox(width: AwSpace.x1),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: titleTop, bottom: AwSpace.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      AwMetaLine(
                        key: Key('task-meta-${task.id}'),
                        children: meta,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (rightSlot != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AwSpace.x2),
                child: _OnFirstLine(center: lineCenter, child: rightSlot),
              ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AwSpace.x1,
          end: AwSpace.x3,
          bottom: AwSpace.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OnFirstLine(center: lineCenter, child: check),
                const SizedBox(width: AwSpace.x1),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: titleTop),
                    child: title,
                  ),
                ),
              ],
            ),
            if (meta.isNotEmpty || rightSlot != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: kMinInteractiveDimension + AwSpace.x1,
                  top: 2,
                ),
                child: AwMetaLine(
                  key: Key('task-meta-${task.id}'),
                  wrap: true,
                  children: [...meta, ?rightSlot],
                ),
              ),
          ],
        ),
      );
    }

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
      // OPH-405 (DESIGN §51 D2): the row open in the pane is outlined, not
      // filled — the fill is the selected day's, and the text keeps its
      // measured pair either way.
      shape: inPane
          ? RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : highlighted
          ? RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
            )
          : null,
      child: InkWell(
        // OPH-405 (DESIGN §51): on a desktop the row opens its task in the
        // pane beside the list; elsewhere it pushes the detail page.
        onTap: () {
          if (pane != null) {
            pane.open(task.id, order: AwListOrder.maybeOf(context));
          } else {
            context.push('/tasks/${task.id}');
          }
        },
        child: body,
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
    return Padding(
      padding: kAwListRowPadding,
      // Always the same wrapper, so opening a row never rebuilds its subtree.
      child: Semantics(selected: inPane ? true : null, child: swipeable),
    );
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
/// meta line's own.
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
        const SizedBox(width: AwSpace.x1),
        // A cap rather than `Flexible`: the meta line measures each item at
        // its natural width (§46 R3), so a long tag ellipsizes at 120 pt.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            '#${tag.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.awText.metaStrong.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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

/// The project, when the row's right slot went to something else (§46 R6):
/// an 8 pt dot in its colour and its name, in the meta line's ink.
class _ProjectDot extends StatelessWidget {
  const _ProjectDot({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final roles = context.awText;
    return Tooltip(
      message: project.name,
      excludeFromSemantics: true,
      child: Semantics(
        label: 'task.projectSemantic'.tr(args: {'project': project.name}),
        excludeSemantics: true,
        // One paragraph, the dot inline: it measures at its natural width on
        // a roomy line and wraps between words on a narrow one (J-03).
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: AwSpace.x1),
                  child: CircleAvatar(
                    backgroundColor: project.color,
                    radius: 4,
                  ),
                ),
              ),
              TextSpan(text: project.name),
            ],
          ),
          style: roles.meta.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Places [child] so its vertical centre is [center] pt below the top
/// (§46 R1: the check circle and the right item sit on the title's first
/// line). The box is as tall as it needs to be to hold the child there.
class _OnFirstLine extends SingleChildRenderObjectWidget {
  const _OnFirstLine({required this.center, required super.child});

  final double center;

  @override
  _RenderOnFirstLine createRenderObject(BuildContext context) =>
      _RenderOnFirstLine(center);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOnFirstLine renderObject,
  ) => renderObject.center = center;
}

class _RenderOnFirstLine extends RenderShiftedBox {
  _RenderOnFirstLine(this._center) : super(null);

  double _center;
  set center(double value) {
    if (value == _center) return;
    _center = value;
    markNeedsLayout();
  }

  Size _place(Size child) =>
      Size(child.width, math.max(0, _center - child.height / 2) + child.height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      _place(child.getDryLayout(constraints.loosen())),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(_place(child.size));
    (child.parentData! as BoxParentData).offset = Offset(
      0,
      math.max(0, _center - child.size.height / 2),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) {
    final h = child?.getMinIntrinsicHeight(width) ?? 0;
    return math.max(0, _center - h / 2) + h;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final h = child?.getMaxIntrinsicHeight(width) ?? 0;
    return math.max(0, _center - h / 2) + h;
  }
}
