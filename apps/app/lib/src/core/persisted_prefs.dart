import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kv/local_kv.dart';

/// UI preferences that survive restarts (feedback round 1): synchronous state
/// with a fallback, hydrated from [localKv] right after build and written
/// back on every change. [LocalKv] guarantees the calls never hang or throw.
class PersistedToggle extends Notifier<bool> {
  PersistedToggle(this.prefKey, {required this.fallback});

  final String prefKey;
  final bool fallback;

  @override
  bool build() {
    _hydrate();
    return fallback;
  }

  Future<void> _hydrate() async {
    final stored = await localKv.get(prefKey);
    if (stored != null && (stored == 'true') != state) {
      state = stored == 'true';
    }
  }

  Future<void> set(bool value) async {
    state = value;
    await localKv.set(prefKey, '$value');
  }

  Future<void> toggle() => set(!state);
}

class PersistedChoice extends Notifier<String> {
  PersistedChoice(this.prefKey, {required this.fallback});

  final String prefKey;
  final String fallback;

  @override
  String build() {
    _hydrate();
    return fallback;
  }

  Future<void> _hydrate() async {
    final stored = await localKv.get(prefKey);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(String value) async {
    state = value;
    await localKv.set(prefKey, value);
  }
}

/// Mobile home screen: is the month calendar expanded? (`Hide calendar`.)
final homeCalendarVisibleProvider = NotifierProvider<PersistedToggle, bool>(
  () => PersistedToggle('alliswell_home_calendar_visible', fallback: true),
);

/// Notes screen view mode: 'list' or 'grid'.
final notesViewModeProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_notes_view_mode', fallback: 'list'),
);

/// Home's view: 'list' (the chronological flow, default) or 'board' (the
/// status-column kanban — round 8, OPH-168 / DESIGN §14 K1).
final homeViewProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_home_view', fallback: 'list'),
);

/// Board columns, ordered; stored as a comma-joined status list (K2). Only
/// statuses present here render as columns — the user hides/reorders in the
/// "Görünümü düzenle" sheet. Hidden statuses stay reachable as MOVE targets.
final boardColumnsProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice(
    'alliswell_board_columns',
    fallback: 'open,in_progress,waiting,completed',
  ),
);

/// Parsed [boardColumnsProvider] value → ordered visible statuses, tolerating
/// junk (unknown names dropped; empty → the factory default set).
List<String> parseBoardColumns(String value, List<String> allStatuses) {
  final parsed = [
    for (final part in value.split(','))
      if (allStatuses.contains(part.trim())) part.trim(),
  ];
  return parsed.isEmpty
      ? const ['open', 'in_progress', 'waiting', 'completed']
      : parsed;
}

/// The time-of-day a task lands on when the user picked only a DAY
/// (round 8, OPH-161 — quick-add on a selected day, FAB prefill, date-picker
/// fallbacks). Stored as 'HH:mm'. The factory default is 23:59 — "due by the
/// end of that day" — because the old fixed 09:00 turned every day-only task
/// into an early-morning deadline. User-changeable in Settings.
final defaultTaskTimeProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_default_task_time', fallback: '23:59'),
);

/// 'HH:mm' → (hour, minute), falling back to 23:59 on junk — a corrupted
/// preference must never crash task creation.
(int, int) parseTaskTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return (23, 59);
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return (23, 59);
  return (hour, minute);
}

/// [day]'s date at the user's default task time ('HH:mm', see
/// [defaultTaskTimeProvider]). Keeps [day]'s calendar date untouched.
DateTime applyDefaultTaskTime(DateTime day, String hhmm) {
  final (hour, minute) = parseTaskTime(hhmm);
  return DateTime(day.year, day.month, day.day, hour, minute);
}
