import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/services_api.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/team_admin_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_services_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-228 — the catalogue as the admin arranges it.
///
/// The server's half (the two-level rule from both sides, the partial PATCH
/// that leaves an untouched approval rule alone, the icon's closed set) is
/// `services-catalog.integration.test.js`. These pin the screen: the shelves
/// in the order the requester will see them, the device-folded search, the
/// icon, and a setup save that sends EXACTLY what changed.
const _shelves = [
  EeServiceCategory(id: 'C1', name: 'Arızalar', icon: 'wrench'),
  EeServiceCategory(
    id: 'C2',
    name: 'Elektrik',
    parentId: 'C1',
    icon: 'network',
  ),
  EeServiceCategory(
    id: 'C3',
    name: 'İnsan kaynakları',
    icon: 'people',
    position: 1,
  ),
];

const _services = [
  EeService(
    id: 'S1',
    name: 'Pres arızası',
    categoryId: 'C1',
    icon: 'wrench',
    unitIds: ['U1'],
  ),
  EeService(
    id: 'S2',
    name: 'Pano arızası',
    description: 'Sigorta attı',
    categoryId: 'C2',
    unitIds: ['U1'],
  ),
  EeService(id: 'S3', name: 'Yazıcı toneri', icon: 'printer', unitIds: ['U2']),
  EeService(
    id: 'S4',
    name: 'Onaylı ekipman',
    categoryId: 'C1',
    unitIds: ['U1'],
    approvalMode: 'role',
    approverRoleKey: 'admin',
  ),
];

class _FakeServices extends Fake implements EeServicesApi {
  final patched = <(String, Map<String, Object?>)>[];
  final shelved = <(String, String?)>[];
  final created = <({String name, String? parentId, String? icon})>[];
  final edited = <(String, Map<String, Object?>)>[];
  final deleted = <String>[];
  int lists = 0;
  Object? patchFails;

  @override
  Future<List<EeService>?> list() async {
    lists += 1;
    return _services;
  }

  @override
  Future<List<EeServiceCategory>?> categories() async => _shelves;

  @override
  Future<void> patch(String serviceId, Map<String, Object?> body) async {
    if (patchFails != null) throw patchFails!;
    patched.add((serviceId, body));
  }

  @override
  Future<void> setCategory(String serviceId, String? categoryId) async =>
      shelved.add((serviceId, categoryId));

  @override
  Future<void> setUnits(String serviceId, List<String> unitIds) async {}

  @override
  Future<void> createCategory({
    required String name,
    String? parentId,
    String? icon,
  }) async => created.add((name: name, parentId: parentId, icon: icon));

  @override
  Future<void> updateCategory(
    String categoryId,
    Map<String, Object?> body,
  ) async => edited.add((categoryId, body));

  @override
  Future<void> deleteCategory(String categoryId) async =>
      deleted.add(categoryId);
}

class _FakeUnits extends Fake implements EeUnitsApi {
  @override
  Future<List<EeUnit>?> list() async => const [
    EeUnit(id: 'U1', name: 'Bakım', memberCount: 3),
    EeUnit(id: 'U2', name: 'Bilgi işlem', memberCount: 2),
  ];
}

class _FakeAdmin extends Fake implements EeTeamAdminApi {
  @override
  Future<List<EeRole>> roles() async => const [
    EeRole(
      key: 'admin',
      name: 'Yönetici',
      base: true,
      anchor: 'admin',
      editable: true,
    ),
    EeRole(
      key: 'member',
      name: 'Üye',
      base: true,
      anchor: 'member',
      editable: true,
    ),
  ];

  @override
  Future<EeTeamRoster> members() async => const EeTeamRoster(
    members: [
      EeTeamMember(
        userId: 'M1',
        role: 'admin',
        active: true,
        displayName: 'Ayla',
      ),
      EeTeamMember(
        userId: 'M2',
        role: 'member',
        active: true,
        displayName: 'Barış',
      ),
      EeTeamMember(
        userId: 'M3',
        role: 'member',
        active: false,
        displayName: 'Eski',
      ),
    ],
    seats: EeSeats(),
  );
}

