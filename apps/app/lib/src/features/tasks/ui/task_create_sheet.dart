import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../core/date_format.dart';
import '../../../core/date_input.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheet_rows.dart';
import '../../../widgets/status_views.dart';
import '../../files/providers.dart';
import '../../files/ui/file_widgets.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../tags/ui/tag_input.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../data/task_defaults.dart';
import '../providers.dart';
import '../../../core/recurrence.dart';
import '../../../core/recurrence_text.dart';
import 'repeat_dialog.dart';
import 'task_visuals.dart';

/// Full task creation sheet behind the Home FAB (feedback round 2): title
/// plus the options quick-add skips — project, priority, due/remind
/// date-times and the urgent toggle.
Future<void> showTaskCreateSheet(
  BuildContext context, {
  DateTime? initialDue,
  String? initialStatus,
  Task? task,
  String? initialTitle,
  String? initialDescription,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => TaskCreateSheet(
      initialDue: initialDue,
      initialStatus: initialStatus,
      task: task,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
    ),
  );
}

class TaskCreateSheet extends ConsumerStatefulWidget {
  const TaskCreateSheet({
    super.key,
    this.initialDue,
    this.initialStatus,
    this.task,
    this.initialTitle,
    this.initialDescription,
  });

  /// Prefilled due date (e.g. the day selected on the Home calendar).
  final DateTime? initialDue;

  /// Status the new task is born with (the board's empty-column "+ Add task",
  /// OPH-168). Create mode only.
  final String? initialStatus;

  /// When set, the sheet EDITS this task ("Plan task" / "Save") instead of
  /// creating a new one — the Inbox triage flow (OPH-107).
  final Task? task;

  /// Prefilled title and description (OPH-243): text shared into the app from
  /// another one lands here, already split, when there is no AI to structure
  /// it. Create mode only — in edit mode the task's own values win.
  final String? initialTitle;
  final String? initialDescription;

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

  /// Round 14: true while the reminder is merely DERIVED from the deadline
  /// (1 h before, [kAwAutoReminderGap]) — a derived value follows the due date
  /// around; one the user touched never gets overwritten.
  bool _remindAuto = false;
  bool _saving = false;

