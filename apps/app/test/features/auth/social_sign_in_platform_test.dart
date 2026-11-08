import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/social_sign_in.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/auth/ui/social_sign_in_buttons.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// OPH-370 — google_sign_in 7 has no Windows or Linux implementation, so the
/// desktop downloads must not offer a button that can only fail.
void main() {
  group('SocialSignIn.googleAvailableOn', () {
    test('web, Android, iOS and macOS offer Google', () {
      expect(
        SocialSignIn.googleAvailableOn(
          isWeb: true,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(
          SocialSignIn.googleAvailableOn(isWeb: false, platform: p),
          isTrue,
          reason: '$p',
        );
      }
    });

    test('Windows and Linux do not', () {
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect(
          SocialSignIn.googleAvailableOn(isWeb: false, platform: p),
          isFalse,
          reason: '$p',
        );
      }
    });
  });

  group('SocialSignInButtons', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    // The server's answer is its own group below; here it could not say,
    // which leaves the platform rule alone.
    Widget host() => ProviderScope(
      overrides: [
        serverSignInProvidersProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: SocialSignInButtons())),
    );

    for (final p in [TargetPlatform.linux, TargetPlatform.windows]) {
      testWidgets('render nothing on $p — no button, no orphan divider', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = p;
        await tester.pumpWidget(host());
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('sign-in-google')), findsNothing);
        expect(find.text('auth.or'.tr()), findsNothing);
        expect(find.byType(Divider), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('show Google on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(host());
      await tester.pump();
      expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
      expect(find.text('auth.or'.tr()), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  /// OPH-392 (E-23) — the server says which sign-ins it can complete. A
  /// server with no Google client offered a button whose tap could only end
  /// in OAUTH_PROVIDER_NOT_CONFIGURED.
  group('the server\'s answer (GET /auth/providers)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Widget hostAsking(FakeHandler server) => ProviderScope(
      overrides: [
        authApiProvider.overrideWithValue(
          AuthApi(fakeDio(FakeHttpClientAdapter(server))),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SocialSignInButtons())),
    );

    Future<void> pumpOn(WidgetTester tester, FakeHandler server) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(hostAsking(server));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('no Google client on the server → no Google button, no '
        'orphan divider', (tester) async {
      final asked = <String>[];
      await pumpOn(tester, (options, _) async {
        asked.add('${options.method} ${options.path}');
        return jsonBody(200, {'google': false, 'apple': false});
      });
      expect(asked, ['GET /api/v1/auth/providers']);
      expect(find.byKey(const Key('sign-in-google')), findsNothing);
      expect(find.text('auth.or'.tr()), findsNothing);
    });

    testWidgets('a Google client on the server → the button', (tester) async {
      await pumpOn(
        tester,
        (options, _) async => jsonBody(200, {'google': true, 'apple': false}),
      );
      expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    });

    testWidgets('an older server that cannot answer keeps the platform rule', (
      tester,
    ) async {
      await pumpOn(
        tester,
        (options, _) async => jsonBody(404, {
          'statusCode': 404,
          'code': 'NOT_FOUND',
          'message': 'Route GET:/api/v1/auth/providers not found',
        }),
      );
      expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    });
  });
}
