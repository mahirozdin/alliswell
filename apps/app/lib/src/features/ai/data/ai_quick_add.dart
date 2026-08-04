import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../projects/providers.dart';
import '../../tasks/data/task_defaults.dart';
import '../../tasks/providers.dart';
import '../providers.dart';
import 'ai_action_reporter.dart';
import 'ai_models.dart';
import 'project_match.dart';

/// Round 14: the ✨ quick-add rider is fire-and-forget. The old flow held the
/// user hostage to the extraction round-trip (no feedback, then a confirm
/// card, then an error if the provider was slow); now the task row appears
/// INSTANTLY with plain quick-add semantics (round-14 defaults included), a
/// per-row badge says "AI is filling this in", and the extraction lands as an
/// update. Any failure — offline, provider down, nothing extractable — simply
/// leaves the plain task standing: the fallback IS the product behavior, not
/// an error state. The confirm card stays the law on the bubble/voice/share
/// paths, where nothing was written yet; here the user's OWN text is already
/// a committed task and the AI only decorates it.
///
/// The accept/reject decision still reaches `ai_action_log`: tapping ✨ is the
/// explicit consent, applied fields are reported exactly like a confirmed
/// card, an unusable proposal is reported as rejected.

/// Task ids currently being enriched — rows watch this to show the badge.
final aiEnrichingTasksProvider =
    NotifierProvider<AiEnrichingTasks, Set<String>>(AiEnrichingTasks.new);

class AiEnrichingTasks extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};

  void remove(String id) {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
  }
}

final aiQuickAddProvider = Provider<AiQuickAdd>(AiQuickAdd.new);

class AiQuickAdd {
  AiQuickAdd(this._ref);
  final Ref _ref;

  /// Creates the plain task NOW and returns as soon as it exists locally;
  /// extraction continues in the background.
  Future<String> start({
    required String workspaceId,
    required String text,
  }) async {
    final store = _ref.read(taskStoreProvider);
    final taskId = await store.create(workspaceId, {
      'title': text,
      ...awQuickTaskDefaults(),
    });
    _ref.read(aiEnrichingTasksProvider.notifier).add(taskId);
    unawaited(_enrich(workspaceId: workspaceId, taskId: taskId, text: text));
    return taskId;
  }

  Future<void> _enrich({
    required String workspaceId,
    required String taskId,
    required String text,
  }) async {
    final store = _ref.read(taskStoreProvider);
    try {
      final projects = _ref.read(projectsControllerProvider).value ?? const [];
      final proposal = await _ref
          .read(aiApiProvider)
          .extract(
            workspaceId,
            text: text,
            source: 'quick_add',
            defaultTaskTime: _ref.read(defaultTaskTimeProvider),
            projectNames: [for (final p in projects) p.name],
          );
      if (proposal.intent != 'create_tasks' || proposal.tasks.isEmpty) {
        _ref
            .read(aiActionReporterProvider)
            .reportReject(proposal.actionId)
            .ignore();
        return;
      }

      final refs = [
        for (final p in projects) ProjectRef(id: p.id, name: p.name),
      ];
      final created = <String>[taskId];
      final first = proposal.tasks.first;
      await store.update(
        taskId,
        _updatePatch(first, refs, fallbackTitle: text),
      );
      for (final item in first.checklist) {
        await store.addChecklistItem(taskId, item);
      }
      // A multi-task utterance stays first-class: the extras are born whole.
      for (final extra in proposal.tasks.skip(1)) {
        final id = await store.create(workspaceId, _createBody(extra, refs));
        for (final item in extra.checklist) {
          await store.addChecklistItem(id, item);
        }
        created.add(id);
      }
      _ref
          .read(aiActionReporterProvider)
          .reportAccept(
            proposal.actionId,
            entityRefs: [
              for (final id in created) {'type': 'task', 'id': id},
            ],
          )
          .ignore();
    } catch (_) {
      // Deliberately silent: the plain task is already exactly what a normal
      // quick add would have produced.
    } finally {
      _ref.read(aiEnrichingTasksProvider.notifier).remove(taskId);
    }
  }

  /// Due/remind, local time: a proposal without its own reminder inherits the
  /// round-14 rule (one hour before the deadline).
  (DateTime?, DateTime?) _dates(AiProposalTask task) {
    final due = task.dueAt == null
        ? null
        : DateTime.tryParse(task.dueAt!)?.toLocal();
    final remind = task.reminderAt == null
        ? null
        : DateTime.tryParse(task.reminderAt!)?.toLocal();
    return (due, remind ?? awAutoReminderFor(due));
  }

  /// What the proposal may change on the already-created task. Absent fields
  /// leave the quick-add values (incl. urgent-on) alone — the AI upgrades, it
  /// never quietly downgrades what the defaults promised.
  Map<String, dynamic> _updatePatch(
    AiProposalTask task,
    List<ProjectRef> refs, {
    required String fallbackTitle,
  }) {
    final (due, remind) = _dates(task);
    final projectId = matchProject(task.projectName, refs).match?.id;
    final title = task.title.trim();
    return {
      'title': title.isEmpty ? fallbackTitle : title,
      'description': ?task.description,
      'projectId': ?projectId,
      if (task.priority != null && task.priority != 'none')
        'priority': task.priority,
      if (due != null) 'dueAt': due.toUtc().toIso8601String(),
      if (remind != null) 'remindAt': remind.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _createBody(AiProposalTask task, List<ProjectRef> refs) {
    return {
      ...awQuickTaskDefaults(),
      ..._updatePatch(task, refs, fallbackTitle: task.title),
    };
  }
}
