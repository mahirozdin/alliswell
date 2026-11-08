import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/my_units_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/ee/ui/desk_paths.dart';

/// EE-267 — AW-E19 on the screen: a manager of two units, looking at one,
/// sees the other's broken promise and reaches it in one tap.
///
/// Pumped against the REAL client over a fake HTTP layer, so what is SENT
/// (alerts only, which unit left out, which cursor) is asserted — a fake at
/// the provider level would agree with whatever the model expected.
const _me = '01USERMEAAAAAAAAAAAAAAAAAA';
const _bt = '01WSBTAAAAAAAAAAAAAAAAAAAA';
const _bakim = '01WSBAKIMAAAAAAAAAAAAAAAAA';
const _compressor = '01TICKETCOMPRESSORAAAAAAAA';
const _vpn = '01TICKETVPNAAAAAAAAAAAAAAA';
const _lamp = '01TICKETLAMPAAAAAAAAAAAAAA';

Map<String, dynamic> _row(
  String id,
  int number,
  String subject,
  String workspaceId,
  String unitName, {
  String? sla,
  String? due,
  String status = 'in_progress',
}) => {
  'id': id,
  'number': number,
  'subject': subject,
  'status': status,
  'priority': 'high',
  'slaStatus': sla,
  'slaDueAt': due,
  'unitId': 'U-$unitName',
  'unitName': unitName,
  'workspaceId': workspaceId,
  'updatedAt': '2026-09-25T08:00:00.000Z',
};

const _units = [
  {'unitId': 'U-Bakım', 'unitName': 'Bakım', 'workspaceId': _bakim},
  {'unitId': 'U-BT', 'unitName': 'BT', 'workspaceId': _bt},
];

/// Nobody has chosen a unit yet — and a choice an earlier test persisted is
/// not read back: the store's instance outlives `setMockInitialValues`, so
/// hydrating would carry one test's switch into the next.
class _Unchosen extends SelectedWorkspace {
  @override
  String? build() => null;
}

/// D-3: a unit switch that waits at [gate] before it happens, so a test
/// can take the screen away while a request's unit is being lent.
class _GatedSelect extends _Unchosen {
  static Completer<void>? gate;

  @override
  Future<void> select(String workspaceId) async {
    final wait = gate;
    if (wait != null) {
      gate = null;
      await wait.future;
    }
    await super.select(workspaceId);
  }
}

