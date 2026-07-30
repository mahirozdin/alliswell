import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheet_rows.dart';
import '../../../widgets/sheets.dart';
import '../../../widgets/status_views.dart';
import '../../projects/data/project.dart';
import '../../projects/providers.dart';
import '../../projects/ui/project_picker.dart';
import '../../tasks/providers.dart';
import '../../workspaces/workspaces.dart';
import '../data/ai_action_reporter.dart';
import '../data/ai_models.dart';
import '../data/project_match.dart';

/// The confirm card (OPH-222, DESIGN §24 AI5): proposals are cards, commits are
/// human. One row per proposed task, each independently toggleable, reusing the
/// create sheet's rows; the model's source phrase shows beside the resolved
/// value; nothing writes until the user accepts. Accepted tasks commit through
/// TaskStore's optimistic + outbox path (no second write path — ADR-0016) and
/// get an undo. Rejecting writes NOTHING.
Future<void> showAiConfirmSheet(BuildContext context, AiProposal proposal) {
  return showAwSheet<void>(
    context,
    showDragHandle: true,
    builder: (_) => AiConfirmCard(proposal: proposal),
  );
}

class _RowDraft {
  _RowDraft(AiProposalTask task, this.projectId)
    : enabled = true,
      title = task.title,
      description = task.description,
      projectNameRaw = task.projectName,
      dueAtSource = task.dueAtSource,
      priority = task.priority ?? 'none',
      urgent = task.urgent,
      dueAt = task.dueAt == null
          ? null
          : DateTime.tryParse(task.dueAt!)?.toLocal(),
      remindAt = task.reminderAt == null
          ? null
          : DateTime.tryParse(task.reminderAt!)?.toLocal(),
      checklist = List.of(task.checklist);

  bool enabled;
  String title;
  final String? description;
  String? projectId;
  final String? projectNameRaw;
  final String? dueAtSource;
  final String priority;
  final bool urgent;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final List<String> checklist;

  Map<String, dynamic> toBody() => {
    'title': title.trim(),
    'description': ?description,
    'projectId': ?projectId,
    if (priority != 'none') 'priority': priority,
    'dueAt': ?dueAt?.toUtc().toIso8601String(),
    'remindAt': ?remindAt?.toUtc().toIso8601String(),
    if (urgent) 'isUrgent': true,
  };
}

class AiConfirmCard extends ConsumerStatefulWidget {
  const AiConfirmCard({super.key, required this.proposal});
  final AiProposal proposal;
  @override
  ConsumerState<AiConfirmCard> createState() => _AiConfirmCardState();
}

class _AiConfirmCardState extends ConsumerState<AiConfirmCard> {
  late final List<_RowDraft> _rows;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final projects =
        ref.read(projectsControllerProvider).value ?? const <Project>[];
    final refs = [for (final p in projects) ProjectRef(id: p.id, name: p.name)];
    _rows = [
      for (final task in widget.proposal.tasks)
        _RowDraft(task, matchProject(task.projectName, refs).match?.id),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final projects =
        ref.watch(projectsControllerProvider).value ?? const <Project>[];
    final enabledCount = _rows.where((r) => r.enabled).length;
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.9).clamp(
        0.0,
        double.infinity,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AwSpace.x4),
            child: Text(
              'ai.confirm.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? AwEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'ai.confirm.emptyTitle'.tr(),
                    message: 'ai.confirm.emptyBody'.tr(),
                  )
                : ListView(
                    padding: awListPadding(context),
                    children: [
                      for (var i = 0; i < _rows.length; i++)
                        _taskCard(i, projects),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AwSpace.x3),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('ai-confirm-reject'),
                    onPressed: _busy ? null : _reject,
                    child: Text('ai.confirm.reject'.tr()),
                  ),
                ),
                const SizedBox(width: AwSpace.x3),
                Expanded(
                  child: FilledButton(
                    key: const Key('ai-confirm-accept'),
                    onPressed: (_busy || enabledCount == 0) ? null : _accept,
                    child: Text(
                      'ai.confirm.accept'.tr(args: {'count': '$enabledCount'}),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(int index, List<Project> projects) {
    final row = _rows[index];
    return Card(
      key: Key('ai-confirm-row-$index'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  key: Key('ai-confirm-toggle-$index'),
                  value: row.enabled,
                  onChanged: (v) => setState(() => row.enabled = v),
                ),
                Expanded(
                  child: TextFormField(
                    key: Key('ai-confirm-title-$index'),
                    initialValue: row.title,
                    decoration: InputDecoration(
                      labelText: 'ai.confirm.taskTitle'.tr(),
                    ),
                    onChanged: (v) => row.title = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x2),
            ProjectPickerField(
              projects: projects,
              value: row.projectId,
              decoration: InputDecoration(
                labelText: 'task.project'.tr(),
                helperText: row.projectId == null && row.projectNameRaw != null
                    ? 'ai.confirm.projectUnresolved'.tr(
                        args: {'name': row.projectNameRaw!},
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => row.projectId = v),
            ),
            if (row.dueAt != null) ...[
              const SizedBox(height: AwSpace.x2),
              AwSheetTile(
                tileKey: Key('ai-confirm-due-$index'),
                icon: Icons.event_outlined,
                title: 'task.due'.tr(),
                subtitle: _dueSubtitle(row),
                isSet: true,
                clearTooltip: 'task.clearDue'.tr(),
                onClear: () {},
                onTap: () {},
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dueSubtitle(_RowDraft row) {
    final resolved = awFormatShort(
      row.dueAt!,
      format: ref.read(dateFormatProvider),
    );
    // dueAtSource beside the resolved value: "yarın 15:00 → 30 Tem 15:00".
    return row.dueAtSource != null
        ? 'ai.confirm.dueSource'.tr(
            args: {'source': row.dueAtSource!, 'resolved': resolved},
          )
        : resolved;
  }

  Future<void> _reject() async {
    // Rejecting writes NOTHING — only the audit log is told.
    ref
        .read(aiActionReporterProvider)
        .reportReject(widget.proposal.actionId)
        .ignore();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    final workspace = ref.read(currentWorkspaceProvider).value;
    if (workspace == null) return;
    setState(() => _busy = true);
    final store = ref.read(taskStoreProvider);
    final created = <String>[];
    try {
      for (final row in _rows.where((r) => r.enabled)) {
        final id = await store.create(workspace.id, row.toBody());
        for (final item in row.checklist) {
          await store.addChecklistItem(id, item);
        }
        created.add(id);
      }
      ref
          .read(aiActionReporterProvider)
          .reportAccept(
            widget.proposal.actionId,
            entityRefs: [
              for (final id in created) {'type': 'task', 'id': id},
            ],
          )
          .ignore();
      if (!mounted) return;
      Navigator.of(context).pop();
      _showUndo(created);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showUndo(List<String> created) {
    final store = ref.read(taskStoreProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'ai.confirm.created'.tr(args: {'count': '${created.length}'}),
        ),
        action: SnackBarAction(
          label: 'ai.confirm.undo'.tr(),
          onPressed: () {
            for (final id in created) {
              store.delete(id);
            }
          },
        ),
      ),
    );
  }
}
