import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart' show AwSpace;
import '../team_origin.dart';

/// Which team this window belongs to (EE-018). Lives in the shared section
/// app bar, so every screen inherits it from one place — and renders NOTHING
/// on a CE server or a plain host, which is what keeps the community build
/// pixel-identical (proven in the widget suite, not assumed).
///
/// Narrow screens keep only the colour dot: identity without stealing the
/// section title's room.
class AwTeamChip extends ConsumerWidget {
  const AwTeamChip({super.key, this.compactWidth = 600});

  /// Below this width only the dot is drawn.
  final double compactWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamOriginProvider);
    if (team == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < compactWidth;
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: team.color, shape: BoxShape.circle),
    );

    return Tooltip(
      message: 'ee.team.tooltip'.tr(args: {'team': team.displayName}),
      child: Semantics(
        label: 'ee.team.tooltip'.tr(args: {'team': team.displayName}),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
          child: compact
              ? dot
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot,
                    const SizedBox(width: AwSpace.x2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        team.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
