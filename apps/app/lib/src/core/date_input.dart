import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'date_format.dart';
import 'persisted_prefs.dart';

/// One date **input** path, the way `date_format.dart` is one date **output**
/// path (OPH-191, DESIGN §17 D5).
///
/// Round 10 #6 found the create sheet asking for a date AND a time while the
/// detail screen asked only for a date and then quietly stamped the user's
/// default task time on it — so changing only the DAY of a 14:30 task silently
/// moved it to 23:59. Same field, two behaviours, and the destructive one was
/// invisible. **Editing a value must never change a part of it the user did not
/// touch.**
///
/// Returns null when the user backs out of the date step: that means "no
/// change", and the caller keeps whatever it had. Dismissing only the CLOCK is
/// not a cancel — the day was chosen, so the time falls back (existing value
/// first, then the user's default task time, OPH-161).
///
/// [anchor] is the date this field lives next to (a reminder opens on its
/// deadline's day); an empty field with no anchor opens on **tomorrow**
/// (OPH-173). See [awInitialPickerDate].
///
/// [cancelText] renames the date step's back-out button where backing out is
/// not a cancel — Home's deadline ask, whose skip still adds the task
/// (DESIGN §26 C3, OPH-401 R-04). Null keeps the platform's "Cancel".
Future<DateTime?> awPickDateTime(
  BuildContext context,
  WidgetRef ref, {
  DateTime? current,
  DateTime? anchor,
  String? cancelText,
}) async {
  final now = DateTime.now();
  final (defHour, defMinute) = parseTaskTime(ref.read(defaultTaskTimeProvider));
  final date = await showDatePicker(
    context: context,
    initialDate: awInitialPickerDate(
      current: current,
      anchor: anchor,
      now: now,
    ),
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 365 * 5)),
    cancelText: cancelText,
  );
  if (date == null || !context.mounted) return null;
  final time = await awShowTimePicker(
    context: context,
    // The value being EDITED wins over any default: this is the line that keeps
    // 14:30 at 14:30 when only the day changes.
    initialTime: current != null
        ? TimeOfDay.fromDateTime(current)
        : TimeOfDay(hour: defHour, minute: defMinute),
  );
  return DateTime(
    date.year,
    date.month,
    date.day,
    time?.hour ?? current?.hour ?? defHour,
    time?.minute ?? current?.minute ?? defMinute,
  );
}

/// The app's one clock picker: [showTimePicker] with the locale's own hour
/// format honoured in TEXT ENTRY too (OPH-471, walkthrough W-06).
///
/// A 24-hour locale (tr) draws a 24-hour dial with no AM/PM toggle, but
/// Flutter's text-entry parser reads `MediaQuery.alwaysUse24HourFormat`
/// instead — false on web and desktop, and on a phone whose system 24-hour
/// switch is off. It then took a typed "05" as 5 in the CURRENT half of the
/// day (17 from a 23:59 start) and refused 13–23. So when the locale's base
/// clock is 24-hour the flag is forced on, and the dial, the fields and the
/// parser agree. A 12-hour locale keeps the platform's value and its toggle.
/// The user's DISPLAY format (`dateFormatProvider`) is deliberately not
/// consulted: the picker's layout follows the locale either way.
Future<TimeOfDay?> awShowTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) {
      final media = MediaQuery.of(context);
      final base = MaterialLocalizations.of(
        context,
      ).timeOfDayFormat(alwaysUse24HourFormat: false);
      if (media.alwaysUse24HourFormat || hourFormat(of: base) == HourFormat.h) {
        return child!;
      }
      return MediaQuery(
        data: media.copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );
    },
  );
}

/// The DAY-only input (OPH-372, DESIGN §17 D5 as amended): "When" stores a
/// day, not an instant, so it asks for a day and nothing else — no clock step
/// whose value would be thrown away. Same bounds and opening rule as
/// [awPickDateTime] (an empty field opens on tomorrow, [awInitialPickerDate]).
///
/// Returns the chosen local day at 00:00, or null when the user backs out
/// ("no change" — the caller keeps what it had).
Future<DateTime?> awPickDate(
  BuildContext context, {
  DateTime? current,
  DateTime? anchor,
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final first = today.subtract(const Duration(days: 365));
  var initial = awInitialPickerDate(
    current: current,
    anchor: anchor,
    now: today,
  );
  // A "when" can sit further back than the picker reaches (a task planned
  // long ago and never done): open on the earliest day rather than assert.
  if (initial.isBefore(first)) initial = first;
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: today.add(const Duration(days: 365 * 5)),
  );
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}
