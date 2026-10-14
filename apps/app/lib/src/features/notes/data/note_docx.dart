/// Note → Word (.docx), our own OOXML writer (ADR-0048).
///
/// The sibling of `note_pdf.dart` and deliberately shaped like it: it turns the
/// SAME [NoteBlock]s plus the SAME already-fetched picture bytes into a file,
/// touches no platform channel and no widget, and so is unit-testable in a
/// plain `flutter test`. The UI edge (`ui/note_export.dart`) does the awaiting
/// and feeds both writers from one pipeline.
///
/// FIDELITY. The page must look like the PDF of the same note. Every colour,
/// size, margin, indent and spacing is read from `note_print_style.dart`, the
/// file the PDF writer reads too, and converted to Word's units here:
///
///   * twips (1/20 pt) — page, margins, indents, paragraph spacing;
///   * half-points — font sizes;
///   * eighths of a point — border widths;
///   * EMUs (12 700 per pt) — picture extents.
///
/// What Word cannot express the PDF way is approximated as closely as it can:
/// panel padding is a border drawn in the panel's own colour, the checkbox is
/// the ☐ / ☑ glyph in the colours of the PDF's drawn box, and a line's leading
/// is an "at least" height of the PDF's line (font height + the same gap).
///
/// VALIDITY. Word refuses a file whose element order deviates from the schema
/// (it calls it "unreadable content"), so every property block below is written
/// in the order ECMA-376 lists its children — keep it that way when editing.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'note_blocks.dart';
import 'note_print_style.dart';

/// Everything the Word document needs besides the body — the same inputs as
/// `NotePdfDocument`, so one export pipeline can feed both writers.
class NoteDocxDocument {
  const NoteDocxDocument({
    required this.title,
    required this.blocks,
    this.updatedLabel,
    this.images = const {},
    this.mediaPlaceholderLabel,
  });

  final String title;
  final List<NoteBlock> blocks;

  /// Already-localised "last updated" line, or null to omit it.
  final String? updatedLabel;

  /// Embed source (or figure raster key) → picture bytes. Anything missing or
  /// undecodable prints the PDF's honest placeholder instead.
  final Map<String, Uint8List> images;

  /// Already-localised caption for that placeholder; null falls back to the
  /// source so nothing ever renders blank.
  final String? mediaPlaceholderLabel;
}

/// The MIME type of what [buildNoteDocx] returns.
const docxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Builds the .docx (a zip of OOXML parts).
Uint8List buildNoteDocx(NoteDocxDocument doc, {DateTime? modified}) =>
    _DocxWriter(doc).build(modified ?? DateTime.now());

// ── Units ────────────────────────────────────────────────────────────────────

typedef _M = NotePrintMetrics;
typedef _C = NotePrintPalette;

/// Points → twips.
int _tw(double pt) => (pt * 20).round();

/// Points → half-points (`w:sz`).
int _hp(double pt) => (pt * 2).round();

/// Points → eighths of a point (`w:bdr/@w:sz`), inside Word's legal 2..96.
int _bdr(double pt) => (pt * 8).round().clamp(2, 96);

/// Points → EMUs.
int _emu(double pt) => (pt * 12700).round();

/// The PDF's line height for [size] with [gap] of extra leading, in twips.
///
/// The `pdf` package lays text out at the face's hhea height (Roboto:
/// (1900 + 500) / 2048 ≈ 1.17 em) plus `lineSpacing`. Written as an "at least"
/// rule it holds whichever face Word ends up using.
int _line(double size, double gap) => _tw(size * 1.17 + gap);

String _hex(int argb) => _C.hex(argb);

/// The body face. Roboto is what the PDF embeds; a machine without it gets
/// Arial, which `fontTable.xml` names as Roboto's substitute.
const _font = 'Roboto';

/// The face for ☐ / ☑ — Roboto has neither glyph (see `note_pdf.dart`).
const _symbolFont = 'Segoe UI Symbol';

// ── XML text ─────────────────────────────────────────────────────────────────

/// Characters XML 1.0 forbids outright — a stray one makes the whole file
/// unreadable, so they are dropped rather than escaped.
final _illegalXml = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]');

