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
///
/// ── TWO SOURCES, AND THE SCREEN SAYS WHICH IS WHICH (EE-238) ───────────
///
/// The rows first are the device's own copy of this unit's register: they
/// open with no signal, and search ranks them with no signal. Below them,
/// under their own heading, come the rows only the server holds — another
/// unit's equipment, and the retired records EE-219 takes off devices after
/// ninety still days. Offline that second half cannot be fetched, so it is
/// replaced by one line saying it exists and needs a connection. The line is
/// the difference between "there is no such machine" and "this phone does
/// not carry it" — the second is true, the first would be a guess.
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
    final register = ref.watch(eeAssetRegisterProvider(_filter));
    final types = ref.watch(eeAssetTypesProvider).value ?? const EeAssetTypes();
    final canManage = ref.watch(canProvider('assets.manage'));
    final query = ref.watch(assetSearchQueryProvider).trim();
    final hits = ref.watch(assetSearchResultsProvider).value;
    final server = ref.watch(
      eeAssetsOffDeviceProvider((filter: _filter, query: query)),
    );

    final device = register.value;
    final here = device == null
        ? const <EeAsset>[]
        : _ranked(device.rows, hits);
    // The server's answer minus everything this workspace's copy holds —
    // filters aside, so a row a filter hid on the device does not come back
    // from the server labelled "not on this device".
    final elsewhere = device == null
        ? const <EeAsset>[]
        : [
            for (final asset in server.value ?? const <EeAsset>[])
              if (!device.onDevice.contains(asset.id)) asset,
          ];

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
              onPressed: () =>
                  printAssetLabels(context, ref, [...here, ...elsewhere]),
            ),
        ],
      ),
      body: Column(
        children: [
          _Filters(
            filter: _filter,
            types: types,
            deviceTypes: device?.types ?? const [],
            units: ref.watch(eeAssetUnitsProvider).value ?? const [],
            onChanged: _set,
          ),
          Expanded(
            child: register.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(eeAssetRegisterProvider(_filter)),
              ),
              data: (_) => _body(
                here: here,
                elsewhere: elsewhere,
                server: server,
                // `hits` is null exactly when the field is closed (EE-220's
                // contract); the typed words also count, for the frame
                // before the replica's first answer arrives.
                searching: hits != null || query.isNotEmpty,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body({
    required List<EeAsset> here,
    required List<EeAsset> elsewhere,
    required AsyncValue<List<EeAsset>> server,
    required bool searching,
  }) {
    final offline = server.hasError && assetNeedsConnection(server.error);
    if (here.isEmpty && elsewhere.isEmpty) {
      // Nothing on the device yet and the server still answering: wait for
      // it rather than announce an empty register for a second.
      if (server.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      // Two different emptinesses, and conflating them is how a person
      // concludes the register is empty when their query simply missed (the
      // queue screen settled this first). EE-238 adds the third: nothing on
      // THIS DEVICE, with the rest out of reach — which is not "no
      // equipment", and must not say so.
      return AwEmptyState(
        key: const Key('asset-empty'),
        icon: searching
            ? Icons.search_off
            : offline
            ? Icons.cloud_off_outlined
            : Icons.precision_manufacturing_outlined,
        title: searching
            ? 'ee.assets.searchEmpty'.tr()
            : offline
            ? 'ee.assets.emptyOnDevice'.tr()
            : 'ee.assets.empty'.tr(),
        message: offline
            ? 'ee.assets.offDevice.offline'.tr()
            : searching
            ? 'ee.assets.searchEmptyBody'.tr()
            : 'ee.assets.emptyBody'.tr(),
      );
    }
    final heading = elsewhere.isEmpty ? 0 : 1;
    final note = offline ? 1 : 0;
    return ListView.builder(
      itemCount: here.length + heading + elsewhere.length + note,
      itemBuilder: (context, index) {
        var i = index;
        if (i < here.length) return _Row(asset: here[i]);
        i -= here.length;
        if (heading == 1 && i == 0) return const _ServerHeading();
        i -= heading;
        if (i < elsewhere.length) {
          return _Row(asset: elsewhere[i], fromServer: true);
        }
        return const _OfflineNote();
      },
    );
  }
}

/// The heading over the rows only the server holds.
class _ServerHeading extends StatelessWidget {
  const _ServerHeading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('asset-off-device'),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x5,
        AwSpace.x4,
        AwSpace.x1,
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              'ee.assets.offDevice.title'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// What stands in for the server's rows when the server cannot be reached.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      key: const Key('asset-off-device-offline'),
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x5,
        AwSpace.x4,
        AwSpace.x6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: muted),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              'ee.assets.offDevice.offline'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
    required this.deviceTypes,
    required this.units,
    required this.onChanged,
  });

  final EeAssetFilter filter;
  final EeAssetTypes types;

  /// EE-239 — the places this person's register spans, from the server.
  /// Empty offline: the device holds one unit's copy, so there is nothing to
  /// choose between until the server can say what else there is.
  final List<EeAssetUnit> units;

  /// The types on the device's copy. Offline the server's vocabulary is out
  /// of reach, and a filter row that lost its type chips in the basement
  /// would be the register quietly shrinking to "search only".
  final List<String> deviceTypes;
  final ValueChanged<EeAssetFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final typeKeys = [
      ...types.all,
      for (final type in deviceTypes)
        if (!types.all.contains(type)) type,
    ];
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
                  workspaceId: filter.workspaceId,
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
                workspaceId: filter.workspaceId,
              ),
            ),
          ),
          const SizedBox(width: AwSpace.x2),
          // EE-239: one place — a unit or the stock shelf. Shown once there is
          // more than one place to choose (a picker with one answer is not a
          // question), and always while one is chosen, so it can be undone
          // with no signal as well.
          if (filter.workspaceId != null || units.length > 1) ...[
            _UnitChip(filter: filter, units: units, onChanged: onChanged),
            const SizedBox(width: AwSpace.x2),
          ],
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
                  workspaceId: filter.workspaceId,
                ),
              ),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          for (final type in typeKeys) ...[
            FilterChip(
              key: Key('asset-filter-type-$type'),
              label: Text(assetTypeLabel(type, types)),
              selected: filter.type == type,
              onSelected: (on) => onChanged(
                EeAssetFilter(
                  type: on ? type : null,
                  status: filter.status,
                  location: filter.location,
                  expiringWithinDays: filter.expiringWithinDays,
                  workspaceId: filter.workspaceId,
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

/// EE-239 — the place filter. Tapped while set, it clears (the queue's tag
/// chip settled the gesture); otherwise it asks which place.
class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.filter,
    required this.units,
    required this.onChanged,
  });

  final EeAssetFilter filter;
  final List<EeAssetUnit> units;
  final ValueChanged<EeAssetFilter> onChanged;

  EeAssetFilter _with(String? workspaceId) => EeAssetFilter(
    type: filter.type,
    status: filter.status,
    location: filter.location,
    expiringWithinDays: filter.expiringWithinDays,
    workspaceId: workspaceId,
  );

  @override
  Widget build(BuildContext context) {
    String? chosen;
    for (final unit in units) {
      if (unit.workspaceId == filter.workspaceId) chosen = unit.name;
    }
    return FilterChip(
      key: const Key('asset-filter-unit'),
      avatar: const Icon(Icons.apartment_outlined, size: 18),
      label: Text(
        chosen == null
            ? 'ee.assets.filter.unit'.tr()
            : 'ee.assets.filter.unitSet'.tr(args: {'unit': chosen}),
      ),
      selected: filter.workspaceId != null,
      onSelected: (_) async {
        if (filter.workspaceId != null) {
          onChanged(_with(null));
          return;
        }
        final picked = await showModalBottomSheet<EeAssetUnit>(
          context: context,
          showDragHandle: true,
          builder: (_) => _UnitPicker(units: units),
        );
        if (picked != null) onChanged(_with(picked.workspaceId));
      },
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({required this.units});

  final List<EeAssetUnit> units;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x2,
            ),
            child: Text(
              'ee.assets.filter.unitPickTitle'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final unit in units)
            ListTile(
              key: Key('asset-filter-unit-option-${unit.workspaceId}'),
              leading: Icon(
                unit.stock
                    ? Icons.inventory_2_outlined
                    : Icons.apartment_outlined,
              ),
              title: Text(unit.name),
              subtitle: unit.stock
                  ? Text('ee.assets.filter.unitStock'.tr())
                  : (unit.unitName != null && unit.unitName != unit.name
                        ? Text(unit.unitName!)
                        : null),
              onTap: () => Navigator.of(context).pop(unit),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.asset, this.fromServer = false});
  final EeAsset asset;

  /// Drawn from the server's answer rather than the device's copy — it opens
  /// only with a connection, and the icon says so beside the heading above.
  final bool fromServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retired = asset.status == 'retired';
    return ListTile(
      key: Key('asset-${asset.id}'),
      leading: Icon(
        fromServer
            ? Icons.cloud_outlined
            : Icons.precision_manufacturing_outlined,
      ),
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
