import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/app_version.dart';
import '../../core/firebase/push_messaging.dart';
import '../../i18n/i18n.dart';
import '../../notifications/device_gate.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart' show currentUserIdProvider;
import 'data/device_api.dart';
import 'device_registry.dart';

final deviceApiProvider = Provider<DeviceApi>(
  (ref) => HttpDeviceApi(ref.watch(apiClientProvider)),
);

/// What the instance said about browser push. Read once per session: a server
/// does not grow keys while a tab is open.
final pushKeyLookupProvider = FutureProvider<PushKeyLookup>(
  (ref) => ref.watch(deviceApiProvider).lookupPushKey(),
);

/// The instance's VAPID public key, or null when this server does not do push
/// (or could not be asked).
final pushPublicKeyProvider = FutureProvider<String?>(
  (ref) async => (await ref.watch(pushKeyLookupProvider.future)).key,
);

/// Whether the server does browser push: false only on its 404, null when it
/// could not be asked (OPH-393).
final pushServerConfiguredProvider = FutureProvider<bool?>(
  (ref) async => (await ref.watch(pushKeyLookupProvider.future)).configured,
);

/// How a sender can reach this install, once something has subscribed.
///
/// Written by the notification gateway (OPH-313) rather than read from it:
/// the descriptor is what the registry sends, and having it reach INTO the
/// notification layer would point the dependency the wrong way round.
class DevicePushCredentialsHolder extends Notifier<DevicePushCredentials?> {
  @override
  DevicePushCredentials? build() => null;

  void set(DevicePushCredentials? credentials) => state = credentials;
}

final devicePushCredentialsProvider =
    NotifierProvider<DevicePushCredentialsHolder, DevicePushCredentials?>(
      DevicePushCredentialsHolder.new,
    );

/// The FCM plugin behind an object tests can replace.
final pushMessagingProvider = Provider<AwPushMessaging>(
  (ref) => AwPushMessaging(),
);

/// Puts this install's FCM token where the registry will find it (OPH-319).
///
/// Watched, not awaited, and silent when there is nothing to fetch: a build
/// with no Firebase config, or a browser (which is reached with VAPID
/// instead), simply never writes any credentials and the heartbeat carries
/// none — the route reads key PRESENCE, so an absent token leaves whatever is
/// stored alone rather than clearing it.
///
/// The REFRESH is the reason this is a subscription rather than one call: the
/// SDK rotates a token on a device restore or an app-data clear, and a
/// rotation nobody wrote down is a device the server keeps sending to and
/// never reaches again.
final pushTokenProvider = Provider<void>((ref) {
  final messaging = ref.watch(pushMessagingProvider);
  if (!messaging.isAvailable) return;

  void publish(String token) => ref
      .read(devicePushCredentialsProvider.notifier)
      .set(DevicePushCredentials.fcm(token));

  unawaited(
    messaging.token().then((token) {
      if (token != null) publish(token);
    }),
  );

  final refreshes = messaging.tokenRefreshes.listen(publish);
  ref.onDispose(refreshes.cancel);
});

/// What this install is, or `null` on a platform the route has no word for.
final deviceDescriptorProvider = Provider<DeviceDescriptor?>((ref) {
  final platform = awDevicePlatform(
    isWeb: kIsWeb,
    target: defaultTargetPlatform,
  );
  if (platform == null) return null;
  return DeviceDescriptor(
    platform: platform,
    appVersion: ref.watch(appVersionProvider),
    // The device's language, not the account's — read live so a language change
    // reaches the row on the next heartbeat.
    locale: AwI18n.instance.locale.toLanguageTag(),
    push: ref.watch(devicePushCredentialsProvider),
  );
});

/// This device's cached ringsUrgent (OPH-446) — LocalKv-backed, so a test
/// can hand it its own store.
final ringsUrgentStoreProvider = Provider<RingsUrgentStore>(
  (_) => RingsUrgentStore(),
);

/// Whether urgent alarms ring on this device (#48). Re-read whenever the
/// session hook or a register response changes the stored answer; the alarm
/// paths apply it through `forThisDevice`.
final ringsUrgentHereProvider = FutureProvider<RingsUrgentHere>(
  (ref) => ref.watch(ringsUrgentStoreProvider).read(),
);

