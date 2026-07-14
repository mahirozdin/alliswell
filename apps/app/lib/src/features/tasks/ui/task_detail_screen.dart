import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/data/project.dart';
import '../../tags/tags.dart';
import '../data/task.dart';
import '../data/tasks_api.dart';
import '../providers.dart';

/// One task write: gets the API + task id, awaits server confirmation.
typedef TaskAction = Future<Object?> Function(TasksApi api, String taskId);

/// Task detail (OPH-037): status, priority, urgent toggle, dates, tags and
/// checklist — every control PATCHes the API and re-fetches.
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

class _TaskDetail extends ConsumerWidget {
  const _TaskDetail({required this.task});

  final Task task;

  Future<void> _apply(WidgetRef ref, TaskAction action) async {
    await action(ref.read(tasksApiProvider), task.id);
    invalidateTaskData(ref, taskId: task.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              ref,
              (api, id) => task.isCompleted ? api.reopen(id) : api.complete(id),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            task.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          if (task.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(task.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('status-dropdown'),
                  initialValue: task.status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final status in kTaskStatuses)
                      DropdownMenuItem(value: status, child: Text(status)),
                  ],
                  onChanged: (v) {
                    if (v != null && v != task.status) {
                      _apply(ref, (api, id) => api.update(id, {'status': v}));
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('priority-dropdown'),
                  initialValue: task.priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final priority in kTaskPriorities)
                      DropdownMenuItem(value: priority, child: Text(priority)),
                  ],
                  onChanged: (v) {
                    if (v != null && v != task.priority) {
                      _apply(ref, (api, id) => api.update(id, {'priority': v}));
                    }
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('urgent-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Urgent alarm'),
            subtitle: const Text(
              'Insistent reminder that must be acknowledged',
            ),
            value: task.isUrgent,
            onChanged: (v) =>
                _apply(ref, (api, id) => api.update(id, {'isUrgent': v})),
          ),
          _DateRow(
            label: 'Due',
            value: task.dueAt,
            onPicked: (picked) => _apply(
              ref,
              (api, id) =>
                  api.update(id, {'dueAt': picked?.toUtc().toIso8601String()}),
            ),
          ),
          _DateRow(
            label: 'Remind',
            value: task.remindAt,
            onPicked: (picked) => _apply(
              ref,
              (api, id) => api.update(id, {
                'remindAt': picked?.toUtc().toIso8601String(),
              }),
            ),
          ),
          const SizedBox(height: 16),
          Text('Tags', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _TagPicker(task: task, onApply: (action) => _apply(ref, action)),
          const SizedBox(height: 16),
          Text('Checklist', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _Checklist(task: task, onApply: (action) => _apply(ref, action)),
        ],
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
    final local = value?.toLocal();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(label == 'Due' ? Icons.flag_outlined : Icons.alarm),
      title: Text(label),
      subtitle: Text(
        local == null ? 'Not set' : local.toString().split('.').first,
      ),
      trailing: local == null
          ? null
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
                      onApply((api, id) => api.setTags(id, next.toList()));
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
    widget.onApply((api, id) => api.addChecklistItem(id, title));
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
              (api, id) =>
                  api.setChecklistItemDone(id, item.id, isDone: v ?? false),
            ),
            secondary: IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => widget.onApply((api, id) async {
                await api.deleteChecklistItem(id, item.id);
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
