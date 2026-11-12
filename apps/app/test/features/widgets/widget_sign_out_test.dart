import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
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
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/features/widgets/widget_token_store.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../../support/fake_notifications.dart';
import '../auth/test_support.dart';
import 'widget_app_group_fake.dart';

/// #50, PR2-02 — after a sign-out the iOS widget kept drawing the account's
/// tasks, also on the sign-in screen after a relaunch: the App Group still
/// held the fetch profile, the server's answer and the app's snapshot. Now a
/// sign-out — and a session the server refused — leaves no widget token, no
/// profile, no server answer, and an empty snapshot, then asks for a redraw.
///
/// Measured over the whole App Group behind the plugin's channel, by
/// substring: a title hiding in any key fails it.
const secret = 'SECRET';

Task _task(String id) => Task(
  id: id,
  workspaceId: 'W1',
  title: '$secret $id',
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  late FakeHomeWidgetChannel plugin;
  late _MemoryTokenStore store;
  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.removeWhere((_) => true);
    plugin = FakeHomeWidgetChannel()..install();
    store = _MemoryTokenStore();
  });
  tearDown(() => plugin.uninstall());

  /// What a signed-in session left in the App Group: the app's snapshot
  /// with titles and its fetch profile, then the extension's own keys and a
  /// titled answer from the server.
  Future<void> leaveAccountInAppGroup(ProviderContainer container) async {
    await container
        .read(widgetBridgeProvider)
        .publish(
          [_task('A'), _task('B')],
          now: DateTime.now(),
          fetch: WidgetFetchSource(
            baseUrl: 'https://api.example.com',
            scope: TaskScope.workspace('W1'),
            pendingOutbox: 0,
          ),
        );
    plugin.values.addAll({
      kWidgetTokenStateKey: 'valid',
      kWidgetServerSnapshotKey: jsonEncode({
        'fetchedAtMs': 1,
        'etag': '"e"',
        'query': 'workspaceIds=W1&private=0',
        'body': {
          'days': [
            {
              'buckets': [
                {
                  'key': 'today',
                  'items': [
                    {'id': 'S', 'title': '$secret server row'},
                  ],
                },
              ],
            },
          ],
        },
      }),
      kWidgetFetchedAtKey: 1,
      kWidgetFetchFailuresKey: 0,
      kWidgetBackoffUntilKey: 2,
    });
    expect(plugin.values.values.join(), contains(secret));
    expect(plugin.isAbsent(kWidgetFetchProfileKey), isFalse);
    plugin.log.clear();
  }

  /// [secrets] — the session store the app starts with: empty unless a test
  /// seeds a stored session. [signIn] — false starts from that store alone.
  Future<ProviderContainer> signedIn({
    String? refreshRefusedWith,
    InMemorySecretStore? secrets,
    bool signIn = true,
  }) async {
    final db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets ?? InMemorySecretStore()),
        authApiProvider.overrideWithValue(
          AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, _) async {
                if (options.path == '/api/v1/auth/logout') {
                  return emptyBody(204);
                }
                if (options.path == '/api/v1/auth/refresh' &&
                    refreshRefusedWith != null) {
                  return jsonBody(401, {
                    'statusCode': 401,
                    'code': refreshRefusedWith,
                    'error': 'Unauthorized',
                    'message': 'Refresh refused',
                  });
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
        deviceRegistryProvider.overrideWithValue(
          DeviceRegistry(
            api: _QuietDeviceApi(),
            readClientId: () async => 'C1',
            describe: () => const DeviceDescriptor(
              platform: 'ios',
              appVersion: '1',
              locale: 'en',
            ),
          ),
        ),
        notificationsGatewayProvider.overrideWithValue(
          FakeNotificationsGateway(),
        ),
        alarmKitHostProvider.overrideWithValue(FakeAlarmKitHost()),
        widgetHostProvider.overrideWithValue(const HomeWidgetHost()),
        widgetTokenLifecycleProvider.overrideWith(
          (ref) => WidgetTokenLifecycle(
            api: _NoMint(),
            store: store,
            groupKeys: const HomeWidgetGroupKeys(),
            enabled: true,
            forgetProfile: () => ref.read(widgetBridgeProvider).forgetFetch(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (!signIn) return container;
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login(email: 'mahir@example.com', password: 'pw');
    await leaveAccountInAppGroup(container);
    return container;
  }

  Future<void> untilRedrawn() async {
    for (var i = 0; i < 100; i++) {
      if (plugin.log.isNotEmpty && plugin.log.last == 'update') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void expectNothingOfTheAccount() {
    expect(store.token, isNull, reason: 'the widget token is gone');
    for (final key in const [
      kWidgetFetchProfileKey,
      kWidgetTokenStateKey,
      kWidgetServerSnapshotKey,
      kWidgetFetchedAtKey,
      kWidgetFetchFailuresKey,
      kWidgetBackoffUntilKey,
    ]) {
      expect(plugin.isAbsent(key), isTrue, reason: '$key must be gone');
    }
    for (final entry in plugin.values.entries) {
      expect(
        '${entry.value}',
        isNot(contains(secret)),
        reason: '${entry.key} still holds a title',
      );
      expect('${entry.value}', isNot(contains('W1')), reason: entry.key);
    }
    // The signed-out snapshot: no row, no project, nothing open.
    final snapshot =
        jsonDecode(plugin.values[kWidgetSnapshotKey]! as String)
            as Map<String, dynamic>;
    expect(snapshot['buckets'], isEmpty);
    expect([for (final list in snapshot['lists'] as List) list['id']], ['all']);
    expect(snapshot['openToday'] ?? 0, 0);
    for (final day in snapshot['days'] as List) {
      expect((day as Map)['buckets'], isEmpty);
    }
    // Written, then the widget is asked to redraw.
    expect(plugin.log.lastIndexOf(kWidgetSnapshotKey), isNot(-1));
    expect(plugin.log.last, 'update');
    expect(
      plugin.calls.where(
        (c) =>
            c.method == 'saveWidgetData' &&
            (c.arguments as Map)['data'] == null,
      ),
      isEmpty,
    );
  }

  test(
    'sign-out leaves no token, profile, envelope or task title in the app group',
    () async {
      final container = await signedIn();

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).value, isNull);
      expectNothingOfTheAccount();
    },
  );

  test('a session the server refused leaves the same', () async {
    final container = await signedIn(refreshRefusedWith: 'AUTH_REFRESH_REUSED');

    final token = await container
        .read(authRepositoryProvider)
        .refreshAccessToken();
    await untilRedrawn();

    expect(token, isNull);
    expect(container.read(authControllerProvider).value, isNull);
    expectNothingOfTheAccount();
  });

  // A stored session whose refresh token ran out while the app was closed:
  // the start drops it and shows the sign-in screen, and the widget, which
  // nothing else would ever write over, shows nothing of the account either.
  test('a session that expired before the start leaves the same', () async {
    final secrets = InMemorySecretStore();
    final container = await signedIn(secrets: secrets, signIn: false);
    await leaveAccountInAppGroup(container);
    await TokenStorage(secrets).save(
      fakeSession(
        refreshExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    final session = await container.read(authControllerProvider.future);

    expect(session, isNull);
    expect(await TokenStorage(secrets).read(), isNull);
    expectNothingOfTheAccount();
  });

  // The same session refused at its first refresh as expired or unknown
  // (not revoked): signed out here, and nothing of it left on the widget.
  test('a session the server refused as expired leaves the same', () async {
    final container = await signedIn(
      refreshRefusedWith: 'AUTH_INVALID_REFRESH_TOKEN',
    );

    final token = await container
        .read(authRepositoryProvider)
        .refreshAccessToken();
    await untilRedrawn();

    expect(token, isNull);
    expect(container.read(authControllerProvider).value, isNull);
    expectNothingOfTheAccount();
  });
}

class _NoMint implements WidgetTokenApi {
  @override
  Future<WidgetTokenMint> mint(String deviceId) =>
      throw const WidgetTokenException(WidgetTokenRefusal.failed);
}

class _MemoryTokenStore implements WidgetTokenStore {
  String? token = 'aww_1';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}

class _QuietDeviceApi implements DeviceApi {
  @override
  Future<DeviceInfo?> register(
    String deviceId,
    DeviceDescriptor device,
  ) async => null;

  @override
  Future<void> unregister(String deviceId) async {}

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
