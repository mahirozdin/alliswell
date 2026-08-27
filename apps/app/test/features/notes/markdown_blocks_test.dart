import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/markdown_blocks.dart';
import 'package:alliswell/src/features/notes/data/note_blocks.dart';

/// OPH-274 — markdown → the PDF exporter's block model.
///
/// The replacement for `deltaToBlocks`. Most of this file is ordinary mapping
/// coverage; the group worth reading is the last one, which pins the things
/// Delta could not express AT ALL and which therefore could never reach an
/// exported PDF before this change.
void main() {
  List<NoteBlock> blocks(String markdown) => markdownToBlocks(markdown);

  NoteBlock only(String markdown) {
    final list = blocks(markdown);
    expect(list, hasLength(1), reason: '$list');
    return list.single;
  }

  group('block kinds', () {
    test('headings map to the exporter’s three levels', () {
      expect(only('# bir').kind, NoteBlockKind.heading1);
      expect(only('## iki').kind, NoteBlockKind.heading2);
      expect(only('### üç').kind, NoteBlockKind.heading3);
      // Deeper headings keep their RANK rather than falling back to body text.
      expect(only('###### altı').kind, NoteBlockKind.heading3);
    });

    test('paragraphs, quotes and rules', () {
      expect(only('düz metin').kind, NoteBlockKind.paragraph);
      expect(only('> alıntı').kind, NoteBlockKind.quote);
      expect(only('---').kind, NoteBlockKind.divider);
    });

    test('a fenced block keeps its text', () {
      final block = only('```dart\nvoid main() {}\n```');
      expect(block.kind, NoteBlockKind.code);
      expect(block.text.trim(), 'void main() {}');
    });

    test('lists number themselves, and tasks carry their state', () {
      final ordered = blocks('1. bir\n1. iki\n1. üç');
      expect(ordered.map((b) => b.ordinal), [1, 2, 3]);
      expect(ordered.every((b) => b.kind == NoteBlockKind.ordered), isTrue);

      final tasks = blocks('- [x] bitti\n- [ ] kaldı');
      expect(tasks.map((b) => b.kind), [
        NoteBlockKind.checked,
        NoteBlockKind.unchecked,
      ]);
      expect(tasks.first.text.trim(), 'bitti');
    });

    test('an image on its own line is a figure, not a paragraph', () {
      final block = only('![şema](alliswell://file/X)');
      expect(block.kind, NoteBlockKind.image);
      expect(block.source, 'alliswell://file/X');
      expect(block.text, 'şema', reason: 'the alt text is the caption');
    });
  });

  group('inline formatting', () {
    NoteSpan spanWith(String markdown, String text) => only(
      markdown,
    ).spans.firstWhere((s) => s.text == text, orElse: () => NoteSpan(''));

    test('bold, italic, strikethrough and code', () {
      expect(spanWith('**kalın**', 'kalın').bold, isTrue);
      expect(spanWith('*eğik*', 'eğik').italic, isTrue);
      expect(spanWith('~~çizili~~', 'çizili').strike, isTrue);
      expect(spanWith('`kod`', 'kod').code, isTrue);
    });

    test('a link carries its target', () {
      final span = spanWith('[etiket](https://ornek.test)', 'etiket');
      expect(span.link, 'https://ornek.test');
    });

    test('nested emphasis keeps BOTH', () {
      // The case a flat mapper gets wrong: the inner span has to inherit the
      // outer one rather than replacing it.
      final span = spanWith('**_ikisi_**', 'ikisi');
      expect(span.bold, isTrue);
      expect(span.italic, isTrue);
    });

    test('a checkbox is the block’s KIND, never its text', () {
      expect(only('- [x] bitti').text.trim(), 'bitti');
    });
  });

  group('what Delta could not hold', () {
    test('a table survives all the way to the page', () {
      // `flutter_quill` 11.5.1 has no table node at all, so a table in a note
      // could not appear in an exported PDF — it was not a rendering gap, it
      // was a document-model gap. This is the measurement that decided
      // ADR-0033, asserted from the other end.
      final block = only('| Gün | Yer |\n| --- | --- |\n| 1 | Ayder |');
      expect(block.kind, NoteBlockKind.table);
      expect(block.rows, [
        ['Gün', 'Yer'],
        ['1', 'Ayder'],
      ]);
    });

    test('a NESTED list keeps its depth', () {
      // Delta's block attributes are flat: a sub-item was the same shape as a
      // top-level one, so the structure was lost before the exporter saw it.
      final list = blocks('- üst\n    - alt\n        - daha alt');
      expect(list.map((b) => b.indent), [0, 1, 2]);
    });

    test('a block the page cannot draw NAMES itself', () {
      // DESIGN §10 F3, applied to paper. Silence is indistinguishable from a
      // bug; a labelled gap is not. Raw HTML is the last block in this
      // category — round 19 moved math and mermaid out of it, into figures.
      final out = markdownToBlocks(
        '<div>merhaba</div>',
        placeholderFor: (kind) => 'unsupported:\$kind',
      );
      expect(out.map((b) => b.text).join(), contains('unsupported:'));
    });

    test('and stays silent when the caller has nothing to say', () {
      expect(markdownToBlocks('<div>merhaba</div>'), isEmpty);
    });
  });

  // Round 19 #1 — "the MD file has to export the way it LOOKS: graphics and
  // images, all of it."
  group('figures the page has to be given a picture of', () {
    test('an image INSIDE a sentence is not swallowed', () {
      // The reported bug, exactly: `_spans` walked unknown elements by
      // recursing into their children, and an `img` has none — so an image
      // written mid-paragraph contributed nothing at all to the PDF.
      final out = blocks('burada olması lazım![](alliswell://file/01ABC) son');
      expect(out.map((b) => b.kind), [
        NoteBlockKind.paragraph,
        NoteBlockKind.image,
        NoteBlockKind.paragraph,
      ]);
      expect(out.first.text.trim(), 'burada olması lazım');
      expect(out[1].source, 'alliswell://file/01ABC');
      expect(out.last.text.trim(), 'son');
    });

    test('an image alone on its line is still one figure, as before', () {
      final out = blocks('![alt](x)');
      expect(out.single.kind, NoteBlockKind.image);
      expect(out.single.source, 'x');
    });

    test('two images in one paragraph are two figures', () {
      final out = blocks('![a](1) arada ![b](2)');
      expect(out.map((b) => b.kind), [
        NoteBlockKind.image,
        NoteBlockKind.paragraph,
        NoteBlockKind.image,
      ]);
    });

    test('a mermaid fence is a diagram, not source code', () {
      final out = blocks('```mermaid\ngraph TD\nA-->B\n```');
      expect(out.single.kind, NoteBlockKind.figure);
      expect(out.single.figureKind, NoteFigureKind.mermaid);
      expect(out.single.source, noteFigureKey(NoteFigureKind.mermaid, 0));
      // The fallback the page prints when no picture could be made.
      expect(out.single.text, contains('graph TD'));
    });

    test('any other fence is still code', () {
      final out = blocks('```dart\nvoid main() {}\n```');
      expect(out.single.kind, NoteBlockKind.code);
      expect(out.single.text, contains('void main'));
    });

    test('display math is a figure carrying its LaTeX', () {
      final out = blocks('\$\$x^2\$\$');
      expect(out.single.kind, NoteBlockKind.figure);
      expect(out.single.figureKind, NoteFigureKind.math);
      expect(out.single.text, 'x^2');
    });

    test('INLINE math stays in its sentence', () {
      // Splitting a line of prose around `\$x\$` would read worse than the
      // LaTeX does; it is marked as code so it is visibly a formula.
      final out = blocks('alan \$x^2\$ kadardır');
      expect(out.single.kind, NoteBlockKind.paragraph);
      expect(out.single.text, 'alan x^2 kadardır');
      expect(out.single.spans.any((s) => s.code && s.text == 'x^2'), isTrue);
    });

    test('figure keys are positional, so two identical diagrams differ', () {
      final out = blocks(
        '```mermaid\ngraph TD\nA-->B\n```\n\n'
        '```mermaid\ngraph TD\nA-->B\n```',
      );
      expect(out.map((b) => b.source), [
        noteFigureKey(NoteFigureKind.mermaid, 0),
        noteFigureKey(NoteFigureKind.mermaid, 1),
      ]);
    });
  });

  group('shape', () {
    test('trailing blank paragraphs are dropped', () {
      expect(blocks('metin\n\n\n\n'), hasLength(1));
    });

    test('an empty document is an empty list, not a blank page', () {
      expect(blocks(''), isEmpty);
      expect(blocks('\n\n'), isEmpty);
    });

    test('document order is body order', () {
      final out = blocks('# baş\n\nara\n\n![a](x)\n\nson');
      expect(out.map((b) => b.kind), [
        NoteBlockKind.heading1,
        NoteBlockKind.paragraph,
        NoteBlockKind.image,
        NoteBlockKind.paragraph,
      ]);
    });
  });

  // Round 19b (OPH-281) — "the reading view's look is better; can the PDF have
  // it?" Comparing the two renderers found five divergences, only one of which
  // had been reported. Four were SILENT: the page either dropped the construct
  // or printed "unsupported block" where the screen drew something.
  group('what the screen draws, the page must carry', () {
    test('a highlight survives instead of flattening to plain text', () {
      // `_spansOf` had no `mark` case, so `default:` recursed straight past it
      // into the plain text underneath and the tint was simply gone.
      final out = blocks('bir ==vurgulu== söz');
      final marked = out.single.spans.where((s) => s.mark).toList();
      expect(marked, hasLength(1));
      expect(marked.single.text, 'vurgulu');
      expect(out.single.text, 'bir vurgulu söz', reason: 'no text is lost');
    });

    test('a highlight keeps the formatting nested inside it', () {
      final out = blocks('==**kalın** vurgu==');
      final bold = out.single.spans.firstWhere((s) => s.bold);
      expect(bold.mark, isTrue, reason: 'bold inside a highlight is both');
    });

    test('a footnote reference is raised, not a stray digit', () {
      final out = blocks('gövde[^1]\n\n[^1]: dipnot');
      final sup = out
          .expand((b) => b.spans)
          .where((s) => s.superscript)
          .toList();
      expect(sup, isNotEmpty);
    });

    test('a GFM alert is a callout, not "unsupported block"', () {
      final out = markdownToBlocks(
        '> [!WARNING]\n> dikkat et',
        placeholderFor: (kind) => 'unsupported:\$kind',
        alertLabelFor: (kind) => {'warning': 'Uyarı'}[kind] ?? kind,
      );
      final callout = out.firstWhere((b) => b.kind == NoteBlockKind.callout);
      expect(callout.calloutKind, 'warning');
      expect(callout.text, contains('Uyarı'));
      expect(callout.text, contains('dikkat et'));
      expect(
        out.map((b) => b.text).join(),
        isNot(contains('unsupported:')),
        reason:
            'an alert is the paragraph you cannot skip — never a placeholder',
      );
    });

    test("the alert's own English title is dropped, not printed twice", () {
      // The parser emits a `<p class="markdown-alert-title">Warning</p>`; the
      // reading view drops it and draws the localized label. If the page kept
      // it, a Turkish document would read "Uyarı / Warning".
      final out = markdownToBlocks(
        '> [!WARNING]\n> dikkat et',
        alertLabelFor: (_) => 'Uyarı',
      );
      final callout = out.firstWhere((b) => b.kind == NoteBlockKind.callout);
      expect(callout.text, isNot(contains('Warning')));
    });

    test('front matter is its own strip, not body text', () {
      final out = markdownToBlocks(
        '---\ntitle: Deneme\n---\n\ngövde',
        placeholderFor: (kind) => 'unsupported:\$kind',
      );
      expect(out.first.kind, NoteBlockKind.frontMatter);
      expect(out.first.text, contains('title: Deneme'));
    });
  });
}
