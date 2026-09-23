import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fabs.dart';
import '../../../widgets/status_views.dart';
import '../my_tickets_providers.dart';
import '../providers.dart';

/// "My requests" (EE-087) — what I asked for, and where it got to.
///
/// ── Why this one screen is allowed to need a connection ──────────────────
///
/// Every other EE list here reads the replica and is right with no signal.
/// This one cannot: a requester is by definition not a member of the unit that
/// answers them, and the sync engine runs one workspace at a time, so a
/// replica-backed list would silently omit most of somebody's requests
/// (ADR-0011 §3). Between an online list and a quietly incomplete one, the ADR
/// chose online — and the price is paid HERE, by saying so plainly when the
/// request fails rather than showing an empty list that looks like "you have
/// asked for nothing".
///
/// That distinction is the whole design of the error state below: "we could
/// not reach the server" and "you have no open requests" must never look alike.
///
/// ── EE-216 REVISES THE HALF THAT WAS AVOIDABLE ───────────────────────────
///
/// READING still needs a connection, for the reason above: the list spans
/// workspaces this replica does not hold, and a quietly incomplete list is
/// worse than an honest failure.
///
/// WRITING no longer does. ADR-0011's parking lot named the way out and
/// EE-216 took it: a draft is a different sync TYPE, living in the requester's
/// OWN workspace, which the server converts into a real request on arrival.
/// So "a requester cannot work offline" is now only true of looking things up
/// — see `ticket_drafts_providers.dart`.
class EeMyTicketsScreen extends ConsumerWidget {
  const EeMyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(eeMyTicketsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.tickets.mineTitle'.tr())),
      // EE-225: the requester's own list is where asking for something new
      // belongs — and filing works with no signal (a draft), even though this
      // list does not.
      floatingActionButton: ref.watch(canProvider('tickets.create'))
          ? AwExtendedFab(
              key: const Key('my-tickets-new'),
              onPressed: () => context.push('/tickets/new'),
              icon: const Icon(Icons.add),
              label: Text('ee.tickets.new.fab'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(eeMyTicketsProvider.future),
        child: tickets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(
            message: localizedError(error),
            onRetry: () => ref.invalidate(eeMyTicketsProvider),
          ),
          data: (rows) {
            if (rows == null || rows.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: AwSpace.x12),
                  AwEmptyState(
                    icon: Icons.help_outline,
                    title: 'ee.tickets.mineEmptyTitle'.tr(),
                    message: 'ee.tickets.mineEmptyBody'.tr(),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(AwSpace.x4),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final ticket = rows[i];
                final theme = Theme.of(context);
                return Card(
                  key: Key('my-ticket-${ticket.id}'),
                  child: ListTile(
                    title: Text(ticket.subject),
                    subtitle: Text(
                      [
                        // The service's NAME, because that is what the asker
                        // recognises — never the unit that answers them.
                        if (ticket.serviceName != null) ticket.serviceName!,
                        'ee.tickets.status.${ticket.status}'.tr(),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
