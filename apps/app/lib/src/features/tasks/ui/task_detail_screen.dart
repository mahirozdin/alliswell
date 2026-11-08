import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/date_input.dart';
import '../../../core/persisted_prefs.dart';
import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../../../i18n/i18n.dart';
import '../../../sections.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/linkified_text.dart';
import '../../../widgets/status_views.dart';
import '../../files/providers.dart';
import '../../files/ui/attach_menu.dart';
import '../../files/ui/file_widgets.dart';
import '../../integrations/providers.dart';
import '../../projects/data/project.dart';
import '../../ee/ticket_work_providers.dart';
import '../../ee/ui/ticket_work_section.dart';
import '../../projects/providers.dart';
import '../../workspaces/workspaces.dart';
import '../../projects/ui/project_picker.dart';
import '../../tags/ui/tag_input.dart';
import '../../tags/ui/tag_manage_sheet.dart';
import '../data/task.dart';
import '../data/task_store.dart';
import '../providers.dart';
import 'duration_picker.dart';
import 'task_tile.dart' show TaskTile, deleteTaskWithUndo;
import 'repeat_row.dart';
import 'task_visuals.dart';
import '../../ee/assignments_providers.dart';
import '../../ee/ui/assignee_avatars.dart';
import '../../../widgets/route_leading.dart';
import '../../../theme/typography.dart';
import '../../../widgets/popup_menu.dart';
import '../../../widgets/dropdown_field.dart';

/// One task write: gets the store + task id. Writes land in the local
/// replica instantly and sync in the background (OPH-054/055).
typedef TaskAction = Future<Object?> Function(TaskStore store, String taskId);

/// Task detail (OPH-037 + feedback round 3): editable title with autosave,
/// status/priority dropdowns with icons/colors, urgent toggle, dates, tags
/// and checklist — every control writes the local replica (instant) and syncs
/// in the background; failed writes surface as snackbars instead of vanishing.
class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.onClose});

  final String taskId;

  /// Set when the detail is the desktop pane beside a list (OPH-405,
  /// DESIGN §51): the app bar leads with a close button instead of back,
  /// and deleting the task closes the pane instead of popping a route.
  final VoidCallback? onClose;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  /// The task this screen has shown at least once. Its row missing after
  /// that is a deletion (a pull applied its tombstone, OPH-419); missing
  /// before that is only a row not pulled yet — the waiting screen's case.
  String? _shownTaskId;

  @override
  Widget build(BuildContext context) {
    final taskId = widget.taskId;
    final onClose = widget.onClose;
    final task = ref.watch(taskDetailProvider(taskId));
    return task.when(
      loading: () => _TaskDetailWaiting(taskId: taskId, onClose: onClose),
      error: (error, _) => Scaffold(
        appBar: AppBar(leading: _leading(context, onClose)),
        body: Center(child: Text('$error')),
      ),
      data: (value) {
        if (value != null) {
          _shownTaskId = taskId;
          return _TaskDetail(task: value, onClose: onClose);
        }
        return _shownTaskId == taskId
            ? _TaskDetailDeleted(onClose: onClose)
            : _TaskDetailWaiting(taskId: taskId, onClose: onClose);
      },
    );
  }
}

/// The task this detail was showing left the replica while it was open —
/// deleted on another device, or no longer this person's (OPH-419). Says so
/// instead of keeping the last task on screen: stale, editable, and every
/// control a write for an entity that is gone. No automatic pop or close:
/// a sheet may be open over it, and a row that comes back (a task moved
/// between workspaces, OPH-378) shows the task again.
class _TaskDetailDeleted extends StatelessWidget {
  const _TaskDetailDeleted({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final close = onClose;
    final router = GoRouter.of(context);
    final canPop = close == null && router.canPop();
    return Scaffold(
      appBar: AppBar(leading: _leading(context, close)),
      body: AwErrorState(
        key: const Key('task-detail-deleted'),
        message: 'task.goneWhileOpen'.tr(),
        retryLabel: close != null
            ? 'common.close'.tr()
            : canPop
            ? 'task.goneBack'.tr()
            : 'error.goHome'.tr(),
        retryIcon: close != null
            ? Icons.close
            : canPop
            ? Icons.arrow_back
            : Icons.home_outlined,
        onRetry:
            close ??
            () => canPop ? router.pop() : router.go(AppSection.home.path),
      ),
    );
  }
}

/// The app bar's leading button: the pane's close, or the route's own.
Widget? _leading(BuildContext context, VoidCallback? onClose) => onClose == null
    ? awRouteLeading(context)
    : IconButton(
        key: const Key('task-pane-close'),
        icon: const Icon(Icons.close),
        tooltip: 'task.paneClose'.tr(),
        onPressed: onClose,
      );

/// The detail's row is not in the replica (yet). A spinner while the server
/// says the task exists — the pull brings it — and an answer otherwise
/// (OPH-392, E-17): a link to a deleted or foreign task, or one opened
/// offline before it ever synced, used to spin forever.
class _TaskDetailWaiting extends ConsumerWidget {
  const _TaskDetailWaiting({required this.taskId, this.onClose});

