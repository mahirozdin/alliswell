/// Note → PDF (round 16 #3).
///
/// Deliberately split from the UI: this file turns [NoteBlock]s plus already
/// fetched image bytes into PDF bytes, and touches no platform channel. That
/// keeps the whole layout — headings, lists, checkboxes, quotes, code panels,
/// links, figures — unit-testable with no plugin, no network and no widget
/// tester. The UI edge (`ui/note_export.dart`) does the awaiting.
///
/// KNOWN LIMIT — glyph coverage. The exporter draws with Roboto, which covers
/// Latin (all of Turkish), Greek, Cyrillic, currency and typographic marks, but
/// NOT the dingbat/arrow blocks: `→ ← ✓ ✗ ★ ▪ ☐` and emoji render as a hollow
/// box, and `pdf` logs "Unable to find a font to draw …". PDF's base-14 Symbol
/// and ZapfDingbats were tried as `fontFallback` and rescue none of them (they
/// carry no Unicode mapping the package can use), so they are deliberately NOT
/// wired up — dead weight reads like a solved problem. Fixing this properly
/// means vendoring a symbol-covering face (DejaVu Sans, ~750 KB) as a fallback.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'note_blocks.dart';

/// The four faces the exporter draws with.
///
/// Roboto, vendored into `assets/fonts/` — NOT the `pdf` package's built-in
/// Helvetica, whose WinAnsi encoding has no `ı ğ ş İ`: every Turkish note would
/// export as mojibake. Passed in rather than loaded here so tests can build a
/// document without a Flutter asset bundle.
class NotePdfFonts {
  const NotePdfFonts({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  pw.Font resolve({required bool bold, required bool italic}) => bold && italic
      ? boldItalic
      : bold
      ? this.bold
      : italic
      ? this.italic
      : regular;
}

/// Everything the page needs besides the body.
class NotePdfDocument {
  const NotePdfDocument({
    required this.title,
    required this.blocks,
    this.updatedLabel,
    this.images = const {},
    this.mediaPlaceholderLabel,
  });

  final String title;
  final List<NoteBlock> blocks;

  /// Already-localised "last updated" line, or null to omit it. Formatting a
  /// date is the caller's job — this file must not carry a locale.
  final String? updatedLabel;

  /// Embed source → image bytes. A source that is missing (offline, deleted,
  /// or a fetch that failed) renders as an honest placeholder instead of
  /// vanishing, mirroring the in-app rule (DESIGN §10 F3).
  final Map<String, Uint8List> images;

  /// Already-localised caption for that placeholder. Printing the raw
  /// `alliswell://file/{id}` URI would be honest but meaningless to a reader;
  /// null falls back to the source so nothing ever renders blank.
  final String? mediaPlaceholderLabel;
}

// Palette — the print equivalents of the app tokens. Print is always "light":
// a dark-theme PDF would waste ink and read badly on paper.
const _ink = PdfColor.fromInt(0xFF0F1B2E);
const _muted = PdfColor.fromInt(0xFF44536F);
const _accent = PdfColor.fromInt(0xFF0A5CFF);
const _rule = PdfColor.fromInt(0xFFD8DEEA);
const _codeBg = PdfColor.fromInt(0xFFF2F4F9);

const _bodySize = 11.0;

/// Builds the PDF. Async only because `pdf`'s own `save()` is — no platform
/// channel is involved, so this still runs in a plain `flutter test`.
Future<Uint8List> buildNotePdf(NotePdfDocument doc, NotePdfFonts fonts) async {
  final pdf = pw.Document(
    title: doc.title,
    creator: 'AllisWell',
    theme: pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 2.2 * PdfPageFormat.cm,
        marginRight: 2.2 * PdfPageFormat.cm,
        marginTop: 2.0 * PdfPageFormat.cm,
        marginBottom: 2.0 * PdfPageFormat.cm,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox.shrink()
          : pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                doc.title,
                style: pw.TextStyle(fontSize: 9, color: _muted),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
      build: (context) => [
        // The title is the document's first block, Apple-Notes style — the same
        // rule the editor and the markdown export follow (feedback round 1).
        pw.Text(
          doc.title,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 24,
            color: _ink,
            letterSpacing: -0.4,
          ),
        ),
        if (doc.updatedLabel case final label?) ...[
          pw.SizedBox(height: 4),
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(color: _rule, thickness: 0.7, height: 1),
        pw.SizedBox(height: 14),
        for (final block in doc.blocks) _block(block, doc, fonts),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _block(NoteBlock block, NotePdfDocument doc, NotePdfFonts fonts) {
  pw.Widget padded(pw.Widget child, {double top = 0, double bottom = 6}) =>
      pw.Padding(
        padding: pw.EdgeInsets.only(top: top, bottom: bottom),
        child: child,
      );

  switch (block.kind) {
    case NoteBlockKind.heading1:
      return padded(_rich(block, fonts, size: 19, bold: true), top: 8);
    case NoteBlockKind.heading2:
      return padded(_rich(block, fonts, size: 15.5, bold: true), top: 7);
    case NoteBlockKind.heading3:
      return padded(_rich(block, fonts, size: 13, bold: true), top: 6);

    case NoteBlockKind.bullet:
      return padded(_marker('•', _rich(block, fonts), fonts), bottom: 3);
    case NoteBlockKind.ordered:
      return padded(
        _marker('${block.ordinal ?? 1}.', _rich(block, fonts), fonts),
        bottom: 3,
      );

    // A drawn box, not a "☑"/"☐" character: those glyphs are not in Roboto, so
    // the text route would print blanks.
    case NoteBlockKind.checked:
    case NoteBlockKind.unchecked:
      return padded(
        _checkItem(block, fonts, done: block.kind == NoteBlockKind.checked),
        bottom: 3,
      );

    case NoteBlockKind.quote:
      return padded(
        pw.Container(
          padding: const pw.EdgeInsets.only(left: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: _rule, width: 2.5)),
          ),
          child: _rich(block, fonts, color: _muted, italic: true),
        ),
      );

    case NoteBlockKind.code:
      return padded(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(color: _codeBg),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9.5,
              color: _ink,
              lineSpacing: 2,
            ),
          ),
        ),
      );

    case NoteBlockKind.image:
      final bytes = doc.images[block.source];
      if (bytes == null) {
        return padded(_missingMedia(block, doc, fonts));
      }
      return padded(
        pw.Center(
          child: pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxHeight: 320),
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
        ),
        top: 4,
        bottom: 10,
      );

