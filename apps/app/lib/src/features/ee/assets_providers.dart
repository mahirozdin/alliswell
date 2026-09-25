import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/fold.dart';
import '../../core/reachability.dart';
import '../../i18n/i18n.dart';
import '../../search/providers.dart';
import '../../search/search.dart';
import '../../sync/db/database.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

import '../auth/providers.dart';
import 'data/assets_api.dart';
import 'data/assets_models.dart';
import 'providers.dart';

/// The equipment register (EE-191…EE-194, EE-238).
///
/// ── THE DEVICE'S COPY FIRST, THE SERVER FOR WHAT IT DOES NOT HOLD ─────
///
/// EE-191 replicated assets "so a technician standing at a machine with no
/// signal can open its card", and until EE-238 nothing but the search field
/// read that copy: the list, the card and the history were all REST, so in a
/// basement the QR code opened a network error. The split now:
///
///   the list      the replica of the CURRENT workspace, filtered here
///   the card      the replica, by id, whichever workspace holds it
///   the rest      the server, and drawn as the server: another unit's
///                 equipment, the retired records EE-219 took off devices,
///                 a machine's request history and its labour
///
/// The list is scoped to the current workspace for the queue's reason
/// (`tickets_providers.dart`): the engine syncs one workspace at a time, so a
/// list spanning units would show rows as stale as the last visit. What the
/// device does not hold is not hidden either — online it is fetched and drawn
/// under its own heading, offline the screen says it exists and needs a
/// connection. Neither half pretends to be the other.
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
    this.workspaceId,
  });

  final String? type;
  final String? status;
  final String? location;
  final int? expiringWithinDays;

  /// EE-239 — one place: a unit's workspace or the stock shelf. On the device
  /// it keeps the current workspace's rows only when it names that
  /// workspace; on the server it narrows the answer to that one place.
  final String? workspaceId;

  @override
  bool operator ==(Object other) =>
      other is EeAssetFilter &&
      other.type == type &&
      other.status == status &&
      other.location == location &&
      other.expiringWithinDays == expiringWithinDays &&
      other.workspaceId == workspaceId;

  @override
  int get hashCode =>
      Object.hash(type, status, location, expiringWithinDays, workspaceId);
}

/// The same record, as the replica holds it.
EeAsset eeAssetFromRecord(AssetRecord row) => EeAsset(
  id: row.id,
  tag: row.tag,
  name: row.name,
  type: row.type,
  status: row.status,
  serialNo: row.serialNo,
  manufacturer: row.manufacturer,
  model: row.model,
  location: row.location,
  supplier: row.supplier,
  warrantyUntil: row.warrantyUntil,
  calibrationDue: row.calibrationDue,
  purchasedAt: row.purchasedAt,
  purchaseCostMinor: row.purchaseCostMinor,
  currency: row.currency,
  notes: row.notes,
  ownerUserId: row.ownerUserId,
  workspaceId: row.workspaceId,
);

/// A calendar day as the register writes one: `YYYY-MM-DD`.
String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The register's filters, applied to the device's copy (EE-238).
///
/// The server's `listAssets` is the reference and this follows it — type and
/// status exact, retired last, then by name — with two deliberate
/// differences, both toward the person holding the phone:
///
///   • the location matches the house search's way, every word somewhere
///     with the Turkish fold (ADR-0013), so "hol 3" finds "Döküm Holü /
///     Hat 3" the way EE-194's filter comment always claimed and a single
///     LIKE on the server never did;
///   • "running out soon" counts from the DEVICE's day, not UTC's: a
///     warranty ends on a date, and at 01:00 in İzmir it is already
///     tomorrow there.
List<EeAsset> filterAssets(
  Iterable<EeAsset> rows,
  EeAssetFilter filter, {
  required DateTime now,
}) {
  final place = filter.location == null
      ? const <String>[]
      : SearchService.queryWords(filter.location!);
  final days = filter.expiringWithinDays;
  final today = _day(now);
  final horizon = days == null
      ? null
      : _day(DateTime(now.year, now.month, now.day + days));
  bool lapses(String? day) =>
      day != null &&
      horizon != null &&
      day.compareTo(today) >= 0 &&
      day.compareTo(horizon) <= 0;

  final kept = <(String, EeAsset)>[];
  for (final asset in rows) {
    if (filter.workspaceId != null && asset.workspaceId != filter.workspaceId) {
      continue;
    }
    if (filter.type != null && asset.type != filter.type) continue;
    if (filter.status != null && asset.status != filter.status) continue;
    if (place.isNotEmpty) {
      final where = foldSearchText(asset.location ?? '');
      if (!place.every(where.contains)) continue;
    }
    if (horizon != null &&
        !lapses(asset.warrantyUntil) &&
        !lapses(asset.calibrationDue)) {
      continue;
    }
    // Folded once per row, not once per comparison: a plant register is
    // thousands of machines, and a sort compares each row many times.
    kept.add((foldSearchText(asset.name), asset));
  }
  kept.sort((a, b) {
    final retired =
        (a.$2.status == 'retired' ? 1 : 0) - (b.$2.status == 'retired' ? 1 : 0);
    if (retired != 0) return retired;
    final byName = a.$1.compareTo(b.$1);
    return byName != 0 ? byName : a.$2.tag.compareTo(b.$2.tag);
  });
  return [for (final (_, asset) in kept) asset];
}

