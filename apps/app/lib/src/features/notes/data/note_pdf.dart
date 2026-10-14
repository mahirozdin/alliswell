/// Note → PDF (round 16 #3).
///
/// Deliberately split from the UI: this file turns [NoteBlock]s plus already
/// fetched image bytes into PDF bytes, and touches no platform channel. That
/// keeps the whole layout — headings, lists, checkboxes, quotes, code panels,
/// links, figures — unit-testable with no plugin, no network and no widget
/// tester. The UI edge (`ui/note_export.dart`) does the awaiting.
///
/// GLYPH COVERAGE. Roboto is a Latin face: its cmap carries 896 code points, so
/// `→ ← ↔ ⇒ ✓ ✗ ★ ☆ ▪ ▫ ☐ ☑ ✔ ✱ ♦ ♥` — all things people type into notes — had
/// no glyph and `pdf` drew a hollow box. PDF's base-14 Symbol and ZapfDingbats
/// were tried as `fontFallback` first and measured to rescue NONE of them (no
/// Unicode mapping the package can use). DejaVu Sans (5918 code points) is
/// vendored as the fallback instead and covers every one.
///
/// Remaining limit, measured not assumed: modern pictographic emoji beyond the
/// legacy Emoticons block (`🎉` U+1F389 and most of Supplemental Symbols) still
/// have no glyph — no monochrome face carries them, and a PDF cannot embed a
/// COLOR emoji font at all. `note_pdf_test.dart` pins what is covered.
///
/// The fallback is regular-weight only: a bold arrow renders in regular DejaVu.
/// That is deliberate — a second 700 KB face to bolden a rare symbol is a bad
/// trade, and the symbol reads correctly either way.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'note_blocks.dart';
import 'note_print_style.dart';

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
    required this.symbols,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  /// DejaVu Sans, consulted per glyph for anything Roboto lacks.
  final pw.Font symbols;

  pw.Font resolve({required bool bold, required bool italic}) => bold && italic
      ? boldItalic
      : bold
      ? this.bold
      : italic
      ? this.italic
      : regular;

  /// Every `TextStyle` this file builds goes through here — a face that is set
  /// without a fallback is the bug this list exists to prevent.
  List<pw.Font> get fallback => [symbols];
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

// Palette and metrics live in `note_print_style.dart`, shared with the Word
// writer (ADR-0048) — the two exports must draw the same page.
const _ink = PdfColor.fromInt(NotePrintPalette.ink);
const _muted = PdfColor.fromInt(NotePrintPalette.muted);
const _accent = PdfColor.fromInt(NotePrintPalette.accent);
const _rule = PdfColor.fromInt(NotePrintPalette.rule);
const _codeBg = PdfColor.fromInt(NotePrintPalette.codeBg);
const _success = PdfColor.fromInt(NotePrintPalette.success);
const _markBg = PdfColor.fromInt(NotePrintPalette.markBg);
const _tableRule = PdfColor.fromInt(NotePrintPalette.tableRule);

/// The edge colour of a GFM alert, by its kind (see
/// [NotePrintPalette.calloutEdge]).
PdfColor _calloutEdge(String? kind) =>
    PdfColor.fromInt(NotePrintPalette.calloutEdge(kind));

typedef _M = NotePrintMetrics;

