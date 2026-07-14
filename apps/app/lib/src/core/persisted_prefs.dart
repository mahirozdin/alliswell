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
