import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../screens/home_shell.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
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
        error: (error, _) => AwErrorState(
          message: '$error',
          onRetry: () => ref.invalidate(projectsControllerProvider),
        ),
        data: (items) => items.isEmpty
            ? const AwEmptyState(
                icon: Icons.folder_open,
                title: 'No projects yet',
                message: 'Create your first project with the + button.',
              )
            : ListView.builder(
                padding: awListPadding(context, extraBottom: 72),
                itemCount: items.length,
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
    final tokens = context.awTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
          leading: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: project.color,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.hairline),
            ),
          ),
          title: Text(project.name),
          subtitle: project.status == 'active' ? null : Text(project.status),
          trailing: IconButton(
            tooltip: project.isFavorite ? 'Remove favorite' : 'Mark favorite',
            icon: Icon(
              project.isFavorite ? Icons.star : Icons.star_border,
              color: project.isFavorite ? tokens.warning : null,
            ),
            onPressed: () => ref
                .read(projectsControllerProvider.notifier)
                .toggleFavorite(project),
          ),
          onTap: () => context.go('/projects/${project.id}'),
        ),
      ),
    );
  }
}
