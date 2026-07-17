import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../../notes/data/note.dart';
import '../../notes/providers.dart';
import '../../notes/ui/notes_screen.dart';
import '../../tasks/providers.dart';
import '../../tasks/ui/quick_add_bar.dart';
import '../../tasks/ui/task_tile.dart';
import '../../workspaces/workspaces.dart';
import '../data/project.dart';
import '../providers.dart';
import 'project_archive.dart';
import 'project_edit_sheet.dart';

/// Project detail (OPH-036 + feedback round 1): Overview opens on the
/// project's README note (GitHub style), Tasks and Notes tabs are live lists
/// with in-place quick adds.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);
    return projects.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$error')),
      ),
      data: (items) {
        Project? project;
        for (final p in items) {
          if (p.id == projectId) project = p;
        }
        if (project == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('project.notFound'.tr())),
          );
        }
        return _ProjectDetail(project: project);
      },
    );
  }
}

class _ProjectDetail extends ConsumerWidget {
  const _ProjectDetail({required this.project});

  final Project project;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('project.deleteTitle'.tr()),
        content: Text(
          'project.deleteBody'.tr(args: {'name': project.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(projectsControllerProvider.notifier)
        .deleteProject(project.id);
    if (context.mounted) context.go('/projects');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              CircleAvatar(backgroundColor: project.color, radius: 8),
              const SizedBox(width: 8),
              Expanded(
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'project.editTooltip'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showProjectEditSheet(context, project: project),
            ),
            IconButton(
              tooltip: 'project.deleteTooltip'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'project.tabOverview'.tr()),
              Tab(text: 'project.tabTasks'.tr()),
              Tab(text: 'project.tabNotes'.tr()),
            ],
          ),
        ),
        body: Column(
          children: [
            if (project.status == 'archived')
              MaterialBanner(
                content: Text('project.archivedBanner'.tr()),
                leading: const Icon(Icons.archive_outlined),
                actions: [
                  TextButton(
                    key: const Key('detail-unarchive'),
                    onPressed: () => showProjectArchiveDialog(context, project),
                    child: Text('project.unarchive'.tr()),
                  ),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(project: project),
                  _ProjectTasksTab(projectId: project.id),
                  _ProjectNotesTab(project: project),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overview: the project README, GitHub style ─────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.project});

  final Project project;

  Future<void> _createReadme(BuildContext context, WidgetRef ref) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    final noteId = await ref.read(noteStoreProvider).create(
      workspaces.first.id,
      {'title': project.name, 'projectId': project.id},
    );
    await ref.read(projectStoreProvider).update(project.id, {
      'readmeNoteId': noteId,
    });
    if (context.mounted) {
      // Edit in the project's context, not the Notes tab (OPH-109): push
      // full-screen so back returns here and the README card refreshes.
      context.push('/edit-note/$noteId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: CircleAvatar(backgroundColor: project.color, radius: 8),
              label: Text(project.status),
            ),
            if (project.isFavorite)
              Chip(
                avatar: const Icon(Icons.star, size: 18, color: Colors.amber),
                label: Text('project.favorite'.tr()),
              ),
            if (project.dueAt != null)
              Chip(
                avatar: const Icon(Icons.flag_outlined, size: 18),
                label: Text(
                  'project.dueOn'.tr(
                    args: {
                      'date': project.dueAt!
                          .toLocal()
                          .toString()
                          .split(' ')
                          .first,
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text('project.readme'.tr(), style: theme.textTheme.titleSmall),
            const Spacer(),
            if (project.readmeNoteId != null)
              IconButton(
                key: const Key('edit-readme'),
                tooltip: 'project.editReadme'.tr(),
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () =>
                    context.push('/edit-note/${project.readmeNoteId}'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (project.readmeNoteId == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'project.noReadme'.tr(),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const Key('create-readme'),
                    onPressed: () => _createReadme(context, ref),
                    icon: const Icon(Icons.post_add),
                    label: Text('project.createReadme'.tr()),
                  ),
                ],
              ),
            ),
          )
        else
          _ReadmeCard(noteId: project.readmeNoteId!),
      ],
    );
  }
}

class _ReadmeCard extends ConsumerWidget {
  const _ReadmeCard({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteDetailProvider(noteId));
    return note.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text('$error'),
      data: (value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _ReadmeView(note: value),
        ),
      ),
    );
  }
}