/// Deliberately NOT rebuilt by the session: it remembers which id it registered
/// so sign-out can delete that row, and a rebuild between the two would leave
/// the row behind.
final deviceRegistryProvider = Provider<DeviceRegistry>(
  (ref) => DeviceRegistry(
    api: ref.watch(deviceApiProvider),
    readClientId: () => ref.read(syncClientIdProvider.future),
    describe: () => ref.read(deviceDescriptorProvider),
    ringsUrgent: ref.watch(ringsUrgentStoreProvider),
    onRingsUrgentChanged: () => ref.invalidate(ringsUrgentHereProvider),
  ),
);

/// Keeps this install's row fresh while the shell is up (OPH-309).
///
/// Two triggers, both cheap: the moment a session and a sync client id both
/// exist, and every return to the foreground. `last_seen_at` is the whole of
/// Epic 30's staleness test — a device that has not been heard from since a
/// reminder changed is the one that gets pushed to — so the heartbeat is not
/// bookkeeping, it is the measurement.
final deviceRegistrationProvider = Provider<void>((ref) {
  final signedIn = ref.watch(authControllerProvider).value != null;
  // Watched, not read: a fresh install has no client id until the sync engine's
  // first round, and this is what makes the registration happen when it lands.
  final clientId = ref.watch(syncClientIdProvider).value;
  if (!signedIn || clientId == null) return;

  // The token has to exist before the heartbeat that carries it, and both
  // want the same trigger: a session.
  ref.watch(pushTokenProvider);

  final registry = ref.watch(deviceRegistryProvider);
  unawaited(registry.sync(signedIn: true));

  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(registry.sync(signedIn: true)),
  );
  ref.onDispose(lifecycle.dispose);
});

/// What Settings ▸ Devices shows (#48, OPH-448): the person's devices as the
/// server listed them, whether that list is the last one seen rather than a
/// fresh one ([offline]), and which rows have a switch change in flight.
@immutable
class DevicesView {
  const DevicesView({
    required this.devices,
    this.offline = false,
    this.saving = const {},
  });

  final List<DeviceInfo> devices;

  /// The server could not be reached; [devices] is the last list this session
  /// saw. Ring switches are a server setting and are not queued, so they are
  /// inactive until it answers again.
  final bool offline;

  /// Device ids whose ring switch is waiting for the server.
  final Set<String> saving;

  /// Whether the server knows `ringsUrgent` at all — an older one sends no
  /// such field, and then every device rings as before #48.
  bool get supportsRingsUrgent =>
      devices.isNotEmpty && devices.every((d) => d.ringsUrgent != null);

  List<DeviceInfo> get ringing => [
    for (final device in devices)
      if (device.ringsUrgent == true) device,
  ];

  DeviceInfo? byId(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  DevicesView _with(DeviceInfo device, {required bool saving}) => DevicesView(
    devices: [for (final d in devices) d.id == device.id ? device : d],
    offline: offline,
    saving: {
      for (final id in this.saving)
        if (id != device.id) id,
      if (saving) device.id,
    },
  );
}

/// What removing a device left behind (OPH-449).
@immutable
class DeviceRemoval {
  const DeviceRemoval({
    required this.removed,
    required this.devices,
    required this.needsPick,
  });

  final DeviceInfo removed;

  /// The list as the server holds it after the removal (its promotion
  /// included).
  final List<DeviceInfo> devices;

