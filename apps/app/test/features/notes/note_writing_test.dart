import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/fold.dart';
import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/markdown/markdown_forge_adapters.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:markdown_forge/markdown_forge.dart';
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

    // Round 19 #3: the code-block button REPLACED the selection with an empty
    // fence. One report, but a whole class of bug — `_insertBlock` was shared
    // by /table and /divider too, and any future block action would have
    // inherited it. So the guard is class-wide rather than a case for the one
    // button that was reported.
    test('no action destroys the selected text', () {
      const before = 'önce\n';
      const selected = 'seçili satır';
      const after = '\nsonra';
      const text = '$before$selected$after';
      const start = before.length;
      const end = start + selected.length;

      for (final action in mdActions()) {
        final edit = action.apply(text, start, end);
        expect(
          edit.text,
          contains(selected),
          reason: '${action.id} lost the selection',
        );
        expect(edit.text, contains('önce'), reason: '${action.id} lost before');
        expect(edit.text, contains('sonra'), reason: '${action.id} lost after');
        expect(
          edit.selection,
          inInclusiveRange(0, edit.text.length),
          reason: '${action.id} put the caret outside the document',
        );
      }
    });

    test('the code button wraps the selection, and unwraps it again', () {
      final code = mdActions().firstWhere((a) => a.id == 'codeBlock');
      const text = 'bir satır';
      final wrapped = code.apply(text, 0, text.length);
      expect(wrapped.text, '```\nbir satır\n```');

      // Pressing it a second time on the same selection returns the original.
      final unwrapped = code.apply(wrapped.text, 0, wrapped.text.length);
      expect(unwrapped.text, text);
    });

    test('an empty selection still gets the empty fence', () {
      final code = mdActions().firstWhere((a) => a.id == 'codeBlock');
      expect(code.apply('', 0, 0).text, '```\n\n```\n');
    });

    test('/table and /divider land after the selection, not on top of it', () {
      const text = 'gövde metni';
      final table = mdActions().firstWhere((a) => a.id == 'table');
      expect(table.apply(text, 0, text.length).text, startsWith('$text\n|'));

      final divider = mdActions().firstWhere((a) => a.id == 'divider');
      expect(divider.apply(text, 0, text.length).text, '$text\n---\n');
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

    testWidgets('the toolbar is there at EVERY width now', (tester) async {
      // D18 originally put the bar above the keyboard on a phone and gave a
      // wide screen nothing but shortcuts, which was fine while the rich
      // editor owned the top of the screen. ADR-0033 took that editor away, so
      // "shortcuts are enough" would have left a desktop window with no
      // visible formatting controls at all. One bar, always mounted.
      for (final width in [500.0, 1200.0]) {
        final doc = docWith('metin');
        addTearDown(doc.dispose);
        await tester.pumpWidget(
          host(MdEditorToolbar(controller: doc.source), size: Size(width, 900)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('md-toolbar')),
          findsOneWidget,
          reason: 'no toolbar at ${width}px',
        );
      }
    });

    testWidgets('a toolbar button wraps the selection', (tester) async {
      final doc = docWith('kalın olacak');
      addTearDown(doc.dispose);
      doc.source.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      await tester.pumpWidget(host(MdEditorToolbar(controller: doc.source)));
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
      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
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

      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
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

      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
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
      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
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
      // dimming does not. Asserted on the TEXT rather than on the number of
      // spans, because live syntax (OPH-274) splits the same characters into
      // more of them: the invariant is that a TextEditingController must hand
      // back exactly the characters of `text`, or every caret offset after the
      // first difference points at the wrong character.
      expect(span.toPlainText(), 'bir\n\niki');

      // …and the two paragraphs really are painted differently.
      final colors = span.children!
          .map((c) => (c as TextSpan).style?.color)
          .toSet();
      expect(
        colors.length,
        greaterThan(1),
        reason: 'the paragraph without the caret must be dimmed',
      );
    });
  });

  group('D18 — the command palette', () {
    Future<void> openPalette(WidgetTester tester, NoteDocument doc) async {
      await tester.pumpWidget(host(SourceMode(controller: doc.source)));
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
      // and a Turkish writer types "kalin" to find "Kalın". The fold is passed
      // EXPLICITLY now (OPH-274): the package's default is plain lowercase,
      // because a package cannot assume Turkish, and the app hands its own
      // fold in through `MarkdownStrings.fold` — which is what this pins.
      String label(MdAction a) =>
          const {'bold': 'Kalın', 'italic': 'İtalik'}[a.id] ?? a.id;
      for (final query in ['kalin', 'KALIN', 'Kalın']) {
        expect(
          matchMdActions(
            query,
            label: label,
            fold: foldSearchText,
          ).map((a) => a.id),
          contains('bold'),
          reason: query,
        );
      }
      expect(
        matchMdActions(
          'İTALİK',
          label: label,
          fold: foldSearchText,
        ).map((a) => a.id),
        contains('italic'),
      );
      // And the app really does hand it in: the strings the scope mounts
      // carry ADR-0013's fold, not the package default.
      expect(awMarkdownStrings().fold('KALIN'), 'kalin');
      expect(awMarkdownStrings().fold('Işık'), 'isik');
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
