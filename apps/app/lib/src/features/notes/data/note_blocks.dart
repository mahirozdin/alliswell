/// Quill Delta → a flat block model (round 16 #3, note PDF export).
///
/// The PDF exporter needs the document's STRUCTURE, not a string: a heading has
/// to become a sized paragraph, a checklist item a box plus text, an image its
/// own figure. `deltaToMarkdown` in this folder flattens all of that to text,
/// so exporting through markdown would have thrown the structure away and then
/// asked a markdown parser to guess it back.
///
/// This converter is PURE and knows nothing about the `pdf` package, so the
/// mapping is unit-testable on its own — and reusable by any future renderer
/// (HTML export, print preview) without dragging a PDF dependency along.
///
/// Delta semantics that drive the parsing, same as [deltaToMarkdown]:
///  * the NEWLINE op carries the line's block attributes, not the text op;
///  * inline attributes ride on the text ops themselves;
///  * consecutive `code-block` lines are one visual block;
///  * ordered lists carry no numbers — consecutive items number 1..n and the
///    counter resets as soon as anything else interrupts them.
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
}

/// A run of text sharing one set of inline attributes.
class NoteSpan {
  const NoteSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is NoteSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strike == strike &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, italic, strike, code, link);

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
  });

  final NoteBlockKind kind;
  final List<NoteSpan> spans;

  /// Embed source for [NoteBlockKind.image] / [NoteBlockKind.attachment] —
  /// `alliswell://file/{id}` for our own media, or a foreign http(s) URL.
  final String? source;

  /// 1-based position within a run of [NoteBlockKind.ordered] items.
  final int? ordinal;

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