  /// The removed device was the only one ringing: the person is asked where
  /// urgent alarms ring now, so they never go quiet unnoticed.
  final bool needsPick;
}

/// The last list this session saw, per person, for [DevicesView.offline].
/// Memory only: device names are not worth a copy on disk that sign-out would
/// then have to remember to remove.
class _DevicesCache {
  String? userId;
  List<DeviceInfo>? devices;
}

final _devicesCacheProvider = Provider<_DevicesCache>((_) => _DevicesCache());

/// Re-reads [ringsUrgentHereProvider]; kept alive so a save that lands after
/// the Devices screen closed still reaches the alarm gate.
final _ringsUrgentChangedProvider = Provider<void Function()>(
  (ref) =>
      () => ref.invalidate(ringsUrgentHereProvider),
);

/// The person's devices (`GET /api/v1/notification-devices`), loaded each
/// time a screen that shows them opens.
///
/// No automatic retry: the screen offers its own, and an offline answer comes
/// back at once from the last list instead of after a backoff.
final devicesProvider =
    AsyncNotifierProvider.autoDispose<DevicesController, DevicesView>(
      DevicesController.new,
      retry: (_, _) => null,
    );

class DevicesController extends AsyncNotifier<DevicesView> {
  @override
  Future<DevicesView> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const DevicesView(devices: []);
    final cache = ref.read(_devicesCacheProvider);
    try {
      final devices = await ref.read(deviceApiProvider).list();
      cache
        ..userId = userId
        ..devices = devices;
      return DevicesView(devices: devices);
    } on Object catch (error) {
      final cached = cache.userId == userId ? cache.devices : null;
      if (cached != null && _unreachable(error)) {
        return DevicesView(devices: cached, offline: true);
      }
      if (error is DioException) throw asApiException(error);
      rethrow;
    }
  }

  /// Turns urgent ringing on or off for one device.
  ///
  /// Optimistic: the row shows [ringsUrgent] at once and is marked saving. On
  /// a failure it goes back to what it was and this returns null, so the
  /// screen can say so. When the row is THIS device, the server's answer is
  /// also cached for the alarm gate (OPH-446) — only the answer, never the
  /// optimistic guess.
  Future<DevicePatchResult?> setRingsUrgent(
    String deviceId,
    bool ringsUrgent,
  ) async {
    final current = state.value;
    if (current == null || current.offline) return null;
    if (current.saving.contains(deviceId)) return null;
    final before = current.byId(deviceId);
    if (before == null) return null;

    final api = ref.read(deviceApiProvider);
    final store = ref.read(ringsUrgentStoreProvider);
    final thisId = ref.read(syncClientIdProvider).value;
    final cache = ref.read(_devicesCacheProvider);
    final gateChanged = ref.read(_ringsUrgentChangedProvider);
    state = AsyncData(
      current._with(_withRings(before, ringsUrgent), saving: true),
    );

    final DevicePatchResult result;
    try {
      result = await api.patch(deviceId, ringsUrgent: ringsUrgent);
    } on Object {
      if (ref.mounted) _settle(before);
      return null;
    }
    final after = _merged(before, result.device, ringsUrgent);
    if (deviceId == thisId) {
      await store.write(ringsUrgentHereFromServer(after.ringsUrgent));
      // Through a provider that outlives this screen: the gate must hear
      // about it even when the person has already left.
      gateChanged();
    }
    final cached = cache.devices;
    if (cached != null) {
      cache.devices = [for (final d in cached) d.id == deviceId ? after : d];
    }
    if (ref.mounted) _settle(after);
    return result;
  }

  /// Renames one device (`PATCH … {deviceName}`). Returns whether the server
  /// took it; the row shows the new name only once it did.
  Future<bool> rename(String deviceId, String name) async {
    final current = state.value;
    if (current == null || current.offline) return false;
    final before = current.byId(deviceId);
    if (before == null) return false;
    final api = ref.read(deviceApiProvider);
    final cache = ref.read(_devicesCacheProvider);
    final DevicePatchResult result;
    try {
      result = await api.patch(deviceId, deviceName: name);
    } on Object {
      return false;
    }
    final fresh = result.device;
    final after = _merged(
      before,
      DeviceInfo(
        id: fresh.id,
        platform: fresh.platform,
        name: fresh.name ?? name,
        appVersion: fresh.appVersion,
        lastSeenAt: fresh.lastSeenAt,
        createdAt: fresh.createdAt,
        ringsUrgent: fresh.ringsUrgent,
        ringsUrgentSource: fresh.ringsUrgentSource,
      ),
      before.ringsUrgent,
    );
    final cached = cache.devices;
    if (cached != null) {
      cache.devices = [for (final d in cached) d.id == deviceId ? after : d];
    }
    if (ref.mounted) _settle(after);
    return true;
  }

