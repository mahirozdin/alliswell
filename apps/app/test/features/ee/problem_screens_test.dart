import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/ee/data/problems_api.dart';
import 'package:alliswell/src/features/ee/data/problems_models.dart';
import 'package:alliswell/src/features/ee/problems_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/new_problem_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-270 (AW-E09, the problem half) — known faults on the phone.
///
/// The report's scenario first: "let's open the known-error record" — the
/// problem's detail and its workaround are shown. Then what it stands on: the
/// whole record opens with no signal from the device's copy, the requests it
/// explains come from the server (and say so when they cannot), nothing is
/// asked without the entitlement, the list puts known errors first and
/// searches with no signal, and the form raises a record in the desk on
/// screen or, from a request, in the request's (EE-280).
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const otherWs = '01WSBBBBBBBBBBBBBBBBBBBBBB';
const printerId = '01PRPRINTERAAAAAAAAAAAAAAA';
const vpnId = '01PRVPNAAAAAAAAAAAAAAAAAAA';
const doneId = '01PRDONEAAAAAAAAAAAAAAAAAA';
const elsewhereId = '01PRELSEWHEREAAAAAAAAAAAAA';
const serverOnlyId = '01PRSERVERONLYAAAAAAAAAAAA';
const ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

Map<String, dynamic> _problem(
  String id, {
  required String title,
  required String symptom,
  String status = 'known_error',
  String? workaround,
  String? rootCause,
  String workspaceId = ws,
}) => {
  'id': id,
  'workspaceId': workspaceId,
  'title': title,
  'symptom': symptom,
  'workaround': workaround,
  'rootCause': rootCause,
  'permanentAction': null,
  'status': status,
  'createdBy': null,
  'resolvedAt': null,
  'revision': 1,
  'createdAt': '2026-09-20T08:00:00.000Z',
  'updatedAt': '2026-09-20T08:00:00.000Z',
};

