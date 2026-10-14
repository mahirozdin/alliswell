/// Note → PDF / Markdown / Word, the impure edge (round 16 #3, ADR-0048).
///
/// The layouts live in `data/note_pdf.dart` and `data/note_docx.dart` (both
/// drawing with `data/note_print_style.dart`), the markdown file in
/// `data/note_markdown_file.dart` and the block mapping in
/// `data/markdown_blocks.dart`; none touches a platform channel, so all are
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
import 'package:share_plus/share_plus.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/sheets.dart';
import '../../files/providers.dart';
import '../../files/ui/note_media.dart' show fileIdFromEmbedSource;
import '../markdown/markdown_forge_adapters.dart' show awMarkdownStrings;
import '../data/markdown_blocks.dart';
import '../data/note_blocks.dart';
import '../data/note_docx.dart';
import '../data/note_markdown_file.dart';
import '../data/note_pdf.dart';
import 'note_figure_raster.dart';
import 'note_file_download.dart';

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

/// The file types a note exports to.
enum NoteExportFormat {
  pdf('pdf', 'application/pdf'),
  md('md', markdownMimeType),
  docx('docx', docxMimeType);

  const NoteExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;

  /// The localized name the progress dialog and the sheet use.
  String get label => switch (this) {
    NoteExportFormat.pdf => 'note.exportFormatPdf'.tr(),
    NoteExportFormat.md => 'note.exportFormatMd'.tr(),
    NoteExportFormat.docx => 'note.exportFormatDocx'.tr(),
  };
}

/// Seam so tests can drive the export without a plugin. The default sends the
/// bytes to the OS; a fake records them.
class NoteFileSink {
  const NoteFileSink();

  /// Whether this platform can hand a [format] file to a share sheet. A PDF
  /// goes through `printing`, which can everywhere; anything else goes through
  /// `share_plus`, whose Linux build cannot share a file at all.
  bool canShare(NoteExportFormat format) =>
      format == NoteExportFormat.pdf ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.linux;

  /// The share sheet — or, on the web, a download.
  ///
  /// A PDF keeps the `printing` route it has always had. MD and DOCX need
  /// `share_plus`, because `Printing.sharePdf` can only say application/pdf
  /// and a share target that is told "PDF" about a Word file opens it wrong.
  Future<void> share(
    Uint8List bytes,
    String filename,
    NoteExportFormat format,
  ) async {
    if (format == NoteExportFormat.pdf) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return;
    }
    if (kIsWeb) return downloadNoteFile(bytes, filename, format.mimeType);
    // `unavailable` is NOT a failure: it is share_plus saying the sheet opened
    // but the platform cannot report what the user picked (Android without an
    // activity result, Windows). A real failure throws.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: format.mimeType)],
        fileNameOverrides: [filename],
      ),
    );
  }

  /// PDF only — the sheet does not offer it for anything else.
  Future<void> print(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  /// Returns the chosen path, or null when the user backed out.
  Future<String?> saveToFiles(
    Uint8List bytes,
    String filename,
    NoteExportFormat format,
  ) => FilePicker.saveFile(
    fileName: filename,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: [format.extension],
  );
}

final noteFileSinkProvider = Provider<NoteFileSink>(
  (ref) => const NoteFileSink(),
);

/// A filesystem-safe name derived from the note title, ending in [extension].
@visibleForTesting
String noteFileName(String title, String extension) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final base = cleaned.isEmpty ? 'note' : cleaned;
  // Keep well under every filesystem's limit once the extension is appended.
  final clipped = base.length <= 80 ? base : base.substring(0, 80).trimRight();
  return '$clipped.$extension';
}

/// [noteFileName] for a PDF.
@visibleForTesting
String pdfFileName(String title) => noteFileName(title, 'pdf');

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

/// Builds the PDF for one note and offers it to the user — [exportNote] with
/// [NoteExportFormat.pdf], kept under its old name for its callers.
Future<void> exportNoteAsPdf(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String markdown,
  DateTime? updatedAt,
}) => exportNote(
  context,
  ref,
  format: NoteExportFormat.pdf,
  title: title,
  markdown: markdown,
  updatedAt: updatedAt,
);

/// Builds one note as a [format] file and offers it to the user.
///
/// Shows a blocking progress dialog while the document is produced (fonts,
/// media fetches and layout), then a sheet with the ways out: share, save, or
/// — for a PDF — print. Returns when the sheet closes.
///
/// PDF and DOCX share everything up to the writer: the same blocks, the same
/// fetched media and the same drawn figures, so the two files show the same
/// pictures. Markdown needs none of it — the body already IS the file.
Future<void> exportNote(
  BuildContext context,
  WidgetRef ref, {
  required NoteExportFormat format,
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
      builder: (_) => _ExportingDialog(format: format),
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
    bytes = switch (format) {
      NoteExportFormat.md => noteMarkdownBytes(title, markdown),
      NoteExportFormat.pdf || NoteExportFormat.docx => await _buildLaidOut(
        context,
        ref,
        format: format,
        title: title,
        markdown: markdown,
        updatedAt: updatedAt,
      ),
    };
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
    builder: (_) => _ExportReadySheet(
      bytes: bytes,
      filename: noteFileName(title, format.extension),
      format: format,
    ),
  );
}

