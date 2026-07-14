import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notes/data/note.dart';
import '../../notes/providers.dart';
import '../../notes/ui/notes_screen.dart';
import '../../tasks/providers.dart';
import '../../tasks/ui/quick_add_bar.dart';
import '../../tasks/ui/task_tile.dart';
import '../../workspaces/workspaces.dart';
import '../data/project.dart';
import '../providers.dart';
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
            body: const Center(child: Text('Project not found')),
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
        title: const Text('Delete project?'),
        content: Text(
          '"${project.name}" will be removed. Its tasks stay in the workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
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
              tooltip: 'Edit project',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showProjectEditSheet(context, project: project),
            ),
            IconButton(
              tooltip: 'Delete project',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Tasks'),
              Tab(text: 'Notes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(project: project),
            _ProjectTasksTab(projectId: project.id),
            _ProjectNotesTab(project: project),
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
    final note = await ref.read(notesApiProvider).create(workspaces.first.id, {
      'title': project.name,
      'projectId': project.id,
    });
    await ref.read(projectsApiProvider).update(project.id, {
      'readmeNoteId': note.id,
    });
    ref.invalidate(projectsControllerProvider);
    if (context.mounted) {
      invalidateNoteData(ref, noteId: note.id, projectId: project.id);
      context.go('/notes/${note.id}');
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
              const Chip(
                avatar: Icon(Icons.star, size: 18, color: Colors.amber),
                label: Text('Favorite'),
              ),
            if (project.dueAt != null)
              Chip(
                avatar: const Icon(Icons.flag_outlined, size: 18),
                label: Text(
                  'Due ${project.dueAt!.toLocal().toString().split(' ').first}',
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
            Text('README', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (project.readmeNoteId != null)
              IconButton(
                key: const Key('edit-readme'),
                tooltip: 'Edit README',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => context.go('/notes/${project.readmeNoteId}'),
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
                    'No README yet — the note that opens with this project, '
                    'like a repo home page.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const Key('create-readme'),
                    onPressed: () => _createReadme(context, ref),
                    icon: const Icon(Icons.post_add),
                    label: const Text('Create README'),
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
    final delta = widget.note.contentDelta;
    if (delta != null && delta.isNotEmpty) {
      _controller.document = Document.fromJson(delta);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.document.isEmpty()) {
      return Text(
        'Empty README — open it with the pencil to start writing.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return QuillEditor.basic(
      controller: _controller,
      config: const QuillEditorConfig(
        showCursor: false,
        padding: EdgeInsets.zero,
      ),
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
    await ref.read(tasksApiProvider).create(workspaces.first.id, {
      'title': title,
      'projectId': projectId,
    });
    invalidateTaskData(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(projectTasksProvider(projectId));
    return Column(
      children: [
        QuickAddBar(
          key: const Key('project-quick-add'),
          hintText: 'Add a task to this project…',
          onAdd: (title) => _add(ref, title),
        ),
        const Divider(height: 1),
        Expanded(
          child: tasks.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (items) => items.isEmpty
                ? const Center(
                    child: Chip(
                      avatar: Icon(Icons.check_circle_outline, size: 18),
                      label: Text('No open tasks in this project'),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        TaskTile(task: items[index]),
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
    final note = await ref.read(notesApiProvider).create(workspaces.first.id, {
      'title': 'Untitled',
      'projectId': project.id,
    });
    if (context.mounted) {
      invalidateNoteData(ref, noteId: note.id, projectId: project.id);
      context.go('/notes/${note.id}');
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
              label: const Text('New note in this project'),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: notes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (items) => items.isEmpty
                ? const Center(
                    child: Chip(
                      avatar: Icon(Icons.description_outlined, size: 18),
                      label: Text('No notes attached to this project yet'),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        NoteTile(note: items[index]),
                  ),
          ),
        ),
      ],
    );
  }
}
