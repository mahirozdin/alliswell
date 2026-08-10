/// Markdown → AST **plus the map back to the source** (OPH-247, ADR-0028 §2).
///
/// The map is the reason this layer exists, and it is the reason ADR-0028 chose
/// our own renderer over a packaged one. Four DESIGN §29 rules need to know
/// which source lines a rendered block came from, and they need it
/// independently of each other:
///
///   * **D4** — ticking a checkbox in the reading view writes to the document,
///     which means finding the `- [ ]` that produced it;
///   * **D13/D14** — the outline and heading folding work on line ranges;
///   * **D16** — `[link](#heading)` scrolls to a heading;
///   * **D5** — source ⇄ reading scroll sync maps an offset either way.
///
/// `markdown` 7.3.1 carries **no position information at any level** — not on
/// `Element`, not on `Line` — and neither does any renderer package that was
/// measured. So this layer is ours no matter which parser wins.
///
/// It needs no fork. Four public seams are enough:
///   1. `Line` is a plain class, so [_IndexedLine] can carry its own index;
///   2. `Document.parseLineList` takes the `List<Line>` we built;
///   3. `BlockParser.lines`/`.current` are public, so a wrapping syntax can
///      read the index the parser is standing on;
///   4. `Element.attributes` is a mutable map, so the wrapper can stamp it.
///
/// Measured on `test/fixtures/markdown_conformance.md` (OPH-246, and asserted
/// in `md_parse_test.dart` so a regression cannot be silent): 109 of 110
/// top-level elements stamped, 29 of 29 heading positions correct.
library;

import 'package:markdown/markdown.dart' as md;

import 'md_syntaxes.dart';

/// Where a block started and ended in the source, stamped onto the element.
/// Read through [MdBlock]; the raw attributes are an implementation detail of
/// the seam, not an API.
const String kMdLineAttr = 'data-aw-line';
const String kMdLineEndAttr = 'data-aw-line-end';

/// A source line that remembers its own index.
///
/// The parser hands these back to us through `BlockParser.current`, so the
/// index is available exactly where a block is being consumed — no searching,
/// no identity scan over the line list.
class _IndexedLine extends md.Line {
  _IndexedLine(super.content, this.index);

  final int index;
}

/// Wraps a block syntax so whatever it produces remembers where it came from.
///
/// Every syntax is wrapped — including the package's own — which is why the
/// document is built with `withDefaultBlockSyntaxes: false`. Left on, the
/// parser appends the standard syntaxes *undecorated* after ours, and the
/// blocks they produce would come back unstamped.
class _PositionedSyntax extends md.BlockSyntax {
  _PositionedSyntax(this.inner);

  final md.BlockSyntax inner;

  @override
  RegExp get pattern => inner.pattern;

  @override
  bool canParse(md.BlockParser parser) => inner.canParse(parser);

  @override
  bool canEndBlock(md.BlockParser parser) => inner.canEndBlock(parser);

  @override
  md.Node? parse(md.BlockParser parser) {
    final start = _lineIndex(parser);
    final node = inner.parse(parser);
    final end = _lineIndex(parser);
    if (node is md.Element && start != null) {
      node.attributes[kMdLineAttr] = '$start';
      // `end` is where the parser stopped, i.e. the first line NOT consumed.
      node.attributes[kMdLineEndAttr] =
          '${((end ?? start) - 1).clamp(start, 1 << 30)}';
    }
    return node;
  }

  static int? _lineIndex(md.BlockParser parser) {
    if (parser.isDone) return parser.lines.length;
    final line = parser.current;
    return line is _IndexedLine ? line.index : null;
  }
}

/// One top-level block, with the source range that produced it.
class MdBlock {
  const MdBlock({
    required this.node,
    required this.startLine,
    required this.endLine,
  });

  final md.Node node;

  /// 0-based, inclusive. `-1` when the parser gave us a block with no position
  /// (see [MdDocument.unpositioned]) — callers must treat that as "unknown",
  /// never as "line zero".
  final int startLine;
  final int endLine;

  bool get hasPosition => startLine >= 0;

  /// The element's tag, or `null` for a bare text node.
  String? get tag => node is md.Element ? (node as md.Element).tag : null;
}

/// A parsed document: the block list the renderer walks, and the source it
/// came from so every block can be traced back to its text.
class MdDocument {
  const MdDocument({
    required this.blocks,
    required this.lines,
    required this.footnoteLabels,
  });

