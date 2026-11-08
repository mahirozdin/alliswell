import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fabs.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../assignments_providers.dart' show Assignee;
import '../providers.dart';
import '../ticket_bulk_providers.dart';
import '../ticket_tags_providers.dart';
import '../tickets_providers.dart';
import 'assignee_avatars.dart';
import 'desk_paths.dart';
import 'my_units_screen.dart';
import 'performance_screen.dart';
import 'sla_dashboard_screen.dart';
import 'ticket_bulk.dart';
import 'sla_chip.dart';
import 'ticket_archive_screen.dart';
import 'ticket_detail_screen.dart';
import '../../../widgets/route_leading.dart';
import 'unit_scope.dart';
import 'csv_download.dart';
import 'figure_scope.dart';
import '../unit_scope_providers.dart';
import '../../workspaces/ui/workspace_switcher.dart';
import '../../workspaces/workspaces.dart';
import '../../../widgets/segment_label.dart';
import '../../../widgets/list_detail.dart';
import '../../../theme/typography.dart';

/// The unit's inbox (EE-084, madde 4/10).
///
/// Drawn entirely from the replica, which is the product's distinctive claim
/// made visible: this list opens with no signal, on a shop floor, and the
/// agent works it there. Nothing on this screen waits for a request.
///
/// Two presentation decisions the code below exists to keep:
///
///   • FINISHED WORK SINKS, it does not disappear. A closed ticket is still
///     the record of what happened and the thing somebody searches for an hour
///     later; hiding it behind a filter would make the default view lie about
///     the desk's own history.
///   • PRIORITY IS A WORD, not only a colour. An urgent row carries its label,
///     because a colour alone fails for the ~8% of men who cannot separate red
///     from green — and because a screenshot of a queue has to survive being
///     printed in black and white, which is what a factory does with it.
class EeTicketQueueScreen extends ConsumerWidget {
  const EeTicketQueueScreen({super.key});