String _esc(String text) => text
    .replaceAll(_illegalXml, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

const _nsW = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _nsR =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _relBase =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// The namespaces a story part (body, header, footer) may use.
const _storyNs =
    'xmlns:w="$_nsW" xmlns:r="$_nsR" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

// ── Building blocks ──────────────────────────────────────────────────────────

/// One side of a paragraph border.
class _Edge {
  const _Edge(this.width, this.color, {this.space = 0});

  /// Points.
  final double width;
  final int color;

  /// Points between the text and the line (Word caps it at 31).
  final double space;

  String xml(String side) =>
      '<w:$side w:val="single" w:sz="${_bdr(width)}" '
      'w:space="${space.round().clamp(0, 31)}" w:color="${_hex(color)}"/>';
}

/// Paragraph properties, written in schema order.
class _PPr {
  const _PPr({
    this.style,
    this.keepNext = false,
    this.numId,
    this.ilvl,
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.fill,
    this.before = 0,
    this.after = 0,
    this.gap = 0,
    this.line,
    this.exactLine = false,
    this.indLeft,
    this.indRight,
    this.hanging,
    this.center = false,
    this.alignRight = false,
    this.markSize,
  });

  final String? style;
  final bool keepNext;
  final int? numId;
  final int? ilvl;
  final _Edge? top, left, bottom, right;
  final int? fill;

  /// Points.
  final double before, after;

  /// The extra leading [line] carries, in points. The PDF adds it BETWEEN
  /// lines only; Word adds it to every line, the first included — so it is
  /// taken back off the space after, and an n-line paragraph is exactly as
  /// tall as on the page.
  final double gap;

  /// Twips; null keeps the default single line.
  final int? line;
  final bool exactLine;

  /// Points.
  final double? indLeft, indRight, hanging;
  final bool center;
  final bool alignRight;

  /// The paragraph mark's own size — what an EMPTY paragraph is as tall as.
  final double? markSize;

  String xml() {
    final b = StringBuffer('<w:pPr>');
    if (style != null) b.write('<w:pStyle w:val="$style"/>');
    if (keepNext) b.write('<w:keepNext/>');
    if (numId != null) {
      b.write(
        '<w:numPr><w:ilvl w:val="${ilvl ?? 0}"/>'
        '<w:numId w:val="$numId"/></w:numPr>',
      );
    }
    if (top != null || left != null || bottom != null || right != null) {
      b.write('<w:pBdr>');
      if (top case final e?) b.write(e.xml('top'));
      if (left case final e?) b.write(e.xml('left'));
      if (bottom case final e?) b.write(e.xml('bottom'));
      if (right case final e?) b.write(e.xml('right'));
      b.write('</w:pBdr>');
    }
    if (fill case final f?) {
      b.write('<w:shd w:val="clear" w:color="auto" w:fill="${_hex(f)}"/>');
    }
    final tail = after > gap ? after - gap : 0.0;
    b.write('<w:spacing w:before="${_tw(before)}" w:after="${_tw(tail)}"');
    if (line case final l?) {
      b.write(' w:line="$l" w:lineRule="${exactLine ? 'exact' : 'atLeast'}"');
    }
    b.write('/>');
    if (indLeft != null || indRight != null || hanging != null) {
      b.write('<w:ind');
      if (indLeft case final v?) b.write(' w:left="${_tw(v)}"');
      if (indRight case final v?) b.write(' w:right="${_tw(v)}"');
      if (hanging case final v?) b.write(' w:hanging="${_tw(v)}"');
      b.write('/>');
    }
    if (center) b.write('<w:jc w:val="center"/>');
    if (alignRight) b.write('<w:jc w:val="right"/>');
    if (markSize case final s?) {
      b.write(
        '<w:rPr><w:sz w:val="${_hp(s)}"/><w:szCs w:val="${_hp(s)}"/></w:rPr>',
      );
    }
    b.write('</w:pPr>');
    return b.toString();
  }
}

/// Run properties, written in schema order.
class _RPr {
  const _RPr({
    this.font,
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.color = _C.ink,
    this.letterSpacing,
    required this.size,
    this.underline = false,
    this.fill,
    this.superscript = false,
    this.noProof = false,
  });

  final String? font;
  final bool bold, italic, strike, underline, superscript, noProof;
  final int color;

  /// Points.
  final double? letterSpacing;
  final double size;
  final int? fill;

  String xml() {
    final b = StringBuffer('<w:rPr>');
    if (font case final f?) {
      b.write(
        '<w:rFonts w:ascii="$f" w:hAnsi="$f" w:eastAsia="$f" w:cs="$f"/>',
      );
    }
    if (bold) b.write('<w:b/><w:bCs/>');
    if (italic) b.write('<w:i/><w:iCs/>');
    if (strike) b.write('<w:strike/>');
    if (noProof) b.write('<w:noProof/>');
    b.write('<w:color w:val="${_hex(color)}"/>');
    if (letterSpacing case final s?) b.write('<w:spacing w:val="${_tw(s)}"/>');
    b.write('<w:sz w:val="${_hp(size)}"/><w:szCs w:val="${_hp(size)}"/>');
    if (underline) b.write('<w:u w:val="single"/>');
    if (fill case final f?) {
      b.write('<w:shd w:val="clear" w:color="auto" w:fill="${_hex(f)}"/>');
    }
    if (superscript) b.write('<w:vertAlign w:val="superscript"/>');
    b.write('</w:rPr>');
    return b.toString();
  }
}

/// A run of [text]: `\n` becomes a line break and `\t` a tab, so a code block
/// or an alert stays ONE paragraph (one panel) the way it is one box in the
/// PDF.
String _run(String text, _RPr rPr) {
  if (text.isEmpty) return '';
  final b = StringBuffer('<w:r>')..write(rPr.xml());
  // A CRLF note (pasted from Windows) must break once, not leave a raw CR in
  // the text, which an XML reader turns into a stray line feed inside `w:t`.
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  for (final (i, line) in lines.indexed) {
    if (i > 0) b.write('<w:br/>');
    final cells = line.split('\t');
    for (final (j, cell) in cells.indexed) {
      if (j > 0) b.write('<w:tab/>');
      if (cell.isNotEmpty) {
        b.write('<w:t xml:space="preserve">${_esc(cell)}</w:t>');
      }
    }
  }
  b.write('</w:r>');
  return b.toString();
}

String _paragraph(_PPr pPr, [String runs = '']) =>
    '<w:p>${pPr.xml()}$runs</w:p>';

/// An empty paragraph exactly [height] points tall — vertical air where Word
/// has no other way to put it (around a table, an empty line).
String _spacer(double height) =>
    _paragraph(_PPr(line: _tw(height), exactLine: true, markSize: 1));

/// A picture's size, read from its header.
class _Picture {
  const _Picture(this.bytes, this.extension, this.width, this.height);

  final Uint8List bytes;
  final String extension; // 'png' | 'jpeg'
  final int width;
  final int height;
}

/// PNG and JPEG go in as they are; anything else Word cannot be relied on to
/// show (WebP, GIF, BMP…) is re-encoded as PNG. Null when the bytes are not a
/// picture at all — the caller prints the placeholder.
_Picture? _picture(Uint8List bytes) {
  if (_pngSize(bytes) case (final w, final h)) {
    return _Picture(bytes, 'png', w, h);
  }
  if (_jpegSize(bytes) case (final w, final h)) {
    return _Picture(bytes, 'jpeg', w, h);
  }
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    return _Picture(
      img.encodePng(decoded),
      'png',
      decoded.width,
      decoded.height,
    );
  } on Object {
    return null;
  }
}

