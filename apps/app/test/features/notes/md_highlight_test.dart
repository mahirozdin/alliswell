import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-274 — live syntax in the source field (DESIGN §29 D24).
///
/// The invariant that gets its own group is the character count. A
/// `TextEditingController` must hand the field back exactly the characters of
/// `text`: drop a `**` to "hide the syntax" and every caret offset, selection,
/// undo entry and IME composition after it points at the wrong character. That
/// is why the markers are DIMMED rather than removed, and it is the one
/// property that can silently corrupt somebody's typing if it regresses.
void main() {
  String scanned(String source) =>
      scanMarkdown(source).map((t) => source.substring(t.start, t.end)).join();

  group('the scan never loses a character', () {
    const documents = [
      '# Başlık\n\ngövde',
      '**kalın** ve *italik* ve `kod`',
      '- [ ] yapılacak\n- [x] bitti',
      '> alıntı\n\n---\n',
      '```dart\nvoid main() {}\n```',
      '[etiket](https://ornek.test) ve ![resim](alliswell://file/X)',
      '| a | b |\n| - | - |\n| 1 | 2 |',
      '~~çizili~~ ve ==vurgu==',
      'düz metin, hiç işaret yok',
      '',
      '\n\n\n',
      '# ',
      '**bitmemiş',
    ];

    for (final source in documents) {
      test(
        'round-trips ${source.length} chars: ${source.split('\n').first}',
        () {
          expect(scanned(source), source);
        },
      );
    }

    test('a document made of every construct at once', () {
      const kitchenSink =
          '# Başlık\n'
          '\n'
          'Bir **kalın**, bir *italik*, bir `kod`, bir ==vurgu==.\n'
          '\n'
          '- [x] bitti\n'
          '- madde\n'
          '1. sıralı\n'
          '\n'
          '> alıntı\n'
          '\n'
          '```js\n'
          'const x = 1;\n'
          '```\n'
          '\n'
          '[bağlantı](https://ornek.test)\n'
          '\n'
          '---\n';
      expect(scanned(kitchenSink), kitchenSink);
    });
  });

  group('the scan says what things are', () {
    MdTokenKind kindAt(String source, int offset) => scanMarkdown(
      source,
    ).firstWhere((t) => offset >= t.start && offset < t.end).kind;

    test('a heading marker is syntax, its text is a heading', () {
      const src = '## Başlık';
      expect(kindAt(src, 0), MdTokenKind.marker);
      expect(kindAt(src, 3), MdTokenKind.heading2);
    });

    test('emphasis marks are syntax, the words between them are not', () {
      const src = 'a **kalın** b';
      expect(kindAt(src, 2), MdTokenKind.marker); // the first *
      expect(kindAt(src, 4), MdTokenKind.bold); // 'k'
      expect(kindAt(src, 9), MdTokenKind.marker); // the closing *
      expect(kindAt(src, 12), MdTokenKind.plain);
    });

    test("a link's label is the document, its target is plumbing", () {
      const src = '[etiket](https://ornek.test)';
      expect(kindAt(src, 0), MdTokenKind.marker); // [
      expect(kindAt(src, 1), MdTokenKind.link); // 'e'
      expect(kindAt(src, 10), MdTokenKind.marker); // inside the url
    });

    test('a fenced block is code all the way through', () {
      const src = '```\nx = 1\n```\n';
      expect(kindAt(src, 0), MdTokenKind.marker); // the opening fence
      expect(kindAt(src, 5), MdTokenKind.codeBlock);
    });

    test('markdown inside a fence is NOT interpreted', () {
      // The classic false positive: `**` in a code block is code, not bold.
      const src = '```\n**not bold**\n```\n';
      expect(kindAt(src, 5), MdTokenKind.codeBlock);
    });

    test('a list marker is syntax, the item text is ordinary', () {
      const src = '- [ ] yapılacak';
      expect(kindAt(src, 0), MdTokenKind.marker);
      expect(kindAt(src, 7), MdTokenKind.plain);
    });
  });

  group('painting', () {
    late BuildContext ctx;

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    testWidgets('the span tree carries the text verbatim', (tester) async {
      await pumpHost(tester);
      const src = '# Başlık\n\n**kalın**';
      final controller = MdSourceController(text: src);
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(color: Color(0xFF101010)),
        withComposing: false,
      );

      expect(span.toPlainText(), src);
    });

    testWidgets('markers step forward on the caret line', (tester) async {
      await pumpHost(tester);
      const src = '# bir\n# iki';
      final controller = MdSourceController(text: src)
        // Caret on the SECOND line.
        ..selection = const TextSelection.collapsed(offset: 8);
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(color: Color(0xFF101010)),
        withComposing: false,
      );
      final children = span.children!.cast<TextSpan>();
      // The two `# ` runs are the first token of each line.
      final firstHash = children.firstWhere((c) => c.text == '# ');
      final lastHash = children.lastWhere((c) => c.text == '# ');

      expect(
        firstHash.style?.color,
        isNot(lastHash.style?.color),
        reason:
            'the line being edited shows its syntax; the others keep it quiet. '
            'Hiding it outright is not available: a TextEditingController must '
            'return every character of `text`.',
      );
    });

    testWidgets('headings are visibly bigger IN the field', (tester) async {
      await pumpHost(tester);
      final controller = MdSourceController(text: '# Başlık\ngövde');
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(fontSize: 14, color: Color(0xFF101010)),
        withComposing: false,
      );
      final children = span.children!.cast<TextSpan>();
      final heading = children.firstWhere((c) => c.text == 'Başlık');
      final body = children.firstWhere((c) => c.text == 'gövde');

      expect(heading.style!.fontSize!, greaterThan(body.style!.fontSize!));
      expect(heading.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('live syntax can be switched off', (tester) async {
      await pumpHost(tester);
      final controller = MdSourceController(text: '# Başlık')
        ..liveSyntax = false;
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(fontSize: 14, color: Color(0xFF101010)),
        withComposing: false,
      );

      expect(span.toPlainText(), '# Başlık');
      expect(span.children, isNull, reason: 'the plain, unstyled span tree');
    });

    testWidgets('focus mode composes with it instead of replacing it', (
      tester,
    ) async {
      await pumpHost(tester);
      final controller = MdSourceController(text: '# bir\n\n# iki')
        ..focusMode = true
        ..selection = const TextSelection.collapsed(offset: 9);
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(fontSize: 14, color: Color(0xFF101010)),
        withComposing: false,
      );
      final children = span.children!.cast<TextSpan>();
      final dimmed = children.firstWhere((c) => c.text == 'bir');
      final lit = children.firstWhere((c) => c.text == 'iki');

      // Both are still headings — focus mode dims, it does not flatten.
      expect(dimmed.style!.fontSize, lit.style!.fontSize);
      expect(dimmed.style!.color!.a, lessThan(lit.style!.color!.a));
      expect(span.toPlainText(), '# bir\n\n# iki');
    });
  });

  group('cost', () {
    test('the scan is reused until the TEXT changes', () {
      final controller = MdSourceController(text: 'bir');
      addTearDown(controller.dispose);

      final first = controller.tokens;
      controller.selection = const TextSelection.collapsed(offset: 1);
      expect(
        identical(controller.tokens, first),
        isTrue,
        reason: 'moving the caret through a long document must not re-scan it',
      );

      controller.text = 'bir iki';
      expect(identical(controller.tokens, first), isFalse);
    });

    test('a large document scans in one pass', () {
      // Not a benchmark — a guard. `buildTextSpan` runs on every rebuild over
      // the WHOLE document, and the API caps a body at a megabyte.
      final big = List.filled(20000, '# başlık\n\ngövde **kalın**\n').join();
      final watch = Stopwatch()..start();
      final tokens = scanMarkdown(big);
      watch.stop();

      expect(tokens, isNotEmpty);
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: '${big.length} chars took ${watch.elapsedMilliseconds}ms',
      );
    });
  });
}
