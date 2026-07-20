import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../features/auth/test_support.dart';
import '../features/projects/fake_api.dart';
import '../support/sync_overrides.dart';

/// OPH-167 — per-screen search over the fold engine (DESIGN §12).
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

/// Type into a search field and ride out its 250 ms debounce.
Future<void> search(WidgetTester tester, Key field, String query) async {
  await tester.enterText(find.byKey(field), query);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  final soon = isoAt(DateTime.now().add(const Duration(days: 2, hours: 12)));

  testWidgets('home search folds Turkish and gathers tasks, captures and '
      'meetings into one ranked list', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    final tag = api.seedTag(name: 'Çay');
    api.seedTask(title: 'Çay siparişi', dueAt: soon); // title hit
    api.seedTask(
      title: 'Mutfak alışverişi',
      dueAt: soon,
      tagIds: [tag['id'] as String], // tag hit
    );
    api.seedTask(
      title: 'Toplantı notları',
      description: 'çay servisi unutulmasın', // body hit
      dueAt: soon,
    );
    api.seedTask(title: 'Fikir: çay makinesi', status: 'inbox'); // capture
    api.seedTask(title: 'Alakasız iş', dueAt: soon);
    api.seedExternalEvent(
      summary: 'Çay tedarikçisi görüşmesi',
      startsAt: soon,
      endsAt: isoAt(DateTime.now().add(const Duration(days: 2, hours: 13))),
    );
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await search(tester, const Key('home-search'), 'cay'); // ASCII in…
    expect(find.byKey(const Key('home-search-results')), findsOneWidget);
    expect(find.text('Çay siparişi'), findsOneWidget); // …Turkish out
    expect(find.text('Mutfak alışverişi'), findsOneWidget);
    expect(find.text('Toplantı notları'), findsOneWidget);
    expect(find.text('Fikir: çay makinesi'), findsOneWidget); // inbox included
    expect(find.text('Çay tedarikçisi görüşmesi'), findsOneWidget); // event
    expect(find.text('Alakasız iş'), findsNothing);
    // Honest match context for the non-title hits (S3).
    expect(find.text('#Çay'), findsWidgets);
    expect(find.textContaining('çay servisi'), findsOneWidget);

    // No hits → an honest empty state, not a blank void (S4).
    await search(tester, const Key('home-search'), 'zzz yok');
    expect(find.text('No results'), findsOneWidget);

    // Clearing restores the exact prior list (S5).
    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-search-results')), findsNothing);
    expect(find.text('Alakasız iş'), findsOneWidget);
  });

  testWidgets('projects search filters and ranks by fold', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedProject(name: 'Yazılım Araçları');
    api.seedProject(name: 'Ev İşleri');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('Ev İşleri'), findsOneWidget);

    await search(tester, const Key('projects-search'), 'yazilim');
    expect(find.text('Yazılım Araçları'), findsOneWidget);
    expect(find.text('Ev İşleri'), findsNothing);
  });

  testWidgets('notes search folds title and body', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    api.seedNote(title: 'Çay tarifleri');
    api.seedNote(title: 'Alışveriş', plainText: 'yeşil çay ve süt al');
    api.seedNote(title: 'Alakasız not');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    await search(tester, const Key('notes-search'), 'cay');
    expect(find.text('Çay tarifleri'), findsOneWidget); // title fold hit
    expect(find.text('Alışveriş'), findsOneWidget); // body fold hit
    expect(find.text('Alakasız not'), findsNothing);
  });
}
