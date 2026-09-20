import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/assets_providers.dart';
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
