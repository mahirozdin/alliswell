import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/notes/ui/notes_screen.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// Shared harness for the notes screens — the same shape `notes_flow_test`
/// uses, extracted so a second file need not copy it.
Future<Widget> signedInAppWith(FakeApi api) async {
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

Future<void> openNotes(WidgetTester tester) async {
  await tester.tap(find.text('Notes').last);
  await tester.pumpAndSettle();
}

/// The note titles as the list actually renders them, top to bottom — the only
/// honest way to assert an ORDER (asserting the store's output would test the
/// comparator twice and the screen never).
List<String> titlesInOrder(WidgetTester tester) => tester
    .widgetList<NoteTile>(find.byType(NoteTile))
    .map((tile) => tile.note.title)
    .toList();
