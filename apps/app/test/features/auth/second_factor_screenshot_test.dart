// The second-factor prompt in both themes (OPH-381): empty, and after a wrong
// code with its inline error.
//
// Run locally with:
//
//   cd apps/app
//   flutter test --update-goldens --dart-define=screenshots=true \
//       --dart-define=shotLocale=en test/features/auth/second_factor_screenshot_test.dart
//
// and again with shotLocale=tr. Inert without the dart-define: goldens are
// generated output (test/goldens is gitignored).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/auth/data/models.dart';
import 'package:alliswell/src/features/auth/ui/second_factor_prompt.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import '../ee/support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// The prompt as it sits over the sign-in screen: dimmed page, the card on top.
Widget _prompt() => Builder(
  builder: (context) => Stack(
    children: [
      ModalBarrier(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      ),
      SecondFactorDialog(
        submit: (_) async => throw const AuthException(
          'AUTH_MFA_INVALID',
          'That code is not right',
          statusCode: 401,
        ),
      ),
    ],
  ),
);

void main() {
  if (!_enabled) return;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AwI18n.instance.setLocale(screenshotLocale('en'));
  });

  const size = Size(780, 1400);

  for (final brightness in Brightness.values) {
    testWidgets('prompt — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'second-factor-prompt',
        size: size,
        screen: Scaffold(backgroundColor: Colors.transparent, body: _prompt()),
      );
    });

    testWidgets('wrong code — ${brightness.name}', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'second-factor-wrong-code',
        size: size,
        screen: Scaffold(backgroundColor: Colors.transparent, body: _prompt()),
        afterPump: (tester) async {
          await tester.enterText(
            find.byKey(const Key('second-factor-code')),
            '000000',
          );
          await tester.tap(find.byKey(const Key('second-factor-verify')));
        },
      );
    });
  }
}
