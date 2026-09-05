// The public-link manager, shot in both themes (EE-106's acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/portal_links_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY TWO SHOTS. The list is one, and the second is the DIALOG — because the
// dialog is the only moment a usable link exists anywhere in this product
// (the server keeps a digest, EE-101), and "this is shown once" is a claim a
// reviewer should be able to check by looking rather than by reading a test.
// If that sentence is ever quietly dropped, the picture is where it shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/portal_links_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/portal_links_providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/portal_links_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/demo_corpus.dart';
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

class _Fixed extends EePortalLinksController {
  _Fixed(this._value);
  final EePortalLinksData _value;
  @override
  Future<EePortalLinksData?> build() async => _value;
}

class _FixedServices extends EeServicesController {
  _FixedServices(this._value);
  final List<EeService> _value;
  @override
  Future<List<EeService>?> build() async => _value;
}

void main() {
  if (!_enabled) return;

  // The links point at the corpus's own catalogue, so a service named on this
  // screen is the same service the SLA dashboard counts and the ticket queue
  // routes to.
  late DemoCorpus corpus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Order matters: the corpus reads the active language and asserts rather
    // than falling back to one.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    corpus = DemoCorpus.active();
  });

  for (final brightness in Brightness.values) {
    testWidgets('portal links list (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-portal-links',
        size: const Size(900, 1100),
        overrides: [
          eePortalLinksProvider.overrideWith(() => _Fixed(corpus.portalLinks)),
          eeServicesProvider.overrideWith(
            () => _FixedServices(corpus.services),
          ),
        ],
        screen: const EePortalLinksScreen(),
      );
    });
    testWidgets('portal link creation (${brightness.name})', (tester) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-portal-create',
        size: const Size(900, 1100),
        overrides: [
          eePortalLinksProvider.overrideWith(() => _Fixed(corpus.portalLinks)),
          eeServicesProvider.overrideWith(
            () => _FixedServices(corpus.services),
          ),
        ],
        screen: const EePortalLinksScreen(),
        // The dialog is the point of this shot: photograph the create form,
        // not the list behind it.
        afterPump: (t) => t.tap(find.byKey(const Key('portal-create'))),
      );
    });
  }
}
