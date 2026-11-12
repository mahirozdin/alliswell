import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/features/widgets/widget_token_store.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';

/// #50, WIDGETS §3.2 "Mint": the app mints the widget's own token once this
/// install is a registered device, renews it in the foreground before it runs
/// out, re-mints after the extension met a 401, takes it away at sign-out
/// after the server record, and leaves an older server alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  setUp(() async => localKv.removeWhere((_) => true));

  test(
    'mints after registration and renews when fewer than 30 days remain',
    () async {
      var now = DateTime.utc(2026, 11, 12, 9);
      final events = <String>[];
      var registered = false;
      var minted = 0;
      final adapter = FakeHttpClientAdapter((options, body) async {
        final deviceId = body?['deviceId'];
        events.add('mint:${options.method} ${options.path} $deviceId');
        if (!registered) {
          return jsonBody(404, {
            'statusCode': 404,
            'code': 'DEVICE_NOT_FOUND',
            'error': 'Not Found',
            'message': 'Device not found',
          });
        }
        minted++;
        return jsonBody(201, {
          'token': 'aww_$minted',
          'deviceId': deviceId,
          'expiresAt': now.add(const Duration(days: 90)).toIso8601String(),
        });
      });
      final store = MemoryWidgetTokenStore(events);
      final keys = MemoryGroupKeys(events);
      var registerWorks = false;
      final lifecycle = WidgetTokenLifecycle(
        api: HttpWidgetTokenApi(fakeDio(adapter)),
        store: store,
        groupKeys: keys,
        enabled: true,
        clock: () => now,
        register: () async {
          events.add('register');
          if (registerWorks) registered = true;
        },
      );

      // Not a registered device yet (the heartbeat failed): the server says
      // so, nothing is stored, and the next foreground asks again.
      await lifecycle.ensure('C1');
      expect(events, ['register', 'mint:POST /api/v1/widget-tokens C1']);
      expect(store.token, isNull);
      expect(keys.values, isEmpty);

      // Registered: the device row first, then the mint, then the token, and
      // only then "valid".
      registerWorks = true;
      events.clear();
      await lifecycle.ensure('C1');
      expect(events, [
        'register',
        'mint:POST /api/v1/widget-tokens C1',
        'token.write',
        'set:$kWidgetTokenStateKey=valid',
      ]);
      expect(store.token, 'aww_1');

      // Fresh, and still more than 30 of its 90 days left: nothing asked.
      events.clear();
      await lifecycle.ensure('C1');
      now = now.add(const Duration(days: 59));
      await lifecycle.ensure('C1');
      expect(events, isEmpty);

      // 29 days left: renewed in the foreground.
      now = now.add(const Duration(days: 2));
      await lifecycle.ensure('C1');
      expect(events, contains('mint:POST /api/v1/widget-tokens C1'));
      expect(store.token, 'aww_2');

      // The extension met a 401 and wrote "invalid": the next foreground
      // mints again, however many days the old one had.
      events.clear();
      keys.values[kWidgetTokenStateKey] = 'invalid';
      await lifecycle.ensure('C1');
      expect(store.token, 'aww_3');
      expect(keys.values[kWidgetTokenStateKey], 'valid');

      // A token minted for another device id is not this install's.
      await lifecycle.ensure('C2');
      expect(store.token, 'aww_4');

      // A failed renewal keeps the token there is.
      now = now.add(const Duration(days: 70));
      registered = false;
      registerWorks = false;
      await lifecycle.ensure('C2');
      expect(store.token, 'aww_4');
      expect(keys.values[kWidgetTokenStateKey], 'valid');
    },
  );

  test('sign-out deletes the server record before the local token', () async {
    final events = <String>[];
    final db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    final registry = DeviceRegistry(
      api: RecordingDeviceApi(events),
      readClientId: () async => 'C1',
      describe: () => const DeviceDescriptor(
        platform: 'ios',
        appVersion: '1',
        locale: 'en',
      ),
    );
    final store = MemoryWidgetTokenStore(events);
    final keys = MemoryGroupKeys(events);
    final lifecycle = WidgetTokenLifecycle(
      api: FakeWidgetTokenApi(
        (deviceId) async => WidgetTokenMint(
          token: 'aww_1',
          deviceId: deviceId,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 90)),
        ),
      ),
      store: store,
      groupKeys: keys,
      enabled: true,
      forgetProfile: () => events.add('profile.forget'),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        authApiProvider.overrideWithValue(
          AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, _) async {
                if (options.path == '/api/v1/auth/logout') {
                  events.add('server.logout');
                  return emptyBody(204);
                }
                return jsonBody(200, sessionJson());
              }),
            ),
          ),
        ),
        apiClientProvider.overrideWithValue(
          fakeDio(
            FakeHttpClientAdapter(
              (options, _) async => jsonBody(404, {'statusCode': 404}),
            ),
          ),
        ),
        deviceRegistryProvider.overrideWithValue(registry),
        widgetTokenLifecycleProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login(email: 'mahir@example.com', password: 'pw');
    await registry.sync(signedIn: true);
    await lifecycle.ensure('C1');
    expect(store.token, 'aww_1');
    // What the extension and an earlier profile left in the App Group.
    keys.values.addAll({
      kWidgetSnapshotKey: '{"v":6}',
      kWidgetFetchProfileKey: '{"v":1}',
      kWidgetServerSnapshotKey: '{}',
      kWidgetFetchedAtKey: '1',
      kWidgetFetchFailuresKey: '2',
      kWidgetBackoffUntilKey: '3',
    });
    events.clear();

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value, isNull);
    final serverDelete = events.indexOf('server.delete:C1');
    final localDelete = events.indexOf('token.delete');
    expect(serverDelete, isNot(-1));
    expect(localDelete, greaterThan(serverDelete));
    // The app forgets the profile before its key goes, so nothing writes the
    // old scope back; the Keychain item is the last thing to go.
    expect(
      events.indexOf('profile.forget'),
      allOf(
        greaterThan(serverDelete),
        lessThan(events.indexOf('remove:$kWidgetFetchProfileKey')),
      ),
    );
    expect(events.last, 'token.delete');
    expect(store.token, isNull);
    // Every self-fetch key goes; the snapshot stays (WIDGETS §3.2).
    expect(keys.values.keys, [kWidgetSnapshotKey]);
    expect(await localKv.get(kWidgetTokenMetaKey), isNull);
    // Nothing that was the token reached the event log.
    expect(events.where((e) => e.contains('aww_')), isEmpty);
  });

  test('a forgotten fetch profile is not written back by the outbox', () async {
    final host = _KeyedHost();
    final bridge = WidgetBridge(host);
    await bridge.publish(
      const [],
      now: DateTime.utc(2026, 11, 12, 9),
      hideTitles: true,
      fetch: WidgetFetchSource(
        baseUrl: 'https://api.example.com',
        scope: TaskScope.workspace('W1'),
        pendingOutbox: 0,
      ),
    );
    expect(host.keys, contains(kWidgetFetchProfileKey));
    host.keys.clear();
    await bridge.updatePendingOutbox(3);
    expect(host.keys, [kWidgetFetchProfileKey]);

    // Signed out: the person's profile inputs are forgotten.
    host.keys.clear();
    bridge.forgetFetch();
    await bridge.updatePendingOutbox(5);
    expect(host.keys, isEmpty);
  });

  test('an old server without widget tokens is left alone', () async {
    final adapter = FakeHttpClientAdapter(
      (options, _) async => jsonBody(404, {
        'statusCode': 404,
        'error': 'Not Found',
        'message': 'Route POST:/api/v1/widget-tokens not found',
      }),
    );
    final events = <String>[];
    final store = MemoryWidgetTokenStore(events);
    final keys = MemoryGroupKeys(events);
    WidgetTokenLifecycle start() => WidgetTokenLifecycle(
      api: HttpWidgetTokenApi(fakeDio(adapter)),
      store: store,
      groupKeys: keys,
      enabled: true,
    );

    final lifecycle = start();
    await lifecycle.ensure('C1');
    await lifecycle.ensure('C1');
    await lifecycle.ensure('C1');
    // Asked once; no retry for the rest of this run, nothing stored.
    expect(adapter.requests, hasLength(1));
    expect(store.token, isNull);
    expect(keys.values, isEmpty);
    expect(await localKv.get(kWidgetTokenMetaKey), isNull);

    // The next app start asks once more (the server may have been updated).
    await start().ensure('C1');
    expect(adapter.requests, hasLength(2));
  });

  test('Android, web and desktop never mint or touch the keychain', () async {
    final events = <String>[];
    var asked = 0;
    final lifecycle = WidgetTokenLifecycle(
      api: FakeWidgetTokenApi((deviceId) async {
        asked++;
        throw StateError('never');
      }),
      store: MemoryWidgetTokenStore(events),
      groupKeys: MemoryGroupKeys(events),
      enabled: false,
    );
    await lifecycle.ensure('C1');
    await lifecycle.signOut();
    expect(asked, 0);
    expect(events, isEmpty);
    // The default is the platform's: only iOS's widget fetches its own days.
    expect(
      widgetTokenLifecycleEnabled(isWeb: false, platform: TargetPlatform.iOS),
      isTrue,
    );
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(
        widgetTokenLifecycleEnabled(isWeb: false, platform: platform),
        isFalse,
      );
    }
    expect(
      widgetTokenLifecycleEnabled(isWeb: true, platform: TargetPlatform.iOS),
      isFalse,
    );
  });
}

