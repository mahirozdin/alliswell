import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../search/search.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../assets_providers.dart';
import '../data/assets_models.dart';
import '../providers.dart';
import 'asset_detail_screen.dart';
import 'asset_labels.dart';

/// The equipment register (EE-194).
///
/// ── THE FILTER THAT DECIDED THE LAYOUT ─────────────────────────────────
///
/// "What lapses soon" is a chip rather than a buried option, because it is the
/// only question this screen answers that a spreadsheet cannot. Everything
/// else here — a list of machines, a search by location — a maintenance desk
/// already has in Excel; what it does not have is a register that tells it
/// when something is about to run out, and burying that behind a filter sheet
/// would waste the one advantage.
///
/// ── RETIRED SORTS LAST, IT DOES NOT DISAPPEAR ──────────────────────────
///
/// The services screen settled this first: archived reads as retired, muted,
/// never struck through or coloured like an error. Somebody looking for a
/// scrapped machine is asking what happened to it, and a register that hides
/// its own history answers "did we already replace this" with silence.
class EeAssetsScreen extends ConsumerStatefulWidget {
  const EeAssetsScreen({super.key});

  @override
  ConsumerState<EeAssetsScreen> createState() => _EeAssetsScreenState();
}

class _EeAssetsScreenState extends ConsumerState<EeAssetsScreen> {
  EeAssetFilter _filter = const EeAssetFilter();

  void _set(EeAssetFilter next) => setState(() => _filter = next);

  /// The list, narrowed and ordered by the search when one is running.
  ///
  /// `null` hits means the field is closed — the register is shown whole. An
  /// EMPTY list means it is open and nothing matched, which is a different
  /// answer and gets a different empty state.
  static List<EeAsset> _ranked(List<EeAsset> rows, List<SearchHit>? hits) {
    if (hits == null) return rows;
    final order = {for (var i = 0; i < hits.length; i += 1) hits[i].id: i};
    return rows.where((r) => order.containsKey(r.id)).toList()
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(eeAssetsProvider(_filter));
    final types = ref.watch(eeAssetTypesProvider).value ?? const EeAssetTypes();
    final canManage = ref.watch(canProvider('assets.manage'));
    final hits = ref.watch(assetSearchResultsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.assets.title'.tr()),
        actions: [
          // EE-220. The house search shape (DESIGN §12 S1), and the first
          // thing in this app to read the assets replica: `searchAssets` has
          // been ready since EE-191 and had zero callers, which by OPH-326's
          // own rule meant the register did not exist for anybody searching.
          AwSearchAction(
            fieldKey: const Key('asset-search'),
            hintText: 'ee.assets.searchHint'.tr(),
            onQuery: (q) => ref.read(assetSearchQueryProvider.notifier).set(q),
          ),
          if (canManage)
            IconButton(
              key: const Key('asset-labels'),
              tooltip: 'ee.assets.labels.action'.tr(),
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => printAssetLabels(
                context,
                ref,
                assets.value ?? const <EeAsset>[],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _Filters(filter: _filter, types: types, onChanged: _set),
          Expanded(
            child: assets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(eeAssetsProvider(_filter)),
              ),
              data: (all) {
                final rows = _ranked(all, hits);
                if (rows.isEmpty) {
                  // Two different emptinesses, and conflating them is how a
                  // person concludes the register is empty when their query
                  // simply missed (the queue screen settled this first).
                  return AwEmptyState(
                    icon: hits == null
                        ? Icons.precision_manufacturing_outlined
                        : Icons.search_off,
                    title: hits == null
                        ? 'ee.assets.empty'.tr()
                        : 'ee.assets.searchEmpty'.tr(),
                    message: hits == null
                        ? 'ee.assets.emptyBody'.tr()
                        : 'ee.assets.searchEmptyBody'.tr(),
                  );
                }
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _Row(asset: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.filter,
    required this.types,
    required this.onChanged,
  });

  final EeAssetFilter filter;
  final EeAssetTypes types;
  final ValueChanged<EeAssetFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x3,
        vertical: AwSpace.x2,
      ),
      child: Row(
        children: [
          // Free text, because the column is free text (ADR-0016: a location
          // TABLE is outside asset-lite). "Hol 3" matches "Döküm Holü / Hat 3"
          // the way a person means it, which a picker over an enumerated list
          // could not do for a plant that never enumerated one.
          SizedBox(
            width: 180,
            child: TextField(
              key: const Key('asset-filter-location'),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.place_outlined, size: 18),
                hintText: 'ee.assets.filter.location'.tr(),
              ),
              onSubmitted: (value) => onChanged(
                EeAssetFilter(
                  type: filter.type,
                  status: filter.status,
                  location: value.trim().isEmpty ? null : value.trim(),
                  expiringWithinDays: filter.expiringWithinDays,
                ),
              ),
            ),
          ),
          const SizedBox(width: AwSpace.x2),
          // The chip this screen exists for. First, and on by one tap.
          FilterChip(
            key: const Key('asset-filter-expiring'),
            label: Text('ee.assets.filter.expiring'.tr()),
            selected: filter.expiringWithinDays != null,
            onSelected: (on) => onChanged(
              EeAssetFilter(
                type: filter.type,
                status: filter.status,
                location: filter.location,
                expiringWithinDays: on ? 90 : null,
              ),
            ),
          ),
          const SizedBox(width: AwSpace.x2),
          for (final status in const [
            'in_use',
            'faulty',
            'maintenance',
            'in_stock',
          ]) ...[
            FilterChip(
              key: Key('asset-filter-$status'),
              label: Text('ee.assets.status.$status'.tr()),
              selected: filter.status == status,
              onSelected: (on) => onChanged(
                EeAssetFilter(
                  type: filter.type,
                  status: on ? status : null,
                  location: filter.location,
                  expiringWithinDays: filter.expiringWithinDays,
                ),
              ),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          for (final type in types.all) ...[
            FilterChip(
              key: Key('asset-filter-type-$type'),
              label: Text(types.team[type] ?? 'ee.assets.type.$type'.tr()),
              selected: filter.type == type,
              onSelected: (on) => onChanged(
                EeAssetFilter(
                  type: on ? type : null,
                  status: filter.status,
                  location: filter.location,
                  expiringWithinDays: filter.expiringWithinDays,
                ),
              ),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.asset});
  final EeAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retired = asset.status == 'retired';
    return ListTile(
      key: Key('asset-${asset.id}'),
      leading: const Icon(Icons.precision_manufacturing_outlined),
      // Tag first — it is painted on the machine, and it is what somebody
      // reads out on the phone.
      title: Text(
        '${asset.tag} · ${asset.name}',
        style: retired
            ? theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Text(
        [
          'ee.assets.status.${asset.status}'.tr(),
          if (asset.location != null) asset.location!,
        ].join(' · '),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EeAssetDetailScreen(assetId: asset.id),
        ),
      ),
    );
  }
}
