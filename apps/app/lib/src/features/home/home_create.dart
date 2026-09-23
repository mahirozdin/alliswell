import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persisted_prefs.dart';
import '../tasks/providers.dart';
import '../tasks/ui/task_create_sheet.dart';

/// Home's "new task": the FAB and the widget's "+" (`alliswell://add`,
/// OPH-333) — one entry, two doors.
///
/// It is one function so the two cannot drift: a day picked on the calendar
/// pre-fills the sheet at the user's default task time (OPH-161) whichever door
/// the person came through. The permission gate (EE-052) stays with each
/// caller, because the FAB HIDES itself while the link simply lands on Home.
Future<void> showHomeTaskCreateSheet(BuildContext context, WidgetRef ref) {
  final day = ref.read(selectedDayProvider);
  return showTaskCreateSheet(
    context,
    initialDue: day == null
        ? null
        : applyDefaultTaskTime(day, ref.read(defaultTaskTimeProvider)),
  );
}

/// The widget's "+" as a one-shot REQUEST (OPH-333).
///
/// The router turns `/home?add=1` into this flag and the location into plain
/// Home; `HomeScreen` consumes it when it is on screen. A flag rather than the
/// query parameter because a parameter did not survive the auth dance — see
/// the router's redirect for the measurement — and a flag simply waits.
class HomeCreateRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  /// Reads and clears in one step: one "+" opens at most one sheet.
  bool take() {
    final wanted = state;
    if (wanted) state = false;
    return wanted;
  }
}

final homeCreateRequestProvider = NotifierProvider<HomeCreateRequest, bool>(
  HomeCreateRequest.new,
);