/// Read-only rendering of the README note's rich content.
class _ReadmeView extends StatefulWidget {
  const _ReadmeView({required this.note});

  final NoteDetail note;

  @override
  State<_ReadmeView> createState() => _ReadmeViewState();
}

class _ReadmeViewState extends State<_ReadmeView> {
  late final QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic()..readOnly = true;
    _applyDelta();
  }

  /// (Re)load the note's content into the read-only controller. Needed on
  /// updates too: the Overview tab is kept alive, so when the README is edited
  /// its content must refresh here instead of staying at the initial (often
  /// empty) delta — feedback round 5.
  void _applyDelta() {
    final delta = widget.note.contentDelta;
    _controller.document = (delta != null && delta.isNotEmpty)
        ? Document.fromJson(delta)
        : Document();
  }

  @override
  void didUpdateWidget(covariant _ReadmeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.note, oldWidget.note)) _applyDelta();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.note.title.trim();
    final body = _controller.document.isEmpty()
        ? Text('project.emptyReadme'.tr(), style: theme.textTheme.bodyMedium)
        : QuillEditor.basic(
            controller: _controller,
            config: const QuillEditorConfig(
              showCursor: false,
              padding: EdgeInsets.zero,
            ),
          );
    // Show the note title as the document heading (feedback round 5): the
    // overview used to render only the body.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        body,
      ],
    );
  }
}

// ── Tasks tab: live list + in-place quick add ───────────────────────────────

class _ProjectTasksTab extends ConsumerWidget {
  const _ProjectTasksTab({required this.projectId});

  final String projectId;

  Future<void> _add(WidgetRef ref, String title) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) throw StateError('No workspace available');
    await ref.read(taskStoreProvider).create(workspaces.first.id, {
      'title': title,
      'projectId': projectId,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(projectTasksProvider(projectId));
    return Column(
      children: [
        QuickAddBar(
          key: const Key('project-quick-add'),
          hintText: 'project.addTaskHint'.tr(),
          onAdd: (title) => _add(ref, title),
        ),
        Expanded(
          child: tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AwErrorState(
              message: localizedError(error),
              onRetry: () => ref.invalidate(projectTasksProvider(projectId)),
            ),
            data: (items) => items.isEmpty
                ? AwEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'project.allClear'.tr(),
                    message: 'project.noOpenTasks'.tr(),
                  )
                : ListView.builder(
                    padding: awListPadding(context),
                    itemCount: items.length,
                    // Every row here is this project — the badge would be noise.
                    itemBuilder: (context, index) =>
                        TaskTile(task: items[index], showProjectBadge: false),
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Notes tab: project notes + one-tap capture ──────────────────────────────

class _ProjectNotesTab extends ConsumerWidget {
  const _ProjectNotesTab({required this.project});

  final Project project;

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    final noteId = await ref.read(noteStoreProvider).create(
      workspaces.first.id,
      {'title': 'Untitled', 'projectId': project.id},
    );
    if (context.mounted) {
      context.go('/notes/$noteId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(projectNotesProvider(project.id));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('project-add-note'),
              onPressed: () => _addNote(context, ref),
              icon: const Icon(Icons.note_add_outlined),
              label: Text('project.newNote'.tr()),
            ),
          ),
        ),
        Expanded(
          child: notes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AwErrorState(
              message: localizedError(error),
              onRetry: () => ref.invalidate(projectNotesProvider(project.id)),
            ),
            data: (items) => items.isEmpty
                ? AwEmptyState(
                    icon: Icons.description_outlined,
                    title: 'project.noNotesTitle'.tr(),
                    message: 'project.noNotesBody'.tr(),
                  )
                : ListView.builder(
                    padding: awListPadding(context),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        NoteTile(note: items[index]),
                  ),
          ),
        ),
      ],
    );
  }
}
