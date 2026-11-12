import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../core/reachability.dart';
import '../../core/server_url.dart';
import '../../notifications/alarmkit.dart' show AlarmKitHost;
import '../../notifications/device_gate.dart';
import '../../notifications/gateway.dart' show NotificationsGateway;
import '../../notifications/os_alarms.dart';
import '../../notifications/providers.dart';
import '../../notifications/web/alert_cache.dart';
import '../../sync/local_data.dart';
import '../../sync/providers.dart';
import '../devices/providers.dart';
import 'data/auth_api.dart';
import 'data/auth_interceptor.dart';
import 'data/auth_repository.dart';
import 'data/social_sign_in.dart';
import 'data/models.dart';
import 'data/secret_store.dart';
import 'data/secure_secret_store.dart';
import 'data/token_storage.dart';

// Where the API lives now belongs to core/server_url.dart: the address is a
// user-changeable setting (self-hosting), not a compile-time constant. Re-export
// it so the many `ref.watch(apiBaseUrlProvider)` call sites keep working.
export '../../core/server_url.dart' show apiBaseUrlProvider;

/// Platform secret storage (OPH-025): Keychain/Keystore-backed on
/// mobile/desktop, in-memory on web (see secure_secret_store.dart).
/// Tests override this with a seeded [InMemorySecretStore].
final secretStoreProvider = Provider<SecretStore>((_) => defaultSecretStore());

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secretStoreProvider)),
);

/// Bare client for the auth endpoints themselves (no interceptor — the
/// interceptor's refresh path must not recurse through itself).
final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(Dio(BaseOptions(baseUrl: ref.watch(apiBaseUrlProvider)))),
);

