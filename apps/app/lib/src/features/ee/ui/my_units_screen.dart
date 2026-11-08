import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import 'desk_paths.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/unit_tickets_api.dart';
import '../unit_scope_providers.dart';
import '../unit_tickets_providers.dart';
import 'figure_scope.dart';
import 'sla_chip.dart';
import '../../../widgets/list_detail.dart';
import '../../../widgets/route_leading.dart';
import 'ticket_detail_screen.dart' show awOpenTicket, kEeTicketPane;

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
  // R-15: the unit is LENT for the reading, and the notifier is held rather
  // than `ref` — the row that opened the request may be gone by the time it
  // closes.
  final loan = ref.read(eeLentUnitProvider.notifier);
  final keepAllUnits = ref.read(eeQueueShowsAllUnitsProvider);
  // D-3 (polish 3): the unit goes back on EVERY way out — the request
  // closed, the row gone before it could open (`context` unmounted while
  // the unit was switched: the list rebuilt or was left), or a failure.
  // Only an opened desktop pane keeps it: the pane gives it back when it
  // closes. Before, an unmounted row returned early and Home stayed on the
  // lent unit for good.
  var paneHolds = false;
  try {
    // E35 polish P-08: on a space that is not a unit, "all units" is the
    // queue's default without being chosen — selecting the request's unit
    // below would then turn the list it was opened from into that unit's
    // queue. Opened from the cross-unit list, the cross-unit list stays.
    await loan.lend(ticket.workspaceId, keepAllUnits: keepAllUnits);
    if (!context.mounted) return;
    // In the desktop pane the request closes with the pane (the queue gives
    // the unit back then); a pushed detail closes when this returns.
    final inPane =
        AwListDetailScope.maybeOf(context, kEeTicketPane, listen: false) !=
        null;
    await awOpenTicket(context, ticket.id);
    paneHolds = inPane;
  } finally {
    if (!paneHolds) await loan.giveBack();
  }
}

