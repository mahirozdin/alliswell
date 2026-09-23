import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-333 — the widget's "+" (`alliswell://add`).
///
/// The URL table is unit-tested in deep_link_test.dart. These drive the REAL
/// router, because the promise is about what the person sees: the app comes
/// forward with the create sheet open, exactly once — and nothing is written
/// until they save, because a link only ever navigates (ADR-0016).
Future<Widget> _app(FakeApi api, {List<Override> extra = const []}) async {
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
      ...extra,
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  GoRouter routerOf() => GoRouter.of(awRootNavigatorKey.currentContext!);

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a warm "+" opens the create sheet once and drops the request', (
    tester,
  ) async {
    wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    expect(find.byType(TaskCreateSheet), findsNothing);

    routerOf().go('alliswell://add');
    await tester.pumpAndSettle();

    expect(find.byType(TaskCreateSheet), findsOneWidget);
    // The request is not a place: the location is plain Home, so a rebuild,
    // a tab switch or a web reload cannot open a second sheet.
    expect(routerOf().state.uri.toString(), '/home');
    expect(find.text('error.routeNotFound'.tr()), findsNothing);
    // A navigation, not a write: the person has not typed anything yet.
    expect(api.tasks, isEmpty);

    // Closing the sheet ends it — nothing reopens it, the request was spent.
    Navigator.of(tester.element(find.byType(TaskCreateSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TaskCreateSheet), findsNothing);
    routerOf().go('/home');
    await tester.pumpAndSettle();
    expect(find.byType(TaskCreateSheet), findsNothing);
    expect(api.tasks, isEmpty);
  });

  testWidgets('a COLD start on "+" opens the sheet once the session is back', (
    tester,
  ) async {
    // The real cold-start shape: the OS hands the URL over as the initial
    // route, and a restoring session parks it until auth has an answer.
    wide(tester);
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'alliswell://add';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    expect(find.byType(TaskCreateSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(TaskCreateSheet))).pop();
    await tester.pumpAndSettle();
    expect(routerOf().state.uri.toString(), '/home');
  });

  testWidgets('a role without tasks.create lands on Home, not in a sheet', (
    tester,
  ) async {
    // The FAB hides itself from such a role (EE-052); a link must not hand
    // it a sheet it could not save. The URL is input, not an instruction.
    wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(
      await _app(
        api,
        extra: [
          canProvider.overrideWith(
            (ref, permission) => permission != 'tasks.create',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    routerOf().go('alliswell://add');
    await tester.pumpAndSettle();

    expect(find.byType(TaskCreateSheet), findsNothing);
    expect(routerOf().state.uri.toString(), '/home');
  });
}
