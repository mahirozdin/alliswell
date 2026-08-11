import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:alliswell/src/features/notes/markdown/md_actions.dart';
import 'package:alliswell/src/features/notes/ui/modes/source_mode.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-250 — writing comfort on the Source surface (DESIGN §29 D17–D23).
void main() {
  NoteDocument docWith(String markdown) => NoteDocument(
    note: NoteDetail(
      id: 'n',
      workspaceId: 'w',
      title: 't',
      snippet: '',
      isPinned: false,
      isArchived: false,
      revision: 1,
      contentFormat: 'markdown',
      contentMarkdown: markdown,
    ),
  );

  Widget host(Widget child, {Size size = const Size(500, 900)}) =>
      ProviderScope(
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: Scaffold(body: child),
          ),
        ),
      );

  group('D18/D19 — one action list, several ways in', () {
    test('every toolbar action has a slash command', () {
      // D19: "the second path to every toolbar action, never the only one."
      for (final action in mdActions()) {
        expect(action.slash, startsWith('/'), reason: action.id);
      }
      final slashes = mdActions().map((a) => a.slash).toList();
      expect(slashes.toSet().length, slashes.length, reason: 'no duplicates');
    });

    test('a slash token is only recognised at a word boundary', () {
      // Otherwise a URL opens a command menu mid-typing.
      expect(slashTokenAt('/ta', 3), '/ta');
      expect(slashTokenAt('bir /ta', 7), '/ta');
      expect(slashTokenAt('https://a.dev', 13), isNull);
      expect(slashTokenAt('/ta bir', 7), isNull);
    });

    test('matching is by prefix, so /ta narrows to /table', () {
      expect(matchSlash('/ta').map((a) => a.id), contains('table'));
      expect(matchSlash('/table').single.id, 'table');
      expect(matchSlash('/zzz'), isEmpty);
      expect(matchSlash('table'), isEmpty, reason: 'needs the slash');
    });

    testWidgets('the phone gets a toolbar; a wide screen gets shortcuts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('metin');
      addTearDown(doc.dispose);
      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('md-toolbar')), findsOneWidget);
    });

    testWidgets('a toolbar button wraps the selection', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('kalın olacak');
      addTearDown(doc.dispose);
      doc.source.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('md-action-bold')));
      await tester.pumpAndSettle();

      expect(doc.source.text, '**kalın** olacak');
    });

    testWidgets('typing a slash opens the menu, picking it inserts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('');
      addTearDown(doc.dispose);
      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('note-source-field')),
        '/tab',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('md-slash-menu')), findsOneWidget);

      await tester.tap(find.byKey(const Key('md-slash-table')));
      await tester.pumpAndSettle();

      // The `/tab` the writer typed is gone; the table is there instead.
      expect(doc.source.text, isNot(contains('/tab')));
      expect(doc.source.text, contains('| --- |'));
      expect(find.byKey(const Key('md-slash-menu')), findsNothing);
    });
  });

  group('D17 — list automation, through the real field', () {
    testWidgets('Enter continues a list and renumbers it', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('1. bir');
      addTearDown(doc.dispose);
      doc.source.selection = const TextSelection.collapsed(offset: 6);

      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-source-field')));
      await tester.pumpAndSettle();
      doc.source.selection = const TextSelection.collapsed(offset: 6);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(doc.source.text, '1. bir\n2. ');
    });

    testWidgets('Tab nests the current item', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('- bir');
      addTearDown(doc.dispose);

      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-source-field')));
      await tester.pumpAndSettle();
      doc.source.selection = const TextSelection.collapsed(offset: 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(doc.source.text, '  - bir');
    });
  });

  group('D22 — counts are always available', () {
    testWidgets('the strip reports words and characters', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = docWith('bir iki üç');
      addTearDown(doc.dispose);
      await tester.pumpWidget(host(SourceMode(document: doc)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('md-count-strip')), findsOneWidget);
      expect(find.textContaining('3 words'), findsOneWidget);
    });
  });

  group('D23 — focus mode dims, it does not hide', () {
    test('the paragraph around the caret is found by blank lines', () {
      final controller = MdSourceController(text: 'bir\n\niki\n\nüç');
      addTearDown(controller.dispose);

      expect(controller.paragraphAt(0), (start: 0, end: 3));
      expect(controller.paragraphAt(6), (start: 5, end: 8));
      expect(controller.paragraphAt(11), (start: 10, end: 12));
    });

    testWidgets('dimming changes STYLE, never the text', (tester) async {
      final controller = MdSourceController(text: 'bir\n\niki')
        ..selection = const TextSelection.collapsed(offset: 6);
      addTearDown(controller.dispose);

      late BuildContext ctx;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      controller.focusMode = true;
      final span = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(color: Color(0xFF000000)),
        withComposing: false,
      );

      // Nothing is removed — that is the whole rule. Hiding causes reflow;
      // dimming does not.
      expect(span.toPlainText(), 'bir\n\niki');
      expect(span.children, hasLength(2));
    });
  });

  group('D18 — the command palette', () {
    Future<void> openPalette(WidgetTester tester, NoteDocument doc) async {
      await tester.pumpWidget(host(SourceMode(document: doc)));
      doc.source.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    test('every shortcut is bound on BOTH ⌘ and Ctrl', () {
      // The regression this test exists for: the actions declared a single
      // `meta: true` activator, so ⌘B worked on macOS and Ctrl+B did nothing
      // on Windows, Linux and web — while the field's own documentation said
      // "⌘/Ctrl". §22: an action nobody can reach is not a feature.
      final withShortcuts = mdActions().where((a) => a.shortcuts.isNotEmpty);
      expect(withShortcuts, isNotEmpty);
      for (final action in withShortcuts) {
        expect(
          action.shortcuts.any((s) => s.meta && !s.control),
          isTrue,
          reason: '${action.id} has no ⌘ binding',
        );
        expect(
          action.shortcuts.any((s) => s.control && !s.meta),
          isTrue,
          reason: '${action.id} has no Ctrl binding',
        );
      }
    });

    test('nothing else claims the palette\'s ⌘K', () {
      // The palette took the bare K; link moved to ⌘⇧K. If an action ever
      // takes it back, the palette becomes unreachable in silence.
      expect(mdPaletteShortcuts.every((s) => !s.shift), isTrue);
      for (final action in mdActions()) {
        final clash = action.shortcuts.any(
          (s) => s.trigger == LogicalKeyboardKey.keyK && !s.shift,
        );
        expect(clash, isFalse, reason: action.id);
      }
      final link = mdActions().firstWhere((a) => a.id == 'link');
      expect(link.shortcuts.every((s) => s.shift), isTrue);
    });

    test('the palette and the slash menu draw from one list', () {
      // Two matchers is how the two surfaces come to disagree about what
      // exists — the failure md_actions.dart's header is written against.
      expect(matchSlash('/'), hasLength(mdActions().length));
      expect(matchMdActions(''), hasLength(mdActions().length));
      expect(matchSlash('/ta').map((a) => a.id), ['table']);
      // A slash query is still prefix-only; a word query is not.
      expect(matchMdActions('/able'), isEmpty);
      expect(matchMdActions('able', label: (_) => '').map((a) => a.id), [
        'table',
      ]);
    });

    test('the palette matches the localized label, folded', () {
      // ADR-0013: neither SQLite nor MySQL folds ı→i, so folding is ours —
      // and a Turkish writer types "kalin" to find "Kalın".
      String label(MdAction a) =>
          const {'bold': 'Kalın', 'italic': 'İtalik'}[a.id] ?? a.id;
      for (final query in ['kalin', 'KALIN', 'Kalın']) {
        expect(
          matchMdActions(query, label: label).map((a) => a.id),
          contains('bold'),
          reason: query,
        );
      }
      expect(
        matchMdActions('İTALİK', label: label).map((a) => a.id),
        contains('italic'),
      );
    });

    testWidgets('Ctrl+K opens the palette and a pick applies the action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doc = docWith('hello');
      await openPalette(tester, doc);
      expect(find.byKey(const Key('md-palette-field')), findsOneWidget);

      await tester.tap(find.byKey(const Key('md-palette-bold')));
      await tester.pumpAndSettle();

      expect(doc.source.text, '**hello**');
    });

    testWidgets('the palette narrows, navigates and picks from the keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doc = docWith('hello');
      await openPalette(tester, doc);

      // Typing a word narrows by NAME, which is the thing the slash menu
      // cannot do — you have to know the command there.
      await tester.enterText(find.byKey(const Key('md-palette-field')), 'ital');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('md-palette-italic')), findsOneWidget);
      expect(find.byKey(const Key('md-palette-bold')), findsNothing);

      // Clear, then walk to the second row and take it with Enter.
      await tester.enterText(find.byKey(const Key('md-palette-field')), '');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(doc.source.text, '*hello*'); // italic, the second action
    });

    testWidgets('Escape leaves the document untouched', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doc = docWith('hello');
      await openPalette(tester, doc);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('md-palette-field')), findsNothing);
      expect(doc.source.text, 'hello');
    });

    testWidgets('an empty result says so instead of showing a blank list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doc = docWith('hello');
      await openPalette(tester, doc);

      await tester.enterText(
        find.byKey(const Key('md-palette-field')),
        'zzzznope',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('md-palette-empty')), findsOneWidget);
      expect(find.byKey(const Key('md-palette-list')), findsNothing);
    });
  });
}
