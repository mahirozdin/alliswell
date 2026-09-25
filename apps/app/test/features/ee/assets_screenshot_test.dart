// The equipment register in a basement (EE-238, AW-E16).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/assets_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here.
//
// WHY THESE TWO SHOTS.
//
//   • THE CARD, OFFLINE. The report's scene: a technician scans a sticker with
//     no signal. The picture has to show the three things the screen now
//     says at once — the machine's facts, WHERE they came from (this
//     device's copy, and how old it is), and that the history below needs a
//     connection. A card that drew the facts and hid the rest would be the old
//     silence in a nicer frame.
//   • THE REGISTER, OFFLINE, SEARCHED. The unit's machines answer a search
//     with no server, and the line under them is the whole EE-219 bargain in
//     one sentence: some records are not kept on this device, and they come
//     back with the signal. "Not here" and "does not exist" are different
//     answers, and only one of them is true.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assets_providers.dart';
import 'package:alliswell/src/features/ee/data/assets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/asset_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/assets_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

const _ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
const _press = '01JPRESSAAAAAAAAAAAAAAAAAA';

/// The app already knows the server is out of reach (OPH-342).
class _Offline extends ServerReachability {
  @override
  bool? build() => false;
}

/// A server that is not there — nothing is asked while the signal is known
/// to be gone, and anything that is asked dies the way airplane mode kills it.
class _NoSignal implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _asset(
  String id, {
  required String tag,
  required String name,
  required String type,
  String status = 'in_use',
  String? location,
  String? serialNo,
  String? manufacturer,
  String? model,
  String? warrantyUntil,
  String? calibrationDue,
  String? supplier,
}) => {
  'id': id,
  'workspaceId': _ws,
  'type': type,
  'name': name,
  'tag': tag,
  'serialNo': serialNo,
  'manufacturer': manufacturer,
  'model': model,
  'ownerUserId': null,
  'location': location,
  'status': status,
  'warrantyUntil': warrantyUntil,
  'calibrationDue': calibrationDue,
  'supplier': supplier,
  'purchasedAt': null,
  'purchaseCostMinor': null,
  'currency': null,
  'notes': null,
  'revision': 1,
  'createdAt': '2026-06-01T08:00:00.000Z',
  'updatedAt': '2026-09-20T08:00:00.000Z',
};

void main() {
  if (!_enabled) return;

  late AwDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final tr = AwI18n.instance.locale.languageCode == 'tr';
    await applyPulledChanges(
      db,
      workspaceId: _ws,
      toRevision: 4,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_asset',
          entityId: _press,
          operation: 'create',
          data: _asset(
            _press,
            tag: 'PRS-250',
            name: tr ? 'Hidrolik pres, 250 ton' : 'Hydraulic press, 250 t',
            type: 'machine',
            location: tr ? 'Döküm Holü / Hat 3' : 'Casting hall / Line 3',
            serialNo: 'SN-99-114-2231',
            manufacturer: 'Durmazlar',
            model: 'HAP 250',
            warrantyUntil: '2028-06-30',
            calibrationDue: '2026-11-15',
            supplier: tr ? 'Anadolu Makina Ltd.' : 'Anatolia Machinery Ltd.',
          ),
        ),
        SyncChange(
          revision: 2,
          entityType: 'ee_asset',
          entityId: '01JPRESSBBBBBBBBBBBBBBBBBB',
          operation: 'create',
          data: _asset(
            '01JPRESSBBBBBBBBBBBBBBBBBB',
            tag: 'PRS-160',
            name: tr ? 'Eksantrik pres, 160 ton' : 'Eccentric press, 160 t',
            type: 'machine',
            status: 'maintenance',
            location: tr ? 'Döküm Holü / Hat 1' : 'Casting hall / Line 1',
          ),
        ),
        SyncChange(
          revision: 3,
          entityType: 'ee_asset',
          entityId: '01JPRESSCCCCCCCCCCCCCCCCCC',
          operation: 'create',
          data: _asset(
            '01JPRESSCCCCCCCCCCCCCCCCCC',
            tag: 'PRS-40',
            name: tr ? 'Pnömatik pres, 40 ton' : 'Pneumatic press, 40 t',
            type: 'machine',
            status: 'faulty',
            location: tr ? 'Montaj / Hat 2' : 'Assembly / Line 2',
          ),
        ),
        SyncChange(
          revision: 4,
          entityType: 'ee_asset',
          entityId: '01JKMPAAAAAAAAAAAAAAAAAAAA',
          operation: 'create',
          data: _asset(
            '01JKMPAAAAAAAAAAAAAAAAAAAA',
            tag: 'KMP-02',
            name: tr ? 'Vidalı kompresör' : 'Screw compressor',
            type: 'machine',
            location: tr ? 'Kompresör odası' : 'Compressor room',
          ),
        ),
      ],
    );
    // The last time this phone had a signal: twenty minutes ago, on the stairs.
    await db
        .into(db.syncStates)
        .insert(
          SyncStatesCompanion.insert(
            workspaceId: _ws,
            clientId: 'shot-device',
            lastRevision: const Value(4),
            lastPulledAt: Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
            ),
          ),
        );
  });

  tearDown(() => db.close());

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
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
    eeFeatureProvider.overrideWith((ref, name) => true),
    canProvider.overrideWith((ref, id) => false),
    serverReachabilityProvider.overrideWith(_Offline.new),
    eeAssetsApiProvider.overrideWithValue(
      EeAssetsApi(Dio()..httpClientAdapter = _NoSignal()),
    ),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('the card, scanned in a basement (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-asset-card-offline',
        size: const Size(900, 1400),
        overrides: overrides(),
        screen: const EeAssetDetailScreen(assetId: _press),
      );
    });

    testWidgets('the register, searched with no signal (${brightness.name})', (
      tester,
    ) async {
      await eeShoot(
        tester,
        brightness: brightness,
        name: 'ee-assets-offline',
        size: const Size(900, 1400),
        overrides: overrides(),
        screen: const EeAssetsScreen(),
        afterPump: (tester) async {
          await tester.tap(find.byKey(const Key('search-open')));
          await tester.pumpAndSettle();
          // What is painted on the sticker, typed in lower case — the tag
          // tier, so the compressor (whose NAME contains "pres") stays out.
          await tester.enterText(find.byKey(const Key('asset-search')), 'prs');
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });
  }
}