class _KeyedHost implements WidgetHost {
  final List<String> keys = [];

  @override
  Future<void> configure() async {}

  @override
  Future<void> save(String key, String value) async => keys.add(key);

  @override
  Future<void> requestUpdate() async {}
}

class FakeWidgetTokenApi implements WidgetTokenApi {
  FakeWidgetTokenApi(this._mint);
  final Future<WidgetTokenMint> Function(String deviceId) _mint;

  @override
  Future<WidgetTokenMint> mint(String deviceId) => _mint(deviceId);
}

class MemoryWidgetTokenStore implements WidgetTokenStore {
  MemoryWidgetTokenStore(this.events);
  final List<String> events;
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    events.add('token.write');
    token = value;
  }

  @override
  Future<void> delete() async {
    events.add('token.delete');
    token = null;
  }
}

class MemoryGroupKeys implements WidgetGroupKeys {
  MemoryGroupKeys(this.events);
  final List<String> events;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    events.add('set:$key=$value');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (values.remove(key) != null) events.add('remove:$key');
  }
}

class RecordingDeviceApi implements DeviceApi {
  RecordingDeviceApi(this.events);
  final List<String> events;

  @override
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device) async {
    events.add('server.register:$deviceId');
    return null;
  }

  @override
  Future<void> unregister(String deviceId) async =>
      events.add('server.delete:$deviceId');

  @override
  Future<List<DeviceInfo>> list() async => const [];

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) => throw UnimplementedError();

  @override
  Future<PushKeyLookup> lookupPushKey() async =>
      const PushKeyLookup.notConfigured();
}
