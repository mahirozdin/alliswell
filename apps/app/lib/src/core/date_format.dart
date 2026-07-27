/// Dates as the USER sees and picks them (round 9 — DESIGN §17).
///
/// Everything here is pure: no providers, no widgets, no globals — so the rules
/// are unit-testable and the UI layer only has to decide *when* to call them.
library;

/// Where a date picker OPENS when the field is still empty (round 9 #4,
/// OPH-173): **tomorrow**, never today.
///
/// Someone who means today taps today — it is right there. The far more common
/// intent is "the next day", and opening on today made that a two-tap move every
/// single time.
///
/// - [current] — an existing value always wins; you never fight a picker that
///   forgot what the field already says.
/// - [anchor] — the date this field belongs NEXT TO. A reminder opens on its
///   task's due day (a nudge lives near its deadline), not on tomorrow.
DateTime awInitialPickerDate({
  DateTime? current,
  DateTime? anchor,
  required DateTime now,
}) {
  final existing = current ?? anchor;
  if (existing != null) return existing;
  // Day arithmetic through the constructor so month/year roll over correctly
  // (and DST never shifts the calendar day the way `add(Duration(days: 1))` can).
  return DateTime(now.year, now.month, now.day + 1);
}
