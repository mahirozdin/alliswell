import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/unit_tickets_api.dart';
import '../unit_tickets_providers.dart';
import 'sla_chip.dart';
import 'ticket_detail_screen.dart' show awOpenTicket;

/// EE-267 (AW-E19) — one tap from a request of another unit to the request.
///
/// The device holds one unit at a time, so reaching a Bakım request from BT
/// means opening Bakım first: the sync engine follows the selected
/// workspace, and the detail (EE-251's address) opens by itself as that
/// unit's copy lands — saying "opening Bakım" rather than offering a switch
/// that already happened (EE-266's frame, told apart).
Future<void> openTicketAcrossUnits(
  BuildContext context,
  WidgetRef ref,
  EeUnitTicket ticket,
) async {
  final here = ref.read(currentWorkspaceProvider).value?.id;
  if (ticket.workspaceId != here) {
    await ref
        .read(selectedWorkspaceIdProvider.notifier)
        .select(ticket.workspaceId);
  }
  if (!context.mounted) return;
  awOpenTicket(context, ticket.id);
}

/// "Birimlerim" — open requests in every unit this person works in, latest
/// promise first, live from the server.
///
/// ── LIVE, AND SAID SO ─────────────────────────────────────────────────────
///
/// Everything else on the queue shelf reads the replica and works on a
/// factory floor with no signal. This screen cannot — the device holds one
/// unit — so it says what it is at the top ("live — needs a connection"),
/// and when it cannot ask it shows THAT, never the list it last had. An old
/// copy drawn as if it were current is the one failure D17.9 rules out.
class EeMyUnitsScreen extends ConsumerStatefulWidget {
  const EeMyUnitsScreen({this.alertsOnly = false, super.key});

  /// Opened from the queue's strip: the alerts, not the whole list.
  final bool alertsOnly;

  @override
  ConsumerState<EeMyUnitsScreen> createState() => _EeMyUnitsScreenState();
}

class _EeMyUnitsScreenState extends ConsumerState<EeMyUnitsScreen> {
  late bool _alertsOnly = widget.alertsOnly;

  /// Where each loaded page starts: `''` for the first, then each page's
  /// `nextCursor` — the archive's way of stacking pages (EE-266).
  final List<String> _cursors = [''];

  EeUnitTicketsKey _key(String cursor) =>
      (alertsOnly: _alertsOnly, cursor: cursor);

  void _setAlertsOnly(bool value) => setState(() {
    _alertsOnly = value;
    _cursors
      ..clear()
      ..add('');
  });

  Future<void> _refresh() async {
    setState(
      () => _cursors
        ..clear()
        ..add(''),
    );
    ref.invalidate(eeUnitTicketsPageProvider);
    // The reads do not ask while the app knows it is offline, so the sync
    // engine's pull is the probe: if the server answers it, they ask again.
    unawaited(ref.read(syncEngineProvider)?.syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final first = ref.watch(eeUnitTicketsPageProvider(_key('')));
    return Scaffold(
      appBar: AppBar(title: Text('ee.myUnits.title'.tr())),
      body: first.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => unitTicketsNeedConnection(error)
            ? AwEmptyState(
                key: const Key('my-units-offline'),
                icon: Icons.cloud_off_outlined,
                title: 'ee.myUnits.offlineTitle'.tr(),
                message: 'ee.myUnits.offlineBody'.tr(),
                action: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text('common.retry'.tr()),
                ),
              )
            : AwErrorState(message: localizedError(error), onRetry: _refresh),
        data: (page) => RefreshIndicator(
          key: const Key('my-units-refresh'),
          onRefresh: _refresh,
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              _Header(
                page: page,
                alertsOnly: _alertsOnly,
                onAlertsOnly: _setAlertsOnly,
              ),
              if (page.units.isEmpty)
                AwEmptyState(
                  key: const Key('my-units-no-units'),
                  icon: Icons.groups_outlined,
                  title: 'ee.myUnits.noUnitsTitle'.tr(),
                  message: 'ee.myUnits.noUnitsBody'.tr(),
                )
              else if (page.tickets.isEmpty)
                _alertsOnly
                    ? AwEmptyState(
                        key: const Key('my-units-no-alerts'),
                        icon: Icons.verified_outlined,
                        title: 'ee.myUnits.noAlertsTitle'.tr(),
                        message: 'ee.myUnits.noAlertsBody'.tr(),
                      )
                    : AwEmptyState(
                        key: const Key('my-units-empty'),
                        icon: Icons.inbox_outlined,
                        title: 'ee.myUnits.emptyTitle'.tr(),
                        message: 'ee.myUnits.emptyBody'.tr(),
                      )
              else ...[
                for (final ticket in page.tickets) _Row(ticket: ticket),
                for (var i = 1; i < _cursors.length; i += 1)
                  _Page(
                    key: ValueKey(_key(_cursors[i])),
                    pageKey: _key(_cursors[i]),
                    last: i == _cursors.length - 1,
                    onMore: (cursor) => setState(() => _cursors.add(cursor)),
                  ),
                if (_cursors.length == 1 && page.hasMore)
                  _MoreButton(
                    onPressed: () =>
                        setState(() => _cursors.add(page.nextCursor!)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What this list is, whose units it covers, and how late their promises are.
class _Header extends StatelessWidget {
  const _Header({
    required this.page,
    required this.alertsOnly,
    required this.onAlertsOnly,
  });

  final EeUnitTicketsPage page;
  final bool alertsOnly;
  final ValueChanged<bool> onAlertsOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x2,
        AwSpace.x4,
        AwSpace.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: const Key('my-units-live'),
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(
                  'ee.myUnits.live'.tr(),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          if (page.units.isNotEmpty) ...[
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.myUnits.scope'.tr(
                args: {'units': page.units.map((u) => u.unitName).join(', ')},
              ),
              key: const Key('my-units-scope'),
              style: muted,
            ),
          ],
          if (page.breached + page.warned > 0) ...[
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.myUnits.counts'.tr(
                args: {
                  'breached': '${page.breached}',
                  'warned': '${page.warned}',
                },
              ),
              key: const Key('my-units-counts'),
              style: muted,
            ),
          ],
          const SizedBox(height: AwSpace.x2),
          FilterChip(
            key: const Key('my-units-alerts'),
            label: Text('ee.myUnits.alertsOnly'.tr()),
            selected: alertsOnly,
            onSelected: onAlertsOnly,
          ),
        ],
      ),
    );
  }
}

