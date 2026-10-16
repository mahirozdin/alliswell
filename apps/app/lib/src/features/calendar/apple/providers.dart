import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../tasks/data/task.dart';
import '../../tasks/providers.dart';
import '../../../sync/providers.dart';
import 'apple_calendar_gateway.dart';
import 'apple_mirror_engine.dart';

/// The OS bridge. Widget tests override this with a fake — the default touches
/// platform channels (and answers `restricted` off Apple platforms).
final appleCalendarGatewayProvider = Provider<AppleCalendarGateway>(
  (_) => const EventKitCalendarGateway(),
);

/// The device's current EventKit permission — cheap, prompts nothing.
final appleAccessProvider = FutureProvider<EventKitAccess>(
  (ref) => ref.watch(appleCalendarGatewayProvider).status(),
);

/// Which Apple calendar to mirror INTO, persisted per device (empty = none
/// chosen yet). Not synced: it names a calendar that exists only on this
/// device.
final appleCalendarIdProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('apple_calendar_id', fallback: ''),
);

final appleEventLinkStoreProvider = Provider<AppleEventLinkStore>(
  (ref) => AppleEventLinkStore(ref.watch(databaseProvider)),
);

final appleMirrorEngineProvider = Provider<AppleMirrorEngine>((ref) {
  final chosen = ref.watch(appleCalendarIdProvider);
  return AppleMirrorEngine(
    gateway: ref.watch(appleCalendarGatewayProvider),
    links: ref.watch(appleEventLinkStoreProvider),
    calendarId: chosen.isEmpty ? null : chosen,
    // OPH-369: a drag in Apple Calendar lands where a drag in Google does —
    // the scheduled block — through the store, so it is an ordinary local
    // write (replica row + outbox) that the server then mirrors to Google.
    writeTaskTimes: (taskId, start, end) =>
        ref.read(taskStoreProvider).update(taskId, {
          'scheduledStartAt': start.toUtc().toIso8601String(),
          'scheduledEndAt': end.toUtc().toIso8601String(),
        }),
  );
});

/// Keeps EventKit in step with the replica (OPH-078), both ways (OPH-369).
/// Watches the open-task stream — which emits on both local writes and pulls —
/// and reconciles the whole set each time; the engine's signature guard makes
/// an unchanged pass a batch of cheap no-ops, and its queue keeps passes from
/// overlapping. Only active once access is granted AND a calendar is chosen,
/// so it never prompts on its own or writes nowhere.
///
/// Read-back (ADR-0050) runs on the first pass and on every return to the
/// foreground — on a Mac, when the window becomes active again after the user
/// dragged an event in Calendar.app. EventKit has no push to wait for.
///
/// This is the device-side analogue of the server's post-commit mirror queue;
/// there is no server for Apple, so the app itself is the worker.
final appleMirrorProvider = Provider<void>((ref) {
  final access = ref.watch(appleAccessProvider).value;
  final calendarId = ref.watch(appleCalendarIdProvider);
  if (access == null || !access.canMirror || calendarId.isEmpty) return;

  final engine = ref.watch(appleMirrorEngineProvider);
  List<Task>? latest;
  var readBackDone = false;
  final sub = ref.listen(openTasksProvider, (_, next) {
    final tasks = next.value;
    if (tasks == null) return;
    latest = tasks;
    final readBack = !readBackDone;
    readBackDone = true;
    unawaited(engine.sync(tasks, readBack: readBack));
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final tasks = latest;
      if (tasks != null) unawaited(engine.sync(tasks, readBack: true));
    },
  );
  ref.onDispose(() {
    sub.close();
    lifecycle.dispose();
  });
});
