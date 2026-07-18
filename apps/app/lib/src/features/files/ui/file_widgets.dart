import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart' show AwI18n, AwTr;
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../integrations/providers.dart' show urlLauncherProvider;
import '../providers.dart';

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
      child: Image.network(
        url,
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
  const FileRowTile({super.key, required this.file, this.badge});

  final FileAttachment file;
  final Widget? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = file.createdAt;
    final subtitle = [
      formatBytes(file.sizeBytes),
      if (when != null) DateFormat.yMMMd().format(when.toLocal()),
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: FileLeadingThumb(file: file),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: badge,
        onTap: () => _onTap(context, ref),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    if (file.isImage) {
      await showFileImageViewer(context, ref, file);
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
  FileAttachment file,
) {
  return showModalBottomSheet<void>(
    context: context,
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

Future<void> confirmFileDelete(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
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
  if (confirmed != true) return;
  try {
    await ref.read(filesApiProvider).delete(file.id);
    ref.read(fileUrlCacheProvider).evict(file.id);
    await ref.read(syncEngineProvider)?.syncNow();
  } on ApiException catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text(_errorText(e.code, 'file.couldNotDelete'.tr()))),
    );
  }
}

/// Full-screen image viewer: pinch/pan via InteractiveViewer, honest
/// loading/error states, actions accessible from the app bar.
Future<void> showFileImageViewer(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _FileImageViewer(file: file),
    ),
  );
}

class _FileImageViewer extends ConsumerWidget {
  const _FileImageViewer({required this.file});

  final FileAttachment file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'file.openDownload'.tr(),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openFileExternally(context, ref, file),
          ),
          IconButton(
            tooltip: 'common.delete'.tr(),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await confirmFileDelete(context, ref, file);
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
      body: ref
          .watch(fileUrlProvider(file.id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text('file.couldNotOpen'.tr())),
            data: (url) => url == null
                ? Center(child: Text('file.couldNotOpen'.tr()))
                : InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) =>
                            Center(child: Text('file.couldNotOpen'.tr())),
                      ),
                    ),
                  ),
          ),
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final job in uploads) UploadRowTile(job: job),
        for (final file in files.value ?? const <FileAttachment>[])
          FileRowTile(file: file),
        const SizedBox(height: AwSpace.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: configured
                ? () => ref
                      .read(uploadsProvider.notifier)
                      .pickAndUpload(
                        workspaceId: workspaceId,
                        targetType: targetType,
                        targetId: targetId,
                      )
                : null,
            icon: const Icon(Icons.attach_file),
            label: Text('file.add'.tr()),
          ),
        ),
      ],
    );
  }
}
