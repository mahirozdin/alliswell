import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../screens/home_shell.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/folder_store.dart';
import '../providers.dart';
import 'file_widgets.dart';

/// The global Dosyalar section (round 8, OPH-170 — BLUEPRINT §12.12,
/// DESIGN §10 F7…F9, ADR-0014). Two layers, one anatomy (F7):
///
/// - **Klasörlerim** — user folders + standalone workspace files, browsed one
///   level at a time with a breadcrumb (F8). Fully offline for browsing;
///   uploads go to the CURRENT folder.
/// - **Kaynaklar** — every file attached to a project/task/note, source-
///   labeled with "go to source" (F4/F7). Never folderable: their lifecycle
///   belongs to their owner.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  /// Breadcrumb path of folder ids; empty = root ("Dosyalar").
  final List<Folder> _path = [];
  bool _showSources = false;

  String? get _currentFolderId => _path.isEmpty ? null : _path.last.id;

  Future<void> _createFolder() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty || !mounted) return;
    final name = await _promptName(context, title: 'files.newFolder'.tr());
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(folderStoreProvider)
        .create(workspaces.first.id, name, parentId: _currentFolderId);
  }

  Future<void> _upload() async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    await ref
        .read(uploadsProvider.notifier)
        .pickAndUpload(
          workspaceId: workspaces.first.id,
          targetType: 'workspace',
          targetId: workspaces.first.id,
          folderId: _currentFolderId,
        );
  }

  Future<void> _folderActions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text('files.renameFolder'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text('files.moveFolder'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text('common.delete'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final store = ref.read(folderStoreProvider);
    switch (action) {
      case 'rename':
        final name = await _promptName(
          context,
          title: 'files.renameFolder'.tr(),
          initial: folder.name,
        );
        if (name != null && name.trim().isNotEmpty) {
          await store.rename(folder.id, name);
        }
      case 'move':
        final target = await _pickMoveTarget(exclude: folder.id);
        if (target != null) {
          await store.move(folder.id, target.id); // null id = root
        }
      case 'delete':
        await _confirmDeleteFolder(folder);
    }
  }

  /// F9 — the confirm names the blast radius before anything dies.
  Future<void> _confirmDeleteFolder(Folder folder) async {
    final workspaces = await ref.read(workspacesProvider.future);
    if (workspaces.isEmpty) return;
    final store = ref.read(folderStoreProvider);
    final counts = await store.subtreeCounts(workspaces.first.id, folder.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('files.deleteFolderTitle'.tr(args: {'name': folder.name})),
        content: Text(
          counts.files == 0 && counts.folders == 1
              ? 'files.deleteFolderEmpty'.tr()
              : 'files.deleteFolderBody'.tr(
                  args: {
                    'folders': '${counts.folders}',
                    'files': '${counts.files}',
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('folder-delete-confirm'),
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
    if (confirmed == true) {
      // If we are INSIDE the folder (or its subtree), step out first.
      final index = _path.indexWhere((f) => f.id == folder.id);
      if (index >= 0) setState(() => _path.removeRange(index, _path.length));
      await store.delete(workspaces.first.id, folder.id);
    }
  }

  /// Target-picker sheet (F8): the folder tree flattened with indentation;
  /// root first; [exclude]'s subtree hidden (a folder can't enter itself).
  Future<({String? id})?> _pickMoveTarget({String? exclude}) async {
    final folders = ref.read(foldersProvider).value ?? const <Folder>[];
    final children = <String?, List<Folder>>{};
    for (final f in folders) {
      children.putIfAbsent(f.parentId, () => []).add(f);
    }
    final excluded = <String>{};
    void markExcluded(String id) {
      excluded.add(id);
      for (final child in children[id] ?? const <Folder>[]) {
        markExcluded(child.id);
      }
    }

    if (exclude != null) markExcluded(exclude);

    final entries = <({Folder folder, int depth})>[];
    void walk(String? parentId, int depth) {
      for (final f in children[parentId] ?? const <Folder>[]) {
        if (excluded.contains(f.id)) continue;
        entries.add((folder: f, depth: depth));
        walk(f.id, depth + 1);
      }
    }

    walk(null, 0);

    return showModalBottomSheet<({String? id})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                0,
                AwSpace.x4,
                AwSpace.x2,
              ),
              child: Text(
                'files.moveTo'.tr(),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('move-target-root'),
              leading: const Icon(Icons.home_outlined),
              title: Text('files.rootFolder'.tr()),
              onTap: () => Navigator.of(sheetContext).pop((id: null)),
            ),
            for (final entry in entries)
              ListTile(
                key: Key('move-target-${entry.folder.id}'),
                contentPadding: EdgeInsetsDirectional.only(
                  start: AwSpace.x4 + entry.depth * AwSpace.x4,
                  end: AwSpace.x4,
                ),
                leading: const Icon(Icons.folder_outlined),
                title: Text(entry.folder.name),
                onTap: () =>
                    Navigator.of(sheetContext).pop((id: entry.folder.id)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveFile(FileAttachment file) async {
    final messenger = ScaffoldMessenger.of(context);
    final target = await _pickMoveTarget();
    if (target == null || !mounted) return;
    try {
      await ref.read(filesApiProvider).move(file.id, target.id);
      // Files are pull-only: the moved row comes back via the pull.
      await ref.read(syncEngineProvider)?.syncNow();
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text('files.couldNotMove'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSectionAppBar(context, 'nav.files'.tr()),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Layer switch: Klasörlerim | Kaynaklar (F7).
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              AwSpace.x1,
              AwSpace.x4,
              0,
            ),
            child: SegmentedButton<bool>(
              key: const Key('files-layer-toggle'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text('files.myFolders'.tr()),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.attachment_outlined),
                  label: Text('files.sources'.tr()),
                ),
              ],
              selected: {_showSources},
              onSelectionChanged: (selection) =>
                  setState(() => _showSources = selection.first),
            ),
          ),
          Expanded(
            child: _showSources
                ? const _SourcesLayer()
                : _FoldersLayer(
                    path: _path,
                    onDescend: (folder) => setState(() => _path.add(folder)),
                    onCrumb: (index) => setState(
                      () => _path.removeRange(index + 1, _path.length),
                    ),
                    onRoot: () => setState(_path.clear),
                    onCreateFolder: _createFolder,
                    onUpload: _upload,
                    onFolderActions: _folderActions,
                    onMoveFile: _moveFile,
                  ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('folder-name-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'files.folderName'.tr()),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('folder-name-save'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Klasörlerim: breadcrumb + this level's folders and files + actions.
class _FoldersLayer extends ConsumerWidget {
  const _FoldersLayer({
    required this.path,
    required this.onDescend,
    required this.onCrumb,
    required this.onRoot,
    required this.onCreateFolder,
    required this.onUpload,
    required this.onFolderActions,
    required this.onMoveFile,
  });

  final List<Folder> path;
  final void Function(Folder) onDescend;
  final void Function(int index) onCrumb;
  final VoidCallback onRoot;
  final VoidCallback onCreateFolder;
  final VoidCallback onUpload;
  final void Function(Folder) onFolderActions;
  final void Function(FileAttachment) onMoveFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folderId = path.isEmpty ? null : path.last.id;
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    final level = [
      for (final f in folders)
        if (f.parentId == folderId) f,
    ];
    final files =
        ref.watch(workspaceLevelFilesProvider(folderId)).value ??
        const <FileAttachment>[];
    final uploads = ref
        .watch(uploadsProvider)
        .where(
          (j) =>
              j.targetType == 'workspace' &&
              (j.folderId ?? '') == (folderId ?? ''),
        )
        .toList();
    final storageOn =
        ref.watch(storageStatusProvider).value?.configured ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb (F8): root chip + one chip per path segment.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            AwSpace.x2,
            AwSpace.x4,
            0,
          ),
          child: Row(
            children: [
              ActionChip(
                key: const Key('crumb-root'),
                label: Text('nav.files'.tr()),
                onPressed: onRoot,
              ),
              for (final (index, folder) in path.indexed) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.chevron_right, size: 16),
                ),
                ActionChip(
                  key: Key('crumb-${folder.id}'),
                  label: Text(folder.name),
                  onPressed: () => onCrumb(index),
                ),
              ],
            ],
          ),
        ),
        // Actions row (the project Files tab idiom — no FAB).
        Padding(
          padding: const EdgeInsets.fromLTRB(AwSpace.x4, 4, AwSpace.x4, 0),
          child: Row(
            children: [
              TextButton.icon(
                key: const Key('files-new-folder'),
                onPressed: onCreateFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text('files.newFolder'.tr()),
              ),
              const SizedBox(width: AwSpace.x2),
              TextButton.icon(
                key: const Key('files-upload'),
                onPressed: storageOn ? onUpload : null,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text('file.add'.tr()),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              (level.isEmpty &&
                  files.isEmpty &&
                  uploads.isEmpty &&
                  path.isEmpty &&
                  !storageOn)
              ? AwEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'file.notConfiguredTitle'.tr(),
                  message: 'file.notConfigured'.tr(),
                )
              : (level.isEmpty && files.isEmpty && uploads.isEmpty)
              ? AwEmptyState(
                  icon: Icons.folder_open_outlined,
                  title: 'files.emptyTitle'.tr(),
                  message: 'files.emptyBody'.tr(),
                )
              : ListView(
                  padding: awListPadding(context),
                  children: [
                    for (final folder in level)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            key: Key('folder-row-${folder.id}'),
                            leading: const FolderLeadingTile(),
                            title: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'files.folderSubtitle'.tr(
                                args: {
                                  // Direct child folders + that level's files
                                  // — WATCHED so the family stays alive
                                  // (ref.read of an autoDispose family tears
                                  // it down mid-stream).
                                  'count':
                                      '${folders.where((f) => f.parentId == folder.id).length + (ref.watch(workspaceLevelFilesProvider(folder.id)).value?.length ?? 0)}',
                                },
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: IconButton(
                              key: Key('folder-menu-${folder.id}'),
                              icon: const Icon(Icons.more_horiz),
                              tooltip: 'files.folderActions'.tr(),
                              onPressed: () => onFolderActions(folder),
                            ),
                            onTap: () => onDescend(folder),
                          ),
                        ),
                      ),
                    for (final job in uploads) UploadRowTile(job: job),
                    for (final file in files)
                      FileRowTile(
                        file: file,
                        onMore: () => showFileActionsSheet(
                          context,
                          ref,
                          file,
                          extraActions: [
                            (
                              icon: Icons.drive_file_move_outlined,
                              label: 'files.moveTo'.tr(),
                              onTap: () => onMoveFile(file),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Kaynaklar: attached files, source-labeled, tap-through to the owner.
class _SourcesLayer extends ConsumerWidget {
  const _SourcesLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(workspaceAttachedFilesProvider).value ??
        const <ProjectFileEntry>[];
    if (entries.isEmpty) {
      return AwEmptyState(
        icon: Icons.attachment_outlined,
        title: 'files.noSourcesTitle'.tr(),
        message: 'files.noSourcesBody'.tr(),
      );
    }
    return ListView(
      padding: awListPadding(context),
      children: [
        for (final entry in entries)
          FileRowTile(
            key: Key('source-file-${entry.file.id}'),
            file: entry.file,
            badge: SourceBadge(
              type: entry.sourceType,
              title: entry.sourceTitle,
            ),
            onMore: () => showFileActionsSheet(
              context,
              ref,
              entry.file,
              extraActions: [
                (
                  icon: Icons.open_in_new,
                  label: 'files.goToSource'.tr(),
                  onTap: () => _goToSource(context, entry),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _goToSource(BuildContext context, ProjectFileEntry entry) {
    switch (entry.sourceType) {
      case 'task':
        context.push('/tasks/${entry.sourceId}');
      case 'note':
        context.go('/notes/${entry.sourceId}');
      case 'project':
        context.go('/projects/${entry.sourceId}');
    }
  }
}
