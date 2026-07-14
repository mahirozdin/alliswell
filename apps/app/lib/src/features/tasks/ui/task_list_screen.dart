import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../screens/home_shell.dart';
import '../../../sections.dart';
import '../providers.dart';
import 'task_tile.dart';

/// Inbox (OPH-037, slimmed in feedback round 1): quick capture without dates —
/// the chronological views live on Home/Calendar now.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(inboxTasksProvider);
    return Scaffold(
      appBar: buildSectionAppBar(context, AppSection.inbox.title),
      body: Column(
        children: [
          const _QuickAddBar(),
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
                      onPressed: () => ref.invalidate(inboxTasksProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyInbox()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          TaskTile(task: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddBar extends ConsumerStatefulWidget {
  const _QuickAddBar();

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
      await ref.read(inboxTasksProvider.notifier).quickAdd(title);
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
          hintText: 'Quick add to Inbox…',
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppSection.inbox.selectedIcon,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('Inbox zero', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(AppSection.inbox.description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
