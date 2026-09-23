import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../search/providers.dart';
import '../../search/search.dart';
import '../workspaces/workspaces.dart';

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

/// EE-220 — the register's search field, and the replica's first reader.
///
/// ── `searchAssets` HAS EXISTED SINCE EE-191 AND NOBODY CALLED IT ──────
///
/// OPH-326 wrote the rule that makes this a bug rather than a gap: "an entity
/// left out of search is an entity that does not exist for the user." The
/// registry obeyed it — `assets` is registered, its shadow columns are filled
/// on every pull, the SQL is ready — and the app never asked. Measured in the
/// EE-196 round and again here: zero callers.
///
/// It was worse than one missing field. Nothing in the app read the assets
/// REPLICA at all: the list, the detail and the history all go to REST. So the
/// table EE-191 shipped "to be read at the machine with no signal" was being
/// written on every pull and read by nobody. This provider is its first
/// reader.
final assetSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Ranked ids, or null when search is off.
///
/// ── WHAT THIS DOES AND DOES NOT BUY, SAID PLAINLY ─────────────────────
///
/// It reads the replica, so the MATCHING is local, instant and does the
/// Turkish `ı`/`i` fold that neither SQLite nor MySQL does on its own
/// (ADR-0013). What it does not buy yet is the offline half: the list behind
/// it is still `eeAssetsProvider`, which is REST, so with no signal there are
/// no rows for these hits to rank. Closing that means moving the register's
/// list onto the replica, which is a screen rewrite and belongs to whoever
/// takes EE-219's measurement of what these replicas are worth. Written down
/// rather than left for somebody to discover in a factory basement.
final assetSearchResultsProvider = FutureProvider.autoDispose<List<SearchHit>?>(
  (ref) async {
    final query = ref.watch(assetSearchQueryProvider).trim();
    if (query.isEmpty) return null;
    final workspace = ref.watch(currentWorkspaceProvider).value;
    if (workspace == null) return null;
    return ref.watch(searchServiceProvider).searchAssets(workspace.id, query);
  },
);