const _bodySize = _M.body;

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
        marginLeft: _M.marginSideCm * PdfPageFormat.cm,
        marginRight: _M.marginSideCm * PdfPageFormat.cm,
        marginTop: _M.marginTopBottomCm * PdfPageFormat.cm,
        marginBottom: _M.marginTopBottomCm * PdfPageFormat.cm,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox.shrink()
          : pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(bottom: _M.headerGap),
              child: pw.Text(
                doc.title,
                style: pw.TextStyle(
                  fontFallback: fonts.fallback,
                  fontSize: _M.meta,
                  color: _muted,
                ),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: _M.headerGap),
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(fontSize: _M.meta, color: _muted),
        ),
      ),
      build: (context) => [
        // The title is the document's first block, Apple-Notes style — the same
        // rule the editor and the markdown export follow (feedback round 1).
        pw.Text(
          doc.title,
          style: pw.TextStyle(
            font: fonts.bold,
            fontFallback: fonts.fallback,
            fontSize: _M.title,
            color: _ink,
            letterSpacing: _M.titleLetterSpacing,
          ),
        ),
        if (doc.updatedLabel case final label?) ...[
          pw.SizedBox(height: _M.titleToLabel),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontFallback: fonts.fallback,
              fontSize: _M.meta,
              color: _muted,
            ),
          ),
        ],
        pw.SizedBox(height: _M.titleToRule),
        pw.Divider(color: _rule, thickness: _M.titleRuleWidth, height: 1),
        pw.SizedBox(height: _M.ruleToBody),
        for (final block in doc.blocks) _block(block, doc, fonts),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _block(NoteBlock block, NotePdfDocument doc, NotePdfFonts fonts) {
  pw.Widget padded(
    pw.Widget child, {
    double top = 0,
    double bottom = _M.blockAfter,
  }) => pw.Padding(
    padding: pw.EdgeInsets.only(top: top, bottom: bottom),
    child: child,
  );

  switch (block.kind) {
    case NoteBlockKind.heading1:
      return padded(
        _rich(block, fonts, size: _M.heading1, bold: true),
        top: _M.heading1Before,
      );
    case NoteBlockKind.heading2:
      return padded(
        _rich(block, fonts, size: _M.heading2, bold: true),
        top: _M.heading2Before,
      );
    case NoteBlockKind.heading3:
      return padded(
        _rich(block, fonts, size: _M.heading3, bold: true),
        top: _M.heading3Before,
      );

    // OPH-274: `indent` is markdown's gift — Delta's block attributes were
    // flat, so a nested list printed as a flat one and the structure was lost
    // between the screen and the page.
    case NoteBlockKind.bullet:
      return padded(
        _indented(block, _marker('•', _rich(block, fonts), fonts)),
        bottom: _M.listAfter,
      );
    case NoteBlockKind.ordered:
      return padded(
        _indented(
          block,
          _marker('${block.ordinal ?? 1}.', _rich(block, fonts), fonts),
        ),
        bottom: _M.listAfter,
      );

    // A drawn box, not a "☑"/"☐" character: those glyphs are not in Roboto, so
    // the text route would print blanks.
    case NoteBlockKind.checked:
    case NoteBlockKind.unchecked:
      return padded(
        _checkItem(block, fonts, done: block.kind == NoteBlockKind.checked),
        bottom: _M.listAfter,
      );

    // Round 19b (OPH-281). A GFM alert: tinted panel, coloured edge, localized
    // header. It used to print "unsupported block", which is the one thing an
    // alert must never become — its whole job is to be the paragraph nobody
    // gets to skip.
    case NoteBlockKind.callout:
      final edge = _calloutEdge(block.calloutKind);
      return padded(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
            horizontal: _M.calloutPaddingH,
            vertical: _M.calloutPaddingV,
          ),
          decoration: pw.BoxDecoration(
            // Pre-blended onto white, not `PdfColor(r, g, b, 0.08)`: the
            // `pdf` package drops a fill's alpha, so the panel printed as a
            // SOLID block of the edge colour with the text sunk into it
            // (caught by the DOCX comparison, ADR-0048).
            color: PdfColor.fromInt(
              NotePrintPalette.calloutTint(block.calloutKind),
            ),
            border: pw.Border(
              left: pw.BorderSide(color: edge, width: _M.calloutEdge),
            ),
          ),
          child: _rich(block, fonts),
        ),
        top: _M.calloutBefore,
      );

    // Front matter is the document's metadata, not its first paragraph — the
    // reading view gives it its own quiet strip, so the page does too.
    case NoteBlockKind.frontMatter:
      return padded(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(_M.panelPadding),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _rule, width: _M.hairline),
          ),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              font: fonts.regular,
              fontFallback: fonts.fallback,
              fontSize: _M.meta,
              color: _muted,
              lineSpacing: _M.codeLineGap,
            ),
          ),
        ),
        bottom: _M.frontMatterAfter,
      );

    case NoteBlockKind.quote:
      return padded(
        pw.Container(
          padding: const pw.EdgeInsets.only(left: _M.quotePadding),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: _rule, width: _M.quoteEdge),
            ),
          ),
          child: _rich(block, fonts, color: _muted, italic: true),
        ),
      );

    case NoteBlockKind.code:
      return padded(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(_M.panelPadding),
          decoration: const pw.BoxDecoration(color: _codeBg),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              font: fonts.regular,
              fontFallback: fonts.fallback,
              fontSize: _M.code,
              color: _ink,
              lineSpacing: _M.codeLineGap,
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
            constraints: const pw.BoxConstraints(maxHeight: _M.imageMaxHeight),
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
        ),
        top: _M.imageBefore,
        bottom: _M.mediaAfter,
      );

    // Round 19 #1 (ADR-0034). The bytes are made by the exporter's off-screen
    // rasterizer, not fetched — but they arrive through the same `images` map,
    // so this file still knows nothing about widgets or platform channels.
    case NoteBlockKind.figure:
      final drawn = doc.images[block.source];
      if (drawn != null) {
        return padded(
          pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(
                maxHeight: _M.figureMaxHeight,
              ),
              child: pw.Image(pw.MemoryImage(drawn), fit: pw.BoxFit.contain),
            ),
          ),
          top: _M.figureBefore,
          bottom: _M.mediaAfter,
        );
      }
      // No picture: print the SOURCE, not an apology. A reader holding a
      // diagram's mermaid has strictly more than one holding "unsupported".
      return padded(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(_M.panelPadding),
          decoration: const pw.BoxDecoration(color: _codeBg),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              font: fonts.regular,
              fontFallback: fonts.fallback,
              fontSize: _M.code,
              color: _muted,
              lineSpacing: _M.codeLineGap,
            ),
          ),
        ),
      );

    case NoteBlockKind.attachment:
      return padded(_missingMedia(block, doc, fonts));

    // Neither of these existed before markdown became canonical: Delta had no
    // rule node and `flutter_quill` 11.5.1 has no table node at all, so a
    // table in a note simply could not reach a PDF.
    case NoteBlockKind.divider:
      return padded(
        pw.Divider(height: 1, thickness: _M.dividerWidth, color: _tableRule),
        top: _M.dividerBefore,
      );

    case NoteBlockKind.table:
      return padded(_table(block, fonts), top: _M.tableBefore);

    case NoteBlockKind.paragraph:
      // An intentional blank line keeps its air; it just must not be a full
      // paragraph's worth.
      if (block.text.trim().isEmpty) return pw.SizedBox(height: _M.blankLine);
      return padded(_rich(block, fonts));
  }
}

