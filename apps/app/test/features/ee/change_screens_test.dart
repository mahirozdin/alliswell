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
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/changes_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_api.dart';
import 'package:alliswell/src/features/ee/data/changes_api.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ui/new_change_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-269 (AW-E09) — change management on the phone.
///
/// The report's scenario first: the IT manager signs the change and sees
/// what its window clashes with, by name. Then the halves it stands on — the
/// plan opens with no signal from the device's copy, the rest says it needs a
/// connection, the buttons follow the server's `canDecide`, nothing is asked
/// without the entitlement — and the form, which files a change in the desk
/// on screen or, raised from a request, in the request's (EE-279).
///
/// The rows arrive through the applier a real pull uses; the screens are
/// reached through the router's own change routes; the server is a script at
/// the HTTP layer, so every request the screens make is counted.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const otherWs = '01WSBBBBBBBBBBBBBBBBBBBBBB';
const diskId = '01CHDISKAAAAAAAAAAAAAAAAAA';
const backupId = '01CHBACKUPAAAAAAAAAAAAAAAA';
const draftId = '01CHDRAFTAAAAAAAAAAAAAAAAA';
const doneId = '01CHDONEAAAAAAAAAAAAAAAAAA';
const elsewhereId = '01CHELSEWHEREAAAAAAAAAAAAA';
const approvalId = '01APPROVALAAAAAAAAAAAAAAAA';
const freezeId = '01FREEZEAAAAAAAAAAAAAAAAAA';
const hat3 = '01SVHAT3AAAAAAAAAAAAAAAAAA';

final _tomorrow = DateTime.now().add(const Duration(days: 1));
final _start = DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, 14);
final _end = _start.add(const Duration(hours: 7));

Map<String, dynamic> _change(
  String id, {
  required String title,
  String workspaceId = ws,
  String type = 'normal',
  String status = 'awaiting_approval',
  String risk = 'high',
  DateTime? start,
  DateTime? end,
  List<String> serviceIds = const [],
  String? sourceTicketId,
}) => {
  'id': id,
  'workspaceId': workspaceId,
  'title': title,
  'description': null,
  'type': type,
  'status': status,
  'risk': risk,
  'impact': 'Hat 3 iki saat durur',
  'rollbackPlan': 'Eski diske geri dön, RAID yeniden kurulur',
  'windowStart': start?.toUtc().toIso8601String(),
  'windowEnd': end?.toUtc().toIso8601String(),
  'serviceIds': serviceIds,
  'sourceTicketId': sourceTicketId,
  'revision': 1,
  'createdAt': '2026-09-20T08:00:00.000Z',
  'updatedAt': '2026-09-20T08:00:00.000Z',
};

