import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/ticket_archive_api.dart';
import '../requester_ticket_providers.dart';
import '../ticket_archive_providers.dart';
import 'requester_ticket_screen.dart';
import 'ticket_detail_screen.dart' show EeTicketAnswersView;

/// A retry that can change the answer: the reads here do not ask while the
/// app knows it is offline, so the sync engine's pull is the probe — if the
/// server answers it, every read watching the signal asks again by itself.
void _retry(WidgetRef ref, void Function() invalidate) {
  invalidate();
  unawaited(ref.read(syncEngineProvider)?.syncNow());
}

/// EE-266 (AW-E17) — a request this device does not hold, found where it is.
///
/// ── THREE ANSWERS THAT USED TO SHARE ONE SENTENCE ──────────────────────
///
/// "This request is no longer on the device; closed requests are dropped
/// after a while" was drawn for every replica miss. It was true for one case
/// and a lie for two: a request LIVE in another of this person's units (the
/// asset card's history opens those) is not closed, and a link to a request
/// that is not this person's is not "dropped". Now each says what it is:
///
///   archived          read-only, with a strip saying so
///   another unit      live — switch to that unit and it opens
///   nowhere           not yours, or never was (the server's one 404)
///   no connection     the archive and other units need one
class EeTicketOffDeviceScreen extends ConsumerWidget {
  const EeTicketOffDeviceScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final where = ref.watch(eeTicketWhereaboutsProvider(ticketId));
    void retry() => _retry(ref, () {
      ref.invalidate(eeRequesterTicketProvider(ticketId));
      ref.invalidate(eeTicketWhereaboutsProvider(ticketId));
    });
    return where.when(
      loading: () =>
          const _Frame(child: Center(child: CircularProgressIndicator())),
      error: (error, _) => _Frame(
        child: ticketNeedsConnection(error)
            ? AwEmptyState(
                key: const Key('ticket-elsewhere-offline'),
                icon: Icons.cloud_off_outlined,
                title: 'ee.tickets.elsewhere.offlineTitle'.tr(),
                message: 'ee.tickets.elsewhere.offlineBody'.tr(),
                action: OutlinedButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: Text('common.retry'.tr()),
                ),
              )
            : AwErrorState(message: localizedError(error), onRetry: retry),
      ),
      data: (found) => switch (found) {
        EeTicketForRequester() => EeRequesterTicketScreen(ticketId: ticketId),
        EeTicketArchived(:final ticket) => EeArchivedTicketView(ticket: ticket),
        EeTicketInAnotherUnit(:final workspaceId) => _Frame(
          child: _AnotherUnit(workspaceId: workspaceId),
        ),
        EeTicketNowhere() => _Frame(
          child: AwEmptyState(
            key: const Key('ticket-elsewhere-nowhere'),
            icon: Icons.help_outline,
            title: 'ee.tickets.elsewhere.nowhereTitle'.tr(),
            message: 'ee.tickets.elsewhere.nowhereBody'.tr(),
          ),
        ),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('ee.tickets.detailTitle'.tr())),
    body: child,
  );
}

/// Live, in another unit of this person's. Switching is the whole fix: the
/// engine follows the selected workspace, the replica fills, and the detail
/// that is watching it opens on its own.
class _AnotherUnit extends ConsumerWidget {
  const _AnotherUnit({required this.workspaceId});
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    String? name;
    for (final w in workspaces) {
      if (w.id == workspaceId) name = w.name;
    }
    return AwEmptyState(
      key: const Key('ticket-elsewhere-unit'),
      icon: Icons.swap_horiz,
      title: 'ee.tickets.elsewhere.unitTitle'.tr(),
      message: name == null
          ? 'ee.tickets.elsewhere.unitBodyUnnamed'.tr()
          : 'ee.tickets.elsewhere.unitBody'.tr(args: {'unit': name}),
      action: workspaceId == null || name == null
          ? null
          : FilledButton.tonal(
              key: const Key('ticket-elsewhere-switch'),
              onPressed: () => ref
                  .read(selectedWorkspaceIdProvider.notifier)
                  .select(workspaceId!),
              child: Text(
                'ee.tickets.elsewhere.switch'.tr(args: {'unit': name}),
              ),
            ),
    );
  }
}