/// The PDF or the DOCX: one pipeline into either writer.
Future<Uint8List> _buildLaidOut(
  BuildContext context,
  WidgetRef ref, {
  required NoteExportFormat format,
  required String title,
  required String markdown,
  DateTime? updatedAt,
}) async {
  // OPH-274: the last delta dependency outside the tests. Round 19 narrowed
  // `placeholderFor` to raw HTML alone — diagrams and formulas are now drawn
  // (ADR-0034) rather than named. What is still named is named, because
  // silence is indistinguishable from a bug (DESIGN §10 F3).
  final blocks = markdownToBlocks(
    markdown,
    placeholderFor: (_) => 'note.exportUnsupportedBlock'.tr(),
    // The SAME strings the reading view labels its alerts with (round 19b):
    // two sources would be two chances for the page to call a box something
    // the screen does not.
    alertLabelFor: awMarkdownStrings().alert,
  );
  final fonts = format == NoteExportFormat.pdf
      ? await ref.read(notePdfFontsProvider.future)
      : null;
  // Two sources of pictures, one map. Fetched media and drawn figures are the
  // same thing to the layout engines — bytes under a key — which is what keeps
  // both writers free of the network and the widget tree.
  final images = {
    ...await _resolveImages(ref, blocks),
    if (context.mounted)
      ...await ref
          .read(noteFigureRasterizerProvider)
          .rasterize(context, blocks),
  };
  final updatedLabel = updatedAt == null
      ? null
      : 'note.edited'.tr(
          args: {
            'date': awFormatDateTime(
              updatedAt,
              format: ref.read(dateFormatProvider),
            ),
          },
        );
  final placeholder = 'note.exportMediaMissing'.tr();

  if (fonts == null) {
    return buildNoteDocx(
      NoteDocxDocument(
        title: title,
        blocks: blocks,
        updatedLabel: updatedLabel,
        images: images,
        mediaPlaceholderLabel: placeholder,
      ),
    );
  }
  return buildNotePdf(
    NotePdfDocument(
      title: title,
      blocks: blocks,
      updatedLabel: updatedLabel,
      images: images,
      mediaPlaceholderLabel: placeholder,
    ),
    fonts,
  );
}

class _ExportingDialog extends StatelessWidget {
  const _ExportingDialog({required this.format});

  final NoteExportFormat format;

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
        Expanded(
          child: Text('note.exporting'.tr(args: {'format': format.label})),
        ),
      ],
    ),
  );
}

class _ExportReadySheet extends ConsumerWidget {
  const _ExportReadySheet({
    required this.bytes,
    required this.filename,
    required this.format,
  });

  final Uint8List bytes;
  final String filename;

  /// Decides what the sheet offers: Print exists only for a PDF, and Share
  /// only where this platform can share a file of this type.
  final NoteExportFormat format;

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
    final sink = ref.watch(noteFileSinkProvider);
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
                'note.exportReady'.tr(args: {'format': format.label}),
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
                onTap: () =>
                    _run(context, () => sink.share(bytes, filename, format)),
              )
            else ...[
              if (sink.canShare(format))
                _ExportAction(
                  actionKey: const Key('note-export-share'),
                  icon: Icons.ios_share,
                  title: 'note.exportShare'.tr(),
                  subtitle: 'note.exportShareHint'.tr(),
                  onTap: () =>
                      _run(context, () => sink.share(bytes, filename, format)),
                ),
              _ExportAction(
                actionKey: const Key('note-export-save'),
                icon: Icons.folder_outlined,
                title: 'note.exportSave'.tr(),
                subtitle: 'note.exportSaveHint'.tr(),
                onTap: () => _run(context, () async {
                  final path = await sink.saveToFiles(bytes, filename, format);
                  if (path == null) throw const _Cancelled();
                }, successMessage: 'note.exportSaved'.tr()),
              ),
            ],
            if (format == NoteExportFormat.pdf)
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

/// The popup-menu values of the three export entries — shared by the editor's
/// overflow and the notes list's row menu, so both offer the same formats.
const noteExportMenuValues = {
  'export-pdf': NoteExportFormat.pdf,
  'export-md': NoteExportFormat.md,
  'export-docx': NoteExportFormat.docx,
};

/// "Export as PDF / Markdown / Word" as popup-menu entries, values from
/// [noteExportMenuValues].
List<PopupMenuEntry<String>> noteExportMenuItems({
  Key? pdfKey,
  Key? mdKey,
  Key? docxKey,
}) {
  PopupMenuItem<String> item(
    Key? key,
    String value,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    key: key,
    value: value,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
    ),
  );

  return [
    item(
      pdfKey,
      'export-pdf',
      Icons.picture_as_pdf_outlined,
      'note.exportPdf'.tr(),
    ),
    item(mdKey, 'export-md', Icons.description_outlined, 'note.exportMd'.tr()),
    item(
      docxKey,
      'export-docx',
      Icons.article_outlined,
      'note.exportDocx'.tr(),
    ),
  ];
}