/// The server, as a script. Every request is recorded; a path with no line in
/// the script answers 404; [offline] makes every request die the way airplane
/// mode does.
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
    final line = script[key];
    const json = {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    if (line == null) {
      return ResponseBody.fromString(
        '{"code":"NOT_FOUND"}',
        404,
        headers: json,
      );
    }
    sent[key] = options.data;
    final created = options.method == 'POST' && key.endsWith('/changes');
    return ResponseBody.fromString(
      jsonEncode(line(options)),
      created ? 201 : 200,
      headers: json,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Catalogue extends EeServicesController {
  @override
  Future<List<EeService>?> build() async => const [
    EeService(id: hat3, name: 'Hat 3 PLC'),
  ];
}

void main() {
  late AwDatabase db;
  late _Server server;
  late ProviderContainer container;
  var entitled = true;
  var grants = <String>{};

  Future<void> setUpWith() async {
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
        eeChangesApiProvider.overrideWithValue(EeChangesApi(dio)),
        eeApprovalsApiProvider.overrideWithValue(EeApprovalsApi(dio)),
        eeServicesProvider.overrideWith(_Catalogue.new),
        // The screens poke the engine after a write; there is no engine here.
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
      toRevision: 5,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_change',
          entityId: diskId,
          operation: 'create',
          data: _change(
            diskId,
            title: 'Hat 3 sunucu disk değişimi',
            start: _start,
            end: _end,
          ),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_change',
          entityId: draftId,
          operation: 'create',
          data: _change(
            draftId,
            title: 'WMS etiket yazıcısı sürücüsü',
            status: 'draft',
            risk: 'low',
          ),
        ),
        SyncChange(
          revision: 3,
          entityType: 'ee_change',
          entityId: doneId,
          operation: 'create',
          data: _change(
            doneId,
            title: 'Pres hattı PLC yazılımı',
            type: 'standard',
            status: 'implemented',
            risk: 'medium',
            start: DateTime.now().subtract(const Duration(days: 6)),
            end: DateTime.now().subtract(const Duration(days: 6, hours: -2)),
          ),
        ),
        // Another unit's change, left on the device by an earlier visit. It
        // is not THIS unit's list, and the list must not pretend it is.
        SyncChange(
          revision: 4,
          entityType: 'ee_change',
          entityId: elsewhereId,
          operation: 'create',
          data: _change(
            elsewhereId,
            title: 'Kalite laboratuvarı ağ anahtarı',
            workspaceId: otherWs,
            start: _start,
            end: _end,
          ),
        ),
      ],
    );
  }

  /// The server's half of the disk change, as the manager sees it.
  void scriptDiskChange({
    String status = 'pending',
    bool canDecide = true,
    String? approverUserId,
    String? approverName,
  }) {
    server.script['GET /api/v1/ee/team/changes/$diskId'] = (_) => _change(
      diskId,
      title: 'Hat 3 sunucu disk değişimi',
      start: _start,
      end: _end,
      serviceIds: const [hat3],
    );
    server.script['GET /api/v1/ee/team/changes/$diskId/approvals'] = (_) => {
      'approvals': [
        {
          'id': approvalId,
          'status': status,
          'approverUserId': approverUserId,
          'approverRoleKey': approverUserId == null ? 'admin' : null,
          'approverName': approverName,
          'requestReason': 'Hat 3 sunucu disk değişimi',
          'decidedBy': status == 'pending' ? null : '01USERAYLA',
          'decidedByName': status == 'pending' ? null : 'Ayla Amir',
          'decidedAt': status == 'pending' ? null : '2026-09-25T10:00:00.000Z',
          'decisionReason': status == 'pending'
              ? null
              : 'CAB: yedek alındıktan sonra',
          'dueAt': null,
          'createdAt': '2026-09-25T09:00:00.000Z',
          'canDecide': status == 'pending' && canDecide,
        },
      ],
    };
    server.script['GET /api/v1/ee/team/changes/$diskId/assets'] = (_) => {
      'assets': [
        {
          'linkId': '01LINK',
          'assetId': '01ASSETSRV3',
          'tag': 'SRV-3',
          'name': 'Hat 3 sunucusu',
          'status': 'in_use',
          'location': 'Sunucu odası',
        },
      ],
    };
    server.script['GET /api/v1/ee/team/changes/calendar'] = (_) => {
      'changes': [
        {
          ..._change(
            diskId,
            title: 'Hat 3 sunucu disk değişimi',
            start: _start,
            end: _end,
            serviceIds: const [hat3],
          ),
          'clashes': [
            {
              'changeId': backupId,
              'title': 'Hat 3 PLC yedeği',
              'type': 'standard',
              'status': 'scheduled',
              'windowStart': _start.toUtc().toIso8601String(),
              'windowEnd': _start
                  .add(const Duration(hours: 2))
                  .toUtc()
                  .toIso8601String(),
            },
          ],
        },
      ],
      'freezes': [
        {
          'id': freezeId,
          'startsAt': _start
              .add(const Duration(hours: 5))
              .toUtc()
              .toIso8601String(),
          'endsAt': _start
              .add(const Duration(days: 2))
              .toUtc()
              .toIso8601String(),
          'reason': 'Yıl sonu sayımı',
          'createdBy': null,
          'createdAt': '2026-09-20T08:00:00.000Z',
        },
      ],
    };
  }

  setUp(() async {
    entitled = true;
    grants = {};
    await setUpWith();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Scrolls the screen's list until [finder] is built and on screen — a
  /// lazily built list does not build what is below the fold, so
  /// `ensureVisible` alone finds nothing there.
  Future<void> reveal(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );

  /// A snackbar keeps a timer for its display time; let it run out so the
  /// test ends with nothing pending.
  Future<void> letSnackbarGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// A phone held upright and long enough that the whole form is built —
  /// the checks below are about the form's rules, not about scrolling.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpAt(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: eeChangeRoutes(),
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

  testWidgets('AW-E09: "the IT manager signs the change on the phone and sees '
      'the calendar clash" — the signature is theirs to give, and both '
      'conflicts are named', (tester) async {
    scriptDiskChange();
    var signed = false;
    server.script['POST /api/v1/ee/team/approvals/$approvalId/decision'] = (_) {
      signed = true;
      // What the change reads back after the door answered.
      scriptDiskChange(status: 'approved');
      return {
        'id': approvalId,
        'targetType': 'ee_change',
        'targetId': diskId,
        'approverUserId': null,
        'approverRoleKey': 'admin',
        'status': 'approved',
        'requestReason': 'Hat 3 sunucu disk değişimi',
        'decidedBy': '01USERAYLA',
        'decidedAt': '2026-09-25T10:00:00.000Z',
        'decisionReason': 'CAB: yedek alındıktan sonra',
        'dueAt': null,
        'createdAt': '2026-09-25T09:00:00.000Z',
        'updatedAt': '2026-09-25T10:00:00.000Z',
        'target': null,
      };
    };

    await pumpAt(tester, '/changes/$diskId');

    // The plan, from the device.
    expect(find.text('Hat 3 sunucu disk değişimi'), findsOneWidget);
    expect(find.text('Yüksek risk'), findsOneWidget);
    expect(find.text('Onay bekliyor'), findsOneWidget);
    // The signature is asked of a role this person holds, and they may give
    // it: the server said so (`canDecide`).
    expect(find.text('Yönetici onayı bekleniyor'), findsOneWidget);
    expect(find.text('İmzanız bekleniyor.'), findsOneWidget);
    // The calendar: the freeze by its reason, the clash by the other change's
    // title — the two sentences the report asked to see.
    expect(
      find.descendant(
        of: find.byKey(const Key('change-freeze-$freezeId')),
        matching: find.textContaining('“Yıl sonu sayımı” dondurmasıyla'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('change-clash-$backupId')),
        matching: find.textContaining('“Hat 3 PLC yedeği”'),
      ),
      findsOneWidget,
    );
    // What it touches.
    expect(find.byKey(const Key('change-service-$hat3')), findsOneWidget);
    expect(find.text('SRV-3 · Hat 3 sunucusu'), findsOneWidget);

    // The signature: a reason first (both buttons stay grey without one),
    // then EE-184's door.
    await reveal(
      tester,
      find.byKey(const Key('change-approval-approve-$approvalId')),
    );
    await tester.tap(
      find.byKey(const Key('change-approval-approve-$approvalId')),
    );
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('ee-approval-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('ee-approval-reason')),
      'CAB: yedek alındıktan sonra',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(signed, isTrue);
    expect(server.sent['POST /api/v1/ee/team/approvals/$approvalId/decision'], {
      'decision': 'approved',
      'reason': 'CAB: yedek alındıktan sonra',
    });
    // Read again, not patched: the detail now says who signed.
    expect(find.text('Ayla Amir onayladı'), findsOneWidget);
    expect(
      find.byKey(const Key('change-approval-approve-$approvalId')),
      findsNothing,
    );
    await letSnackbarGo(tester);
  });

  testWidgets('the plan opens with no signal; the rest says it needs a '
      'connection, and asks once', (tester) async {
    server.offline = true;
    await pumpAt(tester, '/changes/$diskId');

    expect(find.text('Hat 3 sunucu disk değişimi'), findsOneWidget);
    expect(find.text('Hat 3 iki saat durur'), findsOneWidget);
    expect(
      find.text('Eski diske geri dön, RAID yeniden kurulur'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('change-live-offline')), findsOneWidget);
    // One request died and taught the app; nothing after it was sent.
    expect(server.asked, hasLength(1));
  });

  testWidgets('a signature asked of somebody else says who, and draws no '
      'button', (tester) async {
    scriptDiskChange(
      canDecide: false,
      approverUserId: '01USERCEM',
      approverName: 'Cem Depo',
    );
    await pumpAt(tester, '/changes/$diskId');

    expect(find.text('Cem Depo onayı bekleniyor'), findsOneWidget);
    expect(
      find.byKey(const Key('change-approval-approve-$approvalId')),
      findsNothing,
    );
    expect(find.text('İmzanız bekleniyor.'), findsNothing);
  });

  testWidgets('without the entitlement nothing is asked, and the plan still '
      'reads', (tester) async {
    entitled = false;
    await pumpAt(tester, '/changes/$diskId');

    expect(find.text('Hat 3 sunucu disk değişimi'), findsOneWidget);
    expect(server.asked, isEmpty);
  });

  testWidgets('a change this device does not hold is drawn from the server, '
      'and says so', (tester) async {
    server.script['GET /api/v1/ee/team/changes/$backupId'] = (_) => _change(
      backupId,
      title: 'Hat 3 PLC yedeği',
      type: 'standard',
      status: 'scheduled',
      risk: 'low',
      start: _start,
      end: _start.add(const Duration(hours: 2)),
    );
    server.script['GET /api/v1/ee/team/changes/$backupId/approvals'] = (_) => {
      'approvals': const [],
    };
    server.script['GET /api/v1/ee/team/changes/$backupId/assets'] = (_) => {
      'assets': const [],
    };
    server.script['GET /api/v1/ee/team/changes/calendar'] = (_) => {
      'changes': const [],
      'freezes': const [],
    };
    await pumpAt(tester, '/changes/$backupId');

    expect(find.text('Hat 3 PLC yedeği'), findsOneWidget);
    expect(find.byKey(const Key('change-from-server')), findsOneWidget);
    expect(find.byKey(const Key('change-approval-none')), findsOneWidget);
    expect(find.byKey(const Key('change-calendar-clear')), findsOneWidget);
  });

  testWidgets('the list is this unit\'s copy, split by the clock, and search '
      'narrows it with no signal', (tester) async {
    server.offline = true;
    await pumpAt(tester, '/changes');

    final ahead = tester.getTopLeft(find.byKey(const Key('change-$diskId')));
    final unscheduled = tester.getTopLeft(
      find.byKey(const Key('change-$draftId')),
    );
    final past = tester.getTopLeft(find.byKey(const Key('change-$doneId')));
    expect(ahead.dy, lessThan(unscheduled.dy));
    expect(unscheduled.dy, lessThan(past.dy));
    expect(find.byKey(const Key('change-section-ahead')), findsOneWidget);
    expect(find.byKey(const Key('change-section-unscheduled')), findsOneWidget);
    expect(find.byKey(const Key('change-section-past')), findsOneWidget);
    // Another unit's change stays in that unit's list.
    expect(find.text('Kalite laboratuvarı ağ anahtarı'), findsNothing);

    // Typed the way a technician types it: no dotted capital, no accent. The
    // fold (ADR-0013) is the device's, so this needs no server.
    await tester.tap(find.byKey(const Key('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('change-search')), 'surucu');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('change-$draftId')), findsOneWidget);
    expect(find.byKey(const Key('change-$diskId')), findsNothing);
    expect(find.byKey(const Key('change-section-ahead')), findsNothing);
    expect(server.asked, isEmpty);
  });

  testWidgets('raising a change files it in the desk on screen, and refuses '
      'to send one with no way back', (tester) async {
    tallScreen(tester);
    grants = {'changes.create'};
    server.script['POST /api/v1/ee/team/changes'] = (o) => _change(
      '01CHNEWAAAAAAAAAAAAAAAAAAA',
      title: (o.data as Map)['title'] as String,
      status: 'draft',
    );
    await pumpAt(tester, '/changes/new');

    final save = find.byKey(const Key('change-new-save'));
    await tester.enterText(
      find.byKey(const Key('change-new-title')),
      'Hat 3 sunucu disk değişimi',
    );
    await tester.enterText(
      find.byKey(const Key('change-new-impact')),
      'Hat 3 iki saat durur',
    );
    await tester.pump();
    // No way back written: the button cannot send it.
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('change-new-rollback')),
      'Eski diske geri dön',
    );
    await tester.pump();
    await reveal(tester, find.byKey(const Key('change-new-service-$hat3')));
    await tester.tap(find.byKey(const Key('change-new-service-$hat3')));
    await tester.pump();
    await reveal(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = server.sent['POST /api/v1/ee/team/changes']! as Map;
    expect(body['workspaceId'], ws);
    expect(body.containsKey('sourceTicketId'), isFalse);
    expect(body['type'], 'normal');
    expect(body['risk'], 'medium');
    expect(body['serviceIds'], [hat3]);
    expect(body['rollbackPlan'], 'Eski diske geri dön');
    await letSnackbarGo(tester);
  });

  testWidgets('EE-279: raised from a request, the request goes with it and '
      'decides the desk', (tester) async {
    tallScreen(tester);
    grants = {'changes.create'};
    server.script['POST /api/v1/ee/team/changes'] = (o) => _change(
      '01CHNEWAAAAAAAAAAAAAAAAAAA',
      title: (o.data as Map)['title'] as String,
      status: 'draft',
      sourceTicketId: '01TKAAAAAAAAAAAAAAAAAAAAAA',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeNewChangeScreen(
            source: EeChangeSource(
              ticketId: '01TKAAAAAAAAAAAAAAAAAAAAAA',
              subject: 'Hat 3 her vardiya iki kez duruyor',
              number: 1042,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Where it comes from, said at the top; the request's subject is the
    // first draft of the title.
    expect(
      find.descendant(
        of: find.byKey(const Key('change-new-source')),
        matching: find.textContaining('#1042'),
      ),
      findsOneWidget,
    );
    expect(find.text('Hat 3 her vardiya iki kez duruyor'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('change-new-impact')),
      'Hat 3 bir vardiya durur',
    );
    await tester.enterText(
      find.byKey(const Key('change-new-rollback')),
      'Eski PLC yazılımına dön',
    );
    await tester.pump();
    final save = find.byKey(const Key('change-new-save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = server.sent['POST /api/v1/ee/team/changes']! as Map;
    expect(body['sourceTicketId'], '01TKAAAAAAAAAAAAAAAAAAAAAA');
    expect(body.containsKey('workspaceId'), isFalse);
    expect(body['title'], 'Hat 3 her vardiya iki kez duruyor');
    await letSnackbarGo(tester);
  });

  testWidgets('offline, the button is grey and says why', (tester) async {
    tallScreen(tester);
    grants = {'changes.create'};
    container.read(serverReachabilityProvider.notifier).unreachable();
    await pumpAt(tester, '/changes/new');
    await tester.enterText(find.byKey(const Key('change-new-title')), 'x');
    await tester.enterText(find.byKey(const Key('change-new-impact')), 'x');
    await tester.enterText(find.byKey(const Key('change-new-rollback')), 'x');
    await tester.pump();

    final save = find.byKey(const Key('change-new-save'));
    await reveal(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.byKey(const Key('change-new-offline')), findsOneWidget);
    expect(server.asked, isEmpty);
  });
}