(int, int)? _pngSize(Uint8List b) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 24) return null;
  for (var i = 0; i < sig.length; i++) {
    if (b[i] != sig[i]) return null;
  }
  final data = ByteData.sublistView(b);
  final w = data.getUint32(16);
  final h = data.getUint32(20);
  return w > 0 && h > 0 ? (w, h) : null;
}

(int, int)? _jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i += 1; // fill byte
      continue;
    }
    // Standalone markers carry no length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      i += 2;
      continue;
    }
    final length = (b[i + 2] << 8) | b[i + 3];
    final isFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      if (i + 8 >= b.length) return null;
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return w > 0 && h > 0 ? (w, h) : null;
    }
    i += 2 + length;
  }
  return null;
}

class _Rel {
  const _Rel(this.id, this.type, this.target, {this.external = false});

  final String id;
  final String type;
  final String target;
  final bool external;

  String xml() =>
      '<Relationship Id="$id" Type="$_relBase/$type" Target="${_esc(target)}"'
      '${external ? ' TargetMode="External"' : ''}/>';
}

// ── The writer ───────────────────────────────────────────────────────────────

class _DocxWriter {
  _DocxWriter(this.doc);

  final NoteDocxDocument doc;

  final _rels = <_Rel>[];
  final _media = <String, Uint8List>{}; // part name → bytes
  final _mediaRelBySource = <String, (String, _Picture)>{};
  final _hyperlinkRels = <String, String>{};

  /// `wp:docPr/@id` must be unique across the document.
  var _drawingId = 0;

  /// Bullet lists share one numbering; every ordered run gets its OWN abstract
  /// definition, so Word cannot carry a counter from one list into the next.
  static const _bulletNumId = 1;
  final _orderedAbstracts = <int>[]; // start values, index = abstract id - 1
  final _orderedNumAtDepth = <int, int>{};

  String _addRel(String type, String target, {bool external = false}) {
    final id = 'rId${_rels.length + 1}';
    _rels.add(_Rel(id, type, target, external: external));
    return id;
  }

