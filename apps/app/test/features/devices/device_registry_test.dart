import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';

/// OPH-309 — the registry route has existed since 2026-07-15 and nothing ever
/// called it. Epic 30 rests on this table: `last_seen_at` is the whole of the
/// staleness test that decides which devices get pushed to, so these cases are
/// about the call actually happening, and happening once.
class _RecordingApi implements DeviceApi {
  final List<DeviceDescriptor> registered = [];
  final List<String> registeredIds = [];
  final List<String> unregistered = [];
  bool failUnregister = false;
  bool failRegister = false;

  /// Holds the PUT's answer until completed: a heartbeat still on the wire.
  Completer<void>? registerGate;

  /// What the PUT answers with: `null` = an old server without the field.
  bool? ringsUrgent;

  @override
  Future<DeviceInfo?> register(String deviceId, DeviceDescriptor device) async {
    if (failRegister) throw StateError('offline');
    registeredIds.add(deviceId);
    registered.add(device);
    final answer = ringsUrgent;
    await registerGate?.future;
    return DeviceInfo.fromJson({
      'id': deviceId,
      'platform': device.platform,
      'ringsUrgent': ?answer,
    });
  }

  @override
  Future<List<DeviceInfo>> list() async => const [];

  @override
  Future<DevicePatchResult> patch(
    String deviceId, {
    bool? ringsUrgent,
    String? deviceName,
  }) async => throw UnimplementedError();

  @override
  Future<PushKeyLookup> lookupPushKey() async =>
      const PushKeyLookup.key('server-vapid-key');

  @override
  Future<void> unregister(String deviceId) async {
    if (failUnregister) throw StateError('offline');
    unregistered.add(deviceId);
  }
}

const _clientId = '01HZCLIENTAAAAAAAAAAAAAAAA';
const _descriptor = DeviceDescriptor(
  platform: 'macos',
  appVersion: '1.11.0',
  locale: 'tr',
);

DeviceRegistry _registryFor(
  _RecordingApi api, {
  String? clientId = _clientId,
  DeviceDescriptor? descriptor = _descriptor,
  RingsUrgentStore? ringsUrgent,
  void Function()? onRingsUrgentChanged,
}) => DeviceRegistry(
  api: api,
  readClientId: () async => clientId,
  describe: () => descriptor,
  ringsUrgent: ringsUrgent,
  onRingsUrgentChanged: onRingsUrgentChanged,
);

/// A [LocalKv] the test can look into.
class _MemoryKv implements LocalKv {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async =>
      values.removeWhere((key, _) => test(key));
}

