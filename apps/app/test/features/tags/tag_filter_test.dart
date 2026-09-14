import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-306 — tapping a tag shows that tag's work.
///
/// Tags shipped in v0.4.0 and their chips have been on every row since, doing
/// nothing when touched. The report that changed that named the gesture: *"when
/// i click the label tag, automatically sorts, and listed by the order of
/// priority"*.
///
/// The rule these tests exist to hold is Epic 17's, and it is the same one the
/// selected calendar day already obeys: **a filter you can no longer see must
/// not keep filtering.** So the filter says its own name on screen, carries the
/// way to drop it, and never survives into a session where nobody can find it.
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

Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String isoAt(DateTime local) => local.toUtc().toIso8601String();

void main() {
  final today = DateTime.now();
  final soon = isoAt(DateTime(today.year, today.month, today.day, 18));

  /// Two tags, three tasks: two carry #rapor, one carries #ev.
  FakeApi seeded() {
    final api = FakeApi();
    final rapor = api.seedTag(name: 'rapor');
    final ev = api.seedTag(name: 'ev');
    api.seedTask(
      title: 'Raporu yaz',
      dueAt: soon,
      tagIds: [rapor['id'] as String],
    );
    api.seedTask(
      title: 'Raporu gönder',
      dueAt: soon,
      tagIds: [rapor['id'] as String],
    );
    api.seedTask(title: 'Çamaşır', dueAt: soon, tagIds: [ev['id'] as String]);
    return api;
  }

  testWidgets('tapping a tag chip keeps that tag and drops the rest', (
    tester,
  ) async {
    await wideSurface(tester);
    await tester.pumpWidget(await app(seeded()));
    await tester.pumpAndSettle();

    expect(find.text('Çamaşır'), findsOneWidget);

    await tester.tap(find.text('#rapor').first);
    await tester.pumpAndSettle();

    expect(find.text('Raporu yaz'), findsOneWidget);
    expect(find.text('Raporu gönder'), findsOneWidget);
    expect(
      find.text('Çamaşır'),
      findsNothing,
      reason:
          'a tag filter that leaves the other work in place filters nothing',
    );
  });

  testWidgets('the filter says its own name and carries the way out', (
    tester,
  ) async {
    await wideSurface(tester);
    await tester.pumpWidget(await app(seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#rapor').first);
    await tester.pumpAndSettle();

    // Visible, named, and dismissible — the selected-day rule, applied to tags.
    final bar = find.byKey(const Key('tag-filter-bar'));
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.textContaining('rapor')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('tag-filter-clear')));
    await tester.pumpAndSettle();

    expect(bar, findsNothing);
    expect(find.text('Çamaşır'), findsOneWidget, reason: 'clearing restores');
  });

  testWidgets(
    'the filter and the sort compose — the whole ask, in one gesture',
    (tester) async {
      await wideSurface(tester);
      final api = FakeApi();
      final rapor = api.seedTag(name: 'rapor');
      // Chronologically: "sonra" is the earlier one. By priority it is not.
      api.seedTask(
        title: 'Acil rapor',
        dueAt: isoAt(DateTime(today.year, today.month, today.day, 20)),
        priority: 'urgent',
        tagIds: [rapor['id'] as String],
      );
      api.seedTask(
        title: 'Sakin rapor',
        dueAt: isoAt(DateTime(today.year, today.month, today.day, 9)),
        priority: 'low',
        tagIds: [rapor['id'] as String],
      );
      await tester.pumpWidget(await app(api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('#rapor').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('list-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort-option-priority')));
      await tester.pumpAndSettle();

      // "when i click the label tag, automatically sorts, and listed by the
      // order of priority" — the report, satisfied without a second mode: the
      // filter narrows the set and OPH-305's order runs on what is left.
      final urgent = tester.getTopLeft(find.text('Acil rapor')).dy;
      final low = tester.getTopLeft(find.text('Sakin rapor')).dy;
      expect(urgent, lessThan(low));
    },
  );

  testWidgets('a tag with nothing left to show says so', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    final rapor = api.seedTag(name: 'rapor');
    api.seedTask(
      title: 'Raporu yaz',
      dueAt: soon,
      tagIds: [rapor['id'] as String],
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#rapor').first);
    await tester.pumpAndSettle();

    // Complete the only match; the list must not fall back to a blank screen
    // that reads as "you have nothing to do" while a filter is on.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tag-filter-bar')), findsOneWidget);
    expect(find.byKey(const Key('tag-filter-empty')), findsOneWidget);
  });
}
