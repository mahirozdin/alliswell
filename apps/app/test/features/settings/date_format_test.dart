import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-174 — one formatter, one setting (DESIGN §17). The picker shows RESULTS,
/// and the choice reaches every surface that renders a date.
Future<Widget> signedInApp(FakeApi api) async {
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

void main() {
  setUp(() async {
    // localKv is a global singleton whose cache outlives a test.
    await localKv.remove('alliswell_date_format');
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the picker offers results, not patterns, and the row previews '
      'the choice', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();
    await openSettings(tester);

    // The row previews the CURRENT format with the shared sample instant.
    final row = find.byKey(const Key('settings-date-format'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          awFormatDateTime(kAwDateFormatSample, format: kAwSystemDateFormat),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();

    // Every option is the same instant in its own shape — and no ICU pattern is
    // ever shown to the user (D2).
    for (final spec in kAwDateFormats) {
      expect(find.byKey(Key('date-format-${spec.id}')), findsOneWidget);
    }
    expect(find.textContaining('dd.MM.yyyy'), findsNothing);
    expect(find.text('31.12.2026 23:59'), findsWidgets);

    await tester.tap(find.byKey(const Key('date-format-iso')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: row, matching: find.text('2026-12-31 23:59')),
      findsOneWidget,
      reason: 'the row must show what was just chosen',
    );
  });

  testWidgets('the choice reaches the task rows', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    // Inside Home's 30-day horizon, or the row would not be there at all.
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day + 5, 23, 59);
    api.seedTask(title: 'Beş gün sonra', dueAt: due.toUtc().toIso8601String());
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    // Default: follow the language (en in tests) — a 12h clock, no year (D4).
    final asSystem = awFormatShort(due, format: kAwSystemDateFormat);
    final asIso = awFormatShort(due, format: 'iso');
    expect(
      asSystem,
      isNot(asIso),
      reason: 'the test needs two shapes to tell apart',
    );
    expect(find.textContaining(asSystem), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.byKey(const Key('settings-date-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('date-format-iso')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The same row, now in the chosen format.
    expect(find.textContaining(asIso), findsOneWidget);
    expect(find.textContaining(asSystem), findsNothing);
  });
}
