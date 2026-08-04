/// Round-14 creation defaults, in ONE place so the create sheet, Home quick
/// add and the AI quick-add path cannot drift apart:
///
/// - a brand-new task is born **medium** priority with the **urgent alarm on**
///   (the owner's product stance: a task you bothered to write down deserves
///   to actually ring);
/// - picking a due date auto-arms a reminder [kAwAutoReminderGap] before it —
///   a suggestion, not a law: the user can move or clear it afterwards.
library;

/// How far before the deadline the auto-reminder lands.
const Duration kAwAutoReminderGap = Duration(hours: 1);

/// The reminder derived from a deadline, or null without one.
DateTime? awAutoReminderFor(DateTime? dueAt) =>
    dueAt?.subtract(kAwAutoReminderGap);

/// Create-body fragment for the quick-add surfaces (Home bar, AI rider).
/// The detailed sheet applies the same values through its own fields instead,
/// so the user sees them before saving.
Map<String, dynamic> awQuickTaskDefaults({DateTime? dueAt}) => {
  'priority': 'medium',
  'isUrgent': true,
  if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
  if (dueAt != null)
    'remindAt': awAutoReminderFor(dueAt)!.toUtc().toIso8601String(),
};
