import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/team_units_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-057 — the units screens.
///
/// What is pinned here is the ASYMMETRY, because it is the part a redesign
/// would quietly lose: the same two screens serve a team admin and a delegated
/// unit manager, and the manager must not be offered a control the server
/// would refuse. A button that answers 403 is a small lie an app tells its own
/// user (DESIGN §22, EE-052's rule).
class FakeUnitsApi implements EeUnitsApi {
  FakeUnitsApi({List<EeUnit>? units, this.listAnswer = _listOk})
    : _units =
          units ?? [const EeUnit(id: 'U1', name: 'Muhasebe', memberCount: 3)];

  static const _listOk = true;
  final bool listAnswer;
  List<EeUnit> _units;
  final List<String> calls = [];
  List<EeUnitMember> roster = const [
    EeUnitMember(userId: 'P1', role: 'member', displayName: 'Pınar Üye'),
    EeUnitMember(userId: 'M1', role: 'manager', displayName: 'Merve Birim'),
  ];
  List<EeUnitMember> candidateList = const [
    EeUnitMember(userId: 'O1', role: 'member', displayName: 'Onur Aday'),
  ];

  @override
  Future<List<EeUnit>?> list() async => listAnswer ? _units : null;

  @override
  Future<List<EeUnitMember>> members(String unitId) async => roster;

  @override
  Future<List<EeUnitMember>> candidates(String unitId) async => candidateList;

  @override
  Future<void> create(String name) async {
    calls.add('create:$name');
    _units = [..._units, EeUnit(id: 'U${_units.length + 1}', name: name)];
  }

  @override
  Future<void> rename(String unitId, String name) async =>
      calls.add('rename:$unitId:$name');

  @override
  Future<void> setArchived(String unitId, {required bool archived}) async =>
      calls.add('archive:$unitId:$archived');

  @override
  Future<void> addMember(String unitId, String userId) async =>
      calls.add('add:$unitId:$userId');

  @override
  Future<void> removeMember(String unitId, String userId) async =>
      calls.add('remove:$unitId:$userId');

  @override
  Future<void> setMemberRole(String unitId, String userId, String role) async =>
      calls.add('role:$unitId:$userId:$role');
}

Widget harness(
  FakeUnitsApi api, {
  required bool isAdmin,
  required Widget child,
}) => ProviderScope(
  overrides: [
    eeUnitsApiProvider.overrideWithValue(api),
    // The screen's only question about authority: `units.manage` is purely
    // role-based, so an admin holds it and a delegated manager never does.
    canProvider.overrideWith(
      (ref, id) => id == 'units.manage' ? isAdmin : true,
    ),
    eeFeatureProvider.overrideWith((ref, feature) => true),
  ],
  child: MaterialApp(theme: buildAwTheme(Brightness.light), home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the unit list', () {
    testWidgets('an admin may change the shape of the team', (tester) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(api, isAdmin: true, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unit-new')), findsOneWidget);
      expect(find.byKey(const Key('unit-menu-U1')), findsOneWidget);
    });

    testWidgets('a delegated manager is offered NEITHER', (tester) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(api, isAdmin: false, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();

      // No "new unit", no rename/archive menu: those are `units.manage`, and
      // drawing them would promise something the server refuses.
      expect(find.byKey(const Key('unit-new')), findsNothing);
      expect(find.byKey(const Key('unit-menu-U1')), findsNothing);
      // …but the unit itself is there, because staffing it is their job.
      expect(find.byKey(const Key('unit-U1')), findsOneWidget);
    });

    testWidgets('a null list is "nothing here is yours", not an error', (
      tester,
    ) async {
      final api = FakeUnitsApi(listAnswer: false);
      await tester.pumpWidget(
        harness(api, isAdmin: false, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('ee.team.units.noneTitle'.tr()), findsOneWidget);
    });

    testWidgets('an admin with no units sees where to start, not a wall', (
      tester,
    ) async {
      final api = FakeUnitsApi(units: []);
      await tester.pumpWidget(
        harness(api, isAdmin: true, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();

      // Empty ≠ forbidden. This is exactly where the first unit gets opened,
      // so the FAB must survive the empty state.
      expect(find.text('ee.team.units.emptyTitle'.tr()), findsOneWidget);
      expect(find.byKey(const Key('unit-new')), findsOneWidget);
    });

    testWidgets('the "you run this one" badge is about delegation, not power', (
      tester,
    ) async {
      final api = FakeUnitsApi(
        units: [
          const EeUnit(
            id: 'U1',
            name: 'Muhasebe',
            memberCount: 3,
            manages: true,
          ),
        ],
      );
      await tester.pumpWidget(
        harness(api, isAdmin: false, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ee.team.units.youManage'.tr()),
        findsOneWidget,
      );
    });
  });

  group('the unit roster', () {
    const unit = EeUnit(id: 'U1', name: 'Muhasebe', memberCount: 2);

    testWidgets('an admin may appoint a manager', (tester) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(
          api,
          isAdmin: true,
          child: const EeUnitMembersScreen(unit: unit),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('unit-member-menu-P1')));
      await tester.pumpAndSettle();
      expect(find.text('ee.team.units.promote'.tr()), findsOneWidget);
    });

    testWidgets('a delegated manager may staff but not appoint', (
      tester,
    ) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(
          api,
          isAdmin: false,
          child: const EeUnitMembersScreen(unit: unit),
        ),
      );
      await tester.pumpAndSettle();

      // Adding people IS their job — the button stays.
      expect(find.byKey(const Key('unit-member-add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unit-member-menu-P1')));
      await tester.pumpAndSettle();
      // A delegation that can appoint delegates is a second admin role nobody
      // named. The control is ABSENT, not refused.
      expect(find.text('ee.team.units.promote'.tr()), findsNothing);
      expect(find.text('ee.team.units.removeMember'.tr()), findsOneWidget);
    });

    testWidgets('the picker offers people who are not in the unit yet', (
      tester,
    ) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(
          api,
          isAdmin: false,
          child: const EeUnitMembersScreen(unit: unit),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('unit-member-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unit-candidate-O1')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('add:U1:O1'));
    });
  });
}
