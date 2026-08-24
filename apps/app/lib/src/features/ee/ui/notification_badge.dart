import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../notifications_providers.dart';

/// The unread badge (EE-077).
///
/// LIVE FROM THE REPLICA'S OWN STREAM, not from a fetch: the count is a drift
/// `watch` over the notification table, so it moves the instant a pull writes a
/// row and it is correct with no signal. Nothing polls, and nothing has to be
/// told to refresh it.
///
/// ── WHY IT IS A CHIP AND NOT A RED DOT WITH WHITE TEXT ────────────────────
///
/// A badge is small, coloured, and carries a NUMBER — which makes it exactly
/// the surface DESIGN's contrast rule (§11) exists for, and exactly the kind of
/// thing that passes an eye and fails a measurement. E07 learned this twice:
/// half the roster palette could not carry white initials at 4.5:1, and the
/// comment above that code said it could. So this uses the theme's
/// `error`/`onError` pair — a semantic pair the design system already
/// guarantees, measured by the same gate as everything else — instead of a
/// hand-picked red.
///
/// Zero draws NOTHING rather than a "0": a badge that is always there stops
/// being a signal.
class AwNotificationBadge extends ConsumerWidget {
  const AwNotificationBadge({super.key, this.max = 99});

  /// Beyond this it reads "99+". A four-digit badge is not information, it is
  /// a layout problem.
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).value ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final label = count > max ? '$max+' : '$count';

    return Semantics(
      // The number alone tells a screen reader nothing about what it counts.
      label: 'ee.notif.unreadBadge'.tr(args: {'count': '$count'}),
      child: Container(
        key: const Key('notif-badge'),
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onError,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