  /// OPH-409: the SLA board and the workload report were two entries in the
  /// ⋮ menu that nobody found; they are tabs of the requests header now, next
  /// to the queue they are about. Their addresses stay for links.
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 3,
    child: Builder(
      builder: (context) {
        final tabs = DefaultTabController.of(context);
        return ListenableBuilder(
          listenable: tabs,
          builder: (context, _) => tabs.index == 0
              ? _queue(context, ref)
              : Scaffold(
                  appBar: AppBar(
                    leading: awRouteLeading(context),
                    title: Text('ee.tickets.queueTitle'.tr()),
                    bottom: const _QueueTabs(),
                  ),
                  body: tabs.index == 1
                      ? const EeSlaDashboardScreen(embedded: true)
                      : const EePerformanceScreen(embedded: true),
                ),
        );
      },
    ),
  );

  Widget _queue(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(filteredTicketsProvider);
    // U-18: every unit's open requests, live, until a unit is chosen.
    final allUnits = ref.watch(eeQueueShowsAllUnitsProvider);
    final filter = ref.watch(ticketFilterProvider);
    final query = ref.watch(ticketSearchQueryProvider).trim();
    final searching = query.isNotEmpty;
    // EE-227: a long press starts a selection; while one is open the bar is
    // the batch's, and "new request" steps aside.
    final selecting = ref.watch(
      ticketSelectionProvider.select((ids) => ids.isNotEmpty),
    );

    // OPH-410 (DESIGN §51 D2): from the desktop width a request opens in a
    // pane beside the list — the queue and the across-units list alike —
    // and the list keeps its place. Below it the detail is pushed as before.
    return AwListDetailScope(
      kind: kEeTicketPane,
      child: AwListDetailPane(
        kind: kEeTicketPane,
        detailBuilder: (context, id, close) =>
            EeTicketDetailScreen(ticketId: id),
        child: _queueScaffold(
          context,
          ref,
          tickets: tickets,
          allUnits: allUnits,
          filter: filter,
          query: query,
          searching: searching,
          selecting: selecting,
        ),
      ),
    );
  }

  Widget _queueScaffold(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<TicketRecord>> tickets,
    required bool allUnits,
    required TicketFilter filter,
    required String query,
    required bool searching,
    required bool selecting,
  }) {
    return Scaffold(
      // EE-225: the way in to filing one, where the desk already stands.
      // Hidden without `tickets.create` (EE-052's cache): a button that
      // leads to a form the door refuses is a dead one with extra steps.
      floatingActionButton:
          !selecting && ref.watch(canProvider('tickets.create'))
          ? AwExtendedFab(
              key: const Key('ticket-new'),
              onPressed: () => context.push('/tickets/new'),
              icon: const Icon(Icons.add),
              label: Text('ee.tickets.new.fab'.tr()),
            )
          : null,
      appBar: selecting
          ? EeBulkAppBar(visible: tickets.value ?? const [])
          : AppBar(
              leading: awRouteLeading(context),
              title: EeUnitScopedTitle(
                title: 'ee.tickets.queueTitle'.tr(),
                allUnits: allUnits,
              ),
              bottom: const _QueueTabs(),
              actions: [
                // EE-169. The house search shape (DESIGN §12 S1, round 13 #5): an
                // icon until somebody wants it. It reads the REPLICA, so it answers
                // with no signal — which is the whole reason the queue is a replica
                // query and not a request.
                // OPH-359 (UI-AUDIT #29): change unit where the queue is.
                const AwWorkspaceSwitcher(),
                AwSearchAction(
                  fieldKey: const Key('ticket-search'),
                  hintText: 'ee.tickets.searchHint'.tr(),
                  onQuery: (q) =>
                      ref.read(ticketSearchQueryProvider.notifier).set(q),
                ),
                // EE-098. Reachability (DESIGN §22): a dashboard nothing opens is
                // not a feature, and the queue is where the person who wants it is
                // already standing. No permission gate — counting is membership
                // (ADR-0007 §1), and the endpoint scopes itself to the caller's own
                // desks, so everyone sees a true screen rather than a forbidden one.
                // EE-196 — AND A MEASURED CORRECTION TO THIS BAR.
                //
                // The knowledge base belongs on the queue for EE-098's reason,
                // repeated: the person who wants a written answer is the one
                // already looking at requests, and a screen nothing opens is not a
                // feature. But adding a fourth action OVERFLOWED the toolbar by
                // 3.6 pixels at 390 logical width — measured, by the filter test,
                // not predicted. The title takes the rest of the row, which is the
                // part an action count alone does not tell you.
                //
                // So the two destinations share one overflow button. That makes the
                // bar SMALLER than it was, leaves headroom for the next one, and
                // trades two icons nobody can name for two menu entries that say
                // what they are.
                PopupMenuButton<String>(
                  key: const Key('ticket-more'),
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'ee.tickets.more'.tr(),
                  // The two destinations are reached differently, and that is not
                  // untidiness: the knowledge base has real ROUTES because an
                  // article is a thing you link to, while the SLA dashboard is a
                  // pushed screen with no address of its own (EE-098 never gave it
                  // one, and inventing one here would be a second way to reach it).
                  onSelected: (value) {
                    // OPH-360 (UI-AUDIT #56): the export the server had all
                    // along. The queue's own filters travel where the door
                    // can take them (one value per field), scoped to the
                    // unit on screen.
                    if (value == 'csv') {
                      // E35 polish P-10: the file is the list on screen.
                      // Across units that is every unit the person works in
                      // (no unitId: the server scopes to the caller's own
                      // units) and none of the unit's chips, which this view
                      // hides and does not apply.
                      if (ref.read(eeQueueShowsAllUnitsProvider)) {
                        eeDownloadCsv(context, ref, (api) => api.tickets());
                        return;
                      }
                      eeDownloadCsv(context, ref, (api) {
                        String? one(Set<String> values) =>
                            values.length == 1 ? values.first : null;
                        return api.tickets(
                          status: one(filter.statuses),
                          priority: one(filter.priorities),
                          source: one(filter.sources),
                          slaStatus: one(filter.slaStatuses),
                          serviceId: filter.serviceId,
                          unitId: ref.read(eeUnitHereProvider).unit?.unitId,
                        );
                      });
                      return;
                    }
                    // EE-220 adds `/assets` beside `/kb` for the same reason and by
                    // the same means: both are real ROUTES because both are things
                    // you link to (a QR code on a machine opens an asset).
                    // EE-269 puts `/changes` on the same shelf, a real route for
                    // the same reason: an approval notification and a request's
                    // relations both link to one change.
                    if (value == '/kb' ||
                        value == '/assets' ||
                        value == '/changes' ||
                        value == '/problems') {
                      context.push(value);
                      return;
                    }
                    // EE-267: "Birimlerim" sits on the same shelf. OPH-359
                    // (UI-AUDIT #59) gave it an address, so it opens the
                    // way the rest of the shelf does and a reload or a link
                    // lands on it. (The SLA board and the workload report
                    // are the header's tabs since OPH-409.)
                    if (GoRouter.maybeOf(context) != null) {
                      context.push(kAwMyUnitsPath);
                      return;
                    }
                    // Hosted without a router (one screen under test).
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EeMyUnitsScreen(),
                      ),
                    );
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const Key('ticket-kb'),
                      value: '/kb',
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_outlined),
                          const SizedBox(width: AwSpace.x2),
                          // A label may be longer than the menu in another
                          // language: it shortens, the row does not overflow.
                          Flexible(
                            child: Text(
                              'ee.kb.title'.tr(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EE-220. THE REGISTER HAD NO DOOR — measured, not assumed:
                    // `/assets` was a route with no `context.push('/assets')`
                    // anywhere in the app, so the only way in was scanning a QR
                    // code, which opens a DETAIL. A list nobody can reach is a list
                    // nobody searches, which is half of why `searchAssets` had no
                    // caller. It goes on this shelf because EE-196 put the
                    // knowledge base here on EE-098's reasoning: the person who
                    // wants it is already looking at the queue.
                    PopupMenuItem(
                      key: const Key('ticket-assets'),
                      value: '/assets',
                      child: Row(
                        children: [
                          const Icon(Icons.precision_manufacturing_outlined),
                          const SizedBox(width: AwSpace.x2),
                          Flexible(
                            child: Text(
                              'ee.assets.title'.tr(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EE-269 (AW-E09): planned work — the list is the device's
                    // copy, the same shelf as the register because the same
                    // person asks "is anything going out on Hat 3 tonight?".
                    // No gate: every desk member reads changes (EE-186); what
                    // the verbs guard is raising, signing and moving them.
                    PopupMenuItem(
                      key: const Key('ticket-changes'),
                      value: '/changes',
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_outlined),
                          const SizedBox(width: AwSpace.x2),
                          Flexible(
                            child: Text(
                              'ee.changes.title'.tr(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EE-270: known faults beside planned work. The same
                    // shelf, because the same person asks "is this that thing
                    // again, and what do we tell them until it is fixed?".
                    PopupMenuItem(
                      key: const Key('ticket-problems'),
                      value: '/problems',
                      child: Row(
                        children: [
                          const Icon(Icons.bug_report_outlined),
                          const SizedBox(width: AwSpace.x2),
                          Flexible(
                            child: Text(
                              'ee.problems.title'.tr(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EE-098: no permission gate — counting is membership
                    // (ADR-0007 §1), and the endpoint scopes itself to the caller's
                    // own desks, so everyone sees a true screen rather than a
                    // forbidden one.
                    // EE-267 (AW-E19): a manager of several units sees them
                    // all here — live, since the device holds one. No gate:
                    // the list is the caller's own units, so everyone gets a
                    // true screen (one unit is a short list, none an empty one).
                    PopupMenuItem(
                      key: const Key('ticket-my-units'),
                      value: 'units',
                      child: Row(
                        children: [
                          const Icon(Icons.hub_outlined),
                          const SizedBox(width: AwSpace.x2),
                          Flexible(
                            child: Text(
                              'ee.myUnits.title'.tr(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // EE-205: no permission gate here either, for EE-098's reason —
                    // counting is membership (ADR-0007 §1) and the endpoint scopes
                    // itself to the caller's own desks, so everybody sees a TRUE
                    // screen rather than a forbidden one. A manager with
                    // `units.manage` sees the team; everyone else sees their own.
                    // OPH-360 (UI-AUDIT #56): taking the data out is
                    // `tickets.export`, so the entry exists on a yes only.
                    if (ref.read(canProvider('tickets.export')))
                      PopupMenuItem(
                        key: const Key('ticket-csv'),
                        value: 'csv',
                        child: Row(
                          children: [
                            const Icon(Icons.download_outlined),
                            const SizedBox(width: AwSpace.x2),
                            Flexible(
                              child: Text(
                                'ee.csv.download'.tr(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (!filter.isEmpty && !allUnits)
                  TextButton(
                    key: const Key('ticket-filter-clear'),
                    onPressed: () =>
                        ref.read(ticketFilterProvider.notifier).clear(),
                    child: Text('ee.tickets.filterClear'.tr()),
                  ),
              ],
            ),
      body: Column(
        children: [
          if (selecting) const EeBulkBlockedNote(),
          // EE-267 (AW-E19): the other units' SLA alerts, live — the one
          // thing on this screen that is not the replica, and it says so by
          // leading to "Birimlerim". Out of the way while a batch is open.
          // U-18: "All units" first, then each unit — the scope is a filter
          // on this screen, not a place somewhere else.
          if (!selecting) const _UnitScopeBar(),
          if (!selecting && !allUnits) const EeOtherUnitsAlertStrip(),
          // The chips filter the unit's replica; across units they would
          // filter nothing, so they wait for a unit (U-18).
          if (!allUnits) const _FilterBar(),
          // The toolbar's search reaches this list too (E35 G-D review r1).
          if (allUnits)
            Expanded(
              child: EeMyUnitsScreen(
                embedded: true,
                query: query,
                onSearchArchive: (q) => _openArchive(context, q),
                // Home's "unassigned" figure opens here (E35 G-D review r1).
                unassignedOnly:
                    filter.assigneeScope == TicketAssigneeScope.unassigned,
                onUnassignedOnly: (on) => ref
                    .read(ticketFilterProvider.notifier)
                    .setAssignee(
                      on
                          ? TicketAssigneeScope.unassigned
                          : TicketAssigneeScope.any,
                    ),
              ),
            )
          else
            Expanded(
              child: EeUnitScopeGate(
                child: tickets.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => AwErrorState(
                    message: localizedError(error),
                    onRetry: () => ref.invalidate(ticketQueueProvider),
                  ),
                  data: (rows) {
                    final dense = eeDenseTicketRows(context);
                    if (rows.isEmpty) {
                      // Two different emptinesses, and telling them apart is the
                      // whole value of the state: "nothing came in" is good news,
                      // "your filters exclude everything" is a mistake somebody is
                      // one tap from fixing.
                      // EE-169 adds a THIRD emptiness, and it is the one that
                      // would otherwise lie: a search finds nothing here when the
                      // request is on the server but no longer on the device
                      // (EE-091 sweeps finished work off it). "No results" would
                      // read as "no such request", so the state says where the
                      // rest of them are (ADR-0016 D16.3 wrote this bill down;
                      // this is where it is paid).
                      //
                      // EE-266 pays the rest of it: the sentence used to send the
                      // person to an archive the app could not open. Now the
                      // same words open it, with the query they typed.
                      if (searching) {
                        return AwEmptyState(
                          key: const Key('ticket-search-empty'),
                          icon: Icons.search_off_outlined,
                          title: 'ee.tickets.searchEmptyTitle'.tr(),
                          message: 'ee.tickets.searchEmptyBody'.tr(),
                          action: FilledButton.tonalIcon(
                            key: const Key('ticket-search-archive'),
                            onPressed: () => _openArchive(context, query),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: Text('ee.tickets.archive.searchAction'.tr()),
                          ),
                        );
                      }
                      return filter.isEmpty
                          ? AwEmptyState(
                              icon: Icons.inbox_outlined,
                              title: 'ee.tickets.emptyTitle'.tr(),
                              message: 'ee.tickets.emptyBody'.tr(),
                            )
                          : AwEmptyState(
                              icon: Icons.filter_alt_off_outlined,
                              title: 'ee.tickets.emptyFilteredTitle'.tr(),
                              message: 'ee.tickets.emptyFilteredBody'.tr(),
                            );
                    }
                    // OPH-410: ↑/↓ in the pane walk the rows as drawn.
                    final list = ListView.builder(
                      // Clears the "new request" button (EE-225).
                      padding: awListPadding(
                        context,
                        top: dense ? AwSpace.x2 : AwSpace.x4,
                        fab: true,
                      ),
                      // EE-266: a search that found live requests may still be
                      // missing the one somebody wants — it closed last spring.
                      // The last row asks the archive the same question.
                      itemCount: rows.length + (searching ? 1 : 0),
                      itemBuilder: (_, i) => i < rows.length
                          ? _TicketCard(ticket: rows[i])
                          : ListTile(
                              key: const Key('ticket-search-archive'),
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(
                                'ee.tickets.archive.searchFooter'.tr(
                                  args: {'query': query},
                                ),
                              ),
                              onTap: () => _openArchive(context, query),
                            ),
                    );
                    final ordered = AwListOrder(
                      ids: [for (final row in rows) row.id],
                      child: list,
                    );
                    if (!dense) return ordered;
                    // The dense table's column names, over the rows they
                    // name (OPH-410, a desk at a desktop scans columns).
                    return Column(
                      children: [
                        const _DenseHeader(),
                        Expanded(child: ordered),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Status and priority as chips; the service as a menu when there is a choice.
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  /// The states worth filtering by, not all seven: `new` and `triage` are the
  /// two an agent picks work from, `waiting` is the one that hides forgotten
  /// work, and "finished" folds `resolved`/`closed`/`cancelled` because
  /// nobody's queue question distinguishes them.
  static const _statusGroups = {
    'new': ['new'],
    'in_progress': ['triage', 'in_progress'],
    'waiting': ['waiting'],
    'done': ['resolved', 'closed', 'cancelled'],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(ticketFilterProvider);
    final notifier = ref.read(ticketFilterProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x4,
        vertical: AwSpace.x2,
      ),
      child: Row(
        children: [
          for (final entry in _statusGroups.entries) ...[
            FilterChip(
              key: Key('ticket-filter-${entry.key}'),
              label: Text('ee.tickets.filter.${entry.key}'.tr()),
              selected: entry.value.every(filter.statuses.contains),
              onSelected: (_) {
                for (final status in entry.value) {
                  notifier.toggleStatus(status);
                }
              },
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          for (final priority in ['urgent', 'high']) ...[
            FilterChip(
              key: Key('ticket-filter-$priority'),
              label: Text('ee.tickets.priority.$priority'.tr()),
              selected: filter.priorities.contains(priority),
              onSelected: (_) => notifier.togglePriority(priority),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          // EE-171. The two questions a desk actually asks, as chips rather
          // than a menu: "what is on me" and — the expensive one — "what is on
          // nobody". A queue's costliest state is work nobody has picked up,
          // and it is invisible until something asks for it.
          for (final scope in [
            TicketAssigneeScope.mine,
            TicketAssigneeScope.unassigned,
          ]) ...[
            FilterChip(
              key: Key('ticket-filter-${scope.name}'),
              label: Text('ee.tickets.filter.${scope.name}'.tr()),
              selected: filter.assigneeScope == scope,
              // Selecting the one already on turns it OFF: these two are
              // mutually exclusive and a chip that cannot be unpicked is a
              // filter the person has to leave the screen to clear.
              onSelected: (_) => notifier.setAssignee(
                filter.assigneeScope == scope ? TicketAssigneeScope.any : scope,
              ),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          // The SLA badge, as the compliance question a manager asks: which
          // promises are already broken, and which are about to be.
          for (final sla in ['breached', 'warned']) ...[
            FilterChip(
              key: Key('ticket-filter-sla-$sla'),
              label: Text(
                'ee.tickets.filter.sla${sla[0].toUpperCase()}${sla.substring(1)}'
                    .tr(),
              ),
              selected: filter.slaStatuses.contains(sla),
              onSelected: (_) => notifier.toggleSlaStatus(sla),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          // EE-268 (AW-E21): the kind of work. "Only incidents" is the
          // question a shift asks when something is down, and it is answered
          // from the replica like every chip here — with no signal.
          for (final type in ['incident', 'request']) ...[
            FilterChip(
              key: Key('ticket-filter-type-$type'),
              label: Text('ee.tickets.filter.processType.$type'.tr()),
              selected: filter.processTypes.contains(type),
              onSelected: (_) => notifier.toggleProcessType(type),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          // EE-235: one of the desk's words. Its choices are the words on this
          // desk's own rows (the replica's `tag_names`, OPH-350), so it works
          // with no signal; shown only once there is a word to pick — a chip
          // that opens an empty list is a question with no answers.
          if (filter.tag != null ||
              ref.watch(queueTagNamesProvider).isNotEmpty) ...[
            FilterChip(
              key: const Key('ticket-filter-tag'),
              label: Text(
                filter.tag == null
                    ? 'ee.tickets.filter.tag'.tr()
                    : 'ee.tickets.filter.tagSet'.tr(args: {'tag': filter.tag!}),
              ),
              selected: filter.tag != null,
              onSelected: (_) async {
                if (filter.tag != null) {
                  notifier.setTag(null);
                  return;
                }
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) =>
                      _TagPicker(tags: ref.read(queueTagNamesProvider)),
                );
                if (picked != null) notifier.setTag(picked);
              },
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          const SizedBox(width: AwSpace.x2),
          // EE-171: filed between two days. A chip rather than two fields,
          // because the question is always a RANGE — "this week", "since the
          // shutdown" — and a half-applied one would empty the list under the
          // person's hands while they were still answering it.
          FilterChip(
            key: const Key('ticket-filter-dates'),
            label: Text(
              filter.from == null && filter.to == null
                  ? 'ee.tickets.filter.dates'.tr()
                  : 'ee.tickets.filter.datesSet'.tr(),
            ),
            selected: filter.from != null || filter.to != null,
            onSelected: (_) async {
              if (filter.from != null || filter.to != null) {
                notifier.setRange(null, null);
                return;
              }
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1),
              );
              if (picked == null) return;
              // The END of the chosen day, not its midnight: somebody who
              // picks "today" means everything filed today, and a bare date
              // would exclude every request after 00:00.
              notifier.setRange(
                picked.start,
                DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day,
                  23,
                  59,
                  59,
                ),
              );
            },
          ),
          const SizedBox(width: AwSpace.x2),
          // Where it came from. `public` is the one worth a chip of its own:
          // a stranger waiting on an answer is a different kind of queue.
          for (final source in ['public', 'health']) ...[
            FilterChip(
              key: Key('ticket-filter-source-$source'),
              label: Text(
                'ee.tickets.filter.source${source[0].toUpperCase()}${source.substring(1)}'
                    .tr(),
              ),
              selected: filter.sources.contains(source),
              onSelected: (_) => notifier.toggleSource(source),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
        ],
      ),
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final finished = ticket.terminalAt != null;
    // `select` so one ticket gaining an assignee does not rebuild every other
    // row in the queue — the same idiom the task list uses.
    final assignees = ref.watch(
      ticketAssigneesProvider.select(
        (value) => value.value?[ticket.id] ?? const <Assignee>[],
      ),
    );
    // EE-227. `select`s again: ticking one row must not rebuild the queue.
    final selecting = ref.watch(
      ticketSelectionProvider.select((ids) => ids.isNotEmpty),
    );
    final selected = ref.watch(
      ticketSelectionProvider.select((ids) => ids.contains(ticket.id)),
    );
    void toggle() =>
        ref.read(ticketSelectionProvider.notifier).toggle(ticket.id);
    // EE-258: who asked, when the device knows — an account's name from the
    // rosters (one map, `select`ed, so a queue opens no stream per row), or
    // the name kept for somebody without one. Nothing when nobody asked.
    final requesterId = ticket.requesterId;
    final askedBy = requesterId == null
        ? ticket.requesterName
        : ref.watch(
            eeMemberNamesProvider.select((names) => names.value?[requesterId]),
          );
    // OPH-410: the row whose request the desktop pane shows is outlined and
    // says so to a screen reader (DESIGN §51 D2); its context lets ↑/↓
    // scroll it into view.
    final pane = AwListDetailScope.maybeOf(context, kEeTicketPane);
    final inPane = pane != null && pane.selectedId == ticket.id;
    AwListOrder.registerRow(context, ticket.id);
    final assigneeNames = [
      for (final a in assignees)
        a.isKnown
            ? (a.displayName ?? a.initials ?? '?')
            : 'ee.assign.formerMember'.tr(),
    ];
    final leading = selecting
        ? Checkbox(
            key: Key('ticket-select-${ticket.id}'),
            value: selected,
            onChanged: (_) => toggle(),
            // OPH-359 (UI-AUDIT #64): a box a screen reader can name.
            semanticLabel: 'ee.tickets.selectRow'.tr(
              args: {
                'ticket': ticket.number == null
                    ? ticket.subject
                    : '#${ticket.number} ${ticket.subject}',
              },
            ),
          )
        : _PriorityMark(priority: ticket.priority, muted: finished);
    final shape = inPane
        ? RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
            side: BorderSide(color: theme.colorScheme.primary, width: 2),
          )
        : null;
    void open() => awOpenTicket(context, ticket.id);
    if (eeDenseTicketRows(context)) {
      return Padding(
        padding: kAwListRowPadding,
        child: Card(
          key: Key('ticket-${ticket.id}'),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          // Inside the card: the card is the row's one semantics node.
          child: Semantics(
            selected: inPane ? true : null,
            child: InkWell(
              onTap: selecting ? toggle : open,
              onLongPress: toggle,
              child: _DenseRow(
                rowKey: ticket.id,
                leading: leading,
                number: ticket.number,
                subject: ticket.subject,
                status: [
                  'ee.tickets.status.${ticket.status}'.tr(),
                  'ee.tickets.priority.${ticket.priority}'.tr(),
                ].join(' · '),
                people: EeTicketPeopleLine(
                  rowKey: ticket.id,
                  requester: askedBy,
                  assignees: assigneeNames,
                  muted: finished,
                  maxLines: 1,
                  warning: context.awTokens.warning,
                ),
                sla: AwSlaChip(ticket: ticket, muted: finished),
                muted: finished,
              ),
            ),
          ),
        ),
      );
    }
    // DESIGN §4's rhythm: without it the cards sat border on border (the
    // theme's card margin is zero on purpose). The key stays on the CARD, so
    // what a test measures is the card, not the space around it.
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: Key('ticket-${ticket.id}'),
        shape: shape,
        child: Semantics(
          selected: inPane ? true : null,
          child: ListTile(
            // While selecting, the box takes the dot's place: the priority is
            // still a WORD on the status line below, so nothing is lost.
            leading: leading,
            title: Text(
              // EE-167: the number leads, because it is what the person on the
              // phone says. Nullable while a request pulled before the numbering
              // has not been touched again — a bare subject is the honest shape
              // then, not a `#null`.
              ticket.number == null
                  ? ticket.subject
                  : '#${ticket.number} · ${ticket.subject}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: finished
                  // Muted, never struck through: the work happened, it is simply
                  // not waiting for anybody (the units screen settled this shape).
                  ? theme.textTheme.titleMedium?.copyWith(
                      color: theme.disabledColor,
                    )
                  : null,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // EE-097: the due chip sits with the status line rather than on a
                // row of its own — a queue is scanned vertically, and a fourth
                // line per card would cost the screen about three tickets.
                // `Wrap` because Turkish labels are longer and a narrow phone must
                // fold rather than clip.
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [
                        'ee.tickets.status.${ticket.status}'.tr(),
                        'ee.tickets.priority.${ticket.priority}'.tr(),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    AwSlaChip(ticket: ticket, muted: finished),
                  ],
                ),
                // OPH-409 (U-19): "whose is it" in words — who asked and who
                // has it, and a marked "nobody yet": the question a manager
                // opens the queue to answer. Before, only the asker was named
                // and the avatars below were initials nobody could read.
                EeTicketPeopleLine(
                  rowKey: ticket.id,
                  requester: askedBy,
                  assignees: assigneeNames,
                  muted: finished,
                  warning: context.awTokens.warning,
                ),
                // Item 9's avatars, on the ticket card. Empty when nobody is on it
                // — the widget draws nothing rather than a placeholder, because
                // "unassigned" is a real and common state of a queue.
                AwAssigneeStrip(assignees: assignees),
              ],
            ),
            onTap: selecting ? toggle : open,
            onLongPress: toggle,
          ),
        ),
      ),
    );
  }
}

/// OPH-410: from the desktop width a request is one line of aligned columns
/// rather than a card — a desk scans twenty of them, not five. The phone and
/// the tablet keep the card.
bool eeDenseTicketRows(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kAwPaneBreakpoint;

/// The dense table's columns, by the width the list has: the subject always,
/// the status from [_kStatusColumnFrom], who asked and who has it from
/// [_kPeopleColumnFrom] — with the pane open the list is narrower, and a
/// column that would squeeze the subject to a word steps aside.
const double _kNumberColumn = 64;
const double _kStatusColumn = 168;
const double _kSlaColumn = 168;
const double _kStatusColumnFrom = 640;
const double _kPeopleColumnFrom = 880;
const double _kDenseRowHeight = 56;

class _DenseHeader extends StatelessWidget {
  const _DenseHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Text label(String key) => Text(
      key.tr(),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      key: const Key('ticket-dense-header'),
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x3, AwSpace.x4, 0),
      child: _DenseColumns(
        leading: const SizedBox.shrink(),
        number: const SizedBox.shrink(),
        subject: label('ee.tickets.columns.subject'),
        status: label('ee.tickets.columns.status'),
        people: label('ee.tickets.columns.people'),
        sla: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: label('ee.tickets.columns.sla'),
        ),
      ),
    );
  }
}

class _DenseRow extends StatelessWidget {
  const _DenseRow({
    required this.rowKey,
    required this.leading,
    required this.number,
    required this.subject,
    required this.status,
    required this.people,
    required this.sla,
    required this.muted,
  });

  final String rowKey;
  final Widget leading;
  final int? number;
  final String subject;
  final String status;
  final Widget people;
  final Widget sla;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kDenseRowHeight),
      child: _DenseColumns(
        leading: leading,
        number: Text(
          number == null ? '' : '#$number',
          key: Key('ticket-dense-number-$rowKey'),
          maxLines: 1,
          style: awTabular(theme.textTheme.labelLarge!.copyWith(color: quiet)),
        ),
        subject: Text(
          subject,
          key: Key('ticket-dense-subject-$rowKey'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Muted, never struck through — the card's rule.
          style: theme.textTheme.titleSmall?.copyWith(
            color: muted ? theme.disabledColor : null,
          ),
        ),
        status: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        people: people,
        sla: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: sla,
          ),
        ),
      ),
    );
  }
}

/// One layout for the header and every row, so the columns line up.
class _DenseColumns extends StatelessWidget {
  const _DenseColumns({
    required this.leading,
    required this.number,
    required this.subject,
    required this.status,
    required this.people,
    required this.sla,
  });

  final Widget leading;
  final Widget number;
  final Widget subject;
  final Widget status;
  final Widget people;
  final Widget sla;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: AwSpace.x4),
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: leading)),
            SizedBox(width: _kNumberColumn, child: number),
            Expanded(flex: 3, child: subject),
            const SizedBox(width: AwSpace.x3),
            if (width >= _kStatusColumnFrom) ...[
              SizedBox(width: _kStatusColumn, child: status),
              const SizedBox(width: AwSpace.x3),
            ],
            if (width >= _kPeopleColumnFrom) ...[
              Expanded(flex: 2, child: people),
              const SizedBox(width: AwSpace.x3),
            ],
            SizedBox(width: _kSlaColumn, child: sla),
          ],
        ),
      );
    },
  );
}

/// A dot AND a word. The dot is scannable, the word is what survives a
/// black-and-white print-out and a colour-blind reader (DESIGN §7.1's rule
/// read on a list rather than on a banner).
class _PriorityMark extends StatelessWidget {
  const _PriorityMark({required this.priority, required this.muted});

  final String priority;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.awTokens;
    final theme = Theme.of(context);
    final color = switch (priority) {
      'urgent' => theme.colorScheme.error,
      'high' => tokens.warning,
      'low' => theme.disabledColor,
      _ => theme.colorScheme.primary,
    };
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: muted ? theme.disabledColor : color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// EE-266 — the archive, searched with the words the queue was given.
void _openArchive(BuildContext context, String query) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeTicketArchiveSearchScreen(initialQuery: query),
    ),
  );
}

/// EE-235 — the desk's words, one to filter by.
class _TagPicker extends StatelessWidget {
  const _TagPicker({required this.tags});

  final List<String> tags;

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
              'ee.tickets.filter.tagPickTitle'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final name in tags)
            ListTile(
              key: Key('ticket-filter-tag-option-$name'),
              leading: const Icon(Icons.sell_outlined),
              title: Text(name),
              onTap: () => Navigator.of(context).pop(name),
            ),
        ],
      ),
    );
  }
}

/// OPH-409 — the requests header's three tabs: the queue, the SLA board and
/// the workload report.
class _QueueTabs extends StatelessWidget implements PreferredSizeWidget {
  const _QueueTabs();

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) => TabBar(
    key: const Key('ticket-tabs'),
    tabs: [
      Tab(
        key: const Key('ticket-tab-queue'),
        child: AwSegmentLabel('ee.tickets.tabs.queue'.tr()),
      ),
      Tab(
        key: const Key('ticket-tab-sla'),
        child: AwSegmentLabel('ee.tickets.tabs.sla'.tr()),
      ),
      Tab(
        key: const Key('ticket-tab-workload'),
        child: AwSegmentLabel('ee.tickets.tabs.workload'.tr()),
      ),
    ],
  );
}

/// U-18 — "All units" and each of the person's units, as one choice. Drawn
/// only when the units are known: with no answer the queue is what it was.
class _UnitScopeBar extends ConsumerWidget {
  const _UnitScopeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = ref.watch(eeUnitHereProvider);
    if (here.state == EeUnitHereState.unknown || here.units.isEmpty) {
      return const SizedBox.shrink();
    }
    final all = ref.watch(eeQueueShowsAllUnitsProvider);
    final chosen = ref.read(eeQueueAllUnitsChosenProvider.notifier);
    return Semantics(
      container: true,
      label: 'ee.unitScope.chipsLabel'.tr(),
      child: SingleChildScrollView(
        key: const Key('ticket-unit-scope'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          AwSpace.x2,
          AwSpace.x4,
          0,
        ),
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('ticket-unit-all'),
              label: Text('ee.unitScope.all'.tr()),
              selected: all,
              onSelected: (_) => chosen.set(true),
            ),
            for (final unit in here.units) ...[
              const SizedBox(width: AwSpace.x2),
              ChoiceChip(
                key: Key('ticket-unit-${unit.workspaceId}'),
                label: Text(unit.unitName),
                selected: !all && here.unit?.workspaceId == unit.workspaceId,
                onSelected: (_) {
                  chosen.set(false);
                  ref
                      .read(selectedWorkspaceIdProvider.notifier)
                      .select(unit.workspaceId);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
