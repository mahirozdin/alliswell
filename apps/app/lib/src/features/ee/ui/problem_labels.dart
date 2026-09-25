import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';

/// A problem's status as a chip, in the server's own word translated (EE-270).
///
/// A known error carries an icon as well as the word: it is the status that
/// changes what an agent does next (there is a workaround to read out), and a
/// colour alone would fail the person who cannot tell the colours apart
/// (DESIGN §7).
class EeProblemStatusChip extends StatelessWidget {
  const EeProblemStatusChip({
    super.key,
    required this.status,
    this.dense = false,
  });

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: dense ? VisualDensity.compact : null,
      avatar: status == 'known_error'
          ? Icon(
              Icons.lightbulb_outline,
              size: 18,
              color: theme.colorScheme.primary,
            )
          : null,
      label: Text(
        AwI18n.instance.maybeTranslate('ee.problems.status.$status') ?? status,
      ),
    );
  }
}
