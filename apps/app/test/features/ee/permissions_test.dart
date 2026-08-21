import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

/// EE-052 — what a screen asks before it draws a button.
///
/// The distinction this file exists to protect is `governed` vs an empty
/// permission list. A plain build, a personal workspace, an offline first
/// launch and a server that predates the endpoint all mean NOBODY IS ASKING —
/// and there every `can()` must answer true, because a permission layer that
/// is not installed must never take an ability away. An empty list under
/// `governed: true` is the opposite and the only case that removes anything.
const _cacheKey =
    'alliswell_ee_permissions::user-1::01WSAAAAAAAAAAAAAAAAAAAAAA';

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
    // localKv is a global singleton whose cache outlives a test.
    await localKv.remove(_cacheKey);
  });

  test('a plain build is ungoverned — every verb answers yes', () async {
    final api = FakeApi();
    final container = await signedInContainer(api);

    final perms = await container.read(eePermissionsProvider.future);

    expect(perms.governed, isFalse);
    expect(container.read(canProvider('tasks.create')), isTrue);
    expect(container.read(canProvider('anything.at.all')), isTrue);
  });

  test('a server that predates the endpoint is ungoverned too', () async {
    // A 404 says "no such feature here", which is not the same statement as
    // "you may do nothing" — and mixing them up would cripple the app on
    // every older server.
    final api = FakeApi()..eeMePermissionsCode = 404;
    final container = await signedInContainer(api);

    final perms = await container.read(eePermissionsProvider.future);

    expect(perms.governed, isFalse);
    expect(container.read(canProvider('tasks.create')), isTrue);
  });

  test('a narrowed role answers no — and only for what it lacks', () async {
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['tasks.view', 'tasks.complete'];
    final container = await signedInContainer(api);

    await container.read(eePermissionsProvider.future);

    expect(container.read(canProvider('tasks.view')), isTrue);
    expect(container.read(canProvider('tasks.complete')), isTrue);
    expect(container.read(canProvider('tasks.create')), isFalse);
    expect(container.read(canProvider('alarms.create_urgent')), isFalse);
    expect(api.requests, contains('GET /api/v1/ee/me/permissions'));
  });

  test(
    'a change lands on the next refresh — there is nothing to invalidate',
    () async {
      final api = FakeApi()
        ..eeGoverned = true
        ..eePermissions = ['tasks.view'];
      final container = await signedInContainer(api);
      await container.read(eePermissionsProvider.future);
      expect(container.read(canProvider('tasks.create')), isFalse);

      // The team granted the verb; the client learns on its next ask.
      api.eePermissions = ['tasks.view', 'tasks.create'];
      await container.read(eePermissionsProvider.notifier).refresh();

      expect(container.read(canProvider('tasks.create')), isTrue);
    },
  );

  test('offline keeps the last known answer', () async {
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['tasks.view'];
    final container = await signedInContainer(api);
    await container.read(eePermissionsProvider.future);

    api.eeMePermissionsCode = 500; // the network, or the server, is gone
    await container.read(eePermissionsProvider.notifier).refresh();

    final perms = container.read(eePermissionsProvider).value!;
    expect(perms.governed, isTrue);
    expect(perms.permissions, ['tasks.view']);
    expect(container.read(canProvider('tasks.create')), isFalse);
  });

  test(
    'a first launch with no network and no cache is ungoverned, not crippled',
    () async {
      // The fallback that matters most: somebody with every right to use the
      // app must not meet a locked-down one because a request failed.
      final api = FakeApi()..eeMePermissionsCode = 500;
      final container = await signedInContainer(api);

      final perms = await container.read(eePermissionsProvider.future);

      expect(perms.governed, isFalse);
      expect(container.read(canProvider('tasks.create')), isTrue);
    },
  );

  test('the cache is written per user AND per workspace', () async {
    final api = FakeApi()
      ..eeGoverned = true
      ..eePermissions = ['notes.view'];
    final container = await signedInContainer(api);
    await container.read(eePermissionsProvider.future);

    final raw = await localKv.get(_cacheKey);
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as Map<String, dynamic>)['permissions'], [
      'notes.view',
    ]);
  });
}
