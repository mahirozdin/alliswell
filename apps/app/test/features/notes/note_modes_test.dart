import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:alliswell/src/features/notes/markdown/aw_markdown.dart';
import 'package:alliswell/src/features/notes/ui/modes/note_mode_control.dart';
import 'package:alliswell/src/features/notes/ui/modes/source_mode.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-248 — the three modes (DESIGN §29 D1–D5).
NoteDetail _note({
  String format = 'delta',
  String? markdown,
  List<Map<String, dynamic>>? delta,
}) => NoteDetail(
  id: 'n1',
  workspaceId: 'w1',
  title: 'Başlık',
  snippet: '',
  isPinned: false,
  isArchived: false,
  revision: 1,
  contentFormat: format,
  contentMarkdown: markdown,
  contentDelta: delta,
);

void main() {
  group('D1, as amended — a note offers the modes it can honour', () {
    test('a Delta-canonical note offers Live and Reading, never Source', () {
      final doc = NoteDocument(note: _note());

      expect(doc.availableModes, [NoteMode.live, NoteMode.reading]);
      expect(doc.availableModes, isNot(contains(NoteMode.source)));
    });

    test('a markdown-canonical note offers Source and Reading, never Live', () {
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: '# a'),
      );

      expect(doc.availableModes, [NoteMode.source, NoteMode.reading]);
      expect(doc.availableModes, isNot(contains(NoteMode.live)));
    });

    test('asking for a mode the note cannot honour does nothing', () {
      // Not "throws", and not "shows a disabled segment" — the mode simply is
      // not on offer. A dead affordance is what §22 forbids.
      final doc = NoteDocument(note: _note());
      doc.setMode(NoteMode.source);

      expect(doc.mode, isNot(NoteMode.source));
    });
  });

  group('D2 — the default mode follows where the document came from', () {
    test('a note written here opens in its editor', () {
      expect(
        NoteDocument.defaultModeFor(NoteFormat.delta, cameFromOutside: false),
        NoteMode.live,
      );
      expect(
        NoteDocument.defaultModeFor(
          NoteFormat.markdown,
          cameFromOutside: false,
        ),
        NoteMode.source,
      );
    });

    test('a document from outside opens in Reading', () {
      expect(
        NoteDocument.defaultModeFor(NoteFormat.markdown, cameFromOutside: true),
        NoteMode.reading,
      );
    });
  });

  group('D3 — a switch preserves the caret, and therefore the undo history', () {
    test('the controllers are never torn down by a mode switch', () {
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: 'abc'),
      );
      final source = doc.source;
      source.selection = const TextSelection.collapsed(offset: 2);

      doc
        ..setMode(NoteMode.reading)
        ..setMode(NoteMode.source);

      // Identical instance, so the caret, the selection and Flutter's own undo
      // stack all continue — the mechanism is not restoring state, it is never
      // destroying it.
      expect(identical(doc.source, source), isTrue);
      expect(doc.source.selection.baseOffset, 2);
    });

    test('the quill controller survives too', () {
      final doc = NoteDocument(note: _note());
      final quill = doc.quill;

      doc
        ..setMode(NoteMode.reading)
        ..setMode(NoteMode.live);

      expect(identical(doc.quill, quill), isTrue);
    });
  });

  group('canonical content', () {
    test('a markdown note reads back BYTE for byte, not round-tripped', () {
      // The property OPH-251 depends on: a table is not something our Delta
      // converters can express, so a round trip would silently eat it.
      const src = '| a | b |\n| - | - |\n| 1 | 2 |\n';
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: src),
      );

      expect(doc.markdown, src);
    });

    test('a delta note DERIVES its markdown for reading', () {
      final doc = NoteDocument(
        note: _note(
          delta: [
            {
              'insert': 'kalın',
              'attributes': {'bold': true},
            },
            {'insert': '\n'},
          ],
        ),
      );

      expect(doc.markdown, contains('**kalın**'));
    });

    test('the save body always carries the format', () {
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: '# a'),
      );

      expect(doc.bodyFor('Başlık')['contentFormat'], 'markdown');
      expect(doc.bodyFor('Başlık')['contentMarkdown'], '# a');
    });
  });

  group('the conversion door', () {
    test('delta → markdown flattens into the source, and switches mode', () {
      final doc = NoteDocument(
        note: _note(
          delta: [
            {
              'insert': 'kalın',
              'attributes': {'bold': true},
            },
            {'insert': '\n'},
          ],
        ),
      );

      doc.convert();

      expect(doc.format, NoteFormat.markdown);
      expect(doc.source.text, contains('**kalın**'));
      expect(doc.mode, NoteMode.source);
      expect(doc.availableModes, [NoteMode.source, NoteMode.reading]);
    });

    test('markdown → delta parses what markdown can express', () {
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: '**kalın**\n'),
      );

      doc.convert();

      expect(doc.format, NoteFormat.delta);
      expect(doc.mode, NoteMode.live);
      expect(doc.deltaJson.first['attributes'], containsPair('bold', true));
    });
  });

  group('the mode control (D1: one control, never hidden)', () {
    Widget host(NoteDocument doc) => MaterialApp(
      theme: buildAwTheme(Brightness.light),
      home: Scaffold(
        body: NoteModeControl(
          modes: doc.availableModes,
          active: doc.mode,
          onChanged: doc.setMode,
        ),
      ),
    );

    testWidgets('shows exactly the modes on offer', (tester) async {
      await tester.pumpWidget(host(NoteDocument(note: _note())));

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Source'), findsNothing);
    });

    testWidgets('a markdown note shows Source instead of Live', (tester) async {
      await tester.pumpWidget(
        host(
          NoteDocument(
            note: _note(format: 'markdown', markdown: 'a'),
          ),
        ),
      );

      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
    });
  });

  group('D5 — split view is wide-screen only, and syncs both ways', () {
    Widget host(NoteDocument doc, Size size) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(body: SourceMode(document: doc)),
      ),
    );

    testWidgets('the toggle is absent on a narrow screen', (tester) async {
      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: 'a'),
      );
      await tester.pumpWidget(host(doc, const Size(500, 900)));

      expect(find.byKey(const Key('note-split-toggle')), findsNothing);
      expect(find.byKey(const Key('note-source-field')), findsOneWidget);
    });

    testWidgets('at ≥ 900 px the toggle appears and opens a second pane', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final doc = NoteDocument(
        note: _note(format: 'markdown', markdown: '# Başlık\n\ngövde'),
      );
      await tester.pumpWidget(host(doc, const Size(1200, 900)));

      expect(find.byKey(const Key('note-split-preview')), findsNothing);
      await tester.tap(find.byKey(const Key('note-split-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-split-preview')), findsOneWidget);
      expect(find.byType(AwMarkdown), findsOneWidget);
      // Still ONE control's worth of surface: the split is a toggle inside
      // Source, not a fourth mode.
      expect(find.byKey(const Key('note-source-field')), findsOneWidget);
    });
  });
}
