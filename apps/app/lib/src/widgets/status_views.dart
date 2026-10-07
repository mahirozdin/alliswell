import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/tokens.dart';

/// Shared empty state: soft icon badge, title, guidance line, optional action.
class AwEmptyState extends StatelessWidget {
  const AwEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.physics,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// Physics for this state's own scroll view (it has one so tight layouts
  /// never overflow). Two recipes matter (OPH-171, DESIGN §15):
  /// - directly inside an [AwRefresh] → `AlwaysScrollableScrollPhysics()`, so
  ///   the pull gesture overscrolls THIS view and the indicator appears;
  /// - already inside a scrolling parent (a sliver) →
  ///   `NeverScrollableScrollPhysics()`, so the drag reaches that parent
  ///   instead of dying here.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so tight layouts (collapsed panels, small windows) never
    // overflow — the state simply scrolls instead.
    return Center(
      child: SingleChildScrollView(
        physics: physics,
        padding: const EdgeInsets.all(AwSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.55,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 34,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AwSpace.x4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared error state with a retry path (never a dead end).
class AwErrorState extends StatelessWidget {
  const AwErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.physics,
    this.retryLabel,
    this.retryIcon,
    this.detail,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Overrides the action's wording and icon. "Retry" is right for a failed
  /// load; it is wrong for a dead end, where the way out is "go home"
  /// (OPH-189).
  final String? retryLabel;
  final IconData? retryIcon;

  /// Small print under the message — the offending location, an error code:
  /// useful in a bug report, ignorable by everyone else.
  final String? detail;

  /// See [AwEmptyState.physics] — same two recipes.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: physics,
        padding: const EdgeInsets.all(AwSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            Text(
              'state.somethingWrong'.tr(),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AwSpace.x1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: AwSpace.x2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AwSpace.x4),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: Icon(retryIcon ?? Icons.refresh),
                label: Text(retryLabel ?? 'common.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline form error: icon + message on an error-container band, placed
/// right above the submit action (never color-only, never top-of-page).
///
/// With [onRetry] it is also the way a SECTION of a screen says it failed
/// (OPH-357, UI-AUDIT #26): a part that loads on its own must not vanish
/// silently or read as empty when its request was refused.
class AwInlineError extends StatelessWidget {
  const AwInlineError({
    super.key,
    required this.message,
    this.textKey,
    this.onRetry,
  });

  final String message;
  final Key? textKey;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x3,
        vertical: AwSpace.x3,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      child: Row(
        crossAxisAlignment: onRetry == null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              message,
              key: textKey,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: AwSpace.x2),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                minimumSize: const Size(44, 44),
              ),
              child: Text('common.retry'.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

/// The space around ONE card row of a list — DESIGN §4's 6 px rhythm, paid as 3 px
/// above and 3 px below every row so two neighbours never touch.
///
/// The theme's `CardThemeData.margin` is zero on purpose (a card inside a form or a
/// sheet sits where its parent puts it), so a list that stacks bare `Card`s draws
/// them border on border. Every card row wraps itself in this rather than choosing a
/// number: a list at 8 px beside one at 6 px beside one at 0 px is how the queue
/// ended up with none.
const EdgeInsets kAwListRowPadding = EdgeInsets.symmetric(vertical: 3);

/// List padding that clears the glass bottom bar / FAB on every platform.
EdgeInsets awListPadding(
  BuildContext context, {
  double horizontal = AwSpace.x4,
  double top = AwSpace.x2,
  double extraBottom = 0,
}) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(
    horizontal,
    top,
    horizontal,
    bottomInset + AwSpace.x6 + extraBottom,
  );
}
