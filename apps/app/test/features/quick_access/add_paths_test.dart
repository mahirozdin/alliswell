import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_add.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-201 — how a shortcut is born (and unborn) from the entity surfaces.
Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await resetQuickAccessPrefs();
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

void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('quickLinkUri (pure)', () {
    test('completes a bare host and keeps a real address', () {
      expect(
        quickLinkUri('alliswell.space').toString(),
        'https://alliswell.space',
      );
      expect(
        quickLinkUri('www.example.com').toString(),
        'https://www.example.com',
      );
      expect(
        quickLinkUri('http://example.com/a?b=c').toString(),
        'http://example.com/a?b=c',
      );
      expect(quickLinkUri('  https://x.dev  ').toString(), 'https://x.dev');
    });

    test('refuses what is not an http(s) address', () {
      for (final input in [
        '',
        '   ',
        'javascript:alert(1)',
        'mailto:a@b.c',
        'file:///etc/passwd',
      ]) {
        expect(quickLinkUri(input), isNull, reason: 'must refuse "$input"');
      }
    });
  });

  testWidgets('the project menu adds, then offers to remove', (tester) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Ahmet');

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    // Projects section, row menu.
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('project-menu-${project['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('Add to quick access'), findsOneWidget);
    await tester.tap(find.text('Add to quick access'));
    await tester.pumpAndSettle();

    // It reached the server as a quick_link create, and the rail shows it.
    final created = api.pushedMutations.where(
      (m) => m['entityType'] == 'quick_link' && m['operation'] == 'create',
    );
    expect(created, hasLength(1));
    expect((created.single['patch'] as Map)['kind'], 'project');
    expect(find.byKey(const Key('quick-rail-header')), findsOneWidget);

    // Second visit: the same entry now offers the inverse. There is no
    // "add again" — a target is on the rail or it is not.
    await tester.tap(find.byKey(Key('project-menu-${project['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('Add to quick access'), findsNothing);
    expect(find.text('Remove from quick access'), findsOneWidget);
    await tester.tap(find.text('Remove from quick access'));
    await tester.pumpAndSettle();

    expect(
      api.pushedMutations.where(
        (m) => m['entityType'] == 'quick_link' && m['operation'] == 'delete',
      ),
      hasLength(1),
    );
  });

  testWidgets('the note menu carries the same toggle', (tester) async {
    final api = FakeApi();
    api.seedNote(title: 'Toplantı notu');

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to quick access'));
    await tester.pumpAndSettle();

    final created = api.pushedMutations.where(
      (m) => m['entityType'] == 'quick_link' && m['operation'] == 'create',
    );
    expect(created, hasLength(1));
    expect((created.single['patch'] as Map)['kind'], 'note');
  });

  testWidgets('the rail + button adds an external link, host as the name', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(kind: 'url', url: 'https://x.dev/seed', title: 'Seed');

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-rail-add')));
    await tester.pumpAndSettle();

    // A scheme we refuse says so instead of silently storing junk.
    await tester.enterText(
      find.byKey(const Key('quick-link-url')),
      'javascript:alert(1)',
    );
    await tester.tap(find.byKey(const Key('quick-link-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an http or https address'), findsOneWidget);

    // A bare host is completed, and an empty name falls back to it.
    await tester.enterText(
      find.byKey(const Key('quick-link-url')),
      'alliswell.space',
    );
    await tester.tap(find.byKey(const Key('quick-link-save')));
    await tester.pumpAndSettle();

    final created = api.pushedMutations
        .where((m) => m['entityType'] == 'quick_link')
        .map((m) => m['patch'] as Map)
        .toList();
    expect(created, hasLength(1));
    expect(created.single['url'], 'https://alliswell.space');
    expect(created.single['title'], 'alliswell.space');
    expect(find.text('alliswell.space'), findsWidgets);
  });

  testWidgets('a full rail refuses honestly instead of silently', (
    tester,
  ) async {
    final api = FakeApi();
    for (var i = 0; i < 50; i++) {
      api.seedQuickLink(kind: 'url', url: 'https://x.dev/$i', title: 'L$i');
    }
    final project = api.seedProject(name: 'Ahmet');

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('project-menu-${project['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to quick access'));
    await tester.pumpAndSettle();

    expect(find.text('50-shortcut limit — remove one first'), findsOneWidget);
    expect(
      api.pushedMutations.where(
        (m) => m['entityType'] == 'quick_link' && m['operation'] == 'create',
      ),
      isEmpty,
    );
  });
}
