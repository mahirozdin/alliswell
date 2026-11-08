import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../core/format.dart';
import '../../../core/date_input.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/sheet_rows.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/word_safe_text.dart';
import '../../files/providers.dart';
import '../../files/ui/attach_menu.dart';
import '../../files/ui/file_widgets.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../tags/ui/tag_input.dart';
import '../../ee/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/task.dart';
import '../data/task_defaults.dart';
import '../data/task_when.dart';
import '../providers.dart';
import '../../../core/recurrence.dart';
import '../../../core/recurrence_text.dart';
import 'duration_picker.dart';
import 'repeat_dialog.dart';
import 'task_visuals.dart';

/// The tallest a scroll-controlled sheet may grow: the screen below the top
/// safe area, minus one [kAwSheetScrimStrip] of scrim left to tap.
double awSheetMaxHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final available = media.size.height - media.padding.top - kAwSheetScrimStrip;
  return available < 0 ? 0 : available;
}

/// The scrim strip a full-height sheet leaves above itself (E-24): one tap
/// target (DESIGN G-taps ≥ 48 dp).
const double kAwSheetScrimStrip = 56;

/// Full task creation sheet behind the Home FAB (feedback round 2): title
/// plus the options quick-add skips — project, priority, due/remind
/// date-times and the urgent toggle.
///
/// OPH-403 (U-11, DESIGN §49): from [kAwWideBreakpoint] it is a centred
/// dialog instead of a phone sheet; on a phone the sheet's route holds a
/// swipe down that would throw away what was typed (see [_GuardedSheetRoute]).
Future<void> showTaskCreateSheet(
  BuildContext context, {
  DateTime? initialDue,
  String? initialStatus,
  Task? task,
  String? initialTitle,
  String? initialDescription,
}) {
  final guard = AwDiscardGuard();
  Widget sheet({required bool dialog}) => TaskCreateSheet(
    initialDue: initialDue,
    initialStatus: initialStatus,
    task: task,
    initialTitle: initialTitle,
    initialDescription: initialDescription,
    guard: guard,
    dialog: dialog,
  );

  if (MediaQuery.sizeOf(context).width >= kAwWideBreakpoint) {
    return showDialog<void>(
      context: context,
      // OPH-212: the root navigator, above the shell's glass chrome.
      useRootNavigator: true,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: kAwCreateDialogWidth,
            minWidth: kAwCreateDialogWidth,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: sheet(dialog: true),
        ),
      ),
    );
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _GuardedSheetRoute<void>(
      guard: guard,
      // What showModalBottomSheet passes; the route is built by hand only so
      // it can hold a pop (OPH-403).
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
      // renders UNDER the shell's own glass bar and FAB — they are painted by
      // the Scaffold that owns the branch, above its body.
      isScrollControlled: true,
      useSafeArea: true,
      // OPH-395 (E-24): with the keyboard up the sheet grew to the top of the
      // safe area and left the scrim ("Close" to VoiceOver) no visible area,
      // so only a drag on the handle closed it. A tap-target-tall strip of
      // scrim always stays above it; the form scrolls inside.
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: awSheetMaxHeight(context),
      ),
      builder: (_) => sheet(dialog: false),
    ),
  );
}

/// The desktop create dialog's width (U-08: a centred 640 px dialog).
const double kAwCreateDialogWidth = 640;

/// What a create sheet and its route share so that no way of closing it —
/// the Cancel button, the scrim, Back, Escape, or a swipe down — loses typed
/// text without asking (OPH-403).
class AwDiscardGuard {
  /// True while closing would throw something away.
  bool Function() isDirty = _never;

  /// Asked when a pop was held; the sheet shows its "discard?" question.
  VoidCallback? onHeld;

  /// Set once the sheet decided to close (saved, or discard confirmed).
  bool released = false;

  static bool _never() => false;

  bool get holds => !released && isDirty();
}

