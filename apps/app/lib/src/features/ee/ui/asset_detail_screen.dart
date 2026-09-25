import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../assets_providers.dart';
import '../data/assets_models.dart';
import '../providers.dart';
import 'asset_edit_sheet.dart';
import 'asset_labels.dart';
import 'new_ticket_screen.dart';
import 'ticket_archive_screen.dart';
import 'ticket_detail_screen.dart';

/// One machine's card — what a QR code opens (EE-194).
///
/// ── THE ARCHIVE IS THE POINT OF THE LIST ───────────────────────────────
///
/// Most of a machine's history is closed and swept. A card showing only live
/// requests would say "4" where the truth is "14", which is exactly the
/// blindness the analysis named: the same printer fails fourteen times a
/// month and nobody says it should be replaced. Archived rows are drawn as
/// what they are, muted, not hidden.
///
/// ── AND THE NUMBER IS LABELLED FOR WHAT IT MEASURES ────────────────────
///
/// "Open time", not "downtime". The server sums how long requests stayed
/// open. Calling it downtime on the screen would be a number that reads as a
/// fact and is not one.
///
/// ── CORRECTED BY EE-208, BECAUSE THE OLD SENTENCE PROMISED THE WRONG THING ──
///
/// This used to say "nobody records how long the machine was stopped (EE-208's
/// worklog is the round that will)". EE-208 has landed and it does NOT record
/// that. A worklog is LABOUR — this person spent ninety minutes on this
/// request — and a press can stand idle for three days while a technician
/// spends two hours on it. Those are three different numbers:
///
///   open time   how long requests about it stayed open   (here, since EE-192)
///   labour      how long people worked on it             (here, since EE-208)
///   downtime    how long the machine was stopped         (NOBODY RECORDS THIS)
///
/// The third is still missing and is a legitimate thing to want; it needs a
/// stopped-at/restarted-at pair on the asset, which is a feature and not a
/// column. Saying so plainly is better than pointing at a task that has
/// already shipped without it — a promise that has been kept wrongly is
/// harder to notice than one nobody made.
///
/// ── AND THE TWO MONEY FIGURES ARE NEVER ADDED ──────────────────────────
///
/// Purchase price and labour cost sit beside each other. A machine bought in
/// euros and maintained by a team billed in lira has two figures and no third
/// one, so there is no "total cost of ownership" line here and the server has
/// nowhere to put one either.
///
/// ── THE CARD OPENS FROM THE DEVICE; ITS HISTORY SAYS IT NEEDS THE SERVER ──
///
/// EE-238, and the reason the replica exists (AW-E16): a technician in a
/// basement scans the sticker and gets the machine, not a network error. The
/// facts come from the device's copy and say how old that copy is; the server
/// is asked only when the device does not hold the machine at all — another
/// unit's, or a retired one EE-219 took off devices — and a card drawn from
/// the server says THAT. The history and the labour are the server's alone
/// (they span the archive, which no device carries), and the section says so
/// before it is needed rather than after it fails: offline it is one quiet
/// line and a retry, never yesterday's numbers drawn as today's.
class EeAssetDetailScreen extends ConsumerWidget {
  const EeAssetDetailScreen({required this.assetId, super.key});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(eeAssetOnDeviceProvider(assetId));
    final onDevice = local.value;
    // Asked only once the device has answered "not here": a card the device
    // holds must not wait on, or be overwritten by, a network round trip.
    final remote = local.hasValue && onDevice == null
        ? ref.watch(eeAssetProvider(assetId))
        : null;
    final asset = onDevice ?? remote?.value;
    final canManage = ref.watch(canProvider('assets.manage'));
    // Editing is a server write (a register nobody can audit is the reason
    // there is no offline edit), so offline the pencil is greyed BEFORE it is
    // pressed, with the reason as its tooltip — OPH-342's rule.
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(asset?.tag ?? 'ee.assets.one'.tr()),
        actions: [
          if (asset != null && canManage && asset.status != 'retired')
            IconButton(
              key: const Key('asset-edit'),
              tooltip: offline
                  ? 'ee.assets.editOffline'.tr()
                  : 'ee.assets.edit'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: offline
                  ? null
                  : () => editAssetSheet(context, ref, asset),
            ),
          if (asset != null && canManage)
            IconButton(
              key: const Key('asset-label-one'),
              tooltip: 'ee.assets.labels.action'.tr(),
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => printAssetLabels(context, ref, [asset]),
            ),
        ],
      ),
      body: _body(ref, local, remote),
    );
  }

  Widget _body(
    WidgetRef ref,
    AsyncValue<EeAsset?> local,
    AsyncValue<EeAsset>? remote,
  ) {
    if (!local.hasValue) {
      return local.hasError
          ? AwErrorState(
              message: localizedError(local.error!),
              onRetry: () => ref.invalidate(eeAssetOnDeviceProvider(assetId)),
            )
          : const Center(child: CircularProgressIndicator());
    }
    final onDevice = local.value;
    if (onDevice != null) return _Card(asset: onDevice, fromServer: false);
    if (remote == null) return const Center(child: CircularProgressIndicator());
    return remote.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // A scan that shows an empty card is worse than one that says the tag
      // is not in this register — this screen is reached from a sticker. And
      // "not on this device, no connection" is a third answer, not an error:
      // the machine exists, the phone does not carry it, and the signal is
      // what is missing.
      error: (error, _) => assetNeedsConnection(error)
          ? AwEmptyState(
              key: const Key('asset-not-on-device'),
              icon: Icons.cloud_off_outlined,
              title: 'ee.assets.card.notOnDevice'.tr(),
              message: 'ee.assets.card.notOnDeviceBody'.tr(),
              action: OutlinedButton.icon(
                onPressed: () =>
                    _retry(ref, () => ref.invalidate(eeAssetProvider(assetId))),
                icon: const Icon(Icons.refresh),
                label: Text('common.retry'.tr()),
              ),
            )
          : AwErrorState(
              message: localizedError(error),
              onRetry: () => ref.invalidate(eeAssetProvider(assetId)),
            ),
      data: (row) => _Card(asset: row, fromServer: true),
    );
  }
}

