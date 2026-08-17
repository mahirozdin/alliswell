/// The three things `markdown` 7.3.1 does not parse (OPH-247, ADR-0028 §2).
///
/// This list is not a guess — it is what the coverage measurement found
/// missing (`scripts/markdown/measure_coverage.dart`): of the 22 items DESIGN
/// §29 D6 asks for, `ExtensionSet.gitHubWeb` already ships 19, including the
/// ones that look expensive (tables *with alignment*, footnotes, GFM alerts,
/// task-list checkboxes). Only math, `==highlight==` and front matter are ours.
///
/// Everything here emits a node with a tag the widget layer knows; nothing
/// here renders, and nothing here trusts its input.
library;

import 'package:markdown/markdown.dart' as md;

/// Tags this file introduces. Kept as constants because the parser writes them
/// and the widget layer reads them — a typo across that seam would silently
/// render a formula as a paragraph.
const String kMdMathInline = 'aw-math-inline';
const String kMdMathBlock = 'aw-math-block';
const String kMdFrontMatter = 'aw-front-matter';
const String kMdRawHtml = 'aw-raw-html';

/// `$$…$$` written on ONE line.
///
/// Must be tried before [MathInlineSyntax], which would otherwise chew the
/// same text into `$` + math + `$`: its pattern cannot start on the second
/// dollar, so it matches the inner pair and leaves the outer two as literal
/// text. Visibly broken output rather than a crash — the kind of thing that
/// only shows up when somebody pastes a real document.
class MathDisplayInlineSyntax extends md.InlineSyntax {
  MathDisplayInlineSyntax() : super(r'\$\$(?!\s)((?:[^$\n])+?)(?<!\s)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(kMdMathBlock, match[1]!));
    return true;
  }
}

/// `$…$` — inline math (DESIGN §29 D6).
///
/// The delimiters are deliberately strict: no whitespace directly inside the
/// dollars, and the closing dollar may not be followed by a digit. Prose is
/// full of money — "$5 and $10" must stay prose, and a lax pattern turns the
/// span between two prices into a formula.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'\$(?!\s)((?:\\\$|[^$\n])+?)(?<!\s)\$(?![0-9])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(kMdMathInline, match[1]!));
    return true;
  }
}

/// `$$` on its own line … `$$` — block math.
///
/// A block syntax rather than an inline one because it spans lines, and it has
/// to be tried before [md.ParagraphSyntax] or the opening `$$` is swallowed as
/// ordinary text.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final _fence = RegExp(r'^ {0,3}\$\$\s*$');

  @override
  RegExp get pattern => _fence;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance(); // opening fence
    final body = <String>[];
    while (!parser.isDone && !_fence.hasMatch(parser.current.content)) {
      body.add(parser.current.content);
      parser.advance();
    }
    // An unterminated block still produces a node: the source is shown either
    // way, and dropping it would be the silent loss D11 exists to prevent.
    if (!parser.isDone) parser.advance(); // closing fence
    return md.Element.text(kMdMathBlock, body.join('\n'));
  }
}

/// `==highlight==` → a `mark` element.
///
/// Built on [md.DelimiterSyntax] — the same machinery GFM's own `~~del~~`
/// uses — so emphasis nests correctly inside it. Hand-rolling this with a
/// regex would make `==**bold**==` render its asterisks.
class MarkSyntax extends md.DelimiterSyntax {
  MarkSyntax()
    : super(
        '=+',
        requiresDelimiterRun: true,
        allowIntraWord: false,
        startCharacter: 0x3D, // '=' — the package's charcode table is private
        tags: [md.DelimiterTag('mark', 2)],
      );
}

/// An HTML block, given a tag of its own (DESIGN §29 D10).
///
/// The package returns a bare `Text` node for an HTML block, and that is a
/// problem twice over: at top level it is indistinguishable from stray
/// whitespace, so the renderer cannot know to show it as inert source; and a
/// `Text` never carries a source position, so it drops out of the outline and
/// the scroll map. Both are fixed by giving it an element.
///
/// This does not make the HTML safe — nothing here escapes or sanitises
/// anything. It is safe because it is never live: `md_unsupported.dart` draws
/// it as source, and inline HTML is already literal text because the package's
/// [md.InlineHtmlSyntax] is a `TextSyntax`.
class HtmlBlockElementSyntax extends md.HtmlBlockSyntax {
  const HtmlBlockElementSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Text) return md.Element.text(kMdRawHtml, node.text);
    return node;
  }
}

/// A leading `---` fenced YAML block (DESIGN §29 D12).
///
/// Only at the very first line: further down, `---` is a horizontal rule or a
/// setext underline, and stealing it there would break ordinary documents.
/// The raw text is carried through untouched — this parser does not read YAML,
/// it only says "this region is front matter"; the widget layer renders it as
/// a key/value strip instead of dumping it as body text on the first screen.
class FrontMatterSyntax extends md.BlockSyntax {
  const FrontMatterSyntax();

  static final _fence = RegExp(r'^---\s*$');

  @override
  RegExp get pattern => _fence;

  @override
  bool canParse(md.BlockParser parser) {
    // `lines` is the whole document, so identity against the first line is
    // what "are we at the top?" means here.
    if (parser.lines.isEmpty) return false;
    if (!identical(parser.current, parser.lines.first)) return false;
    if (!_fence.hasMatch(parser.current.content)) return false;
    // A closing fence must exist, otherwise this is a setext heading or a rule
    // and the document would lose everything after it.
    for (var i = 1; i < parser.lines.length; i++) {
      if (_fence.hasMatch(parser.lines[i].content)) return true;
    }
    return false;
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance(); // opening fence
    final body = <String>[];
    while (!parser.isDone && !_fence.hasMatch(parser.current.content)) {
      body.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance(); // closing fence
    return md.Element.text(kMdFrontMatter, body.join('\n'));
  }
}
