/// Note → PDF, the impure edge (round 16 #3).
///
/// The layout lives in `data/note_pdf.dart` and the delta mapping in
/// `data/note_blocks.dart`; neither touches a platform channel, so both are
/// testable in a plain `flutter test`. This file owns
/// only what needs a platform: reading the fonts out of the asset bundle,
/// fetching embedded media, showing the progress dialog, and handing the bytes
/// to the OS.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/sheets.dart';
import '../../files/providers.dart';
import '../../files/ui/note_media.dart' show fileIdFromEmbedSource;
import '../data/markdown_blocks.dart';
import '../data/note_blocks.dart';
import '../data/note_pdf.dart';

/// How long we wait for ONE embedded image before exporting without it. An
/// export that hangs on a dead attachment is worse than one that prints an
/// honest placeholder.
const _imageTimeout = Duration(seconds: 8);

/// The faces the exporter draws with, read once per process: four Roboto
/// weights plus DejaVu Sans as the symbol fallback. ~1.4 MB of asset decoding
/// is cheap but not free, and a second export should be instant.
final notePdfFontsProvider = FutureProvider<NotePdfFonts>((ref) async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return NotePdfFonts(
    regular: await load('Roboto-Regular'),
    bold: await load('Roboto-Bold'),
    italic: await load('Roboto-Italic'),
    boldItalic: await load('Roboto-BoldItalic'),
    // The per-glyph fallback for everything Roboto's 896 code points miss.
    symbols: await load('DejaVuSans'),
  );
});

/// Seam so tests can drive the export without a plugin. The default sends the
/// bytes to the OS; a fake records them.
class NotePdfSink {
  const NotePdfSink();

  Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  Future<void> print(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  /// Returns the chosen path, or null when the user backed out.
  Future<String?> saveToFiles(Uint8List bytes, String filename) =>
      FilePicker.saveFile(
        fileName: filename,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
}

final notePdfSinkProvider = Provider<NotePdfSink>((ref) => const NotePdfSink());

/// A filesystem-safe name derived from the note title.
@visibleForTesting
String pdfFileName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final base = cleaned.isEmpty ? 'note' : cleaned;
  // Keep well under every filesystem's limit once ".pdf" is appended.
  final clipped = base.length <= 80 ? base : base.substring(0, 80).trimRight();
  return '$clipped.pdf';
}

/// Fetches the bytes for every image embed in [blocks].
///
/// Best effort by design: a missing or slow attachment yields no entry, and
/// `buildNotePdf` prints a placeholder for it (DESIGN §10 F3 — an honest
/// placeholder, never a broken-image glyph).
Future<Map<String, Uint8List>> _resolveImages(
  WidgetRef ref,
  List<NoteBlock> blocks,
) async {
  final sources = {
    for (final b in blocks)
      if (b.kind == NoteBlockKind.image && b.source != null) b.source!,
  };
  if (sources.isEmpty) return const {};

  final cache = ref.read(fileUrlCacheProvider);
  final dio = Dio();
  final out = <String, Uint8List>{};

  await Future.wait(
    sources.map((source) async {
      try {
        final fileId = fileIdFromEmbedSource(source);
        // Foreign http(s) sources in deltas from elsewhere are fetched as-is;
        // ours are minted fresh (presigned URLs expire — ADR-0011).
        final url = fileId == null ? source : await cache.urlFor(fileId);
        if (url == null || !url.startsWith('http')) return;
        final response = await dio
            .get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes),
            )
            .timeout(_imageTimeout);
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          out[source] = Uint8List.fromList(data);
        }
      } on Object {
        // Placeholder it is.
      }
    }),
  );
  return out;
}

