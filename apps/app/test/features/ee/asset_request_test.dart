import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/deep_link.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/new_ticket_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/theme/theme.dart';

/// AW-E26 / EE-271 + EE-281 — the press, the sticker, and a request about it.
///
/// The report's scenario: a technician scans the sticker on a press, the card
/// opens, and they want to say "this press is leaking oil". Before EE-271 the
/// card had no way to say it — its own comment explained why the button could
/// not exist, and that explanation went stale when EE-225 built the form.
///
/// Walked the way it happens, in the place it happens: a basement with no
/// signal. The QR code goes through the app's deep-link parser into the
/// router's own routes; the card opens from the device's copy; the button
/// opens the request form with the press already in it; and because there is
/// no signal the form writes a DRAFT — through the real store, into the real
/// replica and outbox — which carries the press to the server (EE-281). No
/// store, provider or screen on that path is stubbed.
const _ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const _own = '01WSOWNAAAAAAAAAAAAAAAAAAA';
const _press = '01JPRESSAAAAAAAAAAAAAAAAAA';
const _scrap = '01JHRDAAAAAAAAAAAAAAAAAAAA';

/// Airplane mode: every request dies before an answer, and is counted.
class _NoSignal implements HttpClientAdapter {
  final List<String> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.path);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _asset(
  String id, {
  required String tag,
  required String name,
  String status = 'in_use',
  String? purchasedAt,
  int? purchaseCostMinor,
  String? currency,
}) => {
  'id': id,
  'workspaceId': _ws,
  'type': 'machine',
  'name': name,
  'tag': tag,
  'serialNo': null,
  'manufacturer': 'Durmazlar',
  'model': null,
  'ownerUserId': null,
  'location': 'Döküm Holü / Hat 3',
  'status': status,
  'warrantyUntil': null,
  'calibrationDue': null,
  'supplier': null,
  'purchasedAt': purchasedAt,
  'purchaseCostMinor': purchaseCostMinor,
  'currency': currency,
  'notes': null,
  'revision': 1,
  'createdAt': '2026-08-01T08:00:00.000Z',
  'updatedAt': '2026-08-01T08:00:00.000Z',
};

