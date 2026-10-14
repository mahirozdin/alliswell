import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/data/note_store.dart';
import 'package:alliswell/src/features/notes/providers.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// "Delete note" in the editor's overflow menu: present for a saved note,
/// always behind the shared confirmation, and wired to the same store delete
/// as the app-bar trash.
class _RecordingNoteStore extends NoteStore {
  _RecordingNoteStore(super.db, super.poke, this.deleted);

  final List<String> deleted;

  @override
  Future<void> delete(String noteId) async {
    deleted.add(noteId);
    await super.delete(noteId);
  }
}

Future<Widget> _app(FakeApi api, List<String> deleted) async {
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
      noteStoreProvider.overrideWith(
        (ref) =>
            _RecordingNoteStore(ref.watch(databaseProvider), () {}, deleted),
      ),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> _openTheNote(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Notes').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _chooseDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('note-quick-menu')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('note-delete')), findsOneWidget);
  await tester.tap(find.byKey(const Key('note-delete')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelling the menu delete keeps the note', (tester) async {
    final api = FakeApi()..seedNote(title: 'Kalacak not');
    final deleted = <String>[];

    await tester.pumpWidget(await _app(api, deleted));
    await _openTheNote(tester, 'Kalacak not');
    await _chooseDelete(tester);

    // The shared confirmation, with its question and what it means.
    expect(find.text('Delete note?'), findsOneWidget);
    expect(
      find.text('This note will be deleted from all your devices.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('note-delete-confirm')), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete note?'), findsNothing);
    expect(deleted, isEmpty);
    // Still in the editor.
    expect(find.byKey(const Key('note-quick-menu')), findsOneWidget);
  });

  testWidgets('confirming the menu delete removes the note and leaves', (
    tester,
  ) async {
    final api = FakeApi();
    final note = api.seedNote(title: 'Gidecek not');
    final deleted = <String>[];

    await tester.pumpWidget(await _app(api, deleted));
    await _openTheNote(tester, 'Gidecek not');
    await _chooseDelete(tester);

    await tester.tap(find.byKey(const Key('note-delete-confirm')));
    await tester.pumpAndSettle();

    expect(deleted, [note['id']]);
    // Back on the list, the editor gone and the note with it.
    expect(find.byKey(const Key('note-quick-menu')), findsNothing);
    expect(find.text('Gidecek not'), findsNothing);
  });

  testWidgets('the app-bar trash uses the same confirmation', (tester) async {
    final api = FakeApi()..seedNote(title: 'Çöp kutusu');
    final deleted = <String>[];

    await tester.pumpWidget(await _app(api, deleted));
    await _openTheNote(tester, 'Çöp kutusu');
    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();

    expect(
      find.text('This note will be deleted from all your devices.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
  });
}
