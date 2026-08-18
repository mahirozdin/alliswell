import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

/// EE-008 — the instance entitlement base. Provider-level (no EE surface
/// exists yet to pump): a CE server answers empty, an entitled server carries
/// its list, offline keeps the last-known truth, and a pre-endpoint server's
/// 404 maps to "nothing on". Zero visual difference on CE is carried by the
/// rest of the widget suite: every full-app test runs against the CE default.
Future<ProviderContainer> signedInContainer(FakeApi api) async {
  final store = InMemorySecretStore();
  final container = ProviderContainer(
    retry: awRetry,
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await TokenStorage(store).save(fakeSession());
  await container.read(authControllerProvider.future);
  return container;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // localKv is a global singleton whose cache outlives a test: the mock
    // reset above only affects future instances, so clear the key explicitly
    // (the refresh_test / reminder_settings_test idiom).
    await localKv.remove('alliswell_ee_status::user-1');
  });

  test('a CE server answers empty — every feature reads off', () async {
    final api = FakeApi();
    final container = await signedInContainer(api);

    final status = await container.read(eeStatusProvider.future);

    expect(status.state, 'none');
    expect(status.features, isEmpty);
    expect(container.read(eeFeatureProvider('teams')), isFalse);
    expect(api.requests, contains('GET /api/v1/ee/status'));
  });

  test('an entitled server carries its feature list', () async {
    final api = FakeApi()
      ..eeState = 'active'
      ..eeFeatures = ['teams', 'itsm'];
    final container = await signedInContainer(api);

    final status = await container.read(eeStatusProvider.future);

    expect(status.state, 'active');
    expect(status.features, ['teams', 'itsm']);
    expect(container.read(eeFeatureProvider('teams')), isTrue);
    expect(container.read(eeFeatureProvider('itsm')), isTrue);
    expect(container.read(eeFeatureProvider('sla')), isFalse);
  });

  test('readonly keeps names listed but gates every feature off', () async {
    final api = FakeApi()
      ..eeState = 'readonly'
      ..eeFeatures = ['teams'];
    final container = await signedInContainer(api);

    final status = await container.read(eeStatusProvider.future);

    // The server's has() semantics, mirrored: only active|grace unlock.
    expect(status.features, ['teams']);
    expect(container.read(eeFeatureProvider('teams')), isFalse);
  });

  test('a 404 (server predates the endpoint) maps to nothing-on', () async {
    final api = FakeApi()..eeStatusCode = 404;
    final container = await signedInContainer(api);

    final status = await container.read(eeStatusProvider.future);

    expect(status.state, 'none');
    expect(container.read(eeFeatureProvider('teams')), isFalse);
  });

  test('offline keeps the last-known truth from the cache', () async {
    final api = FakeApi()
      ..eeState = 'active'
      ..eeFeatures = ['teams'];
    // First launch online: the fetch succeeds and lands in localKv.
    final online = await signedInContainer(api);
    await online.read(eeStatusProvider.future);

    // Second launch offline: the network fails, the cache answers.
    api.offline = true;
    final offline = await signedInContainer(api);
    final status = await offline.read(eeStatusProvider.future);

    expect(status.state, 'active');
    expect(status.features, ['teams']);
    expect(offline.read(eeFeatureProvider('teams')), isTrue);
  });

  test('offline with no cache stays withdrawn', () async {
    final api = FakeApi()..offline = true;
    final container = await signedInContainer(api);

    final status = await container.read(eeStatusProvider.future);

    expect(status.state, 'none');
    expect(container.read(eeFeatureProvider('teams')), isFalse);
  });

  test('signed out answers none without touching the network', () async {
    final api = FakeApi();
    final container = ProviderContainer(
      retry: awRetry,
      overrides: [
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(api.handle)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final status = await container.read(eeStatusProvider.future);

    expect(status, same(EeStatus.none));
    expect(api.requests, isEmpty);
  });
}