/// A retry that can actually change the answer.
///
/// The reads here do not ask while the app knows it is offline, so
/// invalidating one alone would ask the same stale question. The sync
/// engine's pull is the probe every other surface already trusts: if the
/// server answers it, the reachability signal flips and every read watching
/// it asks again on its own.
void _retry(WidgetRef ref, void Function() invalidate) {
  invalidate();
  unawaited(ref.read(syncEngineProvider)?.syncNow());
}

class _Card extends ConsumerWidget {
  const _Card({required this.asset, required this.fromServer});

  final EeAsset asset;
  final bool fromServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(eeAssetTypesProvider).value ?? const EeAssetTypes();
    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        _Facts(
          asset: asset,
          typeLabel: assetTypeLabel(asset.type, types),
          provenance: _Provenance(asset: asset, fromServer: fromServer),
        ),
        _OpenRequest(asset: asset),
        const SizedBox(height: AwSpace.x6),
        _History(assetId: asset.id),
      ],
    );
  }
}

/// Where the facts above came from, and how old they are.
class _Provenance extends ConsumerWidget {
  const _Provenance({required this.asset, required this.fromServer});

  final EeAsset asset;
  final bool fromServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final workspaceId = asset.workspaceId;
    final synced = fromServer || workspaceId == null
        ? null
        : ref.watch(eeReplicaSyncedAtProvider(workspaceId)).value;
    final text = fromServer
        ? 'ee.assets.card.fromServer'.tr()
        : synced == null
        ? 'ee.assets.card.onDevice'.tr()
        : 'ee.assets.card.onDeviceSynced'.tr(
            args: {'ago': awRelativePast(synced, DateTime.now())},
          );
    return Row(
      key: const Key('asset-provenance'),
      children: [
        Icon(
          fromServer ? Icons.cloud_outlined : Icons.offline_pin_outlined,
          size: 16,
          color: muted,
        ),
        const SizedBox(width: AwSpace.x1),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// The purchase price as the record states it, or null when it states none.
String? _price(EeAsset asset) {
  final minor = asset.purchaseCostMinor;
  if (minor == null) return null;
  final amount = (minor / 100).toStringAsFixed(2);
  final currency = asset.currency;
  return currency == null ? amount : '$amount $currency';
}

class _Facts extends StatelessWidget {
  const _Facts({
    required this.asset,
    required this.typeLabel,
    required this.provenance,
  });
  final EeAsset asset;
  final String typeLabel;
  final Widget provenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String?)>[
      ('ee.assets.field.name', asset.name),
      ('ee.assets.field.type', typeLabel),
      ('ee.assets.field.status', 'ee.assets.status.${asset.status}'.tr()),
      ('ee.assets.field.location', asset.location),
      ('ee.assets.field.serial', asset.serialNo),
      ('ee.assets.field.manufacturer', asset.manufacturer),
      ('ee.assets.field.model', asset.model),
      ('ee.assets.field.warranty', asset.warrantyUntil),
      ('ee.assets.field.calibration', asset.calibrationDue),
      ('ee.assets.field.supplier', asset.supplier),
      // EE-271: when it was bought and for how much — on the device since
      // EE-191 and never drawn, while the guide promised both. The date is
      // the day as typed (`YYYY-MM-DD`, like the warranty); the price is the
      // record's own currency, never converted — the history below keeps
      // labour in ITS currency beside it and adds nothing up.
      ('ee.assets.field.purchased', asset.purchasedAt),
      ('ee.assets.field.purchaseCost', _price(asset)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(asset.tag, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AwSpace.x1),
        provenance,
        const SizedBox(height: AwSpace.x3),
        for (final (key, value) in rows)
          if (value != null && value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AwSpace.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      key.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
      ],
    );
  }
}

/// "Open a request for this machine" (EE-271).
///
/// This card once explained why the button could not exist: the app had no
/// request form. EE-225 built the form and the explanation went stale while
/// the button stayed missing, so a technician who scanned the sticker had the
/// machine's whole history in hand and no way to add to it. The button opens
/// the same form every other door uses, with this machine already in its
/// asset field — and it works with no signal, because the form then writes a
/// draft that carries the machine (EE-281). Not offered for a retired
/// machine: a request is about something that is supposed to be working.
class _OpenRequest extends ConsumerWidget {
  const _OpenRequest({required this.asset});
  final EeAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (asset.status == 'retired' ||
        !ref.watch(canProvider('tickets.create'))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.tonalIcon(
          key: const Key('asset-open-request'),
          onPressed: () =>
              awOpenNewTicket(context, asset: EeTicketAsset.of(asset)),
          icon: const Icon(Icons.add_comment_outlined),
          label: Text('ee.assets.openRequest'.tr()),
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final history = ref.watch(eeAssetHistoryProvider(assetId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ee.assets.history.title'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x1),
        // EE-238. Said while it works, not only when it fails: the facts above
        // open anywhere, this part does not, and a technician should know
        // which half of the card to trust in a basement before the basement.
        Row(
          children: [
            Icon(Icons.cloud_outlined, size: 14, color: muted),
            const SizedBox(width: AwSpace.x1),
            Expanded(
              child: Text(
                'ee.assets.history.live'.tr(),
                key: const Key('asset-history-live'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: AwSpace.x2),
        history.when(
          // Quiet: the facts above already work, and a spinner the size of
          // the card would make a slow network look like a missing machine.
          loading: () => const LinearProgressIndicator(minHeight: 2),
          // Muted, never red: a history that needs a connection is not a
          // broken machine record.
          error: (error, _) => Row(
            key: const Key('asset-history-offline'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: muted),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(
                  assetNeedsConnection(error)
                      ? 'ee.assets.history.offline'.tr()
                      : localizedError(error),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              TextButton(
                onPressed: () => _retry(
                  ref,
                  () => ref.invalidate(eeAssetHistoryProvider(assetId)),
                ),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
          data: (data) => _HistoryBody(data: data),
        ),
      ],
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.data});
  final EeAssetHistory data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ee.assets.history.counts'.tr(
            args: {
              'months': '${data.stats.months}',
              'count': '${data.stats.ticketCount}',
              'open': '${data.stats.openTicketCount}',
              'hours': '${(data.stats.openMinutes / 60).round()}',
            },
          ),
          key: const Key('asset-history-counts'),
          style: theme.textTheme.bodyMedium,
        ),
        // EE-272 (AW-E22): the header of this file says it to the code; this
        // says it to the reader. "36 h of open time" beside a machine's name
        // reads as "the machine was down for 36 h" unless something says it is
        // not — and nothing on this card records when a machine stopped.
        if (data.stats.ticketCount > 0) ...[
          const SizedBox(height: AwSpace.x1),
          Text(
            'ee.assets.history.openTimeNote'.tr(),
            key: const Key('asset-history-open-time-note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        // EE-208. Drawn only when there is labour to draw: an hours line
        // reading "0" on a machine nobody has worked on is noise, and the
        // acceptance line asks for the cost field to be HIDDEN rather than
        // shown empty.
        if (data.stats.labourMinutes > 0) ...[
          const SizedBox(height: AwSpace.x2),
          // EE-240: one decimal, like the worklog panel — rounded to whole
          // hours, twenty minutes of recorded work read as "0".
          Text(
            'ee.assets.history.labour'.tr(
              args: {'hours': eeHoursText(data.stats.labourMinutes)},
            ),
            key: const Key('asset-history-labour'),
            style: theme.textTheme.bodyMedium,
          ),
          // One line per currency, never a sum. The list is the refusal.
          for (final money in data.stats.labourByCurrency)
            Text(
              'ee.assets.history.labourCost'.tr(
                args: {
                  'amount': (money.costMinor / 100).toStringAsFixed(2),
                  'currency': money.currency,
                },
              ),
              key: Key('asset-history-labour-${money.currency}'),
              style: theme.textTheme.bodySmall,
            ),
          if (data.stats.labourUnpricedMinutes > 0)
            Text(
              'ee.assets.history.labourUnpriced'.tr(
                args: {'hours': eeHoursText(data.stats.labourUnpricedMinutes)},
              ),
              key: const Key('asset-history-labour-unpriced'),
              style: theme.textTheme.bodySmall,
            ),
        ],
        const SizedBox(height: AwSpace.x3),
        if (data.tickets.isEmpty)
          Text('ee.assets.history.empty'.tr(), style: theme.textTheme.bodySmall)
        else
          for (final ticket in data.tickets)
            ListTile(
              key: Key('asset-ticket-${ticket.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                ticket.archived
                    ? Icons.inventory_2_outlined
                    : Icons.confirmation_number_outlined,
                color: ticket.archived
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
              title: Text(
                ticket.number == null
                    ? ticket.subject
                    : '#${ticket.number} · ${ticket.subject}',
                style: ticket.archived
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              // EE-240: the request's own hours beside its state — minutes
              // as hours, money one currency at a time, never summed. Absent
              // when nobody logged any, and absent for a request on a desk
              // this person does not work on (the server sends no figure).
              subtitle: Text(
                [
                  ticket.archived
                      ? 'ee.assets.history.archived'.tr()
                      : 'ee.tickets.status.${ticket.status}'.tr(),
                  if (ticket.labour != null && ticket.labour!.minutes > 0) ...[
                    'ee.assets.history.ticketLabour'.tr(
                      args: {'hours': eeHoursText(ticket.labour!.minutes)},
                    ),
                    for (final money in ticket.labour!.byCurrency)
                      'ee.worklogs.money'.tr(
                        args: {
                          'amount': (money.costMinor / 100).toStringAsFixed(2),
                          'currency': money.currency,
                        },
                      ),
                  ],
                ].join(' · '),
                key: Key('asset-ticket-meta-${ticket.id}'),
              ),
              // EE-266: an archived request opens the archive's read-only
              // view (it used to have no screen at all, so the row took no
              // tap — the honest answer then). A live one opens by its
              // address, which now also says when it lives in another unit.
              onTap: ticket.archived
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            EeArchivedTicketScreen(ticketId: ticket.id),
                      ),
                    )
                  : () => awOpenTicket(context, ticket.id),
            ),
      ],
    );
  }
}
