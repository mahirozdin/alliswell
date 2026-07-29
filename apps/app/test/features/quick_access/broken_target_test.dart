import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/integrations/providers.dart';
import 'package:alliswell/src/features/projects/ui/project_detail_screen.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-203 — what a shortcut does when its target is gone, archived, or the
/// device is offline.
Future<Widget> signedInApp(
  FakeApi api, {
  bool linkOpens = true,
  List<Uri>? opened,
}) async {
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
      urlLauncherProvider.overrideWithValue((url) async {
        opened?.add(url);
        return linkOpens;
      }),
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
  testWidgets('a shortcut whose target is gone says so and offers removal', (
    tester,
  ) async {
    final api = FakeApi();
    // A target the replica has never seen — the race window between a delete
    // elsewhere and the server's cascade arriving here.
    api.seedQuickLink(
      kind: 'project',
      targetId: '01GHOSTGHOSTGHOSTGHOSTGHOS',
      title: 'Kayıp proje',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.text('Kayıp proje'), findsOneWidget);
    expect(find.text('Source deleted'), findsOneWidget);

    await tester.tap(find.text('Kayıp proje'));
    await tester.pumpAndSettle();

    // It does not navigate nowhere; it offers to clean itself up.
    expect(find.byType(ProjectDetailScreen), findsNothing);
    expect(
      find.text("This shortcut's source no longer exists."),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Kayıp proje'), findsNothing);
  });

  testWidgets('an archived target still opens — archives are reversible', (
    tester,
  ) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Arşivli');
    project['status'] = 'archived';
    api.seedQuickLink(
      kind: 'project',
      targetId: project['id'] as String,
      title: 'Arşivli',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.text('Source deleted'), findsNothing);
    await tester.tap(find.text('Arşivli').first);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
  });

  testWidgets('an external link opens in the browser', (tester) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );
    final opened = <Uri>[];

    wide(tester);
    await tester.pumpWidget(await signedInApp(api, opened: opened));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Site'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://alliswell.space');
  });

  testWidgets('a link that cannot open says so instead of failing silently', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api, linkOpens: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Site'));
    await tester.pumpAndSettle();
    // The launcher's boolean was ignored app-wide until now; offline it is a
    // false, and the OS says nothing at all.
    expect(find.text("You're offline — the link can't open"), findsOneWidget);
  });
}
