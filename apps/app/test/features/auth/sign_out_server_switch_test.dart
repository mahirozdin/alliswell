import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/core/server_url.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../support/sync_overrides.dart';
import '../projects/fake_api.dart';
import 'test_support.dart';

/// OPH-390 (E-01, E-02) — sign-out and a server change leave nothing of the
/// old account on screen.
///
/// The persona review found sign-out doing nothing on iOS: with the sync
/// engines running, `AuthController.logout` read `syncEnginesProvider` — a
/// provider that itself hangs off the session — and Riverpod refused the loop.
/// A server change ran the same sign-out, AFTER moving the address, so the old
/// refresh token went to the new server and the team chrome of the old one
/// stayed above somebody else's list. Saving a server on the sign-in screen
/// popped GoRouter's last page.
///
/// Every assertion here is about the outcome — who is signed in, what the
/// replica holds, which server heard what — not about a debug-only assert, so
/// the behaviour they pin holds in a release build too.
void main() {
  // The built-in address: nothing to hydrate, so the start is quiet.
  final oldServer = compiledApiBaseUrl;
  const newServer = 'https://other.example.com';

  Future<void> wideSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Every auth request, with the server it went to.
  late List<String> authCalls;
  late InMemorySecretStore store;
  late bool refuseRefresh;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.removeWhere((_) => true);
    authCalls = [];
    store = InMemorySecretStore();
    refuseRefresh = false;
  });

  /// The full app, signed in as user-1 on [oldServer] with the sync engines
  /// running (the shell watches them). The auth client follows the address
  /// exactly as the real one does, so a server change rebuilds it.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    await wideSurface(tester);
    if (signedIn) await TokenStorage(store).save(fakeSession());
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          authApiProvider.overrideWith((ref) {
            final base = ref.watch(apiBaseUrlProvider);
            final dio = fakeDio(
              FakeHttpClientAdapter((options, body) async {
                authCalls.add('$base ${options.path}');
                if (options.path == '/api/v1/auth/logout') {
                  return emptyBody(204);
                }
                if (options.path == '/api/v1/auth/refresh' && refuseRefresh) {
                  return jsonBody(401, {
                    'statusCode': 401,
                    'code': 'AUTH_REFRESH_INVALID',
                  });
                }
                return jsonBody(200, sessionJson());
              }),
            );
            dio.options.baseUrl = base;
            return AuthApi(dio);
          }),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    );
    if (signedIn) {
      expect(container.read(apiBaseUrlProvider), oldServer);
      expect(container.read(currentUserIdProvider), 'user-1');
      // The engines are running — the state the sign-out used to die in.
      expect(container.read(syncEnginesProvider), isNotEmpty);
      expect(container.read(runningSyncEnginesProvider), isNotEmpty);
    }
    return container;
  }

  /// Lets the sign-out's awaits (storage, the replica wipe) finish.
  Future<void> settleSignOut(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('E-01: Settings → Sign out signs out while the engines run', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await tester.runAsync(
      () => localKv.set('${kWorkspacesCachePrefix}user-1', '[]'),
    );
    container.read(routerProvider).go('/settings');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await settleSignOut(tester);

    expect(tester.takeException(), isNull);
    expect(container.read(authControllerProvider).value, isNull);
    expect(find.text('Sign in to your space'), findsOneWidget);
    // Every engine stopped; the person's facts are gone. (An engine the
    // covered shell still held is let go when that shell rebuilds.)
    expect(
      container.read(runningSyncEnginesProvider).every((e) => e.isStopped),
      isTrue,
    );
    expect(
      await tester.runAsync(
        () => localKv.get('${kWorkspacesCachePrefix}user-1'),
      ),
      isNull,
    );
    expect(await tester.runAsync(() => localKv.get(kReplicaOwnerKey)), isNull);
    // Nothing wrote into the wiped replica afterwards — no engine started
    // again for the workspace that just left.
    final db = container.read(databaseProvider);
    expect(
      await tester.runAsync(() => db.select(db.syncStates).get()),
      isEmpty,
    );
    expect(authCalls, contains('$oldServer /api/v1/auth/logout'));
  });

  testWidgets('E-01: a session that runs out lands on sign-in', (tester) async {
    final container = await pumpApp(tester);
    refuseRefresh = true;
    await tester.runAsync(
      () => container.read(authRepositoryProvider).refreshAccessToken(),
    );
    await settleSignOut(tester);

    expect(tester.takeException(), isNull);
    expect(container.read(authControllerProvider).value, isNull);
    expect(find.text('Sign in to your space'), findsOneWidget);
    expect(container.read(syncEnginesProvider), isEmpty);
    expect(container.read(runningSyncEnginesProvider), isEmpty);
  });

  testWidgets(
    'E-01: changing the server in Settings signs out on the OLD server first, '
    'then nothing of the old account is left',
    (tester) async {
      final container = await pumpApp(tester);
      // The old server's capability list, cached for this person: where the
      // team chrome comes from.
      await tester.runAsync(
        () => localKv.set('${kEeStatusCachePrefix}user-1', '{"teams":true}'),
      );
      container.read(routerProvider).go('/settings/account');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('server-url-tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('server-url-field')),
        newServer,
      );
      await tester.tap(find.text('Save'));
      await settleSignOut(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('server-url-field')), findsNothing);
      expect(container.read(apiBaseUrlProvider), newServer);
      // The refresh token went back to the server that issued it — never to
      // the one being switched to.
      expect(authCalls, contains('$oldServer /api/v1/auth/logout'));
      expect(authCalls.where((c) => c.startsWith(newServer)), isEmpty);
      // Signed out, on the sign-in screen, with no session left to restore.
      expect(container.read(authControllerProvider).value, isNull);
      expect(await tester.runAsync(() => TokenStorage(store).read()), isNull);
      expect(find.text('Sign in to your space'), findsOneWidget);
      // No running engine, workspace, team capability or replica owner.
      expect(
        container.read(runningSyncEnginesProvider).every((e) => e.isStopped),
        isTrue,
      );
      expect(container.read(workspacesProvider).value, isEmpty);
      expect(container.read(eeStatusProvider).value?.has('teams'), isNot(true));
      expect(container.read(teamOriginProvider), isNull);
      expect(
        await tester.runAsync(
          () => localKv.get('${kEeStatusCachePrefix}user-1'),
        ),
        isNull,
      );
      expect(
        await tester.runAsync(() => localKv.get(kReplicaOwnerKey)),
        isNull,
      );
    },
  );

  testWidgets('E-02: saving a server on the sign-in screen closes the dialog '
      'and stays on sign-in', (tester) async {
    final container = await pumpApp(tester, signedIn: false);
    expect(find.text('Sign in to your space'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-url-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      newServer,
    );
    await tester.tap(find.text('Save'));
    await settleSignOut(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('server-url-field')), findsNothing);
    expect(find.text('Sign in to your space'), findsOneWidget);
    expect(container.read(apiBaseUrlProvider), newServer);
    expect(find.textContaining('other.example.com'), findsOneWidget);
    expect(authCalls, isEmpty);
  });
}
