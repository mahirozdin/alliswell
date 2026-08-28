// The service catalogue, shot in both themes (EE-082 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/services_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY THESE TWO SHOTS. The catalogue's dangerous state is not an error and not
// an empty list — it is a service that looks perfectly fine and silently
// receives nothing, because no unit answers it. That is an ABSENCE, which is
// exactly what a code diff cannot show and a picture can. The list shot puts
// the unrouted service next to a routed one and an archived one, so the three
// have to be tellable apart at a glance; the routing shot is where an admin
// fixes it, with the custom-field editor underneath.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/services_api.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_services_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

final _units = [
  const EeUnit(id: 'U1', name: 'Bakım', memberCount: 9),
  const EeUnit(id: 'U2', name: 'Bilgi İşlem', memberCount: 5),
  const EeUnit(id: 'U3', name: 'İnsan Kaynakları', memberCount: 3),
];

/// One of each state the row must make legible — and the second one is the
/// point of the screen: live, correct-looking, and reaching nobody.
final _services = [
  const EeService(
    id: 'S1',
    name: 'Elektrik arızası',
    description: 'Hat duruşları, pano ve sensör arızaları',
    unitIds: ['U1'],
    formFields: [
      EeServiceField(
        key: 'line_no',
        label: 'Hat numarası',
        type: 'text',
        required: true,
      ),
      EeServiceField(
        key: 'shift',
        label: 'Vardiya',
        type: 'select',
        options: ['1', '2', '3'],
      ),
    ],
  ),
  const EeService(
    id: 'S2',
    name: 'Yeni personel kartı',
    description: 'Giriş kartı ve yetkilendirme',
  ),
  const EeService(id: 'S3', name: 'Bilgisayar arızası', unitIds: ['U2', 'U3']),
  const EeService(
    id: 'S4',
    name: 'Eski servis talebi',
    archived: true,
    unitIds: ['U1'],
  ),
];

class _ShotServicesApi implements EeServicesApi {
  const _ShotServicesApi();

  @override
  Future<List<EeService>?> list() async => _services;
  @override
  Future<void> create({
    required String name,
    String? description,
    Map<String, dynamic>? formSchema,
  }) async {}
  @override
  Future<void> update(
    String serviceId, {
    String? name,
    String? description,
    Map<String, dynamic>? formSchema,
    Set<String> clear = const {},
  }) async {}
  @override
  Future<void> setArchived(String serviceId, {required bool archived}) async {}
  @override
  Future<void> setUnits(String serviceId, List<String> unitIds) async {}
}

class _ShotUnitsApi implements EeUnitsApi {
  const _ShotUnitsApi();

  @override
  Future<List<EeUnit>?> list() async => _units;
  @override
  Future<List<EeUnitMember>> members(String unitId) async => const [];
  @override
  Future<List<EeUnitMember>> candidates(String unitId) async => const [];
  @override
  Future<void> create(String name) async {}
  @override
  Future<void> rename(String unitId, String name) async {}
  @override
  Future<void> setArchived(String unitId, {required bool archived}) async {}
  @override
  Future<void> addMember(String unitId, String userId) async {}
  @override
  Future<void> removeMember(String unitId, String userId) async {}
  @override
  Future<void> setMemberRole(String unitId, String userId, String role) async {}
}

List<Override> _overrides() => [
  eeServicesApiProvider.overrideWithValue(const _ShotServicesApi()),
  eeUnitsApiProvider.overrideWithValue(const _ShotUnitsApi()),
  canProvider.overrideWith((ref, id) => true),
  eeFeatureProvider.overrideWith((ref, feature) => true),
];

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    Widget screen,
  ) async {
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
          overrides: _overrides(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            // Every route is wrapped in the page background; a bare Scaffold
            // renders the veil against nothing — a flat grey that exists
            // nowhere in the product.
            home: AwPageBackground(child: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('the catalogue, with one service reaching nobody — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-services-admin',
        const EeTeamServicesScreen(),
      );
    });

    testWidgets('one service: who answers it and what it asks — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-service-routing',
        EeServiceRoutingScreen(service: _services.first),
      );
    });
  }
}
