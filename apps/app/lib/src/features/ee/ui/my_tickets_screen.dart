import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fabs.dart';
import '../../../widgets/status_views.dart';
import '../data/my_tickets_api.dart';
import '../my_tickets_providers.dart';
import '../providers.dart';
import 'ticket_archive_screen.dart' show EeMyArchivedTicketsScreen;
import 'ticket_detail_screen.dart';
import 'ticket_drafts_section.dart';

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
        // One scrolling list, drafts first: they are the device's own and are
        // right with no signal, so they must not share the fate of the REST
        // list below them when that fails (EE-225).
        // The same clearance every FAB list here keeps: the last card must
        // not sit under "new request".
        child: ListView(
          padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
          children: [
            const EeTicketDraftsSection(),
            ...tickets.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(AwSpace.x6),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                AwErrorState(
                  message: localizedError(error),
                  onRetry: () => ref.invalidate(eeMyTicketsProvider),
                ),
              ],
              data: (rows) => rows == null || rows.isEmpty
                  ? [
                      const SizedBox(height: AwSpace.x6),
                      AwEmptyState(
                        icon: Icons.help_outline,
                        title: 'ee.tickets.mineEmptyTitle'.tr(),
                        message: 'ee.tickets.mineEmptyBody'.tr(),
                      ),
                    ]
                  : [
                      for (final ticket in rows)
                        Card(
                          key: Key('my-ticket-${ticket.id}'),
                          child: ListTile(
                            // EE-253: the one wait that is theirs to end,
                            // findable at a glance down a long list.
                            leading: ticket.waitsOnRequester
                                ? Icon(
                                    Icons.front_hand_outlined,
                                    key: Key(
                                      'my-ticket-waiting-on-you-${ticket.id}',
                                    ),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                : null,
                            title: Text(ticket.subject),
                            subtitle: Text(
                              [
                                // The service's NAME, because that is what
                                // the asker recognises — never the unit that
                                // answers them.
                                if (ticket.serviceName != null)
                                  ticket.serviceName!,
                                _statusLabel(ticket),
                                // EE-252: "what happened last" (GUIDE-USER).
                                if (ticket.updatedAt != null)
                                  'ee.tickets.requester.updated'.tr(
                                    args: {
                                      'when': awFormatDateTime(
                                        ticket.updatedAt!.toLocal(),
                                        format: ref.watch(dateFormatProvider),
                                      ),
                                    },
                                  ),
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            // EE-252: the row opens the request — its own
                            // address, the requester's view (EE-251).
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => awOpenTicket(context, ticket.id),
                          ),
                        ),
                    ],
            ),
            const _ArchiveSection(),
          ],
        ),
      ),
    );
  }
}

/// EE-266 (AW-E17): the requests the sweep moved. Its own section, below the
/// live list and whatever state that list is in: a request archived ninety
/// days after closing used to vanish from here, and the person who asked is
/// the one most certain to come back looking for it. One door rather than a
/// second list on this screen — the archive grows for as long as they keep
/// asking, and it pages on its own screen.
class _ArchiveSection extends StatelessWidget {
  const _ArchiveSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ee.tickets.archive.mineSection'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          Card(
            key: const Key('my-tickets-archive'),
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('ee.tickets.archive.mineTitle'.tr()),
              subtitle: Text(
                'ee.tickets.archive.mineTileBody'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EeMyArchivedTicketsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// EE-253: which wait it is. "Beklemede" alone read the same for all five
/// reasons, and only `requester_info` is the asker's move — so that one says
/// "you", and the others name what the desk is waiting on.
String _statusLabel(EeMyTicket ticket) {
  if (ticket.status != 'waiting') {
    return 'ee.tickets.status.${ticket.status}'.tr();
  }
  final reason = ticket.waitingReason;
  if (reason == 'requester_info') {
    return 'ee.tickets.requester.waitingOnYouShort'.tr();
  }
  if (reason != null) return 'ee.sla.reason.$reason'.tr();
  return 'ee.tickets.status.waiting'.tr();
}