/// A modal bottom sheet route that can refuse a pop.
///
/// A swipe down on a sheet ends in `Navigator.pop` itself — straight past a
/// [PopScope], which only `maybePop` (scrim, Back, Escape) consults. Refusing
/// in [didPop] is the one place every pop goes through; the sheet is driven
/// back up and asks instead.
class _GuardedSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _GuardedSheetRoute({
    required this.guard,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.useSafeArea,
    super.constraints,
  });

  final AwDiscardGuard guard;

  @override
  bool didPop(T? result) {
    if (guard.holds) {
      controller?.forward();
      // The navigator is locked while it pops; the question is a new route,
      // so it is pushed right after.
      final onHeld = guard.onHeld;
      if (onHeld != null) scheduleMicrotask(onHeld);
      return false;
    }
    return super.didPop(result);
  }
}

class TaskCreateSheet extends ConsumerStatefulWidget {
  const TaskCreateSheet({
    super.key,
    this.initialDue,
    this.initialStatus,
    this.task,
    this.initialTitle,
    this.initialDescription,
    this.guard,
    this.dialog = false,
  });

  /// Shared with the route that shows the sheet (OPH-403); null when the
  /// sheet is built on its own (a test), which then only guards `maybePop`.
  final AwDiscardGuard? guard;

  /// True inside the desktop dialog: no keyboard inset of its own (the
  /// [Dialog] already moves out of the keyboard's way).
  final bool dialog;

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

  /// "When" (OPH-372, ADR-0053) — a local DAY, never an instant. Independent
  /// of the deadline: setting it never touches [_dueAt], [_remindAt] or the
  /// auto-reminder (DESIGN §38 W2).
  DateTime? _whenDay;

  /// How long it takes, in minutes (OPH-372). Null = not set.
  int? _estimatedMinutes;

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

  /// What the text fields opened with — closing only asks when they differ
  /// (OPH-403), so a shared text dismissed untouched, or a triage sheet
  /// opened and closed, goes without a question.
  late final String _openedTitle;
  late final String _openedDescription;
  bool _asking = false;

  bool get _hasTitle => _title.text.trim().isNotEmpty;

