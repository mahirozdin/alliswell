import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../projects/data/project.dart';
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
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
        title: const Text('Task'),
        actions: [
          IconButton(
            tooltip: task.isCompleted ? 'Reopen' : 'Complete',
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
                decoration: const InputDecoration(
                  hintText: 'Task title',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
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
                title: 'Details',
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
                            decoration: const InputDecoration(
                              labelText: 'Status',
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
                            decoration: const InputDecoration(
                              labelText: 'Priority',
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
                    const SizedBox(height: 4),
                    SwitchListTile(
                      key: const Key('urgent-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Urgent alarm'),
                      subtitle: const Text(
                        'Insistent reminder that must be acknowledged',
                      ),
                      value: task.isUrgent,
                      onChanged: (v) => _apply(
                        (store, id) => store.update(id, {'isUrgent': v}),
                      ),
                    ),
                    _DateRow(
                      label: 'Due',
                      value: task.dueAt,
                      onPicked: (picked) => _apply(
                        (store, id) => store.update(id, {
                          'dueAt': picked?.toUtc().toIso8601String(),
                        }),
                      ),
                    ),
                    _DateRow(
                      label: 'Remind',
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
                title: 'Tags',
                child: _TagPicker(
                  task: task,
                  onApply: (action) => _apply(action),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              _SectionCard(
                title: 'Checklist',
                child: _Checklist(
                  task: task,
                  onApply: (action) => _apply(action),
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

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final DateTime? value;
  final void Function(DateTime?) onPicked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = value?.toLocal();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(label == 'Due' ? Icons.flag_outlined : Icons.alarm),
      title: Text(label),
      subtitle: Text(
        local == null ? 'Not set' : local.toString().split('.').first,
        style: TextStyle(
          color: local == null ? scheme.onSurfaceVariant : scheme.onSurface,
          fontWeight: local == null ? null : FontWeight.w600,
        ),
      ),
      trailing: local == null
          ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
          : IconButton(
              tooltip: 'Clear $label',
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
          onPicked(DateTime(picked.year, picked.month, picked.day, 9));
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
              'No tags in this workspace yet.',
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
              tooltip: 'Remove item',
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
            hintText: 'Add checklist item…',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add item',
              onPressed: _add,
            ),
          ),
        ),
      ],
    );
  }
}
