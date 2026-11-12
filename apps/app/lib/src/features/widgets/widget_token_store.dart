import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/http_timeouts.dart';
import '../../core/kv/local_kv.dart';
import '../../sync/providers.dart' show syncClientIdProvider;
import '../auth/providers.dart' show apiClientProvider, authControllerProvider;
import '../devices/providers.dart' show deviceRegistryProvider;
import 'widget_bridge.dart' show WidgetBridge, widgetBridgeProvider;
import 'widget_host.dart';

/// The widget token (#50, ADR-0070): the WidgetKit extension's own read-only
/// credential for `GET /widget/snapshot`, so a widget whose app was swiped
/// away can still fetch its days. iOS only — WIDGETS §3.2 is the contract
/// this file implements on the Dart side.
///
/// The token is a secret: it is written to the Keychain and nowhere else,
/// never logged, never put into an exception or a LocalKv value.

/// The Keychain account (`kSecAttrAccount`) the extension reads.
const String kWidgetTokenKey = 'aw_widget_token';

/// The App Group keys of the self-fetch that the extension writes and the app
/// clears at sign-out (WIDGETS §3.2 "App Group keys").
const String kWidgetTokenStateKey = 'aw_widget_token_state';
const String kWidgetFetchedAtKey = 'aw_widget_fetched_at_ms';
const String kWidgetFetchFailuresKey = 'aw_widget_fetch_failures';
const String kWidgetBackoffUntilKey = 'aw_widget_backoff_until_ms';

/// What this install knows about its token without reading it: the device it
/// was minted for and when it runs out. LocalKv, not the Keychain — neither
/// is a secret, and the extension never needs them.
const String kWidgetTokenMetaKey = 'alliswell_widget_token_meta';

/// Re-minted in the foreground once fewer than this many of its 90 days
/// remain (WIDGETS §3.2 "Mint").
const Duration kWidgetTokenRenewWithin = Duration(days: 30);

/// The item's attributes (WIDGETS §3.2 "Keychain item", ADR-0071): the App
/// Group as the access group — no team prefix — and readable after the first
/// unlock, on this device only, so the extension can read it while the phone
/// is locked. The service stays the plugin's default
/// (`flutter_secure_storage_service`). The session's own items keep
/// `const FlutterSecureStorage()` (WhenUnlocked, app-private) — unchanged.
const IOSOptions kWidgetTokenIosOptions = IOSOptions(
  groupId: kWidgetAppGroupId,
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

/// The widget token's Keychain item. A store of its own: `SecureSecretStore`
/// and the session tokens are not touched by #50.
class WidgetTokenStore {
  WidgetTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(iOptions: kWidgetTokenIosOptions);

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: kWidgetTokenKey);

  Future<void> write(String token) =>
      _storage.write(key: kWidgetTokenKey, value: token);

  Future<void> delete() => _storage.delete(key: kWidgetTokenKey);
}

/// The App Group values the token's life touches (`UserDefaults(suiteName:)`
/// on iOS). An interface so the lifecycle is testable without a plugin.
abstract interface class WidgetGroupKeys {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// [WidgetGroupKeys] over `home_widget`, in the widget's App Group.
class HomeWidgetGroupKeys implements WidgetGroupKeys {
  const HomeWidgetGroupKeys();

  Future<void> _configure() => HomeWidget.setAppGroupId(kWidgetAppGroupId);

  @override
  Future<String?> read(String key) async {
    await _configure();
    final value = await HomeWidget.getWidgetData<Object>(key);
    return value?.toString();
  }

  @override
  Future<void> write(String key, String value) async {
    await _configure();
    await HomeWidget.saveWidgetData<String>(key, value);
  }

  /// `home_widget` removes the key when it is saved as null.
  @override
  Future<void> remove(String key) async {
    await _configure();
    await HomeWidget.saveWidgetData<String>(key, null);
  }
}

/// A `201` from `POST /api/v1/widget-tokens`.
@immutable
class WidgetTokenMint {
  const WidgetTokenMint({
    required this.token,
    required this.deviceId,
    required this.expiresAt,
  });

  final String token;
  final String deviceId;
  final DateTime expiresAt;

  /// Never the token: this may end up in a log.
  @override
  String toString() => 'WidgetTokenMint($deviceId, $expiresAt)';
}

/// Why a mint did not give a token.
enum WidgetTokenRefusal {
  /// `404 DEVICE_NOT_FOUND`: this install is not a registered device (yet);
  /// asked again at the next foreground.
  deviceNotFound,

  /// A `404` without that code: a server from before #50. Not asked again
  /// until the next app start.
  unsupported,

