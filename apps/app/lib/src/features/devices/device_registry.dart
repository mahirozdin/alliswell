import 'package:flutter/foundation.dart';

import 'data/device_api.dart';

/// The platform name the registry route accepts, or `null` when this build is
/// running somewhere the server has no word for.
///
/// `null` rather than a nearest-neighbour guess. Fuchsia is a `TargetPlatform`
/// and not one of the route's six; calling it Linux would put a sentence into a
/// table that somebody later reads as fact, and the route would be right to
/// reject a seventh value. Not registering says the true thing.
String? awDevicePlatform({
  required bool isWeb,
  required TargetPlatform target,
}) {
  // Web first: the target platform under a browser is whatever the browser is
  // running on, which is not what the row is about.
  if (isWeb) return 'web';
  return switch (target) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => null,
  };
}

/// Keeps this install's row in `notification_devices` current (OPH-309).
///
/// ── WHY THIS EXISTS AT ALL ───────────────────────────────────────────────
///
/// The route has been correct and uncalled since 2026-07-15. EE measured it on
/// 2026-08-24 and wrote the finding down: the table is empty on every real
/// instance, so a push sender would find nobody to send to. Epic 30 rests on
/// this table — `last_seen_at` is the whole of the staleness test that decides
/// which devices get a push — and `last_seen_at` only means anything if
/// something keeps it fresh.
///
/// ── THE ID IS NOT OURS TO MINT ───────────────────────────────────────────
///
/// The device id is the sync client id, which the sync engine creates in
/// `sync_states` on its first round. A fresh install has none yet, and the
/// answer is to wait: minting one here would put a second row in the table that
/// never goes away, for the same install.
///
/// ── AND FAILURE IS NEVER FATAL ───────────────────────────────────────────
///
/// A registration that fails is not recorded as done, so the next heartbeat
/// retries it — being offline at launch must not mean this device never
/// registers. A sign-out that cannot reach the server still signs out: the
/// route answers 204 to a repeated or foreign delete precisely so that this
/// path can be best-effort.
class DeviceRegistry {
  DeviceRegistry({
    required this.api,
    required this.readClientId,
    required this.describe,
  });

  final DeviceApi api;

  /// Reads `sync_states.client_id` — `null` until the engine's first round.
  final Future<String?> Function() readClientId;

  /// What this install is, or `null` on a platform the route cannot name.
  final DeviceDescriptor? Function() describe;

  /// The id this registry actually got a row for — what sign-out deletes.
  String? _registeredId;

  /// Register or heartbeat. Called when the session appears and again whenever
  /// the app comes back to the foreground.
  Future<void> sync({required bool signedIn}) async {
    if (!signedIn) return;
    final device = describe();
    if (device == null) return;
    final deviceId = await readClientId();
    if (deviceId == null) return;
    try {
      await api.register(deviceId, device);
      _registeredId = deviceId;
    } on Object {
      // Swallowed on purpose: a heartbeat is background work and the next one
      // is a few minutes away. Leaving `_registeredId` alone is what makes the
      // retry happen rather than being silently considered done.
    }
  }

  /// Take this device off the list, before the token that could do it is gone.
  Future<void> signOut() async {
    final deviceId = _registeredId;
    if (deviceId == null) return;
    try {
      await api.unregister(deviceId);
    } on Object {
      // A sign-out is a local-state guarantee (OPH-100's rule, same shape).
      // The row is stale rather than wrong: it belongs to whoever signs in on
      // this install next, and the route hands it over when they do.
    }
    _registeredId = null;
  }
}
