import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../approvals_providers.dart';
import '../my_tickets_providers.dart';
import '../providers.dart';
import '../tickets_providers.dart';
import '../unit_scope_providers.dart';
import '../unit_tickets_providers.dart';
import 'desk_paths.dart';

/// OPH-409 (U-22) — requests on Home, for the people who live by them.
///
/// A member of an organisation opened Home onto personal-productivity copy
/// with no way to ask for help, and a manager opened it with no sign of
/// what was late or waiting on nobody. Above the task list now:
///
///   • a member who files requests: "Open a new request" and "My open
///     requests (N)";
///   • somebody at a desk: one line of what needs them — late requests in
///     their units, requests nobody has taken (when the server counts them),
///     approvals waiting for them — each number a door to its list.
///
/// Only on a governed workspace with the teams feature: a plain build, a
/// personal space and a signed-out device draw nothing, so Home is unchanged
/// there. Every figure is the server's; a failed read draws nothing rather
/// than a zero.
class EeHomeTicketCards extends ConsumerWidget {
  const EeHomeTicketCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(eeFeatureProvider('teams'))) return const SizedBox.shrink();
    final permissions = ref.watch(eePermissionsProvider).value;
    if (permissions == null || !permissions.governed) {
      return const SizedBox.shrink();
    }
    return permissions.desk ? const _DeskSummary() : const _MemberCards();
  }
}

const _finished = {'resolved', 'closed', 'cancelled'};

class _MemberCards extends ConsumerWidget {
  const _MemberCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An error (not on this team, offline) draws nothing: the requests
    // screen is where that is said out loud.
    final mine = ref.watch(eeMyTicketsProvider).value;
    if (mine == null) return const SizedBox.shrink();
    final open = mine.where((t) => !_finished.contains(t.status)).length;
    final canFile = ref.watch(canProvider('tickets.create'));
    return Padding(
      key: const Key('ee-home-member-cards'),
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canFile) ...[
            Expanded(
              child: _CardButton(
                key: const Key('ee-home-new-ticket'),
                icon: Icons.add_circle_outline,
                label: 'ee.home.newTicket'.tr(),
                onTap: () => context.push('/tickets/new'),
              ),
            ),
            const SizedBox(width: AwSpace.x2),
          ],
          Expanded(
            child: _CardButton(
              key: const Key('ee-home-my-tickets'),
              icon: Icons.support_agent_outlined,
              label: 'ee.home.myOpenTickets'.tr(
                args: {'count': awFormatNumber(open)},
              ),
              onTap: () => context.push('/settings/team/my-tickets'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.all(AwSpace.x3),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: AwSpace.x2),
                Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeskSummary extends ConsumerWidget {
  const _DeskSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref
        .watch(eeUnitTicketsPageProvider((alertsOnly: true, cursor: '')))
        .value;
    final approvals = ref.watch(eeApprovalsDoorProvider)
        ? ref.watch(eeApprovalsBadgeProvider)
        : 0;
    final breached = alerts?.breached ?? 0;
    final unassigned = alerts?.unassigned ?? 0;
    final links = <Widget>[
      if (breached > 0)
        _Figure(
          key: const Key('ee-home-breached'),
          label: 'ee.home.breached'.tr(
            args: {'count': awFormatNumber(breached)},
          ),
          onTap: () => context.push('$kAwMyUnitsPath?alerts=1'),
        ),
      if (unassigned > 0)
        _Figure(
          key: const Key('ee-home-unassigned'),
          label: 'ee.home.unassigned'.tr(
            args: {'count': awFormatNumber(unassigned)},
          ),
          // The figure counts across the person's units, so its door is
          // every unit's list filtered to nobody's — not the unit on screen
          // (E35 G-D review r1).
          onTap: () {
            ref
                .read(ticketFilterProvider.notifier)
                .setAssignee(TicketAssigneeScope.unassigned);
            ref.read(eeQueueAllUnitsChosenProvider.notifier).set(true);
            context.go('/tickets');
          },
        ),
      if (approvals > 0)
        _Figure(
          key: const Key('ee-home-approvals'),
          label: 'ee.home.approvals'.tr(
            args: {'count': awFormatNumber(approvals)},
          ),
          onTap: () => context.push('/approvals'),
        ),
    ];
    if (links.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Card(
        key: const Key('ee-home-desk-summary'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            AwSpace.x3,
            AwSpace.x2,
            AwSpace.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ee.home.unitsTitle'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              Wrap(spacing: AwSpace.x1, children: links),
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure of the summary, and the door to its list.
class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    child: Text(label),
  );
}
