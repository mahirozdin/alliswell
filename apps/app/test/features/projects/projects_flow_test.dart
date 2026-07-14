import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import 'fake_api.dart';

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

Future<void> openProjects(WidgetTester tester) async {
  await tester.tap(find.text('Projects').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('projects list renders items with status and favorites', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedProject(name: 'Website', isFavorite: true)
      ..seedProject(name: 'Ev İşleri', status: 'paused');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Ev İşleri'), findsOneWidget);
    expect(find.text('paused'), findsOneWidget); // non-active status shown
    expect(find.byIcon(Icons.star), findsOneWidget); // favorite filled
    expect(find.byIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('FAB create flow posts to the API and refreshes the list', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    expect(find.text('No projects yet'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Yeni Proje',
    );
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Proje'), findsOneWidget);
    expect(
      api.requests.where(
        (r) => r == 'POST /api/v1/workspaces/${api.workspaceId}/projects',
      ),
      hasLength(1),
    );
  });

  testWidgets('favorite star toggles via PATCH', (tester) async {
    final api = FakeApi()..seedProject(name: 'Yıldızsız');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(api.projects.single['isFavorite'], isTrue);
    expect(
      api.requests.any((r) => r.startsWith('PATCH /api/v1/projects/')),
      isTrue,
    );
  });

  testWidgets('tapping a project opens the detail tab skeleton', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedProject(name: 'Detaylı', description: 'Açıklama metni');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    await tester.tap(find.text('Detaylı'));
    await tester.pumpAndSettle();

    // 'Notes' also exists as a nav label — scope tab assertions to the TabBar.
    Finder inTabBar(String label) =>
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    expect(inTabBar('Overview'), findsOneWidget);
    expect(inTabBar('Tasks'), findsOneWidget);
    expect(inTabBar('Notes'), findsOneWidget);
    expect(find.text('Açıklama metni'), findsOneWidget);

    // Tasks tab is the OPH-037 placeholder for now.
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OPH-037'), findsOneWidget);
  });
}
