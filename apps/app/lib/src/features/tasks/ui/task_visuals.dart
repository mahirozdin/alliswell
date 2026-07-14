import 'package:flutter/material.dart';

/// Standard task visuals (feedback round 3): statuses get ICONS, priorities
/// get COLORS — consistent across lists, detail dropdowns and create sheets.

IconData taskStatusIcon(String status) => switch (status) {
  'inbox' => Icons.inbox_outlined,
  'open' => Icons.radio_button_unchecked,
  'scheduled' => Icons.event_outlined,
  'in_progress' => Icons.timelapse,
  'waiting' => Icons.hourglass_empty,
  'completed' => Icons.check_circle,
  'cancelled' => Icons.cancel_outlined,
  'archived' => Icons.archive_outlined,
  _ => Icons.circle_outlined,
};

/// Fixed palette (matches the project swatches, theme-independent so the
/// meaning never shifts): low=green, medium=amber, high=orange, urgent=red.
Color? taskPriorityColor(String priority) => switch (priority) {
  'low' => const Color(0xFF10B981),
  'medium' => const Color(0xFFF59E0B),
  'high' => const Color(0xFFF97316),
  'urgent' => const Color(0xFFEF4444),
  _ => null, // none → neutral
};

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
    final color = taskPriorityColor(priority);
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