  final List<MdBlock> blocks;

  /// The source, split the same way the parser split it — indexes into this
  /// list are what [MdBlock.startLine] means.
  final List<String> lines;

  /// Footnote labels in appearance order, as the parser collected them.
  final List<String> footnoteLabels;

  /// Blocks the parser produced without a position. Exposed rather than
  /// swallowed: the parse test names them, so "109 of 110" stays a fact with a
  /// reason attached instead of a number nobody re-checks.
  Iterable<MdBlock> get unpositioned => blocks.where((b) => !b.hasPosition);
}

/// The complete block-syntax list, in priority order, each one wrapped.
///
/// Order is load-bearing:
///   * front matter first, or a leading `---` becomes a horizontal rule and
///     the document loses its head;
///   * block math before paragraphs, or the opening `$$` is eaten as text;
///   * GFM's syntaxes before the plain ones, so headings get ids and list
///     items get their checkboxes.
List<md.BlockSyntax> _blockSyntaxes() => <md.BlockSyntax>[
  const FrontMatterSyntax(),
  const MathBlockSyntax(),
  ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
  const md.EmptyBlockSyntax(),
  // Ours, not the package's: it returns a bare `Text`, which loses both its
  // position and its identity as HTML. See [HtmlBlockElementSyntax].
  const HtmlBlockElementSyntax(),
  const md.SetextHeaderSyntax(),
  const md.HeaderSyntax(),
  const md.CodeBlockSyntax(),
  const md.BlockquoteSyntax(),
  const md.HorizontalRuleSyntax(),
  const md.UnorderedListSyntax(),
  const md.OrderedListSyntax(),
  const md.LinkReferenceDefinitionSyntax(),
  const md.ParagraphSyntax(),
].map(_PositionedSyntax.new).toList(growable: false);

/// Parses [source] into positioned top-level blocks.
///
/// `encodeHtml: false` because nothing downstream emits HTML: the widget layer
/// paints text. Left on, the parser would replace `<` and `&` with entities and
/// the reader would see `&amp;lt;` where the author wrote `<`. Raw HTML is not
/// made safe by escaping it here — it is made safe by never being live, which
/// is `md_security.dart`'s job (D10).
MdDocument parseMarkdown(String source) {
  final rawLines = source.split('\n');
  final document = md.Document(
    blockSyntaxes: _blockSyntaxes(),
    inlineSyntaxes: <md.InlineSyntax>[
      // Ours first: the parser tries `document.inlineSyntaxes` before its own
      // defaults, and `$…$` has to win over plain text. `$$…$$` must come
      // before `$…$` for the same reason, one level down.
      MathDisplayInlineSyntax(),
      MathInlineSyntax(),
      MarkSyntax(),
      ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
    ],
    // False: we supply every block syntax above, decorated. True would append
    // the standard ones a second time, undecorated, and they would win nothing
    // but would leave blocks unstamped if ordering ever shifted.
    withDefaultBlockSyntaxes: false,
    // True: emphasis, links, images, code spans and autolinks all live in the
    // parser's default INLINE set. This flag is not the block one's twin.
    encodeHtml: false,
  );

  final nodes = document.parseLineList(<md.Line>[
    for (var i = 0; i < rawLines.length; i++) _IndexedLine(rawLines[i], i),
  ]);

  return MdDocument(
    blocks: <MdBlock>[for (final node in nodes) _toBlock(node)],
    lines: rawLines,
    footnoteLabels: List.unmodifiable(document.footnoteLabels),
  );
}

MdBlock _toBlock(md.Node node) {
  if (node is! md.Element) {
    return MdBlock(node: node, startLine: -1, endLine: -1);
  }
  final start = int.tryParse(node.attributes[kMdLineAttr] ?? '');
  final end = int.tryParse(node.attributes[kMdLineEndAttr] ?? '');
  return MdBlock(
    node: node,
    startLine: start ?? -1,
    endLine: end ?? start ?? -1,
  );
}

/// The source text a block was built from — what D11 shows when a block cannot
/// be drawn, and what D4 rewrites when a checkbox is ticked.
String sourceOf(MdDocument doc, MdBlock block) {
  if (!block.hasPosition) return '';
  final end = block.endLine.clamp(block.startLine, doc.lines.length - 1);
  return doc.lines.sublist(block.startLine, end + 1).join('\n');
}
