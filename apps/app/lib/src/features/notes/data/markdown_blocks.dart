/// Markdown → the flat block model the PDF exporter renders (OPH-274).
///
/// The replacement for `deltaToBlocks`, and the last thing that tied export to
/// the rich editor. The exporter needs the document's STRUCTURE — a heading is
/// a sized paragraph, a checklist item is a box plus text, an image is its own
/// figure — so exporting through a flattened string was never an option.
///
/// It walks the tree `md_parse.dart` already builds rather than re-parsing:
/// that parser carries the source positions the reading view and the outline
/// need, and having two markdown parsers in one app is how a heading ends up
/// looking different depending on which surface you asked.
///
/// ## This is a gain, not a port
///
/// Delta had no representation for a table, a footnote, math or a diagram
/// (`flutter_quill` 11.5.1 has no table node at all), so those simply could
/// not appear in an exported PDF. They can now. What still cannot be DRAWN —
/// math, diagrams, raw HTML — becomes an honest placeholder rather than
/// silence, the same rule the on-screen renderer follows (DESIGN §10 F3).
library;

import 'package:markdown/markdown.dart' as md;

import 'package:markdown_forge/markdown_forge.dart';
import 'note_blocks.dart';

/// Converts markdown source into the block list the exporter renders.
List<NoteBlock> markdownToBlocks(
  String markdown, {
  String Function(String kind)? placeholderFor,
}) => _BlockWalker(placeholderFor).run(parseMarkdown(markdown));

class _BlockWalker {
  _BlockWalker(this._placeholderFor);

  final String Function(String kind)? _placeholderFor;
  final List<NoteBlock> _out = [];

  List<NoteBlock> run(MdDocument document) {
    for (final block in document.blocks) {
      _node(block.node);
    }
    // Trailing blank paragraphs read as a bug at the end of a PDF.
    while (_out.isNotEmpty &&
        _out.last.kind == NoteBlockKind.paragraph &&
        _out.last.text.trim().isEmpty) {
      _out.removeLast();
    }
    return _out;
  }

