import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';

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

  @override
  Future<void> register(String deviceId, DeviceDescriptor device) async {
    if (failRegister) throw StateError('offline');
    registeredIds.add(deviceId);
    registered.add(device);
  }

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
}) => DeviceRegistry(
  api: api,
  readClientId: () async => clientId,
  describe: () => descriptor,
);

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
}
