import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../../../core/list_sort.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/sort_menu.dart';
import '../../files/data/file_attachment.dart';
import '../../../widgets/status_views.dart';
import '../../files/providers.dart';
import '../../files/ui/attach_menu.dart';
import '../../files/ui/file_widgets.dart';
import '../../notes/data/note.dart';
import 'package:markdown_forge/markdown_forge.dart';
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
      // Round 13 #2: dialogs go to the ROOT navigator for the same
      // reason sheets do (OPH-212) — inside a shell branch the
      // Scaffold's own bar and FAB paint over them.
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('project.deleteTitle'.tr()),
        content: Text('project.deleteBody'.tr(args: {'name': project.name})),
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
      length: 4,
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
            PopupMenuButton<String>(
              key: const Key('project-quick-menu'),
              tooltip: 'quick.actions'.tr(),
              onSelected: (_) => toggleQuickAccess(
                context,
                ref,
                kind: QuickKind.project,
                targetId: project.id,
                suggestedTitle: project.name,
              ),
              itemBuilder: (context) => [
                quickAccessMenuItem(
                  value: 'quick',
                  isSaved: isInQuickAccess(ref, QuickKind.project, project.id),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'project.tabOverview'.tr()),
              Tab(text: 'project.tabTasks'.tr()),
              Tab(text: 'project.tabNotes'.tr()),
              Tab(text: 'project.tabFiles'.tr()),
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
                  _ProjectFilesTab(project: project),
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
            // OPH-193: the chip carries the project's NAME + color, not its
            // raw server enum. `Text(project.status)` printed "active" /
            // "paused" at the user in whatever language they were reading —
            // and the one state that means something, archived, already has
            // its own banner right above this row.
            Chip(
              avatar: CircleAvatar(backgroundColor: project.color, radius: 8),
              label: Text(project.name),
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
/// A project's README, rendered (OPH-274).
///
/// It used to be a read-only `QuillEditor` over the note's delta, which meant
/// the Overview tab drew documents with a DIFFERENT engine than the note
/// screen: a table in a README was invisible here and fine one tap away. One
/// canonical form, one renderer.
///
/// Stateless now. The old widget kept a `QuillController` alive purely to
/// re-`Document.fromJson` it whenever the README was edited — the Overview tab
/// is kept alive, so without that the body stayed at the initial (often empty)
/// delta (feedback round 5). `AwMarkdown` takes the text as a parameter, so a
/// rebuild IS the refresh.
class _ReadmeView extends StatelessWidget {
  const _ReadmeView({required this.note});

  final NoteDetail note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = note.title.trim();
    final markdown = note.contentMarkdown ?? '';
    final body = markdown.trim().isEmpty
        ? Text('project.emptyReadme'.tr(), style: theme.textTheme.bodyMedium)
        : MarkdownView(
            document: parseMarkdown(markdown),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
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

/// The project file manager (Epic 14, OPH-155 — BLUEPRINT §12.3 rev.): the
/// project's own files ∪ its tasks' ∪ its notes' files from the replica
/// (offline-capable), with source badges (F4), source filter chips, sort
/// toggles and uploads targeting the PROJECT. Follows the Tasks/Notes tab
/// shape (top action row, not a FAB — those tabs set the pattern).
class _ProjectFilesTab extends ConsumerStatefulWidget {
  const _ProjectFilesTab({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectFilesTab> createState() => _ProjectFilesTabState();
}

class _ProjectFilesTabState extends ConsumerState<_ProjectFilesTab> {
  String _filter = 'all'; // all | project | task | note

  /// OPH-258 (§34 L4): the same control and the same preference as the global
  /// Files section — this tab's own enum sorted with `setState` and forgot the
  /// choice the moment the tab rebuilt.
  List<ProjectFileEntry> _arrange(
    List<ProjectFileEntry> entries,
    AwSortState sort,
  ) {
    final filtered = _filter == 'all'
        ? entries.toList()
        : entries.where((e) => e.sourceType == _filter).toList();
    final order = fileSortComparator(sort);
    return filtered..sort((a, b) => order(a.file, b.file));
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final theme = Theme.of(context);
    final status = ref.watch(storageStatusProvider);
    final usage = ref.watch(workspaceFilesUsageProvider).value;
    final entries = ref.watch(projectFilesProvider(project.id));
    final uploads = ref
        .watch(uploadsProvider)
        .where((j) => j.targetType == 'project' && j.targetId == project.id)
        .toList();
    final configured = status.value?.configured ?? true;
    final sort = AwSortState.parse(
      ref.watch(filesSortProvider),
      kFileSortChoices,
    );

    Widget list(List<ProjectFileEntry> all) {
      final items = _arrange(all, sort);
      if (items.isEmpty && uploads.isEmpty) {
        return configured
            ? AwEmptyState(
                icon: Icons.folder_open_outlined,
                title: 'file.emptyTitle'.tr(),
                message: 'file.emptyBody'.tr(),
              )
            : AwEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'file.notConfigured'.tr(),
                message: 'file.notConfiguredHint'.tr(),
              );
      }
      // From the ARRANGED list, not the raw one: this tab sorts by name and by
      // size, and swiping right has to land where the list implied it would
      // (DESIGN §30 A11).
      final imageIds = [
        for (final entry in items)
          if (entry.file.isImage) entry.file.id,
      ];
      return ListView(
        padding: awListPadding(context),
        children: [
          for (final job in uploads) UploadRowTile(job: job),
          for (final entry in items)
            FileRowTile(
              file: entry.file,
              siblingImageIds: imageIds,
              badge: _SourceBadge(entry: entry),
            ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              AttachButton(
                buttonKey: const Key('project-add-file'),
                enabled: configured,
                icon: Icons.upload_file_outlined,
                onPicked: (picks) => ref
                    .read(uploadsProvider.notifier)
                    .uploadAll(
                      workspaceId: project.workspaceId,
                      targetType: 'project',
                      targetId: project.id,
                      sources: picks,
                    ),
              ),
              const Spacer(),
              AwSortMenuButton(
                choices: kFileSortChoices,
                sort: sort,
                onChanged: (next) =>
                    ref.read(filesSortProvider.notifier).set(next.encode()),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in [
                  ('all', 'file.filterAll'),
                  ('project', 'file.filterProject'),
                  ('task', 'file.filterTasks'),
                  ('note', 'file.filterNotes'),
                ]) ...[
                  FilterChip(
                    label: Text(label.tr()),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: entries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AwErrorState(
              message: localizedError(error),
              onRetry: () => ref.invalidate(projectFilesProvider(project.id)),
            ),
            data: list,
          ),
        ),
        // Quiet workspace-wide footprint line (OPH-157). Display only —
        // quota enforcement is deliberately v2 (ATTACHMENTS.md §11).
        if (configured && usage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'file.usage'.tr(
                args: {
                  'count': '${usage.fileCount}',
                  'size': formatBytes(usage.totalBytes),
                },
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Where a file came from (F4): the project itself or a task/note title.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.entry});

  final ProjectFileEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = entry.sourceType == 'project'
        ? 'file.filterProject'.tr()
        : entry.sourceTitle;
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
