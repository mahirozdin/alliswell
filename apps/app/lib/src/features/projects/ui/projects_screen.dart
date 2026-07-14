import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../screens/home_shell.dart';
import '../data/project.dart';
import '../providers.dart';
import 'project_edit_sheet.dart';

/// Projects list (OPH-036): color, favorite toggle, status; FAB creates.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);
    return Scaffold(
      appBar: buildSectionAppBar(context, 'Projects'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New project',
        onPressed: () => showProjectEditSheet(context),
        child: const Icon(Icons.add),
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorRetry(
          message: '$error',
          onRetry: () => ref.invalidate(projectsControllerProvider),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyProjects()
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _ProjectTile(project: items[index]),
              ),
      ),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: project.color, radius: 12),
      title: Text(project.name),
      subtitle: project.status == 'active'
          ? null
          : Text(project.status, style: Theme.of(context).textTheme.bodySmall),
      trailing: IconButton(
        tooltip: project.isFavorite ? 'Remove favorite' : 'Mark favorite',
        icon: Icon(
          project.isFavorite ? Icons.star : Icons.star_border,
          color: project.isFavorite ? Colors.amber : null,
        ),
        onPressed: () => ref
            .read(projectsControllerProvider.notifier)
            .toggleFavorite(project),
      ),
      onTap: () => context.go('/projects/${project.id}'),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('No projects yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Create your first project with the + button.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
