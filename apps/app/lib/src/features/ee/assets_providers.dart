import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/assets_api.dart';
import 'data/assets_models.dart';
import 'providers.dart';

/// The equipment register (EE-191…EE-194).
///
/// Read from the SERVER rather than from the device's own copy even though
/// assets replicate. The replica exists so a technician standing at a machine
/// with no signal can open its card; the register SCREEN is a filtered,
/// cross-workspace query with counts that span archived requests, and none of
/// those pieces live on the device.
final eeAssetsApiProvider = Provider<EeAssetsApi>(
  (ref) => EeAssetsApi(ref.watch(apiClientProvider)),
);

/// The filters the list screen carries, as one value so one provider answers.
class EeAssetFilter {
  const EeAssetFilter({
    this.type,
    this.status,
    this.location,
    this.expiringWithinDays,
  });

  final String? type;
  final String? status;
  final String? location;
  final int? expiringWithinDays;

  @override
  bool operator ==(Object other) =>
      other is EeAssetFilter &&
      other.type == type &&
      other.status == status &&
      other.location == location &&
      other.expiringWithinDays == expiringWithinDays;

  @override
  int get hashCode => Object.hash(type, status, location, expiringWithinDays);
}

/// `FutureProvider.family` + `ref.invalidate` — this repo has no
/// `FamilyAsyncNotifier`, and reaching for one cost two rounds in Faz 2.
final eeAssetsProvider = FutureProvider.family<List<EeAsset>, EeAssetFilter>((
  ref,
  filter,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const [];
  return ref
      .watch(eeAssetsApiProvider)
      .list(
        type: filter.type,
        status: filter.status,
        location: filter.location,
        expiringWithinDays: filter.expiringWithinDays,
      );
});

final eeAssetProvider = FutureProvider.family<EeAsset, String>(
  (ref, assetId) => ref.watch(eeAssetsApiProvider).get(assetId),
);

final eeAssetHistoryProvider = FutureProvider.family<EeAssetHistory, String>((
  ref,
  assetId,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) {
    return const EeAssetHistory(
      stats: EeAssetStats(
        months: 12,
        ticketCount: 0,
        openTicketCount: 0,
        openMinutes: 0,
      ),
    );
  }
  return ref.watch(eeAssetsApiProvider).history(assetId);
});

final eeAssetTypesProvider = FutureProvider<EeAssetTypes>((ref) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const EeAssetTypes();
  return ref.watch(eeAssetsApiProvider).types();
});
