import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../data/unit_tickets_api.dart';

/// OPH-409 (U-20) — a count's scope in words, or null when the server did
/// not say (an older server): no label is better than a guessed one.
String? eeFigureScopeText(EeFigureScope? scope) {
  switch (scope?.reach) {
    case 'team':
      return 'ee.scope.team'.tr();
    case 'member':
      final count = scope!.unitCount;
      return count == null
          ? null
          : 'ee.scope.member'.tr(args: {'count': '$count'});
    case 'key':
      return 'ee.scope.key'.tr();
    default:
      return null;
  }
}

/// The scope line under a figure, muted; nothing when unknown.
class EeFigureScopeLine extends StatelessWidget {
  const EeFigureScopeLine({super.key, required this.scope});

  final EeFigureScope? scope;

  @override
  Widget build(BuildContext context) {
    final text = eeFigureScopeText(scope);
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      text,
      key: const Key('ee-figure-scope'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// "Opened by: X · Taken by: Y" (U-19). [assignees] null means "not told"
/// and draws no "taken by" part; an empty list is "nobody yet", marked with
/// the warning colour on the ICON only (the token is not text-strength,
/// DESIGN §7.1) so the words carry the meaning.
class EeTicketPeopleLine extends StatelessWidget {
  const EeTicketPeopleLine({
    super.key,
    required this.rowKey,
    this.requester,
    this.assignees,
    this.muted = false,
    required this.warning,
  });

  final String rowKey;
  final String? requester;
  final List<String>? assignees;
  final bool muted;
  final Color warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final people = assignees;
    final unassigned = people != null && people.isEmpty && !muted;
    final parts = <String>[
      if (requester != null && requester!.isNotEmpty)
        'ee.tickets.row.openedBy'.tr(args: {'name': requester!}),
      if (people != null)
        people.isEmpty
            ? 'ee.tickets.row.unassigned'.tr()
            : 'ee.tickets.row.takenBy'.tr(args: {'names': _names(people)}),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Row(
      key: Key('ticket-people-$rowKey'),
      children: [
        if (unassigned) ...[
          Icon(
            Icons.person_off_outlined,
            key: Key('ticket-unassigned-$rowKey'),
            size: 16,
            color: warning,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            parts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }

  /// Two names, then "+N": a row is scanned, not read.
  static String _names(List<String> names) {
    if (names.length <= 2) return names.join(', ');
    return 'ee.tickets.row.more'.tr(
      args: {'names': names.take(2).join(', '), 'count': '${names.length - 2}'},
    );
  }
}
