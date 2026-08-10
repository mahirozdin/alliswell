import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart' show AwI18n, AwTr;
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/swipe_actions.dart';
import '../../integrations/providers.dart' show urlLauncherProvider;
import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../providers.dart';
import 'attach_menu.dart';
import 'image_viewer.dart';

/// Shared attachment UI (OPH-154/155, DESIGN §10): one row anatomy for task
/// attachments, the project Files tab and note media — F1 says these three
/// homes render the SAME row, so it lives here once.

/// `1.2 MB` style human size — file sizes are display data (F6: users never
/// see raw byte counts, keys or URLs).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  do {
    value /= 1024;
    unit += 1;
  } while (value >= 1024 && unit < units.length - 1);
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

IconData fileKindIcon(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime == 'application/zip' || mime == 'application/gzip') {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// 40 px leading square: image thumbnail from a minted URL, or a kind icon on
/// a soft tile. Offline / URL unavailable → the icon, never a broken glyph
/// (F3); shimmer only while a fetch is actually in flight.
class FileLeadingThumb extends ConsumerWidget {
  const FileLeadingThumb({super.key, required this.file});

  final FileAttachment file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final iconTile = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AwRadius.s),
      ),
      child: Icon(fileKindIcon(file.mime), color: scheme.onSurfaceVariant),
    );
    if (!file.isImage) return iconTile;

    // Fetching or unavailable → the honest tile, never a broken glyph (F3).
    final url = ref.watch(fileUrlProvider(file.id)).value;
    if (url == null) return iconTile;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AwRadius.s),
      child: Image(
        image: ref.watch(networkImageProvider)(url),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => iconTile,
      ),
    );
  }
}

/// One ready attachment row (F1). [badge] is the Files-tab source chip (F4);
/// task/note lists leave it null.
class FileRowTile extends ConsumerWidget {
  const FileRowTile({
    super.key,
    required this.file,
    this.badge,
    this.onMore,
    this.siblingImageIds = const [],
  });

  final FileAttachment file;
  final Widget? badge;

  /// The extra actions this surface injects (OPH-170: move to folder, go to
  /// source), reachable from the row's own ⋯ button — the affordance folder
  /// rows already use.
  ///
  /// Until OPH-245 this ALSO swallowed the tap, for every kind, images
  /// included: that is why an image opened a sheet in Dosyalar and the viewer
  /// in a project's Files tab. The tap now follows the file's kind (A7), and
  /// the extra actions kept their own way in rather than being orphaned.
  final VoidCallback? onMore;

  /// The images this surface is showing, in the order it is showing them, so a
  /// tapped image can be swiped through its siblings (DESIGN §30 A11). Empty
  /// means "this image, alone".
  final List<String> siblingImageIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = file.createdAt;
    final subtitle = [
      formatBytes(file.sizeBytes),
      if (when != null)
        awFormatDate(when, format: ref.watch(dateFormatProvider)),
    ].join(' · ');

    // OPH-184: the same swipe every other list has. A file delete removes the
    // OBJECT from storage on every device, so it keeps its confirmation dialog
    // (DESIGN §19 D3) — the swipe is a shortcut to that question, not past it.
    return AwSwipeToDelete(
      id: file.id,
      semanticLabel: 'file.deleteConfirm'.tr(args: {'name': file.name}),
      onDelete: () => confirmFileDelete(context, ref, file),
      child: Card(
        child: ListTile(
          leading: FileLeadingThumb(file: file),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: (badge == null && onMore == null)
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?badge,
                    if (onMore != null)
                      IconButton(
                        key: Key('file-menu-${file.id}'),
                        tooltip: 'file.fileActions'.tr(),
                        icon: const Icon(Icons.more_horiz),
                        onPressed: onMore,
                      ),
                  ],
                ),
          onTap: () => _onTap(context, ref),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // The tap says what the KIND says, on every surface (A7). Surfaces that
    // inject extra actions offer them through [onMore]'s ⋯ button instead of
    // intercepting this.
    if (file.isImage) {
      final ids = siblingImageIds.isEmpty ? [file.id] : siblingImageIds;
      final at = ids.indexOf(file.id);
      await showAwImageViewer(
        context,
        fileIds: ids,
        initialIndex: at < 0 ? 0 : at,
      );
      return;
    }
    await showFileActionsSheet(context, ref, file);
  }
}

