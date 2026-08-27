/// The flat block model the PDF exporter renders (round 16 #3).
///
/// The exporter needs the document's STRUCTURE, not a string: a heading has to
/// become a sized paragraph, a checklist item a box plus text, an image its
/// own figure. The model is PURE and knows nothing about the `pdf` package, so
/// the mapping is unit-testable on its own — and reusable by any future
/// renderer (HTML export, print preview) without dragging a PDF dependency.
///
/// **Producers:** `markdownToBlocks` (`markdown_blocks.dart`) is the one that
/// runs. `deltaToBlocks`, below, survives ADR-0033 only for the tests that
/// pin the delta era's behaviour and for anything still holding an old
/// document; nothing in the app produces a Delta any more.
library;

/// What a line turns into on the page.
enum NoteBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  ordered,
  checked,
  unchecked,
  quote,
  code,

  /// A `{"image": source}` embed, on its own.
  image,

  /// Any other sourced embed (video, attachment) — rendered as a labelled
  /// reference rather than silently dropped.
  attachment,

  /// A `---` rule. New with markdown (OPH-274): Delta had no such node.
  divider,

  /// A GFM table, rows-first. Also new — `flutter_quill` 11.5.1 has no table
  /// node at all, which is the measurement that decided ADR-0033.
  table,

  /// A block the page cannot DRAW from text — a mermaid diagram, a display
  /// formula — carried as "a picture we will try to make, plus the source to
  /// print if we cannot" (round 19 #1, ADR-0034).
  ///
  /// [NoteBlock.source] is the raster KEY (`aw-figure:<kind>:<n>`), not a URL:
  /// nothing fetches it, the exporter's rasterizer fills it in. [NoteBlock.text]
  /// is the honest fallback — the diagram's own mermaid source, or the LaTeX —
  /// which is strictly more use to a reader than "unsupported block".
  figure,

  /// A GFM alert (`> [!WARNING]`) — a tinted box with a coloured edge and a
  /// localized label (round 19b, OPH-281).
  ///
  /// The reading view draws these as `MdCallout`. The page printed
  /// "unsupported block", which is the one thing an alert must never become:
  /// its whole job is to be the paragraph you cannot skip.
  callout,

  /// A document's front matter, shown as its own quiet strip rather than as
  /// body text (round 19b) — the reading view's `_FrontMatterStrip`.
  frontMatter,
}

/// Which off-screen widget a [NoteBlockKind.figure] should be drawn with.
enum NoteFigureKind { mermaid, math }

/// The raster key for the [index]th figure of [kind] in a document.
///
/// Deterministic and position-based rather than content-based: two identical
/// diagrams in one note are two figures, and a key collision would silently
/// print the first one twice.
String noteFigureKey(NoteFigureKind kind, int index) =>
    'aw-figure:${kind.name}:$index';

/// A run of text sharing one set of inline attributes.
class NoteSpan {
  const NoteSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
    this.mark = false,
    this.superscript = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  /// `==highlight==`. The screen has drawn this since OPH-247 and the page
  /// dropped it silently — `_spansOf` had no `mark` case, so the walker's
  /// `default:` branch recursed past it into plain text (round 19b, OPH-281).
  final bool mark;

  /// A footnote reference (`sup`). Small, raised, and until round 19b printed
  /// as a stray digit in the middle of a sentence.
  final bool superscript;

  @override
  bool operator ==(Object other) =>
      other is NoteSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strike == strike &&
      other.code == code &&
      other.link == link &&
      other.mark == mark &&
      other.superscript == superscript;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, strike, code, link, mark, superscript);

  @override
  String toString() =>
      'NoteSpan("$text"${bold ? ' b' : ''}${italic ? ' i' : ''}'
      '${strike ? ' s' : ''}${code ? ' c' : ''}${link != null ? ' →$link' : ''})';
}

/// One line (or figure) of the exported document.
class NoteBlock {
  const NoteBlock(
    this.kind, {
    this.spans = const [],
    this.source,
    this.ordinal,
    this.rows,
    this.indent = 0,
    this.figureKind,
    this.calloutKind,
  });

  final NoteBlockKind kind;
  final List<NoteSpan> spans;

  /// Embed source for [NoteBlockKind.image] / [NoteBlockKind.attachment] —
  /// `alliswell://file/{id}` for our own media, or a foreign http(s) URL.
  final String? source;

  /// 1-based position within a run of [NoteBlockKind.ordered] items.
  final int? ordinal;

  /// Cells for [NoteBlockKind.table], first row being the header.
  final List<List<String>>? rows;

  /// Nesting depth for list items — 0 is top level. Delta's block attributes
  /// were flat, so a nested list was simply not expressible; markdown's are
  /// not, and the exporter can indent.
  final int indent;

  /// Which renderer draws a [NoteBlockKind.figure]; null for every other kind.
  final NoteFigureKind? figureKind;

  /// A [NoteBlockKind.callout]'s GFM alert name (`note`/`tip`/`important`/
  /// `warning`/`caution`), which picks its edge colour.
  final String? calloutKind;

