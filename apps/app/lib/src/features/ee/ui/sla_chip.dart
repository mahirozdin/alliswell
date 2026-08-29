import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';

/// The SLA badge, on a queue row and on a ticket's detail (EE-097).
///
/// ── The colour is the DOT; the meaning is the WORD ────────────────────────
///
/// `_PriorityMark` next door already settled this shape for the same list, and
/// here it is also what the contrast gate requires. MEASURED against the
/// light surface (#FFFFFF): `AwTokens.warning` #C77700 is **3.46** — fine for
/// a mark (the 3.0 threshold `warning star` already carries) and short of the
/// 4.5 a piece of TEXT needs. `error` #D70015 measures 5.38 and `success`
/// #0D7A33 measures 5.46, so those two may speak in their own colour.
///
/// So: the amber state is a coloured mark beside ordinary body text, and only
/// the two states that pass at text strength are drawn in colour. That is not
/// a compromise made to satisfy a script — a warning nobody can read is not a
/// warning, and DESIGN §7.1 exists because a surface in no pair reads exactly
/// like a surface that passed.
///
/// Every state carries a word for the second reason the priority mark does:
/// roughly 8% of men cannot separate red from green, and a factory prints its
/// queue in black and white.
enum SlaBadgeState { ok, warned, breached, met }

SlaBadgeState? slaBadgeStateOf(String? status) => switch (status) {
  'ok' => SlaBadgeState.ok,
  'warned' => SlaBadgeState.warned,
  'breached' => SlaBadgeState.breached,
  'met' => SlaBadgeState.met,
  // Null is a real answer — this team promised nothing about this ticket, and
  // a badge saying "no SLA" would be noise on every row of an unconfigured
  // desk.
  _ => null,
};

/// A coarse, human duration: days, or hours and minutes, or minutes.
///
/// Deliberately not seconds. A deadline four hours away that ticks every
/// second is a thing people watch instead of working, and the underlying
/// number is business time — which does not flow at one second per second
/// anyway (it stops at 17:00), so a live-ticking clock would be a lie told
/// precisely.
String formatSlaDuration(Duration d) {
  final total = d.abs();
  if (total.inDays >= 1) {
    return 'ee.sla.days'.tr(args: {'d': '${total.inDays}'});
  }
  if (total.inHours >= 1) {
    return 'ee.sla.hoursMinutes'.tr(
      args: {'h': '${total.inHours}', 'm': '${total.inMinutes % 60}'},
    );
  }
  return 'ee.sla.minutes'.tr(args: {'m': '${total.inMinutes}'});
}

/// The label a badge shows, given the state and the deadline.
String slaBadgeLabel(SlaBadgeState state, DateTime? dueAt, {DateTime? now}) {
  switch (state) {
    case SlaBadgeState.breached:
      return 'ee.sla.breached'.tr();
    case SlaBadgeState.met:
      return 'ee.sla.met'.tr();
    case SlaBadgeState.ok:
    case SlaBadgeState.warned:
      if (dueAt == null) return 'ee.sla.dueLabel'.tr();
      final left = dueAt.difference(now ?? DateTime.now());
      final time = formatSlaDuration(left);
      return left.isNegative
          ? 'ee.sla.overdueBy'.tr(args: {'time': time})
          : 'ee.sla.dueIn'.tr(args: {'time': time});
  }
}

/// One compact badge. Draws nothing when the ticket carries no promise.
class AwSlaChip extends StatelessWidget {
  const AwSlaChip({
    super.key,
    required this.ticket,
    this.now,
    this.muted = false,
  });

  final TicketRecord ticket;

  /// Injectable so a golden is a fixed picture rather than a photograph of the
  /// moment it was taken.
  final DateTime? now;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final state = slaBadgeStateOf(ticket.slaStatus);
    if (state == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final label = slaBadgeLabel(state, ticket.slaDueAt, now: now);

    // The mark's colour, and separately whether the LABEL may take it.
    final (Color mark, bool labelTakesColour, IconData icon) = switch (state) {
      SlaBadgeState.breached => (
        theme.colorScheme.error,
        true,
        Icons.error_outline,
      ),
      SlaBadgeState.met => (tokens.success, true, Icons.verified_outlined),
      // 3.46 against the light surface: a mark, never a sentence.
      SlaBadgeState.warned => (tokens.warning, false, Icons.schedule),
      SlaBadgeState.ok => (
        theme.colorScheme.onSurfaceVariant,
        false,
        Icons.schedule,
      ),
    };
    final labelColour = muted
        ? theme.disabledColor
        : labelTakesColour
        ? mark
        : theme.textTheme.bodySmall?.color;

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: muted ? theme.disabledColor : mark),
          const SizedBox(width: 4),
          Text(
            label,
            key: const Key('sla-chip-label'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: labelColour,
              fontWeight: state == SlaBadgeState.breached
                  ? FontWeight.w600
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The detail screen's larger reading of the same fact.
///
/// A countdown rather than a chip, because on the detail there is room to say
/// what the deadline IS as well as how far away — and an agent deciding what
/// to pick up next is exactly who needs the number.
class AwSlaCountdown extends StatelessWidget {
  const AwSlaCountdown({super.key, required this.ticket, this.now});

  final TicketRecord ticket;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final state = slaBadgeStateOf(ticket.slaStatus);
    if (state == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      key: const Key('sla-countdown'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'ee.sla.dueLabel'.tr(),
              style: theme.textTheme.labelLarge,
            ),
          ),
          AwSlaChip(ticket: ticket, now: now),
        ],
      ),
    );
  }
}
