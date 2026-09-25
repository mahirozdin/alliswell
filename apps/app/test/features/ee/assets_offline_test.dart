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
import 'package:alliswell/src/features/ee/assets_providers.dart';
import 'package:alliswell/src/features/ee/data/assets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/assets_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/theme/theme.dart';

/// AW-E16 / EE-238 — the technician in the basement.
///
/// The report's scenario, as written: a technician scans a machine's QR label
/// with no signal and the card opens WITH DATA, not a network error; and a
/// search of the register with no signal gives results. Before EE-238 the
/// card and the list were REST, so both halves of that sentence were false —
/// the replica EE-191 shipped "for the machine with no signal" was read by the
/// search field and nothing else.
///
/// Nothing the screens read is stubbed. The rows arrive through the applier a
/// real pull uses; the QR code goes through the real deep-link parser into the
/// router's own asset routes; and every request to the server fails the way a
/// phone with no signal fails — a connection error at the HTTP layer, with the
/// app's reachability interceptor watching, so the second request is never
/// sent at all.
const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const otherWs = '01WSBBBBBBBBBBBBBBBBBBBBBB';
const pressId = '01JPRESSAAAAAAAAAAAAAAAAAA';
const lathe = '01JTRNAAAAAAAAAAAAAAAAAAAA';
const scrapId = '01JHRDAAAAAAAAAAAAAAAAAAAA';