void main() {
  group('the device registry calls the route', () {
    test('registers under the sync client id, with what it is', () async {
      final api = _RecordingApi();
      await _registryFor(api).sync(signedIn: true);

      expect(api.registeredIds, [_clientId]);
      expect(api.registered.single.platform, 'macos');
      expect(api.registered.single.appVersion, '1.11.0');
      expect(api.registered.single.locale, 'tr');
    });

    test('says nothing while signed out', () async {
      final api = _RecordingApi();
      await _registryFor(api).sync(signedIn: false);
      expect(api.registeredIds, isEmpty);
    });

    test('does not register as a platform the server cannot name', () async {
      // Fuchsia is a TargetPlatform and not one of the route's six. Calling it
      // Linux would be a guess written into a table somebody later reads as
      // fact; not registering says the true thing instead.
      final api = _RecordingApi();
      await _registryFor(api, descriptor: null).sync(signedIn: true);
      expect(api.registeredIds, isEmpty);
    });

    test('waits for the client id a fresh install does not have yet', () async {
      // `sync_states` only gains a row once the engine has run. Registering
      // under an invented id would put a second, permanent row in the table.
      final api = _RecordingApi();
      await _registryFor(api, clientId: null).sync(signedIn: true);
      expect(api.registeredIds, isEmpty);
    });

    test('a later sync is a heartbeat, not a second device', () async {
      final api = _RecordingApi();
      final registry = _registryFor(api);
      await registry.sync(signedIn: true);
      await registry.sync(signedIn: true);

      expect(api.registeredIds, [_clientId, _clientId]);
    });

    test('a failed registration is not remembered as done', () async {
      // Offline at launch must not mean this device never registers.
      final api = _RecordingApi()..failRegister = true;
      final registry = _registryFor(api);
      await registry.sync(signedIn: true);
      expect(api.registeredIds, isEmpty);

      api.failRegister = false;
      await registry.sync(signedIn: true);
      expect(api.registeredIds, [_clientId]);
    });
  });

  group('signing out takes the device off the list', () {
    test('deletes the id it registered', () async {
      final api = _RecordingApi();
      final registry = _registryFor(api);
      await registry.sync(signedIn: true);
      await registry.signOut();

      expect(api.unregistered, [_clientId]);
    });

    test('never lets a failure block the sign-out', () async {
      final api = _RecordingApi()..failUnregister = true;
      final registry = _registryFor(api);
      await registry.sync(signedIn: true);

      await expectLater(registry.signOut(), completes);
    });

    test('signing out without ever registering is a no-op', () async {
      final api = _RecordingApi();
      await _registryFor(api, clientId: null).signOut();
      expect(api.unregistered, isEmpty);
    });
  });

  group('the platform is the one the server has a word for', () {
    test('web wins over whatever it is running on', () {
      expect(
        awDevicePlatform(isWeb: true, target: TargetPlatform.android),
        'web',
      );
    });

    test('never produces a value the route would reject', () {
      // The route's enum, quoted. A target this function cannot name honestly
      // gets `null` and does not register — what it must never do is invent a
      // seventh value, which is a 400 nobody sees until somebody installs on
      // that platform.
      const accepted = {'ios', 'android', 'macos', 'windows', 'linux', 'web'};
      for (final target in TargetPlatform.values) {
        final platform = awDevicePlatform(isWeb: false, target: target);
        expect(
          platform == null || accepted.contains(platform),
          isTrue,
          reason: '$target produced "$platform", which the route rejects',
        );
      }
    });

    test('a platform it cannot name honestly is nothing, not a guess', () {
      expect(
        awDevicePlatform(isWeb: false, target: TargetPlatform.fuchsia),
        isNull,
      );
    });

    test('names the platforms it can name', () {
      expect(awDevicePlatform(isWeb: false, target: TargetPlatform.iOS), 'ios');
      expect(
        awDevicePlatform(isWeb: false, target: TargetPlatform.android),
        'android',
      );
      expect(
        awDevicePlatform(isWeb: false, target: TargetPlatform.macOS),
        'macos',
      );
      expect(
        awDevicePlatform(isWeb: false, target: TargetPlatform.windows),
        'windows',
      );
      expect(
        awDevicePlatform(isWeb: false, target: TargetPlatform.linux),
        'linux',
      );
    });
  });

  group('the call the client actually makes', () {
    // OPH-300's lesson on this boundary: both sides can be independently
    // correct and never meet. Nothing compares this path to the route's, so
    // this pins what the client sends — changing it has to be a decision.
    test('PUT names the route, and carries only what it is', () async {
      final adapter = FakeHttpClientAdapter(
        (options, body) async =>
            jsonBody(200, {'id': _clientId, 'platform': 'macos'}),
      );
      await HttpDeviceApi(fakeDio(adapter)).register(_clientId, _descriptor);

      final sent = adapter.requests.single;
      expect(sent.method, 'PUT');
      expect(sent.path, '/api/v1/notification-devices/$_clientId');
      expect(jsonDecode(jsonEncode(sent.data)), {
        'platform': 'macos',
        'appVersion': '1.11.0',
        'locale': 'tr',
      });
    });

    test('DELETE names the same route', () async {
      final adapter = FakeHttpClientAdapter(
        (options, body) async => emptyBody(204),
      );
      await HttpDeviceApi(fakeDio(adapter)).unregister(_clientId);

      final sent = adapter.requests.single;
      expect(sent.method, 'DELETE');
      expect(sent.path, '/api/v1/notification-devices/$_clientId');
    });
  });

  group('the device gate state (OPH-446, #48)', () {
    late InMemorySecretStore secrets;
    late FakeHttpClientAdapter auth;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await localKv.removeWhere((_) => true);
      secrets = InMemorySecretStore();
      auth = FakeHttpClientAdapter(
        (options, body) async => jsonBody(200, sessionJson()),
      );
    });

    // The real session wiring (auth/providers.dart): the hook that runs
    // before a session is exposed is what decides unknown vs legacy.
    ProviderContainer container({String? clientId}) {
      final c = ProviderContainer(
        overrides: [
          // The replica's sync client id, without a platform database.
          syncClientIdProvider.overrideWith((_) => Stream.value(clientId)),
          secretStoreProvider.overrideWithValue(secrets),
          authApiProvider.overrideWithValue(AuthApi(fakeDio(auth))),
          localDataGuardProvider.overrideWithValue(
            LocalDataGuard(database: () => throw StateError('no replica')),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<RingsUrgentHere> stateIn(ProviderContainer c) =>
        c.read(ringsUrgentStoreProvider).read();

    test(
      'a fresh sign-in starts unknown and turns on only after the register response',
      () async {
        // The previous person on this install had a ringing row.
        await localKv.set(kRingsUrgentKey, 'on');
        final c = container();
        await c
            .read(authRepositoryProvider)
            .login(email: 'mahir@example.com', password: 'pw');
        expect(await stateIn(c), RingsUrgentHere.unknown);
        expect(
          await c.read(ringsUrgentHereProvider.future),
          RingsUrgentHere.unknown,
        );

        var changes = 0;
        final api = _RecordingApi()..ringsUrgent = true;
        // No sync client id yet: no register, still unknown.
        await _registryFor(
          api,
          clientId: null,
          ringsUrgent: c.read(ringsUrgentStoreProvider),
          onRingsUrgentChanged: () => changes++,
        ).sync(signedIn: true);
        expect(await stateIn(c), RingsUrgentHere.unknown);

        // A failed register: still unknown.
        final registry = _registryFor(
          api..failRegister = true,
          ringsUrgent: c.read(ringsUrgentStoreProvider),
          onRingsUrgentChanged: () => changes++,
        );
        await registry.sync(signedIn: true);
        expect(await stateIn(c), RingsUrgentHere.unknown);
        expect(changes, 0);

        api.failRegister = false;
        await registry.sync(signedIn: true);
        expect(await stateIn(c), RingsUrgentHere.on);
        expect(changes, 1);
      },
    );

    test(
      'a fresh sign-in killed before the register response stays unknown on restore',
      () async {
        final c = container();
        await c
            .read(authRepositoryProvider)
            .login(email: 'mahir@example.com', password: 'pw');
        // The app dies here; the next launch restores the session.
        final next = container();
        await next.read(authRepositoryProvider).restore();
        expect(await stateIn(next), RingsUrgentHere.unknown);
      },
    );

    test('an upgraded install with a restored session starts legacy', () async {
      // An install from before #48: a stored session, no gate key.
      await TokenStorage(secrets).save(fakeSession());
      final c = container();
      await c.read(authRepositoryProvider).restore();
      expect(await localKv.get(kRingsUrgentKey), isNull);
      expect(await stateIn(c), RingsUrgentHere.legacy);
    });

    test(
      'a restored session of another account than the replica is unknown',
      () async {
        await localKv.set(kReplicaOwnerKey, 'someone-else');
        await localKv.set(kRingsUrgentKey, 'on');
        await TokenStorage(secrets).save(fakeSession());
        final c = container();
        await c.read(authRepositoryProvider).restore();
        expect(await stateIn(c), RingsUrgentHere.unknown);
      },
    );

    // OPH-447: the family a sign-in starts names this install — the same id
    // the registry registers under — so "remove" elsewhere can revoke it.
    group('sign-in names this device', () {
      Future<Map<String, dynamic>?> signInBody({
        required String? clientId,
        String? stored,
      }) async {
        if (stored != null) await localKv.set(kRingsUrgentKey, stored);
        final c = container(clientId: clientId);
        await c
            .read(authRepositoryProvider)
            .login(email: 'mahir@example.com', password: 'pw');
        return jsonDecode(jsonEncode(auth.requests.last.data))
            as Map<String, dynamic>?;
      }

      test(
        'sign-in passes the sync client id as deviceId when it exists',
        () async {
          final body = await signInBody(clientId: _clientId, stored: 'on');
          expect(body?['deviceId'], _clientId);
        },
      );

      test('a server that answered ringsUrgent (off) is asked too', () async {
        final body = await signInBody(clientId: _clientId, stored: 'off');
        expect(body?['deviceId'], _clientId);
      });

      test('no client id yet: no deviceId', () async {
        final body = await signInBody(clientId: null, stored: 'on');
        expect(body!.containsKey('deviceId'), isFalse);
      });

      test(
        'a server that never answered ringsUrgent (legacy) is not sent it',
        () async {
          // Its auth bodies may be additionalProperties:false.
          final body = await signInBody(clientId: _clientId);
          expect(body!.containsKey('deviceId'), isFalse);
          final legacy = await signInBody(
            clientId: _clientId,
            stored: 'legacy',
          );
          expect(legacy!.containsKey('deviceId'), isFalse);
        },
      );
    });

    test('a server without ringsUrgent leaves legacy', () async {
      final kv = _MemoryKv()..values[kRingsUrgentKey] = 'unknown';
      final store = RingsUrgentStore(kv: kv);
      final api = _RecordingApi()..ringsUrgent = null;
      await _registryFor(api, ringsUrgent: store).sync(signedIn: true);
      expect(await store.read(), RingsUrgentHere.legacy);
      expect(kv.values[kRingsUrgentKey], 'legacy');
    });

    test('register response ringsUrgent is cached', () async {
      final kv = _MemoryKv();
      final store = RingsUrgentStore(kv: kv);
      var changes = 0;
      final api = _RecordingApi()..ringsUrgent = false;
      final registry = _registryFor(
        api,
        ringsUrgent: store,
        onRingsUrgentChanged: () => changes++,
      );
      await registry.sync(signedIn: true);
      expect(kv.values[kRingsUrgentKey], 'off');
      expect(changes, 1);

      // A heartbeat with the same answer is not a change.
      await registry.sync(signedIn: true);
      expect(changes, 1);

      // The user switched this device on elsewhere: the next heartbeat says so.
      api.ringsUrgent = true;
      await registry.sync(signedIn: true);
      expect(await store.read(), RingsUrgentHere.on);
      expect(changes, 2);
    });

    // A heartbeat answers with what the server held when it got there. One
    // asked before this device's switch changed must not put the old value
    // back over the newer one (late-heartbeat-overwrites-switch).
    test(
      'a heartbeat asked before a switch change never overwrites it',
      () async {
        final kv = _MemoryKv()..values[kRingsUrgentKey] = 'on';
        final store = RingsUrgentStore(kv: kv);
        var changes = 0;
        final api = _RecordingApi()
          ..ringsUrgent = true
          ..registerGate = Completer<void>();
        final registry = _registryFor(
          api,
          ringsUrgent: store,
          onRingsUrgentChanged: () => changes++,
        );
        final heartbeat = registry.sync(signedIn: true);
        await pumpEventQueue();

        // The person switches this device off; the PATCH answer is cached.
        await store.write(RingsUrgentHere.off);
        api.registerGate!.complete();
        await heartbeat;
        expect(await store.read(), RingsUrgentHere.off);
        expect(changes, 0);

        // Answered while the PATCH is still on the wire: also too old.
        api.registerGate = Completer<void>();
        final during = registry.sync(signedIn: true);
        await pumpEventQueue();
        store.changeStarted();
        api.registerGate!.complete();
        await during;
        expect(await store.read(), RingsUrgentHere.off);
        expect(changes, 0);

        // A heartbeat asked after the change is believed again.
        api.registerGate = null;
        await registry.sync(signedIn: true);
        expect(await store.read(), RingsUrgentHere.on);
        expect(changes, 1);
      },
    );
  });

  group('the device list and patch calls (OPH-446)', () {
    final row = {
      'id': _clientId,
      'platform': 'ios',
      'deviceName': 'iPhone',
      'appVersion': '1.20.0',
      'lastSeenAt': '2026-11-12T08:00:00.000Z',
      'createdAt': '2026-10-01T08:00:00.000Z',
      'ringsUrgent': true,
      'ringsUrgentSource': 'user',
      'hasSession': true,
    };

    test('PUT returns the parsed device', () async {
      final adapter = FakeHttpClientAdapter(
        (options, body) async => jsonBody(200, row),
      );
      final device = await HttpDeviceApi(
        fakeDio(adapter),
      ).register(_clientId, _descriptor);
      expect(device?.id, _clientId);
      expect(device?.ringsUrgent, isTrue);
      expect(device?.ringsUrgentSource, 'user');
    });

    test(
      'GET lists every device, old servers without the new fields too',
      () async {
        final adapter = FakeHttpClientAdapter(
          (options, body) async => jsonBody(200, {
            'items': [
              row,
              {'id': 'old', 'platform': 'web', 'createdAt': 'not a date'},
            ],
          }),
        );
        final devices = await HttpDeviceApi(fakeDio(adapter)).list();
        final sent = adapter.requests.single;
        expect(sent.method, 'GET');
        expect(sent.path, '/api/v1/notification-devices');

        expect(devices, hasLength(2));
        final first = devices.first;
        expect(first.name, 'iPhone');
        expect(first.appVersion, '1.20.0');
        expect(first.lastSeenAt, DateTime.utc(2026, 11, 12, 8));
        expect(first.createdAt, DateTime.utc(2026, 10, 1, 8));
        expect(first.ringsUrgent, isTrue);
        expect(first.hasSession, isTrue);
        final old = devices.last;
        expect(old.name, isNull);
        expect(old.createdAt, isNull);
        expect(old.ringsUrgent, isNull);
        expect(old.ringsUrgentSource, isNull);
        expect(old.hasSession, isNull);
      },
    );

    test('PATCH sends only what changes and returns the warnings', () async {
      final adapter = FakeHttpClientAdapter(
        (options, body) async => jsonBody(200, {
          ...row,
          'ringsUrgent': false,
          'warnings': ['NO_URGENT_DEVICE'],
        }),
      );
      final result = await HttpDeviceApi(
        fakeDio(adapter),
      ).patch(_clientId, ringsUrgent: false);
      final sent = adapter.requests.single;
      expect(sent.method, 'PATCH');
      expect(sent.path, '/api/v1/notification-devices/$_clientId');
      expect(jsonDecode(jsonEncode(sent.data)), {'ringsUrgent': false});
      expect(result.device.ringsUrgent, isFalse);
      expect(result.warnings, ['NO_URGENT_DEVICE']);
    });

    test('PATCH renames without touching ringsUrgent', () async {
      final adapter = FakeHttpClientAdapter(
        (options, body) async => jsonBody(200, row),
      );
      final result = await HttpDeviceApi(
        fakeDio(adapter),
      ).patch(_clientId, deviceName: 'Work phone');
      expect(jsonDecode(jsonEncode(adapter.requests.single.data)), {
        'deviceName': 'Work phone',
      });
      expect(result.warnings, isEmpty);
    });
  });
}
