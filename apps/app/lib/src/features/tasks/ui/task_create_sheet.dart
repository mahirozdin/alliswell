import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../projects/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../providers.dart';
import 'task_visuals.dart';

/// Full task creation sheet behind the Home FAB (feedback round 2): title
/// plus the options quick-add skips — project, priority, due/remind
/// date-times and the urgent toggle.
Future<void> showTaskCreateSheet(BuildContext context, {DateTime? initialDue}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => TaskCreateSheet(initialDue: initialDue),
  );
}

class TaskCreateSheet extends ConsumerStatefulWidget {
  const TaskCreateSheet({super.key, this.initialDue});

  /// Prefilled due date (e.g. the day selected on the Home calendar).
  final DateTime? initialDue;

  @override
  ConsumerState<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends ConsumerState<TaskCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  String? _projectId;
  String _priority = 'none';
  DateTime? _dueAt;
  DateTime? _remindAt;
  bool _isUrgent = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.initialDue;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return current;
    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final workspaces = await ref.read(workspacesProvider.future);
      if (workspaces.isEmpty) throw StateError('No workspace available');
      await ref.read(tasksApiProvider).create(workspaces.first.id, {
        'title': _title.text.trim(),
        'projectId': ?_projectId,
        if (_priority != 'none') 'priority': _priority,
        'dueAt': ?_dueAt?.toUtc().toIso8601String(),
        'remindAt': ?_remindAt?.toUtc().toIso8601String(),
        if (_isUrgent) 'isUrgent': true,
      });
      if (mounted) {
        invalidateTaskData(ref);
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _format(DateTime? value) =>
      value == null ? 'Not set' : value.toString().split('.').first;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final projects = ref.watch(projectsControllerProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New task', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('task-sheet-title'),
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Give the task a title'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      key: const Key('task-sheet-project'),
                      initialValue: _projectId,
                      decoration: const InputDecoration(labelText: 'Project'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No project'),
                        ),
                        for (final project in projects)
                          DropdownMenuItem(
                            value: project.id,
                            // The project's color leads its name (feedback
                            // round 3): a small filled dot, never a hex code.
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  backgroundColor: project.color,
                                  radius: 6,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    project.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _projectId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const Key('task-sheet-priority'),
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: [
                        for (final priority in kTaskPriorities)
                          DropdownMenuItem(
                            value: priority,
                            child: PriorityLabel(priority: priority),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? _priority),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SheetTile(
                tileKey: const Key('task-sheet-due'),
                icon: Icons.flag_outlined,
                title: 'Due',
                subtitle: _format(_dueAt),
                isSet: _dueAt != null,
                clearTooltip: 'Clear due date',
                onClear: () => setState(() => _dueAt = null),
                onTap: () async {
                  final picked = await _pickDateTime(_dueAt);
                  setState(() => _dueAt = picked);
                },
              ),
              const SizedBox(height: 8),
              _SheetTile(
                tileKey: const Key('task-sheet-remind'),
                icon: Icons.alarm,
                title: 'Remind',
                subtitle: _format(_remindAt),
                isSet: _remindAt != null,
                clearTooltip: 'Clear reminder',
                onClear: () => setState(() => _remindAt = null),
                onTap: () async {
                  final picked = await _pickDateTime(_remindAt);
                  setState(() => _remindAt = picked);
                },
              ),
              const SizedBox(height: 8),
              _SheetSurface(
                child: SwitchListTile(
                  key: const Key('task-sheet-urgent'),
                  title: const Text('Urgent alarm'),
                  subtitle: const Text(
                    'Insistent reminder that must be acknowledged',
                  ),
                  secondary: Icon(
                    Icons.notification_important_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  value: _isUrgent,
                  onChanged: (v) => setState(() => _isUrgent = v),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AwInlineError(
                  message: _error!,
                  textKey: const Key('task-sheet-error'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('task-sheet-create'),
                onPressed: _saving ? null : _create,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create task'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filled rounded backdrop that makes tappable sheet rows read as controls.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Date/reminder picker row: filled surface, chevron affordance, clear action.
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSet,
    required this.clearTooltip,
    required this.onClear,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSet;
  final String clearTooltip;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SheetSurface(
      child: ListTile(
        key: tileKey,
        leading: Icon(icon, color: scheme.onSurfaceVariant),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isSet ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: isSet ? FontWeight.w600 : null,
          ),
        ),
        trailing: isSet
            ? IconButton(
                tooltip: clearTooltip,
                icon: const Icon(Icons.close),
                onPressed: onClear,
              )
            : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