    case NoteBlockKind.attachment:
      return padded(_missingMedia(block, doc, fonts));

    case NoteBlockKind.paragraph:
      // An intentional blank line keeps its air; it just must not be a full
      // paragraph's worth.
      if (block.text.trim().isEmpty) return pw.SizedBox(height: 6);
      return padded(_rich(block, fonts));
  }
}

pw.Widget _marker(String marker, pw.Widget child, NotePdfFonts fonts) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(
      width: 18,
      child: pw.Text(
        marker,
        style: pw.TextStyle(
          font: fonts.regular,
          fontSize: _bodySize,
          color: _muted,
        ),
      ),
    ),
    pw.Expanded(child: child),
  ],
);

/// The tick is DRAWN, not typed. Roboto has no U+2713 — `pdf` refuses to lay
/// out a glyph it cannot find ("Unable to find a font to draw ✓"), and a
/// checklist is exactly the block a note is most likely to be made of.
class _TickPainter {
  const _TickPainter();

  void paint(PdfGraphics canvas, PdfPoint size) {
    canvas
      ..setStrokeColor(PdfColors.white)
      ..setLineWidth(1.1)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      // PDF's origin is bottom-left, so the tick's elbow is LOW.
      ..moveTo(size.x * 0.22, size.y * 0.52)
      ..lineTo(size.x * 0.43, size.y * 0.28)
      ..lineTo(size.x * 0.80, size.y * 0.72)
      ..strokePath();
  }
}

pw.Widget _checkItem(
  NoteBlock block,
  NotePdfFonts fonts, {
  required bool done,
}) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Container(
      width: 9,
      height: 9,
      margin: const pw.EdgeInsets.only(top: 3, right: 9),
      decoration: pw.BoxDecoration(
        color: done ? _accent : null,
        border: pw.Border.all(color: done ? _accent : _muted, width: 0.9),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: done
          ? pw.CustomPaint(
              size: const PdfPoint(9, 9),
              painter: (canvas, size) =>
                  const _TickPainter().paint(canvas, size),
            )
          : null,
    ),
    // Done means done, on paper too (DESIGN §20).
    pw.Expanded(
      child: _rich(
        block,
        fonts,
        color: done ? _muted : _ink,
        forceStrike: done,
      ),
    ),
  ],
);

pw.Widget _missingMedia(
  NoteBlock block,
  NotePdfDocument doc,
  NotePdfFonts fonts,
) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule, width: 0.7)),
  child: pw.Text(
    doc.mediaPlaceholderLabel ?? block.source ?? '',
    style: pw.TextStyle(font: fonts.italic, fontSize: 9, color: _muted),
    maxLines: 2,
    overflow: pw.TextOverflow.clip,
  ),
);

pw.Widget _rich(
  NoteBlock block,
  NotePdfFonts fonts, {
  double size = _bodySize,
  bool bold = false,
  bool italic = false,
  bool forceStrike = false,
  PdfColor color = _ink,
}) {
  if (block.spans.isEmpty) return pw.SizedBox(height: size);
  return pw.RichText(
    text: pw.TextSpan(
      children: [
        for (final span in block.spans)
          pw.TextSpan(
            text: span.text,
            style: pw.TextStyle(
              font: fonts.resolve(
                bold: bold || span.bold,
                italic: italic || span.italic,
              ),
              fontSize: span.code ? size - 0.5 : size,
              color: span.link != null ? _accent : color,
              lineSpacing: 2.4,
              background: span.code
                  ? const pw.BoxDecoration(color: _codeBg)
                  : null,
              decoration: pw.TextDecoration.combine([
                if (span.strike || forceStrike) pw.TextDecoration.lineThrough,
                if (span.link != null) pw.TextDecoration.underline,
              ]),
            ),
            // A link in a PDF should be clickable, not just blue.
            annotation: span.link != null ? pw.AnnotationUrl(span.link!) : null,
          ),
      ],
    ),
  );
}
