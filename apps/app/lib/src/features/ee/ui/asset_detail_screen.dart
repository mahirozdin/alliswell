import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../assets_providers.dart';
import '../data/assets_models.dart';
import '../providers.dart';
import 'asset_edit_sheet.dart';
import 'asset_labels.dart';
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
class EeAssetDetailScreen extends ConsumerWidget {
  const EeAssetDetailScreen({required this.assetId, super.key});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(eeAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.value?.tag ?? 'ee.assets.one'.tr()),
        actions: [
          if (asset.value != null &&
              ref.watch(canProvider('assets.manage')) &&
              asset.value!.status != 'retired')
            IconButton(
              key: const Key('asset-edit'),
              tooltip: 'ee.assets.edit'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editAssetSheet(context, ref, asset.value!),
            ),
          if (asset.value != null && ref.watch(canProvider('assets.manage')))
            IconButton(
              key: const Key('asset-label-one'),
              tooltip: 'ee.assets.labels.action'.tr(),
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => printAssetLabels(context, ref, [asset.value!]),
            ),
        ],
      ),
      body: asset.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // A scan that shows an empty card is worse than one that says the tag
        // is not in this register — this screen is reached from a sticker.
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeAssetProvider(assetId)),
        ),
        data: (row) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            _Facts(asset: row),
            const SizedBox(height: AwSpace.x6),
            _History(assetId: assetId),
          ],
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.asset});
  final EeAsset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String?)>[
      ('ee.assets.field.name', asset.name),
      ('ee.assets.field.type', 'ee.assets.type.${asset.type}'.tr()),
      ('ee.assets.field.status', 'ee.assets.status.${asset.status}'.tr()),
      ('ee.assets.field.location', asset.location),
      ('ee.assets.field.serial', asset.serialNo),
      ('ee.assets.field.manufacturer', asset.manufacturer),
      ('ee.assets.field.model', asset.model),
      ('ee.assets.field.warranty', asset.warrantyUntil),
      ('ee.assets.field.calibration', asset.calibrationDue),
      ('ee.assets.field.supplier', asset.supplier),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(asset.tag, style: theme.textTheme.headlineSmall),
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

/// ── WHY THERE IS NO "OPEN A REQUEST FOR THIS ASSET" BUTTON ────────────
///
/// The task asks for one, and it cannot land here yet. Measured before it was
/// written: this app has no in-app request-creation flow at all. Every ticket
/// endpoint it calls is a read or an edit of an existing request (`/mine`,
/// `/links`, `/convert`, `/related`, `/assets`) and nothing POSTs
/// `/ee/team/tickets`. Requests arrive through the public portal, by e-mail,
/// or from an agent.
///
/// So the button would be the FIRST one, and what it needs is a request form
/// — a service picker, an impact-and-urgency pair, an attachment path — which
/// is a task, not a button. Shipping one that navigates to a route that does
/// not exist would be a dead button, which this codebase tests against by
/// name.
///
/// What the QR code does deliver is already the larger half: scanning the
/// sticker opens exactly this card, with the machine's whole history on it.

class _History extends ConsumerWidget {
  const _History({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(eeAssetHistoryProvider(assetId));

    return history.when(
      // Quiet on both: the facts above already work, and a red box here would
      // make a slow network look like a broken machine record.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ee.assets.history.title'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
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
          // EE-208. Drawn only when there is labour to draw: an hours line
          // reading "0" on a machine nobody has worked on is noise, and the
          // acceptance line asks for the cost field to be HIDDEN rather than
          // shown empty.
          if (data.stats.labourMinutes > 0) ...[
            const SizedBox(height: AwSpace.x2),
            Text(
              'ee.assets.history.labour'.tr(
                args: {'hours': '${(data.stats.labourMinutes / 60).round()}'},
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
                  args: {
                    'hours':
                        '${(data.stats.labourUnpricedMinutes / 60).round()}',
                  },
                ),
                key: const Key('asset-history-labour-unpriced'),
                style: theme.textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: AwSpace.x3),
          if (data.tickets.isEmpty)
            Text(
              'ee.assets.history.empty'.tr(),
              style: theme.textTheme.bodySmall,
            )
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
                subtitle: Text(
                  ticket.archived
                      ? 'ee.assets.history.archived'.tr()
                      : 'ee.tickets.status.${ticket.status}'.tr(),
                ),
                // An archived request has no live screen to open — it left
                // `ee_tickets`. Saying nothing is honest; a tap that lands on
                // "not found" is not.
                onTap: ticket.archived
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EeTicketDetailScreen(ticketId: ticket.id),
                        ),
                      ),
              ),
        ],
      ),
    );
  }
}
