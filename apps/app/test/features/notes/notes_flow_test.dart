import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

Future<Widget> signedInAppWith(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> openNotes(WidgetTester tester) async {
  await tester.tap(find.text('Notes').last);
  await tester.pumpAndSettle();
}

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
    await tester.enterText(find.byKey(const Key('notes-search')), 'yumurta');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Alışveriş'), findsOneWidget);
    expect(find.text('Yayla planı'), findsNothing);
  });

  testWidgets('opening a note loads the quill editor with its content', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedNote(
        title: 'Detaylı not',
        contentDelta: [
          {
            'insert': 'Kalın kısım',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ],
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    await tester.tap(find.text('Detaylı not'));
    await tester.pumpAndSettle();

    expect(find.byType(QuillEditor), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Detaylı not'),
      findsOneWidget,
      reason: 'title loads into the app bar field',
    );

    // Markdown preview renders the converted delta, led by the title as H1.
    await tester.tap(find.byIcon(Icons.preview_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.textContaining('# Detaylı not'), findsOneWidget);
    expect(find.textContaining('**Kalın kısım**'), findsOneWidget);
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
    await tester.tap(find.byType(PopupMenuButton<String>));
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

  testWidgets('view toggle switches to A4 cards and persists the mode', (
    tester,
  ) async {
    final api = FakeApi()..seedNote(title: 'Kart notu', plainText: 'gövde');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openNotes(tester);

    expect(find.byType(GridView), findsNothing);
    await tester.tap(find.byKey(const Key('notes-view-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Kart notu'), findsOneWidget);
    expect(find.textContaining('Edited '), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('alliswell_notes_view_mode'), 'grid');
  });

  testWidgets('title edits autosave via PATCH after the debounce', (
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
    expect(
      api.requests.any((r) => r.startsWith('PATCH /api/v1/notes/')),
      isTrue,
    );
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
    expect(find.byType(QuillEditor), findsOneWidget);

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
