import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import '../ticket_links_providers.dart';
import '../tickets_providers.dart';
import 'history_tab.dart';
import 'sla_chip.dart';

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
        // EE-167: the number above the subject rather than inside it. On the
        // detail screen there is room for a line, and the thing somebody reads
        // out on the phone should not be competing with a sentence for it.
        if (ticket.number != null)
          Text(
            '#${ticket.number}',
            key: const Key('ticket-number'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
        // EE-097: the countdown, under the chips and above the request itself.
        // An agent deciding what to pick up next reads it before the body.
        AwSlaCountdown(ticket: ticket),
        if (ticket.body != null && ticket.body!.isNotEmpty) ...[
          const SizedBox(height: AwSpace.x4),
          Text(ticket.body!, style: theme.textTheme.bodyMedium),
        ],
        // EE-189/EE-190: what this request has to do with anything else, and
        // what came out of it. Below the request and ABOVE the conversation,
        // because an agent picking this up asks "is this the known one, and
        // has somebody already started" before reading forty replies.
        _Relations(ticketId: ticket.id),
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

/// EE-189 + EE-190 — the problem, the work, and the way back.
///
/// Three things a request carries that its own row cannot: the problem that
/// explains it (with the WORKAROUND, the one sentence an agent can act on
/// while the fix is built), the work it caused, and — when it has come up
/// again — the way to open a new one instead of reopening this.
class _Relations extends ConsumerWidget {
  const _Relations({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relations = ref.watch(eeTicketRelationsProvider(ticketId));

    return relations.when(
      // Quiet on both: this section is an ADDITION to a screen that already
      // works. A spinner or a red box here would make a slow network look
      // like a broken request.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        final canConvert = ref.watch(canProvider('tickets.convert'));
        final canCreate = ref.watch(canProvider('tickets.create'));
        final titles =
            ref.watch(eeLinkedTaskTitlesProvider(data.taskIds)).value ??
            const {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.waitingReason != null) ...[
              const SizedBox(height: AwSpace.x4),
              _Chip(
                label:
                    '${'ee.tickets.waitingReason'.tr()}: '
                    '${'ee.sla.reason.${data.waitingReason}'.tr()}',
              ),
            ],
            for (final problem in data.problems) ...[
              const SizedBox(height: AwSpace.x4),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(problem.title, style: theme.textTheme.titleSmall),
                      if (problem.hasUsableWorkaround) ...[
                        const SizedBox(height: AwSpace.x2),
                        // The reason this card exists. Full text, never
                        // truncated: a workaround cut in half is a wrong one.
                        Text(
                          problem.workaround!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (data.assets.isNotEmpty) ...[
              const SizedBox(height: AwSpace.x6),
              Text(
                'ee.tickets.affectedAssets'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AwSpace.x2),
              // Shown only when there is one. An empty "affected equipment"
              // heading on every request would teach agents to scroll past
              // this section, and the section is the whole point on the day a
              // machine is involved.
              for (final asset in data.assets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.precision_manufacturing_outlined),
                  // Tag first: it is painted on the machine, and it is what a
                  // technician reads out on the phone.
                  title: Text('${asset.tag} · ${asset.name}'),
                  subtitle: Text(
                    [
                      'ee.assets.status.${asset.status}'.tr(),
                      if (asset.location != null) asset.location!,
                    ].join(' · '),
                  ),
                ),
            ],
            const SizedBox(height: AwSpace.x6),
            Text(
              'ee.tickets.linkedTasks'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x2),
            if (data.taskIds.isEmpty)
              Text(
                'ee.tickets.linkedTasksEmpty'.tr(),
                style: theme.textTheme.bodySmall,
              )
            else
              // A LIST, which is the whole of GAP §3.11: the data model always
              // allowed several (`ee_ticket_task_links` is unique on the task,
              // not on the ticket) and the screen showed one.
              for (final id in data.taskIds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  // A task the device has not pulled yet is still a task: the
                  // id is shown rather than the row hidden, because a missing
                  // line reads as "no work was done".
                  title: Text(titles[id] ?? id),
                ),
            Wrap(
              spacing: AwSpace.x2,
              children: [
                if (canConvert)
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(eeTicketLinksApiProvider)
                          .convertToTask(ticketId);
                      ref.invalidate(eeTicketRelationsProvider(ticketId));
                    },
                    icon: const Icon(Icons.add),
                    label: Text('ee.tickets.openAnotherTask'.tr()),
                  ),
                if (canCreate)
                  TextButton.icon(
                    onPressed: () => _askAgain(context, ref),
                    icon: const Icon(Icons.replay),
                    label: Text('ee.tickets.relatedAction'.tr()),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// EE-190 — and the dialog says what it is about to do.
  ///
  /// "This has come up again" is a button an agent presses expecting a reopen,
  /// because that is what every other tool does. So the sentence explaining
  /// that a NEW request is opened is in the dialog rather than in a doc
  /// nobody reads — the surprise is cheaper here than afterwards.
  Future<void> _askAgain(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.tickets.relatedAction'.tr()),
        content: Text('ee.tickets.relatedHint'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(eeTicketLinksApiProvider).openRelated(ticketId);
    ref.invalidate(eeTicketRelationsProvider(ticketId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('ee.tickets.relatedOpened'.tr())));
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
