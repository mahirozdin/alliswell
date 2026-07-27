import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/files/providers.dart';
import '../notifications/providers.dart';
import '../sections.dart';
import 'providers.dart';

/// What a pull-to-refresh actually does (DESIGN §15 R3): converge the replica
/// with the server, plus whatever [section] shows that the replica does not
/// own. It never re-mounts a list, scrolls it, or clears a filter or search.
///
/// Returns false when the user should be told it did not work (R4) — signed out
/// counts as "nothing to do", not as a failure.
Future<bool> refreshSection(WidgetRef ref, AppSection section) async {
  final engine = ref.read(syncEngineProvider);
  var ok = engine == null || await engine.syncNow();

  switch (section) {
    case AppSection.home:
      // Alarm delivery is an OS fact, not a replica fact, and the user may have
      // just come back from the permission screen — Home is where we admit it
      // (`AlarmDegradationBanner`), so re-probe while we are here. Calendar
      // events need nothing: they are a pull-only sync entity (ADR-0008) and
      // the round above already brought them.
      ref.invalidate(alarmSupportProvider);
    case AppSection.files:
      // Whether object storage is configured is the server's answer, not ours.
      ref.invalidate(storageStatusProvider);
      try {
        await ref.read(storageStatusProvider.future);
      } catch (_) {
        ok = false;
      }
    case AppSection.inbox || AppSection.projects || AppSection.notes:
      break; // the replica is the whole truth here
  }
  return ok;
}
