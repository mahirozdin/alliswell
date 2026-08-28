import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../tickets_providers.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.tickets.queueTitle'.tr()),
        actions: [
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
    return Card(
      key: Key('ticket-${ticket.id}'),
      child: ListTile(
        leading: _PriorityMark(priority: ticket.priority, muted: finished),
        title: Text(
          ticket.subject,
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
        subtitle: Text(
          [
            'ee.tickets.status.${ticket.status}'.tr(),
            'ee.tickets.priority.${ticket.priority}'.tr(),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
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
