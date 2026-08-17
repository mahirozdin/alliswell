import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:markdown_forge/markdown_forge.dart';

import '../projects/fake_api.dart';
import 'notes_flow_test_support.dart';

void main() {
  testWidgets('notes list renders, pinned chip and search filter the list', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(
        title: 'Yayla planı',
        plainText: 'Pokut rotası',
        isPinned: true,
      )
      ..seedNote(title: 'Alışveriş', plainText: 'süt ve yumurta');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    expect(find.text('Yayla planı'), findsOneWidget);
    expect(find.text('Alışveriş'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget); // pinned = filled star
    expect(find.byIcon(Icons.star_border), findsOneWidget);

    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    expect(find.text('Yayla planı'), findsOneWidget);
    expect(find.text('Alışveriş'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    // The field lives behind the app-bar search icon now (round 13 #5).
    await tester.tap(find.byKey(const Key('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notes-search')), 'yumurta');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Alışveriş'), findsOneWidget);
    expect(find.text('Yayla planı'), findsNothing);
  });

  testWidgets('opening a note loads the editor with its content', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(title: 'Detaylı not', contentMarkdown: '**Kalın kısım**');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    await tester.tap(find.text('Detaylı not'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-source-field')), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Detaylı not'),
      findsOneWidget,
      reason: 'title loads into the app bar field',
    );

    // OPH-248 replaced the monospace "preview" sheet with a real Reading mode.
    // The old assertion looked for the markdown SOURCE (`# Detaylı not`,
    // `**Kalın kısım**`); a rendered document shows neither, because the marks
    // have become a heading and bold text — which is the entire point.
    expect(find.byKey(const Key('note-mode-control')), findsOneWidget);
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(
      find.byKey(const Key('note-source-field')),
      findsNothing,
      reason: 'D4: Reading is never editable-looking',
    );
    expect(
      find.textContaining('Kalın kısım', findRichText: true),
      findsWidgets,
      reason: 'the text survives; only its asterisks are gone',
    );
    expect(
      find.textContaining('**Kalın kısım**', findRichText: true),
      findsNothing,
      reason: 'rendered, not shown as source',
    );
  });

  testWidgets('star quick-pins from the list; archive menu hides the note', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(title: 'Yıldızlanacak', plainText: 'içerik');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    // Quick pin via the leading star — no editor round-trip.
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();
    expect(api.notes.single['isPinned'], isTrue);
    expect(find.byIcon(Icons.star), findsOneWidget);

    // Archive via the row menu (the chip also says "Archive" — target the
    // menu item, which mounts later in the overlay) → leaves the default list…
    // By KEY, not by type: OPH-251 put a second PopupMenuButton in this app
    // bar ("open a file"), so a type finder is now ambiguous — and would stay
    // ambiguous every time the screen grows another menu.
    await tester.tap(find.byKey(Key('note-menu-${api.notes.single['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    expect(api.notes.single['isArchived'], isTrue);
    expect(find.text('Yıldızlanacak'), findsNothing);

    // …and shows up under the Archive chip.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Yıldızlanacak'), findsOneWidget);
  });

  // OPH-272: the owner went looking for the export "where archive and delete
  // are" — the row menu — and it was only inside the editor's overflow.
  testWidgets('a note can be exported to PDF from its row menu', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(title: 'Dışa aktarılacak', plainText: 'gövde');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    await tester.tap(find.byKey(Key('note-menu-${api.notes.single['id']}')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('note-row-export-${api.notes.single['id']}')),
      findsOneWidget,
      reason:
          'export belongs beside archive and delete, not only in the editor',
    );
    expect(find.text('Export as PDF'), findsOneWidget);
  });

  testWidgets('view toggle switches to A4 cards and persists the mode', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Kart notu', plainText: 'gövde');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    expect(find.byType(GridView), findsNothing);
    // OPH-258: view and order share one app-bar menu now (§34 L2) — the bar
    // was at the phone's limit, so the order could not arrive as a sixth icon.
    await tester.tap(find.byKey(const Key('list-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('sort-option-sort.viewSection:grid')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Kart notu'), findsOneWidget);
    expect(find.textContaining('Edited '), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alliswell_notes_view_mode'), 'grid');
  });

  testWidgets('title edits autosave through the outbox after the debounce', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Eski başlık', plainText: 'gövde');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    await tester.tap(find.text('Eski başlık'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('note-title')), 'Yeni başlık');
    await tester.pump(const Duration(seconds: 2)); // debounce fires
    await tester.pumpAndSettle();

    expect(api.notes.single['title'], 'Yeni başlık');
    expect(api.requests.any((r) => r.contains('/sync/push')), isTrue);
  });

  testWidgets('FAB creates a new note on first autosave (POST)', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-source-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note-title')), 'Sıfırdan not');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(api.notes, hasLength(1));
    expect(api.notes.single['title'], 'Sıfırdan not');
  });

  testWidgets('project detail Notes tab lists the project notes', (
    tester,
  ) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Kitap');
    api.seedNote(title: 'Bölüm taslağı', projectId: project['id'] as String);

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitap'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes').last); // the tab, not the nav rail
    await tester.pumpAndSettle();
    expect(find.text('Bölüm taslağı'), findsOneWidget);
  });
}
