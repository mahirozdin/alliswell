import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/widgets/document_surface.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-271 — while a note is open, nothing floats over it.
///
/// Reported plainly: "not yazma ve düzenleme ekranında FAB butonların tamamı
/// görünmez olmalı". The section FAB, the AI button and the quick-access
/// bubble all live ABOVE the editor — the first two because the editor is a
/// route inside the shell's Scaffold, the third because it wraps the whole
/// app — so all three had to learn the same thing.
Future<Widget> app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('which routes are documents', () {
    test('every way into the editor counts', () {
      // Four entry points, and the last one is the one a path list forgets.
      expect(awIsDocumentRoute('/notes/new'), isTrue);
      expect(awIsDocumentRoute('/notes/file'), isTrue);
      expect(awIsDocumentRoute('/notes/01J8Z9ABCDEF'), isTrue);
      expect(awIsDocumentRoute('/edit-note/01J8Z9ABCDEF'), isTrue);
      // The import preview is a document one tap before it becomes a note.
      expect(awIsDocumentRoute('/notes/import'), isTrue);
    });

    test('the lists are not', () {
      expect(awIsDocumentRoute('/notes'), isFalse);
      expect(awIsDocumentRoute('/home'), isFalse);
      expect(awIsDocumentRoute('/files'), isFalse);
      expect(awIsDocumentRoute('/projects/01J8Z9ABCDEF'), isFalse);
      expect(awIsDocumentRoute('/settings'), isFalse);
    });
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_notes_sort');
  });

  testWidgets('opening a note hides every floating control, and closing it '
      'brings them back', (tester) async {
    phone(tester);
    final api = FakeApi()..seedNote(title: 'Yazılacak not');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    expect(
      find.byType(FloatingActionButton),
      findsWidgets,
      reason: 'the list offers "new note"',
    );

    await tester.tap(find.text('Yazılacak not'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-title')), findsOneWidget);
    expect(
      find.byType(FloatingActionButton),
      findsNothing,
      reason: 'a screen for writing is not a screen for starting something new',
    );
    expect(find.byType(QuickAccessBubble), findsNothing);

    // Back out: the controls belong to the list, and they come back with it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsWidgets);
  });

  testWidgets('a brand-new note hides them from the first frame', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(await app(FakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    // The "+" is the way in, so it must survive its own tap and then go.
    await tester.tap(find.byType(FloatingActionButton).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-title')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
