import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/services_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/team_units_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/fab_clearance.dart';
import '../auth/test_support.dart';
import 'support/permissions.dart';

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
    // OPH-356 (#62): the list reads the permission answer first; one from
    // before EE-302 (no `managedUnitIds`) still asks the list.
    fixedPermissions(),
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

  // R3-1 (OPH-363): with the Quick Access bubble docked in the bar's row
  // (OPH-362) nothing above the page cleared the page's OWN floating button
  // any more — a units list ended under "+ New unit", and a tap on the last
  // row's ⋮ at the end of the scroll opened the new-unit dialog instead.
  group('R3-1: the end of a list clears the page\'s own button', () {
    Future<void> pumpDocked(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final api =
          FakeUnitsApi(
              units: [
                for (var i = 1; i <= 14; i++)
                  EeUnit(id: 'U$i', name: 'Birim $i', memberCount: 2),
              ],
            )
            ..roster = [
              for (var i = 1; i <= 14; i++)
                EeUnitMember(
                  userId: 'P$i',
                  role: 'member',
                  displayName: 'Kişi $i',
                ),
            ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeUnitsApiProvider.overrideWithValue(api),
            canProvider.overrideWith((ref, id) => true),
            eeFeatureProvider.overrideWith((ref, feature) => true),
            fixedPermissions(),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            // The bubble docked on the right of the bottom row, as on a phone.
            builder: (context, child) => AwBubbleDock(
              edge: AwDockEdge.right,
              height: 80,
              width: 72,
              child: child!,
            ),
            home: child,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> expectLastMenuReachable(
      WidgetTester tester, {
      required Key fab,
      required Key lastMenu,
    }) async {
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(lastMenu));
      final button = tester.getRect(find.byKey(fab));
      expect(
        menu.bottom,
        lessThanOrEqualTo(button.top),
        reason: 'the last row ends above the page\'s button ($menu vs $button)',
      );
      // And the tap lands on the menu, not on the button.
      await tester.tapAt(menu.center);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
    }

    testWidgets('the unit list', (tester) async {
      await pumpDocked(tester, const EeTeamUnitsScreen());
      await expectLastMenuReachable(
        tester,
        fab: const Key('unit-new'),
        lastMenu: const Key('unit-menu-U14'),
      );
    });

    testWidgets('a unit\'s roster', (tester) async {
      await pumpDocked(
        tester,
        const EeUnitMembersScreen(
          unit: EeUnit(id: 'U1', name: 'Muhasebe', memberCount: 14),
        ),
      );
      await expectLastMenuReachable(
        tester,
        fab: const Key('unit-member-add'),
        lastMenu: const Key('unit-member-menu-P14'),
      );
    });
  });

  group('UI-AUDIT OPH-360', () {
    const unit = EeUnit(id: 'U1', name: 'Muhasebe', memberCount: 0);

    testWidgets('UI-AUDIT #80: an empty roster says so, not a blank page', (
      tester,
    ) async {
      final api = FakeUnitsApi()..roster = const [];
      await tester.pumpWidget(
        harness(
          api,
          isAdmin: true,
          child: const EeUnitMembersScreen(unit: unit),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-members-empty')), findsOneWidget);
      expect(find.text('ee.team.units.noMembersTitle'.tr()), findsOneWidget);
      // …and the way in stays.
      expect(find.byKey(const Key('unit-member-add')), findsOneWidget);
    });

    testWidgets('UI-AUDIT #22 pattern: archiving a unit asks first', (
      tester,
    ) async {
      final api = FakeUnitsApi();
      await tester.pumpWidget(
        harness(api, isAdmin: true, child: const EeTeamUnitsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unit-menu-U1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ee.team.units.archive'.tr()));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('archive:U1:true')));
      await tester.tap(find.text('ee.team.units.keep'.tr()));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('archive:U1:true')));

      await tester.tap(find.byKey(const Key('unit-menu-U1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ee.team.units.archive'.tr()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unit-archive-confirm')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('archive:U1:true'));
    });
  });

  // UI-AUDIT #62 (OPH-356, EE-302): a member's Settings asked the units list
  // and a request's detail asked the admin service list on every open — two
  // 403s each time, to learn what `/me/permissions` can now say.
  group('UI-AUDIT #62: no admin endpoint is probed to learn a member\'s '
      'reach', () {
    ProviderContainer containerWith(
      EePermissions permissions, {
      required _CountingUnits units,
      List<String>? servicesAsked,
      bool admin = false,
    }) {
      final dio = Dio(BaseOptions(baseUrl: 'https://acme.example.com'));
      dio.httpClientAdapter = FakeHttpClientAdapter((options, body) async {
        servicesAsked?.add(options.path);
        return jsonBody(403, {'code': 'PERM_DENIED', 'message': 'no'});
      });
      final container = ProviderContainer(
        overrides: [
          eeFeatureProvider.overrideWith((ref, feature) => true),
          fixedPermissions(permissions),
          eeTeamProvider.overrideWith(
            (ref) async => EeTeamInfo(
              id: 'T1',
              name: 'Acme',
              slug: 'acme',
              status: 'active',
              myRole: admin ? 'admin' : 'member',
            ),
          ),
          eeUnitsApiProvider.overrideWithValue(units),
          eeServicesApiProvider.overrideWithValue(EeServicesApi(dio)),
          eeCatalogProvider.overrideWith(
            (ref) async => const EeCatalog(
              services: [EeCatalogService(id: 'S1', name: 'Hat 3 PLC')],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    const member = EePermissions(
      workspaceId: 'W1',
      governed: true,
      permissions: ['tickets.create'],
      managedUnitIds: [],
    );

    test('a member who runs no unit: the units list is never asked', () async {
      final units = _CountingUnits();
      final c = containerWith(member, units: units);
      expect(await c.read(eeUnitsProvider.future), isNull);
      expect(units.listed, 0);
    });

    test('a delegated manager: the list is asked, and answers', () async {
      final units = _CountingUnits();
      final c = containerWith(
        const EePermissions(
          workspaceId: 'W1',
          governed: true,
          managedUnitIds: ['U-QA'],
        ),
        units: units,
      );
      expect(await c.read(eeUnitsProvider.future), isNotNull);
      expect(units.listed, 1);
    });

    test('a server from before EE-302 (no field): the list is still the '
        'only way to know', () async {
      final units = _CountingUnits();
      final c = containerWith(
        const EePermissions(workspaceId: 'W1', governed: true),
        units: units,
      );
      await c.read(eeUnitsProvider.future);
      expect(units.listed, 1);
    });

    test('an admin is asked even with no delegation of their own', () async {
      final units = _CountingUnits();
      final c = containerWith(
        const EePermissions(
          workspaceId: 'W1',
          governed: true,
          permissions: ['units.manage_members'],
          managedUnitIds: [],
        ),
        units: units,
        admin: true,
      );
      await c.read(eeUnitsProvider.future);
      expect(units.listed, 1);
    });

    test('a request\'s services come from the catalogue for a member — the '
        'admin list is never asked', () async {
      final asked = <String>[];
      final c = containerWith(
        member,
        units: _CountingUnits(),
        servicesAsked: asked,
      );
      c.listen(eeServiceGlancesProvider, (_, _) {});
      await c.read(eePermissionsProvider.future);
      await c.read(eeTeamProvider.future);
      await c.read(eeCatalogProvider.future);
      final glances = c.read(eeServiceGlancesProvider);
      expect(glances['S1']?.name, 'Hat 3 PLC');
      expect(asked, isEmpty);
    });
  });
}

class _CountingUnits extends FakeUnitsApi {
  int listed = 0;

  @override
  Future<List<EeUnit>?> list() {
    listed += 1;
    return super.list();
  }
}