/// The register as this device holds it.
class EeAssetRegister {
  const EeAssetRegister({
    this.rows = const [],
    this.onDevice = const {},
    this.types = const [],
  });

  /// Filtered and ordered — what the list draws.
  final List<EeAsset> rows;

  /// EVERY id the current workspace's replica holds, filters aside. The
  /// server's answer is drawn minus these, so a row the device has but a
  /// filter hid never comes back from the server labelled "not on this
  /// device".
  final Set<String> onDevice;

  /// The type keys on the device, for the filter chips when the server's
  /// vocabulary is out of reach.
  final List<String> types;
}

/// EE-238 — the register, from the replica of the current workspace.
///
/// No entitlement gate, for the queue's reason: the replica holds only what
/// the server sent, and a gate that answers "no" while the entitlement check
/// is still loading would draw an empty register in exactly the basement this
/// exists for.
final eeAssetRegisterProvider = StreamProvider.autoDispose
    .family<EeAssetRegister, EeAssetFilter>((ref, filter) {
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return Stream.value(const EeAssetRegister());
      final db = ref.watch(databaseProvider);
      return (db.select(db.assets)
            ..where((a) => a.workspaceId.equals(workspace.id)))
          .watch()
          .map((records) {
            final all = [for (final row in records) eeAssetFromRecord(row)];
            return EeAssetRegister(
              rows: filterAssets(all, filter, now: DateTime.now()),
              onDevice: {for (final asset in all) asset.id},
              types: ({for (final asset in all) asset.type}.toList()..sort()),
            );
          });
    });

/// "The server could not be reached", in the one shape every surface here
/// already draws — the same error a failed request becomes (`asApiException`).
const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer", as opposed to an answer.
bool assetNeedsConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// What one screen asks the server: the list's filters and its search words.
typedef EeAssetServerQuery = ({EeAssetFilter filter, String query});

/// EE-238 — what the SERVER holds that this device's list does not.
///
/// Another unit's equipment, the stock shelf while a unit is open, and the
/// retired records EE-219 took off devices after ninety still days. The
/// screen subtracts [EeAssetRegister.onDevice] and draws the remainder under
/// its own heading; offline this fails as [_unreachable] WITHOUT asking — the
/// app already knows (OPH-342), and a request bound to fail would only repeat
/// it after a timeout. It asks again by itself when the server answers
/// anything, because it watches that signal.
final eeAssetsOffDeviceProvider = FutureProvider.autoDispose
    .family<List<EeAsset>, EeAssetServerQuery>((ref, key) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      final query = key.query.trim();
      return ref
          .watch(eeAssetsApiProvider)
          .list(
            type: key.filter.type,
            status: key.filter.status,
            location: key.filter.location,
            expiringWithinDays: key.filter.expiringWithinDays,
            q: query.isEmpty ? null : query,
            workspaceId: key.filter.workspaceId,
          );
    });

/// EE-239 — the places the register can be narrowed to.
///
/// The SERVER's answer, deliberately: a list derived from the rows on screen
/// would miss every unit whose machines sort past the first page of a plant
/// register, and the picker would quietly offer a smaller company than the
/// person works in. Server-only and gated like the type vocabulary — with no
/// signal it does not ask, and the screen draws no picker it cannot fill.
final eeAssetUnitsProvider = FutureProvider.autoDispose<List<EeAssetUnit>>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const [];
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    throw _unreachable;
  }
  return ref.watch(eeAssetsApiProvider).units();
});

