import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/fold.dart';
import 'package:markdown_forge/markdown_forge.dart';

/// OPH-249 — the heading tree and its anchors (DESIGN §29 D13/D14/D16).
void main() {
  group('slugs (D16) — folded, not truncated', () {
    test('Turkish letters FOLD instead of vanishing', () {
      // The bug OPH-247 measured and pinned: `HeaderWithIdSyntax` produces
      // `trke-balk` for this, so `#türkçe-başlık` could never resolve.
      expect(
        markdownSlug('Türkçe Başlık', fold: foldSearchText),
        'turkce-baslik',
      );
      expect(
        markdownSlug('Işık ve Iğdır', fold: foldSearchText),
        'isik-ve-igdir',
      );
      expect(markdownSlug('Çay İç', fold: foldSearchText), 'cay-ic');
    });

    test('GitHub rules do the rest', () {
      expect(
        markdownSlug('Hello, World!', fold: foldSearchText),
        'hello-world',
      );
      expect(
        markdownSlug('  spaced   out  ', fold: foldSearchText),
        'spaced-out',
      );
      expect(markdownSlug('C++ & Rust', fold: foldSearchText), 'c-rust');
      expect(
        markdownSlug('Kurulum (2026)', fold: foldSearchText),
        'kurulum-2026',
      );
    });

    test('duplicate headings get GitHub-style suffixes', () {
      final doc = parseMarkdown('## Kurulum\n\n## Kurulum\n\n## Kurulum\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      // Without this the second and third sections share an anchor and two of
      // the three are unreachable.
      expect(headings.map((h) => h.slug), [
        'kurulum',
        'kurulum-1',
        'kurulum-2',
      ]);
    });
  });

  group('anchors resolve (D16)', () {
    test('#türkçe-başlık finds its heading', () {
      final doc = parseMarkdown('# Giriş\n\n## Türkçe Başlık\n\nmetin\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      final hit = headingForAnchor(
        headings,
        'türkçe-başlık',
        fold: foldSearchText,
      );
      expect(hit, isNotNull);
      expect(hit!.text, 'Türkçe Başlık');
    });

    test('the already-folded form works too, and so does the raw heading', () {
      final doc = parseMarkdown('## Türkçe Başlık\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      expect(
        headingForAnchor(headings, 'turkce-baslik', fold: foldSearchText),
        isNotNull,
      );
      expect(
        headingForAnchor(headings, 'TÜRKÇE BAŞLIK', fold: foldSearchText),
        isNotNull,
      );
    });

    test('a percent-encoded anchor is decoded first', () {
      final doc = parseMarkdown('## Türkçe Başlık\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      expect(
        headingForAnchor(
          headings,
          Uri.encodeComponent('türkçe-başlık'),
          fold: foldSearchText,
        ),
        isNotNull,
      );
    });

    test('a stray % does not throw the jump away', () {
      // `Uri.decodeComponent` throws "Illegal percent encoding" on raw
      // non-ASCII AND on a half-encoded string. Decoding unconditionally
      // crashed on exactly the input D16 exists for.
      final doc = parseMarkdown('## Yüzde %100 bölüm\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      expect(
        headingForAnchor(headings, 'yüzde-%100-bölüm', fold: foldSearchText),
        isNotNull,
      );
    });

    test('an anchor nobody wrote returns null, it does not guess', () {
      final doc = parseMarkdown('## Giriş\n');
      expect(
        headingForAnchor(
          outlineHeadings(doc, fold: foldSearchText),
          'yok-boyle',
        ),
        isNull,
      );
    });
  });

  group('the tree (D13)', () {
    test('nests by level', () {
      final doc = parseMarkdown(
        '# Bir\n\n## Bir-A\n\n### Bir-A-1\n\n## Bir-B\n\n# İki\n',
      );
      final tree = buildOutline(outlineHeadings(doc, fold: foldSearchText));

      expect(tree, hasLength(2));
      expect(tree.first.heading.text, 'Bir');
      expect(tree.first.children.map((c) => c.heading.text), [
        'Bir-A',
        'Bir-B',
      ]);
      expect(tree.first.children.first.children.single.heading.text, 'Bir-A-1');
    });

    test('a document that starts deep, or skips levels, still nests', () {
      // Normal in the wild, and not an error — attaching to the nearest
      // SHALLOWER heading is what keeps such a document navigable.
      final doc = parseMarkdown('### Derin\n\n#### Daha derin\n\n## Üst\n');
      final tree = buildOutline(outlineHeadings(doc, fold: foldSearchText));

      expect(tree.map((n) => n.heading.text), ['Derin', 'Üst']);
      expect(tree.first.children.single.heading.text, 'Daha derin');
    });

    test('500 headings build the right tree, and each keeps its block', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 250; i++) {
        buffer
          ..writeln('## Bölüm $i')
          ..writeln()
          ..writeln('gövde $i')
          ..writeln()
          ..writeln('### Alt $i')
          ..writeln()
          ..writeln('gövde alt $i')
          ..writeln();
      }
      final doc = parseMarkdown(buffer.toString());
      final headings = outlineHeadings(doc, fold: foldSearchText);
      final tree = buildOutline(headings);

      expect(headings, hasLength(500));
      expect(tree, hasLength(250));
      expect(tree.every((n) => n.children.length == 1), isTrue);

      // Every heading points at a block that really IS that heading — the
      // property the jump depends on.
      for (final heading in headings) {
        expect(doc.blocks[heading.blockIndex].tag, 'h${heading.level}');
      }
    });

    test('the current section is the last heading at or above a block', () {
      final doc = parseMarkdown('# Bir\n\nmetin\n\n# İki\n\nmetin\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      expect(headingAt(headings, 0)!.text, 'Bir');
      expect(headingAt(headings, 1)!.text, 'Bir');
      expect(headingAt(headings, 3)!.text, 'İki');
    });
  });

  group('folding is a VIEW (D14)', () {
    test(
      'a section covers everything up to the next same-or-shallower head',
      () {
        final doc = parseMarkdown('# Bir\n\na\n\n## Alt\n\nb\n\n# İki\n\nc\n');
        final headings = outlineHeadings(doc, fold: foldSearchText);
        final range = foldedRangeFor(doc, headings, headings.first);

        // Everything between "Bir" and "İki" — including the nested "Alt".
        expect(range.start, headings.first.blockIndex + 1);
        expect(range.end, headings.last.blockIndex);
      },
    );

    test('the last section runs to the end of the document', () {
      final doc = parseMarkdown('# Bir\n\na\n\n# Son\n\nb\n');
      final headings = outlineHeadings(doc, fold: foldSearchText);

      expect(
        foldedRangeFor(doc, headings, headings.last).end,
        doc.blocks.length,
      );
    });

    test('computing a fold does not touch the document', () {
      // The rule this returns a RANGE for, instead of applying anything: fold
      // state is per-session and the bytes are not ours to rewrite.
      const src = '# Bir\n\na\n\n## Alt\n\nb\n';
      final doc = parseMarkdown(src);
      final headings = outlineHeadings(doc, fold: foldSearchText);

      foldedRangeFor(doc, headings, headings.first);

      expect(doc.lines.join('\n'), src);
      expect(sourceOf(doc, doc.blocks.first), '# Bir');
    });
  });
}
