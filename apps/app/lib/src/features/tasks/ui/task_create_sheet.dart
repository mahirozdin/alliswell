import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../files/providers.dart';
import '../../files/ui/file_widgets.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../tags/ui/tag_input.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../providers.dart';
import 'task_visuals.dart';

/// Full task creation sheet behind the Home FAB (feedback round 2): title
/// plus the options quick-add skips — project, priority, due/remind
/// date-times and the urgent toggle.
Future<void> showTaskCreateSheet(
  BuildContext context, {
  DateTime? initialDue,
  Task? task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => TaskCreateSheet(initialDue: initialDue, task: task),
  );
}

class TaskCreateSheet extends ConsumerStatefulWidget {
  const TaskCreateSheet({super.key, this.initialDue, this.task});

  /// Prefilled due date (e.g. the day selected on the Home calendar).
  final DateTime? initialDue;

  /// When set, the sheet EDITS this task ("Plan task" / "Save") instead of
  /// creating a new one — the Inbox triage flow (OPH-107).
  final Task? task;

  @override
  ConsumerState<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends ConsumerState<TaskCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<String> _tagIds = const [];
  final List<PickedUpload> _pendingFiles = [];
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
    final task = widget.task;
    if (task != null) {
      _title.text = task.title;
      _description.text = task.description ?? '';
      _tagIds = List.of(task.tagIds);
      _projectId = task.projectId;
      _priority = task.priority;
      _dueAt = task.dueAt?.toLocal();
      _remindAt = task.remindAt?.toLocal();
      _isUrgent = task.isUrgent;
    } else {
      _dueAt = widget.initialDue;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Empty description = no description — never an empty-string field.
  String? get _descriptionOrNull {
    final value = _description.text.trim();
    return value.isEmpty ? null : value;
  }

  /// OPH-166: files are PICKED here but uploaded on save — a task must exist
  /// to own them. Until then they are plain local selections (removable).
  Future<void> _pickFiles() async {
    final picked = await ref.read(filePickerProvider)();
    if (picked.isEmpty || !mounted) return;
    setState(() => _pendingFiles.addAll(picked));
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    // The user's default task time backs both the picker's starting position
    // and the "picked a date, dismissed the clock" fallback (OPH-161).
    final (defHour, defMinute) = parseTaskTime(
      ref.read(defaultTaskTimeProvider),
    );
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
          : TimeOfDay(hour: defHour, minute: defMinute),
    );
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? defHour,
      time?.minute ?? defMinute,
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final editing = widget.task;
      if (editing != null) {
        // Triage: update in place. Nulls are sent so cleared fields clear; a
        // date or project here promotes an inbox capture to 'open' (OPH-107).
        await ref.read(taskStoreProvider).update(editing.id, {
          'title': _title.text.trim(),
          'description': _descriptionOrNull,
          'projectId': _projectId,
          'priority': _priority,
          'dueAt': _dueAt?.toUtc().toIso8601String(),
          'remindAt': _remindAt?.toUtc().toIso8601String(),
          'isUrgent': _isUrgent,
          'tagIds': _tagIds,
        });
      } else {
        final workspaces = await ref.read(workspacesProvider.future);
        if (workspaces.isEmpty) throw StateError('No workspace available');
        final workspaceId = workspaces.first.id;
        final taskId = await ref.read(taskStoreProvider).create(workspaceId, {
          'title': _title.text.trim(),
          'description': ?_descriptionOrNull,
          'projectId': ?_projectId,
          if (_priority != 'none') 'priority': _priority,
          'dueAt': ?_dueAt?.toUtc().toIso8601String(),
          'remindAt': ?_remindAt?.toUtc().toIso8601String(),
          if (_isUrgent) 'isUrgent': true,
          if (_tagIds.isNotEmpty) 'tagIds': _tagIds,
        });
        // OPH-166: now the task exists — hand the picked files to the upload
        // machinery (F2 rows surface on detail; the sheet does not wait).
        final uploads = ref.read(uploadsProvider.notifier);
        for (final source in _pendingFiles) {
          unawaited(
            uploads.start(
              workspaceId: workspaceId,
              targetType: 'task',
              targetId: taskId,
              source: source,
            ),
          );
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _format(DateTime? value) =>
      value == null ? 'task.notSet'.tr() : value.toString().split('.').first;

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
              Text(
                widget.task != null
                    ? 'task.planTask'.tr()
                    : 'task.newTask'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('task-sheet-title'),
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: 'task.title'.tr()),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'task.titleRequired'.tr()
                    : null,
              ),
              const SizedBox(height: 12),
              // The task's OWN context (OPH-164) — links, short details. Not a
              // Note: long-form writing belongs to a linked note.
              TextFormField(
                key: const Key('task-sheet-description'),
                controller: _description,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'task.descriptionLabel'.tr(),
                  hintText: 'task.descriptionHint'.tr(),
                ),
              ),
              const SizedBox(height: 12),
              // OPH-165: tags are born here — type, Enter, chip; unknown
              // names auto-create (DESIGN §13).
              TagInputField(
                value: _tagIds,
                onChanged: (tagIds) => setState(() => _tagIds = tagIds),
              ),
              const SizedBox(height: 12),
              // OPH-166: attachments, picked now, uploaded on save. Edit/triage
              // mode has the full section on detail — no duplicate here.
              if (widget.task == null) ...[
                Builder(
                  builder: (context) {
                    final configured =
                        ref
                            .watch(storageStatusProvider)
                            .value
                            ?.configured ??
                        true; // optimistic while loading (F6 idiom)
                    if (!configured && _pendingFiles.isEmpty) {
                      return Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AwSpace.x2),
                          Expanded(
                            child: Text(
                              'file.notConfigured'.tr(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, file)
                            in _pendingFiles.indexed)
                          ListTile(
                            key: Key('pending-file-$index'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              fileKindIcon(file.mime ?? ''),
                              size: 20,
                            ),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(formatBytes(file.sizeBytes)),
                            trailing: IconButton(
                              tooltip: 'common.remove'.tr(),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(
                                () => _pendingFiles.removeAt(index),
                              ),
                            ),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: const Key('task-sheet-attach'),
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.attach_file, size: 18),
                            label: Text('file.add'.tr()),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: ProjectPickerField(
                      key: const Key('task-sheet-project'),
                      projects: projects,
                      value: _projectId,
                      decoration: InputDecoration(
                        labelText: 'task.project'.tr(),
                        // With no projects the picker still carries "+ Add
                        // project" (OPH-163) — the hint tells first-timers
                        // why the list is otherwise empty (OPH-106).
                        helperText: projects.isEmpty
                            ? 'task.noProjectsHint'.tr()
                            : null,
                      ),
                      onChanged: (v) => setState(() => _projectId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const Key('task-sheet-priority'),
                      initialValue: _priority,
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
                title: 'task.due'.tr(),
                subtitle: _format(_dueAt),
                isSet: _dueAt != null,
                clearTooltip: 'task.clearDue'.tr(),
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
                title: 'task.remind'.tr(),
                subtitle: _format(_remindAt),
                isSet: _remindAt != null,
                clearTooltip: 'task.clearReminder'.tr(),
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
                  title: Text('task.urgentAlarm'.tr()),
                  subtitle: Text('task.urgentAlarmSub'.tr()),
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
                    : Text(
                        widget.task != null
                            ? 'common.save'.tr()
                            : 'task.createTask'.tr(),
                      ),
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
