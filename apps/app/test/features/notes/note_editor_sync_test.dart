import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../support/note_sync_server.dart';
import 'notes_flow_test_support.dart';

/// The 2026-11-18 report, end to end through the real editor (OPH-488…493,
/// ADR-0072): one person types a new note on one computer. It must never say
/// "edited on another device too", and no typed text may go missing — not
/// over a slow network, not while a push is in flight, not when the note is
/// closed right after typing.
void main() {
  AwDatabase dbOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  ).read(databaseProvider);

  Finder conflictSnack() => find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data ?? '').contains(RegExp('another device|başka bir cihazda')),
  );

  Future<void> newNote(WidgetTester tester, NoteSyncServer api) async {
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  final source = find.byKey(const Key('note-source-field'));

  testWidgets('OPH-488: a new note typed over a slow network reaches the '
      'server whole, with no conflict', (tester) async {
    final api = NoteSyncServer();
    await newNote(tester, api);

    // The create's push is held: every save behind it waits on the wire.
    api.gate = Completer<void>();
    await tester.enterText(find.byKey(const Key('note-title')), 'Toplantı');
    await tester.pump(const Duration(seconds: 2));
    await tester.enterText(source, 'Birinci paragraf.');
    await tester.pump(const Duration(seconds: 2));
    await tester.enterText(source, 'Birinci paragraf. İkinci paragraf.');
    await tester.pump(const Duration(seconds: 2));
    api.gate!.complete();
    api.gate = null;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      api.notes.single['contentMarkdown'],
      'Birinci paragraf. İkinci paragraf.',
    );
    expect(api.versions.where((v) => v['origin'] == 'conflict'), isEmpty);
    expect(conflictSnack(), findsNothing);
    expect(find.byKey(const Key('note-conflict-banner')), findsNothing);
    expect(
      await dbOf(tester).select(dbOf(tester).pendingMutations).get(),
      isEmpty,
    );
  });

  testWidgets('OPH-488: text typed while a push is in flight is never lost', (
    tester,
  ) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Not');
    await tester.enterText(source, 'A.');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    api.gate = Completer<void>();
    await tester.enterText(source, 'A. B.');
    await tester.pump(const Duration(seconds: 2)); // this save's push is held
    await tester.enterText(source, 'A. B. C.');
    await tester.pump(const Duration(seconds: 2)); // lands while it is out
    api.gate!.complete();
    api.gate = null;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(api.notes.single['contentMarkdown'], 'A. B. C.');
    expect(api.versions.where((v) => v['origin'] == 'conflict'), isEmpty);
    expect(conflictSnack(), findsNothing);
  });

  testWidgets('OPH-488: a push whose answer was lost does not swallow the '
      'next save', (tester) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Not');
    await tester.enterText(source, 'Bir.');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    api.loseNextAnswer = true; // the server applies "Bir. İki." — no answer
    await tester.enterText(source, 'Bir. İki.');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.enterText(source, 'Bir. İki. Üç.');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 70)); // the backoff retry
    await tester.pumpAndSettle();

    expect(api.notes.single['contentMarkdown'], 'Bir. İki. Üç.');
    expect(api.versions.where((v) => v['origin'] == 'conflict'), isEmpty);
  });

  testWidgets('OPH-491: closing the editor right after typing keeps the last '
      'words', (tester) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Toplantı');
    await tester.enterText(source, 'Birinci yarı.');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.enterText(source, 'Birinci yarı. İkinci yarı.');
    await tester.pump(const Duration(milliseconds: 300)); // < autosave delay
    final db = dbOf(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final row = (await db.select(db.notes).get()).single;
    expect(row.contentMarkdown, 'Birinci yarı. İkinci yarı.');
    expect(api.notes.single['contentMarkdown'], 'Birinci yarı. İkinci yarı.');
  });

  testWidgets('OPH-493: moving the cursor is not an edit — nothing is pushed', (
    tester,
  ) async {
    final api = NoteSyncServer()
      ..seedNote(
        title: 'Var olan',
        contentMarkdown: 'birinci satır\nikinci satır',
        contentFormat: 'markdown',
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);
    await tester.tap(find.text('Var olan'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final before = api.processed.length;

    final r = tester.getRect(source);
    await tester.tapAt(r.topLeft + const Offset(20, 10));
    await tester.pump(const Duration(seconds: 2));
    await tester.tapAt(r.topLeft + const Offset(60, 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(api.processed.length, before);
  });

  testWidgets('OPH-492: a real conflict in a /notes/new session shows its '
      'banner there', (tester) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Ortak');
    await tester.enterText(source, 'A\nM\nN');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-conflict-banner')), findsNothing);

    // Another device rewrites the note before this one pulls it.
    api.foreignWrite(api.notes.single['id'] as String, 'A\nM\nX');
    await tester.enterText(source, 'A\nM\nY');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(api.versions.where((v) => v['origin'] == 'conflict'), hasLength(1));
    expect(find.byKey(const Key('note-conflict-banner')), findsOneWidget);
  });

  testWidgets('OPH-490: "use the other one" puts the server text on the '
      'device, and the next edit does not bring the refused text back', (
    tester,
  ) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Ortak');
    await tester.enterText(source, 'A\nM\nN');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final noteId = api.notes.single['id'] as String;
    api.foreignWrite(noteId, 'A\nM\nX');
    await tester.enterText(source, 'A\nM\nY');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10)); // the snackbar leaves
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conflict-use-theirs')));
    await tester.pumpAndSettle();

    final db = dbOf(tester);
    final row = (await db.select(db.notes).get()).single;
    expect(row.contentMarkdown, 'A\nM\nX');
    expect(row.conflictVersionId, isNull);
    expect(find.byKey(const Key('note-conflict-banner')), findsNothing);
    final editor = tester.widget<EditableText>(
      find.descendant(of: source, matching: find.byType(EditableText)),
    );
    expect(editor.controller.text, 'A\nM\nX');

    await tester.enterText(source, 'A\nM\nX\nZ');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.notes.single['contentMarkdown'], 'A\nM\nX\nZ');
  });

  testWidgets('OPH-490: "use the other one" while still typing drops that '
      'typing — the choice is not reversed by the next autosave', (
    tester,
  ) async {
    final api = NoteSyncServer();
    await newNote(tester, api);
    await tester.enterText(find.byKey(const Key('note-title')), 'Ortak');
    await tester.enterText(source, 'A\nM\nN');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    api.foreignWrite(api.notes.single['id'] as String, 'A\nM\nX');
    await tester.enterText(source, 'A\nM\nY');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    await tester.enterText(source, 'A\nM\nY daha');
    await tester.pump(const Duration(milliseconds: 300)); // within the debounce
    await tester.tap(find.byKey(const Key('conflict-use-theirs')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(api.notes.single['contentMarkdown'], 'A\nM\nX');
    final editor = tester.widget<EditableText>(
      find.descendant(of: source, matching: find.byType(EditableText)),
    );
    expect(editor.controller.text, 'A\nM\nX');
  });

  testWidgets('OPH-489: a change pulled into a clean editor is adopted, and '
      'not saved back up as an edit', (tester) async {
    final api = NoteSyncServer()
      ..seedNote(
        title: 'Var olan',
        contentMarkdown: 'ilk hali',
        contentFormat: 'markdown',
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);
    await tester.tap(find.text('Var olan'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final before = api.processed.length;

    api.foreignWrite(api.notes.single['id'] as String, 'başka cihazdan');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    unawaited(container.read(syncEngineProvider)!.syncNow());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final editor = tester.widget<EditableText>(
      find.descendant(of: source, matching: find.byType(EditableText)),
    );
    expect(editor.controller.text, 'başka cihazdan');
    expect(api.processed.length, before, reason: 'adopting is not typing');
  });
}
