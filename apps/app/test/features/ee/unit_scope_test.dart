import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/changes_screen.dart';
import 'package:alliswell/src/features/ee/ui/kb_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-359 — UI-AUDIT #29: the desk's lists know WHOSE list they are.
///
/// After sign-in the selected space is the team's general one, which is not a
/// unit, and every unit list said "nothing in this unit" — beside a strip
/// counting 70 breached requests in the units that were full. Each list now
/// names its unit, and on a space that is not one says "choose a unit" with
/// the person's units to choose from. The knowledge base's empty state stops
/// telling a reader to write.
const _general = WorkspaceSummary(
  id: '01HWS000000000000000GENERL',
  name: 'Demir Çelik Fabrikası',
  slug: 'demir-celik',
  colorRgb: '#2563EB',
  role: 'member',
);
const _it = WorkspaceSummary(
  id: '01HWS0000000000000000BILGI',
  name: 'Bilgi İşlem',
  slug: 'bilgi-islem',
  colorRgb: '#2563EB',
  role: 'member',
);
const _units = [
  EeUnitScope(
    unitId: 'U1',
    unitName: 'Bilgi İşlem',
    workspaceId: '01HWS0000000000000000BILGI',
  ),
];

class _FakeUnitsApi extends Fake implements EeUnitTicketsApi {
  _FakeUnitsApi({this.fail = false});
  final bool fail;
  int asked = 0;

  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async {
    asked += 1;
    if (fail) throw Exception('offline');
    return const EeUnitTicketsPage(units: _units);
  }
}

class _Selected extends SelectedWorkspace {
  _Selected(this._id);
  final String _id;
  @override
  String? build() => _id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.remove('${kEeMyUnitsCachePrefix}user-1');
  });

  List<Override> scope({
    required String selected,
    EeUnitTicketsApi? api,
    List<String> grants = const [],
  }) => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    currentUserIdProvider.overrideWithValue('user-1'),
    workspacesProvider.overrideWith((ref) async => const [_general, _it]),
    selectedWorkspaceIdProvider.overrideWith(() => _Selected(selected)),
    eeUnitTicketsApiProvider.overrideWithValue(api ?? _FakeUnitsApi()),
    canProvider.overrideWith((ref, id) => grants.contains(id)),
    eeKbArticlesProvider.overrideWith((ref) => Stream.value(const [])),
    eeKbArticleCountsProvider.overrideWith((ref, id) async => null),
  ];

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen,
    List<Override> overrides,
  ) async {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAwTheme(Brightness.light), home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('UI-AUDIT #29', () {
    testWidgets('on the general space the knowledge base says "choose a '
        'unit", and choosing one opens that unit', (tester) async {
      final container = await pump(
        tester,
        const EeKbScreen(),
        scope(selected: _general.id),
      );
      expect(find.byKey(const Key('ee-unit-scope-choose')), findsOneWidget);
      expect(find.text('ee.kb.empty'.tr()), findsNothing);

      await tester.tap(find.byKey(Key('ee-unit-scope-pick-${_it.id}')));
      await tester.pumpAndSettle();
      expect(container.read(currentWorkspaceProvider).value?.id, _it.id);
      expect(find.byKey(const Key('ee-unit-scope-choose')), findsNothing);
      // …and the list now says whose it is.
      expect(
        tester.widget<Text>(find.byKey(const Key('ee-unit-scope-name'))).data,
        'Bilgi İşlem',
      );
    });

    testWidgets('changes: the same door on the general space', (tester) async {
      await pump(tester, const EeChangesScreen(), [
        ...scope(selected: _general.id),
        eeChangeListProvider.overrideWith(
          (ref) => Stream.value(const EeChangeList()),
        ),
      ]);
      expect(find.byKey(const Key('ee-unit-scope-choose')), findsOneWidget);
    });

    testWidgets('a reader is not told to write: the empty knowledge base '
        'depends on kb.write', (tester) async {
      await pump(tester, const EeKbScreen(), scope(selected: _it.id));
      expect(find.text('ee.kb.emptyBodyReader'.tr()), findsOneWidget);
      expect(find.text('ee.kb.emptyBody'.tr()), findsNothing);
    });

    testWidgets('…and a writer is', (tester) async {
      await pump(
        tester,
        const EeKbScreen(),
        scope(selected: _it.id, grants: const ['kb.write']),
      );
      expect(find.text('ee.kb.emptyBody'.tr()), findsOneWidget);
    });

    testWidgets('never answered (offline, first run): the list draws as '
        'before — "not a unit" is never guessed', (tester) async {
      await pump(
        tester,
        const EeKbScreen(),
        scope(selected: _general.id, api: _FakeUnitsApi(fail: true)),
      );
      expect(find.byKey(const Key('ee-unit-scope-choose')), findsNothing);
      expect(find.text('ee.kb.empty'.tr()), findsOneWidget);
    });

    test('the last answer is kept for a device with no signal, and is the '
        'person\'s — sign-out wipes it', () async {
      final online = ProviderContainer(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          currentUserIdProvider.overrideWithValue('user-1'),
          workspacesProvider.overrideWith((ref) async => const [_general, _it]),
          eeUnitTicketsApiProvider.overrideWithValue(_FakeUnitsApi()),
        ],
      );
      addTearDown(online.dispose);
      // Listened: Riverpod pauses a provider nobody listens to.
      online.listen(eeMyUnitsScopeProvider, (_, _) {});
      expect(await online.read(eeMyUnitsScopeProvider.future), hasLength(1));

      final offline = ProviderContainer(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          currentUserIdProvider.overrideWithValue('user-1'),
          workspacesProvider.overrideWith((ref) async => const [_general, _it]),
          eeUnitTicketsApiProvider.overrideWithValue(_FakeUnitsApi(fail: true)),
        ],
      );
      addTearDown(offline.dispose);
      offline.listen(eeMyUnitsScopeProvider, (_, _) {});
      final cached = await offline.read(eeMyUnitsScopeProvider.future);
      expect(cached?.single.workspaceId, _it.id);
      expect(kUserBoundKvPrefixes, contains(kEeMyUnitsCachePrefix));
    });
  });
}
