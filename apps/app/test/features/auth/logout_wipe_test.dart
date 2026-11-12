import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/server_url.dart';
import 'package:alliswell/src/features/auth/data/auth_api.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/auth/ui/sign_out.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/sync/db/connection_native.dart'
    show awSqlitePragmas;
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/outbox.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

import '../../support/fake_notifications.dart';
import 'test_support.dart';

/// UI-AUDIT #3 / OPH-355 — signing out leaves nothing of the person behind.
///
/// The audit signed saha3 out of a browser and found the whole replica still
/// there: 248 IndexedDB blocks, request texts readable, and saha3's request
/// notifications in saha2's centre once saha2 signed in. Sign-out now wipes the
/// replica and the person's cached facts — after asking, when something
/// unsent would go with them.
void main() {
  const ws = 'W1';
  const marker = 'VPN-ERISIM-GIZLI-METIN';

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.removeWhere((_) => true);
  });

  /// What a person's session leaves in the replica: a notification carrying a
  /// request's words, the sync cursor, and the device's own alarm log.
  Future<void> seedPersonalRows(
    AwDatabase db, {
    String userId = 'user-1',
  }) async {
    await applyPulledChanges(
      db,
      workspaceId: ws,
      changes: [
        SyncChange(
          revision: 1,
          entityType: 'ee_notification',
          entityId: 'N1',
          operation: 'upsert',
          data: {
            'id': 'N1',
            'workspaceId': ws,
            'userId': userId,
            'eventClass': 'ticket.status_changed',
            'titleKey': 'ee.notif.ticket.status_changed.title',
            'params': {'ticketRef': '#222', 'subject': marker},
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
    await db
        .into(db.syncStates)
        .insert(SyncStatesCompanion.insert(workspaceId: ws, clientId: 'C1'));
    await db
        .into(db.alarmEvents)
        .insert(
          AlarmEventsCompanion.insert(
            at: DateTime.utc(2026, 10, 7),
            event: 'scheduled',
            lane: 'notification',
          ),
        );
  }

  /// A minimal signed-in app: one button that signs out the way Settings does.
  Future<(ProviderContainer, AwDatabase)> pumpSignedIn(
    WidgetTester tester, {
    String? refreshRefusedWith,
    List<Override> overrides = const [],
  }) async {
    final db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
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
                      'message': 'Invalid or expired refresh token',
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
          ...overrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => signOutWithConfirm(context, ref),
                child: const Text('sign-out'),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('sign-out')),
    );
    await tester.runAsync(() async {
      await container.read(authControllerProvider.future);
      await container
          .read(authControllerProvider.notifier)
          .login(email: 'mahir@example.com', password: 'pw');
    });
    expect(container.read(authControllerProvider).value?.user.id, 'user-1');
    return (container, db);
  }

  Future<Map<String, int>> counts(AwDatabase db) async => {
    for (final table in db.allTables)
      table.actualTableName:
          (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM ${table.actualTableName}',
                  )
                  .getSingle())
              .read<int>('n'),
  };

  testWidgets(
    'UI-AUDIT #3: sign-out empties the replica and the person\'s keys; '
    'device settings stay',
    (tester) async {
      final (container, db) = await pumpSignedIn(tester);
      await tester.runAsync(() async {
        await seedPersonalRows(db);
        // The person's small facts …
        await localKv.set('${kWorkspacesCachePrefix}user-1', '[]');
        await localKv.set('${kSelectedWorkspacePrefix}user-1', ws);
        await localKv.set('alliswell_ee_permissions::user-1::$ws', '{}');
        await localKv.set('alliswell_ee_approvals_door::user-1::acme', '{}');
        await localKv.set('alliswell_created_by_repull::$ws', '1');
        // … and the device's.
        await localKv.set(kServerUrlPrefKey, 'https://acme.example.com');
        await localKv.set(kAwLocalePrefKey, 'tr');
        await localKv.set('alliswell_date_format', 'dmy');
      });
      expect(
        await tester.runAsync(() => localKv.get(kReplicaOwnerKey)),
        'user-1',
      );

      await tester.tap(find.text('sign-out'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      // Nothing unsent → nothing to ask.
      expect(find.byKey(const Key('sign-out-unsent-dialog')), findsNothing);
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (await localKv.get(kReplicaOwnerKey) == null) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(container.read(authControllerProvider).value, isNull);
      final after = (await tester.runAsync(() => counts(db)))!;
      for (final entry in after.entries) {
        if (entry.key == 'alarm_events') continue;
        expect(entry.value, 0, reason: '${entry.key} must be empty');
      }
      // The device's own content-free diagnostic log is the device's.
      expect(after['alarm_events'], 1);

      final kv = (await tester.runAsync(
        () async => {
          for (final key in [
            '${kWorkspacesCachePrefix}user-1',
            '${kSelectedWorkspacePrefix}user-1',
            'alliswell_ee_permissions::user-1::$ws',
            'alliswell_ee_approvals_door::user-1::acme',
            'alliswell_created_by_repull::$ws',
            kReplicaOwnerKey,
            kServerUrlPrefKey,
            kAwLocalePrefKey,
            'alliswell_date_format',
          ])
            key: await localKv.get(key),
        },
      ))!;
      expect(kv['${kWorkspacesCachePrefix}user-1'], isNull);
      expect(kv['${kSelectedWorkspacePrefix}user-1'], isNull);
      expect(kv['alliswell_ee_permissions::user-1::$ws'], isNull);
      expect(kv['alliswell_ee_approvals_door::user-1::acme'], isNull);
      expect(kv['alliswell_created_by_repull::$ws'], isNull);
      expect(kv[kReplicaOwnerKey], isNull);
      expect(kv[kServerUrlPrefKey], 'https://acme.example.com');
      expect(kv[kAwLocalePrefKey], 'tr');
      expect(kv['alliswell_date_format'], 'dmy');
    },
  );

  testWidgets(
    'UI-AUDIT #3: unsent changes are counted and asked about; cancel keeps '
    'everything, confirm deletes it',
    (tester) async {
      final (container, db) = await pumpSignedIn(tester);
      await tester.runAsync(() async {
        await seedPersonalRows(db);
        await enqueueMutation(
          db,
          workspaceId: ws,
          entityType: 'task',
          entityId: 'T1',
          operation: 'update',
          patch: {'title': marker},
        );
        await db
            .into(db.rejectedMutations)
            .insert(
              RejectedMutationsCompanion.insert(
                id: 'R1',
                workspaceId: ws,
                entityType: 'task',
                entityId: 'T2',
                operation: 'update',
                patchJson: Value(jsonEncode({'title': 'kept'})),
                rejectedAt: DateTime.utc(2026, 10, 7),
              ),
            );
      });
      expect(await tester.runAsync(() => unsentChangeCount(db)), 2);

      await tester.tap(find.text('sign-out'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-out-unsent-dialog')), findsOneWidget);
      expect(find.textContaining('2 changes'), findsOneWidget);

      // Cancel: still signed in, nothing touched.
      await tester.tap(find.byKey(const Key('sign-out-unsent-cancel')));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).value, isNotNull);
      expect(await tester.runAsync(() => unsentChangeCount(db)), 2);

      // Confirm: signed out, and the outbox is gone with the rest.
      await tester.tap(find.text('sign-out'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-out-unsent-confirm')));
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (await localKv.get(kReplicaOwnerKey) == null) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).value, isNull);
      expect(await tester.runAsync(() => unsentChangeCount(db)), 0);
      expect(
        await tester.runAsync(() => db.select(db.notifications).get()),
        isEmpty,
      );
    },
  );

  // OPH-447 (#48) — "remove this device" on another device revokes the
  // session family bound to it. The next refresh here is refused, and that
  // must leave this device exactly as a sign-out does: signed out, the replica
  // and the person's facts gone, and no alarm of theirs left in the OS.
  testWidgets('a revoked family signs this device out and wipes local data', (
    tester,
  ) async {
    final gateway = FakeNotificationsGateway();
    final alarmKit = FakeAlarmKitHost();
    final (container, db) = await pumpSignedIn(
      tester,
      refreshRefusedWith: 'AUTH_REFRESH_REUSED',
      overrides: [
        notificationsGatewayProvider.overrideWithValue(gateway),
        alarmKitHostProvider.overrideWithValue(alarmKit),
      ],
    );
    await tester.runAsync(() async {
      await seedPersonalRows(db);
      await localKv.set('${kWorkspacesCachePrefix}user-1', '[]');
      await localKv.set(kServerUrlPrefKey, 'https://acme.example.com');
      // What the scheduler left in the OS for this person.
      await gateway.schedule(
        PlannedNotification(
          id: 11,
          title: 'AllisWell',
          body: marker,
          fireAt: DateTime.utc(2026, 11, 13, 9),
          urgent: true,
          payload: '{}',
        ),
      );
      alarmKit.foreign[22] = const AlarmKitScheduled(id: 22);
      // revocation-leaves-delivered-alarm: one alarm is already presented —
      // an Android notification looping its sound, an AlarmKit alert on the
      // screen. Signed out, nothing in the app can silence them any more.
      await gateway.schedule(
        PlannedNotification(
          id: 12,
          title: 'AllisWell',
          body: marker,
          fireAt: DateTime.utc(2026, 11, 12, 9),
          urgent: true,
          payload: '{}',
        ),
      );
      gateway.deliver(12);
      alarmKit.foreign[23] = const AlarmKitScheduled(
        id: 23,
        state: AlarmKitAlarmState.alerting,
      );
    });

    final token = await tester.runAsync(
      () => container.read(authRepositoryProvider).refreshAccessToken(),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (await localKv.get(kReplicaOwnerKey) == null &&
            alarmKit.cancelled.length >= 2) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(token, isNull);
    expect(container.read(authControllerProvider).value, isNull);
    final after = (await tester.runAsync(() => counts(db)))!;
    for (final entry in after.entries) {
      if (entry.key == 'alarm_events') continue;
      expect(entry.value, 0, reason: '${entry.key} must be empty');
    }
    expect(
      await tester.runAsync(
        () => localKv.get('${kWorkspacesCachePrefix}user-1'),
      ),
      isNull,
    );
    expect(await tester.runAsync(() => localKv.get(kReplicaOwnerKey)), isNull);
    // The device's own settings stay, as on a sign-out.
    expect(
      await tester.runAsync(() => localKv.get(kServerUrlPrefKey)),
      'https://acme.example.com',
    );
    expect(gateway.scheduled, isEmpty);
    expect(gateway.active, isEmpty, reason: 'the presented alarm is dismissed');
    expect(gateway.cancelled, containsAll([11, 12]));
    expect(alarmKit.stopped, [23], reason: 'the alerting alarm is silenced');
    expect(alarmKit.cancelled, containsAll([22, 23]));
  });

  // OPH-355's rule holds here too: an unsent change is never lost without the
  // person being asked. A revoked family with an outbox signs out and drops
  // the alarms, but keeps the replica for the same person's next sign-in
  // (claimFor adopts it; anyone else's sign-in wipes it).
  testWidgets('a revoked family with unsent changes signs out but keeps them', (
    tester,
  ) async {
    final gateway = FakeNotificationsGateway();
    final alarmKit = FakeAlarmKitHost();
    final (container, db) = await pumpSignedIn(
      tester,
      refreshRefusedWith: 'AUTH_REFRESH_REUSED',
      overrides: [
        notificationsGatewayProvider.overrideWithValue(gateway),
        alarmKitHostProvider.overrideWithValue(alarmKit),
      ],
    );
    await tester.runAsync(() async {
      await seedPersonalRows(db);
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: 'T1',
        operation: 'update',
        patch: {'title': marker},
      );
      alarmKit.foreign[22] = const AlarmKitScheduled(id: 22);
    });

    await tester.runAsync(
      () => container.read(authRepositoryProvider).refreshAccessToken(),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (alarmKit.cancelled.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).value, isNull);
    expect(await tester.runAsync(() => unsentChangeCount(db)), 1);
    expect((await tester.runAsync(() => counts(db)))!['sync_states'], 1);
    expect(
      await tester.runAsync(() => localKv.get(kReplicaOwnerKey)),
      'user-1',
    );
    expect(alarmKit.cancelled, [22]);
  });

  // An expired refresh token (left unopened past AUTH_REFRESH_TTL_DAYS) is
  // refused with AUTH_INVALID_REFRESH_TOKEN, the same code as an unknown one:
  // nothing says the device was removed, so it signs out as before and keeps
  // its offline edits for the next sign-in.
  testWidgets('an expired refresh token signs out and wipes nothing', (
    tester,
  ) async {
    final alarmKit = FakeAlarmKitHost();
    final (container, db) = await pumpSignedIn(
      tester,
      refreshRefusedWith: 'AUTH_INVALID_REFRESH_TOKEN',
      overrides: [alarmKitHostProvider.overrideWithValue(alarmKit)],
    );
    await tester.runAsync(() async {
      await seedPersonalRows(db);
      await enqueueMutation(
        db,
        workspaceId: ws,
        entityType: 'task',
        entityId: 'T1',
        operation: 'update',
        patch: {'title': marker},
      );
      alarmKit.foreign[22] = const AlarmKitScheduled(id: 22);
    });

    final token = await tester.runAsync(
      () => container.read(authRepositoryProvider).refreshAccessToken(),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(token, isNull);
    expect(container.read(authControllerProvider).value, isNull);
    expect(await tester.runAsync(() => unsentChangeCount(db)), 1);
    expect((await tester.runAsync(() => counts(db)))!['sync_states'], 1);
    expect(
      await tester.runAsync(() => localKv.get(kReplicaOwnerKey)),
      'user-1',
    );
    expect(alarmKit.cancelled, isEmpty);
  });

  testWidgets('a refresh that only failed to arrive wipes nothing', (
    tester,
  ) async {
    final (container, db) = await pumpSignedIn(
      tester,
      refreshRefusedWith: 'RATE_LIMITED',
    );
    await tester.runAsync(() => seedPersonalRows(db));

    await tester.runAsync(
      () => container.read(authRepositoryProvider).refreshAccessToken(),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    final after = (await tester.runAsync(() => counts(db)))!;
    expect(after['sync_states'], 1);
    expect(
      await tester.runAsync(() => localKv.get(kReplicaOwnerKey)),
      'user-1',
    );
  });

  test(
    'UI-AUDIT #3: the wiped words are gone from the file, not just unlinked',
    () async {
      // The audit read request texts straight out of the browser's storage
      // after sign-out. A DELETE alone leaves the bytes in free pages; the
      // wipe must leave nothing readable on disk — WAL included.
      final dir = await Directory.systemTemp.createTemp('aw-wipe-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/alliswell.sqlite');
      final db = AwDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            for (final pragma in awSqlitePragmas) {
              raw.execute(pragma);
            }
          },
        ),
      );
      await seedPersonalRows(db);
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      bool onDisk() => [file, File('${file.path}-wal')]
          .where((f) => f.existsSync())
          .any((f) => latin1.decode(f.readAsBytesSync()).contains(marker));
      expect(onDisk(), isTrue, reason: 'the marker is on disk to begin with');

      await wipeReplica(db);
      await db.close();

      expect(onDisk(), isFalse);
    },
  );
}