void main() {
  late AwDatabase db;
  late _NoSignal adapter;
  late ProviderContainer container;

  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    adapter = _NoSignal();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.alliswell.test'))
      ..httpClientAdapter = adapter;
    container = ProviderContainer(
      retry: awRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(dio),
        syncEngineProvider.overrideWithValue(null),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: _ws,
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
        ),
        // The person's own drawer, where a draft lives (EE-243).
        draftWorkspaceIdProvider.overrideWithValue(_own),
        eeFeatureProvider.overrideWith((ref, name) => true),
        // A field technician: may file and may see the register, nothing
        // more — the person the QR flow is for.
        canProvider.overrideWith(
          (ref, id) => id == 'tickets.create' || id == 'assets.view',
        ),
      ],
    );
    dio.interceptors.add(
      ReachabilityInterceptor(
        container.read(serverReachabilityProvider.notifier),
      ),
    );
    await applyPulledChanges(
      db,
      workspaceId: _ws,
      toRevision: 2,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_asset',
          entityId: _press,
          operation: 'create',
          data: _asset(
            _press,
            tag: 'PRS-250',
            name: 'Hidrolik pres',
            purchasedAt: '2024-03-15',
            purchaseCostMinor: 1250000,
            currency: 'EUR',
          ),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_asset',
          entityId: _scrap,
          operation: 'create',
          data: _asset(
            _scrap,
            tag: 'KMP-0',
            name: 'Eski kompresör',
            status: 'retired',
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<GoRouter> scan(WidgetTester tester, String assetId) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final route = awRouteForUri(Uri.parse('alliswell://asset/$assetId'));
    expect(route, '/assets/$assetId');
    final router = GoRouter(
      initialLocation: route,
      routes: [...eeAssetRoutes(), ...eeTicketRoutes()],
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
    return router;
  }

  Finder key(String k) => find.byKey(Key(k));

  /// The form is a lazy list: the button below the fold is built only once
  /// it is scrolled to.
  Future<void> submit(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      key('new-ticket-submit'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(EeNewTicketScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(key('new-ticket-submit'));
    await tester.pumpAndSettle();
  }

  /// The app's retry policy (`awRetry`: 250 ms, 500 ms, 1 s) keeps asking the
  /// dead network for a moment after every screen that tried; the test ends
  /// after it has given up, not in the middle of it.
  Future<void> letRetriesEnd(WidgetTester tester) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('AW-E26: in the basement, the press card files a request about '
      'the press — a draft that carries it', (tester) async {
    await scan(tester, _press);

    // The card says what the press cost and when it was bought — on the
    // device since EE-191, drawn since EE-271 — in the record's own currency.
    expect(find.text('ee.assets.field.purchased'.tr()), findsOneWidget);
    expect(find.text('2024-03-15'), findsOneWidget);
    expect(find.text('ee.assets.field.purchaseCost'.tr()), findsOneWidget);
    expect(find.text('12500.00 EUR'), findsOneWidget);

    await tester.ensureVisible(key('asset-open-request'));
    await tester.tap(key('asset-open-request'));
    await tester.pumpAndSettle();

    // The request form, with the press already in its asset field.
    expect(find.byType(EeNewTicketScreen), findsOneWidget);
    expect(
      find.descendant(
        of: key('new-ticket-asset'),
        matching: find.text('PRS-250 · Hidrolik pres'),
      ),
      findsOneWidget,
    );
    // No signal, and the form says so — and that a draft carries the machine.
    expect(key('new-ticket-offline'), findsOneWidget);
    expect(find.text('ee.tickets.new.draftCarries'.tr()), findsOneWidget);

    await tester.enterText(key('new-ticket-subject'), 'Pres yağ kaçırıyor');
    await submit(tester);

    // The draft, in the person's own drawer, with the press on it…
    final draft = await db.select(db.ticketDrafts).getSingle();
    expect(draft.workspaceId, _own);
    expect(draft.subject, 'Pres yağ kaçırıyor');
    expect(draft.assetId, _press);
    // …and queued with it, so the press reaches the server with the report.
    final queued = await db.select(db.pendingMutations).getSingle();
    expect(queued.entityType, 'ee_ticket_draft');
    expect(queued.operation, 'create');
    expect(
      (jsonDecode(queued.patchJson!) as Map<String, dynamic>)['assetId'],
      _press,
    );
    await letRetriesEnd(tester);
  });

  testWidgets('AW-E26: a retired machine offers no request, and its price '
      'is not invented when the record has none', (tester) async {
    await scan(tester, _scrap);
    expect(find.text('KMP-0'), findsWidgets);
    expect(key('asset-open-request'), findsNothing);
    expect(find.text('ee.assets.field.purchaseCost'.tr()), findsNothing);
    await letRetriesEnd(tester);
  });

  testWidgets('AW-E26: the asset field offers this unit\'s machines, never a '
      'retired one, and can be cleared', (tester) async {
    final router = await scan(tester, _press);
    unawaited(router.push('/tickets/new'));
    await tester.pumpAndSettle();

    // Opened without a card, the field asks.
    expect(
      find.descendant(
        of: key('new-ticket-asset'),
        matching: find.text('ee.tickets.new.assetPick'.tr()),
      ),
      findsOneWidget,
    );
    await tester.tap(key('new-ticket-asset'));
    await tester.pumpAndSettle();
    expect(key('new-ticket-asset-option-$_press'), findsOneWidget);
    expect(key('new-ticket-asset-option-$_scrap'), findsNothing);

    // Searched the house way, with no signal: folded, every word somewhere.
    await tester.enterText(key('new-ticket-asset-search'), 'hidrolik');
    await tester.pumpAndSettle();
    expect(key('new-ticket-asset-option-$_press'), findsOneWidget);
    await tester.enterText(key('new-ticket-asset-search'), 'forklift');
    await tester.pumpAndSettle();
    expect(key('new-ticket-asset-empty'), findsOneWidget);
    await tester.enterText(key('new-ticket-asset-search'), 'PRS');
    await tester.pumpAndSettle();
    await tester.tap(key('new-ticket-asset-option-$_press'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: key('new-ticket-asset'),
        matching: find.text('PRS-250 · Hidrolik pres'),
      ),
      findsOneWidget,
    );

    // And taken back out: nothing is linked that the person removed.
    await tester.tap(key('new-ticket-asset-clear'));
    await tester.pumpAndSettle();
    await tester.enterText(key('new-ticket-subject'), 'Genel bir sorun');
    await submit(tester);
    final draft = await db.select(db.ticketDrafts).getSingle();
    expect(draft.assetId, null);
    final queued = await db.select(db.pendingMutations).getSingle();
    expect(
      (jsonDecode(queued.patchJson!) as Map<String, dynamic>).containsKey(
        'assetId',
      ),
      isFalse,
    );
    await letRetriesEnd(tester);
  });
}
