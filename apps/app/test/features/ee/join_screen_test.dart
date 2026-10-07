import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/core/server_url.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/ee/ui/join_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart' show pendingDeepLinkProvider;
import 'package:alliswell/src/theme/theme.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// UI-AUDIT #5 (OPH-356) — the invitation link opens the acceptance screen
/// ON THE TEAM'S SERVER.
///
/// The audit's scenario, as the app half of it: the link the team admin
/// copied (`…/#/join/<token>?server=https://<slug>.<baseDomain>`, ADR-0021) is
/// opened by somebody with no account. Before this task the app ignored
/// `server`, sent the visitor to sign in on the service's own address, and
/// the screen behind it could not redeem anything at all.
const _token = 'd6eqwPmZ92KSNdTf8tREbom1dei';
const _apex = 'https://api.example.com';
const _team = 'https://acme.example.com';

/// One fake per address the screen talks to: which origins were asked, and
/// what was sent.
class _Invites {
  _Invites({this.accountExists = false, this.teamSlug = 'acme'});

  final bool accountExists;
  final String teamSlug;
  final List<String> asked = [];
  Map<String, dynamic>? accepted;
  String? acceptedAuth;

  Dio dioFor(String origin) {
    final dio = Dio(BaseOptions(baseUrl: origin));
    dio.httpClientAdapter = FakeHttpClientAdapter((options, body) async {
      asked.add('${options.method} $origin${options.path}');
      if (options.path == '/api/v1/ee/invites/$_token' &&
          options.method == 'GET') {
        return jsonBody(200, {
          'email': 'yeni@example.com',
          'teamName': 'Demir Çelik Fabrikası',
          'teamSlug': teamSlug,
          'expiresAt': '2026-10-14T00:00:00.000Z',
          'accountExists': accountExists,
        });
      }
      if (options.path == '/api/v1/ee/invites/$_token/accept') {
        accepted = body;
        acceptedAuth = options.headers['Authorization'] as String?;
        return jsonBody(200, {
          'teamId': 'T1',
          'role': 'member',
          'account': accountExists ? 'existing' : 'created',
          'email': 'yeni@example.com',
        });
      }
      return jsonBody(404, {'message': 'Not found'});
    });
    return dio;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove(kServerUrlPrefKey);
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  /// The join route the app uses, with Home and Login as plain landmarks.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    _Invites invites, {
    String? server,
    bool signedIn = false,
    FakeApi? api,
    List<String>? logins,
  }) async {
    final store = InMemorySecretStore();
    late ProviderContainer container;
    await tester.runAsync(() async {
      if (signedIn) await TokenStorage(store).save(fakeSession());
      container = ProviderContainer(
        retry: awRetry,
        overrides: [
          secretStoreProvider.overrideWithValue(store),
          // The app starts on the service's own address.
          serverUrlOverrideProvider.overrideWith(
            () => PersistedChoice(kServerUrlPrefKey, fallback: _apex),
          ),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter((api ?? FakeApi()).handle)),
          ),
          eeInviteDioProvider.overrideWith(
            (ref, origin) => invites.dioFor(origin),
          ),
          // Sign-in, on whichever address the app is pointed at by then.
          authApiProvider.overrideWith((ref) {
            final base = ref.watch(apiBaseUrlProvider);
            final dio = Dio(BaseOptions(baseUrl: base));
            dio.httpClientAdapter = FakeHttpClientAdapter((o, body) async {
              logins?.add('$base${o.path} ${body?['email']}');
              return jsonBody(200, sessionJson());
            });
            return AuthApi(dio);
          }),
        ],
      );
      await container.read(authControllerProvider.future);
    });
    addTearDown(container.dispose);

    final location = server == null
        ? '/join/$_token'
        : '/join/$_token?server=${Uri.encodeComponent(server)}';
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/join/:token',
          builder: (context, state) => JoinTeamScreen(
            token: state.pathParameters['token']!,
            server: state.uri.queryParameters['server'],
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildAwTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('UI-AUDIT #5: the link\'s server is shown, the invitation is '
      'read and redeemed THERE, and the new account signs in there', (
    tester,
  ) async {
    final invites = _Invites();
    final logins = <String>[];
    final container = await pump(
      tester,
      invites,
      server: _team,
      logins: logins,
    );

    // The host is on screen before anything is sent to it.
    expect(find.text('Team address: acme.example.com'), findsOneWidget);
    expect(find.text('Join Demir Çelik Fabrikası'), findsOneWidget);
    expect(find.text('Invitation for yeni@example.com'), findsOneWidget);
    expect(invites.asked, ['GET $_team/api/v1/ee/invites/$_token']);

    await tester.enterText(find.byKey(const Key('join-code')), '123456');
    await tester.enterText(find.byKey(const Key('join-name')), 'Yeni Üye');
    await tester.enterText(
      find.byKey(const Key('join-password')),
      'uzun-bir-parola',
    );
    await tester.tap(find.byKey(const Key('join-accept')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(invites.asked.last, 'POST $_team/api/v1/ee/invites/$_token/accept');
    expect(invites.accepted, {
      'code': '123456',
      'password': 'uzun-bir-parola',
      'displayName': 'Yeni Üye',
    });
    // The app now lives on the team's address — and signed in THERE.
    expect(container.read(apiBaseUrlProvider), _team);
    expect(logins, ['$_team/api/v1/auth/login yeni@example.com']);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('UI-AUDIT #5: a host outside the trusted domain is named and '
      'refused — the app is not moved, nothing is asked of it', (tester) async {
    for (final server in [
      'https://acme.evil.com',
      'http://acme.example.com',
      'https://api.example.com',
      'https://acme.example.com/steal',
    ]) {
      final invites = _Invites();
      final container = await pump(tester, invites, server: server);
      expect(
        find.byKey(const Key('join-wrong-server')),
        findsOneWidget,
        reason: server,
      );
      expect(
        find.text('This link does not belong to this app'),
        findsOneWidget,
      );
      expect(invites.asked, isEmpty, reason: server);
      expect(container.read(apiBaseUrlProvider), _apex);
    }
  });

  testWidgets('UI-AUDIT #5: the team the server names must be the team the '
      'invitation belongs to', (tester) async {
    final invites = _Invites(teamSlug: 'globex');
    await pump(tester, invites, server: _team);
    expect(find.byKey(const Key('join-wrong-server')), findsOneWidget);
    expect(find.byKey(const Key('join-accept')), findsNothing);
  });

  testWidgets('UI-AUDIT #5: without `server` the invitation is read on the '
      'address the app is on — the link format before ADR-0021', (
    tester,
  ) async {
    final invites = _Invites();
    await pump(tester, invites);
    expect(invites.asked, ['GET $_apex/api/v1/ee/invites/$_token']);
    expect(find.text('Team address: api.example.com'), findsOneWidget);
  });

  testWidgets('UI-AUDIT #5: an address that already has an account signs in '
      'on the TEAM\'s server, and the whole link waits for it', (tester) async {
    final invites = _Invites(accountExists: true);
    final container = await pump(tester, invites, server: _team);
    // No password to set: the account exists.
    expect(find.byKey(const Key('join-password')), findsNothing);
    await tester.tap(find.byKey(const Key('join-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
    expect(container.read(apiBaseUrlProvider), _team);
    expect(
      container.read(pendingDeepLinkProvider),
      '/join/$_token?server=${Uri.encodeComponent(_team)}',
    );
  });

  testWidgets('UI-AUDIT #5: signed in, the instance\'s own baseDomain decides '
      '— and the redeeming session is the one already held', (tester) async {
    final api = FakeApi()
      ..eeState = 'active'
      ..eeFeatures = ['teams']
      ..eeBaseDomain = 'example.com';
    final invites = _Invites(accountExists: true);
    // The fake session is mahir@example.com; the invitation is for another
    // address — said, and no button that the server would refuse.
    await pump(tester, invites, server: _team, signedIn: true, api: api);
    expect(find.byKey(const Key('join-wrong-account')), findsOneWidget);
    expect(find.byKey(const Key('join-accept')), findsNothing);

    final foreign = _Invites();
    await pump(
      tester,
      foreign,
      server: 'https://acme.alliswell.space',
      signedIn: true,
      api: api,
    );
    expect(find.byKey(const Key('join-wrong-server')), findsOneWidget);
    expect(foreign.asked, isEmpty);
  });

  // The router half: the audit's "#/join/<token> giriş ekranına düştü".
  for (final signedIn in [false, true]) {
    testWidgets('UI-AUDIT #5: a cold start on the link opens the invitation '
        '(${signedIn ? 'signed in' : 'signed out'}), not the sign-in', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/join/$_token?server=${Uri.encodeComponent(_team)}';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final store = InMemorySecretStore();
      if (signedIn) await TokenStorage(store).save(fakeSession());
      final invites = _Invites();
      await tester.pumpWidget(
        ProviderScope(
          retry: awRetry,
          overrides: [
            ...syncTestOverrides(),
            secretStoreProvider.overrideWithValue(store),
            serverUrlOverrideProvider.overrideWith(
              () => PersistedChoice(kServerUrlPrefKey, fallback: _apex),
            ),
            apiClientProvider.overrideWithValue(
              fakeDio(
                FakeHttpClientAdapter(
                  (FakeApi()
                        ..eeState = 'active'
                        ..eeFeatures = ['teams']
                        ..eeBaseDomain = 'example.com')
                      .handle,
                ),
              ),
            ),
            eeInviteDioProvider.overrideWith(
              (ref, origin) => invites.dioFor(origin),
            ),
          ],
          child: const AllisWellApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JoinTeamScreen), findsOneWidget);
      expect(find.text('Team address: acme.example.com'), findsOneWidget);
      expect(invites.asked, ['GET $_team/api/v1/ee/invites/$_token']);
    });
  }
}