  Uint8List build(DateTime modified) {
    _addRel('styles', 'styles.xml');
    _addRel('numbering', 'numbering.xml');
    _addRel('settings', 'settings.xml');
    _addRel('fontTable', 'fontTable.xml');
    final headerId = _addRel('header', 'header1.xml');
    final firstHeaderId = _addRel('header', 'header2.xml');
    final footerId = _addRel('footer', 'footer1.xml');
    final firstFooterId = _addRel('footer', 'footer2.xml');

    final body = StringBuffer()..write(_titleBlock());
    for (final block in doc.blocks) {
      body.write(_block(block));
    }

    final document =
        '$_xmlHeader<w:document $_storyNs><w:body>$body'
        '<w:sectPr>'
        '<w:headerReference w:type="default" r:id="$headerId"/>'
        '<w:headerReference w:type="first" r:id="$firstHeaderId"/>'
        '<w:footerReference w:type="default" r:id="$footerId"/>'
        '<w:footerReference w:type="first" r:id="$firstFooterId"/>'
        '<w:pgSz w:w="${_tw(_M.pageWidthCm * _M.pointsPerCm)}" '
        'w:h="${_tw(_M.pageHeightCm * _M.pointsPerCm)}"/>'
        '<w:pgMar w:top="${_tw(_M.marginTopBottomCm * _M.pointsPerCm)}" '
        'w:right="${_tw(_M.marginSideCm * _M.pointsPerCm)}" '
        'w:bottom="${_tw(_M.marginTopBottomCm * _M.pointsPerCm)}" '
        'w:left="${_tw(_M.marginSideCm * _M.pointsPerCm)}" '
        // The running header/footer start where the PDF's do: on the margin.
        'w:header="${_tw(_M.marginTopBottomCm * _M.pointsPerCm)}" '
        'w:footer="${_tw(_M.marginTopBottomCm * _M.pointsPerCm)}" '
        'w:gutter="0"/>'
        // Page 1 carries the title itself, so its header is empty (PDF:
        // `context.pageNumber == 1 ? SizedBox.shrink()`).
        '<w:titlePg/>'
        '</w:sectPr></w:body></w:document>';

    final parts = <String, List<int>>{
      '[Content_Types].xml': utf8.encode(_contentTypes()),
      '_rels/.rels': utf8.encode(_packageRels),
      'docProps/core.xml': utf8.encode(_coreProps()),
      'docProps/app.xml': utf8.encode(_appProps),
      'word/document.xml': utf8.encode(document),
      'word/styles.xml': utf8.encode(_styles),
      'word/numbering.xml': utf8.encode(_numbering()),
      'word/settings.xml': utf8.encode(_settings),
      'word/fontTable.xml': utf8.encode(_fontTable),
      'word/header1.xml': utf8.encode(_header()),
      'word/header2.xml': utf8.encode(_emptyStory('hdr')),
      'word/footer1.xml': utf8.encode(_footer()),
      // Same footer on page 1 — the PDF numbers every page.
      'word/footer2.xml': utf8.encode(_footer()),
      'word/_rels/document.xml.rels': utf8.encode(_documentRels()),
      for (final entry in _media.entries) 'word/${entry.key}': entry.value,
    };

    final archive = Archive();
    for (final entry in parts.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    return ZipEncoder().encodeBytes(archive, modified: modified);
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  /// The title, the optional "edited" line, and the hairline under them —
  /// drawn as the last paragraph's bottom border, 10 pt below the text and
  /// 14 pt above the body, like the PDF's `SizedBox` + `Divider` + `SizedBox`.
  String _titleBlock() {
    final label = doc.updatedLabel;
    const ruleEdge = _Edge(_M.titleRuleWidth, _C.rule, space: _M.titleToRule);
    final title = _paragraph(
      _PPr(
        style: 'Title',
        line: _line(_M.title, 0),
        after: label == null ? _M.ruleToBody : _M.titleToLabel,
        bottom: label == null ? ruleEdge : null,
      ),
      _run(
        doc.title,
        const _RPr(
          bold: true,
          size: _M.title,
          letterSpacing: _M.titleLetterSpacing,
        ),
      ),
    );
    if (label == null) return title;
    return title +
        _paragraph(
          _PPr(line: _line(_M.meta, 0), after: _M.ruleToBody, bottom: ruleEdge),
          _run(label, const _RPr(size: _M.meta, color: _C.muted)),
        );
  }

  String _block(NoteBlock block) {
    switch (block.kind) {
      case NoteBlockKind.heading1:
        return _heading(block, 1, _M.heading1, _M.heading1Before);
      case NoteBlockKind.heading2:
        return _heading(block, 2, _M.heading2, _M.heading2Before);
      case NoteBlockKind.heading3:
        return _heading(block, 3, _M.heading3, _M.heading3Before);

      case NoteBlockKind.bullet:
        return _paragraph(
          _PPr(
            numId: _bulletNumId,
            ilvl: _level(block),
            after: _M.listAfter,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
          ),
          _rich(block),
        );
      case NoteBlockKind.ordered:
        return _paragraph(
          _PPr(
            numId: _orderedNum(block),
            ilvl: _level(block),
            after: _M.listAfter,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
          ),
          _rich(block),
        );

      // The PDF draws an outlined box (muted when open, green with a green
      // tick when done) beside ordinary text; ☐ / ☑ in those colours is the
      // closest a word processor can type. Like the PDF, a checklist item is
      // not indented by its nesting depth.
      case NoteBlockKind.checked:
      case NoteBlockKind.unchecked:
        final done = block.kind == NoteBlockKind.checked;
        return _paragraph(
          _PPr(
            after: _M.listAfter,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
            indLeft: _M.markerWidth,
            hanging: _M.markerWidth,
          ),
          '${_run(done ? '\u2611' : '\u2610', _RPr(font: _symbolFont, size: _M.body, color: done ? _C.success : _C.muted))}'
          '<w:r><w:tab/></w:r>${_rich(block)}',
        );

      case NoteBlockKind.callout:
        final edge = _C.calloutEdge(block.calloutKind);
        final tint = _C.calloutTint(block.calloutKind);
        return _paragraph(
          _PPr(
            top: _Edge(0.5, tint, space: _M.calloutPaddingV),
            left: _Edge(_M.calloutEdge, edge, space: _M.calloutPaddingH),
            bottom: _Edge(0.5, tint, space: _M.calloutPaddingV),
            right: _Edge(0.5, tint, space: _M.calloutPaddingH),
            fill: tint,
            before: _M.calloutBefore + _M.calloutPaddingV,
            after: _M.blockAfter + _M.calloutPaddingV,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
            indLeft: _M.calloutPaddingH + _M.calloutEdge,
            indRight: _M.calloutPaddingH + 0.5,
          ),
          _rich(block),
        );

      case NoteBlockKind.frontMatter:
        return _panel(
          block.text,
          border: const _Edge(_M.hairline, _C.rule, space: _M.panelPadding),
          size: _M.meta,
          color: _C.muted,
          after: _M.frontMatterAfter,
        );

      case NoteBlockKind.quote:
        return _paragraph(
          _PPr(
            left: const _Edge(_M.quoteEdge, _C.rule, space: _M.quotePadding),
            after: _M.blockAfter,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
            indLeft: _M.quotePadding + _M.quoteEdge,
          ),
          _rich(block, color: _C.muted, italic: true),
        );

      case NoteBlockKind.code:
        return _panel(
          block.text,
          fill: _C.codeBg,
          size: _M.code,
          color: _C.ink,
          after: _M.blockAfter,
        );

      case NoteBlockKind.image:
        return _picturePara(
          block,
          maxHeight: _M.imageMaxHeight,
          before: _M.imageBefore,
        );

      case NoteBlockKind.figure:
        final drawn = _picturePara(
          block,
          maxHeight: _M.figureMaxHeight,
          before: _M.figureBefore,
          placeholder: false,
        );
        if (drawn.isNotEmpty) return drawn;
        // No picture: print the SOURCE, as the PDF does.
        return _panel(
          block.text,
          fill: _C.codeBg,
          size: _M.code,
          color: _C.muted,
          after: _M.blockAfter,
        );

      case NoteBlockKind.attachment:
        return _placeholder(block);

      case NoteBlockKind.divider:
        return _paragraph(
          _PPr(
            bottom: const _Edge(_M.dividerWidth, _C.tableRule),
            before: _M.dividerBefore,
            after: _M.blockAfter,
            line: _tw(_M.dividerWidth),
            exactLine: true,
            markSize: 1,
          ),
        );

      case NoteBlockKind.table:
        return _table(block);

      case NoteBlockKind.paragraph:
        if (block.text.trim().isEmpty) return _spacer(_M.blankLine);
        return _paragraph(
          _PPr(
            after: _M.blockAfter,
            line: _line(_M.body, _M.bodyLineGap),
            gap: _M.bodyLineGap,
          ),
          _rich(block),
        );
    }
  }

  String _heading(NoteBlock block, int level, double size, double before) =>
      _paragraph(
        _PPr(
          style: 'Heading$level',
          keepNext: true,
          before: before,
          after: _M.blockAfter,
          line: _line(size, _M.bodyLineGap),
          gap: _M.bodyLineGap,
        ),
        _rich(block, size: size, bold: true),
      );

  int _level(NoteBlock block) => block.indent.clamp(0, 8);

  /// The numbering instance for an ordered item: a new one wherever a run
  /// begins at this depth, so every list counts from its own first item.
  int _orderedNum(NoteBlock block) {
    final depth = _level(block);
    final current = _orderedNumAtDepth[depth];
    if (current != null && (block.ordinal ?? 1) != 1) return current;
    _orderedAbstracts.add(block.ordinal ?? 1);
    // Abstract 0 / num 1 is the bullet list; ordered runs follow it.
    final numId = _orderedAbstracts.length + 1;
    _orderedNumAtDepth[depth] = numId;
    return numId;
  }

  /// A shaded or outlined box around ONE paragraph of preformatted text —
  /// code, a figure's source, front matter. The padding is a border in the
  /// panel's own colour, which Word draws inside the shading.
  String _panel(
    String text, {
    int? fill,
    _Edge? border,
    required double size,
    required int color,
    required double after,
  }) {
    final edge = border ?? _Edge(0.5, fill!, space: _M.panelPadding);
    // A fence's body ends in a newline the PDF does not print as a line.
    final body = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    final inset = _M.panelPadding + edge.width;
    return _paragraph(
      _PPr(
        top: edge,
        left: edge,
        bottom: edge,
        right: edge,
        fill: fill,
        before: _M.panelPadding,
        after: after + _M.panelPadding,
        line: _line(size, _M.codeLineGap),
        gap: _M.codeLineGap,
        indLeft: inset,
        indRight: inset,
      ),
      _run(body, _RPr(size: size, color: color, noProof: true)),
    );
  }

  /// The PDF's "media unavailable" box: a hairline outline and a quiet italic
  /// caption.
  String _placeholder(NoteBlock block) => _paragraph(
    _PPr(
      top: const _Edge(_M.hairline, _C.rule, space: _M.placeholderPaddingV),
      left: const _Edge(_M.hairline, _C.rule, space: _M.placeholderPaddingH),
      bottom: const _Edge(_M.hairline, _C.rule, space: _M.placeholderPaddingV),
      right: const _Edge(_M.hairline, _C.rule, space: _M.placeholderPaddingH),
      before: _M.placeholderPaddingV,
      after: _M.blockAfter + _M.placeholderPaddingV,
      line: _line(_M.meta, 0),
      indLeft: _M.placeholderPaddingH + _M.hairline,
      indRight: _M.placeholderPaddingH + _M.hairline,
    ),
    _run(
      doc.mediaPlaceholderLabel ?? block.source ?? '',
      const _RPr(size: _M.meta, color: _C.muted, italic: true),
    ),
  );

  /// A picture, centred and fitted inside the content width × [maxHeight]
  /// with its ratio kept — exactly the PDF's `ConstrainedBox(maxHeight)` +
  /// `BoxFit.contain`, which scales a small picture UP as well as a large one
  /// down. Missing or undecodable bytes print the placeholder (or, with
  /// [placeholder] false, nothing, so the caller can print a fallback).
  String _picturePara(
    NoteBlock block, {
    required double maxHeight,
    required double before,
    bool placeholder = true,
  }) {
    final source = block.source;
    final bytes = source == null ? null : doc.images[source];
    final embedded = bytes == null ? null : _embed(source!, bytes);
    if (embedded == null) return placeholder ? _placeholder(block) : '';
    final (relId, picture) = embedded;

    final scale = [
      _M.contentWidth / picture.width,
      maxHeight / picture.height,
    ].reduce((a, b) => a < b ? a : b);
    final cx = _emu(picture.width * scale);
    final cy = _emu(picture.height * scale);
    final id = ++_drawingId;
    final alt = _esc(block.text);

    final drawing =
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="$id" name="Picture $id" descr="$alt"/>'
        '<wp:cNvGraphicFramePr>'
        '<a:graphicFrameLocks noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData '
        'uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="Picture $id"/>'
        '<pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relId"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/>'
        '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic>'
        '</wp:inline></w:drawing></w:r>';

    return _paragraph(
      _PPr(before: before, after: _M.mediaAfter, center: true),
      drawing,
    );
  }

  /// Adds the picture to the package once per source and returns its rel.
  (String, _Picture)? _embed(String source, Uint8List bytes) {
    if (_mediaRelBySource[source] case final known?) return known;
    final picture = _picture(bytes);
    if (picture == null) return null;
    final name = 'media/image${_media.length + 1}.${picture.extension}';
    _media[name] = picture.bytes;
    final rel = (_addRel('image', name), picture);
    _mediaRelBySource[source] = rel;
    return rel;
  }

  /// A GFM table: a full-width grid of 0.5 pt rules, 4 pt cell padding, 10 pt
  /// text, the first row bold and repeated at the top of every page it spans.
  String _table(NoteBlock block) {
    final rows = block.rows ?? const <List<String>>[];
    if (rows.isEmpty) return '';
    final columns = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (columns == 0) return '';
    // `pw.Table`'s default is intrinsic widths stretched to the page, so a
    // column of short labels stays narrow. Word fits columns from the grid, so
    // the grid is weighted the same way: the widest cell's estimated text width
    // (an average glyph is ~0.55 em) plus the cell padding.
    final weights = [
      for (var c = 0; c < columns; c++)
        rows
                    .map((r) => c < r.length ? r[c].length : 0)
                    .fold(1, (a, b) => a > b ? a : b) *
                _M.table *
                0.55 +
            2 * _M.tableCellPadding,
    ];
    final total = weights.fold(0.0, (a, b) => a + b);
    final widths = [
      for (final w in weights) (_tw(_M.contentWidth) * w / total).floor(),
    ];
    const rule = _M.tableBorder;
    String edge(String side) =>
        '<w:$side w:val="single" w:sz="${_bdr(rule)}" w:space="0" '
        'w:color="${_hex(_C.tableRule)}"/>';

    final b = StringBuffer()
      ..write(_spacer(_M.tableBefore))
      ..write('<w:tbl><w:tblPr>')
      ..write('<w:tblW w:w="5000" w:type="pct"/>')
      ..write('<w:tblBorders>')
      ..write(edge('top'))
      ..write(edge('left'))
      ..write(edge('bottom'))
      ..write(edge('right'))
      ..write(edge('insideH'))
      ..write(edge('insideV'))
      ..write('</w:tblBorders>')
      ..write('<w:tblLayout w:type="autofit"/>')
      ..write('<w:tblCellMar>')
      ..write('<w:top w:w="${_tw(_M.tableCellPadding)}" w:type="dxa"/>')
      ..write('<w:left w:w="${_tw(_M.tableCellPadding)}" w:type="dxa"/>')
      ..write('<w:bottom w:w="${_tw(_M.tableCellPadding)}" w:type="dxa"/>')
      ..write('<w:right w:w="${_tw(_M.tableCellPadding)}" w:type="dxa"/>')
      ..write('</w:tblCellMar>')
      ..write(
        '<w:tblLook w:val="0020" w:firstRow="1" w:lastRow="0" '
        'w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/>',
      )
      ..write('</w:tblPr><w:tblGrid>');
    for (var c = 0; c < columns; c++) {
      b.write('<w:gridCol w:w="${widths[c]}"/>');
    }
    b.write('</w:tblGrid>');
    for (final (index, row) in rows.indexed) {
      final header = index == 0;
      b.write('<w:tr>');
      if (header) b.write('<w:trPr><w:tblHeader/></w:trPr>');
      for (var c = 0; c < columns; c++) {
        final cell = c < row.length ? row[c] : '';
        b
          ..write('<w:tc><w:tcPr><w:tcW w:w="${widths[c]}" w:type="dxa"/>')
          ..write('</w:tcPr>')
          ..write(
            _paragraph(
              _PPr(line: _line(_M.table, 0)),
              _run(cell, _RPr(size: _M.table, bold: header)),
            ),
          )
          ..write('</w:tc>');
      }
      b.write('</w:tr>');
    }
    b
      ..write('</w:tbl>')
      ..write(_spacer(_M.blockAfter));
    return b.toString();
  }

  /// A block's inline runs, as the PDF's `_rich` styles them: links in the
  /// accent colour and underlined (and clickable), `==mark==` on its tint,
  /// inline code on the code tint at half a point smaller.
  String _rich(
    NoteBlock block, {
    double size = _M.body,
    bool bold = false,
    bool italic = false,
    int color = _C.ink,
  }) {
    final b = StringBuffer();
    String? openLink;

    void closeLink() {
      if (openLink != null) b.write('</w:hyperlink>');
      openLink = null;
    }

    for (final span in block.spans) {
      final target = _linkTarget(span.link);
      if (target != openLink) {
        closeLink();
        if (target != null) {
          b.write(
            '<w:hyperlink r:id="${_hyperlinkRel(target)}" w:history="1">',
          );
          openLink = target;
        }
      }
      b.write(
        _run(
          span.text,
          _RPr(
            bold: bold || span.bold,
            italic: italic || span.italic,
            strike: span.strike,
            color: span.link != null ? _C.accent : color,
            size: span.code ? size - 0.5 : size,
            underline: span.link != null,
            fill: span.mark ? _C.markBg : (span.code ? _C.codeBg : null),
            superscript: span.superscript,
          ),
        ),
      );
    }
    closeLink();
    return b.toString();
  }

  /// A link Word can open, or null. An in-page anchor (`#fn-1`, a footnote
  /// reference) has no bookmark to land on, and a target that is not a
  /// well-formed absolute URI makes Word reject the whole file — both stay
  /// styled as links but are not made clickable.
  String? _linkTarget(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || uri.scheme.isEmpty) return null;
    return uri.toString();
  }

  String _hyperlinkRel(String target) => _hyperlinkRels.putIfAbsent(
    target,
    () => _addRel('hyperlink', target, external: true),
  );

  // ── Parts ─────────────────────────────────────────────────────────────────

  String _contentTypes() {
    const wml =
        'application/vnd.openxmlformats-officedocument.wordprocessingml';
    String override(String part, String type) =>
        '<Override PartName="$part" ContentType="$type"/>';
    return '$_xmlHeader<Types '
        'xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" '
        'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '${override('/word/document.xml', '$wml.document.main+xml')}'
        '${override('/word/styles.xml', '$wml.styles+xml')}'
        '${override('/word/numbering.xml', '$wml.numbering+xml')}'
        '${override('/word/settings.xml', '$wml.settings+xml')}'
        '${override('/word/fontTable.xml', '$wml.fontTable+xml')}'
        '${override('/word/header1.xml', '$wml.header+xml')}'
        '${override('/word/header2.xml', '$wml.header+xml')}'
        '${override('/word/footer1.xml', '$wml.footer+xml')}'
        '${override('/word/footer2.xml', '$wml.footer+xml')}'
        '${override('/docProps/core.xml', 'application/vnd.openxmlformats-package.core-properties+xml')}'
        '${override('/docProps/app.xml', 'application/vnd.openxmlformats-officedocument.extended-properties+xml')}'
        '</Types>';
  }

  static const _packageRels =
      '$_xmlHeader<Relationships '
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_relBase/officeDocument" '
      'Target="word/document.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
      'Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="$_relBase/extended-properties" '
      'Target="docProps/app.xml"/>'
      '</Relationships>';

  String _documentRels() =>
      '$_xmlHeader<Relationships '
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${_rels.map((r) => r.xml()).join()}'
      '</Relationships>';

  String _coreProps() =>
      '$_xmlHeader<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(doc.title)}</dc:title>'
      '<dc:creator>AllisWell</dc:creator>'
      '</cp:coreProperties>';

  static const _appProps =
      '$_xmlHeader<Properties '
      'xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>AllisWell</Application>'
      '</Properties>';

  /// Running header for page 2 onward: the title, small and muted, 12 pt above
  /// the body.
  String _header() =>
      '$_xmlHeader<w:hdr $_storyNs>'
      '${_paragraph(_PPr(after: _M.headerGap, line: _line(_M.meta, 0)), _run(doc.title, const _RPr(size: _M.meta, color: _C.muted)))}'
      '</w:hdr>';

  /// "3 / 7", right-aligned, 12 pt below the body — on every page.
  String _footer() {
    const rPr = _RPr(size: _M.meta, color: _C.muted);
    String field(String code) =>
        '<w:fldSimple w:instr=" $code \\* MERGEFORMAT ">'
        '${_run('1', rPr)}</w:fldSimple>';
    return '$_xmlHeader<w:ftr $_storyNs>'
        '${_paragraph(_PPr(before: _M.headerGap, line: _line(_M.meta, 0), alignRight: true), '${field('PAGE')}${_run(' / ', rPr)}${field('NUMPAGES')}')}'
        '</w:ftr>';
  }

  /// A header with nothing in it that also takes no room — the first page's.
  String _emptyStory(String tag) =>
      '$_xmlHeader<w:$tag $_storyNs>'
      '${_paragraph(_PPr(line: _tw(1), exactLine: true, markSize: 1))}'
      '</w:$tag>';

  static final _styles =
      '$_xmlHeader<w:styles xmlns:w="$_nsW">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="$_font" w:hAnsi="$_font" w:eastAsia="$_font" '
      'w:cs="$_font"/>'
      '<w:color w:val="${_hex(_C.ink)}"/>'
      '<w:sz w:val="${_hp(_M.body)}"/><w:szCs w:val="${_hp(_M.body)}"/>'
      '</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" '
      'w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title">'
      '<w:name w:val="Title"/><w:basedOn w:val="Normal"/>'
      '<w:next w:val="Normal"/><w:qFormat/>'
      '<w:rPr><w:b/><w:bCs/><w:spacing w:val="${_tw(_M.titleLetterSpacing)}"/>'
      '<w:sz w:val="${_hp(_M.title)}"/><w:szCs w:val="${_hp(_M.title)}"/>'
      '</w:rPr></w:style>'
      '${_headingStyle(1, _M.heading1, _M.heading1Before)}'
      '${_headingStyle(2, _M.heading2, _M.heading2Before)}'
      '${_headingStyle(3, _M.heading3, _M.heading3Before)}'
      '<w:style w:type="character" w:styleId="Hyperlink">'
      '<w:name w:val="Hyperlink"/>'
      '<w:rPr><w:color w:val="${_hex(_C.accent)}"/><w:u w:val="single"/>'
      '</w:rPr></w:style>'
      '</w:styles>';

  static String _headingStyle(int level, double size, double before) =>
      '<w:style w:type="paragraph" w:styleId="Heading$level">'
      '<w:name w:val="heading $level"/><w:basedOn w:val="Normal"/>'
      '<w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/>'
      '<w:spacing w:before="${_tw(before)}" w:after="${_tw(_M.blockAfter)}"/>'
      '<w:outlineLvl w:val="${level - 1}"/></w:pPr>'
      '<w:rPr><w:b/><w:bCs/><w:sz w:val="${_hp(size)}"/>'
      '<w:szCs w:val="${_hp(size)}"/></w:rPr></w:style>';

  /// The list definitions: marker in a [NotePrintMetrics.markerWidth] column,
  /// [NotePrintMetrics.indentPerLevel] more per level (capped where the PDF
  /// caps it), the marker muted like the PDF's.
  String _numbering() {
    String levels({required bool ordered, int start = 1}) {
      final b = StringBuffer();
      for (var l = 0; l < 9; l++) {
        final left =
            l.clamp(0, _M.maxIndentLevel) * _M.indentPerLevel + _M.markerWidth;
        b.write(
          '<w:lvl w:ilvl="$l">'
          '<w:start w:val="${ordered ? start : 1}"/>'
          '<w:numFmt w:val="${ordered ? 'decimal' : 'bullet'}"/>'
          '<w:suff w:val="tab"/>'
          '<w:lvlText w:val="${ordered ? '%${l + 1}.' : '•'}"/>'
          '<w:lvlJc w:val="left"/>'
          '<w:pPr><w:tabs><w:tab w:val="num" w:pos="${_tw(left)}"/></w:tabs>'
          '<w:ind w:left="${_tw(left)}" w:hanging="${_tw(_M.markerWidth)}"/>'
          '</w:pPr>'
          '<w:rPr><w:rFonts w:ascii="$_font" w:hAnsi="$_font" w:cs="$_font"/>'
          '<w:b w:val="0"/><w:i w:val="0"/>'
          '<w:color w:val="${_hex(_C.muted)}"/>'
          '<w:sz w:val="${_hp(_M.body)}"/><w:szCs w:val="${_hp(_M.body)}"/>'
          '</w:rPr></w:lvl>',
        );
      }
      return b.toString();
    }

    String abstract(int id, String body) =>
        '<w:abstractNum w:abstractNumId="$id">'
        '<w:nsid w:val="${(0x1A110000 + id).toRadixString(16).toUpperCase()}"/>'
        '<w:multiLevelType w:val="hybridMultilevel"/>$body</w:abstractNum>';

    final b = StringBuffer('$_xmlHeader<w:numbering xmlns:w="$_nsW">')
      ..write(abstract(0, levels(ordered: false)));
    for (final (i, start) in _orderedAbstracts.indexed) {
      b.write(abstract(i + 1, levels(ordered: true, start: start)));
    }
    b.write(
      '<w:num w:numId="$_bulletNumId"><w:abstractNumId w:val="0"/></w:num>',
    );
    for (var i = 0; i < _orderedAbstracts.length; i++) {
      b.write(
        '<w:num w:numId="${i + 2}"><w:abstractNumId w:val="${i + 1}"/>'
        '</w:num>',
      );
    }
    b.write('</w:numbering>');
    return b.toString();
  }

  static const _settings =
      '$_xmlHeader<w:settings xmlns:w="$_nsW">'
      '<w:zoom w:percent="100"/>'
      '<w:defaultTabStop w:val="720"/>'
      '<w:characterSpacingControl w:val="doNotCompress"/>'
      '<w:compat><w:compatSetting w:name="compatibilityMode" '
      'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
      '</w:settings>';

  /// Roboto is declared with Arial as its stand-in, so a machine without
  /// Roboto substitutes a sans of the same build rather than Times.
  static const _fontTable =
      '$_xmlHeader<w:fonts xmlns:w="$_nsW">'
      '<w:font w:name="$_font"><w:altName w:val="Arial"/>'
      '<w:charset w:val="00"/><w:family w:val="swiss"/>'
      '<w:pitch w:val="variable"/></w:font>'
      '<w:font w:name="$_symbolFont"><w:charset w:val="00"/>'
      '<w:family w:val="swiss"/><w:pitch w:val="variable"/></w:font>'
      '</w:fonts>';
}
