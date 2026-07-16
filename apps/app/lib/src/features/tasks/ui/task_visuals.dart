import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

/// Standard task visuals (feedback round 3): statuses get ICONS, priorities
/// get COLORS — consistent across lists, detail dropdowns and create sheets.

IconData taskStatusIcon(String status) => switch (status) {
  'inbox' => Icons.inbox_outlined,
  // 'open' is work waiting to be done → an hourglass, NOT a bare circle (the
  // circle collided with the row's circular completion checkbox — OPH-105).
  'open' => Icons.hourglass_empty,
  'scheduled' => Icons.event_outlined,
  'in_progress' => Icons.timelapse,
  // 'waiting' (on hold) hands the hourglass to 'open' and takes a pause circle.
  'waiting' => Icons.pause_circle_outline,
  'completed' => Icons.check_circle,
  'cancelled' => Icons.cancel_outlined,
  'archived' => Icons.archive_outlined,
  _ => Icons.circle_outlined,
};

/// Priority → color. Hues are fixed (low=green, medium=amber, high=orange,
/// urgent=red) so the MEANING never shifts; lightness adapts per brightness
/// so the flag keeps ≥ 3:1 contrast on surfaces (AwTokens, docs/DESIGN.md).
Color? taskPriorityColor(String priority, Brightness brightness) {
  final t = brightness == Brightness.dark ? AwTokens.dark : AwTokens.light;
  return switch (priority) {
    'low' => t.prioLow,
    'medium' => t.prioMedium,
    'high' => t.prioHigh,
    'urgent' => t.prioUrgent,
    _ => null, // none → neutral
  };
}

/// Convenience for widgets: resolves against the ambient theme.
Color? taskPriorityColorOf(BuildContext context, String priority) =>
    taskPriorityColor(priority, Theme.of(context).brightness);

/// Icon + name, for status dropdown entries.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          taskStatusIcon(status),
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(status),
      ],
    );
  }
}

/// Colored flag + name, for priority dropdown entries.
class PriorityLabel extends StatelessWidget {
  const PriorityLabel({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = taskPriorityColorOf(context, priority);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          color == null ? Icons.flag_outlined : Icons.flag,
          size: 18,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(priority),
      ],
    );
  }
}