class _Server implements HttpClientAdapter {
  /// What `/my-units` answers, given what it was asked.
  Map<String, dynamic> Function(Map<String, dynamic> query) answer = (_) => {
    'units': _units,
    'alerts': {'breached': 0, 'warned': 0},
    'tickets': <Object>[],
    'nextCursor': null,
  };
  final List<RequestOptions> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    return ResponseBody.fromString(
      jsonEncode(answer(options.queryParameters)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  Iterable<RequestOptions> get lists =>
      asked.where((o) => o.path == '/api/v1/ee/team/tickets/my-units');
}

/// D-2: a client whose pages are made by [page], counting the asks.
class _PagingApi implements EeUnitTicketsApi {
  _PagingApi(this.page);
  final EeUnitTicketsPage Function(String? cursor) page;
  int calls = 0;

  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async {
    calls += 1;
    return page(cursor);
  }
}

void main() {
  late _Server server;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    server = _Server();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool entitled = true,
    bool offline = false,
    bool gatedSelect = false,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    container = ProviderContainer(
      retry: awRetry,
      overrides: <Override>[
        // OPH-359: the unit scope in the bar reads this.
        eeMyUnitsScopeProvider.overrideWith((ref) async => null),
        // With no answer about units the queue is one unit's; a test that
        // wants the across-units view chooses it, as the scope bar does.
        eeQueueShowsAllUnitsProvider.overrideWith(
          (ref) => ref.watch(eeQueueAllUnitsChosenProvider),
        ),
        eeUnitTicketsApiProvider.overrideWithValue(EeUnitTicketsApi(dio)),
        eeFeatureProvider.overrideWith((ref, name) => entitled),
        currentUserIdProvider.overrideWithValue(_me),
        selectedWorkspaceIdProvider.overrideWith(
          gatedSelect ? _GatedSelect.new : _Unchosen.new,
        ),
        // BT first: the unit open on this device, nobody having chosen.
        workspacesProvider.overrideWith(
          (ref) async => const [
            WorkspaceSummary(
              id: _bt,
              name: 'BT',
              slug: 'bt',
              colorRgb: '#2563EB',
              role: 'member',
            ),
            WorkspaceSummary(
              id: _bakim,
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#16A34A',
              role: 'member',
            ),
          ],
        ),
        // The queue's heartbeat, stilled: one answer, asked once.
        eeCurrentUnitPulledAtProvider.overrideWith((ref) => Stream.value(null)),
        syncEngineProvider.overrideWithValue(null),
        // BT's own queue, from its replica: empty here — the other unit is
        // the point.
        ticketQueueProvider.overrideWith(
          (ref) => Stream.value(const <TicketRecord>[]),
        ),
        ticketAssigneesProvider.overrideWith(
          (ref) => Stream.value(const <String, List<Assignee>>{}),
        ),
        canProvider.overrideWith((ref, permission) => false),
        // The desktop pane's detail (R-15): it never finishes loading here —
        // which unit is open while it shows, and after, is what is tested.
        ticketProvider.overrideWith((ref, id) {
          final detail = StreamController<TicketRecord?>();
          ref.onDispose(detail.close);
          return detail.stream;
        }),
      ],
    );
    addTearDown(container.dispose);
    // The app's shell watches the open unit all the time; a screen pumped on
    // its own would otherwise ask while the list of units is still loading.
    container.listen(currentWorkspaceProvider, (_, _) {});
    if (offline) {
      container.read(serverReachabilityProvider.notifier).unreachable();
    }
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        // D-3: somewhere else, so the list can go while a unit is lent.
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('away')),
        ),
        // OPH-359 (UI-AUDIT #59): "Birimlerim" has an address now; the
        // shelf and the strip open it there.
        GoRoute(
          path: kAwMyUnitsPath,
          builder: (_, state) => EeMyUnitsScreen(
            alertsOnly: state.uri.queryParameters['alerts'] == '1',
          ),
        ),
        // EE-251's address, stood in for: which request was opened.
        GoRoute(
          path: '/tickets/:ticketId',
          builder: (_, state) => Scaffold(
            body: Text(
              'opened ${state.pathParameters['ticketId']}',
              key: const Key('opened'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
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
  }

  String? openUnit() => container.read(currentWorkspaceProvider).value?.id;

  testWidgets('AW-E19: the manager of Bakım and BT, looking at BT, sees '
      'Bakım’s broken promise on the queue — and one tap opens it there', (
    tester,
  ) async {
    server.answer = (query) => {
      'units': _units,
      'alerts': {'breached': 1, 'warned': 0},
      'tickets': [
        _row(
          _compressor,
          1042,
          'Kompresör arızası',
          _bakim,
          'Bakım',
          sla: 'breached',
          due: '2026-09-25T06:00:00.000Z',
        ),
      ],
      'nextCursor': null,
    };
    await pump(tester, const EeTicketQueueScreen());
    expect(openUnit(), _bt);

    // What the strip asked: the alerts, with the unit on screen left out.
    final sent = server.lists.single.queryParameters;
    expect(sent['alerts'], true);
    expect(sent['except'], _bt);
    expect(sent['limit'], 3);

    expect(find.byKey(const Key('other-units-alerts')), findsOneWidget);
    expect(find.textContaining('Kompresör arızası'), findsOneWidget);
    expect(find.textContaining('Bakım'), findsOneWidget);

    await tester.tap(find.byKey(const Key('other-units-alert-$_compressor')));
    await tester.pumpAndSettle();
    // One tap: Bakım is the open unit now, and the request's address opened.
    expect(openUnit(), _bakim);
    expect(find.text('opened $_compressor'), findsOneWidget);
  });

  testWidgets('the strip says nothing when the other units have nothing late, '
      'and asks nothing when the app knows it is offline', (tester) async {
    await pump(tester, const EeTicketQueueScreen());
    expect(server.lists, hasLength(1));
    expect(find.byKey(const Key('other-units-alerts')), findsNothing);
  });

  testWidgets('offline, the strip is not drawn from anything old — it is not '
      'drawn at all, and nothing is asked', (tester) async {
    await pump(tester, const EeTicketQueueScreen(), offline: true);
    expect(server.lists, isEmpty);
    expect(find.byKey(const Key('other-units-alerts')), findsNothing);
  });

  testWidgets('the queue’s shelf has "Birimlerim", and it opens', (
    tester,
  ) async {
    await pump(tester, const EeTicketQueueScreen());
    await tester.tap(find.byKey(const Key('ticket-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-my-units')));
    await tester.pumpAndSettle();
    expect(find.byType(EeMyUnitsScreen), findsOneWidget);
    expect(find.byKey(const Key('my-units-live')), findsOneWidget);
  });

  testWidgets('Birimlerim says it is live, names the units, and lists their '
      'open requests with the unit each lives in', (tester) async {
    server.answer = (query) => {
      'units': _units,
      'alerts': {'breached': 1, 'warned': 1},
      'tickets': [
        _row(
          _compressor,
          1042,
          'Kompresör arızası',
          _bakim,
          'Bakım',
          sla: 'breached',
        ),
        _row(
          _vpn,
          7,
          'VPN',
          _bt,
          'BT',
          sla: 'warned',
          due: '2099-01-01T00:00:00.000Z',
        ),
        _row(_lamp, 12, 'Atölye lambası', _bakim, 'Bakım', status: 'new'),
      ],
      'nextCursor': null,
    };
    await pump(tester, const EeMyUnitsScreen());

    expect(find.text('ee.myUnits.live'.tr()), findsOneWidget);
    expect(
      find.text('ee.myUnits.scope'.tr(args: {'units': 'Bakım, BT'})),
      findsOneWidget,
    );
    expect(
      find.text('ee.myUnits.counts'.tr(args: {'breached': '1', 'warned': '1'})),
      findsOneWidget,
    );
    for (final id in [_compressor, _vpn, _lamp]) {
      expect(find.byKey(Key('unit-ticket-$id')), findsOneWidget);
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('unit-ticket-unit-$_vpn'))).data,
      'BT',
    );
    // The row says how late it is — the same badge as the queue's rows.
    expect(
      find.descendant(
        of: find.byKey(const Key('unit-ticket-$_compressor')),
        matching: find.text('ee.sla.breached'.tr()),
      ),
      findsOneWidget,
    );
    // The whole list was asked for, not the alerts.
    expect(server.lists.single.queryParameters.containsKey('alerts'), isFalse);
  });

  testWidgets('R-11: the whole list is the queue\'s order, newest first — '
      'not a lateness list that only the alerts chip should give', (
    tester,
  ) async {
    // The server pages by lateness: breached, warned, then the rest.
    server.answer = (query) => {
      'units': _units,
      'alerts': {'breached': 1, 'warned': 1},
      'tickets': [
        _row(_lamp, 12, 'Atölye lambası', _bakim, 'Bakım', sla: 'breached'),
        _row(
          _vpn,
          7,
          'VPN',
          _bt,
          'BT',
          sla: 'warned',
          due: '2099-01-01T00:00:00.000Z',
        ),
        _row(_compressor, 1042, 'Kompresör arızası', _bakim, 'Bakım'),
      ],
      'nextCursor': null,
    };
    await pump(tester, const EeMyUnitsScreen());
    double top(String id) =>
        tester.getTopLeft(find.byKey(Key('unit-ticket-$id'))).dy;
    // Without the chip: newest first, as a unit's own queue reads.
    expect(top(_compressor), lessThan(top(_lamp)));
    expect(top(_lamp), lessThan(top(_vpn)));
    // The full list asks for the server's largest page, so the order covers
    // every open request a team usually has, not the first fifty by lateness.
    expect(server.lists.last.queryParameters['limit'], 100);

    // With the chip: the server's lateness order stands.
    await tester.tap(find.byKey(const Key('my-units-alerts')));
    await tester.pumpAndSettle();
    expect(server.lists.last.queryParameters['alerts'], true);
    expect(top(_lamp), lessThan(top(_vpn)));
    expect(top(_vpn), lessThan(top(_compressor)));
  });

  // D-2 (polish 3): the server pages by lateness, so past one page the
  // newest requests (not late, deadlines far off) sat on page 2. R-11
  // ordered only the first page: the first screen was not the newest, and
  // "more" dropped the newest in above what had been read.
  testWidgets('D-2: the newest-first list follows every page before it '
      'orders them — the newest request on page 2 is the first row', (
    tester,
  ) async {
    server.answer = (query) => query['cursor'] == 'c1'
        ? {
            'units': _units,
            'alerts': {'breached': 1, 'warned': 0},
            'tickets': [_row(_vpn, 2000, 'VPN', _bt, 'BT')],
            'nextCursor': null,
          }
        : {
            'units': _units,
            'alerts': {'breached': 1, 'warned': 0},
            'tickets': [
              _row(
                _compressor,
                1042,
                'Kompresör arızası',
                _bakim,
                'Bakım',
                sla: 'breached',
              ),
              _row(_lamp, 12, 'Atölye lambası', _bakim, 'Bakım'),
            ],
            'nextCursor': 'c1',
          };
    await pump(tester, const EeMyUnitsScreen());
    // No tap: the second page was asked for by itself, with the same
    // page size, and the whole set is in one order.
    expect(server.lists.map((o) => o.queryParameters['cursor']), [null, 'c1']);
    expect(server.lists.last.queryParameters['limit'], 100);
    double top(String id) =>
        tester.getTopLeft(find.byKey(Key('unit-ticket-$id'))).dy;
    expect(top(_vpn), lessThan(top(_compressor)));
    expect(top(_compressor), lessThan(top(_lamp)));
    expect(find.byKey(const Key('my-units-more')), findsNothing);
  });

  test('D-2: the pages are followed to a cap, and a repeated cursor ends '
      'the walk', () async {
    final asked = <String?>[];
    final api = _PagingApi((cursor) {
      asked.add(cursor);
      final n = cursor == null ? 0 : int.parse(cursor);
      return EeUnitTicketsPage(
        tickets: [
          EeUnitTicket.fromJson(
            _row('T$n', n + 1, 'Talep $n', _bakim, 'Bakım'),
          ),
        ],
        nextCursor: '${n + 1}',
      );
    });
    final all = await eeAllOpenAcrossUnits(api);
    expect(asked.length, kEeAcrossUnitsMaxPages);
    expect(all.tickets.length, kEeAcrossUnitsMaxPages);
    // Capped: the rest stays a "show more" away.
    expect(all.nextCursor, '$kEeAcrossUnitsMaxPages');

    final loop = _PagingApi(
      (cursor) => EeUnitTicketsPage(
        tickets: [
          EeUnitTicket.fromJson(_row('T1', 1, 'Talep', _bakim, 'Bakım')),
        ],
        nextCursor: 'same',
      ),
    );
    final once = await eeAllOpenAcrossUnits(loop);
    expect(loop.calls, 2);
    expect(once.tickets.length, 1);
    expect(once.nextCursor, isNull);
  });

  testWidgets('the alerts chip asks the server for alerts only', (
    tester,
  ) async {
    await pump(tester, const EeMyUnitsScreen());
    await tester.tap(find.byKey(const Key('my-units-alerts')));
    await tester.pumpAndSettle();
    expect(server.lists.last.queryParameters['alerts'], true);
    // Nothing late: said as such, not as "nothing open".
    expect(find.byKey(const Key('my-units-no-alerts')), findsOneWidget);
  });

  testWidgets('"more" asks for the page after the server’s cursor and adds it '
      'under the rows already there', (tester) async {
    server.answer = (query) => query['cursor'] == 'c1'
        ? {
            'units': _units,
            'alerts': {'breached': 1, 'warned': 0},
            'tickets': [_row(_lamp, 12, 'Atölye lambası', _bakim, 'Bakım')],
            'nextCursor': null,
          }
        : {
            'units': _units,
            'alerts': {'breached': 1, 'warned': 0},
            'tickets': [
              _row(
                _compressor,
                1042,
                'Kompresör arızası',
                _bakim,
                'Bakım',
                sla: 'breached',
              ),
            ],
            'nextCursor': 'c1',
          };
    await pump(tester, const EeMyUnitsScreen());
    // The alerts list keeps the server's pages (D-2 follows them only for
    // the newest-first list).
    await tester.tap(find.byKey(const Key('my-units-alerts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unit-ticket-$_lamp')), findsNothing);

    await tester.tap(find.byKey(const Key('my-units-more')));
    await tester.pumpAndSettle();
    expect(server.lists.last.queryParameters['cursor'], 'c1');
    expect(find.byKey(const Key('unit-ticket-$_compressor')), findsOneWidget);
    expect(find.byKey(const Key('unit-ticket-$_lamp')), findsOneWidget);
    // The last page has no "more".
    expect(find.byKey(const Key('my-units-more')), findsNothing);
  });

  testWidgets('D17.9: when the connection goes, the list goes with it — it is '
      'never shown from an old copy', (tester) async {
    server.answer = (query) => {
      'units': _units,
      'alerts': {'breached': 1, 'warned': 0},
      'tickets': [
        _row(
          _compressor,
          1042,
          'Kompresör arızası',
          _bakim,
          'Bakım',
          sla: 'breached',
        ),
      ],
      'nextCursor': null,
    };
    await pump(tester, const EeMyUnitsScreen());
    expect(find.byKey(const Key('unit-ticket-$_compressor')), findsOneWidget);

    container.read(serverReachabilityProvider.notifier).unreachable();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unit-ticket-$_compressor')), findsNothing);
    expect(find.byKey(const Key('my-units-offline')), findsOneWidget);
  });

  testWidgets('when the app already knows it is offline, it names the '
      'connection and asks nothing', (tester) async {
    await pump(tester, const EeMyUnitsScreen(), offline: true);
    expect(find.byKey(const Key('my-units-offline')), findsOneWidget);
    expect(server.lists, isEmpty);
  });

  // R-15: reading a request of another unit opens that unit for a while —
  // the detail reads its copy — but the person's choice (Home's unit) is
  // not changed by it: closing the request brings the earlier one back.
  Map<String, dynamic> bakimRequest(Map<String, dynamic> query) => {
    'units': _units,
    'alerts': {'breached': 1, 'warned': 0},
    'tickets': [
      _row(
        _compressor,
        1042,
        'Kompresör arızası',
        _bakim,
        'Bakım',
        sla: 'breached',
      ),
    ],
    'nextCursor': null,
  };

  testWidgets('R-15: on a phone, back from another unit’s request returns '
      'to the unit that was open', (tester) async {
    server.answer = bakimRequest;
    await pump(tester, const EeMyUnitsScreen());
    expect(openUnit(), _bt);

    await tester.tap(find.byKey(const Key('unit-ticket-$_compressor')));
    await tester.pumpAndSettle();
    expect(find.text('opened $_compressor'), findsOneWidget);
    expect(openUnit(), _bakim);

    GoRouter.of(tester.element(find.byKey(const Key('opened')))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(EeMyUnitsScreen), findsOneWidget);
    expect(openUnit(), _bt);
  });

  // D-3 (polish 3): the row that opened the request was gone by the time
  // its unit had been lent (the list rebuilt or was left while the switch
  // ran), and `if (!context.mounted) return;` left the unit lent for good:
  // Home stayed on the other unit.
  testWidgets('D-3: the lent unit comes back when the list is gone before '
      'the request could open', (tester) async {
    server.answer = bakimRequest;
    await pump(tester, const EeMyUnitsScreen(), gatedSelect: true);
    expect(openUnit(), _bt);

    final gate = _GatedSelect.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('unit-ticket-$_compressor')));
    await tester.pump();
    // The list goes while the unit switch is under way.
    GoRouter.of(tester.element(find.byType(EeMyUnitsScreen))).go('/away');
    await tester.pumpAndSettle();
    expect(find.byType(EeMyUnitsScreen), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opened')), findsNothing);
    expect(container.read(eeLentUnitProvider), isNull);
    expect(openUnit(), _bt);
  });

