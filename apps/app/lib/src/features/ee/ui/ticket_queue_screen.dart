import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../assignments_providers.dart' show Assignee;
import '../tickets_providers.dart';
import 'assignee_avatars.dart';
import 'sla_chip.dart';
import 'sla_dashboard_screen.dart';
import 'ticket_detail_screen.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(filteredTicketsProvider);
    final filter = ref.watch(ticketFilterProvider);
    final searching = ref.watch(ticketSearchQueryProvider).trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.tickets.queueTitle'.tr()),
        actions: [
          // EE-169. The house search shape (DESIGN §12 S1, round 13 #5): an
          // icon until somebody wants it. It reads the REPLICA, so it answers
          // with no signal — which is the whole reason the queue is a replica
          // query and not a request.
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
          IconButton(
            key: const Key('ticket-sla-dashboard'),
            tooltip: 'ee.slaDash.title'.tr(),
            icon: const Icon(Icons.query_stats_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EeSlaDashboardScreen(),
              ),
            ),
          ),
          if (!filter.isEmpty)
            TextButton(
              key: const Key('ticket-filter-clear'),
              onPressed: () => ref.read(ticketFilterProvider.notifier).clear(),
              child: Text('ee.tickets.filterClear'.tr()),
            ),
        ],
      ),
      body: Column(
        children: [
          const _FilterBar(),
          Expanded(
            child: tickets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(ticketQueueProvider),
              ),
              data: (rows) {
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
                  if (searching) {
                    return AwEmptyState(
                      key: const Key('ticket-search-empty'),
                      icon: Icons.search_off_outlined,
                      title: 'ee.tickets.searchEmptyTitle'.tr(),
                      message: 'ee.tickets.searchEmptyBody'.tr(),
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
                return ListView.builder(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _TicketCard(ticket: rows[i]),
                );
              },
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
                filter.assigneeScope == scope
                    ? TicketAssigneeScope.any
                    : scope,
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
                'ee.tickets.filter.sla${sla[0].toUpperCase()}${sla.substring(1)}'.tr(),
              ),
              selected: filter.slaStatuses.contains(sla),
              onSelected: (_) => notifier.toggleSlaStatus(sla),
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
    return Card(
      key: Key('ticket-${ticket.id}'),
      child: ListTile(
        leading: _PriorityMark(priority: ticket.priority, muted: finished),
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
            // Item 9's avatars, on the ticket card. Empty when nobody is on it
            // — the widget draws nothing rather than a placeholder, because
            // "unassigned" is a real and common state of a queue.
            AwAssigneeStrip(assignees: assignees),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EeTicketDetailScreen(ticketId: ticket.id),
          ),
        ),
      ),
    );
  }
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
