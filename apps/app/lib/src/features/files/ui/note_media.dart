import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart' show AwTr;
import '../../../theme/tokens.dart';
import '../../integrations/providers.dart' show urlLauncherProvider;
import '../providers.dart';

/// Inline note media (Epic 14, OPH-156 — BLUEPRINT §12.5 rev.).
///
/// Embeds carry `alliswell://file/{fileId}` sources — a stable id, NEVER a
/// presigned URL (those expire; ADR-0011). Rendering resolves the id to a
/// fresh minted URL via [FileUrlCache]; offline or gone → an honest
/// placeholder tile, never a broken-image glyph (DESIGN §10 F3). Foreign
/// http(s) sources in deltas from elsewhere still render (don't break other
/// people's documents).

final _fileEmbedRe = RegExp(r'^alliswell://file/([0-9A-HJKMNP-TV-Z]{26})$');

/// The file id behind an embed source, or null for foreign/malformed sources.
String? fileIdFromEmbedSource(String source) =>
    _fileEmbedRe.firstMatch(source)?.group(1);

/// Embed builders for both the editor and read-only renderers (README view).
List<EmbedBuilder> awNoteEmbedBuilders() => [
  _AwImageEmbedBuilder(),
  _AwVideoEmbedBuilder(),
];

class _AwImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data;
    return AwNoteImageEmbed(source: source is String ? source : '');
  }
}

class _AwVideoEmbedBuilder extends EmbedBuilder {
  @override
  String get key => BlockEmbed.videoType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data;
    return AwNoteMediaTile(source: source is String ? source : '');
  }
}

/// An inline image: minted-URL fetch → image (tap = full-screen viewer);
/// while fetching → soft progress tile; unavailable → placeholder tile.
class AwNoteImageEmbed extends ConsumerWidget {
  const AwNoteImageEmbed({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileId = fileIdFromEmbedSource(source);
    if (fileId == null) {
      // A foreign (http) image from someone else's delta.
      return _framed(
        context,
        Image.network(
          source,
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => _placeholder(context, null),
        ),
      );
    }
    return ref
        .watch(fileUrlProvider(fileId))
        .when(
          loading: () => _loadingTile(context),
          error: (_, _) => _placeholder(context, fileId),
          data: (url) => url == null
              ? _placeholder(context, fileId)
              : GestureDetector(
                  onTap: () => _openViewer(context, ref, fileId),
                  child: _framed(
                    context,
                    Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : _loadingTile(context),
                      errorBuilder: (context, _, _) =>
                          _placeholder(context, fileId),
                    ),
                  ),
                ),
        );
  }

  Widget _framed(BuildContext context, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AwRadius.m),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: child,
      ),
    ),
  );

  Widget _loadingTile(BuildContext context) => Container(
    height: 160,
    margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AwRadius.m),
    ),
    child: const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _placeholder(BuildContext context, String? fileId) =>
      _EmbedPlaceholder(fileId: fileId, icon: Icons.image_outlined);

  Future<void> _openViewer(
    BuildContext context,
    WidgetRef ref,
    String fileId,
  ) async {
    final file = await ref.read(fileByIdProvider(fileId).future);
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _EmbedImageViewer(
          title: file?.name ?? 'file.mediaUnavailable'.tr(),
          fileId: fileId,
        ),
      ),
    );
  }
}

/// Video (and any non-image) embed: a tile with the file's current name and
/// an open action — inline playback is deliberately v2 (ATTACHMENTS.md §11).
class AwNoteMediaTile extends ConsumerWidget {
  const AwNoteMediaTile({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fileId = fileIdFromEmbedSource(source);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            Icons.movie_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: fileId == null
              ? Text(source, maxLines: 1, overflow: TextOverflow.ellipsis)
              : Text(
                  ref.watch(fileByIdProvider(fileId)).value?.name ??
                      'file.mediaUnavailable'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open(context, ref, fileId),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String? fileId,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = fileId == null
        ? source
        : await ref.read(fileUrlCacheProvider).urlFor(fileId);
    if (url == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text('file.couldNotOpen'.tr())),
      );
      return;
    }
    await ref.read(urlLauncherProvider)(Uri.parse(url));
  }
}

class _EmbedPlaceholder extends ConsumerWidget {
  const _EmbedPlaceholder({required this.fileId, required this.icon});

  final String? fileId;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = fileId; // local so the null check promotes
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
      padding: const EdgeInsets.all(AwSpace.x4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AwRadius.m),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AwSpace.x3),
          Expanded(
            child: Text(
              id == null
                  ? 'file.mediaUnavailable'.tr()
                  : ref.watch(fileByIdProvider(id)).value?.name ??
                        'file.mediaUnavailable'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbedImageViewer extends ConsumerWidget {
  const _EmbedImageViewer({required this.title, required this.fileId});

  final String title;
  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ref
          .watch(fileUrlProvider(fileId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text('file.couldNotOpen'.tr())),
            data: (url) => url == null
                ? Center(child: Text('file.couldNotOpen'.tr()))
                : InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
          ),
    );
  }
}

/// The editor toolbar's "insert image / insert video" buttons: pick → upload
/// to the NOTE → insert the `alliswell://file/{id}` embed at the caret on
/// completion (no phantom embeds while bytes are still in flight). Files that
/// are neither image nor video still upload as note attachments — visible in
/// the project Files tab — with an honest snackbar instead of a weird embed.
class NoteMediaButtons extends ConsumerWidget {
  const NoteMediaButtons({
    super.key,
    required this.controller,
    required this.ensureNote,
  });

  final QuillController controller;

  /// Autosaves a brand-new note first so an upload has a target id.
  final Future<({String noteId, String workspaceId})?> Function() ensureNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'file.insertImage'.tr(),
          icon: const Icon(Icons.image_outlined),
          onPressed: () => _pickAndInsert(context, ref),
        ),
        IconButton(
          tooltip: 'file.insertVideo'.tr(),
          icon: const Icon(Icons.movie_outlined),
          onPressed: () => _pickAndInsert(context, ref),
        ),
      ],
    );
  }

  Future<void> _pickAndInsert(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picks = await ref.read(filePickerProvider)();
    if (picks.isEmpty) return;
    final target = await ensureNote();
    if (target == null) return;

    for (final pick in picks) {
      final fileId = await ref
          .read(uploadsProvider.notifier)
          .start(
            workspaceId: target.workspaceId,
            targetType: 'note',
            targetId: target.noteId,
            source: pick,
          );
      if (fileId == null) continue; // the upload strip shows the failure
      final mime = pick.mime ?? mimeForName(pick.name);
      final uri = 'alliswell://file/$fileId';

      final BlockEmbed? embed;
      if (mime.startsWith('image/')) {
        embed = BlockEmbed.image(uri);
      } else if (mime.startsWith('video/')) {
        embed = BlockEmbed.video(uri);
      } else {
        embed = null;
      }
      if (embed == null) {
        messenger?.showSnackBar(
          SnackBar(content: Text('file.attachedNotEmbedded'.tr())),
        );
        continue;
      }

      final selection = controller.selection;
      final index = selection.isValid
          ? selection.start
          : controller.document.length - 1;
      final length = selection.isValid ? selection.end - selection.start : 0;
      controller.replaceText(
        index,
        length,
        embed,
        TextSelection.collapsed(offset: index + 1),
      );
    }
  }
}
