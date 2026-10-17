import 'package:alliswell/src/features/auth/data/social_sign_in.dart';
import 'package:alliswell/src/features/auth/ui/social_sign_in_buttons.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    Widget host() => const ProviderScope(
      child: MaterialApp(home: Scaffold(body: SocialSignInButtons())),
    );

    for (final p in [TargetPlatform.linux, TargetPlatform.windows]) {
      testWidgets('render nothing on $p — no button, no orphan divider', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = p;
        await tester.pumpWidget(host());
        expect(find.byKey(const Key('sign-in-google')), findsNothing);
        expect(find.text('auth.or'.tr()), findsNothing);
        expect(find.byType(Divider), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('show Google on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(host());
      expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
      expect(find.text('auth.or'.tr()), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
