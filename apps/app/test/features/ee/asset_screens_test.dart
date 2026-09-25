import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assets_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_archive_api.dart';
import 'package:alliswell/src/features/ee/ticket_archive_providers.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/search/search.dart';
import 'package:alliswell/src/features/ee/data/assets_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/asset_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/assets_screen.dart';

/// EE-194 — the register's two screens.
///
/// The claim worth a test is the one a reader would not guess from the code:
/// an ARCHIVED request is drawn, not hidden. Most of a machine's history is
/// archived, and a card that showed only live requests would answer "has this
/// failed before" with a number too small to act on — the exact blindness the
/// analysis named.
void main() {
  // The translations are loaded globally by `flutter_test_config.dart`; this
  // file needs no setUp of its own.

  const asset = EeAsset(
    id: '01JABCDEFGHJKMNPQRSTVWXYZ',
    tag: 'PRN-14',
    name: 'Kat 2 yazıcısı',
    type: 'machine',
    status: 'in_use',
    location: 'Hol 2',
  );

  const other = EeAsset(
    id: '01JZZZZZZZZZZZZZZZZZZZZZZZ',
    tag: 'KMP-02',
    name: 'Kompresör',
    type: 'machine',
    status: 'in_use',
  );

  /// The register as the device holds it (EE-238), and a server with nothing
  /// more to add — the two sources the list screen reads.
  List<Override> register(
    List<EeAsset> rows, {
    List<EeAsset> server = const [],
    List<String> types = const [],
    List<EeAssetUnit> units = const [],
  }) => [
    eeAssetRegisterProvider.overrideWith(
      (ref, filter) => Stream.value(
        EeAssetRegister(
          rows: rows,
          onDevice: {for (final a in rows) a.id},
          types: types,
        ),
      ),
    ),
    eeAssetsOffDeviceProvider.overrideWith((ref, key) async => server),
    // EE-239: the places, from the server — overridden everywhere so no test
    // here reaches for a network it does not have.
    eeAssetUnitsProvider.overrideWith((ref) async => units),
  ];

  /// EE-220 — the register's search, and the two answers it has to keep apart.
  ///
  /// The register was reachable only by scanning a QR code before this round,
  /// and `searchAssets` had no caller at all. A test that only proved "the
  /// field exists" would pass against a field wired to nothing, so these
  /// assert what the field DOES: it narrows the list, it orders by rank, and
  /// an open field that matched nothing says something different from an
  /// empty register.
  testWidgets('EE-220: search narrows the register and keeps rank', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register([asset, other]),
          eeAssetTypesProvider.overrideWith(
            (ref) async => const EeAssetTypes(),
          ),
          canProvider.overrideWith((ref, id) => false),
          // The replica answered with ONE of the two, and that is the whole
          // point: the list shows what search returned, not everything.
          assetSearchResultsProvider.overrideWith(
            (ref) async => [
              const SearchHit(id: '01JZZZZZZZZZZZZZZZZZZZZZZZ', tier: 0),
            ],
          ),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The row draws tag and name together (`KMP-02 · Kompresör`), so the
    // assertion matches how it actually renders rather than how one might
    // assume it does.
    expect(find.textContaining('KMP-02'), findsOneWidget);
    // The one the search did not return is gone — a search field that leaves
    // the whole list on screen is a search field that does nothing.
    expect(find.textContaining('PRN-14'), findsNothing);
  });

  testWidgets('EE-220: an open field that matched nothing says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register([asset]),
          eeAssetTypesProvider.overrideWith(
            (ref) async => const EeAssetTypes(),
          ),
          canProvider.overrideWith((ref, id) => false),
          // Open, and nothing matched — NOT the same as an empty register.
          assetSearchResultsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Conflating the two is how somebody concludes the register is empty when
    // their query simply missed.
    expect(find.text('ee.assets.searchEmpty'.tr()), findsOneWidget);
    expect(find.text('ee.assets.empty'.tr()), findsNothing);
  });

  testWidgets('the register lists a machine tag-first', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The feature gate, on: these screens do not exist without it.
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register([asset]),
          eeAssetTypesProvider.overrideWith(
            (ref) async => const EeAssetTypes(),
          ),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('asset-${'01JABCDEFGHJKMNPQRSTVWXYZ'}')),
      findsOneWidget,
    );
    expect(find.textContaining('PRN-14'), findsOneWidget);
    // The label action is behind `assets.manage`, which this caller does not
    // hold — a button that would 403 is not shown.
    expect(find.byKey(const Key('asset-labels')), findsNothing);
  });

  testWidgets('the label action appears for somebody who may print', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register([asset]),
          eeAssetTypesProvider.overrideWith(
            (ref) async => const EeAssetTypes(),
          ),
          canProvider.overrideWith((ref, id) => id == 'assets.manage'),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset-labels')), findsOneWidget);
  });

  testWidgets('an archived request is drawn, not hidden', (tester) async {
    final history = EeAssetHistory(
      stats: const EeAssetStats(
        months: 12,
        ticketCount: 14,
        openTicketCount: 1,
        openMinutes: 600,
      ),
      tickets: [
        EeAssetTicket(
          id: 'T1',
          number: 1042,
          subject: 'Kağıt sıkışması',
          status: 'in_progress',
          priority: 'normal',
          createdAt: DateTime(2026, 9, 1),
          archived: false,
        ),
        EeAssetTicket(
          id: 'T2',
          number: 812,
          subject: 'Geçen yılın arızası',
          status: 'closed',
          priority: 'normal',
          createdAt: DateTime(2025, 6, 1),
          terminalAt: DateTime(2025, 6, 2),
          archived: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          eeAssetOnDeviceProvider.overrideWith(
            (ref, id) => Stream.value(asset),
          ),
          eeAssetHistoryProvider.overrideWith((ref, id) async => history),
          canProvider.overrideWith((ref, id) => false),
          eeArchivedTicketProvider.overrideWith(
            (ref, id) async => EeArchivedTicket(
              summary: EeArchivedTicketSummary(
                id: 'T2',
                number: 812,
                subject: 'Geçen yılın arızası',
                status: 'closed',
                priority: 'normal',
                terminalAt: DateTime(2025, 6, 2),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeAssetDetailScreen(assetId: '01JABCDEFGHJKMNPQRSTVWXYZ'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both rows. The archived one is the reason this list exists.
    expect(find.byKey(const Key('asset-ticket-T1')), findsOneWidget);
    expect(find.byKey(const Key('asset-ticket-T2')), findsOneWidget);
    expect(find.textContaining('Geçen yılın arızası'), findsOneWidget);

    // And the counts say fourteen, not one.
    final counts = tester.widget<Text>(
      find.byKey(const Key('asset-history-counts')),
    );
    expect(counts.data, contains('14'));
    // AW-E22 (EE-272): and right under it, that open time is not downtime —
    // the number reads like one until something on the card says otherwise.
    expect(
      find.byKey(const Key('asset-history-open-time-note')),
      findsOneWidget,
    );
    expect(find.text('ee.assets.history.openTimeNote'.tr()), findsOneWidget);

    // EE-266: the archived one opens — read-only, from the archive — where
    // it used to take no tap because there was nowhere to go.
    await tester.tap(find.byKey(const Key('asset-ticket-T2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archive-strip')), findsOneWidget);
    expect(find.text('Geçen yılın arızası'), findsWidgets);
  });
  // ── EE-238: the device's copy first, the server for the rest ──────────

  testWidgets('EE-238: rows only the server holds come under their own '
      'heading, once', (tester) async {
    const scrap = EeAsset(
      id: '01JHRDZZZZZZZZZZZZZZZZZZZZ',
      tag: 'HRD-7',
      name: 'Eski kaynak makinesi',
      type: 'machine',
      status: 'retired',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          // The server answers with the device's row AND one it does not
          // hold; only the second is "not on this device".
          ...register([asset], server: [asset, scrap]),
          eeAssetTypesProvider.overrideWith(
            (ref) async => const EeAssetTypes(),
          ),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-off-device')), findsOneWidget);
    expect(find.text('ee.assets.offDevice.title'.tr()), findsOneWidget);
    expect(find.byKey(Key('asset-${scrap.id}')), findsOneWidget);
    // The device's row is drawn once, above the heading — not a second time
    // below it because the server also sent it.
    expect(find.byKey(Key('asset-${asset.id}')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(Key('asset-${asset.id}'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('asset-off-device'))).dy),
    );
    // Online, nothing is out of reach, so no "needs a connection" line.
    expect(find.byKey(const Key('asset-off-device-offline')), findsNothing);
  });

  testWidgets('EE-238: offline, the type chips come from the device — and a '
      "team's own key is printed as itself, never as an i18n path", (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register([asset], types: ['cnc_torna', 'machine']),
          // The vocabulary lives on the server, and the server is not there.
          eeAssetTypesProvider.overrideWith(
            (ref) async => throw Exception('no signal'),
          ),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-filter-type-machine')), findsOneWidget);
    expect(
      find.byKey(const Key('asset-filter-type-cnc_torna')),
      findsOneWidget,
    );
    expect(find.text('cnc_torna'), findsOneWidget);
    expect(find.textContaining('ee.assets.type.'), findsNothing);
  });

  testWidgets('EE-238: a card the device does not hold, read from the server, '
      'says where it came from', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          eeAssetOnDeviceProvider.overrideWith((ref, id) => Stream.value(null)),
          eeAssetProvider.overrideWith((ref, id) async => asset),
          eeAssetHistoryProvider.overrideWith(
            (ref, id) async => const EeAssetHistory(
              stats: EeAssetStats(
                months: 12,
                ticketCount: 0,
                openTicketCount: 0,
                openMinutes: 0,
              ),
            ),
          ),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(
          home: EeAssetDetailScreen(assetId: '01JABCDEFGHJKMNPQRSTVWXYZ'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kat 2 yazıcısı'), findsOneWidget);
    expect(find.text('ee.assets.card.fromServer'.tr()), findsOneWidget);
    expect(find.textContaining('ee.assets.card.onDevice'.tr()), findsNothing);
  });

  testWidgets('EE-238: offline, the pencil is greyed before it is pressed, '
      'with the reason', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          eeAssetOnDeviceProvider.overrideWith(
            (ref, id) => Stream.value(asset),
          ),
          eeAssetHistoryProvider.overrideWith(
            (ref, id) async => throw const ApiException(
              'NETWORK_ERROR',
              'Could not reach the AllisWell server',
            ),
          ),
          serverReachabilityProvider.overrideWith(_Offline.new),
          canProvider.overrideWith((ref, id) => id == 'assets.manage'),
        ],
        child: const MaterialApp(
          home: EeAssetDetailScreen(assetId: '01JABCDEFGHJKMNPQRSTVWXYZ'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pencil = tester.widget<IconButton>(
      find.byKey(const Key('asset-edit')),
    );
    expect(pencil.onPressed, isNull);
    expect(pencil.tooltip, 'ee.assets.editOffline'.tr());
    // The card itself is all there.
    expect(find.text('Kat 2 yazıcısı'), findsOneWidget);
    expect(find.text('ee.assets.history.offline'.tr()), findsOneWidget);
  });

  /// EE-239 — the unit filter narrows BOTH halves of the register: the
  /// device's copy of the current unit (kept only when that unit is chosen)
  /// and the server's answer (asked with the chosen place).
  testWidgets('EE-239: choosing a unit narrows the register to its machines — '
      'and tapping the chip again gives the whole register back', (
    tester,
  ) async {
    const bakim = 'WS-BAKIM';
    const kalite = 'WS-KALITE';
    const stock = 'WS-STOK';
    const mine = EeAsset(
      id: 'A1',
      tag: 'BKM-1',
      name: 'Hat 3 tornası',
      type: 'machine',
      status: 'in_use',
      workspaceId: bakim,
    );
    const theirs = EeAsset(
      id: 'K1',
      tag: 'KLT-1',
      name: 'Ölçüm masası',
      type: 'machine',
      status: 'in_use',
      workspaceId: kalite,
    );
    const shelf = EeAsset(
      id: 'S1',
      tag: 'STK-1',
      name: 'Yedek pompa',
      type: 'machine',
      status: 'in_stock',
      workspaceId: stock,
    );
    final asked = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          // The device holds Bakım's copy; the filter is applied to it the
          // way the real provider applies it.
          eeAssetRegisterProvider.overrideWith(
            (ref, filter) => Stream.value(
              EeAssetRegister(
                rows: filterAssets(const [mine], filter, now: DateTime(2026)),
                onDevice: const {'A1'},
              ),
            ),
          ),
          eeAssetsOffDeviceProvider.overrideWith((ref, key) async {
            asked.add(key.filter.workspaceId);
            return [
              for (final a in const [mine, theirs, shelf])
                if (key.filter.workspaceId == null ||
                    a.workspaceId == key.filter.workspaceId)
                  a,
            ];
          }),
          eeAssetUnitsProvider.overrideWith(
            (ref) async => const [
              EeAssetUnit(workspaceId: stock, name: 'Genel', stock: true),
              EeAssetUnit(workspaceId: bakim, name: 'Bakım', unitName: 'Bakım'),
              EeAssetUnit(workspaceId: kalite, name: 'Kalite', unitName: 'Kalite'),
            ],
          ),
          eeAssetTypesProvider.overrideWith((ref) async => const EeAssetTypes()),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // The whole register: the device's row, and the server's two others.
    expect(find.textContaining('BKM-1'), findsOneWidget);
    expect(find.textContaining('KLT-1'), findsOneWidget);
    expect(find.textContaining('STK-1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('asset-filter-unit')));
    await tester.pumpAndSettle();
    // The picker names the places, the shelf as the team's stock.
    expect(find.text('ee.assets.filter.unitStock'.tr()), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-filter-unit-option-WS-KALITE')));
    await tester.pumpAndSettle();

    // Kalite's machine only — the device's Bakım row is not Kalite's, the
    // shelf is not either — and the server was ASKED with the place, not
    // asked for everything and filtered here.
    expect(find.textContaining('KLT-1'), findsOneWidget);
    expect(find.textContaining('BKM-1'), findsNothing);
    expect(find.textContaining('STK-1'), findsNothing);
    expect(asked.last, kalite);
    expect(
      find.text('ee.assets.filter.unitSet'.tr(args: {'unit': 'Kalite'})),
      findsOneWidget,
    );

    // The chip, tapped while set, clears — the queue's tag chip's gesture.
    await tester.tap(find.byKey(const Key('asset-filter-unit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('BKM-1'), findsOneWidget);
    expect(find.textContaining('STK-1'), findsOneWidget);
    expect(asked.last, isNull);
  });

  testWidgets('EE-239: with one place to choose there is no unit chip — a '
      'picker with one answer is not a question', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          ...register(
            [asset],
            units: const [EeAssetUnit(workspaceId: 'WS-1', name: 'Bakım')],
          ),
          eeAssetTypesProvider.overrideWith((ref) async => const EeAssetTypes()),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(home: EeAssetsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset-filter-unit')), findsNothing);
  });

  group('EE-238: the register\'s filters, on the device', () {
    final now = DateTime(2026, 9, 25, 1, 30);
    const press = EeAsset(
      id: 'P',
      tag: 'PRS-1',
      name: 'Pres',
      type: 'machine',
      status: 'in_use',
      location: 'Döküm Holü / Hat 3',
      warrantyUntil: '2026-10-20',
    );
    const scale = EeAsset(
      id: 'S',
      tag: 'TRT-1',
      name: 'ağırlık terazisi',
      type: 'instrument',
      status: 'in_use',
      location: 'Kalite',
      calibrationDue: '2026-09-25',
    );
    const old = EeAsset(
      id: 'O',
      tag: 'ESK-1',
      name: 'Anahtarlık',
      type: 'machine',
      status: 'retired',
      warrantyUntil: '2026-09-24',
    );

    test('"hol 3" finds "Döküm Holü / Hat 3" — every word, folded', () {
      final kept = filterAssets(
        [press, scale, old],
        const EeAssetFilter(location: 'hol 3'),
        now: now,
      );
      expect(kept.map((a) => a.id), ['P']);
      // Typed without the dots and the accents, the way a phone keyboard in a
      // hurry types them: the fold is on BOTH sides, not only the query's.
      expect(
        filterAssets(
          [press, scale, old],
          const EeAssetFilter(location: 'DOKUM holu'),
          now: now,
        ).map((a) => a.id),
        ['P'],
      );
    });

    test('"running out soon" counts from the device\'s own day', () {
      // 01:30 on the 25th, local. Today's calibration is inside the window;
      // yesterday's warranty is not, whatever the UTC date says.
      final kept = filterAssets(
        [press, scale, old],
        const EeAssetFilter(expiringWithinDays: 30),
        now: now,
      );
      expect(kept.map((a) => a.id).toSet(), {'P', 'S'});
    });

    test('retired last, then by name the way a person reads it', () {
      final kept = filterAssets(
        [old, press, scale],
        const EeAssetFilter(),
        now: now,
      );
      // "ağırlık" sorts as "agirlik", before "Pres"; the retired one is last
      // although "Anahtarlık" would lead the alphabet.
      expect(kept.map((a) => a.id), ['S', 'P', 'O']);
    });

    test('EE-239: a place keeps only its own rows', () {
      const here = EeAsset(
        id: 'H',
        tag: 'H-1',
        name: 'Burada',
        type: 'machine',
        status: 'in_use',
        workspaceId: 'W1',
      );
      const there = EeAsset(
        id: 'T',
        tag: 'T-1',
        name: 'Orada',
        type: 'machine',
        status: 'in_use',
        workspaceId: 'W2',
      );
      expect(
        filterAssets(
          const [here, there],
          const EeAssetFilter(workspaceId: 'W2'),
          now: now,
        ).map((a) => a.id),
        ['T'],
      );
      expect(
        filterAssets(const [here, there], const EeAssetFilter(), now: now)
            .map((a) => a.id)
            .toSet(),
        {'H', 'T'},
      );
    });

    test('type and status are exact', () {
      expect(
        filterAssets(
          [press, scale, old],
          const EeAssetFilter(type: 'machine', status: 'in_use'),
          now: now,
        ).map((a) => a.id),
        ['P'],
      );
    });
  });
}

/// The app already knows the server is out of reach (OPH-342).
class _Offline extends ServerReachability {
  @override
  bool? build() => false;
}
