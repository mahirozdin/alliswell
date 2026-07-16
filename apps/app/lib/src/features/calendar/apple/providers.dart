import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
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
  );
});

/// Keeps EventKit in step with the replica (OPH-078). Watches the open-task
/// stream — which emits on both local writes and pulls — and reconciles the
/// whole set each time; the engine's signature guard makes an unchanged pass a
/// batch of cheap no-ops. Only active once access is granted AND a calendar is
/// chosen, so it never prompts on its own or writes nowhere.
///
/// This is the device-side analogue of the server's post-commit mirror queue;
/// there is no server for Apple, so the app itself is the worker.
final appleMirrorProvider = Provider<void>((ref) {
  final access = ref.watch(appleAccessProvider).value;
  final calendarId = ref.watch(appleCalendarIdProvider);
  if (access == null || !access.canMirror || calendarId.isEmpty) return;

  final engine = ref.watch(appleMirrorEngineProvider);
  final sub = ref.listen(openTasksProvider, (_, next) {
    final tasks = next.value;
    if (tasks != null) unawaited(engine.reconcileAll(tasks));
  }, fireImmediately: true);
  ref.onDispose(sub.close);
});
