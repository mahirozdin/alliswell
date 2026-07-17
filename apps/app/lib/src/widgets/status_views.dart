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
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so tight layouts (collapsed panels, small windows) never
    // overflow — the state simply scrolls instead.
    return Center(
      child: SingleChildScrollView(
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
  const AwErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
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
            if (onRetry != null) ...[
              const SizedBox(height: AwSpace.x4),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text('common.retry'.tr()),
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
class AwInlineError extends StatelessWidget {
  const AwInlineError({super.key, required this.message, this.textKey});

  final String message;
  final Key? textKey;

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
        ],
      ),
    );
  }
}

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
