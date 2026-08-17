import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/ui/note_conflict_banner.dart';
import 'package:alliswell/src/features/notes/ui/note_versions_screen.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-269 — version history and the conflict banner (DESIGN §35).
///
/// The promises under test: history reads as days rather than rows, a restore
/// asks first and says what it does, the banner offers four choices and NONE
/// of them destroys anything, and offline the screen says so instead of
/// showing an empty list (V6).

const noteId = '01NOTEAAAAAAAAAAAAAAAAAAAA';

Future<Widget> hostWith(FakeApi api, Widget child) async {
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
    child: MaterialApp(theme: buildAwTheme(Brightness.light), home: child),
  );
}

void main() {
  testWidgets('history groups by day and names where each version came from', (
    tester,
  ) async {
    final api = FakeApi();
    final today = DateTime.now();
    api.seedNoteVersion(
      noteId: noteId,
      origin: 'edit',
      createdAt: today.toUtc(),
    );
    api.seedNoteVersion(
      noteId: noteId,
      origin: 'merge',
      createdAt: today.subtract(const Duration(days: 1)).toUtc(),
    );
    api.seedNoteVersion(
      noteId: noteId,
      origin: 'conflict',
      createdAt: today.subtract(const Duration(days: 9)).toUtc(),
    );

    await tester.pumpWidget(
      await hostWith(api, const NoteVersionsScreen(noteId: noteId)),
    );
    await tester.pumpAndSettle();

    // Day headers, not a flat list of timestamps.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // Origins are named in the user's words, never as raw enum values.
    expect(find.text('Merged'), findsOneWidget);
    expect(find.text('Conflict'), findsOneWidget);
    expect(find.textContaining('device'), findsOneWidget);
  });

  testWidgets('restoring asks first, and says that nothing is lost', (
    tester,
  ) async {
    final api = FakeApi();
    final version = api.seedNoteVersion(noteId: noteId, markdown: 'eski gövde');

    await tester.pumpWidget(
      await hostWith(api, const NoteVersionsScreen(noteId: noteId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('version-${version['id']}')));
    await tester.pumpAndSettle();

    // The preview reads the version in the note's own reading renderer.
    expect(find.textContaining('eski gövde'), findsOneWidget);

    await tester.tap(find.byKey(const Key('version-restore')));
    await tester.pumpAndSettle();
    // V5's sentence lives in the dialog, where the decision is made.
    expect(find.textContaining('Nothing is lost'), findsOneWidget);

    await tester.tap(find.byKey(const Key('version-restore-cancel')));
    await tester.pumpAndSettle();
    expect(api.restoreCalls, isEmpty);

    await tester.tap(find.byKey(const Key('version-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('version-restore-confirm')));
    await tester.pumpAndSettle();

    expect(api.restoreCalls.single['mode'], 'replace');
    expect(api.restoreCalls.single['versionId'], version['id']);
  });

  testWidgets('“restore as a copy” sends the copy mode, not replace', (
    tester,
  ) async {
    final api = FakeApi();
    final version = api.seedNoteVersion(noteId: noteId);
    await tester.pumpWidget(
      await hostWith(api, const NoteVersionsScreen(noteId: noteId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('version-${version['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('version-restore-copy')));
    await tester.pumpAndSettle();

    expect(api.restoreCalls.single['mode'], 'copy');
  });

  testWidgets('the diff toggle draws the server’s segments', (tester) async {
    final api = FakeApi();
    final version = api.seedNoteVersion(noteId: noteId);
    await tester.pumpWidget(
      await hostWith(api, const NoteVersionsScreen(noteId: noteId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('version-${version['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('version-diff-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('version-diff')), findsOneWidget);
    // Drawn, not computed here: the words came from the fake server.
    expect(find.textContaining('yeni'), findsOneWidget);
  });

  testWidgets('offline it says history is online — never an empty list', (
    tester,
  ) async {
    final api = FakeApi()..offline = true;
    await tester.pumpWidget(
      await hostWith(api, const NoteVersionsScreen(noteId: noteId)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('versions-offline')), findsOneWidget);
    expect(find.text('No history yet'), findsNothing);
  });

  group('the conflict banner', () {
    Future<void> pumpBanner(WidgetTester tester, FakeApi api) async {
      await tester.pumpWidget(
        await hostWith(
          api,
          const Scaffold(
            body: NoteConflictBanner(
              noteId: noteId,
              conflictVersionId: 'VER00000000000000000000001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers four choices and promises none of them deletes', (
      tester,
    ) async {
      await pumpBanner(tester, FakeApi());
      expect(find.textContaining('edited on another device'), findsOneWidget);
      expect(find.textContaining('nothing is deleted'), findsOneWidget);
      for (final key in [
        'conflict-show-diff',
        'conflict-use-mine',
        'conflict-use-theirs',
        'conflict-keep-both',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
    });

    testWidgets('“use mine” restores my refused body as the new head', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpBanner(tester, api);
      await tester.tap(find.byKey(const Key('conflict-use-mine')));
      await tester.pumpAndSettle();
      expect(api.restoreCalls.single['mode'], 'replace');
    });

    testWidgets('“keep both” is the copy — a chosen outcome, not automatic', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpBanner(tester, api);
      await tester.tap(find.byKey(const Key('conflict-keep-both')));
      await tester.pumpAndSettle();
      expect(api.restoreCalls.single['mode'], 'copy');
    });

    testWidgets('“use the other one” writes NOTHING — the server already won', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpBanner(tester, api);
      await tester.tap(find.byKey(const Key('conflict-use-theirs')));
      await tester.pumpAndSettle();
      // No restore, no create: only the local pointer is cleared, and my body
      // is still in the server's history if this turns out to be wrong.
      expect(api.restoreCalls, isEmpty);
    });
  });
}