  bool get _dirty =>
      _title.text != _openedTitle ||
      _description.text != _openedDescription ||
      _pendingFiles.isNotEmpty;

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

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
      _whenDay = taskWhenDay(task);
      _estimatedMinutes = task.estimatedMinutes;
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
    _openedTitle = _title.text;
    _openedDescription = _description.text;
    _title.addListener(_onTextChanged);
    _description.addListener(_onTextChanged);
    final guard = widget.guard;
    if (guard != null) {
      guard.isDirty = () => mounted && _dirty;
      guard.onHeld = () => unawaited(_confirmDiscard());
    }
  }

  /// Closes the sheet for good: nothing guards it any more.
  void _close() {
    widget.guard?.released = true;
    Navigator.of(context).pop();
  }

  /// "Discard what you typed?" — asked by every way out once something is
  /// typed (DESIGN §49 N3). Keep editing is the default, safe answer.
  Future<void> _confirmDiscard() async {
    if (_asking || !mounted) return;
    _asking = true;
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        key: const Key('task-sheet-discard'),
        title: Text('task.discardTitle'.tr()),
        actions: [
          TextButton(
            key: const Key('task-sheet-keep-editing'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('task.discardKeep'.tr()),
          ),
          TextButton(
            key: const Key('task-sheet-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('task.discardConfirm'.tr()),
          ),
        ],
      ),
    );
    _asking = false;
    if (discard == true && mounted) _close();
  }

  /// The header's Cancel: closes an untouched sheet, asks otherwise.
  void _cancel() {
    if (_dirty) {
      unawaited(_confirmDiscard());
    } else {
      _close();
    }
  }

  /// Add, the keyboard's Done, Ctrl/⌘+Enter: one way in, dead without a title.
  void _submit() {
    if (_saving || !_hasTitle) return;
    unawaited(_create());
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
    final guard = widget.guard;
    if (guard != null) {
      guard.isDirty = () => false;
      guard.onHeld = null;
    }
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
  /// OPH-244: the picking moved into [AttachButton]; this only files what came
  /// back. Uploads still wait for save — a task that does not exist yet has no
  /// id to attach to.
  void _addPending(List<PickedUpload> picked) {
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
          'startAt': _whenDay == null ? null : awWhenIso(_whenDay!),
          'estimatedMinutes': _estimatedMinutes,
          'isUrgent': _isUrgent,
          'tagIds': _tagIds,
        });
      } else {
        final workspaceId = await ref.read(activeWorkspaceIdProvider.future);
        if (workspaceId == null) throw StateError('No workspace available');
        final taskId = await ref.read(taskStoreProvider).create(workspaceId, {
          'title': _title.text.trim(),
          'status': ?widget.initialStatus,
          'description': ?_descriptionOrNull,
          'projectId': ?_projectId,
          if (_priority != 'none') 'priority': _priority,
          'dueAt': ?_dueAt?.toUtc().toIso8601String(),
          'remindAt': ?_remindAt?.toUtc().toIso8601String(),
          if (_whenDay != null) 'startAt': awWhenIso(_whenDay!),
          'estimatedMinutes': ?_estimatedMinutes,
          if (_isUrgent) 'isUrgent': true,
          if (_tagIds.isNotEmpty) 'tagIds': _tagIds,
        });
        // A task somebody adds is theirs until they give it away: in an
        // organisation's workspaces its author is put on it.
        await claimIfShared(ref.read, workspaceId: workspaceId, taskId: taskId);
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
                  // Duration is a series template field (server
                  // TEMPLATE_FIELDS); "when" is not — it belongs to one
                  // occurrence (ADR-0053).
                  'estimatedMinutes': ?_estimatedMinutes,
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
      if (mounted) _close();
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

    final form = SingleChildScrollView(
      key: const Key('task-sheet-form'),
      // OPH-400 (R-09): the title field's floating label sits half above its
      // border; at AX3 a fixed 4 pt let the scroll view clip it ("Başlık").
      padding: EdgeInsets.fromLTRB(
        24,
        awFloatingLabelClearance(context),
        24,
        24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('task-sheet-title'),
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.done,
              // OPH-403: Done creates — with a title; without one it only
              // closes the keyboard, as before.
              onFieldSubmitted: (_) => _submit(),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          subtitle: Text(awFormatFileSize(file.sizeBytes)),
                          trailing: IconButton(
                            tooltip: 'common.remove'.tr(),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _pendingFiles.removeAt(index)),
                          ),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AttachButton(
                          buttonKey: const Key('task-sheet-attach'),
                          style: AttachButtonStyle.text,
                          onPicked: (picks) async => _addPending(picks),
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
                    decoration: InputDecoration(labelText: 'task.project'.tr()),
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
            // OPH-372 (DESIGN §38 W1): "When" sits ABOVE the deadline — the
            // day you will do it, then the day it is due. A day only.
            _SheetTile(
              tileKey: const Key('task-sheet-when'),
              icon: Icons.wb_sunny_outlined,
              title: 'task.when'.tr(),
              subtitle: _whenDay == null
                  ? 'task.notSet'.tr()
                  : awFormatDate(_whenDay!, format: dateFormat),
              isSet: _whenDay != null,
              clearTooltip: 'task.clearWhen'.tr(),
              onClear: () => setState(() => _whenDay = null),
              onTap: () async {
                final picked = await awPickDate(context, current: _whenDay);
                if (picked != null && mounted) {
                  setState(() => _whenDay = picked);
                }
              },
            ),
            const SizedBox(height: 8),
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
            // OPH-372 (DESIGN §38 W3): how long it takes — the calendar
            // block is this long instead of 30 minutes.
            _SheetTile(
              tileKey: const Key('task-sheet-duration'),
              icon: Icons.timelapse_outlined,
              title: 'task.duration'.tr(),
              subtitle: _estimatedMinutes == null
                  ? 'task.notSet'.tr()
                  : awFormatDuration(_estimatedMinutes!, days: false),
              isSet: _estimatedMinutes != null,
              clearTooltip: 'task.clearDuration'.tr(),
              onClear: () => setState(() => _estimatedMinutes = null),
              onTap: () async {
                final picked = await showDurationPicker(
                  context,
                  current: _estimatedMinutes,
                );
                if (picked != null && mounted) {
                  setState(() => _estimatedMinutes = picked);
                }
              },
            ),
            const SizedBox(height: 8),
            // EE-052: item 3's own example, on screen. The switch stays
            // VISIBLE and goes dead when the role lacks the verb — the
            // alarm is a property of the task in front of you, so hiding it
            // would just make the setting look like it does not exist.
            // The subtitle says why, because a dead control with no reason
            // is indistinguishable from a bug.
            Builder(
              builder: (context) {
                final canUrgent = ref.watch(
                  canProvider('alarms.create_urgent'),
                );
                return _SheetSurface(
                  child: SwitchListTile(
                    key: const Key('task-sheet-urgent'),
                    title: Text('task.urgentAlarm'.tr()),
                    subtitle: Text(
                      canUrgent
                          ? 'task.urgentAlarmSub'.tr()
                          : 'perm.deniedUrgentAlarm'.tr(),
                    ),
                    secondary: Icon(
                      Icons.notification_important_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    value: _isUrgent && canUrgent,
                    onChanged: canUrgent
                        ? (v) => setState(() => _isUrgent = v)
                        : null,
                  ),
                );
              },
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
          ],
        ),
      ),
    );

    return PopScope(
      // Scrim, Back and Escape come through here; a swipe down goes through
      // the route's didPop ([_GuardedSheetRoute]).
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
          const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
              _submit,
        },
        child: Padding(
          padding: EdgeInsets.only(
            bottom: widget.dialog ? 0 : viewInsets.bottom,
            top: widget.dialog ? AwSpace.x2 : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(
                title: widget.task != null
                    ? 'task.planTask'.tr()
                    : 'task.newTask'.tr(),
                actionLabel: widget.task != null
                    ? 'common.save'.tr()
                    : 'common.add'.tr(),
                saving: _saving,
                onCancel: _cancel,
                onAction: _hasTitle && !_saving ? _submit : null,
              ),
              Flexible(child: form),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet's header (OPH-403, DESIGN §49 N1): Cancel on the left, the
/// sheet's name in the middle, Add (or Save) on the right — 17 pt w600 in the
/// link colour, dead while the title is empty. Always on the first screen,
/// above the scrolling form and the keyboard.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.actionLabel,
    required this.saving,
    required this.onCancel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A button's text style does not inherit the theme's family (the button
    // sets it outright), so name it: the same face as the sheet's title.
    final barAction = context.awText.barAction.copyWith(
      fontFamily: theme.textTheme.titleMedium?.fontFamily,
    );
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
      textStyle: barAction,
    );
    // OPH-400 (R-09): like a system navigation bar, the two bar actions stop
    // growing at 2× so the sheet's name keeps room for a whole word; past
    // that, Cancel and Add at AX3 alone were wider than a 393 pt phone.
    Widget barLabel(Widget child) =>
        MediaQuery.withClampedTextScaling(maxScaleFactor: 2.0, child: child);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
      child: Row(
        children: [
          TextButton(
            key: const Key('task-sheet-cancel'),
            style: buttonStyle.copyWith(
              textStyle: WidgetStatePropertyAll(
                barAction.copyWith(fontWeight: FontWeight.w400),
              ),
            ),
            onPressed: onCancel,
            child: barLabel(Text('task.sheetCancel'.tr())),
          ),
          Expanded(
            child: Semantics(
              header: true,
              // OPH-400 (R-09): at AX3 the name wraps to a second line
              // between words ("Yeni / görev") instead of "Yeni …", and a
              // word too wide for the slot is drawn smaller, never cut.
              child: AwWordSafeText(
                title,
                key: const Key('task-sheet-heading'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          TextButton(
            key: const Key('task-sheet-create'),
            style: buttonStyle,
            onPressed: onAction,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : barLabel(Text(actionLabel)),
          ),
        ],
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