/// An in-flight or failed upload row (F2): determinate progress + cancel, or
/// the inline-error treatment with retry — never a silent disappearance.
class UploadRowTile extends ConsumerWidget {
  const UploadRowTile({super.key, required this.job});

  final UploadJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uploads = ref.read(uploadsProvider.notifier);
    final failed = job.phase == UploadPhase.failed;

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: failed
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AwRadius.s),
          ),
          child: Icon(
            failed ? Icons.error_outline : Icons.upload_file_outlined,
            color: failed
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: failed
            ? Text(
                _errorText(job.errorCode, 'file.uploadFailed'.tr()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(top: AwSpace.x2),
                child: LinearProgressIndicator(
                  value: job.progress > 0 ? job.progress : null,
                  minHeight: 4,
                ),
              ),
        trailing: failed
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'common.retry'.tr(),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => uploads.retry(job.localId),
                  ),
                  IconButton(
                    tooltip: 'common.close'.tr(),
                    icon: const Icon(Icons.close),
                    onPressed: () => uploads.dismiss(job.localId),
                  ),
                ],
              )
            : IconButton(
                tooltip: 'common.cancel'.tr(),
                icon: const Icon(Icons.close),
                onPressed: () => uploads.cancel(job.localId),
              ),
      ),
    );
  }
}

/// Maps a stable error code through `error.<CODE>` with an honest, surface-
/// specific fallback (private: the app-wide mapper is `localizedError` in
/// core/error_messages.dart — this one exists for code-only sites like
/// UploadJob.errorCode where there is no exception object).
String _errorText(String? code, String fallback) {
  if (code == null) return fallback;
  return AwI18n.instance.maybeTranslate('error.$code') ?? fallback;
}

/// Open/Download · Rename · Delete for one file (F5: destructive confirms
/// with the filename; F6: failures speak product language).
Future<void> showFileActionsSheet(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file, {
  // OPH-170: callers inject context actions (move-to-folder, go-to-source).
  List<({IconData icon, String label, VoidCallback onTap})> extraActions =
      const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: FileLeadingThumb(file: file),
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(file.sizeBytes)),
          ),
          const Divider(height: 1),
          for (final action in extraActions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                action.onTap();
              },
            ),
          // OPH-201: inside the sheet rather than an injected extra action, so
          // all five callers (folders, sources, project tabs, note media, the
          // default tap) get it without touching a single call site.
          Consumer(
            builder: (context, sheetRef, _) => quickAccessSheetTile(
              isSaved: isInQuickAccess(sheetRef, QuickKind.file, file.id),
              onTap: () {
                Navigator.of(sheetContext).pop();
                toggleQuickAccess(
                  context,
                  sheetRef,
                  kind: QuickKind.file,
                  targetId: file.id,
                  suggestedTitle: file.name,
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text('file.openDownload'.tr()),
            onTap: () {
              Navigator.of(sheetContext).pop();
              openFileExternally(context, ref, file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text('file.rename'.tr()),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showFileRenameDialog(context, ref, file);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(sheetContext).colorScheme.error,
            ),
            title: Text(
              'common.delete'.tr(),
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              confirmFileDelete(context, ref, file);
            },
          ),
          const SizedBox(height: AwSpace.x2),
        ],
      ),
    ),
  );
}

/// Launches a freshly minted download URL — the browser/OS saves it. Nothing
/// is written to app storage in v1 (ATTACHMENTS.md §2.2).
Future<void> openFileExternally(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  // urlFor answers null on any failure (it never throws) — one honest path.
  final url = await ref.read(fileUrlCacheProvider).urlFor(file.id);
  if (url == null) {
    messenger?.showSnackBar(SnackBar(content: Text('file.couldNotOpen'.tr())));
    return;
  }
  await ref.read(urlLauncherProvider)(Uri.parse(url));
}

