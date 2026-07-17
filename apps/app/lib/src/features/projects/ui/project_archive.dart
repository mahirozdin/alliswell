import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/providers.dart';
import '../../tasks/providers.dart';
import '../data/project.dart';
import '../providers.dart';

/// Archive or unarchive a project with the optional cascade (OPH-110). The
/// dialog shows live counts when archiving and the restore caveat when
/// unarchiving; a plain flip (both boxes off) works offline, a cascade needs a
/// connection (handled with an inline error).
Future<void> showProjectArchiveDialog(BuildContext context, Project project) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ArchiveDialog(project: project),
  );
}

class _ArchiveDialog extends ConsumerStatefulWidget {
  const _ArchiveDialog({required this.project});

  final Project project;

  @override
  ConsumerState<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends ConsumerState<_ArchiveDialog> {
  bool _tasks = false;
  bool _notes = false;
  bool _busy = false;
  String? _error;

  bool get _archiving => widget.project.status != 'archived';

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ctl = ref.read(projectsControllerProvider.notifier);
      if (_archiving) {
        await ctl.archiveProject(
          widget.project.id,
          includeTasks: _tasks,
          includeNotes: _notes,
        );
      } else {
        await ctl.unarchiveProject(
          widget.project.id,
          includeTasks: _tasks,
          includeNotes: _notes,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(
          () => _error = (_tasks || _notes)
              ? 'Archiving with its tasks/notes needs a connection.'
              : 'Could not update the project.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live counts only make sense for the archive direction (they count what
    // WOULD be swept). Unarchive restores everything archived — see the caveat.
    final openTasks = _archiving
        ? ref.watch(projectTasksProvider(widget.project.id)).value?.length
        : null;
    final notes = _archiving
        ? ref.watch(projectNotesProvider(widget.project.id)).value?.length
        : null;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(_archiving ? 'Archive project?' : 'Unarchive project?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _archiving
                ? 'It leaves the active list. Choose what to take with it.'
                : 'It returns to the active list. Choose what to restore.',
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('archive-include-tasks'),
            contentPadding: EdgeInsets.zero,
            value: _tasks,
            onChanged: _busy
                ? null
                : (v) => setState(() => _tasks = v ?? false),
            title: Text(
              _archiving
                  ? 'Also archive its open tasks${openTasks == null ? '' : ' ($openTasks)'}'
                  : 'Also restore its tasks',
            ),
          ),
          CheckboxListTile(
            key: const Key('archive-include-notes'),
            contentPadding: EdgeInsets.zero,
            value: _notes,
            onChanged: _busy
                ? null
                : (v) => setState(() => _notes = v ?? false),
            title: Text(
              _archiving
                  ? 'Also archive its notes${notes == null ? '' : ' ($notes)'}'
                  : 'Also restore its notes',
            ),
          ),
          if (!_archiving && (_tasks || _notes))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Restores ALL archived tasks and notes of this project.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('archive-confirm'),
          onPressed: _busy ? null : _confirm,
          child: Text(_archiving ? 'Archive' : 'Unarchive'),
        ),
      ],
    );
  }
}
