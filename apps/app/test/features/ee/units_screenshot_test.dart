// The unit screens, shot in both themes (EE-057 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/units_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// Why these two shots and not one: the list is the only screen in the product
// that renders DIFFERENTLY for two people looking at the same team, and the
// difference is an absence — no "new unit" button, no per-unit menu. An
// absence is precisely what a diff of code does not show and a picture does.
// The third shot is the roster, where "who runs this unit" has to read at a
// glance next to people who merely work in it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/team_units_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart'
    show loadRealFontsForStore, screenshotLocale;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

/// A team with every state the row has to make legible: a busy unit, a small
/// one the viewer runs themselves, and a retired one.
final _units = [
  const EeUnit(id: 'U1', name: 'Muhasebe', memberCount: 12),
  const EeUnit(id: 'U2', name: 'Saha Servis', memberCount: 4, manages: true),
  const EeUnit(id: 'U3', name: 'Ar-Ge', memberCount: 7),
  const EeUnit(id: 'U4', name: 'Eski Depo', memberCount: 2, archived: true),
];

final _roster = [
  const EeUnitMember(userId: 'M1', role: 'manager', displayName: 'Merve Birim'),
  const EeUnitMember(userId: 'P1', role: 'member', displayName: 'Pınar Üye'),
  const EeUnitMember(userId: 'C1', role: 'member', displayName: 'Cem Saha'),
  const EeUnitMember(userId: 'K1', role: 'member', email: 'kerem@acme.example'),
];

class _ShotApi implements EeUnitsApi {
  const _ShotApi(this._visible);

  /// What the SERVER would hand this caller. An admin gets the team; a
  /// delegated manager gets only what they run — so the shot must not show
  /// them four units, or the picture pins a state the server cannot produce.
  final List<EeUnit> _visible;

  @override
  Future<List<EeUnit>?> list() async => _visible;
  @override
  Future<List<EeUnitMember>> members(String unitId) async => _roster;
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

List<Override> _as({required bool admin}) => [
  eeUnitsApiProvider.overrideWithValue(
    _ShotApi(admin ? _units : _units.where((u) => u.manages).toList()),
  ),
  canProvider.overrideWith((ref, id) => id == 'units.manage' ? admin : true),
  eeFeatureProvider.overrideWith((ref, feature) => true),
];

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    List<Override> overrides,
    Widget screen,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            // Every route is wrapped in the page background; a bare Scaffold
            // renders the veil against nothing — a flat grey that exists
            // nowhere in the product (the history shot learned this first).
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
    testWidgets('units, as the team admin sees them — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-units-admin',
        _as(admin: true),
        const EeTeamUnitsScreen(),
      );
    });

    // The same team, the same data, one person down the authority ladder.
    // Everything that differs is missing rather than greyed: a disabled
    // control still promises a capability.
    testWidgets(
      'units, as the delegated manager sees them — ${brightness.name}',
      (tester) async {
        await shoot(
          tester,
          brightness,
          'ee-units-manager',
          _as(admin: false),
          const EeTeamUnitsScreen(),
        );
      },
    );

    testWidgets('one unit\'s roster — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-unit-members',
        _as(admin: true),
        const EeUnitMembersScreen(
          unit: EeUnit(id: 'U2', name: 'Saha Servis', memberCount: 4),
        ),
      );
    });
  }
}