/// The replica and the person's small facts belong to one person (OPH-355):
/// wiped at sign-out, and wiped at sign-in when they were somebody else's.
final localDataGuardProvider = Provider<LocalDataGuard>(
  (ref) => LocalDataGuard(
    database: () => ref.read(databaseProvider),
    clearAlerts: () => createAlertCache().clear(),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = AuthRepository(
    api: ref.watch(authApiProvider),
    storage: ref.watch(tokenStorageProvider),
    onSessionUser: (userId, {required restored}) async {
      // Read before the claim records the new owner: a restored session of
      // somebody else is an account switch for the device gate (OPH-446).
      final owner = await localKv.get(kReplicaOwnerKey);
      await ref
          .read(localDataGuardProvider)
          .claimFor(userId, restored: restored);
      await ref
          .read(ringsUrgentStoreProvider)
          .onSessionUser(
            restored: restored,
            switchedAccount: owner != null && owner != userId,
          );
      ref.invalidate(ringsUrgentHereProvider);
    },
    deviceId: () => _deviceIdForAuth(ref),
    onSessionRevoked: (userId, {required replaced}) =>
        _endRevokedSession(ref, userId, replaced: replaced),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The id a sign-in or refresh names this install by (OPH-447, #48): the
/// sync client id — the same id the device registry registers under — or
/// null.
///
/// Only once this server has shown it knows #48: a stored `ringsUrgent` that
/// is not [RingsUrgentHere.legacy] came from a register response carrying the
/// field. A server from before it validates auth bodies strictly; the API
/// client retries without the field on that 400 anyway, this just spares the
/// round trip. Bounded and never throwing: a sign-in does not wait on the
/// replica.
Future<String?> _deviceIdForAuth(Ref ref) async {
  try {
    final here = await ref.read(ringsUrgentStoreProvider).read();
    if (here == RingsUrgentHere.legacy) return null;
    // Listened, not read: an unlistened stream provider is paused and would
    // never deliver its first value.
    final clientId = ref.listen(syncClientIdProvider.future, (_, _) {});
    try {
      return await clientId.read().timeout(const Duration(seconds: 2));
    } finally {
      clientId.close();
    }
  } on Object {
    return null;
  }
}

/// A session family the server refused as revoked or reused (OPH-447): the
/// device was removed on another device, a password changed, or the family
/// was burned. The session is already gone; this does what an explicit
/// sign-out does with what the person left here — the push token, the
/// replica and their facts — and also takes their alarms out of the OS,
/// which no scheduler will ever reconcile again for this install.
///
/// The device row needs no delete: the server dropped it with the family,
/// and the token that could delete it is dead.
///
/// Never a silent loss (OPH-355): a sign-out asks before it deletes unsent
/// changes, and nobody is asked here. So with an outbox (or refused writes
/// kept for the person) the replica stays: the same person signing in again
/// adopts it and the outbox goes out (`LocalDataGuard.claimFor`); anybody
/// else signing in wipes it first. A count that cannot be read is treated as
/// unsent work.
///
/// For [userId]'s session only (revocation-cleanup-crosses-sessions): the
/// repository holds the next session's start until this returns, and the
/// replica is wiped only while it is still recorded as [userId]'s (or as
/// nobody's).
///
/// [replaced] — a sign-in that was under way when the refusal came runs this
/// before it exposes its session, and its own `claimFor` decides the replica:
/// it adopts it for the same person, or wipes it for somebody else while
/// carrying over the client id that sign-in already sent. Wiping here first
/// would discard that id (signin-binds-discarded-client-id), so the replica is
/// left to it; the token, the engines and the OS alarms go as always.
Future<void> _endRevokedSession(
  Ref ref,
  String userId, {
  required bool replaced,
}) async {
  try {
    await ref.read(pushMessagingProvider).forgetToken();
  } on Object {
    // Best effort, as on a sign-out.
  }
  await _haltSyncEngines(ref);
  final owner = await localKv.get(kReplicaOwnerKey);
  if (!replaced &&
      (owner == null || owner == userId) &&
      await _nothingUnsent(ref)) {
    await ref.read(localDataGuardProvider).wipe();
  }
  await _dropOsAlarms(ref);
}

Future<bool> _nothingUnsent(Ref ref) async {
  try {
    return await unsentChangeCount(ref.read(databaseProvider)) == 0;
  } on Object {
    return false;
  }
}

/// Every engine stops and finishes the round it is in, so no pull lands on
/// the replica after a wipe. Bounded: a request hanging on a dead network must
/// not hold the sign-out — a stopped engine drops the page that answers late
/// instead of applying it (`SyncEngine._pullAll`).
///
/// Through the registry, never `syncEnginesProvider` (OPH-390, E-01): the
/// engines hang off the session, so reading them from here is a dependency
/// loop — Riverpod threw on it and the sign-out never ran.
Future<void> _haltSyncEngines(Ref ref) async {
  final engines = ref.read(runningSyncEnginesProvider).toList();
  if (engines.isEmpty) return;
  await Future.wait([
    for (final engine in engines) engine.halt(),
  ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
}

/// Cancels every notification and AlarmKit alarm this install still holds in
/// the OS, the presented ones included ([dropEveryOsAlarm]). Not on the web,
/// where the alert cache the wipe clears is the whole schedule.
Future<void> _dropOsAlarms(Ref ref) async {
  if (kIsWeb) return;
  NotificationsGateway gateway;
  AlarmKitHost? alarmKit;
  try {
    gateway = ref.read(notificationsGatewayProvider);
  } on Object {
    return;
  }
  try {
    alarmKit = ref.read(alarmKitHostProvider);
  } on Object {
    alarmKit = null;
  }
  await dropEveryOsAlarm(gateway: gateway, alarmKit: alarmKit);
}

/// Authenticated dio for every feature API (tasks, projects, /me, …):
/// attaches the access token and transparently refreshes it once on a 401.
final apiClientProvider = Provider<Dio>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final dio = Dio(BaseOptions(baseUrl: ref.watch(apiBaseUrlProvider)));
  // OPH-342: first, so it sees every raw answer and every "no answer" before
  // the auth layer retries or rewrites anything.
  dio.interceptors.add(
    ReachabilityInterceptor(ref.read(serverReachabilityProvider.notifier)),
  );
  dio.interceptors.add(
    AuthInterceptor(
      getAccessToken: () => repository.accessToken,
      refreshAccessToken: repository.refreshAccessToken,
    ),
  );
  return dio;
});

/// App-wide auth state: `null` data = signed out, loading = restoring the
/// persisted session at startup.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final repository = ref.watch(authRepositoryProvider);
    // Mirror every repository-side change (rotation, forced sign-out on a
    // failed refresh, logout) into the exposed state.
    final sub = repository.sessionChanges.listen(
      (session) => state = AsyncData(session),
    );
    ref.onDispose(sub.cancel);
    // Storage must never brick startup: a hanging backend degrades to
    // signed-out instead of an eternal splash (feedback round 1, item 2).
    return repository.restore().timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
  }

  /// Throws [AuthException] on failure — screens turn codes into messages.
  /// Success lands in [state] via the repository's change stream.
  Future<AuthSession> login({
    required String email,
    required String password,
    String? totpCode,
  }) => ref
      .read(authRepositoryProvider)
      .login(email: email, password: password, totpCode: totpCode);

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) => ref
      .read(authRepositoryProvider)
      .register(email: email, password: password, displayName: displayName);

  /// Signs out AND removes what this person left on the device (OPH-355):
  /// the replica — outbox included — and their small cached facts. A screen
  /// asks first when [unsentChangeCount] is not zero (`confirmSignOut`).
  Future<void> logout({bool allDevices = false}) async {
    // Take this install off the notification registry FIRST, while the token
    // that can still do it exists (OPH-309). The registry swallows its own
    // failures — the route answers 204 to a repeated or foreign delete for
    // exactly this reason — so a sign-out is never blocked by it.
    await ref.read(deviceRegistryProvider).signOut();
    // And stop being reachable even if the row outlives the request: a deleted
    // token cannot be sent to, whatever the server still believes (OPH-319).
    await ref.read(pushMessagingProvider).forgetToken();
    // Every engine stops before the wipe below (see [_haltSyncEngines]).
    await _haltSyncEngines(ref);
    await ref.read(authRepositoryProvider).logout(allDevices: allDevices);
    await ref.read(localDataGuardProvider).wipe();
  }
}

/// Google / Apple sign-in (ADR-0026). Overridden in widget tests with a fake so
/// no test ever reaches a real provider.
final socialSignInProvider = Provider<SocialSignIn>((_) => SocialSignIn());

/// The social sign-ins the server on the address can complete (OPH-392,
/// E-23), or null when it could not say — an older server without the
/// question, or no answer at all. Null keeps the platform's own rule
/// ([SocialSignIn.googleAvailable]); an answer narrows it, so a server with
/// no Google client no longer offers a Google button that can only fail.
/// Follows the address: a server change asks the new one.
final serverSignInProvidersProvider = FutureProvider<ServerSignInProviders?>((
  ref,
) async {
  final api = ref.watch(authApiProvider);
  try {
    return await api.signInProviders();
  } on Object {
    return null;
  }
});
