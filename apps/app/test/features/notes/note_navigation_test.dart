import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/markdown/markdown_forge_adapters.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-249 — navigating a long document (DESIGN §29 D13–D16).
void main() {
  String longDocument({int sections = 40}) {
    final buffer = StringBuffer('# Belge\n\ngiriş\n\n');
    for (var i = 0; i < sections; i++) {
      buffer
        ..writeln('## Bölüm $i')
        ..writeln()
        ..writeln('gövde metni $i, biraz uzunca olsun diye yazılmış bir satır.')
        ..writeln();
    }
    return buffer.toString();
  }

  // The scope is part of the host (OPH-274): the outline's words come from
  // the app's MarkdownStrings, and this suite asserts on the APP's copy —
  // "No headings yet." — not the package's English fallback.
  Widget host(Widget child, {Size size = const Size(1200, 800)}) =>
      ProviderScope(
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: Builder(
              builder: (context) => MarkdownForge(
                theme: awMarkdownTheme(context),
                strings: awMarkdownStrings(),
                child: Scaffold(body: child),
              ),
            ),
          ),
        ),
      );

  group('D13 — the outline', () {
    testWidgets('is a side panel at ≥ 900 px', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(ReadingMode(markdown: longDocument())));
      await tester.pump();

      expect(find.byKey(const Key('note-outline')), findsOneWidget);
      expect(find.byKey(const Key('note-outline-button')), findsNothing);
    });

    testWidgets('is a sheet on a phone, reached from one button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          ReadingMode(markdown: longDocument(sections: 6)),
          size: const Size(420, 900),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('note-outline')), findsNothing);
      await tester.tap(find.byKey(const Key('note-outline-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-outline')), findsOneWidget);
      expect(find.text('Bölüm 0'), findsWidgets);
    });

    testWidgets(
      'a document with no headings says so instead of showing a gap',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(const ReadingMode(markdown: 'sadece düz metin\n')),
        );
        await tester.pump();

        expect(find.text('No headings yet.'), findsOneWidget);
      },
    );

    testWidgets('tapping a heading scrolls the document to it', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(ReadingMode(markdown: longDocument())));
      await tester.pumpAndSettle();

      final list = find.byType(Scrollable).last;
      final before = tester.widget<Scrollable>(list).controller!.offset;

      // Far enough down the DOCUMENT to require a jump, but near enough the
      // top of the OUTLINE that its lazy list has built the row to tap.
      await tester.tap(find.text('Bölüm 12').first);
      await tester.pumpAndSettle();

      final after = tester.widget<Scrollable>(list).controller!.offset;
      expect(
        after,
        greaterThan(before),
        reason: 'the estimate-and-correct jump should have moved the document',
      );
    });
  });

  group('D14 — folding is a view, never a write', () {
    testWidgets('collapsing a section hides its body and nothing else', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const src = '# Bir\n\ngizlenecek gövde\n\n# İki\n\nkalacak gövde\n';
      await tester.pumpWidget(host(const ReadingMode(markdown: src)));
      await tester.pumpAndSettle();

      expect(find.textContaining('gizlenecek gövde'), findsOneWidget);

      await tester.tap(find.byKey(const Key('outline-fold-bir')));
      await tester.pumpAndSettle();

      expect(find.textContaining('gizlenecek gövde'), findsNothing);
      expect(find.textContaining('kalacak gövde'), findsOneWidget);
      // The heading itself never disappears — folding a section you cannot
      // then unfold would be a trap.
      expect(find.text('Bir'), findsWidgets);
    });

    testWidgets('unfolding brings the body back', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const src = '# Bir\n\ngövde\n';
      await tester.pumpWidget(host(const ReadingMode(markdown: src)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('outline-fold-bir')));
      await tester.pumpAndSettle();
      expect(find.textContaining('gövde'), findsNothing);

      await tester.tap(find.byKey(const Key('outline-fold-bir')));
      await tester.pumpAndSettle();
      expect(find.textContaining('gövde'), findsOneWidget);
    });
  });

  group('D15 — find & replace', () {
    test('finds every match, case-insensitively', () {
      const text = 'Kurulum, kurulum ve KURULUM.';
      expect(findMatches(text, 'kurulum'), hasLength(3));
      expect(findMatches(text, 'yok'), isEmpty);
      expect(findMatches(text, ''), isEmpty);
    });

    test('replace-all rewrites every match in ONE string', () {
      // One assignment is what makes one undo enough (D20's principle, a rule
      // early).
      expect(replaceAllMatches('bir iki bir', 'bir', 'üç'), 'üç iki üç');
      expect(replaceAllMatches('abc', 'yok', 'x'), 'abc');
    });

    test('replacement is not fold-insensitive', () {
      // Searching to READ folds ı→i (ADR-0013). Searching to REWRITE must not:
      // replacing `ısı` when somebody typed `isi` would edit text they never
      // meant to touch.
      expect(findMatches('ısı', 'isi'), isEmpty);
    });

    testWidgets('the bar counts matches and steps through them', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'bir iki bir üç bir');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(FindReplaceBar(target: controller, onClose: () {})),
      );
      await tester.enterText(find.byKey(const Key('note-find-field')), 'bir');
      await tester.pumpAndSettle();

      expect(find.text('1 of 3'), findsOneWidget);
      // The hit is SELECTED, not merely counted.
      expect(controller.selection.baseOffset, 0);

      await tester.tap(find.byKey(const Key('note-find-next')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(controller.selection.baseOffset, 8);
    });

    testWidgets('replace all rewrites the target', (tester) async {
      final controller = TextEditingController(text: 'bir iki bir');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          FindReplaceBar(target: controller, showReplace: true, onClose: () {}),
        ),
      );
      await tester.enterText(find.byKey(const Key('note-find-field')), 'bir');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-replace-field')), 'üç');
      await tester.tap(find.byKey(const Key('note-replace-all')));
      await tester.pumpAndSettle();

      expect(controller.text, 'üç iki üç');
    });

    testWidgets('Source mode opens it with the keyboard', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = NoteDocument(
        note: NoteDetail(
          id: 'n',
          workspaceId: 'w',
          title: 't',
          snippet: '',
          isPinned: false,
          isArchived: false,
          revision: 1,
          contentMarkdown: 'bir iki bir',
        ),
      );
      addTearDown(doc.dispose);

      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
      await tester.pumpAndSettle();
      expect(find.byType(FindReplaceBar), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(FindReplaceBar), findsOneWidget);
    });
  });
}