/// One archived request, opened from the archive's own list.
class EeArchivedTicketScreen extends ConsumerWidget {
  const EeArchivedTicketScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(eeArchivedTicketProvider(ticketId));
    void retry() =>
        _retry(ref, () => ref.invalidate(eeArchivedTicketProvider(ticketId)));
    return ticket.when(
      loading: () =>
          const _Frame(child: Center(child: CircularProgressIndicator())),
      error: (error, _) => _Frame(
        child: ticketNeedsConnection(error)
            ? AwEmptyState(
                key: const Key('ticket-archive-offline'),
                icon: Icons.cloud_off_outlined,
                title: 'ee.tickets.archive.offlineTitle'.tr(),
                message: 'ee.tickets.archive.offlineBody'.tr(),
                action: OutlinedButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: Text('common.retry'.tr()),
                ),
              )
            : AwErrorState(message: localizedError(error), onRetry: retry),
      ),
      data: (row) => row == null
          ? _Frame(
              child: AwEmptyState(
                key: const Key('ticket-elsewhere-nowhere'),
                icon: Icons.help_outline,
                title: 'ee.tickets.elsewhere.nowhereTitle'.tr(),
                message: 'ee.tickets.elsewhere.nowhereBody'.tr(),
              ),
            )
          : EeArchivedTicketView(ticket: row),
    );
  }
}

/// An archived request, read-only, and saying so before anything else.
class EeArchivedTicketView extends ConsumerWidget {
  const EeArchivedTicketView({required this.ticket, super.key});

