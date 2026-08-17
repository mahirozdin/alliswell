import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/markdown/markdown_forge_adapters.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-254 — the four mermaid cases the conformance fixture carries.
void main() {
  final fixture = File(
    'test/fixtures/markdown_conformance.md',
  ).readAsStringSync();

  Widget host(String markdown, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: buildAwTheme(brightness),
        // OPH-274: the renderer's words come from the host through
        // `MarkdownStrings`. Without the scope the package falls back to its
        // English defaults, and this suite would be measuring those.
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

  String fence(String body) => '```mermaid\n$body\n```';

  testWidgets('a mermaid fence becomes a diagram, not a code block', (
    tester,
  ) async {
    await tester.pumpWidget(host(fence('flowchart TD\n  A --> B')));

    expect(find.byType(MermaidView), findsOneWidget);
    expect(
      find.byKey(const Key('md-copy-code')),
      findsNothing,
      reason: 'a diagram is not source to copy',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fixture flowchart draws', (tester) async {
    await tester.pumpWidget(
      host(
        fence('''
flowchart TD
    A[Paylaşılan metin] --> B{AI yapılandırılmış mı?}
    B -->|evet| C[Bubble + onay kartı]
    B -->|hayır| D[Inbox'a kaydet]
    D --> E([Sebebi söyleyen diyalog])
    C --> F[Görev]
    E --> F'''),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(MdUnsupportedBlock), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fixture sequence diagram draws', (tester) async {
    await tester.pumpWidget(
      host(
        fence('''
sequenceDiagram
    participant U as Uzantı
    participant G as App Group
    U->>G: payload yazar
    G-->>U: payload
    U->>U: oku-ve-sil'''),
      ),
    );

    expect(find.byType(MdUnsupportedBlock), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('D11 — two failures, two different sentences', () {
    testWidgets('a declined TYPE names itself', (tester) async {
      await tester.pumpWidget(host(fence('gantt\n  title x\n  section y')));

      expect(find.byType(MdUnsupportedBlock), findsOneWidget);
      // Naming the type is the point: the reader learns WHICH diagram is
      // affected and that waiting is the answer.
      expect(find.textContaining('gantt'), findsWidgets);
      expect(find.textContaining('not drawn yet'), findsOneWidget);
    });

    testWidgets('an UNREADABLE diagram says something else entirely', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(fence('flowchart TD\n  A[Kapanmamış --> B\n  B -->')),
      );

      expect(find.byType(MdUnsupportedBlock), findsOneWidget);
      expect(find.textContaining('could not be read'), findsOneWidget);
      // Sending the reader to wait for a feature when their own line is
      // broken would be the wrong destination.
      expect(find.textContaining('not drawn yet'), findsNothing);
    });

    testWidgets('either way the source stays readable', (tester) async {
      await tester.pumpWidget(host(fence('pie\n  "a" : 10')));

      expect(find.textContaining('"a" : 10', findRichText: true), findsWidgets);
    });
  });

  group('D7/D8', () {
    for (final brightness in Brightness.values) {
      testWidgets('draws in ${brightness.name} without overflowing', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            fence('flowchart LR\n  A[bir] --> B[iki] --> C[üç] --> D[dört]'),
            brightness: brightness,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a wide diagram scrolls inside its own box', (tester) async {
      await tester.pumpWidget(
        host(
          fence(
            'flowchart LR\n'
            '  A[bir uzunca etiket] --> B[ikinci uzunca etiket]\n'
            '  B --> C[üçüncü uzunca etiket]\n'
            '  C --> D[dördüncü uzunca etiket]',
          ),
        ),
      );

      final scrollables = tester.widgetList<SingleChildScrollView>(
        find.descendant(
          of: find.byType(MermaidView),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        scrollables.any((s) => s.scrollDirection == Axis.horizontal),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the whole fixture still renders with diagrams in it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A ProviderScope is REQUIRED: images resolve through Riverpod. This test
    // caught that — the equivalent in `aw_markdown_test.dart` was passing only
    // because its shorter viewport never built the image blocks.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(body: MarkdownView(document: parseMarkdown(fixture))),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