  /// The block's text with formatting dropped — for alt text and tests.
  String get text => spans.map((s) => s.text).join();

  @override
  String toString() =>
      'NoteBlock($kind${ordinal != null ? ' #$ordinal' : ''}'
      '${source != null ? ' src=$source' : ''} "$text")';
}

NoteBlockKind _kindFor(Map<String, dynamic> attrs) {
  if (attrs['code-block'] != null && attrs['code-block'] != false) {
    return NoteBlockKind.code;
  }
  final header = attrs['header'];
  if (header is int) {
    // The toolbar offers H1–H3; anything deeper renders as the smallest
    // heading rather than falling back to body text.
    if (header == 1) return NoteBlockKind.heading1;
    if (header == 2) return NoteBlockKind.heading2;
    if (header >= 3 && header <= 6) return NoteBlockKind.heading3;
  }
  if (attrs['blockquote'] == true) return NoteBlockKind.quote;
  return switch (attrs['list']) {
    'bullet' => NoteBlockKind.bullet,
    'ordered' => NoteBlockKind.ordered,
    'checked' => NoteBlockKind.checked,
    'unchecked' => NoteBlockKind.unchecked,
    _ => NoteBlockKind.paragraph,
  };
}

NoteSpan _span(String text, Map<String, dynamic>? attrs) {
  final link = attrs?['link'];
  return NoteSpan(
    text,
    bold: attrs?['bold'] == true,
    italic: attrs?['italic'] == true,
    strike: attrs?['strike'] == true,
    code: attrs?['code'] == true,
    link: link is String && link.isNotEmpty ? link : null,
  );
}

/// Converts a Quill delta into the block list the exporter renders.
List<NoteBlock> deltaToBlocks(List<Map<String, dynamic>> ops) {
  final blocks = <NoteBlock>[];
  var pending = <NoteSpan>[];
  var ordinal = 0;
  // An embed sits ON a line, so the newline that ends that line arrives right
  // after it with nothing left to write. Without this, every image would be
  // followed by a blank paragraph's worth of dead space.
  var lineAlreadyEmitted = false;

  void closeLine(Map<String, dynamic>? lineAttributes) {
    final spans = pending;
    pending = <NoteSpan>[];
    final kind = _kindFor(lineAttributes ?? const {});
    final closingAnEmbedLine = lineAlreadyEmitted;
    lineAlreadyEmitted = false;
    if (closingAnEmbedLine &&
        spans.isEmpty &&
        kind == NoteBlockKind.paragraph) {
      ordinal = 0;
      return;
    }

    if (kind == NoteBlockKind.ordered) {
      ordinal += 1;
    } else {
      ordinal = 0;
    }

    // Consecutive code lines are ONE block, so the renderer can draw a single
    // panel instead of a stack of one-line panels.
    if (kind == NoteBlockKind.code &&
        blocks.isNotEmpty &&
        blocks.last.kind == NoteBlockKind.code) {
      final previous = blocks.removeLast();
      blocks.add(
        NoteBlock(
          NoteBlockKind.code,
          spans: [...previous.spans, const NoteSpan('\n'), ...spans],
        ),
      );
      return;
    }

    blocks.add(
      NoteBlock(
        kind,
        spans: spans,
        ordinal: kind == NoteBlockKind.ordered ? ordinal : null,
      ),
    );
  }

  void flushPendingAsParagraph() {
    if (pending.isEmpty) return;
    blocks.add(NoteBlock(NoteBlockKind.paragraph, spans: pending));
    pending = <NoteSpan>[];
    ordinal = 0;
  }

  for (final op in ops) {
    final insert = op['insert'];
    final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();

    if (insert is! String) {
      // An embed is a figure: it gets its own block, after whatever text was
      // already on the line. Shapes we do not understand are dropped rather
      // than rendered as an empty box (parity with deltaToMarkdown).
      if (insert is Map) {
        final image = insert['image'];
        final video = insert['video'];
        final isImage = image is String && image.isNotEmpty;
        final source = isImage ? image : video;
        if (source is String && source.isNotEmpty) {
          flushPendingAsParagraph();
          blocks.add(
            NoteBlock(
              isImage ? NoteBlockKind.image : NoteBlockKind.attachment,
              source: source,
            ),
          );
          ordinal = 0;
          lineAlreadyEmitted = true;
        }
      }
      continue;
    }

    var remaining = insert;
    while (remaining.contains('\n')) {
      final idx = remaining.indexOf('\n');
      if (idx > 0) pending.add(_span(remaining.substring(0, idx), attrs));
      closeLine(attrs);
      remaining = remaining.substring(idx + 1);
    }
    if (remaining.isNotEmpty) pending.add(_span(remaining, attrs));
  }
  flushPendingAsParagraph();

  // Quill documents always end with a newline, so the last block is an empty
  // paragraph. Drop that and any other trailing blank lines — a page of empty
  // paragraphs at the end of a PDF looks like a bug.
  while (blocks.isNotEmpty &&
      blocks.last.kind == NoteBlockKind.paragraph &&
      blocks.last.text.trim().isEmpty) {
    blocks.removeLast();
  }
  return blocks;
}