/// The server, as a script (the change screens' test's shape).
class _Server implements HttpClientAdapter {
  final Map<String, Object? Function(RequestOptions)> script = {};
  final List<String> asked = [];
  final Map<String, Object?> sent = {};
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    asked.add(key);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    const json = {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    final line = script[key];
    if (line == null) {
      return ResponseBody.fromString(
        '{"code":"NOT_FOUND"}',
        404,
        headers: json,
      );
    }
    sent[key] = options.data;
    final created = options.method == 'POST' && key.endsWith('/problems');
    return ResponseBody.fromString(
      jsonEncode(line(options)),
      created ? 201 : 200,
      headers: json,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AwDatabase db;
  late _Server server;
  late ProviderContainer container;
  var entitled = true;
  var grants = <String>{};

  setUp(() async {
    entitled = true;
    grants = {};
    AwI18n.instance.setActiveCached(const Locale('tr'));
    SharedPreferences.setMockInitialValues({});
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    server = _Server();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = server;
    container = ProviderContainer(
      retry: awRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: ws,
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
        ),
        eeFeatureProvider.overrideWith((ref, name) => entitled),
        canProvider.overrideWith((ref, id) => grants.contains(id)),
        eeProblemsApiProvider.overrideWithValue(EeProblemsApi(dio)),
        syncEngineProvider.overrideWithValue(null),
      ],
    );
    dio.interceptors.add(
      ReachabilityInterceptor(
        container.read(serverReachabilityProvider.notifier),
      ),
    );
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 4,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_problem',
          entityId: printerId,
          operation: 'create',
          data: _problem(
            printerId,
            title: 'Etiket yazıcısı bekleme sonrası sıkışıyor',
            symptom: 'Gece bekleme modundan sonra ilk etikette kağıt sıkışıyor',
            workaround: 'Vardiya başında yazıcıyı bir kez kapatıp açın',
            rootCause: 'Bekleme dönüşünde ısıtıcı geç devreye giriyor',
          ),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_problem',
          entityId: vpnId,
          operation: 'create',
          data: _problem(
            vpnId,
            title: 'VPN sabah bağlanmıyor',
            symptom: 'Saat 8 ile 9 arasında VPN bağlantısı düşüyor',
            status: 'investigating',
          ),
        ),
        SyncChange(
          revision: 3,
          entityType: 'ee_problem',
          entityId: doneId,
          operation: 'create',
          data: _problem(
            doneId,
            title: 'Pres hattı sensörü yanlış okuyor',
            symptom: 'Pres sensörü her 200 baskıda bir sıfır okuyor',
            status: 'resolved',
          ),
        ),
        // Another unit's record, left by an earlier visit.
        SyncChange(
          revision: 4,
          entityType: 'ee_problem',
          entityId: elsewhereId,
          operation: 'create',
          data: _problem(
            elsewhereId,
            title: 'Kalite laboratuvarı terazisi kayıyor',
            symptom: 'Terazi ısınınca yanlış tartıyor',
            workspaceId: otherWs,
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  void scriptPrinter() {
    server.script['GET /api/v1/ee/team/problems/$printerId'] = (_) => _problem(
      printerId,
      title: 'Etiket yazıcısı bekleme sonrası sıkışıyor',
      symptom: 'Gece bekleme modundan sonra ilk etikette kağıt sıkışıyor',
      workaround: 'Vardiya başında yazıcıyı bir kez kapatıp açın',
      rootCause: 'Bekleme dönüşünde ısıtıcı geç devreye giriyor',
    );
    server.script['GET /api/v1/ee/team/problems/$printerId/tickets'] = (_) => {
      'tickets': [
        {
          'id': ticketId,
          'workspaceId': ws,
          'number': 1042,
          'subject': 'Etiket yazıcısı her sabah sıkışıyor',
          'status': 'in_progress',
          'priority': 'high',
          'createdAt': '2026-09-24T08:00:00.000Z',
        },
      ],
      'count': 1,
      'elsewhere': 2,
    };
  }

  Future<void> pumpAt(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: eeProblemRoutes(),
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

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> letSnackbarGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('AW-E09: "let\'s open the known-error record" — the problem\'s '
      'detail and its workaround are shown, with the requests it explains', (
    tester,
  ) async {
    tallScreen(tester);
    scriptPrinter();
    await pumpAt(tester, '/problems/$printerId');

    expect(
      find.text('Etiket yazıcısı bekleme sonrası sıkışıyor'),
      findsOneWidget,
    );
    expect(find.text('Bilinen hata'), findsOneWidget);
    // The workaround, in full, first.
    expect(
      find.descendant(
        of: find.byKey(const Key('problem-workaround')),
        matching: find.text('Vardiya başında yazıcıyı bir kez kapatıp açın'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Gece bekleme modundan sonra ilk etikette kağıt sıkışıyor'),
      findsOneWidget,
    );
    expect(
      find.text('Bekleme dönüşünde ısıtıcı geç devreye giriyor'),
      findsOneWidget,
    );
    // The requests it explains: the one this person may see by subject, the
    // rest as a count.
    expect(
      find.descendant(
        of: find.byKey(const Key('problem-request-$ticketId')),
        matching: find.text('#1042 · Etiket yazıcısı her sabah sıkışıyor'),
      ),
      findsOneWidget,
    );
    expect(find.text('Çalışmadığınız birimlerde 2 tane daha'), findsOneWidget);
  });

  testWidgets('the record opens with no signal; its requests say they need a '
      'connection, and nothing is asked again', (tester) async {
    server.offline = true;
    await pumpAt(tester, '/problems/$printerId');

    expect(
      find.descendant(
        of: find.byKey(const Key('problem-workaround')),
        matching: find.text('Vardiya başında yazıcıyı bir kez kapatıp açın'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('problem-live-offline')), findsOneWidget);
    // The first attempt's two reads go out together, before the first
    // failure has taught the app anything; after it, nothing more is sent —
    // not when the retry window passes either.
    final first = server.asked.length;
    expect(first, lessThanOrEqualTo(2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(server.asked, hasLength(first));
  });

  testWidgets('without the entitlement nothing is asked, and the record still '
      'reads', (tester) async {
    entitled = false;
    await pumpAt(tester, '/problems/$printerId');

    expect(find.byKey(const Key('problem-workaround')), findsOneWidget);
    expect(server.asked, isEmpty);
  });

  testWidgets('a record with no workaround says so rather than drawing an '
      'empty card', (tester) async {
    server.script['GET /api/v1/ee/team/problems/$vpnId'] = (_) => _problem(
      vpnId,
      title: 'VPN sabah bağlanmıyor',
      symptom: 'Saat 8 ile 9 arasında VPN bağlantısı düşüyor',
      status: 'investigating',
    );
    server.script['GET /api/v1/ee/team/problems/$vpnId/tickets'] = (_) => {
      'tickets': const [],
      'count': 0,
      'elsewhere': 0,
    };
    await pumpAt(tester, '/problems/$vpnId');

    expect(find.byKey(const Key('problem-no-workaround')), findsOneWidget);
    expect(find.byKey(const Key('problem-workaround')), findsNothing);
    expect(find.byKey(const Key('problem-requests-none')), findsOneWidget);
  });

  testWidgets('a record this device does not hold is drawn from the server, '
      'and says so', (tester) async {
    server.script['GET /api/v1/ee/team/problems/$serverOnlyId'] = (_) =>
        _problem(
          serverOnlyId,
          title: 'Depo tarayıcısı ağdan düşüyor',
          symptom: 'El terminali her saat başı ağı kaybediyor',
          workspaceId: otherWs,
        );
    server.script['GET /api/v1/ee/team/problems/$serverOnlyId/tickets'] = (_) =>
        {'tickets': const [], 'count': 0, 'elsewhere': 3};
    await pumpAt(tester, '/problems/$serverOnlyId');

    expect(find.text('Depo tarayıcısı ağdan düşüyor'), findsOneWidget);
    expect(find.byKey(const Key('problem-from-server')), findsOneWidget);
    expect(find.byKey(const Key('problem-requests-elsewhere')), findsOneWidget);
  });

  testWidgets('the list: known errors first, the workaround said on the row, '
      'and search narrows it with no signal', (tester) async {
    server.offline = true;
    await pumpAt(tester, '/problems');

    // Another unit's record stays in that unit's list.
    expect(find.text('Kalite laboratuvarı terazisi kayıyor'), findsNothing);
    final known = tester.getTopLeft(
      find.byKey(const Key('problem-$printerId')),
    );
    final open = tester.getTopLeft(find.byKey(const Key('problem-$vpnId')));
    final done = tester.getTopLeft(find.byKey(const Key('problem-$doneId')));
    expect(known.dy, lessThan(open.dy));
    expect(open.dy, lessThan(done.dy));
    expect(
      find.byKey(const Key('problem-section-known_error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('problem-has-workaround-$printerId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('problem-has-workaround-$vpnId')),
      findsNothing,
    );

    // Typed without Turkish letters, the way a technician types.
    await tester.tap(find.byKey(const Key('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('problem-search')),
      'baglanmiyor',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('problem-$vpnId')), findsOneWidget);
    expect(find.byKey(const Key('problem-$printerId')), findsNothing);
    expect(server.asked, isEmpty);
  });

  testWidgets('EE-280: from a request, the known-error record carries the '
      'request and lets it decide the desk', (tester) async {
    tallScreen(tester);
    grants = {'problems.manage', 'tickets.link'};
    server.script['POST /api/v1/ee/team/problems'] = (o) => _problem(
      '01PRNEWAAAAAAAAAAAAAAAAAAA',
      title: (o.data as Map)['title'] as String,
      symptom: (o.data as Map)['symptom'] as String,
      status: 'investigating',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeNewProblemScreen(
            source: EeProblemSource(
              ticketId: ticketId,
              subject: 'Etiket yazıcısı her sabah sıkışıyor',
              number: 1042,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('problem-new-source')),
        matching: find.textContaining('#1042'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bilinen hata kaydı'), findsOneWidget);
    final save = find.byKey(const Key('problem-new-save'));
    // No symptom, no record: it is how anybody recognises the fault.
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('problem-new-symptom')),
      'İlk etikette kağıt sıkışıyor',
    );
    await tester.enterText(
      find.byKey(const Key('problem-new-workaround')),
      'Yazıcıyı kapatıp açın',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = server.sent['POST /api/v1/ee/team/problems']! as Map;
    expect(body['sourceTicketId'], ticketId);
    expect(body.containsKey('workspaceId'), isFalse);
    expect(body['title'], 'Etiket yazıcısı her sabah sıkışıyor');
    expect(body['workaround'], 'Yazıcıyı kapatıp açın');
    await letSnackbarGo(tester);
  });

  testWidgets('from the list, the record is filed in the desk on screen', (
    tester,
  ) async {
    tallScreen(tester);
    grants = {'problems.manage'};
    server.script['POST /api/v1/ee/team/problems'] = (o) => _problem(
      '01PRNEWAAAAAAAAAAAAAAAAAAA',
      title: (o.data as Map)['title'] as String,
      symptom: (o.data as Map)['symptom'] as String,
      status: 'investigating',
    );
    await pumpAt(tester, '/problems/new');
    await tester.enterText(
      find.byKey(const Key('problem-new-title')),
      'Forklift şarj istasyonu kapanıyor',
    );
    await tester.enterText(
      find.byKey(const Key('problem-new-symptom')),
      'Gece şarjda istasyon kendini kapatıyor',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('problem-new-save')));
    await tester.pumpAndSettle();

    final body = server.sent['POST /api/v1/ee/team/problems']! as Map;
    expect(body['workspaceId'], ws);
    expect(body.containsKey('sourceTicketId'), isFalse);
    expect(body.containsKey('workaround'), isFalse);
    await letSnackbarGo(tester);
  });

  testWidgets('offline, the button is grey and says why', (tester) async {
    tallScreen(tester);
    grants = {'problems.manage'};
    container.read(serverReachabilityProvider.notifier).unreachable();
    await pumpAt(tester, '/problems/new');
    await tester.enterText(find.byKey(const Key('problem-new-title')), 'x');
    await tester.enterText(find.byKey(const Key('problem-new-symptom')), 'x');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('problem-new-save')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('problem-new-offline')), findsOneWidget);
    expect(server.asked, isEmpty);
  });
}