  final EeArchivedTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = ref.watch(dateFormatProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    final summary = ticket.summary;
    final slaLabel = ticket.slaStatus == null
        ? null
        : AwI18n.instance.maybeTranslate('ee.sla.${ticket.slaStatus}');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          summary.number == null
              ? 'ee.tickets.detailTitle'.tr()
              : '#${summary.number}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AwSpace.x4),
        children: [
          // The strip is the first thing on the screen, before the subject:
          // a read-only record must not be mistaken for a live one somebody
          // could still answer.
          Container(
            key: const Key('archive-strip'),
            padding: const EdgeInsets.all(AwSpace.x3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AwRadius.m),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 20),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    summary.terminalAt == null
                        ? 'ee.tickets.archive.stripUndated'.tr()
                        : 'ee.tickets.archive.strip'.tr(
                            args: {
                              'date': awFormatDate(
                                summary.terminalAt!,
                                format: dateFormat,
                              ),
                            },
                          ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AwSpace.x4),
          Text(summary.subject, style: theme.textTheme.titleLarge),
          const SizedBox(height: AwSpace.x2),
          Wrap(
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x2,
            children: [
              _Tag('ee.tickets.status.${summary.status}'.tr()),
              _Tag('ee.tickets.priority.${summary.priority}'.tr()),
              if (ticket.serviceName != null) _Tag(ticket.serviceName!),
              if (slaLabel != null) _Tag(slaLabel),
            ],
          ),
          if (summary.requesterDisplayName != null) ...[
            const SizedBox(height: AwSpace.x3),
            Text(
              'ee.tickets.archive.askedBy'.tr(
                args: {'name': summary.requesterDisplayName!},
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if ((ticket.body ?? '').isNotEmpty) ...[
            const SizedBox(height: AwSpace.x4),
            Text(ticket.body!, style: theme.textTheme.bodyLarge),
          ],
          if (ticket.answers.isNotEmpty)
            EeTicketAnswersView(
              answers: ticket.answers,
              dateFormat: dateFormat,
            ),
          // What the request left behind (EE-265) — each line only when
          // there is something to say, the asset card's rule for labour.
          if (ticket.approvals.isNotEmpty ||
              ticket.ratingScore != null ||
              ticket.labourMinutes > 0) ...[
            const SizedBox(height: AwSpace.x4),
            for (final approval in ticket.approvals)
              _Fact(
                key: const Key('archive-approval'),
                icon: Icons.verified_outlined,
                text: 'ee.tickets.archive.approval.${approval.status}'.tr(
                  args: {
                    'name': approval.decidedByName ?? '—',
                    'date': approval.decidedAt == null
                        ? '—'
                        : awFormatDate(approval.decidedAt!, format: dateFormat),
                  },
                ),
              ),
            if (ticket.ratingScore != null)
              _Fact(
                key: const Key('archive-rating'),
                icon: Icons.sentiment_satisfied_alt_outlined,
                text: 'ee.tickets.archive.rating'.tr(
                  args: {'score': '${ticket.ratingScore}'},
                ),
              ),
            if (ticket.labourMinutes > 0)
              _Fact(
                key: const Key('archive-labour'),
                icon: Icons.timer_outlined,
                // Hours AND minutes, never a decimal: "1.5" is wrong in
                // Turkish ("1,5") and "1 sa 30 dk" is right in both.
                text: 'ee.tickets.archive.labour'.tr(
                  args: {'time': _duration(ticket.labourMinutes)},
                ),
              ),
          ],
          const SizedBox(height: AwSpace.x6),
          Text(
            'ee.tickets.archive.thread'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          if (ticket.comments.isEmpty)
            Text(
              'ee.tickets.archive.noComments'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            )
          else
            for (final comment in ticket.comments)
              _ArchivedComment(comment: comment, dateFormat: dateFormat),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
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

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AwSpace.x2),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// An archived line of the conversation. The internal note keeps the live
/// thread's three signals — the set-apart surface, the lock and the word —
/// because a note mistaken for a reply is the same mistake in the archive.
class _ArchivedComment extends StatelessWidget {
  const _ArchivedComment({required this.comment, required this.dateFormat});
  final EeArchivedComment comment;
  final String dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (comment.authorName != null) comment.authorName!,
      if (comment.createdAt != null)
        awFormatDateTime(comment.createdAt!, format: dateFormat),
    ].join(' · ');
    return Card(
      key: Key('archive-comment-${comment.id}'),
      color: comment.internal
          ? theme.colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comment.internal) ...[
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: AwSpace.x1),
                  // The label is a sentence in Turkish ("only the desk sees
                  // it"): on a phone it wraps rather than running off the card.
                  Expanded(
                    child: Text(
                      'ee.tickets.internalNote'.tr(),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AwSpace.x2),
            ],
            Text(comment.body, style: theme.textTheme.bodyMedium),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: AwSpace.x1),
              Text(meta, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// EE-266 — "search the archive", the queue's other half.
///
/// A separate screen on purpose (ADR-0016 D16.3): the queue's search runs on
/// the device and answers with no signal; this one asks the server, and says
/// so — offline it names the connection it needs rather than drawing an empty
/// list that would read as "no such request".
class EeTicketArchiveSearchScreen extends ConsumerStatefulWidget {
  const EeTicketArchiveSearchScreen({this.initialQuery = '', super.key});

  final String initialQuery;

  @override
  ConsumerState<EeTicketArchiveSearchScreen> createState() =>
      _EeTicketArchiveSearchScreenState();
}

class _EeTicketArchiveSearchScreenState
    extends ConsumerState<EeTicketArchiveSearchScreen> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialQuery,
  );
  late String _query = widget.initialQuery.trim();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(eeArchiveSearchProvider(_query));
    final dateFormat = ref.watch(dateFormatProvider);
    void retry() =>
        _retry(ref, () => ref.invalidate(eeArchiveSearchProvider(_query)));
    return Scaffold(
      appBar: AppBar(title: Text('ee.tickets.archive.title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AwSpace.x3),
            child: TextField(
              key: const Key('archive-search'),
              controller: _field,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'ee.tickets.archive.searchHint'.tr(),
              ),
              onSubmitted: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? AwEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'ee.tickets.archive.title'.tr(),
                    message: 'ee.tickets.archive.intro'.tr(),
                  )
                : page.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => ticketNeedsConnection(error)
                        ? AwEmptyState(
                            key: const Key('archive-search-offline'),
                            icon: Icons.cloud_off_outlined,
                            title: 'ee.tickets.archive.offlineTitle'.tr(),
                            message: 'ee.tickets.archive.offlineBody'.tr(),
                            action: OutlinedButton.icon(
                              onPressed: retry,
                              icon: const Icon(Icons.refresh),
                              label: Text('common.retry'.tr()),
                            ),
                          )
                        : AwErrorState(
                            message: localizedError(error),
                            onRetry: retry,
                          ),
                    data: (found) => found.tickets.isEmpty
                        ? AwEmptyState(
                            key: const Key('archive-search-empty'),
                            icon: Icons.search_off_outlined,
                            title: 'ee.tickets.archive.emptyTitle'.tr(),
                            message: 'ee.tickets.archive.emptyBody'.tr(),
                          )
                        : ListView(
                            children: [
                              for (final t in found.tickets)
                                ListTile(
                                  key: Key('archive-row-${t.id}'),
                                  leading: const Icon(
                                    Icons.inventory_2_outlined,
                                  ),
                                  title: Text(
                                    t.number == null
                                        ? t.subject
                                        : '#${t.number} · ${t.subject}',
                                  ),
                                  subtitle: Text(
                                    [
                                      'ee.tickets.status.${t.status}'.tr(),
                                      if (t.terminalAt != null)
                                        awFormatDate(
                                          t.terminalAt!,
                                          format: dateFormat,
                                        ),
                                    ].join(' · '),
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EeArchivedTicketScreen(
                                        ticketId: t.id,
                                      ),
                                    ),
                                  ),
                                ),
                              if (found.hasMore)
                                Padding(
                                  key: const Key('archive-search-more'),
                                  padding: const EdgeInsets.all(AwSpace.x4),
                                  child: Text(
                                    'ee.tickets.archive.more'.tr(),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "1 sa 30 dk" / "45 dk" — the SLA chip's own words for a duration.
String _duration(int minutes) => minutes < 60
    ? 'ee.sla.minutes'.tr(args: {'m': '$minutes'})
    : 'ee.sla.hoursMinutes'.tr(
        args: {'h': '${minutes ~/ 60}', 'm': '${minutes % 60}'},
      );