/// Opens [ticket]'s unit when another one is open: its detail reads the
/// unit's replica, which the sync engine fills for the selected workspace.
/// Lent, like a tap's (R-15): the pane gives it back when it closes.
Future<void> _selectTicketUnit(WidgetRef ref, EeUnitTicket ticket) =>
    ref.read(eeLentUnitProvider.notifier).lend(ticket.workspaceId);

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
  const EeMyUnitsScreen({
    this.alertsOnly = false,
    this.embedded = false,
    this.query = '',
    this.onSearchArchive,
    this.unassignedOnly = false,
    this.onUnassignedOnly,
    super.key,
  });

  /// Opened from the queue's strip: the alerts, not the whole list.
  final bool alertsOnly;

  /// OPH-409 (U-18): the request queue's "all units" view draws this list
  /// under its own bar — no second app bar, and room for its "new request"
  /// button under the last row.
  final bool embedded;

  /// E35 G-D review r1: the queue's search, applied to the rows this list
  /// has loaded (subject or `#number`). Empty means no search.
  final String query;

  /// Where a search goes for the requests that are no longer open — the
  /// queue's archive door. Null draws no such door.
  final ValueChanged<String>? onSearchArchive;

  /// E35 G-D review r1: only requests nobody has taken — Home's
  /// "unassigned" figure counts across the person's units and opens here.
  /// A row whose people the server did not send is left out: "not told" is
  /// not "nobody" (U-19).
  final bool unassignedOnly;

  /// Turns [unassignedOnly] on or off; null draws no chip for it.
  final ValueChanged<bool>? onUnassignedOnly;

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

  String get _query => widget.query.trim();

  bool _keep(EeUnitTicket ticket) {
    if (widget.unassignedOnly) {
      final names = ticket.assigneeNames;
      if (names == null || names.isNotEmpty) return false;
    }
    final q = _query.toLowerCase();
    if (q.isEmpty) return true;
    if (ticket.subject.toLowerCase().contains(q)) return true;
    final number = ticket.number;
    if (number == null) return false;
    final digits = q.startsWith('#') ? q.substring(1) : q;
    return digits.isNotEmpty && '$number'.contains(digits);
  }

  Widget? _archiveFooter() {
    final open = widget.onSearchArchive;
    if (_query.isEmpty || open == null) return null;
    return ListTile(
      key: const Key('ticket-search-archive'),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(
        'ee.tickets.archive.searchFooter'.tr(args: {'query': _query}),
      ),
      onTap: () => open(_query),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = ref.watch(eeUnitTicketsPageProvider(_key('')));
    final body = first.when(
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
      data: (page) => _list(context, page),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.myUnits.title'.tr()),
      ),
      body: body,
    );
  }

  /// Every row drawn, in order: the first page's and each later page's
  /// loaded so far — what ↑/↓ walk in the desktop pane (E35 polish P-09).
  ///
  /// R-11: the whole list reads newest first, like a unit's own queue; the
  /// server's lateness order is what the alerts chip asks for. A later page
  /// joins that order rather than being stacked under the first.
  List<EeUnitTicket> _drawn(List<EeUnitTicket> first) {
    final rows = [
      ...first,
      for (var i = 1; i < _cursors.length; i += 1)
        ...?ref
            .watch(eeUnitTicketsPageProvider(_key(_cursors[i])))
            .value
            ?.tickets
            .where(_keep),
    ];
    return _alertsOnly ? rows : eeNewestFirst(rows);
  }

  Widget _list(BuildContext context, EeUnitTicketsPage page) {
    final visible = page.tickets.where(_keep).toList();
    final searching = _query.isNotEmpty;
    final footer = _archiveFooter();
    final drawn = _drawn(visible);
    // A step lands on a request of another unit as a tap on it would: in
    // that unit, so the pane shows the request rather than a "switch" door.
    return AwListOrder(
      ids: [for (final ticket in drawn) ticket.id],
      onReached: (id) {
        for (final ticket in drawn) {
          if (ticket.id == id) {
            unawaited(_selectTicketUnit(ref, ticket));
            return;
          }
        }
      },
      child: _scrolled(context, page, visible, drawn, searching, footer),
    );
  }

  Widget _scrolled(
    BuildContext context,
    EeUnitTicketsPage page,
    List<EeUnitTicket> visible,
    List<EeUnitTicket> drawn,
    bool searching,
    Widget? footer,
  ) {
    return RefreshIndicator(
      key: const Key('my-units-refresh'),
      onRefresh: _refresh,
      child: ListView(
        padding: awListPadding(context, top: AwSpace.x2, fab: widget.embedded),
        children: [
          _Header(
            page: page,
            alertsOnly: _alertsOnly,
            onAlertsOnly: _setAlertsOnly,
            unassignedOnly: widget.unassignedOnly,
            onUnassignedOnly: widget.onUnassignedOnly,
          ),
          if (page.units.isEmpty)
            AwEmptyState(
              key: const Key('my-units-no-units'),
              icon: Icons.groups_outlined,
              title: 'ee.myUnits.noUnitsTitle'.tr(),
              message: 'ee.myUnits.noUnitsBody'.tr(),
            )
          else if ((searching || widget.unassignedOnly) &&
              visible.isEmpty &&
              _cursors.length == 1) ...[
            if (!searching)
              AwEmptyState(
                key: const Key('my-units-filtered-empty'),
                icon: Icons.filter_alt_off_outlined,
                title: 'ee.tickets.emptyFilteredTitle'.tr(),
                message: 'ee.tickets.emptyFilteredBody'.tr(),
              )
            else
              AwEmptyState(
                key: const Key('my-units-search-empty'),
                icon: Icons.search_off_outlined,
                title: 'ee.tickets.searchEmptyTitle'.tr(),
                message: 'ee.myUnits.searchEmptyBody'.tr(),
                action: widget.onSearchArchive == null
                    ? null
                    : FilledButton.tonalIcon(
                        key: const Key('ticket-search-archive'),
                        onPressed: () => widget.onSearchArchive!(_query),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text('ee.tickets.archive.searchAction'.tr()),
                      ),
              ),
            if (page.hasMore)
              _MoreButton(
                onPressed: () => setState(() => _cursors.add(page.nextCursor!)),
              ),
          ] else if (page.tickets.isEmpty)
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
            for (final ticket in drawn) _Row(ticket: ticket),
            for (var i = 1; i < _cursors.length; i += 1)
              _PageTail(
                key: ValueKey(_key(_cursors[i])),
                pageKey: _key(_cursors[i]),
                last: i == _cursors.length - 1,
                onMore: (cursor) => setState(() => _cursors.add(cursor)),
              ),
            if (_cursors.length == 1 && page.hasMore)
              _MoreButton(
                onPressed: () => setState(() => _cursors.add(page.nextCursor!)),
              ),
            ?footer,
          ],
        ],
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
    this.unassignedOnly = false,
    this.onUnassignedOnly,
  });

  final EeUnitTicketsPage page;
  final bool alertsOnly;
  final ValueChanged<bool> onAlertsOnly;
  final bool unassignedOnly;
  final ValueChanged<bool>? onUnassignedOnly;

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
          // U-20: whose requests the counts are.
          EeFigureScopeLine(scope: page.scope),
          const SizedBox(height: AwSpace.x2),
          Wrap(
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x2,
            children: [
              FilterChip(
                key: const Key('my-units-alerts'),
                label: Text('ee.myUnits.alertsOnly'.tr()),
                selected: alertsOnly,
                onSelected: onAlertsOnly,
              ),
              // Offered where the server counts unassigned requests (it then
              // says who has each one), and always while it is on.
              if (onUnassignedOnly != null &&
                  (unassignedOnly || page.unassigned != null))
                FilterChip(
                  key: const Key('my-units-unassigned'),
                  label: Text('ee.tickets.filter.unassigned'.tr()),
                  selected: unassignedOnly,
                  onSelected: onUnassignedOnly,
                ),
            ],
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
    // ↑/↓ scroll the row they reach into view (E35 polish P-09).
    AwListOrder.registerRow(context, ticket.id);
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
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
                // U-19: who asked and who has it — when the server says.
                EeTicketPeopleLine(
                  rowKey: ticket.id,
                  requester: ticket.requesterName,
                  assignees: ticket.assigneeNames,
                  warning: context.awTokens.warning,
                ),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openTicketAcrossUnits(context, ref, ticket),
        ),
      ),
    );
  }
}

