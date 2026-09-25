import 'package:flutter/material.dart';

import '../../../core/date_format.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/changes_models.dart';

/// How a change names itself on every screen (EE-269): its type, its risk and
/// its status, each in the server's own word translated — never recomputed.

/// "25 Eyl 14:00 – 16:00", or across days "25 Eyl 22:00 – 26 Eyl 02:00".
String changeWindowText(
  DateTime start,
  DateTime end, {
  required String format,
}) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final from = awFormatShort(start, format: format);
  final to = sameDay
      ? awFormatTime(end, format: format)
      : awFormatShort(end, format: format);
  return '$from – $to';
}

/// The three chips a change row and its detail both carry.
class EeChangeChips extends StatelessWidget {
  const EeChangeChips({super.key, required this.change, this.dense = false});

  final EeChange change;

  /// The list row's size: labels only, no padding to spare.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = dense ? VisualDensity.compact : null;
    // High risk is the one fact that changes how somebody reads the rest, so
    // it carries an icon as well as the word — never colour alone (DESIGN §7).
    final highRisk = change.risk == 'high';
    return Wrap(
      spacing: AwSpace.x2,
      runSpacing: AwSpace.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          key: Key('change-type-${change.id}'),
          visualDensity: density,
          label: Text('ee.changes.type.${change.type}'.tr()),
        ),
        Chip(
          key: Key('change-risk-${change.id}'),
          visualDensity: density,
          avatar: highRisk
              ? Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                )
              : null,
          label: Text('ee.changes.risk.${change.risk}'.tr()),
        ),
        Chip(
          key: Key('change-status-${change.id}'),
          visualDensity: density,
          label: Text(
            AwI18n.instance.maybeTranslate(
                  'ee.changes.status.${change.status}',
                ) ??
                change.status,
          ),
        ),
      ],
    );
  }
}
