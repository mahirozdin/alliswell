import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/devices/data/device_api.dart';

import '../auth/test_support.dart';

/// OPH-393 (E-14) — `GET /api/v1/push/public-key` is registered only when the
/// server has VAPID keys (OPH-310), so a 404 is the server's own answer: "I do
/// not do browser push". Every other failure is a server we could not ask, and
/// must not be shown to anyone as the admin's missing setup.
void main() {
  Future<PushKeyLookup> lookup(int status, Object body) {
    final adapter = FakeHttpClientAdapter(
      (options, _) async => jsonBody(status, body),
    );
    return HttpDeviceApi(fakeDio(adapter)).lookupPushKey();
  }

  test('a key: configured, with the key', () async {
    final result = await lookup(200, {'publicKey': 'BPk'});
    expect(result.key, 'BPk');
    expect(result.configured, isTrue);
  });

  test('a 404: the server has no push, and says so', () async {
    final result = await lookup(404, {'error': 'not_found'});
    expect(result.key, isNull);
    expect(result.configured, isFalse);
  });

  test('a 500 is not the same answer as a 404', () async {
    final result = await lookup(500, {'error': 'internal'});
    expect(result.key, isNull);
    expect(result.configured, isNull, reason: 'unknown, not "unconfigured"');
  });

  test('no network is unknown too', () async {
    final adapter = FakeHttpClientAdapter(
      (options, _) async => throw StateError('offline'),
    );
    final result = await HttpDeviceApi(fakeDio(adapter)).lookupPushKey();
    expect(result.configured, isNull);
  });
}
