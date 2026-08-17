import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart' show AwTr;
import '../../notes/data/note_document.dart';
import '../providers.dart';
import 'attach_menu.dart';

/// Inline note media (Epic 14, OPH-156 — BLUEPRINT §12.5 rev.).
///
/// Embeds carry `alliswell://file/{fileId}` sources — a stable id, NEVER a
/// presigned URL (those expire; ADR-0011). Rendering resolves the id to a
/// fresh minted URL via [FileUrlCache]; offline or gone → an honest
/// placeholder tile, never a broken-image glyph (DESIGN §10 F3). Foreign
/// http(s) sources still render (don't break other people's documents).
///
/// ADR-0033 removed the Quill `EmbedBuilder` pair that used to live here.
/// Markdown images go through `aw_markdown.dart`, which resolves the same
/// scheme and builds the image viewer's gallery by walking its own document —
/// so document order can no longer differ between the renderer and the
/// viewer, which is what the delta walk existed to guarantee.

final _fileEmbedRe = RegExp(r'^alliswell://file/([0-9A-HJKMNP-TV-Z]{26})$');

/// The file id behind an embed source, or null for foreign/malformed sources.
String? fileIdFromEmbedSource(String source) =>
    _fileEmbedRe.firstMatch(source)?.group(1);

/// The widgets that used to live here — `AwNoteImageEmbed`, `AwNoteMediaTile`
/// and their placeholder — are gone with ADR-0033. They were Quill embed
/// renderers, and the markdown renderer draws its own images and its own
/// honest placeholder (`aw_markdown.dart`, `MdImageSource`). Keeping a second
/// pair around for nobody to call is §22's dead affordance at the widget
/// level: two implementations of one picture, only one of them reachable, and
/// no way to tell which one a bug report is about.

/// The editor toolbar's "insert image / insert video" buttons: pick → upload
/// to the NOTE → write the `alliswell://file/{id}` reference at the caret on
/// completion (nothing appears while bytes are still in flight). A file that
/// is neither image nor video becomes a LINK rather than an `![…]()` every
/// renderer would draw as broken — it is in the document either way, and the
/// reading view opens it.
class NoteMediaButtons extends ConsumerWidget {
  const NoteMediaButtons({
    super.key,
    required this.document,
    required this.ensureNote,
  });

  /// The document, not the Quill controller: where an upload lands is the
  /// document's decision now (`NoteDocument.insertFile`), shared with the
  /// drop target so the two cannot drift apart.
  final NoteDocument document;

  /// Autosaves a brand-new note first so an upload has a target id.
  final Future<({String noteId, String workspaceId})?> Function() ensureNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // OPH-244: two buttons, two sources. They used to call one untyped
        // picker, so "Insert image" opened the document browser and the
        // tooltip was simply a lie about what would happen. No attach MENU
        // here — these are format-insertion buttons, not the attach control.
        IconButton(
          key: const Key('note-insert-image'),
          tooltip: 'file.insertImage'.tr(),
          icon: const Icon(Icons.image_outlined),
          onPressed: () =>
              _pickAndInsert(context, ref, AttachSource.imageLibrary),
        ),
        IconButton(
          key: const Key('note-insert-video'),
          tooltip: 'file.insertVideo'.tr(),
          icon: const Icon(Icons.movie_outlined),
          onPressed: () =>
              _pickAndInsert(context, ref, AttachSource.videoLibrary),
        ),
      ],
    );
  }

  Future<void> _pickAndInsert(
    BuildContext context,
    WidgetRef ref,
    AttachSource source,
  ) async {
    final picks = await pickFrom(context, ref, source);
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
      // Every outcome now puts something in the document — an image embeds, a
      // video or a document becomes a link (ADR-0033) — so there is no longer
      // a silent case to apologise for.
      document.insertFile(
        fileId: fileId,
        name: pick.name,
        mime: pick.mime ?? mimeForName(pick.name),
      );
    }
  }
}
