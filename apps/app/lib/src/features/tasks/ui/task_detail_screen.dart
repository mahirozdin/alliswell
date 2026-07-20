import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../files/ui/file_widgets.dart';
import '../../projects/data/project.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../tags/tags.dart';
import '../data/task.dart';
import '../data/task_store.dart';
import '../providers.dart';
import 'task_visuals.dart';

/// One task write: gets the store + task id. Writes land in the local
/// replica instantly and sync in the background (OPH-054/055).
typedef TaskAction = Future<Object?> Function(TaskStore store, String taskId);

/// Task detail (OPH-037 + feedback round 3): editable title with autosave,
/// status/priority dropdowns with icons/colors, urgent toggle, dates, tags
/// and checklist — every control writes the local replica (instant) and syncs
/// in the background; failed writes surface as snackbars instead of vanishing.
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskDetailProvider(taskId));
    return task.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$error')),
      ),
      data: (value) => _TaskDetail(task: value),
    );
  }
}

class _TaskDetail extends ConsumerStatefulWidget {
  const _TaskDetail({required this.task});

  final Task task;

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

  void _onTitleChanged(String value) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_autosaveDelay, () {
      final title = value.trim();
      if (title.isEmpty || title == task.title) return;
      _apply((store, id) => store.update(id, {'title': title}));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('task.detailTitle'.tr()),
        actions: [
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
              if (task.description?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(task.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AwSpace.x3),
              _SectionCard(
                title: 'task.details'.tr(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            key: const Key('status-dropdown'),
                            initialValue: task.status,
                            decoration: InputDecoration(
                              labelText: 'task.statusLabel'.tr(),
                            ),
                            items: [
                              for (final status in kTaskStatuses)
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
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
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      key: const Key('detail-project'),
                      initialValue: task.projectId,
                      decoration: InputDecoration(
                        labelText: 'task.project'.tr(),
                      ),
                      items: projectDropdownItems(
                        ref.watch(projectsControllerProvider).value ??
                            const <Project>[],
                        currentValue: task.projectId,
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
                    SwitchListTile(
                      key: const Key('urgent-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('task.urgentAlarm'.tr()),
                      subtitle: Text('task.urgentAlarmSub'.tr()),
                      value: task.isUrgent,
                      onChanged: (v) => _apply(
                        (store, id) => store.update(id, {'isUrgent': v}),
                      ),
                    ),
                    // OPH-081: opt-in mirroring (BLUEPRINT §12). Enabling it
                    // early is fine — the event appears the moment the task
                    // gets a time — so say that instead of blocking the switch.
                    SwitchListTile(
                      key: const Key('calendar-mirror-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('task.showInCalendar'.tr()),
                      subtitle: Text(
                        task.hasCalendarTime
                            ? 'task.showInCalendarOnSub'.tr()
                            : 'task.showInCalendarOffSub'.tr(),
                      ),
                      value: task.calendarMirrorEnabled,
                      onChanged: (v) => _apply(
                        (store, id) =>
                            store.update(id, {'calendarMirrorEnabled': v}),
                      ),
                    ),
                    _DateRow(
                      label: 'task.due'.tr(),
                      icon: Icons.flag_outlined,
                      value: task.dueAt,
                      onPicked: (picked) => _apply(
                        (store, id) => store.update(id, {
                          'dueAt': picked?.toUtc().toIso8601String(),
                        }),
                      ),
                    ),
                    // When you'll actually do it — and where a dragged calendar
                    // event lands (OPH-076). Without this row the two-way sync
                    // would be invisible in the app.
                    _DateRow(
                      key: const Key('scheduled-row'),
                      label: 'task.scheduledField'.tr(),
                      icon: Icons.event_outlined,
                      value: task.scheduledStartAt,
                      onPicked: (picked) => _apply(
                        (store, id) => store.update(id, {
                          'scheduledStartAt': picked?.toUtc().toIso8601String(),
                          // The end belongs to the block: clearing the start
                          // clears it, and a moved start must never be left
                          // behind an end (§7.1 would derive a backwards
                          // block). Null → the derivation uses 30 minutes.
                          'scheduledEndAt': null,
                        }),
                      ),
                    ),
                    _DateRow(
                      label: 'task.remind'.tr(),
                      icon: Icons.alarm,
                      value: task.remindAt,
                      onPicked: (picked) => _apply(
                        (store, id) => store.update(id, {
                          'remindAt': picked?.toUtc().toIso8601String(),
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              _SectionCard(
                title: 'task.tags'.tr(),
                child: _TagPicker(
                  task: task,
                  onApply: (action) => _apply(action),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
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
  const _SectionCard({required this.title, required this.child});

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
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
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

class _DateRow extends ConsumerWidget {
  const _DateRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onPicked,
    super.key,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
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
        local == null ? 'task.notSet'.tr() : local.toString().split('.').first,
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
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: local ?? now,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now.add(const Duration(days: 365 * 5)),
        );
        if (picked != null) {
          // Day-only pick lands on the user's default task time (OPH-161).
          onPicked(
            applyDefaultTaskTime(picked, ref.read(defaultTaskTimeProvider)),
          );
        }
      },
    );
  }
}

class _TagPicker extends ConsumerWidget {
  const _TagPicker({required this.task, required this.onApply});

  final Task task;
  final void Function(TaskAction) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    return tags.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (items) => items.isEmpty
          ? Text(
              'task.noTagsYet'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in items)
                  FilterChip(
                    avatar: CircleAvatar(
                      backgroundColor: colorFromRgbHex(tag.colorRgb),
                      radius: 6,
                    ),
                    label: Text(tag.name),
                    selected: task.tagIds.contains(tag.id),
                    onSelected: (selected) {
                      final next = {...task.tagIds};
                      selected ? next.add(tag.id) : next.remove(tag.id);
                      onApply((store, id) => store.setTags(id, next.toList()));
                    },
                  ),
              ],
            ),
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
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              item.title,
              style: item.isDone
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            value: item.isDone,
            onChanged: (v) => widget.onApply(
              (store, id) =>
                  store.setChecklistItemDone(id, item.id, isDone: v ?? false),
            ),
            secondary: IconButton(
              tooltip: 'task.removeItem'.tr(),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => widget.onApply((store, id) async {
                await store.deleteChecklistItem(id, item.id);
                return null;
              }),
            ),
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
