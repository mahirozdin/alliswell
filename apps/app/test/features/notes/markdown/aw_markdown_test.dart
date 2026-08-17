import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/markdown/markdown_forge_adapters.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-247 — the reading view over `markdown_conformance.md`.
///
/// STRUCTURAL, not golden: each assertion names the widget a feature is
/// supposed to produce. A golden would go red on a font change and tell us
/// nothing about whether tables still render.
void main() {
  final fixture = File(
    'test/fixtures/markdown_conformance.md',
  ).readAsStringSync();

  // OPH-274: the renderer is a package now, and its words come from the host
  // through `MarkdownStrings`. Without the scope it falls back to English
  // defaults — which is the package behaving correctly and this suite
  // measuring the wrong thing, so the scope is part of the host.
  Widget host(String markdown, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: buildAwTheme(brightness),
        home: Builder(
          builder: (context) => MarkdownForge(
            theme: awMarkdownTheme(context),
            strings: awMarkdownStrings(),
            child: Scaffold(
              body: MarkdownView(
                document: parseMarkdown(markdown),
                shrinkWrap: true,
                onOpenLink: (_) {},
              ),
            ),
          ),
        ),
      );

  group('the whole fixture', () {
    testWidgets('renders end to end without throwing', (tester) async {
      tester.view.physicalSize = const Size(1400, 9000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // A ProviderScope is REQUIRED — images resolve through Riverpod. The
      // viewport is tall enough to reach them on purpose: at 6000 px this test
      // stopped short of the image section and passed without ever proving
      // the thing it claims to prove.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: Scaffold(
              body: MarkdownView(document: parseMarkdown(fixture)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(MdImage), findsWidgets, reason: 'images were reached');
    });
  });

  group('GFM structures become their own widgets', () {
    testWidgets('a table is an MdTable, not a paragraph of pipes', (
      tester,
    ) async {
      await tester.pumpWidget(host('| a | b |\n| :- | -: |\n| 1 | 2 |'));
      expect(find.byType(MdTable), findsOneWidget);
      expect(find.text('|'), findsNothing);
    });

    testWidgets('a fenced block gets its language label and copy button', (
      tester,
    ) async {
      await tester.pumpWidget(host('```dart\nvar a = 1;\n```'));

      expect(find.byType(MdCodeBlock), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.byKey(const Key('md-copy-code')), findsOneWidget);
    });

    testWidgets('all five alert types render as callouts', (tester) async {
      const src = '''
> [!NOTE]
> a

> [!TIP]
> b

> [!IMPORTANT]
> c

> [!WARNING]
> d

> [!CAUTION]
> e
''';
      await tester.pumpWidget(host(src));
      expect(find.byType(MdCallout), findsNWidgets(5));
    });

    testWidgets('an alert says its type in the app language, not English', (
      tester,
    ) async {
      // The parser injects its own `<p class="markdown-alert-title">Note</p>`.
      // Rendering that would leak raw English into a Turkish document — the
      // exact class of bug `check:i18n` cannot see.
      await tester.pumpWidget(host('> [!NOTE]\n> gövde'));

      expect(find.text('Note'), findsOneWidget); // our key, en locale
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Note' && w.style?.fontWeight == null,
        ),
        findsNothing,
        reason: 'the parser\'s own title paragraph should not be rendered',
      );
    });

    testWidgets('front matter is a strip, not body text', (tester) async {
      await tester.pumpWidget(host('---\ntitle: a\n---\n\ngövde'));

      expect(find.text('Document properties'), findsOneWidget);
      expect(find.text('title: a'), findsOneWidget);
    });

    testWidgets('math renders through the engine', (tester) async {
      await tester.pumpWidget(host(r'satır içi $E = mc^2$ formül'));
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('task list checkboxes reflect their state', (tester) async {
      await tester.pumpWidget(host('- [x] bitti\n- [ ] açık'));

      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });
  });

  group('D8 — wide content scrolls inside its own box', () {
    testWidgets('a code block owns a horizontal scroll view', (tester) async {
      await tester.pumpWidget(host('```\n${'x' * 400}\n```'));

      final scrollables = tester.widgetList<SingleChildScrollView>(
        find.descendant(
          of: find.byType(MdCodeBlock),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        scrollables.any((s) => s.scrollDirection == Axis.horizontal),
        isTrue,
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    testWidgets('a wide table does not overflow the page', (tester) async {
      final wide =
          StringBuffer('| ${List.filled(12, 'başlık').join(' | ')} |\n')
            ..write('| ${List.filled(12, '---').join(' | ')} |\n')
            ..write('| ${List.filled(12, 'değer').join(' | ')} |');

      await tester.pumpWidget(host(wide.toString()));
      expect(tester.takeException(), isNull);
    });
  });

  group('D11 — nothing is dropped silently', () {
    testWidgets('an HTML block is shown as inert source', (tester) async {
      await tester.pumpWidget(
        host('<div onclick="x()">\n  <script>alert(1)</script>\n</div>'),
      );

      expect(find.byType(MdRawHtmlBlock), findsOneWidget);
      // The source is visible…
      expect(find.textContaining('<script>', findRichText: true), findsWidgets);
      // …and it is explained rather than just dumped.
      expect(find.textContaining('never run'), findsOneWidget);
    });

    testWidgets('an unparseable BLOCK formula shows itself and says why', (
      tester,
    ) async {
      // Fences on their own lines — that is what a display block is, and what
      // the fixture uses. Writing it on one line makes it an inline node, and
      // an inline failure falls back to its source instead of a card.
      await tester.pumpWidget(host('\$\$\n\\frac{\\left(}{}\n\$\$'));
      await tester.pump();

      expect(find.byType(MdUnsupportedBlock), findsOneWidget);
      expect(find.textContaining('could not be typeset'), findsOneWidget);
    });

    testWidgets(r'$$…$$ on one line is display math, not $ + math + $', (
      tester,
    ) async {
      // Without a dedicated syntax the single-dollar rule matches the INNER
      // pair and leaves the outer dollars as literal text — visibly broken
      // output that only shows up on a real pasted document.
      await tester.pumpWidget(host(r'önce $$a + b$$ sonra'));

      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$', findRichText: true), findsNothing);
    });
  });

  group('D10 — a document is untrusted input', () {
    testWidgets('a javascript: link is not tappable', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: MarkdownView(
              document: parseMarkdown("[tıkla](javascript:alert('xss'))"),
              shrinkWrap: true,
              onOpenLink: opened.add,
            ),
          ),
        ),
      );

      expect(_recognizerCount(tester), 0, reason: 'no tap target was created');
      await tester.tap(find.textContaining('tıkla', findRichText: true));
      expect(opened, isEmpty);
    });

    testWidgets('a data: link is not tappable either', (tester) async {
      await tester.pumpWidget(host('[veri](data:text/html;base64,PHN2Zz4=)'));
      expect(_recognizerCount(tester), 0);
    });

    testWidgets('an https link IS tappable and reports its uri', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: MarkdownView(
              document: parseMarkdown('[site](https://alliswell.space)'),
              shrinkWrap: true,
              onOpenLink: opened.add,
            ),
          ),
        ),
      );

      await tester.tap(find.textContaining('site', findRichText: true));
      expect(opened.single.toString(), 'https://alliswell.space');
    });
  });

  group('D7 — themed from tokens, in both brightnesses', () {
    for (final brightness in Brightness.values) {
      testWidgets('the code panel takes its fill from the scheme '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(
          host('```dart\nvar a = 1;\n```', brightness: brightness),
        );

        final context = tester.element(find.byType(MdCodeBlock));
        final expected = Theme.of(context).colorScheme.surfaceContainerHighest;
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MdCodeBlock),
                matching: find.byType(Container),
              )
              .first,
        );

        expect((container.decoration! as BoxDecoration).color, expected);
      });
    }
  });
}

/// How many tappable spans the rendered document created. The security tests
/// assert on this rather than on "did a tap do nothing", because a span that
/// LOOKS like a link and swallows the tap is its own kind of lie.
int _recognizerCount(WidgetTester tester) {
  var count = 0;
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.recognizer is TapGestureRecognizer) count++;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return count;
}
