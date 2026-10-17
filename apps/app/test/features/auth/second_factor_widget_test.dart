import 'package:dio/dio.dart' show RequestOptions, ResponseBody;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/social_sign_in.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../../support/sync_overrides.dart';
import '../projects/fake_api.dart';
import 'auth_flow_widget_test.dart' show wideSurface;
import 'test_support.dart';

/// Hands back a fixed Google ID token and counts how often the native sheet
/// would have opened — the retry with a code must not open it again.
class _FakeSocialSignIn extends SocialSignIn {
  int googleCalls = 0;

  @override
  Future<String> googleIdToken() async {
    googleCalls++;
    return 'google-id-token-1';
  }
}

ResponseBody _mfa(String code) => jsonBody(401, {
  'statusCode': 401,
  'code': code,
  'error': 'Unauthorized',
  'message': code,
});

/// OPH-381 — an account with an authenticator is asked for its code after
/// the password or the Google / Apple token, and the SAME request is sent
/// again with it. Until this change the app never sent `totpCode`, so such an
/// account could not sign in at all.
void main() {
  late List<Map<String, dynamic>?> bodies;

  Widget appWith(FakeHandler handler, {SocialSignIn? social}) {
    SharedPreferences.setMockInitialValues({});
    return ProviderScope(
      retry: awRetry,
      overrides: [
        ...syncTestOverrides(),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        authApiProvider.overrideWithValue(
          AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, body) {
                bodies.add(body);
                return handler(options, body);
              }),
            ),
          ),
        ),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(FakeApi().handle)),
        ),
        if (social != null) socialSignInProvider.overrideWithValue(social),
      ],
      child: const AllisWellApp(),
    );
  }

  /// The server's side of a TOTP account: no code → required, a wrong one →
  /// invalid, `123456` → a session.
  Future<ResponseBody> totpServer(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final code = body?['totpCode'];
    if (code == null) return _mfa('AUTH_MFA_REQUIRED');
    if (code != '123456') return _mfa('AUTH_MFA_INVALID');
    return jsonBody(200, {...sessionJson(), 'created': false});
  }

  Future<void> typePassword(WidgetTester tester) async {
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
  }

  Future<void> submitCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('second-factor-code')), code);
    await tester.tap(find.byKey(const Key('second-factor-verify')));
    await tester.pumpAndSettle();
  }

  setUp(() => bodies = []);

  testWidgets('password sign-in asks for the code, says a wrong one inline, '
      'and retries the same request', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async {
        expect(options.path, '/api/v1/auth/login');
        return totpServer(options, body);
      }),
    );
    await tester.pumpAndSettle();
    await typePassword(tester);

    expect(find.byKey(const Key('second-factor-dialog')), findsOneWidget);
    expect(find.text('Enter your verification code'), findsOneWidget);
    expect(find.byKey(const Key('login-error')), findsNothing);

    await submitCode(tester, '000000');
    expect(find.byKey(const Key('second-factor-dialog')), findsOneWidget);
    expect(
      find.text('That code is not right. Check it and try again.'),
      findsOneWidget,
    );

    await submitCode(tester, '123456');
    expect(find.byKey(const Key('second-factor-dialog')), findsNothing);
    expect(find.text('All caught up'), findsOneWidget, reason: 'in the shell');

    expect(bodies, hasLength(3));
    for (final body in bodies) {
      expect(body?['email'], 'mahir@example.com');
      expect(body?['password'], 'correct-horse-battery');
    }
    expect(bodies.map((b) => b?['totpCode']), [null, '000000', '123456']);
  });

  testWidgets('cancelling the prompt returns to the sign-in screen', (
    tester,
  ) async {
    await wideSurface(tester);
    await tester.pumpWidget(appWith(totpServer));
    await tester.pumpAndSettle();
    await typePassword(tester);

    await tester.tap(find.byKey(const Key('second-factor-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('second-factor-dialog')), findsNothing);
    expect(find.text('Sign in to your space'), findsOneWidget);
    expect(find.byKey(const Key('login-error')), findsNothing);
    expect(bodies, hasLength(1));
  });

  testWidgets('a recovery code is accepted as typed', (tester) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async {
        final code = body?['totpCode'];
        if (code == null) return _mfa('AUTH_MFA_REQUIRED');
        expect(code, 'ABCDE-12345');
        return jsonBody(200, sessionJson());
      }),
    );
    await tester.pumpAndSettle();
    await typePassword(tester);
    await submitCode(tester, 'ABCDE-12345');

    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('Google sign-in asks for the code and resends the SAME token '
      'without opening the provider again', (tester) async {
    await wideSurface(tester);
    final social = _FakeSocialSignIn();
    await tester.pumpWidget(
      appWith((options, body) async {
        expect(options.path, '/api/v1/auth/oauth');
        return totpServer(options, body);
      }, social: social),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('sign-in-google')));
    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('second-factor-dialog')), findsOneWidget);
    expect(find.byKey(const Key('social-sign-in-error')), findsNothing);

    await submitCode(tester, '000000');
    expect(
      find.text('That code is not right. Check it and try again.'),
      findsOneWidget,
    );
    await submitCode(tester, '123456');

    expect(find.text('All caught up'), findsOneWidget);
    expect(social.googleCalls, 1);
    expect(bodies, hasLength(3));
    for (final body in bodies) {
      expect(body?['provider'], 'google');
      expect(body?['idToken'], 'google-id-token-1');
    }
    expect(bodies.map((b) => b?['totpCode']), [null, '000000', '123456']);
  });

  testWidgets('cancelling after Google stays on sign-in with no error', (
    tester,
  ) async {
    await wideSurface(tester);
    final social = _FakeSocialSignIn();
    await tester.pumpWidget(appWith(totpServer, social: social));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('sign-in-google')));
    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('second-factor-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your space'), findsOneWidget);
    expect(find.byKey(const Key('social-sign-in-error')), findsNothing);
    final google = tester.widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(const Key('sign-in-google')),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(google.onPressed, isNotNull, reason: 'the button is usable again');
  });

  testWidgets('an account without a factor signs in with no prompt', (
    tester,
  ) async {
    await wideSurface(tester);
    await tester.pumpWidget(
      appWith((options, body) async => jsonBody(200, sessionJson())),
    );
    await tester.pumpAndSettle();
    await typePassword(tester);

    expect(find.byKey(const Key('second-factor-dialog')), findsNothing);
    expect(find.text('All caught up'), findsOneWidget);
    expect(bodies.single?.containsKey('totpCode'), isFalse);
  });
}
