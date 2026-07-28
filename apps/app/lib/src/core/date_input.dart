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
Future<DateTime?> awPickDateTime(
  BuildContext context,
  WidgetRef ref, {
  DateTime? current,
  DateTime? anchor,
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
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
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
