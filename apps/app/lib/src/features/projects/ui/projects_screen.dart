import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../../../i18n/i18n.dart';
import '../../../screens/home_shell.dart';
import '../../../search/providers.dart';
import '../../../sections.dart';
import '../../../sync/refresh.dart';
import '../../../widgets/search_field.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/refreshable.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart';
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
    Future<bool> refresh() => refreshSection(ref, AppSection.projects);
    // FAB hoisted to HomeShell (OPH-101).
    return Scaffold(
      appBar: buildSectionAppBar(
        context,
        'nav.projects'.tr(),
        onRefresh: refresh,
        // Round 13 #5: search is an app-bar action; the Active/Archived chips
        // keep their row and the list starts higher.
        trailingActions: [
          AwSearchAction(
            fieldKey: const Key('projects-search'),
            hintText: 'project.searchHint'.tr(),
            onQuery: (q) =>
                ref.read(projectsSearchQueryProvider.notifier).set(q),
          ),
        ],
      ),
      body: Column(
        children: [
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
            // OPH-171: the indicator is born right under the filter chips —
            // this wraps the list, not the body (§15 R1).
            child: AwRefresh(
              indicatorKey: const Key('projects-refresh'),
              onRefresh: refresh,
              child: projects.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AwErrorState(
                  message: localizedError(error),
                  onRetry: () => ref.invalidate(projectsControllerProvider),
                  physics: const AlwaysScrollableScrollPhysics(),
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
                      physics: const AlwaysScrollableScrollPhysics(),
                    );
                  }
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: awListPadding(context, extraBottom: 72),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _ProjectTile(project: items[index]),
                  );
                },
              ),
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
      // OPH-184: a project could only be deleted from inside its detail screen.
      // A project delete CASCADES, so it keeps its confirmation dialog and does
      // NOT use the undo path (DESIGN §19 D3) — the swipe is a shortcut to that
      // dialog, not a shortcut past it.
      child: AwSwipeToDelete(
        id: project.id,
        semanticLabel: 'project.deleteTooltip'.tr(),
        onDelete: () => deleteProjectConfirmed(context, ref, project),
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
            // OPH-193 will retire the free-form status entirely; until then the
            // one state a user recognises is the archived banner, not a raw
            // `paused`/`completed` enum printed in English.
            subtitle: archived ? Text('project.filterArchived'.tr()) : null,
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
                    } else if (action == 'delete') {
                      deleteProjectConfirmed(context, ref, project);
                    } else if (action == 'quick') {
                      toggleQuickAccess(
                        context,
                        ref,
                        kind: QuickKind.project,
                        targetId: project.id,
                        suggestedTitle: project.name,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('common.edit'.tr()),
                    ),
                    quickAccessMenuItem(
                      value: 'quick',
                      isSaved: isInQuickAccess(
                        ref,
                        QuickKind.project,
                        project.id,
                      ),
                    ),
                    PopupMenuItem(
                      value: archived ? 'unarchive' : 'archive',
                      child: Text(
                        archived
                            ? 'project.unarchiveMenu'.tr()
                            : 'project.archiveMenu'.tr(),
                      ),
                    ),
                    // D2: the swipe's visible equivalent.
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('project.deleteMenu'.tr()),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () => context.go('/projects/${project.id}'),
          ),
        ),
      ),
    );
  }
}

/// Delete a project after its confirmation dialog (OPH-184, DESIGN §19 D3).
/// Shared by the list swipe, the list menu and the detail screen's app bar so
/// the cascade question can never be skipped by taking a different route.
Future<void> deleteProjectConfirmed(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  final confirmed = await awConfirmDelete(
    context,
    title: 'project.deleteTitle'.tr(),
    body: 'project.deleteBody'.tr(args: {'name': project.name}),
  );
  if (!confirmed) return;
  await ref.read(projectsControllerProvider.notifier).deleteProject(project.id);
}
