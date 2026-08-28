import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../tickets_providers.dart';
import 'history_tab.dart';

/// One request: what was asked, what happened, and what was said (EE-084).
///
/// ── Why this one IS a tab, when the task's history is a screen ─────────────
///
/// EE-069 made a task's history a separate SCREEN, and said why: the task
/// detail is a CORE screen, and giving it a tab bar for an EE feature would
/// reshape core for an overlay reason (ADR-0001 §5). That objection does not
/// exist here — this screen belongs to the overlay — so item 10's actual words
/// ("History sekmesinde izlenir") are honoured rather than approximated. The
/// widget rendering it is EE-026's, unchanged.
///
/// ── The internal note ─────────────────────────────────────────────────────
///
/// An agent who mistakes an internal note for a reply to the customer has said
/// the wrong thing to the wrong person, and no amount of "they should have
/// read carefully" fixes that afterwards. So the distinction is carried three
/// ways at once — a tinted card, a lock icon, and the word — because any one of
/// them alone fails somebody: colour fails a colour-blind reader, the icon
/// fails at a glance on a dirty screen, and the word fails nobody but is the
/// easiest to skim past.
class EeTicketDetailScreen extends ConsumerWidget {
  const EeTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(ticketProvider(ticketId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ee.tickets.detailTitle'.tr()),
          bottom: TabBar(
            tabs: [
              Tab(text: 'ee.tickets.tabThread'.tr()),
              Tab(text: 'ee.tickets.tabHistory'.tr()),
            ],
          ),
        ),
        body: ticket.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(message: '$error'),
          data: (row) {
            // Not an error: the archive sweep drops terminal tickets from the
            // replica (EE-091), so a link somebody kept can legitimately point
            // at a row this device no longer holds.
            if (row == null) {
              return AwEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'ee.tickets.goneTitle'.tr(),
                message: 'ee.tickets.goneBody'.tr(),
              );
            }
            return TabBarView(
              children: [
                _Thread(ticket: row),
                EeHistoryTab(entityType: 'ee_ticket', entityId: ticketId),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Thread extends ConsumerWidget {
  const _Thread({required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = ref.watch(dateFormatProvider);
    final comments = ref.watch(ticketCommentsProvider(ticket.id));

    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        Text(ticket.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            _Chip(label: 'ee.tickets.status.${ticket.status}'.tr()),
            _Chip(label: 'ee.tickets.priority.${ticket.priority}'.tr()),
            if (ticket.terminalAt != null)
              _Chip(
                label: 'ee.tickets.closedOn'.tr(
                  args: {
                    'date': awFormatDate(
                      ticket.terminalAt!,
                      format: dateFormat,
                    ),
                  },
                ),
              ),
          ],
        ),
        if (ticket.body != null && ticket.body!.isNotEmpty) ...[
          const SizedBox(height: AwSpace.x4),
          Text(ticket.body!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: AwSpace.x6),
        Text('ee.tickets.thread'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        comments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(message: '$error'),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
                  child: Text(
                    'ee.tickets.threadEmpty'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final comment in rows)
                      _CommentCard(comment: comment, dateFormat: dateFormat),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AwSpace.x3,
      vertical: AwSpace.x1,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AwRadius.pill),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment, required this.dateFormat});

  final TicketCommentRecord comment;
  final String dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('ticket-comment-${comment.id}'),
      // The tint is the first of the three signals; the icon and the word
      // below are the other two. One of them is enough for anybody, and
      // together they are enough for everybody. `surfaceContainerHighest` is
      // the theme's own "this is set apart" surface — a hand-mixed amber would
      // be a colour the contrast gate has never measured.
      color: comment.internal
          ? theme.colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comment.internal)
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: AwSpace.x1),
                  Text(
                    'ee.tickets.internalNote'.tr(),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            if (comment.internal) const SizedBox(height: AwSpace.x2),
            Text(comment.body, style: theme.textTheme.bodyMedium),
            if (comment.createdAt != null) ...[
              const SizedBox(height: AwSpace.x1),
              Text(
                awFormatDateTime(comment.createdAt!, format: dateFormat),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
