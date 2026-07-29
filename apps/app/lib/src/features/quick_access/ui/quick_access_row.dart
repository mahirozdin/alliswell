import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../projects/data/project.dart';
import '../data/quick_link.dart';

/// The glyph Quick Access uses everywhere — menu items, rail header, app-bar
/// fallback, bubble. Never the favourite star: the star sorts a list in place,
/// Quick Access composes a personal navigation list (DESIGN §23 Q2).
const IconData kQuickAccessIcon = Icons.bolt;

/// The kind's own icon, shown when the user picked no emoji (DESIGN §23 Q3).
IconData quickKindIcon(QuickKind kind) => switch (kind) {
  QuickKind.project => Icons.folder_outlined,
  QuickKind.task => Icons.check_circle_outline,
  QuickKind.note => Icons.description_outlined,
  QuickKind.folder => Icons.folder_copy_outlined,
  QuickKind.file => Icons.insert_drive_file_outlined,
  QuickKind.url => Icons.link,
};

/// The user's colour as a 10 px dot — filled with what they picked, ringed in
/// the `outline` token (DESIGN §23 Q8a).
///
/// The ring is not decoration: five of the ten palette colours cannot clear
/// 3:1 as a bare fill (#F59E0B is 2.15 on white), and project colour is not
/// even bounded to the palette. WCAG 1.4.11 measures the BOUNDARY of a
/// non-text control, so the ring carries the contrast and the fill stays
/// honest to the user's choice.
class QuickColorDot extends StatelessWidget {
  const QuickColorDot({super.key, required this.colorRgb, this.size = 10});

  final String colorRgb;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFromRgbHex(colorRgb),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
    );
  }
}

/// One rail row, identical in all three surfaces (DESIGN §23 Q1/Q3): identity
/// (emoji, else the kind icon), the user's title, then hints — a colour dot
/// and, for external links, a mandatory glyph (G5: leaving the app is meaning,
/// and colour alone never carries meaning).
///
/// Muting an archived or broken row is a TOKEN swap, never `Opacity`: a dimmed
/// label has to stay measurable (DESIGN §20 C3).
class QuickAccessRowTile extends StatelessWidget {
  const QuickAccessRowTile({
    super.key,
    required this.row,
    required this.onTap,
    this.trailing,
    this.dense = false,
  });

  final QuickAccessRow row;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = row.isBroken || row.isArchived;
    final titleColor = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    final subtitle = switch (row) {
      final r when r.isBroken => 'quick.broken'.tr(),
      final r when r.targetRenamed => 'quick.targetRenamed'.tr(
        args: {'name': r.targetTitle!},
      ),
      _ => null,
    };

    return ListTile(
      key: Key('quick-row-${row.id}'),
      dense: dense,
      visualDensity: dense ? VisualDensity.compact : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
      minLeadingWidth: 24,
      leading: _Leading(row: row, muted: muted),
      title: Text(
        row.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: titleColor,
          decoration: row.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (row.link.colorRgb case final color?) ...[
            QuickColorDot(colorRgb: color),
            const SizedBox(width: AwSpace.x2),
          ],
          if (row.link.kind == QuickKind.url) ...[
            Tooltip(
              message: 'quick.externalHint'.tr(),
              child: Icon(
                Icons.open_in_new,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AwSpace.x1),
          ],
          ?trailing,
        ],
      ),
      onTap: onTap,
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.row, required this.muted});

  final QuickAccessRow row;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (row.link.emoji case final emoji?) {
      return SizedBox(
        width: 24,
        child: Center(child: Text(emoji, style: theme.textTheme.titleMedium)),
      );
    }
    // A project keeps its own colour on the kind icon, so the rail reads the
    // same way the projects list does.
    final tint = row.link.kind == QuickKind.project && !muted
        ? (row.targetColorRgb == null
              ? theme.colorScheme.onSurfaceVariant
              : colorFromRgbHex(row.targetColorRgb!))
        : theme.colorScheme.onSurfaceVariant;
    return Icon(quickKindIcon(row.link.kind), size: 20, color: tint);
  }
}