  /// Anything else — offline, a timeout, a 5xx, a refused session: asked
  /// again at the next foreground.
  failed,
}

class WidgetTokenException implements Exception {
  const WidgetTokenException(this.refusal);

  final WidgetTokenRefusal refusal;

  @override
  String toString() => 'WidgetTokenException(${refusal.name})';
}

/// The one call the app makes for the widget token.
abstract interface class WidgetTokenApi {
  /// Mints the token for [deviceId] (a `notification_devices` id = the sync
  /// client id); throws [WidgetTokenException].
  Future<WidgetTokenMint> mint(String deviceId);
}

/// `POST /api/v1/widget-tokens` over the session's authenticated client.
class HttpWidgetTokenApi implements WidgetTokenApi {
  const HttpWidgetTokenApi(this._dio);

  final Dio _dio;

  @override
  Future<WidgetTokenMint> mint(String deviceId) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '/api/v1/widget-tokens',
        data: {'deviceId': deviceId},
        options: boundedApiCall(),
      );
    } on DioException catch (e) {
      final answer = e.response;
      if (answer?.statusCode == 404) {
        final data = answer?.data;
        final code = data is Map ? data['code'] : null;
        throw WidgetTokenException(
          code == 'DEVICE_NOT_FOUND'
              ? WidgetTokenRefusal.deviceNotFound
              : WidgetTokenRefusal.unsupported,
        );
      }
      throw const WidgetTokenException(WidgetTokenRefusal.failed);
    }
    final body = response.data;
    final token = body is Map ? body['token'] : null;
    final expiresAt = body is Map && body['expiresAt'] is String
        ? DateTime.tryParse(body['expiresAt'] as String)
        : null;
    if (token is! String || token.isEmpty || expiresAt == null) {
      throw const WidgetTokenException(WidgetTokenRefusal.failed);
    }
    final minted = body['deviceId'];
    return WidgetTokenMint(
      token: token,
      deviceId: minted is String ? minted : deviceId,
      expiresAt: expiresAt.toUtc(),
    );
  }
}

/// Whether this platform keeps a widget token: iOS only (WIDGETS §3.2).
/// Android's background turn runs Dart, the macOS widget's self-fetch is a
/// later candidate, web and the other desktops have no widget.
bool widgetTokenLifecycleEnabled({
  required bool isWeb,
  required TargetPlatform platform,
}) => !isWeb && platform == TargetPlatform.iOS;

/// The token's life on this install (WIDGETS §3.2 "Mint", ADR-0070):
///
/// - **mint** once this install is a registered device — the device row is
///   written first ([register]), since the server mints only for a device of
///   the session's user;
/// - **renew** in the foreground when fewer than [kWidgetTokenRenewWithin] of
///   its days remain, when the extension wrote `invalid` after a 401, when
///   the item is gone or was minted for another device id;
/// - **forget** at sign-out ([signOut]), after the caller deleted the device
///   on the server (that revokes the token);
/// - an older server without the route is left alone until the next start.
///
/// A no-op where [enabled] is false (every platform but iOS). Failures are
/// swallowed: the widget keeps its local snapshot, and the next foreground
/// asks again.
class WidgetTokenLifecycle {
  WidgetTokenLifecycle({
    required this.api,
    WidgetTokenStore? store,
    WidgetGroupKeys? groupKeys,
    LocalKv? kv,
    DateTime Function()? clock,
    this.register,
    this.forgetProfile,
    bool? enabled,
  }) : store = store ?? WidgetTokenStore(),
       groupKeys = groupKeys ?? const HomeWidgetGroupKeys(),
       _kv = kv ?? localKv,
       _clock = clock ?? DateTime.now,
       enabled =
           enabled ??
           widgetTokenLifecycleEnabled(
             isWeb: kIsWeb,
             platform: defaultTargetPlatform,
           );

  final WidgetTokenApi api;
  final WidgetTokenStore store;
  final WidgetGroupKeys groupKeys;
  final LocalKv _kv;
  final DateTime Function() _clock;

  /// Writes this install's device row (a registry heartbeat) before a mint.
  final Future<void> Function()? register;

  /// Makes the app forget the fetch profile it would otherwise write again
  /// ([WidgetBridge.forgetFetch]) — called at sign-out before the keys go.
  final void Function()? forgetProfile;

  final bool enabled;

  /// A server from before #50 answered: no more asking in this process.
  bool _unsupported = false;

  /// Bumped by [signOut]: a mint still on the wire then stores nothing.
  int _generation = 0;

  Future<void>? _running;

  /// Mints or renews when due. Called when a session and a device id exist
  /// and at every return to the foreground; one at a time. Never throws.
  Future<void> ensure(String deviceId) {
    if (!enabled || _unsupported) return Future.value();
    return _running ??= _ensure(deviceId).whenComplete(() => _running = null);
  }

