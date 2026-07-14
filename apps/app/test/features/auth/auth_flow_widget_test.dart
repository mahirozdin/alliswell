import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import 'test_support.dart';

void main() {
  Widget appWith(FakeHandler handler) => ProviderScope(
    overrides: [
      authApiProvider.overrideWithValue(
        AuthApi(fakeDio(FakeHttpClientAdapter(handler))),
      ),
    ],
    child: const AllisWellApp(),
  );

  testWidgets('boots to the login screen when signed out', (tester) async {
    await tester.pumpWidget(
      appWith((options, body) async => fail('no request expected')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in to your space'), findsOneWidget);
  });

  testWidgets('logging in navigates into the app shell', (tester) async {
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

    // Router redirect landed on /today inside the shell.
    expect(
      find.text('Everything due, scheduled or urgent today.'),
      findsOneWidget,
    );
  });

  testWidgets('wrong credentials show a friendly inline error', (tester) async {
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

    expect(
      find.text('Everything due, scheduled or urgent today.'),
      findsOneWidget,
    );
  });
}
