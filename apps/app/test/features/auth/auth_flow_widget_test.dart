import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../projects/fake_api.dart';
import 'test_support.dart';
import '../../support/sync_overrides.dart';

/// Wide two-pane surface: these shell tests assert CONTENT presence, not
/// phone sliver economics (the narrow Home keeps search+calendar in the
/// scroll — OPH-167/168).
Future<void> wideSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // Every platform boundary is faked: auth HTTP via the handler, the
  // authenticated API via an empty FakeApi (the shell fetches /me + tasks
  // after login), and secret storage in memory (the real default would hit a
  // platform channel and hang tests).
  Widget appWith(FakeHandler handler) {
    SharedPreferences.setMockInitialValues({});
    return ProviderScope(
      retry: awRetry,
      overrides: [
        ...syncTestOverrides(),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        authApiProvider.overrideWithValue(
          AuthApi(fakeDio(FakeHttpClientAdapter(handler))),
        ),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(FakeApi().handle)),
        ),
      ],
      child: const AllisWellApp(),
    );
  }

  testWidgets('boots to the login screen when signed out', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async => fail('no request expected')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in to your space'), findsOneWidget);
  });

  testWidgets('logging in navigates into the app shell', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async {
        expect(options.path, '/api/v1/auth/login');
        return jsonBody(200, sessionJson());
      }),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mahir@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-horse-battery',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // Router redirect landed on /home inside the shell.
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('wrong credentials show a friendly inline error', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith(
        (options, body) async => jsonBody(401, {
          'statusCode': 401,
          'code': 'AUTH_INVALID_CREDENTIALS',
          'error': 'Unauthorized',
          'message': 'Invalid email or password',
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mahir@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrong-password',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget, reason: 'still on login');
  });

  testWidgets('register flow: validation, then account creation', (
    tester,
  ) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async {
        expect(options.path, '/api/v1/auth/register');
        return jsonBody(201, sessionJson());
      }),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    // Too-short password is caught client-side, before any request.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mahir@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'short',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-horse-battery',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('All caught up'), findsOneWidget);
  });
}