  /// OPH-208: the rule the user configured before the task exists. A series
  /// needs a task to adopt (`fromTaskId`), so the order is save → start
  /// repeating, in that transaction-less but deterministic sequence.
  AwRepeatRule? _repeatRule;
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
      // OPH-243: text shared from another app arrives already split into a
      // title and a body. The caret goes to the END — the field autofocuses,
      // and a prefilled autofocused field otherwise opens with everything
      // selected, one keystroke away from destroying what was shared.
      _title.text = widget.initialTitle ?? '';
      _title.selection = TextSelection.collapsed(offset: _title.text.length);
      _description.text = widget.initialDescription ?? '';
      // Round 14 creation defaults: medium priority, urgent alarm armed. The
      // sheet SHOWS both before saving — defaults, not hidden behavior.
      _priority = 'medium';
      _isUrgent = true;
      _syncAutoReminder();
    }
  }

  /// Keeps a derived reminder glued to the deadline (round 14): due set and
  /// reminder empty-or-derived → reminder lands [kAwAutoReminderGap] before
  /// due; due cleared → a derived reminder leaves with it. A hand-set
  /// reminder is never touched.
  void _syncAutoReminder() {
    if (_dueAt != null && (_remindAt == null || _remindAuto)) {
      _remindAt = awAutoReminderFor(_dueAt);
      _remindAuto = true;
    } else if (_dueAt == null && _remindAuto) {
      _remindAt = null;
      _remindAuto = false;
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

  /// [anchor]: the date this field lives next to — see [awInitialPickerDate].
  /// OPH-191: the picking itself now lives in one place (`core/date_input.dart`)
  /// so the detail screen cannot drift away from it again; backing out keeps the
  /// current value.
  Future<DateTime?> _pickDateTime(
    DateTime? current, {
    DateTime? anchor,
  }) async =>
      await awPickDateTime(context, ref, current: current, anchor: anchor) ??
      current;

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
          'status': ?widget.initialStatus,
          'description': ?_descriptionOrNull,
          'projectId': ?_projectId,
          if (_priority != 'none') 'priority': _priority,
          'dueAt': ?_dueAt?.toUtc().toIso8601String(),
          'remindAt': ?_remindAt?.toUtc().toIso8601String(),
          if (_isUrgent) 'isUrgent': true,
          if (_tagIds.isNotEmpty) 'tagIds': _tagIds,
        });
        // OPH-208: the task exists now, so the series has something to adopt —
        // its own day becomes the first occurrence instead of a duplicate.
        final rule = _repeatRule;
        if (rule != null) {
          await ref
              .read(seriesStoreProvider)
              .create(
                workspaceId: workspaceId,
                rule: rule,
                template: {
                  'title': _title.text.trim(),
                  'description': _descriptionOrNull,
                  'projectId': _projectId,
                  'priority': _priority,
                  'isUrgent': _isUrgent,
                  'tagIds': _tagIds,
                },
                anchorAt: _dueAt?.toLocal() ?? DateTime.now(),
                fromTaskId: taskId,
              );
        }
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

  /// One formatter, the user's chosen format (OPH-174 — DESIGN §17 D1).
  String _format(DateTime? value, String dateFormat) => value == null
      ? 'task.notSet'.tr()
      : awFormatDateTime(value, format: dateFormat);

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final projects = ref.watch(projectsControllerProvider).value ?? const [];
    final dateFormat = ref.watch(dateFormatProvider);

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
                        ref.watch(storageStatusProvider).value?.configured ??
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
                        for (final (index, file) in _pendingFiles.indexed)
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
                              onPressed: () =>
                                  setState(() => _pendingFiles.removeAt(index)),
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
              // Round 9 #3: `start` alignment, so a helper/error line under one
              // field can never shove the other one out of line. The "no
              // projects yet" hint that used to do exactly that is GONE — the
              // picker already carries "+ Add project" (OPH-163), and an empty
              // list explains itself the moment you open it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ProjectPickerField(
                      key: const Key('task-sheet-project'),
                      projects: projects,
                      value: _projectId,
                      decoration: InputDecoration(
                        labelText: 'task.project'.tr(),
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
                subtitle: _format(_dueAt, dateFormat),
                isSet: _dueAt != null,
                clearTooltip: 'task.clearDue'.tr(),
                onClear: () => setState(() {
                  _dueAt = null;
                  _syncAutoReminder();
                }),
                onTap: () async {
                  final picked = await _pickDateTime(_dueAt);
                  setState(() {
                    _dueAt = picked;
                    _syncAutoReminder();
                  });
                },
              ),
              const SizedBox(height: 8),
              _SheetTile(
                tileKey: const Key('task-sheet-remind'),
                icon: Icons.alarm,
                title: 'task.remind'.tr(),
                subtitle: _format(_remindAt, dateFormat),
                isSet: _remindAt != null,
                clearTooltip: 'task.clearReminder'.tr(),
                onClear: () => setState(() {
                  _remindAt = null;
                  // An explicit clear is a decision — stop deriving.
                  _remindAuto = false;
                }),
                onTap: () async {
                  // A reminder belongs near its deadline, so it opens on the
                  // due day when there is one (OPH-173).
                  final picked = await _pickDateTime(_remindAt, anchor: _dueAt);
                  setState(() {
                    if (picked != _remindAt) {
                      _remindAt = picked;
                      _remindAuto = false;
                    }
                  });
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
              // OPH-208 (DESIGN §25 R1): the Repeat switch, in the create
              // sheet too. Editing an existing task keeps its rule on the
              // detail screen, where the series it may already belong to lives.
              if (widget.task == null) ...[
                const SizedBox(height: 8),
                _SheetSurface(
                  child: Column(
                    children: [
                      SwitchListTile(
                        key: const Key('task-sheet-repeat'),
                        title: Text('repeat.switchTitle'.tr()),
                        subtitle: Text('repeat.switchSubtitle'.tr()),
                        secondary: Icon(
                          Icons.repeat,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        value: _repeatRule != null,
                        onChanged: (wanted) async {
                          if (!wanted) {
                            setState(() => _repeatRule = null);
                            return;
                          }
                          final rule = await showRepeatDialog(
                            context,
                            anchor: _dueAt?.toLocal() ?? DateTime.now(),
                          );
                          // Cancelling leaves the switch off — no half rule.
                          if (rule != null) setState(() => _repeatRule = rule);
                        },
                      ),
                      if (_repeatRule != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 12,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              awRepeatSentence(
                                _repeatRule!,
                                dateFormat: ref.watch(dateFormatProvider),
                              ),
                              key: const Key('task-sheet-repeat-summary'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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

// _SheetSurface / _SheetTile moved to lib/src/widgets/sheet_rows.dart
// (AwSheetSurface / AwSheetTile) in OPH-221 so the AI confirm card reuses the
// exact same rows (DESIGN §24 AI5). This file aliases them to keep its call
// sites unchanged.
typedef _SheetSurface = AwSheetSurface;
typedef _SheetTile = AwSheetTile;
