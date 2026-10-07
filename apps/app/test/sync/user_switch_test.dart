import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/data/models.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/notifications_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

import '../features/auth/test_support.dart';

/// OPH-355 — the replica belongs to the person it was filled for.
///
/// Sign-out wipes it, but a sign-out can be skipped: a forced one after a dead
/// refresh token, a crash, a build from before the wipe. So signing in as
/// somebody ELSE drops the replica before the session is exposed — before any
/// screen or engine reads it — and the same person coming back keeps theirs.
void main() {
  const ws = 'W1';

  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  setUp(() async => localKv.removeWhere((_) => true));

  Map<String, dynamic> sessionFor(String userId) => {
    'user': {
      'id': userId,
      'email': '$userId@example.com',
      'displayName': userId,
    },
    'tokens': {
      'accessToken': 'access-$userId',
      'accessTokenExpiresInSec': 900,
      'refreshToken': 'refresh-$userId',
      'refreshTokenExpiresAt': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String(),
    },
  };

  late AwDatabase db;
  late InMemorySecretStore store;

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    store = InMemorySecretStore();
  });
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(
          AuthApi(
            fakeDio(
              FakeHttpClientAdapter((options, body) async {
                if (options.path == '/api/v1/auth/login') {
                  final email = body!['email'] as String;
                  return jsonBody(200, sessionFor(email.split('@').first));
                }
                return emptyBody(204);
              }),
            ),
          ),
        ),
        syncWorkspaceIdsProvider.overrideWithValue(const [ws]),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> login(ProviderContainer c, String userId) async {
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .login(email: '$userId@example.com', password: 'pw');
    // The controller mirrors the repository's change stream, one event later.
    await Future<void>.delayed(Duration.zero);
  }

  /// One of [userId]'s request notifications, as a pull writes it.
  Future<void> seedNotification(String userId) => applyPulledChanges(
    db,
    workspaceId: ws,
    changes: [
      SyncChange(
        revision: 1,
        entityType: 'ee_notification',
        entityId: 'N-$userId',
        operation: 'upsert',
        data: {
          'id': 'N-$userId',
          'workspaceId': ws,
          'userId': userId,
          'eventClass': 'ticket.status_changed',
          'titleKey': 'ee.notif.ticket.status_changed.title',
          'params': {'ticketRef': '#222'},
          'entityType': 'ee_ticket',
          'entityId': 'T1',
          'createdAt': '2026-10-07T08:00:00.000Z',
          'revision': 1,
          'updatedAt': '2026-10-07T08:00:00.000Z',
        },
      ),
    ],
    toRevision: 1,
  );

  Future<List<String>> centreIds(ProviderContainer c) async {
    final sub = c.listen(notificationCenterProvider, (_, _) {});
    addTearDown(sub.close);
    return [
      for (final n in await c.read(notificationCenterProvider.future)) n.id,
    ];
  }

  test('UI-AUDIT #3: A signs out without the wipe, B signs in — A\'s rows and '
      'notifications are gone before B sees anything', () async {
    final first = container();
    await login(first, 'saha3');
    await seedNotification('saha3');
    // The sign-out that never wiped: an older build, a crash, a forced one.
    await TokenStorage(store).clear();
    first.dispose();

    final second = container();
    await login(second, 'saha2');
    expect(second.read(currentUserIdProvider), 'saha2');
    expect(await db.select(db.notifications).get(), isEmpty);
    expect(await db.select(db.syncStates).get(), isEmpty);
    expect(await centreIds(second), isEmpty);
    expect(await localKv.get(kReplicaOwnerKey), 'saha2');
  });

  test('UI-AUDIT #3: A signs out and B signs in through the app', () async {
    final c = container();
    await login(c, 'saha3');
    await seedNotification('saha3');
    await c.read(authControllerProvider.notifier).logout();
    expect(await db.select(db.notifications).get(), isEmpty);

    await login(c, 'saha2');
    await seedNotification('saha2');
    expect(await centreIds(c), ['N-saha2']);
  });

  test('the same person signing back in keeps their replica', () async {
    final c = container();
    await login(c, 'saha3');
    await seedNotification('saha3');
    await TokenStorage(store).clear();
    c.dispose();

    final again = container();
    await login(again, 'saha3');
    expect(await centreIds(again), ['N-saha3']);
  });

  test(
    'a session restored at start with no recorded owner adopts the replica',
    () async {
      // A build from before OPH-355, signed in: the replica is this person's.
      await seedNotification('user-1');
      await TokenStorage(store).save(fakeSession());
      final c = container();
      final session = await c.read(authControllerProvider.future);
      expect(session?.user.id, 'user-1');
      expect(await db.select(db.notifications).get(), hasLength(1));
      expect(await localKv.get(kReplicaOwnerKey), 'user-1');
    },
  );

  test('a session restored over somebody else\'s replica drops it', () async {
    await seedNotification('saha3');
    await localKv.set(kReplicaOwnerKey, 'saha3');
    await TokenStorage(store).save(fakeSession());
    final c = container();
    final AuthSession? session = await c.read(authControllerProvider.future);
    expect(session?.user.id, 'user-1');
    expect(await db.select(db.notifications).get(), isEmpty);
    expect(await localKv.get(kReplicaOwnerKey), 'user-1');
  });

  test(
    'a fresh sign-in with no recorded owner cannot vouch for the rows',
    () async {
      // Signed out under a build from before OPH-355: whose rows these are is
      // unknown, so they go.
      await seedNotification('saha3');
      final c = container();
      await login(c, 'saha2');
      expect(await db.select(db.notifications).get(), isEmpty);
    },
  );

  test(
    'halt waits for the round in flight, so no page lands after the wipe',
    () async {
      final gate = Completer<void>();
      final api = _GatedSyncApi(gate.future);
      final engine = SyncEngine(db: db, api: api, workspaceId: ws);
      final round = engine.syncNow();
      await api.pulling.future;

      var halted = false;
      final halting = engine.halt().then((_) => halted = true);
      await Future<void>.delayed(Duration.zero);
      expect(halted, isFalse, reason: 'the pull is still out');

      gate.complete();
      await halting;
      await round;
      // The page that was in flight has landed BEFORE halt returned — a wipe
      // after it removes it; nothing arrives later.
      await wipeReplica(db);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await db.select(db.notifications).get(), isEmpty);
      expect(api.pulls, 1);
      engine.dispose();
    },
  );
}

class _GatedSyncApi implements SyncApi {
  _GatedSyncApi(this._gate);

  final Future<void> _gate;
  final pulling = Completer<void>();
  int pulls = 0;

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    pulls += 1;
    if (!pulling.isCompleted) pulling.complete();
    await _gate;
    return SyncPullPage(
      fromRevision: sinceRevision,
      toRevision: 1,
      hasMore: false,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_notification',
          entityId: 'N-late',
          operation: 'upsert',
          data: {
            'id': 'N-late',
            'workspaceId': workspaceId,
            'userId': 'saha3',
            'eventClass': 'ticket.status_changed',
            'titleKey': 'ee.notif.ticket.status_changed.title',
            'createdAt': '2026-10-07T08:00:00.000Z',
            'revision': 1,
            'updatedAt': '2026-10-07T08:00:00.000Z',
          },
        ),
      ],
    );
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async => SyncPushResponse(toRevision: baseRevision, results: const []);
}
