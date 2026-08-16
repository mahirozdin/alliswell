import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/recent_colors.dart';
import '../features/projects/data/project.dart' show colorFromRgbHex;
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'color_swatch_dot.dart';

/// One colour picker for the whole app (OPH-259, DESIGN §33 R1).
///
/// Anatomy, in order: the colours you used last (only the ones THIS surface
/// can honour, hidden when there are none), then this surface's palette, then
/// whatever extra affordances the surface has — "more colours" where it offers
/// them, "no colour" where clearing means something.
///
/// Four hand-rolled variants existed before this: the project sheet's Wrap, the
/// tag dialog's own `InkWell`+`CircleAvatar` (which did not even use the shared
/// swatch), the quick-link sheet's copy, and — the one that started the
/// complaint — flutter_quill's stock dialog, complete with a **hex text field**
/// that round 1 forbade in the first place (§33 R3).
///
/// Picking is the whole interaction: it applies and, in a sheet, closes (R5).
/// Every pick is remembered here, so no caller can forget to (R2).
class AwColorPicker extends ConsumerWidget {
  const AwColorPicker({
    super.key,
    required this.palette,
    required this.selected,
    required this.onPicked,
    this.keyPrefix = 'color',
    this.onMore,
    this.onCleared,
    this.moreLabelKey = 'color.more',
    this.clearLabelKey = 'color.none',
    this.colorOf = colorFromRgbHex,
  });

  /// The values this surface is willing to show — `#RRGGBB` for the surfaces
  /// that store a colour, or note-colour **names** for the editor, which
  /// stores a name so each theme can resolve its own hex (§33 R4).
  final List<String> palette;
  final String? selected;
  final ValueChanged<String> onPicked;

  /// How a palette value becomes something paintable. Only the editor needs to
  /// override it; everywhere else a value IS a hex.
  final Color Function(String value) colorOf;

  /// Namespaces the swatch keys so two pickers on one screen stay findable.
  final String keyPrefix;

  /// Shown only where the surface really offers a wider set (projects, tags).
  final VoidCallback? onMore;

  /// Shown only where "no colour" is a meaningful value (quick links).
  final VoidCallback? onCleared;

  final String moreLabelKey;
  final String clearLabelKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = awRecentColorsFor(ref.watch(recentColorsProvider), palette);

    Widget dot(String hex, {required String keyName}) => AwColorSwatchDot(
      key: Key(keyName),
      color: colorOf(hex),
      selected: selected?.toUpperCase() == hex.toUpperCase(),
      onTap: () {
        // Remembered before it is applied: the caller may close the sheet.
        ref.read(recentColorsProvider.notifier).remember(hex);
        onPicked(hex);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recents.isNotEmpty) ...[
          Text(
            'color.recent'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AwSpace.x1),
          Wrap(
            key: Key('$keyPrefix-recents'),
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x2,
            children: [
              for (final hex in recents)
                dot(hex, keyName: '$keyPrefix-recent-$hex'),
            ],
          ),
          const SizedBox(height: AwSpace.x3),
        ],
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          children: [
            for (final hex in palette) dot(hex, keyName: '$keyPrefix-$hex'),
          ],
        ),
        if (onMore != null || onCleared != null) ...[
          const SizedBox(height: AwSpace.x2),
          Row(
            children: [
              if (onMore != null)
                TextButton.icon(
                  key: Key('$keyPrefix-more'),
                  onPressed: onMore,
                  icon: const Icon(Icons.palette_outlined),
                  label: Text(moreLabelKey.tr()),
                ),
              if (onCleared != null)
                TextButton.icon(
                  key: Key('$keyPrefix-clear'),
                  onPressed: onCleared,
                  icon: const Icon(Icons.format_color_reset_outlined),
                  label: Text(clearLabelKey.tr()),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