/// EE-238 — one machine's card, from the device's copy.
///
/// By id and NOT by the current workspace, like `ticketProvider`: a QR label
/// names a machine, not a unit, and a technician from Bakım scanning a press
/// on the stock shelf should get its card if this device holds it at all.
/// `null` means the device does not hold it — the screen then asks the server.
final eeAssetOnDeviceProvider = StreamProvider.autoDispose
    .family<EeAsset?, String>((ref, assetId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.assets)..where((a) => a.id.equals(assetId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : eeAssetFromRecord(row));
    });

/// When this device last heard from a workspace — how fresh its copy is.
///
/// A card read from the replica is as new as its workspace's last pull, and
/// saying so is what keeps an old copy from passing for a current one: the
/// unit on screen is minutes old, a unit last opened a month ago is a month
/// old, and both are drawn the same way otherwise.
final eeReplicaSyncedAtProvider = StreamProvider.autoDispose
    .family<DateTime?, String>((ref, workspaceId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.syncStates)
            ..where((s) => s.workspaceId.equals(workspaceId)))
          .watchSingleOrNull()
          .map((state) => state?.lastPulledAt);
    });

/// One machine from the SERVER — the card's fallback when the device does not
/// hold it (another unit's, or pruned by EE-219). A 404 travels: this is
/// reached by a QR code, and a scan that silently shows an empty card is worse
/// than one that says the tag is not in this register.
final eeAssetProvider = FutureProvider.autoDispose.family<EeAsset, String>((
  ref,
  assetId,
) async {
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    throw _unreachable;
  }
  return ref.watch(eeAssetsApiProvider).get(assetId);
});

/// A machine's requests (archive included) and labour — server-only, and
/// asked for EVERY time the card opens.
///
/// autoDispose is the point rather than a tidiness: a family kept alive would
/// hand yesterday's history to a card opened in a basement today and draw it
/// as current. EE-238's box says it in so many words — old data is not shown
/// as if it were fresh — so offline this is the reachability error, and the
/// card says the history needs a connection.
final eeAssetHistoryProvider = FutureProvider.autoDispose
    .family<EeAssetHistory, String>((ref, assetId) async {
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
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      return ref.watch(eeAssetsApiProvider).history(assetId);
    });

/// The type vocabulary — the built-ins plus the team's own words. Server-only;
/// offline the screens fall back to the keys on the device and to
/// [assetTypeLabel]'s built-in translations, so this does not ask while the
/// app knows it would only fail. Measured in EE-238's basement test: without
/// the gate every retry asked again — twelve requests under Riverpod's default
/// policy, four under the app's own (`awRetry`) — for a card that needed none.
final eeAssetTypesProvider = FutureProvider<EeAssetTypes>((ref) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const EeAssetTypes();
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    throw _unreachable;
  }
  return ref.watch(eeAssetsApiProvider).types();
});

/// A type's words: the team's own label, the built-in's translation, or —
/// for a key this device has no label for (offline, or a type added since)
/// — the key itself. Never an i18n path: `ee.assets.type.cnc_torna` is not
/// something to print on a card.
String assetTypeLabel(String type, EeAssetTypes types) =>
    types.team[type] ??
    AwI18n.instance.maybeTranslate('ee.assets.type.$type') ??
    type;

/// EE-220 — the register's search field, and the replica's first reader.
///
/// ── `searchAssets` HAS EXISTED SINCE EE-191 AND NOBODY CALLED IT ──────
///
/// OPH-326 wrote the rule that makes this a bug rather than a gap: "an entity
/// left out of search is an entity that does not exist for the user." The
/// registry obeyed it — `assets` is registered, its shadow columns are filled
/// on every pull, the SQL is ready — and the app never asked. Measured in the
/// EE-196 round and again here: zero callers.
final assetSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Ranked ids, or null when search is off.
///
/// The matching is local, instant, and does the Turkish `ı`/`i` fold that
/// neither SQLite nor MySQL does on its own (ADR-0013). Since EE-238 the list
/// behind it is the replica too, so with no signal the hits have rows to rank
/// — the "offline half" this comment used to write down as missing. What the
/// device does not hold is [eeAssetsOffDeviceProvider]'s question, asked
/// with the same words.
final assetSearchResultsProvider = FutureProvider.autoDispose<List<SearchHit>?>(
  (ref) async {
    final query = ref.watch(assetSearchQueryProvider).trim();
    if (query.isEmpty) return null;
    final workspace = ref.watch(currentWorkspaceProvider).value;
    if (workspace == null) return null;
    return ref.watch(searchServiceProvider).searchAssets(workspace.id, query);
  },
);
