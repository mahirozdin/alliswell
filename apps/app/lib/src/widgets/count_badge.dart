import 'package:flutter/material.dart';
import '../theme/typography.dart';

/// "3", "99+" — what a count badge prints.
String awCountLabel(int count, {int max = 99}) =>
    count > max ? '$max+' : '$count';

/// A count that wants attention: the red pill beside a row, a tab or a
/// navigation entry.
///
/// Extracted from the notification centre's badge (EE-077) so every counter
/// in the app is ONE widget with one rule:
///
/// - **The theme's `error` / `onError` pair**, never a hand-picked red: a
///   badge is small, coloured and carries a number, which is exactly the
///   surface DESIGN §7's contrast rule exists for. The pair is measured by
///   the same gate as everything else — and it is why the text is white on
///   red in light and dark ink on a lighter red in dark: white on the dark
///   theme's `error` measures 3.22:1, under the 4.5 floor.
/// - **Zero draws nothing.** A badge that is always there stops being a
///   signal (DESIGN W8).
/// - **Beyond [max] it reads "99+".** A four-digit badge is not information,
///   it is a layout problem.
/// - **The number alone tells a screen reader nothing** about what it
///   counts, so [semanticsLabel] is required.
class AwCountBadge extends StatelessWidget {
  const AwCountBadge({
    super.key,
    required this.count,
    required this.semanticsLabel,
    this.max = 99,
    this.badgeKey,
    this.ring = false,
  });

  final int count;
  final String semanticsLabel;
  final int max;

  /// A 2 px ring in the surface colour, for a badge that sits ON another
  /// coloured shape: the quick-access button's dark `primaryContainer` is
  /// only 2.40:1 against the dark `error` fill, so the ring — not the button
  /// — is what the pill's edge is measured against (DESIGN §7.1).
  final bool ring;

  /// Put on the pill itself — the notification centre's `notif-badge` has
  /// always been found that way.
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: semanticsLabel,
      child: Container(
        key: badgeKey,
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(11),
          border: ring ? Border.all(color: scheme.surface, width: 2) : null,
        ),
        child: Text(
          awCountLabel(count, max: max),
          textAlign: TextAlign.center,
          // ADR-0063 #3: a count is tabular, so 9 → 10 does not jitter.
          style: awTabular(
            theme.textTheme.labelSmall!.copyWith(
              color: scheme.onError,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon wearing an [AwCountBadge] on its top-right corner — a navigation
/// entry, the quick-access ⚡.
///
/// The badge sits OUTSIDE the icon's box (negative offset, no clipping), so
/// it never covers the glyph and never changes the tap target the icon's
/// parent measured.
class AwBadgedIcon extends StatelessWidget {
  const AwBadgedIcon({
    super.key,
    required this.icon,
    required this.count,
    required this.semanticsLabel,
    this.color,
    this.size,
    this.badgeKey,
  });

  final IconData icon;
  final int count;
  final String semanticsLabel;
  final Color? color;
  final double? size;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color, size: size),
        if (count > 0)
          Positioned(
            top: -6,
            right: -12,
            child: AwCountBadge(
              badgeKey: badgeKey,
              count: count,
              semanticsLabel: semanticsLabel,
            ),
          ),
      ],
    );
  }
}
