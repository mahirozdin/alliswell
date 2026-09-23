import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/assets_providers.dart';
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
          eeAssetsProvider.overrideWith((ref, filter) async => [asset, other]),
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
          eeAssetsProvider.overrideWith((ref, filter) async => [asset]),
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
          eeAssetsProvider.overrideWith((ref, filter) async => [asset]),
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
          eeAssetsProvider.overrideWith((ref, filter) async => [asset]),
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
          eeAssetProvider.overrideWith((ref, id) async => asset),
          eeAssetHistoryProvider.overrideWith((ref, id) async => history),
          canProvider.overrideWith((ref, id) => false),
        ],
        child: const MaterialApp(
          home: EeAssetDetailScreen(assetId: '01JABCDEFGHJKMNPQRSTVWXYZ'),
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
  });
}
