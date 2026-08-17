import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:markdown_forge/markdown_forge.dart';

/// ADR-0028 §Zorlama — the coverage claim, enforced.
///
/// `scripts/markdown/measure_coverage.dart` produced the numbers the ADR
/// argues from: of the 22 items DESIGN §29 D6 asks for, `markdown` 7.3.1 with
/// `ExtensionSet.gitHubWeb` supplies 19, and the three it does not (math,
/// `==highlight==`, front matter) are ours.
///
/// That claim decides which code we write. Left as a one-off measurement it
/// would rot silently: a package upgrade that drops footnote or alert support
/// would narrow the viewer and nothing would go red. So the measurement lives
/// here now, as assertions.
void main() {
  final fixture = File(
    'test/fixtures/markdown_conformance.md',
  ).readAsStringSync();

  late String html;
  late List<String> tags;

  setUpAll(() {
    final doc = parseMarkdown(fixture);
    tags = <String>[];
    void walk(md.Node node) {
      if (node is! md.Element) return;
      tags.add(node.tag);
      for (final child in node.children ?? const <md.Node>[]) {
        walk(child);
      }
    }

    for (final block in doc.blocks) {
      walk(block.node);
    }
    html = md.renderToHtml([for (final b in doc.blocks) b.node]);
  });

  group(
    'what the package supplies (19 of 22) — upgrades must not narrow it',
    () {
      // Each of these was VAR in the measurement. A false here means the parser
      // stopped producing something the reading view renders.
      final expectations = <String, bool Function()>{
        'tables with header cells': () =>
            tags.contains('table') && tags.contains('th'),
        // Alignment is an `align` attribute, NOT a CSS `text-align` — the first
        // measurement looked for the latter and wrongly reported a gap.
        'table alignment': () => html.contains('align="center"'),
        'task-list checkboxes': () => html.contains('type="checkbox"'),
        'footnote definitions': () => html.contains('footnote'),
        'footnote references': () => html.contains('fnref'),
        'GFM alerts': () => html.contains('markdown-alert'),
        'strikethrough': () => tags.contains('del'),
        'bare-url autolinks': () => html.contains('>https://alliswell.space<'),
        'emoji shortcodes': () => html.contains('🚀'),
        // Attribute-tolerant on purpose: our elements carry `data-aw-line`, so
        // the literal `<h2 id=` of the original measurement no longer matches.
        'heading ids (anchors)': () => RegExp(r'<h2[^>]*\sid="').hasMatch(html),
        'three levels of nested list': () => RegExp(
          r'<ul[^>]*>[\s\S]*?<ul[^>]*>[\s\S]*?<ul[^>]*>',
        ).hasMatch(html),
        'fenced code with a language': () => html.contains('language-dart'),
        'mermaid fences reach us as code blocks': () =>
            html.contains('language-mermaid'),
        'inline code': () => tags.contains('code'),
        'horizontal rules': () => tags.contains('hr'),
        'blockquotes': () => tags.contains('blockquote'),
        'images': () => tags.contains('img'),
        'hard line breaks': () => tags.contains('br'),
      };

      for (final entry in expectations.entries) {
        test(entry.key, () => expect(entry.value(), isTrue));
      }
    },
  );

  group('the three gaps we fill ourselves', () {
    test('inline math', () => expect(tags, contains(kMdMathInline)));
    test('block math', () => expect(tags, contains(kMdMathBlock)));
    test('==highlight==', () => expect(tags, contains('mark')));
    test('front matter', () => expect(tags, contains(kMdFrontMatter)));
    test(
      'raw HTML gets an element of its own',
      () => expect(tags, contains(kMdRawHtml)),
    );
  });

  test(
    'the package strips Turkish from heading ids — OPH-249 must not use them',
    () {
      // Measured here so the gap cannot be discovered halfway through OPH-249.
      //
      // `HeaderWithIdSyntax` generates `id="trke-balk"` for "Türkçe Başlık": it
      // DROPS ş/ı/ç rather than folding them, so `[git](#türkçe-başlık)` would
      // never resolve. DESIGN §29 D16 already says anchors must agree with
      // `core/fold.dart` — this is the same lesson ADR-0013 learned about search
      // (neither SQLite nor MySQL folds ı→i either; folding has to be
      // app-owned).
      //
      // When OPH-249 lands its own slug generator, THIS TEST SHOULD GO RED and
      // be replaced by one asserting `#türkçe-başlık` resolves.
      final doc = parseMarkdown('## Türkçe Başlık\n');
      final rendered = md.renderToHtml([for (final b in doc.blocks) b.node]);

      expect(rendered, contains('id="trke-balk"'));
      expect(
        rendered,
        isNot(contains('id="turkce-baslik"')),
        reason:
            'if this passes, the package started folding and D16 got easier',
      );
    },
  );

  test('the fixture still exercises every case the ADR counted', () {
    // A shrinking fixture would make every assertion above vacuously easy.
    expect(fixture.length, greaterThan(4000));
    expect(tags.length, greaterThan(200));
  });
}
