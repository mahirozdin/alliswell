import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    container = ProviderContainer(
      retry: awRetry,
      overrides: <Override>[
        eeUnitTicketsApiProvider.overrideWithValue(EeUnitTicketsApi(dio)),
        eeFeatureProvider.overrideWith((ref, name) => entitled),
        currentUserIdProvider.overrideWithValue(_me),
        selectedWorkspaceIdProvider.overrideWith(_Unchosen.new),
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

  testWidgets('without the entitlement nothing is asked', (tester) async {
    await pump(tester, const EeTicketQueueScreen(), entitled: false);
    expect(server.asked, isEmpty);
    expect(find.byKey(const Key('other-units-alerts')), findsNothing);
  });
}