/// One request: which unit, what it is, how late — and one tap to it.
class _Row extends ConsumerWidget {
  const _Row({required this.ticket});

  final EeUnitTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      key: Key('unit-ticket-${ticket.id}'),
      child: ListTile(
        title: Text(
          ticket.number == null
              ? ticket.subject
              : '#${ticket.number} · ${ticket.subject}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AwSpace.x1),
          child: Wrap(
            spacing: AwSpace.x3,
            runSpacing: AwSpace.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ticket.unitName,
                key: Key('unit-ticket-unit-${ticket.id}'),
                style: theme.textTheme.labelMedium,
              ),
              Text(
                'ee.tickets.status.${ticket.status}'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              AwSlaChip.values(
                slaStatus: ticket.slaStatus,
                slaDueAt: ticket.slaDueAt,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openTicketAcrossUnits(context, ref, ticket),
      ),
    );
  }
}

/// A page after the first, and the "more" button under the last one.
class _Page extends ConsumerWidget {
  const _Page({
    required this.pageKey,
    required this.last,
    required this.onMore,
    super.key,
  });

  final EeUnitTicketsKey pageKey;
  final bool last;
  final ValueChanged<String> onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(eeUnitTicketsPageProvider(pageKey));
    return page.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AwSpace.x4),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AwInlineError(message: localizedError(error)),
      data: (page) => Column(
        children: [
          for (final ticket in page.tickets) _Row(ticket: ticket),
          if (last && page.hasMore)
            _MoreButton(onPressed: () => onMore(page.nextCursor!)),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AwSpace.x2),
    child: Center(
      child: OutlinedButton(
        key: const Key('my-units-more'),
        onPressed: onPressed,
        child: Text('ee.myUnits.more'.tr()),
      ),
    ),
  );
}

/// The queue's doorway to the other units' SLA alerts (AW-E19): the most
/// urgent one, one tap from the request, and "see all" to the list.
///
/// Drawn only when there is something to say and the server said it — never
/// from an old answer (the provider is quiet offline). The unit on screen is
/// left out: its alerts are already in the queue below.
class EeOtherUnitsAlertStrip extends ConsumerWidget {
  const EeOtherUnitsAlertStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(eeOtherUnitsAlertsProvider).value;
    if (page == null || page.tickets.isEmpty) return const SizedBox.shrink();
    final top = page.tickets.first;
    final theme = Theme.of(context);
    final breached = top.slaStatus == 'breached';
    final title = page.breached > 0 && page.warned > 0
        ? 'ee.myUnits.stripBoth'.tr(
            args: {'breached': '${page.breached}', 'warned': '${page.warned}'},
          )
        : page.breached > 0
        ? 'ee.myUnits.stripBreached'.tr(args: {'breached': '${page.breached}'})
        : 'ee.myUnits.stripWarned'.tr(args: {'warned': '${page.warned}'});
    return Card(
      key: const Key('other-units-alerts'),
      margin: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: Key('other-units-alert-${top.id}'),
            leading: Icon(
              breached ? Icons.error_outline : Icons.schedule,
              color: breached
                  ? theme.colorScheme.error
                  : context.awTokens.warning,
            ),
            title: Text(title, style: theme.textTheme.labelLarge),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  top.number == null
                      ? '${top.unitName} · ${top.subject}'
                      : '${top.unitName} · #${top.number} ${top.subject}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                AwSlaChip.values(
                  slaStatus: top.slaStatus,
                  slaDueAt: top.slaDueAt,
                ),
              ],
            ),
            onTap: () => openTicketAcrossUnits(context, ref, top),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(
                right: AwSpace.x2,
                bottom: AwSpace.x1,
              ),
              child: TextButton(
                key: const Key('other-units-all'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EeMyUnitsScreen(alertsOnly: true),
                  ),
                ),
                child: Text('ee.myUnits.stripAll'.tr()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
