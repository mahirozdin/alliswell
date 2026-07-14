import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notes/providers.dart';
import '../../notes/ui/notes_screen.dart';
import '../data/project.dart';
import '../providers.dart';
import 'project_edit_sheet.dart';

/// Project detail with the Overview/Tasks/Notes tab skeleton (OPH-036).
/// Tasks tab fills in with OPH-037, Notes with Epic 05.
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
            const _ComingSoonTab(
              icon: Icons.check_circle_outline,
              label: 'Project tasks arrive with OPH-037',
            ),
            _ProjectNotesTab(projectId: project.id),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
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
        Text('Description', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          project.description?.isNotEmpty == true
              ? project.description!
              : 'No description yet — add one from Edit.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ProjectNotesTab extends ConsumerWidget {
  const _ProjectNotesTab({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(projectNotesProvider(projectId));
    return notes.when(
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
              itemBuilder: (context, index) => NoteTile(note: items[index]),
            ),
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Chip(avatar: Icon(icon, size: 18), label: Text(label)),
    );
  }
}
