import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../screens/home_shell.dart';
import '../../../sections.dart';
import '../data/task.dart';
import '../providers.dart';

/// Shared list screen for Inbox / Today / Upcoming (OPH-037): a quick-add bar
/// on top, server-filtered tasks below.
class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key, required this.kind});

  final TaskListKind kind;

  AppSection get _section => switch (kind) {
    TaskListKind.inbox => AppSection.inbox,
    TaskListKind.today => AppSection.today,
    TaskListKind.upcoming => AppSection.upcoming,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = taskListProvider(kind);
    final tasks = ref.watch(provider);
    return Scaffold(
      appBar: buildSectionAppBar(context, _section.title),
      body: Column(
        children: [
          _QuickAddBar(kind: kind),
          const Divider(height: 1),
          Expanded(
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(provider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? _EmptyList(section: _section)
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _TaskTile(task: items[index], kind: kind),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddBar extends ConsumerStatefulWidget {
  const _QuickAddBar({required this.kind});

  final TaskListKind kind;

  @override
  ConsumerState<_QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<_QuickAddBar> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(taskListProvider(widget.kind).notifier).quickAdd(title);
      _controller.clear();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add task: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        key: const Key('quick-add'),
        controller: _controller,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: switch (widget.kind) {
            TaskListKind.inbox => 'Quick add to Inbox…',
            TaskListKind.today => 'Add a task due today…',
            TaskListKind.upcoming => 'Add a task for tomorrow…',
          },
          prefixIcon: const Icon(Icons.add),
          suffixIcon: _submitting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Add task',
                  onPressed: _submit,
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.kind});

  final Task task;
  final TaskListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = task.dueAt?.toLocal();
    return ListTile(
      leading: Checkbox(
        value: task.isCompleted,
        onChanged: (_) =>
            ref.read(taskListProvider(kind).notifier).toggleCompleted(task),
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
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            section.selectedIcon,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('All clear', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(section.description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