/// Shifts a list item by its nesting depth. Capped so a pathological document
/// cannot indent itself off the right edge of the page.
pw.Widget _indented(NoteBlock block, pw.Widget child) => block.indent <= 0
    ? child
    : pw.Padding(
        padding: pw.EdgeInsets.only(
          left: block.indent.clamp(0, _M.maxIndentLevel) * _M.indentPerLevel,
        ),
        child: child,
      );

/// A GFM table. The first row is the header, and cells print as plain text:
/// inline formatting inside a cell is rare and a full rich cell would need the
/// span model to nest, which is not worth it for the page.
pw.Widget _table(NoteBlock block, NotePdfFonts fonts) {
  final rows = block.rows ?? const <List<String>>[];
  if (rows.isEmpty) return pw.SizedBox();
  return pw.Table(
    border: pw.TableBorder.all(color: _tableRule, width: _M.tableBorder),
    children: [
      for (final (index, row) in rows.indexed)
        pw.TableRow(
          children: [
            for (final cell in row)
              pw.Padding(
                padding: const pw.EdgeInsets.all(_M.tableCellPadding),
                child: pw.Text(
                  cell,
                  style: pw.TextStyle(
                    font: index == 0 ? fonts.bold : fonts.regular,
                    fontSize: _M.table,
                  ),
                ),
              ),
          ],
        ),
    ],
  );
}

pw.Widget _marker(String marker, pw.Widget child, NotePdfFonts fonts) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(
      width: _M.markerWidth,
      child: pw.Text(
        marker,
        style: pw.TextStyle(
          font: fonts.regular,
          fontFallback: fonts.fallback,
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
      ..setStrokeColor(_success)
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

/// A checklist item, drawn the way the READING VIEW draws it (round 19b,
/// OPH-281).
///
/// It used to grey the text and strike it through, citing DESIGN §20 — but §20
/// is about the TASK ROW in the app, and a checklist inside a note body is a
/// different object whose renderer is §29's reading view. So the page was
/// applying one surface's rule to another surface's content, and the result was
/// a PDF that visibly disagreed with the screen it was exported from: green
/// outlined tick and ordinary text there, blue filled box and struck-through
/// grey here.
///
/// The reading view wins, because it is the thing the reader was looking at
/// when they pressed Export. Green outlined box, tick inside, text untouched.
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
        border: pw.Border.all(color: done ? _success : _muted, width: 1),
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
    pw.Expanded(child: _rich(block, fonts)),
  ],
);

pw.Widget _missingMedia(
  NoteBlock block,
  NotePdfDocument doc,
  NotePdfFonts fonts,
) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.symmetric(
    horizontal: _M.placeholderPaddingH,
    vertical: _M.placeholderPaddingV,
  ),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _rule, width: _M.hairline),
  ),
  child: pw.Text(
    doc.mediaPlaceholderLabel ?? block.source ?? '',
    style: pw.TextStyle(
      font: fonts.italic,
      fontFallback: fonts.fallback,
      fontSize: _M.meta,
      color: _muted,
    ),
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
              fontFallback: fonts.fallback,
              fontSize: span.superscript
                  ? size * 0.75
                  : (span.code ? size - 0.5 : size),
              color: span.link != null ? _accent : color,
              lineSpacing: _M.bodyLineGap,
              // `==highlight==` (round 19b): a tint behind the ink, never a
              // change to the ink itself — the same rule the screen follows, so
              // the text keeps its contrast in both places.
              background: span.mark
                  ? const pw.BoxDecoration(color: _markBg)
                  : (span.code ? const pw.BoxDecoration(color: _codeBg) : null),
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