  final String taskId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final absence = ref.watch(taskAbsenceProvider(taskId)).value;
    return Scaffold(
      appBar: absence == null
          ? null
          : AppBar(leading: _leading(context, onClose)),
      body: switch (absence) {
        null => const Center(child: CircularProgressIndicator()),
        TaskAbsence.gone => AwErrorState(
          key: const Key('task-detail-gone'),
          message: 'error.notFound'.tr(),
          retryLabel: 'error.goHome'.tr(),
          retryIcon: Icons.home_outlined,
          onRetry: () => GoRouter.of(context).go(AppSection.home.path),
        ),
        TaskAbsence.unreachable => AwErrorState(
          key: const Key('task-detail-unreachable'),
          message: 'error.NETWORK_ERROR'.tr(),
          onRetry: () => ref.invalidate(taskAbsenceProvider(taskId)),
        ),
      },
    );
  }
}

class _TaskDetail extends ConsumerStatefulWidget {
  const _TaskDetail({required this.task, this.onClose});

  final Task task;
  final VoidCallback? onClose;

  @override
  ConsumerState<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<_TaskDetail> {
  static const _autosaveDelay = Duration(milliseconds: 1500);

  late final TextEditingController _title;
  Timer? _titleDebounce;

  Task get task => widget.task;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: task.title);
  }

  @override
  void didUpdateWidget(covariant _TaskDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetches rebuild us with fresh data; only sync the field when the user
    // isn't mid-edit (their text still matches what the server had before).
    if (widget.task.title != oldWidget.task.title &&
        _title.text == oldWidget.task.title) {
      _title.text = widget.task.title;
    }
  }

  /// Leaving with a title still waiting for its autosave pause — another
  /// task opened in the desktop pane, the pane closed, the page popped —
  /// writes it now instead of dropping it. Here and not in [dispose]: `ref`
  /// and the messenger are still reachable. No series question can be asked
  /// from a detail that is going away, so on a recurring occurrence the
  /// rename reaches this occurrence only (the write without a scope).
  @override
  void deactivate() {
    final pending = _titleDebounce?.isActive ?? false;
    _titleDebounce?.cancel();
    final title = _title.text.trim();
    if (pending && title.isNotEmpty && title != task.title) {
      final store = ref.read(taskStoreProvider);
      final messenger = ScaffoldMessenger.maybeOf(context);
      store.update(task.id, {'title': title}).catchError((Object _) {
        messenger?.showSnackBar(
          SnackBar(content: Text('task.couldNotSave'.tr())),
        );
      });
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _title.dispose();
    super.dispose();
  }

  Future<void> _apply(TaskAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(ref.read(taskStoreProvider), task.id);
    } on Object catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('task.couldNotSave'.tr())));
    }
  }

  /// A field edit on ONE occurrence of a series is ambiguous by construction
  /// (DESIGN §25 R8), so it asks first — and the default follows the field:
  /// moving a date means "just this", renaming means "this and future".
  /// Backing out of the question writes nothing at all.
  Future<void> _applyScoped(
    Map<String, dynamic> patch, {
    bool isDateEdit = false,
  }) async {
    if (!task.isRecurring || await isAfterCompletionTask(ref, task)) {
      await _apply((store, id) => store.update(id, patch));
      return;
    }
    if (!mounted) return;
    final scope = await showSeriesScopeDialog(context, isDateEdit: isDateEdit);
    if (scope == null) return;
    await _apply(
      (store, id) => store.update(id, {...patch, 'seriesScope': scope}),
    );
  }

  void _onTitleChanged(String value) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_autosaveDelay, () {
      final title = value.trim();
      if (title.isEmpty || title == task.title) return;
      _applyScoped({'title': title});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // EE-297: the request this task is the work of. What the request owns —
    // deleting, cancelling, the project, the repeat — is not offered here;
    // the server refuses each of them too (TICKET_WORK_BOUND / _LOCKED).
    final work = ref.watch(ticketWorkOfTaskProvider(task.id)).value;
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > kAwRowVerticalTextScale;
    Widget half(Widget field) => largeText ? field : Expanded(child: field);
    return Scaffold(
      appBar: AppBar(
        leading: _leading(context, widget.onClose),
        // The pane has no route under it to imply a back button from.
        automaticallyImplyLeading: widget.onClose == null,
        title: Text('task.detailTitle'.tr()),
        actions: [
          // EE-069 / item 10: the task's own history. Present only where there
          // is a team to have made it — on a personal workspace nothing has
          // ever been recorded and the button would open an empty room.
          // EE-290: the TASK's workspace decides, not the one on screen. It
          // read the selected workspace's roster, so with a team's workspace
          // selected a personal task opened from Home (or from a link) wore
          // the team's history button too.
          if (ref
                  .watch(workspaceRosterOfProvider(task.workspaceId))
                  .value
                  ?.isNotEmpty ??
              false)
            IconButton(
              key: const Key('task-history'),
              tooltip: 'ee.history.taskTitle'.tr(),
              icon: const Icon(Icons.history),
              onPressed: () => context.push('/tasks/${task.id}/history'),
            ),
          IconButton(
            tooltip: task.isCompleted
                ? 'task.reopen'.tr()
                : 'task.complete'.tr(),
            icon: Icon(
              task.isCompleted ? Icons.replay : Icons.check_circle_outline,
            ),
            onPressed: () => _apply(
              (store, id) =>
                  task.isCompleted ? store.reopen(id) : store.complete(id),
            ),
          ),
          // OPH-184: the detail screen's delete, the same one the note editor
          // and project detail already had. The task was the app's most-used
          // object and the only one that could not be deleted anywhere.
          if (work == null)
            IconButton(
              key: const Key('task-delete'),
              tooltip: 'task.deleteTooltip'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final router = GoRouter.of(context);
                final close = widget.onClose;
                await deleteTaskWithUndo(context, ref, task);
                if (close != null) {
                  close();
                  return;
                }
                // Pop first: the row is already hidden everywhere, and staying on
                // the detail of a deleted task would strand the user.
                if (router.canPop()) {
                  router.pop();
                } else {
                  router.go(AppSection.home.path);
                }
              },
            ),
          AwPopupMenuButton<String>(
            key: const Key('task-quick-menu'),
            tooltip: 'quick.actions'.tr(),
            onSelected: (_) => toggleQuickAccess(
              context,
              ref,
              kind: QuickKind.task,
              targetId: task.id,
              suggestedTitle: task.title,
            ),
            itemBuilder: (context) => [
              quickAccessMenuItem(
                value: 'quick',
                isSaved: isInQuickAccess(ref, QuickKind.task, task.id),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              // Editable in place — autosaves after a pause (feedback round 3).
              TextField(
                key: const Key('task-title'),
                controller: _title,
                maxLines: null,
                onChanged: _onTitleChanged,
                decoration: InputDecoration(
                  hintText: 'task.titleHint'.tr(),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                style: theme.textTheme.headlineSmall?.copyWith(
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: task.isCompleted
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              if (work != null) ...[
                AwTicketWorkSection(work: work),
                const SizedBox(height: AwSpace.x3),
              ],
              // OPH-164: the task's own description — editable in place with
              // the title's autosave DNA; URLs are tappable in display mode.
              _DescriptionField(
                task: task,
                onApply: _apply,
                // One destination, two doors: this lands in the very list the
                // Attachments section at the bottom of this screen renders.
                attach: AttachButton(
                  buttonKey: const Key('task-description-attach'),
                  style: AttachButtonStyle.text,
                  labelKey: 'file.attach',
                  onPicked: (picks) => ref
                      .read(uploadsProvider.notifier)
                      .uploadAll(
                        workspaceId: task.workspaceId,
                        targetType: 'task',
                        targetId: task.id,
                        sources: picks,
                      ),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              _SectionCard(
                title: 'task.details'.tr(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Polish 4 T-06: at large text the two half-width fields
                    // scaled the longer value down ("Yüksek" drawn smaller
                    // than "Açık"); there they stack, each at full width.
                    Flex(
                      direction: largeText ? Axis.vertical : Axis.horizontal,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: largeText
                          ? CrossAxisAlignment.stretch
                          : CrossAxisAlignment.center,
                      children: [
                        half(
                          AwDropdownField<String>(
                            isExpanded: true,
                            key: const Key('status-dropdown'),
                            initialValue: task.status,
                            decoration: InputDecoration(
                              labelText: 'task.statusLabel'.tr(),
                            ),
                            items: [
                              for (final status in kTaskStatuses)
                                // A request's work is not cancelled or
                                // archived on its own: the request is.
                                if (work == null ||
                                    status == task.status ||
                                    (status != 'cancelled' &&
                                        status != 'archived'))
                                  DropdownMenuItem(
                                    value: status,
                                    child: StatusLabel(status: status),
                                  ),
                            ],
                            onChanged: (v) {
                              if (v != null && v != task.status) {
                                _apply(
                                  (store, id) =>
                                      store.update(id, {'status': v}),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12, height: 12),
                        half(
                          AwDropdownField<String>(
                            isExpanded: true,
                            key: const Key('priority-dropdown'),
                            initialValue: task.priority,
                            decoration: InputDecoration(
                              labelText: 'task.priorityLabel'.tr(),
                            ),
                            items: [
                              for (final priority in kTaskPriorities)
                                DropdownMenuItem(
                                  value: priority,
                                  child: PriorityLabel(priority: priority),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null && v != task.priority) {
                                _apply(
                                  (store, id) =>
                                      store.update(id, {'priority': v}),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Project picker (OPH-106): same color-dot entries as the
                    // create sheet; assigning a project also promotes an inbox
                    // capture to 'open' via the store rule (OPH-107).
                    if (work == null) ...[
                      ProjectPickerField(
                        key: const Key('detail-project'),
                        // The TASK's workspace (EE-296): opened from Home it
                        // may live in a unit other than the one selected.
                        projects:
                            ref
                                .watch(
                                  workspaceProjectsProvider(task.workspaceId),
                                )
                                .value ??
                            const <Project>[],
                        value: task.projectId,
                        decoration: InputDecoration(
                          labelText: 'task.project'.tr(),
                        ),
                        onChanged: (v) {
                          if (v != task.projectId) {
                            _apply(
                              (store, id) => store.update(id, {'projectId': v}),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                    // H-5 (OPH-400): the urgent row carries its icon like
                    // every other switch row here, so its title starts on the
                    // same line as "Sustur" and "Tekrarla" instead of the
                    // card's edge (DESIGN §46 R8).
                    SwitchListTile(
                      key: const Key('urgent-switch'),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.notification_important_outlined,
                      ),
                      title: Text('task.urgentAlarm'.tr()),
                      subtitle: Text('task.urgentAlarmSub'.tr()),
                      value: task.isUrgent,
                      onChanged: (v) => _apply(
                        (store, id) => store.update(id, {'isUrgent': v}),
                      ),
                    ),
                    // OPH-178: silence this task's alarms for good, without
                    // completing it. The subtitle says what silence means; the
                    // task keeps its dates and its status.
                    SwitchListTile(
                      key: const Key('mute-alarms-switch'),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.notifications_off_outlined),
                      // OPH-303: a SWITCH is named for what flipping it DOES,
                      // and this one was named for the state it leaves behind.
                      // `task.alarmsMuted` ("Alarm silenced") is correct where
                      // it reports a fact — the row's badge and the ring
                      // screen's confirmation — and wrong here, where it reads
                      // to a non-native speaker as "silent alarm": exactly the
                      // feature a user was hunting for when they turned this on
                      // and reported that nothing happened.
                      title: Text('task.muteAlarms'.tr()),
                      subtitle: Text('task.alarmsMutedSub'.tr()),
                      value: task.alarmsMutedAt != null,
                      onChanged: (mute) async {
                        if (mute) {
                          await ref.read(taskStoreProvider).muteAlarms(task.id);
                        } else {
                          await unmuteTaskAlarms(context, ref, task);
                        }
                      },
                    ),
                    // OPH-207 (DESIGN §25 R1): the Repeat switch. Turning it
                    // on opens the rule dialog immediately; the sentence and
                    // "Değiştir" appear underneath once a rule exists.
                    if (work == null) RepeatRow(task: task),
                    // OPH-177: a snoozed alarm says so here too — the task is
                    // still open, it is just quiet until then.
                    if (task.snoozedUntil != null &&
                        task.snoozedUntil!.toLocal().isAfter(DateTime.now()))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AwSpace.x2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.snooze,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AwSpace.x3),
                            Text(
                              'task.snoozedUntil'.tr(
                                args: {
                                  'time': awFormatTime(
                                    task.snoozedUntil!,
                                    format: ref.watch(dateFormatProvider),
                                  ),
                                },
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    // OPH-210 (ADR-0021 §1): the "show in calendar" switch is
                    // GONE. Every task is on the calendar now — it was never a
                    // choice the user should have had to find, and the default
                    // being off meant an ordinary dated task never got there.
                    // OPH-372 (ADR-0053, DESIGN §38 W1): "When" — the day it
                    // enters Today — above the deadline. A day, no clock. It
                    // belongs to THIS occurrence of a series, so it asks no
                    // scope question; and like the deadline it is never
                    // written by a calendar drag (that lands in scheduled*).
                    _DateRow(
                      key: const Key('when-row'),
                      label: 'task.when'.tr(),
                      icon: Icons.wb_sunny_outlined,
                      value: task.startAt,
                      dateOnly: true,
                      onPicked: (picked) =>
                          _apply((store, id) => store.setWhen(id, picked)),
                    ),
                    _DateRow(
                      key: const Key('due-row'),
                      label: 'task.due'.tr(),
                      icon: Icons.flag_outlined,
                      value: task.dueAt,
                      onPicked: (picked) => _applyScoped({
                        'dueAt': picked?.toUtc().toIso8601String(),
                      }, isDateEdit: true),
                    ),
                    // OPH-192 (round 10 #7): NOT a third date field any more.
                    // "Planlanan" was never in BLUEPRINT §12.4's field list —
                    // OPH-076 added it so a calendar drag would be visible — and
                    // as a permanent, empty, unexplained row it read as clutter.
                    //
                    // It cannot simply be deleted either: §7.1 derives the
                    // calendar block from `scheduled_start_at` FIRST, and
                    // dragging our event in Google writes exactly that (never
                    // `due_at` — moving a block says "I'll do it then", not "the
                    // deadline moved"). A hidden field would pin the event in
                    // place forever with no way to see or clear it.
                    //
                    // So: invisible until it applies, and when it applies it
                    // says what it is and offers the way out.
                    if (task.scheduledStartAt != null)
                      _MovedInCalendarRow(
                        key: const Key('scheduled-row'),
                        at: task.scheduledStartAt!,
                        onReset: () => _apply(
                          (store, id) => store.update(id, {
                            'scheduledStartAt': null,
                            // The end belongs to the block: clearing the start
                            // clears it, and a start left behind an end would
                            // make §7.1 derive a backwards block.
                            'scheduledEndAt': null,
                          }),
                        ),
                      ),
                    _DateRow(
                      key: const Key('remind-row'),
                      label: 'task.remind'.tr(),
                      icon: Icons.alarm,
                      value: task.remindAt,
                      anchor: task.dueAt,
                      onPicked: (picked) => _apply(
                        (store, id) => store.update(id, {
                          'remindAt': picked?.toUtc().toIso8601String(),
                        }),
                      ),
                    ),
                    // OPH-372: how long it takes. A series template field on
                    // the server (PROPAGATED_FIELDS), so a recurring task asks
                    // the scope question like a rename does.
                    _DurationRow(
                      key: const Key('duration-row'),
                      minutes: task.estimatedMinutes,
                      onPicked: (minutes) =>
                          _applyScoped({'estimatedMinutes': minutes}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              _SectionCard(
                title: 'task.tags'.tr(),
                // OPH-165: not a picker anymore — type to assign, auto-create
                // when missing, manage from the same card (DESIGN §13).
                child: TagInputField(
                  value: task.tagIds,
                  workspaceId: task.workspaceId,
                  onChanged: (tagIds) =>
                      _apply((store, id) => store.setTags(id, tagIds)),
                  // Managing tags is the selected workspace's business; from
                  // a task that lives in another unit it would manage the
                  // wrong list, so the door is offered only at home.
                  onManage:
                      task.workspaceId ==
                          ref.watch(
                            currentWorkspaceProvider.select((w) => w.value?.id),
                          )
                      ? () => showTagManageSheet(context)
                      : null,
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              // EE-068 / item 9: who is on this task. The section is present
              // only where there IS a roster, so a personal workspace and a
              // plain build never see a card they cannot use. EE-290: the
              // roster of the task's OWN workspace, for the reason the
              // history button above gives.
              if (ref
                      .watch(workspaceRosterOfProvider(task.workspaceId))
                      .value
                      ?.isNotEmpty ??
                  false) ...[
                _SectionCard(
                  title: 'ee.assign.section'.tr(),
                  child: AwAssigneeSection(
                    workspaceId: task.workspaceId,
                    taskId: task.id,
                  ),
                ),
                const SizedBox(height: AwSpace.x3),
              ],
              // OPH-394 (E-07): a subtask is listed here, under its parent,
              // and not as a row of its own on Home. Only when there is one:
              // subtasks are written through the API and MCP, and an empty
              // card would promise a control this screen does not have.
              if (ref.watch(subtasksProvider(task.id)).value
                  case final subtasks? when subtasks.isNotEmpty) ...[
                _SectionCard(
                  key: const Key('task-subtasks'),
                  title: 'task.subtasks'.tr(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final subtask in subtasks)
                        TaskTile(
                          task: subtask,
                          showProjectBadge: false,
                          swipeToDelete: false,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AwSpace.x3),
              ],
              _SectionCard(
                title: 'task.checklist'.tr(),
                child: _Checklist(
                  task: task,
                  onApply: (action) => _apply(action),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              // Epic 14 (OPH-154): images/videos/any file on the task —
              // uploads are visible and cancelable, rows come from the synced
              // replica (offline-capable metadata, on-demand bytes).
              _SectionCard(
                title: 'task.attachments'.tr(),
                child: AttachmentsSection(
                  workspaceId: task.workspaceId,
                  targetType: 'task',
                  targetId: task.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded surface card with a small uppercase-ish section header.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: context.awText.sectionLabel.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            child,
          ],
        ),
      ),
    );
  }
}

/// The calendar-drag explanation (OPH-192). Only ever built when the task
/// actually carries a `scheduledStartAt`, so a user who never drags an event in
/// their calendar never learns this concept exists — which is the point.
class _MovedInCalendarRow extends ConsumerWidget {
  const _MovedInCalendarRow({
    required this.at,
    required this.onReset,
    super.key,
  });

  final DateTime at;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_available_outlined),
      title: Text(
        'task.movedInCalendar'.tr(
          args: {
            'date': awFormatDateTime(
              at.toLocal(),
              format: ref.watch(dateFormatProvider),
            ),
          },
        ),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'task.movedInCalendarSub'.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      trailing: TextButton(
        key: const Key('reset-schedule'),
        onPressed: onReset,
        child: Text('task.resetSchedule'.tr()),
      ),
    );
  }
}

class _DateRow extends ConsumerWidget {
  const _DateRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onPicked,
    this.anchor,
    this.dateOnly = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final DateTime? value;

  /// A field that stores a DAY ("When", OPH-372): shown and picked without a
  /// time (DESIGN §17 D5 as amended).
  final bool dateOnly;

  /// The date this row lives next to — see [awInitialPickerDate]. The deadline
  /// row has none (it opens on tomorrow); a reminder or a planned block opens
  /// on the deadline's day when there is one (OPH-173).
  final DateTime? anchor;
  final void Function(DateTime?) onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final local = value?.toLocal();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        local == null
            ? 'task.notSet'.tr()
            : dateOnly
            ? awFormatDate(local, format: ref.watch(dateFormatProvider))
            : awFormatDateTime(local, format: ref.watch(dateFormatProvider)),
        style: TextStyle(
          color: local == null ? scheme.onSurfaceVariant : scheme.onSurface,
          fontWeight: local == null ? null : FontWeight.w600,
        ),
      ),
      trailing: local == null
          ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
          : IconButton(
              tooltip: 'task.clearField'.tr(args: {'field': label}),
              icon: const Icon(Icons.close),
              onPressed: () => onPicked(null),
            ),
      // OPH-191 (DESIGN §17 D5): the SAME input path the create sheet uses —
      // date AND time. This row used to ask for a date only and then stamp the
      // default task time on it, so editing the day of a 14:30 task silently
      // moved it to 23:59.
      onTap: () async {
        final picked = dateOnly
            ? await awPickDate(
                context,
                current: local,
                anchor: anchor?.toLocal(),
              )
            : await awPickDateTime(
                context,
                ref,
                current: local,
                anchor: anchor?.toLocal(),
              );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

/// The duration row (OPH-372, DESIGN §38 W3) — the dates card's sibling of
/// [_DateRow]: tap to pick, ✕ to clear.
class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.minutes,
    required this.onPicked,
    super.key,
  });

  final int? minutes;
  final void Function(int?) onPicked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = 'task.duration'.tr();
    final value = minutes;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.timelapse_outlined),
      title: Text(label),
      subtitle: Text(
        value == null
            ? 'task.notSet'.tr()
            : awFormatDuration(value, days: false),
        style: TextStyle(
          color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
          fontWeight: value == null ? null : FontWeight.w600,
        ),
      ),
      trailing: value == null
          ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
          : IconButton(
              tooltip: 'task.clearField'.tr(args: {'field': label}),
              icon: const Icon(Icons.close),
              onPressed: () => onPicked(null),
            ),
      onTap: () async {
        final picked = await showDurationPicker(context, current: value);
        if (picked != null && picked != value) onPicked(picked);
      },
    );
  }
}

class _Checklist extends StatefulWidget {
  const _Checklist({required this.task, required this.onApply});

  final Task task;
  final void Function(TaskAction) onApply;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    widget.onApply((store, id) => store.addChecklistItem(id, title));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in widget.task.checklist)
          _ChecklistItemRow(
            key: ValueKey('checklist-item-${item.id}'),
            item: item,
            onToggle: (done) => widget.onApply(
              (store, id) =>
                  store.setChecklistItemDone(id, item.id, isDone: done),
            ),
            onRename: (title) => widget.onApply((store, id) async {
              await store.renameChecklistItem(id, item.id, title);
              return null;
            }),
            onRemove: () => widget.onApply((store, id) async {
              await store.deleteChecklistItem(id, item.id);
              return null;
            }),
          ),
        TextField(
          key: const Key('checklist-add'),
          controller: _controller,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            hintText: 'task.addChecklistItem'.tr(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'task.addItem'.tr(),
              onPressed: _add,
            ),
          ),
        ),
      ],
    );
  }
}

/// One checklist row (OPH-416, issue #38): the checkbox ticks, the words
/// edit. Tapping the title swaps it for an in-place field; Enter or focus
/// loss saves the trimmed text, Escape cancels, and an empty field restores
/// the old title without writing anything.
class _ChecklistItemRow extends StatefulWidget {
  const _ChecklistItemRow({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onRename,
    required this.onRemove,
  });

  final ChecklistItem item;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;

  @override
  State<_ChecklistItemRow> createState() => _ChecklistItemRowState();
}

class _ChecklistItemRowState extends State<_ChecklistItemRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.title,
  );
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _startEditing() {
    _controller.value = TextEditingValue(
      text: widget.item.title,
      selection: TextSelection.collapsed(offset: widget.item.title.length),
    );
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _commit() {
    if (!_editing) return;
    final title = _controller.text.trim();
    setState(() => _editing = false);
    if (title.isEmpty || title == widget.item.title) {
      _controller.text = widget.item.title;
      return;
    }
    widget.onRename(title);
  }

  void _cancel() {
    if (!_editing) return;
    _controller.text = widget.item.title;
    setState(() => _editing = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final style = theme.textTheme.bodyLarge?.copyWith(
      decoration: item.isDone ? TextDecoration.lineThrough : null,
    );
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Checkbox(
              key: Key('checklist-item-check-${item.id}'),
              value: item.isDone,
              semanticLabel: item.title,
              onChanged: (v) => widget.onToggle(v ?? false),
            ),
          ),
        ),
        Expanded(
          child: _editing
              ? TextField(
                  key: Key('checklist-item-edit-${item.id}'),
                  controller: _controller,
                  focusNode: _focus,
                  style: style,
                  maxLength: TaskStore.checklistTitleMax,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _commit(),
                  onTapOutside: (_) => _focus.unfocus(),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                )
              : Semantics(
                  button: true,
                  hint: 'task.editItem'.tr(),
                  child: InkWell(
                    key: Key('checklist-item-title-${item.id}'),
                    borderRadius: BorderRadius.circular(AwRadius.s),
                    onTap: _startEditing,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(item.title, style: style),
                      ),
                    ),
                  ),
                ),
        ),
        IconButton(
          tooltip: 'task.removeItem'.tr(),
          icon: const Icon(Icons.close, size: 18),
          onPressed: widget.onRemove,
        ),
      ],
    );
  }
}

/// The task's own description (round 8, OPH-164) — not a Note.
///
/// Display mode renders URLs tappable ([LinkifiedText]); tapping the text (or
/// the "Add description" affordance when empty) switches to an in-place
/// editor with the title's autosave DNA: debounce while typing, flush on
/// focus loss. Empty text saves as null — a task with nothing to say has no
/// description row, not a blank one.
class _DescriptionField extends ConsumerStatefulWidget {
  const _DescriptionField({
    required this.task,
    required this.onApply,
    required this.attach,
  });

  final Task task;
  final Future<void> Function(TaskAction action) onApply;

  /// The attach affordance (DESIGN §30 A4) — round 17 #2: this is where the
  /// owner looked for it first, because it is where notes put it.
  ///
  /// Passed IN rather than placed beside this widget by the parent: only this
  /// state knows whether the description is empty, being edited or displayed,
  /// and the three layouts want the button in three different places. Tapping
  /// it while editing moves focus out, which flushes the autosave — correct,
  /// not a bug. Files land in the SAME list the Attachments section below
  /// renders: one destination, two doors.
  final Widget attach;

  @override
  ConsumerState<_DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends ConsumerState<_DescriptionField> {
  static const _autosaveDelay = Duration(milliseconds: 1500);

  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _editing = false;

  String get _current => widget.task.description ?? '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _current);
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) {
        _flush();
        setState(() => _editing = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch while not editing → sync the controller (title-field idiom).
    final fresh = widget.task.description ?? '';
    final old = oldWidget.task.description ?? '';
    if (fresh != old && !_editing) _controller.text = fresh;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save(String raw) {
    final value = raw.trim();
    if (value == _current.trim()) return;
    widget.onApply(
      (store, id) =>
          store.update(id, {'description': value.isEmpty ? null : value}),
    );
  }

  void _flush() {
    _debounce?.cancel();
    _save(_controller.text);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, () => _save(value));
  }

  void _startEditing() {
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('task-description'),
            controller: _controller,
            focusNode: _focus,
            maxLines: null,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'task.descriptionHint'.tr(),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: widget.attach,
          ),
        ],
      );
    }
    if (_current.trim().isEmpty) {
      // "Add description · Attach" on one line — literally the round-17 ask.
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: AwSpace.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const Key('task-add-description'),
              onPressed: _startEditing,
              icon: const Icon(Icons.notes_outlined, size: 18),
              label: Text('task.addDescription'.tr()),
            ),
            widget.attach,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('task-description-display'),
          borderRadius: BorderRadius.circular(AwRadius.s),
          onTap: _startEditing,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LinkifiedText(
              _current,
              style: theme.textTheme.bodyMedium,
              onOpen: (uri) => ref.read(urlLauncherProvider)(uri),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: widget.attach,
        ),
      ],
    );
  }
}