  void _node(md.Node node, {int listDepth = 0}) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        _out.add(NoteBlock(NoteBlockKind.paragraph, spans: [NoteSpan(text)]));
      }
      return;
    }
    if (node is! md.Element) return;

    switch (node.tag) {
      case 'h1':
        _out.add(NoteBlock(NoteBlockKind.heading1, spans: _spans(node)));
      case 'h2':
        _out.add(NoteBlock(NoteBlockKind.heading2, spans: _spans(node)));
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        // The exporter styles three heading levels; deeper ones render as the
        // smallest rather than falling back to body text and losing the rank.
        _out.add(NoteBlock(NoteBlockKind.heading3, spans: _spans(node)));
      case 'p':
        // A paragraph whose only child is an image is a FIGURE, not a line of
        // text with a picture in it — `![alt](src)` on its own line is how
        // every markdown author writes one. Block math arrives wrapped the
        // same way (`p > aw-math-block`), and unwrapping it is what stops a
        // formula from being flattened into its own source text.
        final only = _lone(node);
        if (only != null && (only.tag == 'img' || _undrawable(only.tag))) {
          _node(only, listDepth: listDepth);
        } else {
          _out.add(NoteBlock(NoteBlockKind.paragraph, spans: _spans(node)));
        }
      case 'blockquote':
        for (final child in node.children ?? const <md.Node>[]) {
          if (child is md.Element && child.tag == 'p') {
            _out.add(NoteBlock(NoteBlockKind.quote, spans: _spans(child)));
          } else {
            _node(child, listDepth: listDepth);
          }
        }
      case 'pre':
        _out.add(NoteBlock(NoteBlockKind.code, spans: [NoteSpan(_raw(node))]));
      case 'hr':
        _out.add(const NoteBlock(NoteBlockKind.divider));
      case 'ul':
        _list(node, ordered: false, depth: listDepth);
      case 'ol':
        _list(node, ordered: true, depth: listDepth);
      case 'table':
        _table(node);
      case 'img':
        _image(node);
      default:
        // Math, diagrams and raw HTML have no page representation. Saying so
        // beats a silent gap the reader cannot distinguish from a bug.
        final label = _placeholderFor?.call(node.tag);
        if (label != null) {
          _out.add(
            NoteBlock(NoteBlockKind.paragraph, spans: [NoteSpan(label)]),
          );
        }
    }
  }

  void _list(md.Element list, {required bool ordered, required int depth}) {
    var ordinal = 0;
    for (final item in list.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      final checkbox = _checkbox(item);
      final kind = checkbox != null
          ? (checkbox ? NoteBlockKind.checked : NoteBlockKind.unchecked)
          : (ordered ? NoteBlockKind.ordered : NoteBlockKind.bullet);
      if (kind == NoteBlockKind.ordered) ordinal += 1;

      _out.add(
        NoteBlock(
          kind,
          spans: _spans(item, skipNested: true),
          ordinal: kind == NoteBlockKind.ordered ? ordinal : null,
          indent: depth,
        ),
      );
      // Nested lists — the thing Delta could not hold at all, because its
      // block attributes are flat. One more reason markdown won.
      for (final child in item.children ?? const <md.Node>[]) {
        if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
          _list(child, ordered: child.tag == 'ol', depth: depth + 1);
        }
      }
    }
  }

  void _table(md.Element table) {
    final rows = <List<String>>[];
    void collect(md.Element section) {
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        rows.add([
          for (final cell in row.children ?? const <md.Node>[])
            if (cell is md.Element) _raw(cell).trim(),
        ]);
      }
    }

    for (final section in table.children ?? const <md.Node>[]) {
      if (section is md.Element) collect(section);
    }
    if (rows.isNotEmpty) _out.add(NoteBlock(NoteBlockKind.table, rows: rows));
  }

  void _image(md.Element img) {
    final source = img.attributes['src'];
    if (source == null || source.isEmpty) return;
    final alt = img.attributes['alt'] ?? '';
    _out.add(
      NoteBlock(
        NoteBlockKind.image,
        source: source,
        spans: alt.isEmpty ? const [] : [NoteSpan(alt)],
      ),
    );
  }

  /// Tags with no representation on a page.
  ///
  /// Math is drawn in pure Flutter on screen and there is no such widget for
  /// the `pdf` package; raw HTML is shown as inert source on screen (D10) and
  /// dumping markup into a PDF would be noise. A fenced `mermaid` block is
  /// deliberately NOT here: it prints as code, and a reader who gets the
  /// diagram's source has strictly more than one who gets "unsupported".
  static bool _undrawable(String tag) =>
      tag.startsWith('aw-math') || tag == 'aw-raw-html';

  /// The single element child of [node], when that is all it has.
  md.Element? _lone(md.Element node) {
    final children = (node.children ?? const <md.Node>[])
        .where((c) => !(c is md.Text && c.text.trim().isEmpty))
        .toList();
    if (children.length != 1) return null;
    final only = children.first;
    return only is md.Element ? only : null;
  }

  /// GFM task-list state, or null when this item is not a task.
  bool? _checkbox(md.Element item) {
    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') {
        return child.attributes['checked'] == 'true';
      }
    }
    return null;
  }

  String _raw(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      return (node.children ?? const <md.Node>[]).map(_raw).join();
    }
    return '';
  }

  /// Inline runs, carrying the formatting down through nested emphasis.
  List<NoteSpan> _spans(
    md.Element element, {
    bool skipNested = false,
    bool bold = false,
    bool italic = false,
    bool strike = false,
    bool code = false,
    String? link,
  }) {
    final spans = <NoteSpan>[];
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Text) {
        if (child.text.isEmpty) continue;
        spans.add(
          NoteSpan(
            child.text,
            bold: bold,
            italic: italic,
            strike: strike,
            code: code,
            link: link,
          ),
        );
        continue;
      }
      if (child is! md.Element) continue;
      // A nested list is its own set of blocks; the item's text stops here.
      if (skipNested && (child.tag == 'ul' || child.tag == 'ol')) continue;
      switch (child.tag) {
        case 'strong':
          spans.addAll(
            _spans(
              child,
              bold: true,
              italic: italic,
              strike: strike,
              link: link,
            ),
          );
        case 'em':
          spans.addAll(
            _spans(child, bold: bold, italic: true, strike: strike, link: link),
          );
        case 'del':
          spans.addAll(
            _spans(child, bold: bold, italic: italic, strike: true, link: link),
          );
        case 'code':
          spans.add(NoteSpan(_raw(child), code: true, link: link));
        case 'a':
          spans.addAll(
            _spans(
              child,
              bold: bold,
              italic: italic,
              strike: strike,
              link: child.attributes['href'],
            ),
          );
        case 'input':
          break; // the checkbox itself is the block's kind, not its text
        case 'br':
          spans.add(const NoteSpan('\n'));
        default:
          spans.addAll(
            _spans(
              child,
              bold: bold,
              italic: italic,
              strike: strike,
              code: code,
              link: link,
            ),
          );
      }
    }
    return spans;
  }
}