/// A page after the first, while it loads or when it failed, and the "more"
/// button under the last one. Its rows are drawn with the rest (R-11: one
/// order over every loaded page).
class _PageTail extends ConsumerWidget {
  const _PageTail({
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
      data: (page) => last && page.hasMore
          ? _MoreButton(onPressed: () => onMore(page.nextCursor!))
          : const SizedBox.shrink(),
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
    // P-14 (EE-310): the server names the unit its counts leave out, so the
    // strip's 22 and the SLA board's 24 read as two scopes, not one figure
    // disagreeing. Named when the device knows it; "the unit on screen"
    // otherwise; nothing from an older server.
    final excludedId = page.scope?.excludedWorkspaceId;
    String? excluded;
    if (excludedId != null) {
      final name = ref
          .watch(workspacesProvider)
          .value
          ?.where((w) => w.id == excludedId)
          .firstOrNull
          ?.name;
      excluded = name == null
          ? 'ee.myUnits.stripExcludingHere'.tr()
          : 'ee.myUnits.stripExcluding'.tr(args: {'unit': name});
    }
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
                if (excluded != null)
                  Text(
                    excluded,
                    key: const Key('other-units-excluded'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                // By its address where there is a router (OPH-359).
                onPressed: () => GoRouter.maybeOf(context) != null
                    ? context.push('$kAwMyUnitsPath?alerts=1')
                    : Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const EeMyUnitsScreen(alertsOnly: true),
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
