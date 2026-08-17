import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:markdown_forge/markdown_forge.dart';

/// OPH-247 — the parse layer and its source map (ADR-0028 §2).
///
/// These assertions ARE the ADR's numbers. The decision to write our own
/// renderer rests on "no package gives us positions, and we can build them
/// without forking"; if that stops being true, this file goes red rather than
/// the viewer quietly losing its outline, its anchors and its checkboxes.
void main() {
  final fixture = File(
    'test/fixtures/markdown_conformance.md',
  ).readAsStringSync();

  group('source map', () {
    test('every parsed block carries its source line', () {
      final doc = parseMarkdown(fixture);
      final elements = doc.blocks.where((b) => b.tag != null).toList();

      expect(elements.length, greaterThan(100), reason: 'fixture shrank?');

      // Two kinds legitimately have no source range, and they are named here
      // rather than absorbed into a tolerance — ADR-0028's "109 of 110" is
      // this fact, not a rounding:
      //
      //   * `section` is the footnote container, which `Document` SYNTHESISES
      //     after parsing from definitions scattered through the document; it
      //     never consumed a contiguous run of lines, so it has no range.
      //   * a bare `Text` at top level is a whitespace remnant, not a block.
      //
      // Anything else appearing here means a syntax escaped the decorator and
      // the outline, anchors and checkboxes just lost that block.
      final unexpected = doc.unpositioned
          .map((b) => b.tag ?? 'text')
          .where((t) => t != 'section' && t != 'text')
          .toList();

      expect(
        unexpected,
        isEmpty,
        reason: 'blocks escaped the position decorator: $unexpected',
      );
    });

    test('heading stamps point at lines that really start with #', () {
      final doc = parseMarkdown(fixture);
      final headings = doc.blocks.where(
        (b) => b.tag != null && RegExp(r'^h[1-6]$').hasMatch(b.tag!),
      );

      expect(headings, isNotEmpty);
      for (final h in headings) {
        expect(h.hasPosition, isTrue, reason: 'heading without a position');
        expect(
          doc.lines[h.startLine].trimLeft(),
          startsWith('#'),
          reason: 'h stamp at line ${h.startLine} is not a heading line',
        );
      }
    });

    test('sourceOf round-trips a fenced code block verbatim', () {
      const src = 'giriş\n\n```dart\nvar a = 1;\nvar b = 2;\n```\n\nson';
      final doc = parseMarkdown(src);
      final pre = doc.blocks.firstWhere((b) => b.tag == 'pre');

      expect(sourceOf(doc, pre), '```dart\nvar a = 1;\nvar b = 2;\n```');
    });

    test('a block with no position reports -1, never line zero', () {
      // The guarantee callers rely on: "unknown" must not masquerade as the
      // top of the document, or an anchor jump would silently scroll home.
      final block = MdBlock(node: md.Text('x'), startLine: -1, endLine: -1);
      expect(block.hasPosition, isFalse);
      expect(block.startLine, -1);
    });
  });

  group('the three syntaxes the package does not ship', () {
    test('inline math becomes its own node, money stays prose', () {
      final doc = parseMarkdown(r'formül $E = mc^2$ ve fiyat $5 ile $10 arası');
      final tags = _allTags(doc);

      expect(tags, contains(kMdMathInline));
      expect(
        tags.where((t) => t == kMdMathInline),
        hasLength(1),
        reason: r'"$5 ile $10" must not become a formula',
      );
    });

    test('block math survives multiple lines', () {
      final doc = parseMarkdown('önce\n\n\$\$\na + b\nc + d\n\$\$\n\nsonra');
      final math = doc.blocks.firstWhere((b) => b.tag == kMdMathBlock);

      expect((math.node as md.Element).textContent, 'a + b\nc + d');
    });

    test('==highlight== nests emphasis instead of printing asterisks', () {
      final doc = parseMarkdown('bu ==**çok** önemli== bir şey');
      final tags = _allTags(doc);

      expect(tags, contains('mark'));
      expect(tags, contains('strong'));
    });

    test('front matter only counts at the top of the document', () {
      final leading = parseMarkdown('---\ntitle: a\n---\n\ngövde');
      expect(leading.blocks.first.tag, kMdFrontMatter);

      // The same three dashes further down is a rule, not front matter —
      // stealing it there would eat the rest of an ordinary document.
      final middle = parseMarkdown('gövde\n\n---\n\ndevam');
      expect(_allTags(middle), isNot(contains(kMdFrontMatter)));
      expect(_allTags(middle), contains('hr'));
    });

    test('an unclosed leading fence is a rule, not front matter', () {
      final doc = parseMarkdown('---\nbu asla kapanmıyor\n\ndevam');
      expect(_allTags(doc), isNot(contains(kMdFrontMatter)));
    });
  });

  group('GFM the package already ships (ADR-0028: 19 of 22)', () {
    test('tables keep their alignment', () {
      final doc = parseMarkdown('| a | b |\n| :- | -: |\n| 1 | 2 |');
      final table = doc.blocks.firstWhere((b) => b.tag == 'table');
      final aligns = <String>[];
      _walk(table.node, (e) {
        final a = e.attributes['align'];
        if (a != null) aligns.add(a);
      });

      expect(aligns, contains('left'));
      expect(aligns, contains('right'));
    });

    test('alerts, footnotes and task lists parse without help from us', () {
      final doc = parseMarkdown(
        '> [!NOTE]\n> dikkat\n\n- [x] bitti\n\nmetin[^1]\n\n[^1]: not',
      );
      final html = md.renderToHtml([for (final b in doc.blocks) b.node]);

      expect(html, contains('alert'));
      expect(html, contains('type="checkbox"'));
      expect(doc.footnoteLabels, isNotEmpty);
    });
  });
}

List<String> _allTags(MdDocument doc) {
  final tags = <String>[];
  for (final b in doc.blocks) {
    _walk(b.node, (e) => tags.add(e.tag));
  }
  return tags;
}

void _walk(md.Node node, void Function(md.Element) visit) {
  if (node is! md.Element) return;
  visit(node);
  for (final child in node.children ?? const <md.Node>[]) {
    _walk(child, visit);
  }
}