void main() {
  late _FakeServices api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeServices();
  });

  Future<void> pumpCatalogue(WidgetTester tester) async {
    // Tall: the setup screen is one long list, and a list builds only what
    // is on screen — a finder cannot reach a row that was never built.
    tester.view.physicalSize = const Size(1170, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          eeServicesApiProvider.overrideWithValue(api),
          eeUnitsApiProvider.overrideWithValue(_FakeUnits()),
          eeTeamAdminApiProvider.overrideWithValue(_FakeAdmin()),
          eeFeatureProvider.overrideWith((ref, feature) => true),
          canProvider.overrideWith((ref, id) => true),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTeamServicesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(Key(value));
  double top(WidgetTester tester, String k) => tester.getTopLeft(key(k)).dy;

  Future<void> search(WidgetTester tester, String text) async {
    await tester.tap(key('search-open'));
    await tester.pumpAndSettle();
    await tester.enterText(key('service-search'), text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> openSetup(WidgetTester tester, String serviceId) async {
    await tester.tap(key('service-$serviceId'));
    await tester.pumpAndSettle();
  }

  /// `ensureVisible` scrolls, but the new layout is only there after a
  /// frame — a tap in between lands where the widget USED to be.
  Future<void> reveal(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await reveal(tester, 'service-routing-save');
    await tester.tap(key('service-routing-save'));
    await tester.pumpAndSettle();
  }

  /// The list builds what is on screen, so the button is brought there
  /// before it is asked about.
  Future<bool> saveEnabled(WidgetTester tester) async {
    await reveal(tester, 'service-routing-save');
    return tester.widget<FilledButton>(key('service-routing-save')).onPressed !=
        null;
  }

  group('the catalogue on its shelves', () {
    testWidgets('top shelves, their sub-shelves, and the unshelved last', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      final order = [
        'shelf-C1',
        'service-S1',
        'shelf-C2',
        'service-S2',
        'shelf-C3',
        'shelf-none',
        'service-S3',
      ];
      for (var i = 1; i < order.length; i += 1) {
        expect(
          top(tester, order[i - 1]),
          lessThan(top(tester, order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      // A shelf nothing sits on says so rather than looking like a heading
      // that lost its rows.
      expect(key('shelf-empty-C3'), findsOneWidget);
      expect(find.text('Rafsız'), findsOneWidget);
    });

    testWidgets('a service carries the icon a requester will see', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      expect(
        find.descendant(
          of: key('service-S3'),
          matching: find.byIcon(Icons.print_outlined),
        ),
        findsOneWidget,
      );
    });
  });

  group('search, folded on the device', () {
    // Three spellings of one word — a phone without Turkish letters, a
    // Turkish keyboard, caps lock — and each needs the fold on a different
    // side: the entry's words, the query, or both.
    for (final spelling in ['yazici', 'yazıcı', 'YAZICI']) {
      testWidgets('"$spelling" finds "Yazıcı" — and nothing else', (
        tester,
      ) async {
        await pumpCatalogue(tester);
        await search(tester, spelling);
        expect(key('service-S3'), findsOneWidget);
        expect(key('service-S1'), findsNothing);
        expect(
          key('shelf-C3'),
          findsNothing,
          reason: 'empty groups step aside',
        );
      });
    }

    testWidgets('a shelf\'s name finds what is on it', (tester) async {
      await pumpCatalogue(tester);
      await search(tester, 'elektrik');
      expect(key('service-S2'), findsOneWidget);
      expect(key('service-S1'), findsNothing);
    });

    testWidgets('no match says so', (tester) async {
      await pumpCatalogue(tester);
      await search(tester, 'zzz');
      expect(key('service-search-empty'), findsOneWidget);
    });
  });

  group('a service\'s setup sends exactly what changed', () {
    testWidgets('a new shelf is a move, and nothing else is patched', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      await openSetup(tester, 'S1');
      await tester.tap(key('service-shelf'));
      await tester.pumpAndSettle();
      await tester.tap(key('service-shelf-C2').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(api.shelved, [('S1', 'C2')]);
      expect(api.patched, isEmpty);
    });

    testWidgets(
      'an icon is one key — an approval rule not touched is not sent',
      (tester) async {
        await pumpCatalogue(tester);
        await openSetup(tester, 'S4');
        await tester.tap(key('service-icon-printer'));
        await tester.pumpAndSettle();
        await save(tester);
        expect(api.patched.single.$1, 'S4');
        expect(api.patched.single.$2, {'icon': 'printer'});
      },
    );

    testWidgets('EE-268 (AW-E21): the kind of work is one key, and saying it '
        'again is no change', (tester) async {
      await pumpCatalogue(tester);
      await openSetup(tester, 'S4');
      // Every service starts as a request — the answer before this existed.
      await reveal(tester, 'service-process-type-incident');
      expect(await saveEnabled(tester), isFalse);
      await reveal(tester, 'service-process-type-incident');
      await tester.tap(key('service-process-type-incident'));
      await tester.pumpAndSettle();
      // Back to what it was is not a change…
      await tester.tap(key('service-process-type-request'));
      await tester.pumpAndSettle();
      expect(await saveEnabled(tester), isFalse);
      // …and a real change sends that key alone.
      await reveal(tester, 'service-process-type-incident');
      await tester.tap(key('service-process-type-incident'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(api.patched.single.$1, 'S4');
      expect(api.patched.single.$2, {'processType': 'incident'});
    });

    testWidgets('a role rule waits for its role, then goes whole', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      await openSetup(tester, 'S1');
      await reveal(tester, 'service-approval-role');
      await tester.tap(key('service-approval-role'));
      await tester.pumpAndSettle();
      expect(await saveEnabled(tester), isFalse);
      expect(key('service-approval-incomplete'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(key('service-approval-role-admin').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(api.patched.single.$1, 'S1');
      expect(api.patched.single.$2, {
        'approvalMode': 'role',
        'approverRoleKey': 'admin',
        'approverUserIds': <String>[],
      });
    });

    testWidgets('named people: at least one, and only active members offered', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      await openSetup(tester, 'S1');
      await reveal(tester, 'service-approval-users');
      await tester.tap(key('service-approval-users'));
      await tester.pumpAndSettle();
      expect(await saveEnabled(tester), isFalse);
      expect(key('service-approver-M3'), findsNothing, reason: 'deactivated');

      await reveal(tester, 'service-approver-M2');
      await tester.tap(key('service-approver-M2'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(api.patched.single.$1, 'S1');
      expect(api.patched.single.$2, {
        'approvalMode': 'users',
        'approverRoleKey': null,
        'approverUserIds': ['M2'],
      });
    });

    testWidgets('switching the rule away and back is not a change', (
      tester,
    ) async {
      await pumpCatalogue(tester);
      await openSetup(tester, 'S4');
      await reveal(tester, 'service-approval-none');
      await tester.tap(key('service-approval-none'));
      await tester.pumpAndSettle();
      expect(await saveEnabled(tester), isTrue);
      await tester.tap(key('service-approval-role'));
      await tester.pumpAndSettle();
      expect(await saveEnabled(tester), isFalse);
    });

    testWidgets('a refusal stays on the setup screen, in the server\'s words', (
      tester,
    ) async {
      api.patchFails = const ApiException(
        'SERVICE_APPROVER_NOT_HERE',
        'Some of those people are not on this team',
      );
      await pumpCatalogue(tester);
      await openSetup(tester, 'S1');
      await tester.tap(key('service-icon-key'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        tester.widget<Text>(key('service-setup-error')).data,
        'Some of those people are not on this team',
      );
      expect(
        find.widgetWithText(AppBar, 'Pres arızası'),
        findsOneWidget,
        reason: 'still on the setup screen',
      );
    });
  });

  group('the shelves', () {
    Future<void> openShelves(WidgetTester tester) async {
      await pumpCatalogue(tester);
      await tester.tap(key('service-shelves'));
      await tester.pumpAndSettle();
    }

    Future<void> menu(WidgetTester tester, String id, String item) async {
      await tester.tap(key('shelf-menu-$id'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(item)).last);
      await tester.pumpAndSettle();
    }

    testWidgets('two levels, a sub-shelf set in under its parent', (
      tester,
    ) async {
      await openShelves(tester);
      // The ListTile, not the Card: a Card's margin sits inside its own box.
      Offset tile(String id) => tester.getTopLeft(
        find.descendant(
          of: key('shelf-row-$id'),
          matching: find.byType(ListTile),
        ),
      );
      final root = tile('C1');
      final sub = tile('C2');
      expect(sub.dy, greaterThan(root.dy));
      expect(sub.dx, greaterThan(root.dx), reason: 'indented');
      expect(
        top(tester, 'shelf-row-C2'),
        lessThan(top(tester, 'shelf-row-C3')),
      );
    });

    testWidgets('a new shelf: name and icon', (tester) async {
      await openShelves(tester);
      await tester.tap(key('shelf-new'));
      await tester.pumpAndSettle();
      await tester.enterText(key('shelf-name'), 'Tesis');
      await tester.tap(key('shelf-icon-building'));
      await tester.pumpAndSettle();
      await tester.tap(key('shelf-save'));
      await tester.pumpAndSettle();
      expect(api.created, [(name: 'Tesis', parentId: null, icon: 'building')]);
    });

    testWidgets('a sub-shelf starts under its parent; a sub-shelf takes none', (
      tester,
    ) async {
      await openShelves(tester);
      await tester.tap(key('shelf-menu-C2'));
      await tester.pumpAndSettle();
      expect(key('shelf-add-sub-C2'), findsNothing, reason: 'no third level');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await menu(tester, 'C1', 'shelf-add-sub-C1');
      await tester.enterText(key('shelf-name'), 'Mekanik');
      await tester.tap(key('shelf-save'));
      await tester.pumpAndSettle();
      expect(api.created.single.parentId, 'C1');
    });

    testWidgets('only top shelves can be parents, never the shelf itself', (
      tester,
    ) async {
      await openShelves(tester);
      await menu(tester, 'C3', 'shelf-edit-C3');
      await tester.tap(key('shelf-parent'));
      await tester.pumpAndSettle();
      expect(key('shelf-parent-C1'), findsWidgets);
      expect(key('shelf-parent-C2'), findsNothing, reason: 'a sub-shelf');
      expect(key('shelf-parent-C3'), findsNothing, reason: 'itself');
    });

    testWidgets(
      'a shelf with sub-shelves cannot move under another, and says why',
      (tester) async {
        await openShelves(tester);
        await menu(tester, 'C1', 'shelf-edit-C1');
        final parent = tester.widget<DropdownButton<String?>>(
          find.descendant(
            of: key('shelf-parent'),
            matching: find.byType(DropdownButton<String?>),
          ),
        );
        expect(parent.onChanged, isNull);
        expect(find.textContaining('Alt rafları olan bir raf'), findsOneWidget);
      },
    );

    testWidgets('a rename sends the name alone', (tester) async {
      await openShelves(tester);
      await menu(tester, 'C1', 'shelf-edit-C1');
      await tester.enterText(key('shelf-name'), 'Arıza');
      await tester.tap(key('shelf-save'));
      await tester.pumpAndSettle();
      expect(api.edited.single.$1, 'C1');
      expect(api.edited.single.$2, {'name': 'Arıza'});
    });

    testWidgets('deleting asks first, and the catalogue is read again', (
      tester,
    ) async {
      await openShelves(tester);
      final before = api.lists;
      await menu(tester, 'C3', 'shelf-delete-C3');
      expect(find.textContaining('hiçbir servis kaybolmaz'), findsOneWidget);
      await tester.tap(key('shelf-delete-confirm'));
      await tester.pumpAndSettle();
      expect(api.deleted, ['C3']);
      // The catalogue behind this screen is paused while covered (Riverpod
      // pauses what nobody can see); it is asked again the moment it is
      // shown, so the services that fell off the shelf appear at the root.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.lists, greaterThan(before));
    });
  });
}