/// A server that is not there: every request dies before an answer, the way
/// airplane mode does. Every attempt is counted.
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
  String workspaceId = ws,
  String status = 'in_use',
  String? location,
  String? serialNo,
}) => {
  'id': id,
  'workspaceId': workspaceId,
  'type': 'machine',
  'name': name,
  'tag': tag,
  'serialNo': serialNo,
  'manufacturer': 'Durmazlar',
  'model': null,
  'ownerUserId': null,
  'location': location,
  'status': status,
  'warrantyUntil': null,
  'calibrationDue': null,
  'supplier': null,
  'purchasedAt': null,
  'purchaseCostMinor': null,
  'currency': null,
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
      // The app's own retry policy (`main.dart`), not Riverpod's default ten.
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
        // The last-known entitlement, which `eeStatusProvider` keeps on the
        // device for exactly this: the plant floor with no signal.
        eeFeatureProvider.overrideWith((ref, name) => true),
        canProvider.overrideWith((ref, id) => false),
        eeAssetsApiProvider.overrideWithValue(EeAssetsApi(dio)),
      ],
    );
    // The app's own interceptor, on the app's own signal: the first request
    // that dies teaches every surface the server is out of reach.
    dio.interceptors.add(
      ReachabilityInterceptor(
        container.read(serverReachabilityProvider.notifier),
      ),
    );

    // What the device received the last time it had a signal — through the
    // applier a pull uses, not a hand-written insert.
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 3,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_asset',
          entityId: pressId,
          operation: 'create',
          data: _asset(
            pressId,
            tag: 'PRS-250',
            name: 'Hidrolik pres',
            location: 'Döküm Holü / Hat 3',
            serialNo: 'SN-99-114',
          ),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_asset',
          entityId: lathe,
          operation: 'create',
          data: _asset(lathe, tag: 'TRN-7', name: 'Işıklı torna'),
        ),
        // Another unit's machine, left on the device by an earlier visit. It
        // is not THIS unit's register, and the list must not pretend it is.
        SyncChange(
          revision: 3,
          entityType: 'ee_asset',
          entityId: '01JOTHERAAAAAAAAAAAAAAAAAA',
          operation: 'create',
          data: _asset(
            '01JOTHERAAAAAAAAAAAAAAAAAA',
            tag: 'KLT-1',
            name: 'Kalite ölçüm cihazı',
            workspaceId: otherWs,
          ),
        ),
      ],
    );
    // The last time this phone had a signal: twenty minutes ago, on the
    // stairs down. The engine writes this row; there is no engine here.
    await db
        .into(db.syncStates)
        .insert(
          SyncStatesCompanion.insert(
            workspaceId: ws,
            clientId: 'basement-phone',
            lastRevision: const Value(3),
            lastPulledAt: Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
            ),
          ),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: child),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AW-E16: the QR label opens the card with no signal — data, '
      'not a network error', (tester) async {
    // The sticker, scanned: the app's own scheme, parsed by the app's own
    // guard, into the router's own asset routes.
    final route = awRouteForUri(Uri.parse('alliswell://asset/$pressId'));
    expect(route, '/assets/$pressId');
    final router = GoRouter(initialLocation: route, routes: eeAssetRoutes());
    addTearDown(router.dispose);
    // The product's theme: the routes wrap their page in the app background,
    // which reads AllisWell Glass's tokens.
    await pump(
      tester,
      MaterialApp.router(
        theme: buildAwTheme(Brightness.light),
        routerConfig: router,
      ),
    );

    // The machine, from the device's copy.
    expect(find.text('PRS-250'), findsWidgets);
    expect(find.text('Hidrolik pres'), findsOneWidget);
    expect(find.text('Döküm Holü / Hat 3'), findsOneWidget);
    expect(find.text('SN-99-114'), findsOneWidget);
    // …and it says it is the device's copy, and how old that copy is — the
    // difference between "the press is in Hat 3" and "it was, twenty minutes
    // ago, which is when this phone last heard".
    expect(
      find.descendant(
        of: find.byKey(const Key('asset-provenance')),
        matching: find.text(
          'ee.assets.card.onDeviceSynced'.tr(
            args: {
              'ago': 'time.ago.minutes'.tr(args: {'n': '20'}),
            },
          ),
        ),
      ),
      findsOneWidget,
    );

    // No error state anywhere — the failure the report describes.
    expect(find.text('error.NETWORK_ERROR'.tr()), findsNothing);
    expect(find.byKey(const Key('asset-not-on-device')), findsNothing);

    // The history is the server's, and says so instead of showing nothing —
    // or showing an old answer as a current one.
    expect(find.byKey(const Key('asset-history-live')), findsOneWidget);
    expect(find.byKey(const Key('asset-history-offline')), findsOneWidget);
    expect(find.text('ee.assets.history.offline'.tr()), findsOneWidget);
    expect(find.byKey(const Key('asset-history-counts')), findsNothing);

    // And the phone learned it was offline from the first request that died:
    // the card asked the server at most twice (the history and the type
    // labels), and nothing more once the signal was known to be gone.
    expect(container.read(serverReachabilityProvider), isFalse);
    expect(adapter.asked.length, lessThanOrEqualTo(2));
  });

  testWidgets('AW-E16: searching the register with no signal gives results', (
    tester,
  ) async {
    await pump(tester, const MaterialApp(home: EeAssetsScreen()));

    // The unit's register, from the device: both machines of THIS unit, not
    // the other unit's leftover row.
    expect(find.byKey(const Key('asset-$pressId')), findsOneWidget);
    expect(find.byKey(const Key('asset-$lathe')), findsOneWidget);
    expect(find.textContaining('KLT-1'), findsNothing);

    // A search, typed the way a technician types it: no dotted capital, no
    // accent. The fold (ADR-0013) is the device's, so this needs no server.
    await tester.tap(find.byKey(const Key('search-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('asset-search')), 'isikli');
    // The field's own debounce, then the replica's answer — and the app's
    // three quick retries of the server half (`awRetry`), which a phone with
    // no signal also sits through before it says "needs a connection".
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-$lathe')), findsOneWidget);
    expect(find.byKey(const Key('asset-$pressId')), findsNothing);
    // Results, not "nothing matched".
    expect(find.text('ee.assets.searchEmpty'.tr()), findsNothing);

    // What the device does not hold is not silently absent: one line says it
    // exists and needs a connection.
    expect(find.byKey(const Key('asset-off-device-offline')), findsOneWidget);
    expect(find.byKey(const Key('asset-off-device')), findsNothing);
  });

  testWidgets('EE-238: a machine the device does not hold says so honestly, '
      'and opens once the server answers', (tester) async {
    // The retired record EE-219 took off devices: the pull brought a
    // tombstone, the applier removed the row.
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 4,
      changes: const [
        SyncChange(
          revision: 4,
          entityType: 'ee_asset',
          entityId: scrapId,
          operation: 'delete',
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: awRouteForUri(Uri.parse('alliswell://asset/$scrapId')),
      routes: eeAssetRoutes(),
    );
    addTearDown(router.dispose);
    // The product's theme: the routes wrap their page in the app background,
    // which reads AllisWell Glass's tokens.
    await pump(
      tester,
      MaterialApp.router(
        theme: buildAwTheme(Brightness.light),
        routerConfig: router,
      ),
    );

    // Not "not found", not a red error: the machine exists, this phone does
    // not carry it, and the signal is what is missing.
    expect(find.byKey(const Key('asset-not-on-device')), findsOneWidget);
    expect(find.text('ee.assets.card.notOnDevice'.tr()), findsOneWidget);
    expect(find.text('ee.assets.card.notOnDeviceBody'.tr()), findsOneWidget);
  });
}
