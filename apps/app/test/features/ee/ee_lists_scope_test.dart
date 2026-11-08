import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/data/my_tickets_api.dart';
import 'package:alliswell/src/features/ee/data/performance_models.dart';
import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/data/team_address_api.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/performance_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/sla_dashboard_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/assignments_moved_screen.dart';
import 'package:alliswell/src/features/ee/ui/home_ticket_cards.dart';
import 'package:alliswell/src/features/ee/ui/my_tickets_screen.dart';
import 'package:alliswell/src/features/ee/ui/my_units_screen.dart';
import 'package:alliswell/src/features/ee/ui/performance_screen.dart';
import 'package:alliswell/src/features/ee/ui/sla_dashboard_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-409 — the extension's lists answer a manager's first questions: what
/// is open across my units, whose is it, and what does each number count.
///
/// U-18: the queue opens on "All units", not on "choose a unit"; a unit chip
/// filters to that unit's own (offline) queue. U-19: a row names who asked
/// and who has it, and marks "nobody yet". U-20: every count carries its
/// scope, and a share of nothing is "—". U-22: requests on Home. E-03: no
/// "new request" for somebody the team does not know. E-19: the retired
/// assignments address says where its list went. The SLA board and the
/// workload report are tabs of the requests header.
const _general = WorkspaceSummary(
  id: '01HWS000000000000000GENERL',
  name: 'Demir Çelik',
  slug: 'demir-celik',
  colorRgb: '#2563EB',
  role: 'member',
);
const _bt = WorkspaceSummary(
  id: '01HWS00000000000000000BTWS',
  name: 'BT',
  slug: 'bt',
  colorRgb: '#2563EB',
  role: 'member',
);
const _bakim = WorkspaceSummary(
  id: '01HWS000000000000000BAKIMW',
  name: 'Bakım',
  slug: 'bakim',
  colorRgb: '#16A34A',
  role: 'member',
);
const _units = [
  EeUnitScope(
    unitId: 'U-BT',
    unitName: 'BT',
    workspaceId: '01HWS00000000000000000BTWS',
  ),
  EeUnitScope(
    unitId: 'U-BAKIM',
    unitName: 'Bakım',
    workspaceId: '01HWS000000000000000BAKIMW',
  ),
];

const _requester = '01USREQUESTERAAAAAAAAAAAAA';

TicketRecord _ticket(String id, {String status = 'new'}) => TicketRecord(
  id: id,
  workspaceId: _bt.id,
  subject: 'Yazıcı $id',
  status: status,
  priority: 'high',
  source: 'app',
  requesterId: _requester,
  revision: 1,
  createdAt: DateTime.utc(2026, 11, 1),
);

class _FakeUnitsApi extends Fake implements EeUnitTicketsApi {
  _FakeUnitsApi(this.page);
  final EeUnitTicketsPage page;

  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async => page;
}

class _Selected extends SelectedWorkspace {
  _Selected(this._id);
  final String _id;
  @override
  String? build() => _id;
}

class _Sla extends EeSlaDashboardController {
  _Sla(this._value);
  final EeSlaDashboard? _value;
  @override
  Future<EeSlaDashboard?> build() async => _value;
}

class _Perf extends EePerformanceController {
  _Perf(this._value);
  final EePerformance? _value;
  @override
  Future<EePerformance?> build() async => _value;
}

class _Perms extends EePermissionsController {
  _Perms(this._value);
  final EePermissions _value;
  @override
  Future<EePermissions> build() async => _value;
}

