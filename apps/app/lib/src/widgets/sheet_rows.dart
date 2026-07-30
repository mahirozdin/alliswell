import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shared sheet field rows (OPH-221/222). Extracted from task_create_sheet.dart
/// so the AI confirm card reuses the exact visual language of the create sheet
/// (DESIGN §24 AI5) instead of forking it. The bubble also uses [AwSheetSurface]
/// as its opaque content surface (glass stays chrome-only, AI3).

/// A filled, rounded backdrop for a field — opaque, never glass.
class AwSheetSurface extends StatelessWidget {
  const AwSheetSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A tap-to-set row (date, reminder, …) with a clear affordance when set.
class AwSheetTile extends StatelessWidget {
  const AwSheetTile({
    super.key,
    this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSet,
    required this.clearTooltip,
    required this.onClear,
    required this.onTap,
  });

  final Key? tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSet;
  final String clearTooltip;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AwSheetSurface(
      child: ListTile(
        key: tileKey,
        leading: Icon(icon, color: scheme.onSurfaceVariant),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isSet ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: isSet ? FontWeight.w600 : null,
          ),
        ),
        trailing: isSet
            ? IconButton(
                tooltip: clearTooltip,
                icon: const Icon(Icons.close),
                onPressed: onClear,
              )
            : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