Future<void> showFileRenameDialog(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final controller = TextEditingController(text: file.name);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final newName = await showDialog<String>(
    context: context,
    // Round 13 #2: dialogs go to the ROOT navigator for the same
    // reason sheets do (OPH-212) — inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: Text('file.renameTitle'.tr()),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 255,
        decoration: InputDecoration(labelText: 'file.nameLabel'.tr()),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text('common.save'.tr()),
        ),
      ],
    ),
  );
  controller.dispose();
  if (newName == null || newName.isEmpty || newName == file.name) return;
  try {
    await ref.read(filesApiProvider).rename(file.id, newName);
    await ref.read(syncEngineProvider)?.syncNow();
  } on ApiException catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(_errorText(e.code, 'file.couldNotRename'.tr()))),
    );
  }
}

/// True only when the user confirmed AND the server accepted it. The viewer
/// needs to tell those apart (OPH-245): before this returned a verdict it
/// popped unconditionally, so cancelling the dialog still closed the image.
Future<bool> confirmFileDelete(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    // Round 13 #2: dialogs go to the ROOT navigator for the same
    // reason sheets do (OPH-212) — inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: Text('file.deleteConfirm'.tr(args: {'name': file.name})),
      content: Text('file.deleteBody'.tr()),
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
  if (confirmed != true) return false;
  try {
    await ref.read(filesApiProvider).delete(file.id);
    ref.read(fileUrlCacheProvider).evict(file.id);
    await ref.read(syncEngineProvider)?.syncNow();
    return true;
  } on ApiException catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(_errorText(e.code, 'file.couldNotDelete'.tr()))),
    );
    return false;
  }
}

/// The whole attachments body for one entity (task detail today, reusable by
/// design): add button, upload rows for THIS target, then the synced files.
/// Storage off → one quiet explainer row (F6) — no spinner, no dead button.
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({
    super.key,
    required this.workspaceId,
    required this.targetType,
    required this.targetId,
  });

  final String workspaceId;
  final String targetType;
  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(storageStatusProvider);
    final files = ref.watch(
      targetFilesProvider((targetType: targetType, targetId: targetId)),
    );
    final uploads = ref
        .watch(uploadsProvider)
        .where((j) => j.targetType == targetType && j.targetId == targetId)
        .toList();

    final configured =
        status.value?.configured ?? true; // optimistic while loading
    if (!configured && (files.value?.isEmpty ?? true) && uploads.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              'file.notConfigured'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final rows = files.value ?? const <FileAttachment>[];
    // The gallery is what this surface is showing, in the order it shows it.
    final imageIds = [
      for (final file in rows)
        if (file.isImage) file.id,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final job in uploads) UploadRowTile(job: job),
        for (final file in rows)
          FileRowTile(file: file, siblingImageIds: imageIds),
        const SizedBox(height: AwSpace.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: AttachButton(
            buttonKey: const Key('attach-button'),
            enabled: configured,
            onPicked: (picks) => ref
                .read(uploadsProvider.notifier)
                .uploadAll(
                  workspaceId: workspaceId,
                  targetType: targetType,
                  targetId: targetId,
                  sources: picks,
                ),
          ),
        ),
      ],
    );
  }
}

/// Folder rows lead with the same soft tile as file kind icons (F8).
class FolderLeadingTile extends StatelessWidget {
  const FolderLeadingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AwRadius.s),
      ),
      child: Icon(Icons.folder_outlined, color: scheme.onSurfaceVariant),
    );
  }
}

/// Source badge for aggregated rows (F4/F7) — public twin of the project
/// Files tab's badge so the Dosyalar section reuses one anatomy.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.type, required this.title});

  final String type;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (type) {
      'project' => 'file.sourceProject'.tr(args: {'name': title}),
      'task' => 'file.sourceTask'.tr(args: {'name': title}),
      _ => 'file.sourceNote'.tr(args: {'name': title}),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
