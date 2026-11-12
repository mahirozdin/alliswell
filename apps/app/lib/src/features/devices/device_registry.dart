import 'package:flutter/foundation.dart';

import '../../core/kv/local_kv.dart';
import '../../notifications/device_gate.dart';
import 'data/device_api.dart';

/// This device's cached "do urgent alarms ring here" (#48, OPH-446), in
/// LocalKv under [kRingsUrgentKey] so the headless pass can read it too.
class RingsUrgentStore {
  RingsUrgentStore({LocalKv? kv}) : _kv = kv ?? localKv;

  final LocalKv _kv;

  /// Bumped by every local decision about the flag (a switch change, its
  /// answer, a session hook), never by what a server listing reports.
  int _generation = 0;

  /// Taken just before asking the server for a listing (a heartbeat, the
  /// device list), and handed back to [writeObserved] with its answer.
  int get generation => _generation;

  Future<RingsUrgentHere> read() async =>
      ringsUrgentHereFromStored(await _kv.get(kRingsUrgentKey));

  /// A decision made here: a PATCH answer or a session hook. It wins over any
  /// listing asked for before it.
  Future<void> write(RingsUrgentHere here) {
    _generation++;
    return _kv.set(kRingsUrgentKey, here.name);
  }

  /// A switch change for this device is on its way to the server: whatever a
  /// listing already on the wire says about it is older than that change.
  void changeStarted() => _generation++;

  /// What a server listing said about this device, written only when no
  /// local decision came after it was asked for ([askedAt], a [generation]).
  /// A heartbeat that left before the person switched this device off
  /// answers with the old value, and must not switch it back on
  /// (late-heartbeat-overwrites-switch). Returns whether the stored answer
  /// changed.
  Future<bool> writeObserved(
    RingsUrgentHere here, {
    required int askedAt,
  }) async {
    if (askedAt != _generation) return false;
    final stored = await read();
    // Checked again after the read: the set below must follow the check with
    // no await in between.
    if (askedAt != _generation || stored == here) return false;
    await _kv.set(kRingsUrgentKey, here.name);
    return true;
  }

  /// Called with every session that is about to start, before it is exposed.
  ///
  /// A fresh sign-in, or a restored session whose person is not the one the
  /// install last held ([switchedAccount]), forgets the previous answer and
  /// writes [RingsUrgentHere.unknown] — written, not removed, so an app killed
  /// before the register response does not come back as legacy and ring. A
  /// plain restore keeps what is stored; with nothing stored (an install
  /// updated from before #48) that reads as legacy and rings as before.
  Future<void> onSessionUser({
    required bool restored,
    required bool switchedAccount,
  }) async {
    if (!restored || switchedAccount) await write(RingsUrgentHere.unknown);
  }
}

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
    this.ringsUrgent,
    this.onRingsUrgentChanged,
  });

  final DeviceApi api;

  /// Reads `sync_states.client_id` — `null` until the engine's first round.
  final Future<String?> Function() readClientId;

  /// What this install is, or `null` on a platform the route cannot name.
  final DeviceDescriptor? Function() describe;

  /// Where the register response's `ringsUrgent` is cached (OPH-446).
  final RingsUrgentStore? ringsUrgent;

  /// Told when that cached answer changed, so the alarm paths re-plan.
  final void Function()? onRingsUrgentChanged;

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
    final askedAt = ringsUrgent?.generation;
    final DeviceInfo? row;
    try {
      row = await api.register(deviceId, device);
      _registeredId = deviceId;
    } on Object {
      // Swallowed on purpose: a heartbeat is background work and the next one
      // is a few minutes away. Leaving `_registeredId` alone is what makes the
      // retry happen rather than being silently considered done. The cached
      // ringsUrgent stays as it was: a failure says nothing about it.
      return;
    }
    await _cacheRingsUrgent(row, askedAt);
  }

  /// The server's answer is the only thing that turns `unknown` into `on`.
  /// An answer without the field (an older server) is `legacy`: it rings as
  /// it did before #48. An answer older than a switch change made here since
  /// it was asked for is dropped ([RingsUrgentStore.writeObserved]).
  Future<void> _cacheRingsUrgent(DeviceInfo? row, int? askedAt) async {
    final store = ringsUrgent;
    if (store == null || askedAt == null) return;
    final next = ringsUrgentHereFromServer(row?.ringsUrgent);
    if (await store.writeObserved(next, askedAt: askedAt)) {
      onRingsUrgentChanged?.call();
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