final _acrossPage = EeUnitTicketsPage.fromJson({
  'units': [
    for (final u in _units)
      {
        'unitId': u.unitId,
        'unitName': u.unitName,
        'workspaceId': u.workspaceId,
      },
  ],
  'alerts': {'breached': 3, 'warned': 1, 'unassigned': 2},
  'scope': {'reach': 'member', 'unitCount': 2, 'tickets': 'open_now'},
  'tickets': [
    {
      'id': 'A1',
      'number': 41,
      'subject': 'Kompresör',
      'status': 'new',
      'priority': 'high',
      'slaStatus': 'breached',
      'unitId': 'U-BAKIM',
      'unitName': 'Bakım',
      'workspaceId': _bakim.id,
      'requesterName': 'Onur Depo',
      'assigneeNames': <String>[],
    },
    {
      'id': 'A2',
      'number': 7,
      'subject': 'VPN',
      'status': 'in_progress',
      'priority': 'normal',
      'unitId': 'U-BT',
      'unitName': 'BT',
      'workspaceId': _bt.id,
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await localKv.remove('${kEeMyUnitsCachePrefix}user-1');
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const [],
    bool listenWorkspace = false,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // No retry: a typed refusal (not in this team) is the answer under test.
    final container = ProviderContainer(
      overrides: overrides,
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    // The app's shell watches the open unit all the time; only the queue's
    // tests hand it the workspaces to watch.
    if (listenWorkspace) {
      container.listen(currentWorkspaceProvider, (_, _) {});
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAwTheme(Brightness.light), home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  List<Override> queue({
    required String selected,
    List<EeUnitScope>? units = _units,
    Map<String, List<Assignee>> assignees = const {},
    List<TicketRecord>? tickets,
    EeUnitTicketsPage? across,
  }) => [
    eeFeatureProvider.overrideWith((ref, name) => true),
    currentUserIdProvider.overrideWithValue('user-1'),
    workspacesProvider.overrideWith(
      (ref) async => const [_general, _bt, _bakim],
    ),
    selectedWorkspaceIdProvider.overrideWith(() => _Selected(selected)),
    eeMyUnitsScopeProvider.overrideWith((ref) async => units),
    eeUnitTicketsApiProvider.overrideWithValue(
      _FakeUnitsApi(across ?? _acrossPage),
    ),
    eeCurrentUnitPulledAtProvider.overrideWith((ref) => Stream.value(null)),
    syncEngineProvider.overrideWithValue(null),
    ticketQueueProvider.overrideWith(
      (ref) => Stream.value(tickets ?? [_ticket('T1'), _ticket('T2')]),
    ),
    ticketAssigneesProvider.overrideWith((ref) => Stream.value(assignees)),
    eeMemberNamesProvider.overrideWith(
      (ref) => Stream.value(const {_requester: 'Onur Depo'}),
    ),
    canProvider.overrideWith((ref, permission) => false),
    eeSlaDashboardProvider.overrideWith(
      () => _Sla(const EeSlaDashboard(compliance: 80, judged: 10)),
    ),
    eePerformanceProvider.overrideWith(
      () => _Perf(
        const EePerformance(
          from: '2026-10-09',
          to: '2026-11-07',
          units: [],
          agents: [],
          closedIsNotPerformance: '',
        ),
      ),
    ),
  ];

  bool chipSelected(WidgetTester tester, String key) =>
      tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

  group('U-18: the queue opens on all units', () {
    testWidgets('on the general space the queue shows every unit\'s open '
        'requests with their unit, and no replica filters', (tester) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _general.id),
      );
      expect(find.byKey(const Key('ee-unit-scope-choose')), findsNothing);
      expect(find.text('Tüm birimler'), findsWidgets);
      expect(chipSelected(tester, 'ticket-unit-all'), isTrue);
      expect(chipSelected(tester, 'ticket-unit-${_bt.id}'), isFalse);
      // The unit column: each row names its unit.
      expect(find.byKey(const Key('unit-ticket-A1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('unit-ticket-unit-A2'))).data,
        'BT',
      );
      // Filter chips wait for a unit; so does the other-units strip.
      expect(find.byKey(const Key('ticket-filter-new')), findsNothing);
      expect(find.byKey(const Key('other-units-alerts')), findsNothing);
    });

    testWidgets('a unit chip filters to that unit\'s own queue; "all units" '
        'brings every unit back without leaving it', (tester) async {
      final container = await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _general.id),
      );
      await tester.tap(find.byKey(Key('ticket-unit-${_bt.id}')));
      await tester.pumpAndSettle();
      expect(container.read(currentWorkspaceProvider).value?.id, _bt.id);
      expect(chipSelected(tester, 'ticket-unit-${_bt.id}'), isTrue);
      expect(find.byKey(const Key('ticket-T1')), findsOneWidget);
      expect(find.byKey(const Key('ticket-filter-new')), findsOneWidget);
      expect(find.byKey(const Key('unit-ticket-A1')), findsNothing);

      await tester.tap(find.byKey(const Key('ticket-unit-all')));
      await tester.pumpAndSettle();
      expect(container.read(currentWorkspaceProvider).value?.id, _bt.id);
      expect(chipSelected(tester, 'ticket-unit-all'), isTrue);
      expect(find.byKey(const Key('unit-ticket-A1')), findsOneWidget);
      expect(find.byKey(const Key('ticket-T1')), findsNothing);
    });

    testWidgets('inside a unit the unit\'s queue stays the default', (
      tester,
    ) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _bt.id),
      );
      expect(chipSelected(tester, 'ticket-unit-${_bt.id}'), isTrue);
      expect(find.byKey(const Key('ticket-T1')), findsOneWidget);
    });

    testWidgets('units never answered: no scope chips, the queue as before', (
      tester,
    ) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _general.id, units: null),
      );
      expect(find.byKey(const Key('ticket-unit-scope')), findsNothing);
      expect(find.byKey(const Key('ticket-filter-new')), findsOneWidget);
      expect(find.byKey(const Key('ticket-T1')), findsOneWidget);
    });

    // E35 G-D review r1: the toolbar's search used to filter only the unit
    // replica, so across units every request stayed on screen.
    testWidgets('search filters the all-units list and offers the archive', (
      tester,
    ) async {
      final container = await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _general.id),
      );
      container.read(ticketSearchQueryProvider.notifier).set('yokböyle');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-ticket-A1')), findsNothing);
      expect(find.byKey(const Key('unit-ticket-A2')), findsNothing);
      expect(find.byKey(const Key('my-units-search-empty')), findsOneWidget);
      expect(find.byKey(const Key('ticket-search-archive')), findsOneWidget);

      container.read(ticketSearchQueryProvider.notifier).set('KOMPRES');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-ticket-A1')), findsOneWidget);
      expect(find.byKey(const Key('unit-ticket-A2')), findsNothing);
      // A search that found live requests still asks the archive last.
      expect(find.byKey(const Key('ticket-search-archive')), findsOneWidget);

      container.read(ticketSearchQueryProvider.notifier).set('#7');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-ticket-A1')), findsNothing);
      expect(find.byKey(const Key('unit-ticket-A2')), findsOneWidget);
    });
  });

  group('U-19: whose is it', () {
    testWidgets('a row names who asked and who has it, and marks nobody', (
      tester,
    ) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(
          selected: _bt.id,
          assignees: const {
            'T2': [
              Assignee(
                assignmentId: 'AS1',
                userId: 'U2',
                displayName: 'Kemal Usta',
                initials: 'KU',
                colorRgb: '#2563EB',
              ),
            ],
          },
        ),
      );
      expect(find.text('Açan: Onur Depo · Alan: atanmadı'), findsOneWidget);
      expect(find.byKey(const Key('ticket-unassigned-T1')), findsOneWidget);
      expect(find.text('Açan: Onur Depo · Alan: Kemal Usta'), findsOneWidget);
      expect(find.byKey(const Key('ticket-unassigned-T2')), findsNothing);
      // The "unassigned" filter is one tap away, word for word.
      expect(
        find.descendant(
          of: find.byKey(const Key('ticket-filter-unassigned')),
          matching: find.text('Atanmamış'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('across units the people line follows what the server says, '
        'and says nothing it was not told', (tester) async {
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _general.id),
      );
      expect(find.text('Açan: Onur Depo · Alan: atanmadı'), findsOneWidget);
      expect(find.byKey(const Key('ticket-people-A2')), findsNothing);
    });
  });

  group('the dashboards are tabs of the requests header', () {
    testWidgets(
      'SLA and workload open as tabs; the menu no longer hides them',
      (tester) async {
        await pump(
          tester,
          const EeTicketQueueScreen(),
          listenWorkspace: true,
          overrides: queue(selected: _bt.id),
        );
        await tester.tap(find.byKey(const Key('ticket-more')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ticket-sla-dashboard')), findsNothing);
        expect(find.byKey(const Key('ticket-performance')), findsNothing);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('ticket-tab-sla')));
        await tester.pumpAndSettle();
        expect(find.byType(EeSlaDashboardScreen), findsOneWidget);
        expect(find.byKey(const Key('sla-compliance')), findsOneWidget);
        expect(find.byKey(const Key('ticket-T1')), findsNothing);

        await tester.tap(find.byKey(const Key('ticket-tab-workload')));
        await tester.pumpAndSettle();
        expect(find.byType(EePerformanceScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('ticket-tab-queue')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ticket-T1')), findsOneWidget);
      },
    );

    testWidgets('the tabs fit a 360 pt phone at 2× text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        const EeTicketQueueScreen(),
        listenWorkspace: true,
        // The header is under test; rows are measured elsewhere.
        overrides: queue(
          selected: _bt.id,
          tickets: const [],
          across: const EeUnitTicketsPage(units: _units),
        ),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ticket-tab-workload')), findsOneWidget);
    });
  });

  group('U-20: every number says what it counts', () {
    testWidgets('the SLA board shows open-now apart from the stock, with '
        'scope and target', (tester) async {
      final board = EeSlaDashboard.fromJson({
        'compliance': 51.4,
        'judged': 144,
        'bySla': [
          {'key': 'breached', 'count': 70},
          {'key': 'met', 'count': 74},
        ],
        'open': {'breached': 24, 'warned': 7},
        'scope': {'reach': 'member', 'unitCount': 8},
      });
      await pump(
        tester,
        const EeSlaDashboardScreen(),
        overrides: [eeSlaDashboardProvider.overrideWith(() => _Sla(board))],
      );
      expect(find.text('Şu an açık talepler'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('sla-open-breached')),
          matching: find.text('24'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('sla-outcome-breached')),
          matching: find.text('70'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sla-stock-scope')), findsOneWidget);
      expect(find.text('Kapsam: birimleriniz (8)'), findsOneWidget);
      expect(find.text('Hedef: %90'), findsOneWidget);
      expect(find.text('144 talepten 74'), findsOneWidget);
    });

    testWidgets('an older server: no open card, no scope line, no guess', (
      tester,
    ) async {
      await pump(
        tester,
        const EeSlaDashboardScreen(),
        overrides: [
          eeSlaDashboardProvider.overrideWith(
            () => _Sla(const EeSlaDashboard(compliance: 95, judged: 20)),
          ),
        ],
      );
      expect(find.byKey(const Key('sla-open-now')), findsNothing);
      expect(find.byKey(const Key('ee-figure-scope')), findsNothing);
    });

    testWidgets('workload: a share with its denominator, "—" over nothing, '
        'none for a person', (tester) async {
      final panel = EePerformance.fromJson({
        'from': '2026-10-09',
        'to': '2026-11-07',
        'closedIsNotPerformance': '',
        'scope': {'reach': 'team', 'unitCount': 8},
        'units': [
          {
            'key': 'U-BT',
            'label': 'BT',
            'opened': 150,
            'compliance': 51.4,
            'judged': 144,
          },
          {
            'key': 'U-BAKIM',
            'label': 'Bakım',
            'opened': 0,
            'compliance': null,
            'judged': 0,
          },
        ],
        'agents': [
          {
            'key': 'P1',
            'label': 'Kemal Usta',
            'opened': 3,
            'compliance': null,
            'judged': 0,
          },
        ],
        'processTypes': [],
      });
      await pump(
        tester,
        const EePerformanceScreen(),
        overrides: [eePerformanceProvider.overrideWith(() => _Perf(panel))],
      );
      final bt = find.byKey(const Key('perf-compliance-U-BT'));
      expect(
        find.descendant(of: bt, matching: find.text('%51,4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bt, matching: find.text('144 talepten')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('perf-compliance-U-BAKIM')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('perf-compliance-P1')), findsNothing);
      expect(find.byKey(const Key('perf-scope')), findsOneWidget);
      expect(find.text('Kapsam: takımın tamamı'), findsOneWidget);
    });

    testWidgets('Birimlerim says its counts are open now, and whose', (
      tester,
    ) async {
      await pump(
        tester,
        const EeMyUnitsScreen(),
        listenWorkspace: true,
        overrides: queue(selected: _bt.id),
      );
      expect(
        find.text(
          'Şu an açık: 3 talebin süresi aşıldı · 1 talebinki dolmak üzere',
        ),
        findsOneWidget,
      );
      expect(find.text('Kapsam: birimleriniz (2)'), findsOneWidget);
    });
  });

  group('E-03: nobody files into a team that does not know them', () {
    List<Override> mine(AsyncValue<List<EeMyTicket>?> Function() answer) => [
      eeFeatureProvider.overrideWith((ref, name) => true),
      currentUserIdProvider.overrideWithValue('user-1'),
      workspacesProvider.overrideWith((ref) async => const [_general]),
      canProvider.overrideWith((ref, permission) => true),
      eeMyTicketsProvider.overrideWith((ref) async {
        final value = answer();
        if (value.hasError) throw value.error!;
        return value.value;
      }),
    ];

    testWidgets('not in this team: no "new request"', (tester) async {
      await pump(
        tester,
        const EeMyTicketsScreen(),
        overrides: mine(
          () => const AsyncError(EeNoTeamHereException(), StackTrace.empty),
        ),
      );
      expect(find.byKey(const Key('my-tickets-new')), findsNothing);
    });

    testWidgets('a member keeps it', (tester) async {
      await pump(
        tester,
        const EeMyTicketsScreen(),
        overrides: mine(() => const AsyncData([])),
      );
      expect(find.byKey(const Key('my-tickets-new')), findsOneWidget);
    });
  });

  group('U-22: requests on Home', () {
    EePermissions perms({required bool desk, bool governed = true}) =>
        EePermissions(
          workspaceId: _general.id,
          governed: governed,
          permissions: const ['tickets.create'],
          desk: desk,
        );

    List<Override> home({
      bool entitled = true,
      required EePermissions permissions,
      List<EeMyTicket>? mine,
      bool approvalsDoor = false,
      int approvals = 0,
    }) => [
      eeFeatureProvider.overrideWith((ref, name) => entitled),
      currentUserIdProvider.overrideWithValue('user-1'),
      eePermissionsProvider.overrideWith(() => _Perms(permissions)),
      eeMyTicketsProvider.overrideWith((ref) async {
        if (mine == null) throw const EeNoTeamHereException();
        return mine;
      }),
      eeUnitTicketsApiProvider.overrideWithValue(_FakeUnitsApi(_acrossPage)),
      eeApprovalsDoorProvider.overrideWith((ref) => approvalsDoor),
      eeApprovalsBadgeProvider.overrideWith((ref) => approvals),
    ];

    EeMyTicket mineTicket(String id, String status) => EeMyTicket(
      id: id,
      subject: 'Talep $id',
      status: status,
      priority: 'normal',
      createdAt: DateTime.utc(2026, 11, 1),
    );

    Widget host() => const Scaffold(body: EeHomeTicketCards());

    testWidgets('a member gets "new request" and their open requests', (
      tester,
    ) async {
      await pump(
        tester,
        host(),
        overrides: home(
          permissions: perms(desk: false),
          mine: [
            mineTicket('1', 'new'),
            mineTicket('2', 'waiting'),
            mineTicket('3', 'closed'),
          ],
        ),
      );
      expect(find.text('Yeni talep açın'), findsOneWidget);
      expect(find.text('Açık taleplerim (2)'), findsOneWidget);
      expect(find.byKey(const Key('ee-home-desk-summary')), findsNothing);
    });

    testWidgets('a desk gets late, unassigned and approvals — each a door', (
      tester,
    ) async {
      await pump(
        tester,
        host(),
        overrides: home(
          permissions: perms(desk: true),
          mine: const [],
          approvalsDoor: true,
          approvals: 2,
        ),
      );
      expect(find.text('Birimleriniz'), findsOneWidget);
      expect(find.text('3 talep gecikti'), findsOneWidget);
      expect(find.text('2 talep atanmamış'), findsOneWidget);
      expect(find.text('Onayınızı bekleyen 2'), findsOneWidget);
      expect(find.byKey(const Key('ee-home-member-cards')), findsNothing);
      // Each figure is a 44-point door.
      final size = tester.getSize(find.byKey(const Key('ee-home-breached')));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    // E35 G-D review r1: the figure counts across the person's units, so
    // its door opens every unit's list, filtered to nobody's — not the unit
    // on screen, and not every request.
    testWidgets('the unassigned figure opens every unit\'s unassigned '
        'requests', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => host()),
          GoRoute(
            path: '/tickets',
            builder: (_, _) => const EeTicketQueueScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          ...queue(selected: _bt.id),
          eePermissionsProvider.overrideWith(() => _Perms(perms(desk: true))),
          eeApprovalsDoorProvider.overrideWith((ref) => false),
          eeApprovalsBadgeProvider.overrideWith((ref) => 0),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      container.listen(currentWorkspaceProvider, (_, _) {});
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A search left behind on the requests screen (E35 G-D review r2):
      // the figure's list must not open filtered by it.
      container.read(ticketSearchQueryProvider.notifier).set('yokböyle');
      await tester.tap(find.byKey(const Key('ee-home-unassigned')));
      await tester.pumpAndSettle();
      expect(container.read(ticketSearchQueryProvider), isEmpty);
      // Inside unit BT, yet the list is every unit's: the count was.
      expect(chipSelected(tester, 'ticket-unit-all'), isTrue);
      expect(find.byKey(const Key('ticket-T1')), findsNothing);
      // A1 is nobody's; A2's people were not told, so it is not counted.
      expect(find.byKey(const Key('unit-ticket-A1')), findsOneWidget);
      expect(find.byKey(const Key('unit-ticket-A2')), findsNothing);
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('my-units-unassigned')))
            .selected,
        isTrue,
      );
      // One tap takes the filter off again.
      await tester.tap(find.byKey(const Key('my-units-unassigned')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit-ticket-A2')), findsOneWidget);
    });

    testWidgets('a plain build, a personal space and a stranger see nothing', (
      tester,
    ) async {
      for (final overrides in [
        home(entitled: false, permissions: perms(desk: false), mine: const []),
        home(permissions: perms(desk: false, governed: false), mine: const []),
        home(permissions: perms(desk: false)),
      ]) {
        await pump(tester, host(), overrides: overrides);
        expect(find.byKey(const Key('ee-home-member-cards')), findsNothing);
        expect(find.byKey(const Key('ee-home-desk-summary')), findsNothing);
      }
    });
  });

  testWidgets('E-19: the old assignments address says where the list went '
      'and takes the person there', (tester) async {
    final router = GoRouter(
      initialLocation: '/settings/team/assignments',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/settings/team/assignments',
          builder: (_, _) => const EeAssignmentsMovedScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: buildAwTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Atamalar Ana Sayfa\'ya taşındı'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ee-assignments-moved-home')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