  Future<void> _ensure(String deviceId) async {
    final generation = _generation;
    try {
      if (!await _due(deviceId)) return;
      await register?.call();
      if (generation != _generation) return;
      final minted = await api.mint(deviceId);
      if (generation != _generation) return;
      await store.write(minted.token);
      await _kv.set(
        kWidgetTokenMetaKey,
        jsonEncode({
          'deviceId': deviceId,
          'expiresAt': minted.expiresAt.toUtc().toIso8601String(),
        }),
      );
      await groupKeys.write(kWidgetTokenStateKey, 'valid');
    } on WidgetTokenException catch (e) {
      if (e.refusal == WidgetTokenRefusal.unsupported) _unsupported = true;
    } on Object {
      // A Keychain or App Group hiccup: the next foreground tries again.
    }
  }

  Future<bool> _due(String deviceId) async {
    if (await groupKeys.read(kWidgetTokenStateKey) == 'invalid') return true;
    final meta = _readMeta(await _kv.get(kWidgetTokenMetaKey));
    if (meta == null || meta.deviceId != deviceId) return true;
    if (meta.expiresAt.difference(_clock().toUtc()) < kWidgetTokenRenewWithin) {
      return true;
    }
    // Restored from a backup, or removed by hand: the item is this
    // device's only (ThisDeviceOnly), the stamp may not be.
    return await store.read() == null;
  }

  static ({String deviceId, DateTime expiresAt})? _readMeta(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final deviceId = data['deviceId'];
      final expiresAt = data['expiresAt'] is String
          ? DateTime.tryParse(data['expiresAt'] as String)
          : null;
      if (deviceId is! String || expiresAt == null) return null;
      return (deviceId: deviceId, expiresAt: expiresAt);
    } on FormatException {
      return null;
    }
  }

  /// Sign-out or an account switch (WIDGETS §3.2): the caller has already
  /// deleted this device on the server, which revokes the token. Then every
  /// self-fetch key goes except the snapshot, then the Keychain item. Each
  /// step is best effort; a sign-out is never blocked by it.
  Future<void> signOut() async {
    if (!enabled) return;
    _generation++;
    try {
      await _running;
    } on Object {
      // Never throws, but a sign-out must not depend on it.
    }
    forgetProfile?.call();
    for (final key in const [
      kWidgetFetchProfileKey,
      kWidgetTokenStateKey,
      kWidgetServerSnapshotKey,
      kWidgetFetchedAtKey,
      kWidgetFetchFailuresKey,
      kWidgetBackoffUntilKey,
    ]) {
      try {
        await groupKeys.remove(key);
      } on Object {
        // Best effort.
      }
    }
    try {
      await _kv.remove(kWidgetTokenMetaKey);
    } on Object {
      // Best effort.
    }
    try {
      await store.delete();
    } on Object {
      // Best effort.
    }
  }
}

/// The install's one [WidgetTokenLifecycle]. Not rebuilt by the session: it
/// outlives a sign-out so it can be the one that clears the token.
final widgetTokenLifecycleProvider = Provider<WidgetTokenLifecycle>(
  (ref) => WidgetTokenLifecycle(
    // Read at call time: the client follows the server address.
    api: _LazyWidgetTokenApi(
      () => HttpWidgetTokenApi(ref.read(apiClientProvider)),
    ),
    register: () => ref.read(deviceRegistryProvider).sync(signedIn: true),
    forgetProfile: () => ref.read(widgetBridgeProvider).forgetFetch(),
  ),
);

class _LazyWidgetTokenApi implements WidgetTokenApi {
  const _LazyWidgetTokenApi(this._api);

  final WidgetTokenApi Function() _api;

  @override
  Future<WidgetTokenMint> mint(String deviceId) => _api().mint(deviceId);
}

/// Mints or renews the widget token while a session and this install's
/// device id exist, and again at every return to the foreground (iOS only).
/// Watched by the signed-in shell, beside the widget sync.
final widgetTokenSyncProvider = Provider<void>((ref) {
  final lifecycle = ref.watch(widgetTokenLifecycleProvider);
  if (!lifecycle.enabled) return;
  final signedIn = ref.watch(
    authControllerProvider.select((session) => session.value != null),
  );
  final deviceId = ref.watch(syncClientIdProvider).value;
  if (!signedIn || deviceId == null) return;
  unawaited(lifecycle.ensure(deviceId));
  final listener = AppLifecycleListener(
    onResume: () => unawaited(lifecycle.ensure(deviceId)),
  );
  ref.onDispose(listener.dispose);
});
