import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/auth/ui/forgot_password_screen.dart';
import 'package:alliswell/src/features/auth/ui/reset_password_screen.dart';

import '../../support/sync_overrides.dart';
import '../projects/fake_api.dart';
import 'test_support.dart';

/// OPH-406 (ADR-0064) — "Forgot password?" from the sign-in screen to a new
/// password, against a faked `/auth/password/*`.
void main() {
  late List<({String path, Map<String, dynamic>? body})> calls;

  Widget appWith(FakeHandler handler) {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    return ProviderScope(
      retry: awRetry,
      overrides: [
        ...syncTestOverrides(),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        authApiProvider.overrideWithValue(
          AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, body) async {
                // The sign-in screen asks which social buttons to show.
                if (options.path == '/api/v1/auth/providers') {
                  return jsonBody(200, {'google': false, 'apple': false});
                }
                calls.add((path: options.path, body: body));
                return handler(options, body);
              }),
            ),
          ),
        ),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(FakeApi().handle)),
        ),
      ],
      child: const AllisWellApp(),
    );
  }

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Signs-in screen → typed email → "Forgot password?".
  Future<void> openForgot(WidgetTester tester, {String email = ''}) async {
    await tester.pumpAndSettle();
    if (email.isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        email,
      );
    }
    await tester.ensureVisible(find.byKey(const Key('login-forgot')));
    await tester.tap(find.byKey(const Key('login-forgot')));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
  }

  testWidgets('the sign-in screen offers it, carrying the typed email, and a '
      'mailing server says to check the inbox', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      appWith((options, body) async => jsonBody(202, {'delivery': 'email'})),
    );
    await openForgot(tester, email: 'ada@example.com');

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('forgot-email')),
    );
    expect(field.controller!.text, 'ada@example.com');
    final sendSize = tester.getSize(find.byKey(const Key('forgot-send')));
    expect(sendSize.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('forgot-send')));
    await tester.pumpAndSettle();

    expect(calls.single.path, '/api/v1/auth/password/forgot');
    expect(calls.single.body, {'email': 'ada@example.com', 'locale': 'en'});
    expect(find.byKey(const Key('forgot-sent')), findsOneWidget);
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.textContaining('If there is an account for ada@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('a server with no mail sends the person to its operator, with '
      'the command filled in', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      appWith((options, body) async => jsonBody(202, {'delivery': 'admin'})),
    );
    await openForgot(tester, email: 'ada@example.com');
    await tester.tap(find.byKey(const Key('forgot-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot-admin')), findsOneWidget);
    expect(find.text("This server doesn't send email"), findsOneWidget);
    final command = tester.widget<SelectableText>(
      find.byKey(const Key('forgot-command')),
    );
    expect(
      command.data,
      'docker compose exec api node apps/api/src/cli/password-reset-link.js '
      'ada@example.com',
    );
  });

  testWidgets('an empty or malformed address is caught before any request', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      appWith((options, body) async => fail('no request expected')),
    );
    await openForgot(tester);
    await tester.tap(find.byKey(const Key('forgot-send')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('"I have a link": a pasted link sets the new password', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(appWith((options, body) async => emptyBody(204)));
    await openForgot(tester);
    await tester.tap(find.byKey(const Key('forgot-have-link')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);

    // Nothing usable pasted, and a short password: refused here.
    await tester.enterText(find.byKey(const Key('reset-link')), 'hello');
    await tester.enterText(find.byKey(const Key('reset-password')), 'short');
    await tester.tap(find.byKey(const Key('reset-save')));
    await tester.pumpAndSettle();
    expect(find.text('Paste the link'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(calls, isEmpty);

    const token = 'AbC_dEf-123456789012345678901234567890xyz';
    await tester.enterText(
      find.byKey(const Key('reset-link')),
      'https://alliswell.example/#/reset-password?token=$token',
    );
    await tester.enterText(
      find.byKey(const Key('reset-password')),
      'a-new-password',
    );
    await tester.tap(find.byKey(const Key('reset-save')));
    await tester.pumpAndSettle();

    expect(calls.single.path, '/api/v1/auth/password/reset');
    expect(calls.single.body, {'token': token, 'password': 'a-new-password'});
    expect(find.byKey(const Key('reset-done')), findsOneWidget);
    expect(find.text('Your password is changed'), findsOneWidget);
  });

  testWidgets('a spent or expired link says so and offers a new one', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      appWith(
        (options, body) async => jsonBody(400, {
          'statusCode': 400,
          'code': 'AUTH_RESET_INVALID',
          'error': 'Bad Request',
          'message': 'This reset link is invalid or has expired',
        }),
      ),
    );
    await openForgot(tester);
    await tester.tap(find.byKey(const Key('forgot-have-link')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reset-link')),
      'AbC_dEf-123456789012345678901234567890xyz',
    );
    await tester.enterText(
      find.byKey(const Key('reset-password')),
      'a-new-password',
    );
    await tester.tap(find.byKey(const Key('reset-save')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This link no longer works: it was used or it expired. '
        'Request a new one.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('reset-request-new')));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
  });

  test('an address with shell syntax is quoted in the operator command', () {
    // E35 G-C review r1: the address is whatever the form accepted, and the
    // operator pastes the command into a shell — nothing in it may run.
    const prefix =
        'docker compose exec api node apps/api/src/cli/password-reset-link.js ';
    expect(awResetLinkCommand('ada@example.com'), '${prefix}ada@example.com');
    expect(
      awResetLinkCommand(r'`printf${IFS}injected`@example.com'),
      "$prefix'`printf\${IFS}injected`@example.com'",
    );
    expect(
      awResetLinkCommand(r"o'neil$(id)@example.com"),
      "$prefix'o'\\''neil\$(id)@example.com'",
    );
    expect(awResetLinkCommand(''), '$prefix<email>');
  });

  test('the token is read from a whole link or taken as a bare code', () {
    expect(
      awResetTokenFrom(
        ' https://a.example/app/#/reset-password?token=abcdefghijklmnopqrstuvwxyz ',
      ),
      'abcdefghijklmnopqrstuvwxyz',
    );
    expect(
      awResetTokenFrom('abcdefghijklmnopqrstuvwxyz_-01'),
      'abcdefghijklmnopqrstuvwxyz_-01',
    );
    expect(awResetTokenFrom('short'), isNull);
    expect(awResetTokenFrom('not a link at all, really'), isNull);
    expect(awResetTokenFrom(''), isNull);
  });
}
