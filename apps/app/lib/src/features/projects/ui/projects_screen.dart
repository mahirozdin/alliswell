import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../screens/home_shell.dart';
import '../../../search/providers.dart';
import '../../../widgets/search_field.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/project.dart';
import '../providers.dart';
import 'project_archive.dart';
import 'project_edit_sheet.dart';

/// Projects list (OPH-036): color, favorite toggle, status; FAB creates.
/// Archived projects are hidden by default behind the Active/Archived chips
/// (OPH-110).
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsControllerProvider);
    final showArchived = ref.watch(projectsShowArchivedProvider);
    // FAB hoisted to HomeShell (OPH-101).
    return Scaffold(
      appBar: buildSectionAppBar(context, 'nav.projects'.tr()),
      body: Column(
        children: [
          // OPH-167 (DESIGN §12): fold-insensitive search, ANDs with the
          // Active/Archived chips below (S1/S5).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AwSearchField(
              key: const Key('projects-search'),
              hintText: 'project.searchHint'.tr(),
              onQuery: (q) =>
                  ref.read(projectsSearchQueryProvider.notifier).set(q),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                for (final (archived, label) in [
                  (false, 'project.filterActive'.tr()),
                  (true, 'project.filterArchived'.tr()),
                ]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: showArchived == archived,
                    onSelected: (_) => ref
                        .read(projectsShowArchivedProvider.notifier)
                        .set(archived),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(projectsControllerProvider),
              ),
              data: (all) {
                var items = [
                  for (final p in all)
                    if ((p.status == 'archived') == showArchived) p,
                ];
                final hits = ref.watch(projectsSearchResultsProvider).value;
                if (hits != null) {
                  // Ranked ids from the fold engine: name hits first (S3).
                  final order = {
                    for (final (i, hit) in hits.indexed) hit.id: i,
                  };
                  items = [
                    for (final p in items)
                      if (order.containsKey(p.id)) p,
                  ]..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
                }
                if (items.isEmpty) {
                  return AwEmptyState(
                    icon: showArchived
                        ? Icons.archive_outlined
                        : Icons.folder_open,
                    title: showArchived
                        ? 'project.noArchived'.tr()
                        : 'project.empty'.tr(),
                    message: showArchived
                        ? 'project.archivedHere'.tr()
                        : 'project.createFirst'.tr(),
                  );
                }
                return ListView.builder(
                  padding: awListPadding(context, extraBottom: 72),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _ProjectTile(project: items[index]),
                );
              },
            ),
          ),
        ],
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
    final archived = project.status == 'archived';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            0,
            AwSpace.x2,
            0,
          ),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: project.isFavorite
                    ? 'project.removeFavorite'.tr()
                    : 'project.markFavorite'.tr(),
                icon: Icon(
                  project.isFavorite ? Icons.star : Icons.star_border,
                  color: project.isFavorite ? tokens.warning : null,
                ),
                onPressed: () => ref
                    .read(projectsControllerProvider.notifier)
                    .toggleFavorite(project),
              ),
              PopupMenuButton<String>(
                key: Key('project-menu-${project.id}'),
                tooltip: 'project.actions'.tr(),
                onSelected: (action) {
                  if (action == 'edit') {
                    showProjectEditSheet(context, project: project);
                  } else if (action == 'archive' || action == 'unarchive') {
                    showProjectArchiveDialog(context, project);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text('common.edit'.tr())),
                  PopupMenuItem(
                    value: archived ? 'unarchive' : 'archive',
                    child: Text(
                      archived
                          ? 'project.unarchiveMenu'.tr()
                          : 'project.archiveMenu'.tr(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => context.go('/projects/${project.id}'),
        ),
      ),
    );
  }
}
