import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../i18n/i18n.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import 'data/device_api.dart';
import 'device_registry.dart';

final deviceApiProvider = Provider<DeviceApi>(
  (ref) => HttpDeviceApi(ref.watch(apiClientProvider)),
);

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
  );
});

/// Deliberately NOT rebuilt by the session: it remembers which id it registered
/// so sign-out can delete that row, and a rebuild between the two would leave
/// the row behind.
final deviceRegistryProvider = Provider<DeviceRegistry>(
  (ref) => DeviceRegistry(
    api: ref.watch(deviceApiProvider),
    readClientId: () => ref.read(syncClientIdProvider.future),
    describe: () => ref.read(deviceDescriptorProvider),
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

  final registry = ref.watch(deviceRegistryProvider);
  unawaited(registry.sync(signedIn: true));

  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(registry.sync(signedIn: true)),
  );
  ref.onDispose(lifecycle.dispose);
});
