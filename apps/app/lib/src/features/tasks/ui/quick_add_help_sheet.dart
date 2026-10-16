import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';

/// What the quick-add bar understands (OPH-373, DESIGN §39 Q3): a short,
/// example-first sheet, opened from the bar's ?. A solid sheet surface — text
/// never sits on glass (rule 11). The grammar itself is ADR-0054; this sheet
/// shows each language its own words, and says both always work.
class QuickAddHelpSheet extends StatelessWidget {
  const QuickAddHelpSheet({super.key});

  static const _sections = [
    (Icons.event, 'dates'),
    (Icons.schedule, 'times'),
    (Icons.wb_sunny_outlined, 'dueWhen'),
    (Icons.repeat, 'repeat'),
    (Icons.sell_outlined, 'marks'),
    (Icons.undo, 'undo'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      key: const Key('quick-add-help-sheet'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x6,
            0,
            AwSpace.x6,
            AwSpace.x6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'task.quickParse.help.title'.tr(),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AwSpace.x2),
              Text(
                'task.quickParse.help.intro'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              for (final (icon, id) in _sections) ...[
                const SizedBox(height: AwSpace.x5),
                Row(
                  children: [
                    Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        'task.quickParse.help.${id}Title'.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AwSpace.x1),
                for (final line in 'task.quickParse.help.$id'.tr().split('\n'))
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: AwSpace.x1),
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