  testWidgets('R-15: at a desktop width, closing the pane returns to the unit '
      'that was open, and ↓ to a third request does not lose it', (
    tester,
  ) async {
    server.answer = (query) => {
      ...bakimRequest(query),
      'tickets': [
        ...bakimRequest(query)['tickets'] as List,
        _row(_lamp, 12, 'Atölye lambası', _bakim, 'Bakım'),
      ],
    };
    await pump(tester, const EeTicketQueueScreen());
    container.read(eeQueueAllUnitsChosenProvider.notifier).set(true);
    tester.view.physicalSize = const Size(1440 * 3, 1000 * 3);
    await tester.pumpAndSettle();
    expect(openUnit(), _bt);

    Future<void> step() async {
      for (var i = 0; i < 6; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final pane = find.byKey(const Key('list-detail-pane'));
    await tester.tap(find.byKey(const Key('unit-ticket-$_compressor')));
    await step();
    expect(pane, findsOneWidget);
    expect(openUnit(), _bakim);
    // Still the list across units behind the pane.
    expect(container.read(eeQueueShowsAllUnitsProvider), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await step();
    expect(openUnit(), _bakim);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await step();
    expect(pane, findsNothing);
    expect(openUnit(), _bt);
  });

  testWidgets('a row of the unit already open opens without a switch', (
    tester,
  ) async {
    server.answer = (query) => {
      'units': _units,
      'alerts': {'breached': 0, 'warned': 1},
      'tickets': [
        _row(
          _vpn,
          7,
          'VPN',
          _bt,
          'BT',
          sla: 'warned',
          due: '2099-01-01T00:00:00.000Z',
        ),
      ],
      'nextCursor': null,
    };
    await pump(tester, const EeMyUnitsScreen());
    await tester.tap(find.byKey(const Key('unit-ticket-$_vpn')));
    await tester.pumpAndSettle();
    expect(container.read(selectedWorkspaceIdProvider), isNull);
    expect(openUnit(), _bt);
    expect(find.text('opened $_vpn'), findsOneWidget);
  });

  testWidgets('R-12: across units the bar does not name one workspace — the '
      'chips under it say the scope, and opening a request cannot make the '
      'bar contradict "All units"', (tester) async {
    await pump(tester, const EeTicketQueueScreen());
    // One unit's queue: the switcher is where the queue is (OPH-359).
    expect(find.byKey(const Key('workspace-switcher')), findsOneWidget);

    container.read(eeQueueAllUnitsChosenProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ee-unit-scope-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ee-unit-scope-name'))).data,
      'ee.unitScope.all'.tr(),
    );
    expect(find.byKey(const Key('workspace-switcher')), findsNothing);
  });

  testWidgets('without the entitlement nothing is asked', (tester) async {
    await pump(tester, const EeTicketQueueScreen(), entitled: false);
    expect(server.asked, isEmpty);
    expect(find.byKey(const Key('other-units-alerts')), findsNothing);
  });
}
