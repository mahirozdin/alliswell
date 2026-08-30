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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/portal_links_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/portal_links_providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/portal_links_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

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

final _services = [
  const EeService(id: 'S1', name: 'Elektrik arızası', unitIds: ['U1']),
  const EeService(id: 'S2', name: 'Aydınlatma', unitIds: ['U1', 'U2']),
  const EeService(id: 'S3', name: 'Kartlı geçiş', unitIds: ['U2']),
];

final _data = EePortalLinksData(
  links: [
    EePortalLink(
      id: 'L1',
      serviceId: 'S1',
      unitId: 'U1',
      state: EePortalLinkState.active,
      enabled: true,
      expiresAt: DateTime(2026, 9, 1, 12),
      hasCustomFields: true,
    ),
    EePortalLink(
      id: 'L2',
      serviceId: 'S2',
      unitId: 'U2',
      state: EePortalLinkState.disabled,
      enabled: false,
      expiresAt: DateTime(2026, 9, 14, 12),
    ),
    // The two that are easy to draw wrong: expired must read as ordinary,
    // revoked must carry no controls.
    EePortalLink(
      id: 'L3',
      serviceId: 'S3',
      unitId: 'U2',
      state: EePortalLinkState.expired,
      enabled: true,
      expiresAt: DateTime(2026, 8, 20, 12),
    ),
    EePortalLink(
      id: 'L4',
      serviceId: 'S1',
      unitId: 'U1',
      state: EePortalLinkState.revoked,
      enabled: true,
      expiresAt: DateTime(2026, 9, 30, 12),
      revokedAt: DateTime(2026, 8, 25, 9),
    ),
  ],
  linkQuota: const EePortalQuota(used: 2, max: 5, remaining: 3),
  ticketQuota: const EePortalQuota(used: 143, max: 500, remaining: 357),
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name, {
    bool openDialog = false,
  }) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eePortalLinksProvider.overrideWith(() => _Fixed(_data)),
            eeServicesProvider.overrideWith(() => _FixedServices(_services)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: const AwPageBackground(child: EePortalLinksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (openDialog) {
        await tester.tap(find.byKey(const Key('portal-create')));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('portal links list (${brightness.name})', (tester) async {
      await shoot(tester, brightness, 'ee-portal-links');
    });
    testWidgets('portal link creation (${brightness.name})', (tester) async {
      await shoot(tester, brightness, 'ee-portal-create', openDialog: true);
    });
  }
}
