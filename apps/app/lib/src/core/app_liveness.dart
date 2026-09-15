import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kv/local_kv.dart';

/// Whether the app itself is awake right now, readable from a background
/// isolate (OPH-318).
///
/// ── WHY A STAMP AND NOT A LOCK ────────────────────────────────────────────
///
/// A background turn (the periodic refresh, OPH-321) exists to keep the local
/// schedule fresh while the app is NOT running. When the app is running it is
/// already doing that, continuously, and a second engine syncing the same
/// workspace into the same file at the same moment is pure risk for no gain.
/// WAL (`connection_native.dart`) makes that overlap survivable; this makes it
/// unnecessary, which is the cheaper of the two.
///
/// It is a stamp in `SharedPreferences` rather than a lock because a lock has
/// to be released, and the one case that matters — the OS killing a
/// foregrounded app — is exactly the case where nothing gets to release
/// anything.
///
/// ── AND WHY IT EXPIRES ────────────────────────────────────────────────────
///
/// The stamp is cleared when the app leaves the foreground, but a hard kill
/// clears nothing. An unbounded stamp would then disable background refresh
/// **forever**, silently, on the one device unlucky enough to be killed at the
/// wrong moment — a far worse failure than the one this prevents. So a stamp
/// older than [staleAfter] is treated as nobody's: the cost is at most one
/// redundant background sync during an uninterrupted foreground session, and
/// that sync is idempotent.
class AppLiveness {
  const AppLiveness(this._kv);

  final LocalKv _kv;

  static const _key = 'alliswell_foreground_since';

  /// How long a foreground stamp is believed without being renewed.
  static const staleAfter = Duration(hours: 1);

  /// The app is in front of the user. Called on every resume, so the stamp is
  /// renewed for as long as somebody keeps coming back to it.
  Future<void> markForeground(DateTime now) =>
      _kv.set(_key, now.toUtc().toIso8601String());

  /// The app went away. The stamp is removed rather than aged out, because a
  /// clean exit is the one moment we actually know the answer.
  Future<void> markBackground() => _kv.remove(_key);

  /// Should a background turn do nothing? True only when the app said it was
  /// in the foreground recently enough to still be believed.
  Future<bool> isForeground(DateTime now) async {
    final raw = await _kv.get(_key);
    if (raw == null) return false;
    final since = DateTime.tryParse(raw);
    // Unparsable is not "yes": a value we cannot read is a value we cannot act
    // on, and the safe direction here is to let the refresh run.
    if (since == null) return false;
    final age = now.toUtc().difference(since.toUtc());
    return !age.isNegative && age < staleAfter;
  }
}

/// The process-wide instance, on the same backend every other preference uses.
final appLiveness = AppLiveness(localKv);

/// Keeps the stamp honest for as long as the app is mounted. Watched once, at
/// the root — the listener has to exist whether or not anybody is signed in,
/// because "is the app running" is not a question about a session.
final appLivenessTrackerProvider = Provider<void>((ref) {
  final liveness = ref.watch(appLivenessProvider);
  // Mounted means in front of the user: `onResume` does not fire for the
  // launch that brought us here, only for returns to it.
  unawaited(liveness.markForeground(DateTime.now()));
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(liveness.markForeground(DateTime.now())),
    onPause: () => unawaited(liveness.markBackground()),
    onDetach: () => unawaited(liveness.markBackground()),
  );
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(liveness.markBackground());
  });
});

/// Overridden in tests with a fake [LocalKv].
final appLivenessProvider = Provider<AppLiveness>((ref) => appLiveness);
