import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI preferences that survive restarts (feedback round 1): synchronous state
/// with a fallback, hydrated from SharedPreferences right after build and
/// written back on every change.
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
    try {
      final stored = (await SharedPreferences.getInstance()).getBool(prefKey);
      if (stored != null && stored != state) state = stored;
    } on Object {
      // Preferences unavailable (private mode, tests) — keep the fallback.
    }
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      await (await SharedPreferences.getInstance()).setBool(prefKey, value);
    } on Object {
      // Non-persistent session; the in-memory state still applies.
    }
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
    try {
      final stored = (await SharedPreferences.getInstance()).getString(prefKey);
      if (stored != null && stored != state) state = stored;
    } on Object {
      // Preferences unavailable (private mode, tests) — keep the fallback.
    }
  }

  Future<void> set(String value) async {
    state = value;
    try {
      await (await SharedPreferences.getInstance()).setString(prefKey, value);
    } on Object {
      // Non-persistent session; the in-memory state still applies.
    }
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
