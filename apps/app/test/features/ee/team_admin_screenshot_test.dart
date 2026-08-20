// The team-admin screens, shot in both themes (EE-042 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/team_admin_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// The acceptance is a picture somebody looks at, and these two screens are
// where a team's people are added and taken away. A deactivated row has to
// read as deactivated at a glance, and a seat banner that is over its plan has
// to look like a fact rather than an alarm — nobody is being evicted.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_invites_screen.dart';
import 'package:alliswell/src/features/ee/ui/team_members_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

EeTeamMember _member(
  String id,
  String name,
  String role,
  String initials,
  String color, {
  bool active = true,
}) => EeTeamMember(
  userId: id,
  role: role,
  active: active,
  email: '${name.split(' ').first.toLowerCase()}@acme.example',
  displayName: name,
  initials: initials,
  colorRgb: color,
);

/// A roster with every state the screen has to make legible at a glance: an
/// owner, an admin, ordinary members, and somebody deactivated.
final _roster = EeTeamRoster(
  members: [
    _member('U1', 'Ada Yönetici', 'owner', 'AY', '#2563EB'),
    _member('U2', 'Bora Şef', 'admin', 'BŞ', '#7C3AED'),
    _member('U3', 'Cem Üye', 'member', 'CÜ', '#16A34A'),
    _member('U4', 'Deniz Vardiya', 'member', 'DV', '#EA580C'),
    _member('U5', 'Elif İzinde', 'member', 'Eİ', '#CA8A04', active: false),
  ],
  seats: const EeSeats(used: 11, max: 10, exceeded: true, canAdd: false),
);

final _invites = [
  const EeInvite(
    id: 'I1',
    email: 'yeni@acme.example',
    role: 'member',
    state: 'pending',
    expiresAt: '2026-08-21T09:00:00.000Z',
  ),
  const EeInvite(
    id: 'I2',
    email: 'sef@acme.example',
    role: 'admin',
    state: 'accepted',
    expiresAt: '2026-08-20T09:00:00.000Z',
  ),
  const EeInvite(
    id: 'I3',
    email: 'vazgecildi@acme.example',
    role: 'member',
    state: 'revoked',
    expiresAt: '2026-08-20T09:00:00.000Z',
  ),
  const EeInvite(
    id: 'I4',
    email: 'gecikti@acme.example',
    role: 'member',
    state: 'expired',
    expiresAt: '2026-08-19T09:00:00.000Z',
  ),
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
    testWidgets('team members — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-team-members', [
        eeTeamRosterProvider.overrideWith(() => _FixedRoster(_roster)),
      ], const EeTeamMembersScreen());
    });

    testWidgets('team invitations — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-team-invites', [
        eeInvitesProvider.overrideWith(() => _FixedInvites(_invites)),
      ], const EeTeamInvitesScreen());
    });
  }
}

class _FixedRoster extends EeRosterController {
  _FixedRoster(this._value);
  final EeTeamRoster _value;
  @override
  Future<EeTeamRoster> build() async => _value;
}

class _FixedInvites extends EeInvitesController {
  _FixedInvites(this._value);
  final List<EeInvite> _value;
  @override
  Future<List<EeInvite>> build() async => _value;
}