  /// Removes another device: `DELETE /api/v1/notification-devices/:id`,
  /// which also revokes that device's session (ADR-0069 §6) and, when it was
  /// the last ringing one, promotes another. The list is read again so the
  /// promotion shows; this device's alarm gate follows it at once.
  ///
  /// Null when the server could not be told; nothing changes then.
  Future<DeviceRemoval?> remove(String deviceId) async {
    final current = state.value;
    if (current == null || current.offline) return null;
    final before = current.byId(deviceId);
    if (before == null) return null;
    final lastRinging =
        before.ringsUrgent == true && current.ringing.length == 1;

    final api = ref.read(deviceApiProvider);
    final store = ref.read(ringsUrgentStoreProvider);
    final thisId = ref.read(syncClientIdProvider).value;
    final cache = ref.read(_devicesCacheProvider);
    final gateChanged = ref.read(_ringsUrgentChangedProvider);
    try {
      await api.unregister(deviceId);
    } on Object {
      return null;
    }
    List<DeviceInfo> fresh;
    try {
      fresh = await api.list();
    } on Object {
      fresh = current.devices;
    }
    fresh = [
      for (final d in fresh)
        if (d.id != deviceId) d,
    ];
    if (cache.devices != null) cache.devices = fresh;
    if (thisId != null) {
      final self = fresh.where((d) => d.id == thisId).firstOrNull;
      final rings = self?.ringsUrgent;
      if (rings != null && rings != current.byId(thisId)?.ringsUrgent) {
        await store.write(ringsUrgentHereFromServer(rings));
        gateChanged();
      }
    }
    if (ref.mounted) state = AsyncData(DevicesView(devices: fresh));
    return DeviceRemoval(
      removed: before,
      devices: fresh,
      needsPick: lastRinging && fresh.isNotEmpty,
    );
  }

  /// Makes [deviceId] the one device that rings (the pick page): it is
  /// switched on first and every other ringing device off after, so there is
  /// no moment with none. Returns whether every change was saved.
  Future<bool> ringOnlyOn(String deviceId) async {
    final current = state.value;
    if (current == null) return false;
    final target = current.byId(deviceId);
    if (target == null) return false;
    if (target.ringsUrgent != true) {
      if (await setRingsUrgent(deviceId, true) == null) return false;
    }
    for (final other in current.ringing) {
      if (other.id == deviceId) continue;
      if (await setRingsUrgent(other.id, false) == null) return false;
    }
    return true;
  }

  void _settle(DeviceInfo device) {
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(latest._with(device, saving: false));
  }

  static bool _unreachable(Object error) => switch (error) {
    DioException() => error.response == null,
    ApiException(code: 'NETWORK_ERROR') => true,
    _ => false,
  };

  static DeviceInfo _withRings(DeviceInfo device, bool? ringsUrgent) =>
      DeviceInfo(
        id: device.id,
        platform: device.platform,
        name: device.name,
        appVersion: device.appVersion,
        lastSeenAt: device.lastSeenAt,
        createdAt: device.createdAt,
        ringsUrgent: ringsUrgent,
        ringsUrgentSource: device.ringsUrgentSource,
        hasSession: device.hasSession,
      );

  /// The PATCH answer, minus what only GET says (`hasSession`) and with the
  /// requested value when the answer leaves the flag out.
  static DeviceInfo _merged(DeviceInfo before, DeviceInfo fresh, bool? asked) =>
      DeviceInfo(
        id: before.id,
        platform: fresh.platform.isEmpty ? before.platform : fresh.platform,
        name: fresh.name ?? before.name,
        appVersion: fresh.appVersion ?? before.appVersion,
        lastSeenAt: fresh.lastSeenAt ?? before.lastSeenAt,
        createdAt: fresh.createdAt ?? before.createdAt,
        ringsUrgent: fresh.ringsUrgent ?? asked,
        ringsUrgentSource: fresh.ringsUrgentSource ?? before.ringsUrgentSource,
        hasSession: before.hasSession,
      );
}
