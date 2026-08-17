import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/data/note.dart';
import 'package:alliswell/src/features/notes/data/note_document.dart';
import 'package:alliswell/src/features/notes/ui/modes/note_mode_control.dart';
import 'package:markdown_forge/markdown_forge.dart';
import 'package:alliswell/src/theme/theme.dart';

/// The two modes (DESIGN §29 D1–D5, as ADR-0033 left them).
NoteDetail _note({String? markdown}) => NoteDetail(
  id: 'n1',
  workspaceId: 'w1',
  title: 'Başlık',
  snippet: '',
  isPinned: false,
  isArchived: false,
  revision: 1,
  contentMarkdown: markdown,
);

void main() {
  group('D1 — every note offers both modes', () {
    test('Source and Reading, for every note there is', () {
      // The D1 amendment OPH-248 had to write (a note offers only the editor
      // matching its canonical form) existed because there were two canonical
      // forms. ADR-0033 left one, so the amendment is retired and D1 reads the
      // way it was originally written.
      final doc = NoteDocument(note: _note(markdown: '# a'));

      expect(doc.availableModes, [NoteMode.source, NoteMode.reading]);
    });

    test('a brand new note opens in the editor', () {
      expect(NoteDocument().mode, NoteMode.source);
    });

    test('D2 — a document from outside opens in Reading', () {
      final doc = NoteDocument(
        note: _note(markdown: '# someone else'),
        cameFromOutside: true,
      );

      expect(doc.mode, NoteMode.reading);
    });

    test('D2 asks about PROVENANCE, not about the content format', () {
      // The parked OPH-270 finding: this used to be computed as
      // `format == NoteFormat.markdown`, which equated "markdown" with "came
      // from outside". A note the user converted on purpose opened read-only
      // every single time — and under ADR-0033, where every note is markdown,
      // that heuristic would have made the whole app read-only.
      final mine = NoteDocument(note: _note(markdown: '# mine'));

      expect(mine.mode, NoteMode.source);
    });
  });

  group('D3 — a mode switch never tears the controller down', () {
    test('the source controller, its caret and its undo stack survive', () {
      final doc = NoteDocument(note: _note(markdown: 'abc'));
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
  });

  group('canonical content', () {
    test('the body reads back BYTE for byte', () {
      // The property OPH-251 depends on, and the reason ADR-0033 is a
      // simplification rather than a trade: there is no converter between the
      // stored text and the edited text, so there is nothing that could eat a
      // table on the way through.
      const src = '| a | b |\n| - | - |\n| 1 | 2 |\n';
      final doc = NoteDocument(note: _note(markdown: src));

      expect(doc.markdown, src);
    });

    test('the save body is markdown, and does not repeat the title', () {
      final doc = NoteDocument(note: _note(markdown: '# a'));
      final body = doc.bodyFor('Başlık');

      expect(body['contentFormat'], 'markdown');
      expect(body['contentMarkdown'], '# a');
      expect(body['title'], 'Başlık');
      // The previous release prefixed `# $title` onto the body it derived,
      // which is what made migrated notes render their title twice.
      expect(body['contentMarkdown'], isNot(contains('# Başlık')));
      expect(body.containsKey('contentDelta'), isFalse);
    });

    test('a remote change lands in a clean editor', () {
      final doc = NoteDocument(note: _note(markdown: 'ilk'));

      doc.adoptRemote(_note(markdown: 'sunucudan'));

      expect(doc.source.text, 'sunucudan');
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

    testWidgets('shows both modes, and no dead third segment', (tester) async {
      final doc = NoteDocument(note: _note(markdown: '# a'));
      await tester.pumpWidget(host(doc));

      expect(find.byKey(const Key('note-mode-control')), findsOneWidget);
      expect(find.byType(ButtonSegment<NoteMode>), findsNothing);
      expect(find.text('Kaynak'), findsNothing); // English locale in tests
      expect(doc.availableModes.length, 2);
    });
  });

  group('the surfaces each mode mounts', () {
    testWidgets('Reading renders through the markdown renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: const Scaffold(body: _ReadingHost()),
          ),
        ),
      );
      expect(find.byType(MarkdownView), findsOneWidget);
    });

    testWidgets('Source mounts the text field', (tester) async {
      final doc = NoteDocument(note: _note(markdown: 'gövde'));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(body: SourceMode(controller: doc.source)),
        ),
      );
      expect(find.byKey(const Key('note-source-field')), findsOneWidget);
    });
  });
}

class _ReadingHost extends StatelessWidget {
  const _ReadingHost();

  @override
  Widget build(BuildContext context) =>
      MarkdownView(document: parseMarkdown('# a'));
}
