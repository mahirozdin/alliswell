// Where the accounts come from (EE-148).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/team_identity_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THIS SCREEN IS ON THE PAGE AT ALL. docs/ENTERPRISE.md has been telling
// readers since EE-119 that directory integration "is not included" — and E15
// shipped all of it: LDAP bind, SAML, OIDC, SCIM 2.0, group-to-unit mapping
// and deprovisioning that kills sessions. The page understated the product,
// and a screenshot is the least deniable way to stop doing that.
//
// WHY THREE PROVIDERS. The screen has three states worth photographing and
// they fail differently:
//
//   • One LIVE and verified — the ordinary case, and the one that has to look
//     boring.
//   • One live from a DIFFERENT protocol, because "we support LDAP" and "we
//     support your identity provider" are different promises, and a buyer on
//     Entra ID is reading for the second.
//   • One that CANNOT be turned on yet and says WHICH settings it is missing.
//     An enabled provider is the only authority for the addresses it owns, so
//     a half-filled one turned on is a typo that becomes an outage for
//     everybody the directory holds. "Still needs: ssoUrl" is the difference
//     between a screen somebody can finish and one they have to guess at.
//
// A stored credential shows four characters and is never a field — that is
// asserted in team_identity_test.dart, and the picture has to agree with it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/identity_models.dart';
import 'package:alliswell/src/features/ee/identity_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_identity_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/demo_corpus.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

class _Fixed extends EeIdentityController {
  _Fixed(this._value);
  final List<EeIdentityProvider> _value;
  @override
  Future<List<EeIdentityProvider>?> build() async => _value;
}

class _FixedStatus extends EeIdentityStatusController {
  _FixedStatus(this._value);
  final EeIdentityStatus _value;
  @override
  Future<EeIdentityStatus?> build() async => _value;
}

List<Override> _overrides(DemoCorpus corpus) => [
  eeIdentityProvidersProvider.overrideWith(
    () => _Fixed(corpus.identityProviders),
  ),
  eeIdentityStatusProvider.overrideWith(
    () => _FixedStatus(corpus.identityStatus),
  ),
];

void main() {
  if (!_enabled) return;

  late DemoCorpus corpus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Order matters: the corpus reads the active language and asserts rather
    // than falling back to one.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    corpus = DemoCorpus.active();
  });

  for (final brightness in Brightness.values) {
    testWidgets('where the accounts come from — ${brightness.name}', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-team-identity',
        size: const Size(900, 1500),
        overrides: _overrides(corpus),
        screen: const EeTeamIdentityScreen(),
      );
    });
  }
}