/// Builds the PDF for one note and offers it to the user.
///
/// Shows a blocking progress dialog while the document is produced (fonts,
/// media fetches and layout), then a sheet with the ways out: share, save, or
/// print. Returns when the sheet closes.
Future<void> exportNoteAsPdf(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String markdown,
  DateTime? updatedAt,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const _ExportingDialog(),
    ).then((_) => dialogOpen = false),
  );

  void closeDialog() {
    if (dialogOpen && navigator.canPop()) {
      dialogOpen = false;
      navigator.pop();
    }
  }

  Uint8List bytes;
  try {
    // OPH-274: the last delta dependency outside the tests. Blocks the page
    // cannot draw (math, diagrams, raw HTML) name themselves instead of
    // vanishing — DESIGN §10 F3, applied to paper.
    final blocks = markdownToBlocks(
      markdown,
      placeholderFor: (_) => 'note.exportUnsupportedBlock'.tr(),
    );
    final fonts = await ref.read(notePdfFontsProvider.future);
    final images = await _resolveImages(ref, blocks);
    bytes = await buildNotePdf(
      NotePdfDocument(
        title: title,
        blocks: blocks,
        updatedLabel: updatedAt == null
            ? null
            : 'note.edited'.tr(
                args: {
                  'date': awFormatDateTime(
                    updatedAt,
                    format: ref.read(dateFormatProvider),
                  ),
                },
              ),
        images: images,
        mediaPlaceholderLabel: 'note.exportMediaMissing'.tr(),
      ),
      fonts,
    );
  } on Object {
    closeDialog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('note.exportFailed'.tr())));
    return;
  }

  closeDialog();
  if (!context.mounted) return;
  await showAwSheet<void>(
    context,
    builder: (_) =>
        _ExportReadySheet(bytes: bytes, filename: pdfFileName(title)),
  );
}

class _ExportingDialog extends StatelessWidget {
  const _ExportingDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('note-export-progress'),
    content: Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text('note.exporting'.tr())),
      ],
    ),
  );
}

class _ExportReadySheet extends ConsumerWidget {
  const _ExportReadySheet({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text('note.exportFailed'.tr())));
      return;
    }
    if (navigator.canPop()) navigator.pop();
    if (successMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sink = ref.watch(notePdfSinkProvider);
    final theme = Theme.of(context);
    // On the web the OS has no share sheet — the browser downloads the file —
    // and there is no "Files" to save into. Saying "Share" there would name a
    // thing that does not happen.
    final sizeKb = (bytes.lengthInBytes / 1024).round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'note.exportReady'.tr(),
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'note.exportFile'.tr(
                  args: {'name': filename, 'size': '$sizeKb'},
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (kIsWeb)
              _ExportAction(
                actionKey: const Key('note-export-download'),
                icon: Icons.download_outlined,
                title: 'note.exportDownload'.tr(),
                subtitle: 'note.exportDownloadHint'.tr(),
                onTap: () => _run(context, () => sink.share(bytes, filename)),
              )
            else ...[
              _ExportAction(
                actionKey: const Key('note-export-share'),
                icon: Icons.ios_share,
                title: 'note.exportShare'.tr(),
                subtitle: 'note.exportShareHint'.tr(),
                onTap: () => _run(context, () => sink.share(bytes, filename)),
              ),
              _ExportAction(
                actionKey: const Key('note-export-save'),
                icon: Icons.folder_outlined,
                title: 'note.exportSave'.tr(),
                subtitle: 'note.exportSaveHint'.tr(),
                onTap: () => _run(context, () async {
                  final path = await sink.saveToFiles(bytes, filename);
                  if (path == null) throw const _Cancelled();
                }, successMessage: 'note.exportSaved'.tr()),
              ),
            ],
            _ExportAction(
              actionKey: const Key('note-export-print'),
              icon: Icons.print_outlined,
              title: 'note.exportPrint'.tr(),
              subtitle: 'note.exportPrintHint'.tr(),
              onTap: () => _run(context, () => sink.print(bytes, filename)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The user backing out of the save dialog is not an error, but it must not
/// look like success either — `_run` reports it the same way as a failure only
/// because there is nothing else honest to say.
class _Cancelled implements Exception {
  const _Cancelled();
}

class _ExportAction extends StatelessWidget {
  const _ExportAction({
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: actionKey,
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          onTap: onTap,
        ),
      ),
    );
  }
}
