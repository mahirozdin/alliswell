import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/app_liveness.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/headless.dart';
import 'package:alliswell/src/sync/db/connection_native.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/local_data.dart';
import 'package:alliswell/src/sync/outbox.dart';

import '../features/auth/test_support.dart';
import '../support/fake_notifications.dart';
import '../support/fake_widget_host.dart';

const _ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String _id(String prefix) => prefix.padRight(26, '0');

/// headless-revocation-bypasses-cleanup (OPH-447) — the device is removed on
/// another device while this app is in the background, and the Android wake
/// turn is the first to hear the refresh refused as revoked. That turn must do
/// what the foreground does with a revoked family: drop every alarm of this
/// person from the OS (the presented one too) and wipe the replica when
/// nothing in it is unsent — never re-arm alarms from those rows. The next
/// launch restores no session, so nothing would ever clean it up later.
void main() {
  late Directory dir;
  late AwDatabase db;
  late FakeNotificationsGateway gateway;
  late InMemorySecretStore secrets;
  late FakeHttpClientAdapter server;

  // A file, not memory: the turn closes the database it opened, and the
  // checks read what it left with a connection of their own.
  AwDatabase open() =>
      AwDatabase(NativeDatabase(File('${dir.path}/alliswell.sqlite')));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aw-headless-revoked-');
    db = open();
    gateway = FakeNotificationsGateway();
    secrets = InMemorySecretStore();
    await TokenStorage(secrets).save(fakeSession());
    // Every call is refused: the access token is dead, and so is the family
    // behind the refresh token.
    server = FakeHttpClientAdapter((options, _) async {
      if (options.path == '/api/v1/auth/refresh') {
        return jsonBody(401, {
          'statusCode': 401,
          'code': 'AUTH_REFRESH_REUSED',
          'error': 'Unauthorized',
          'message': 'reuse detected',
        });
      }
      return jsonBody(401, {'statusCode': 401, 'code': 'AUTH_UNAUTHORIZED'});
    });

    await db
        .into(db.syncStates)
        .insert(SyncStatesCompanion.insert(workspaceId: _ws, clientId: 'C1'));
    final soon = DateTime.now().toUtc().add(const Duration(hours: 1));
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: _id('T1'),
            workspaceId: _ws,
            title: 'Görev T1',
            isUrgent: const Value(true),
            requiresAcknowledgement: const Value(true),
            remindAt: Value(soon),
          ),
        );
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: _id('R1'),
            taskId: _id('T1'),
            remindAt: soon,
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
    // An alarm of this person is already on screen.
    await gateway.schedule(
      PlannedNotification(
        id: 12,
        title: 'AllisWell',
        body: 'Görev T0',
        fireAt: DateTime.now().toUtc(),
        urgent: true,
        payload: '{}',
      ),
    );
    gateway.deliver(12);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> turn() async {
    await db.close();
    await runHeadlessRefresh(
      openDatabase: open,
      liveness: AppLiveness(_NeverKv()),
      openGateway: () => gateway,
      widgetHost: FakeWidgetHost(),
      secretStore: secrets,
      httpAdapter: server,
    );
    db = open();
  }

  test('a revoked family wipes the clean replica and drops every alarm, '
      'the ringing one included', () async {
    await turn();

    expect(
      server.requests.map((r) => r.path),
      contains('/api/v1/auth/refresh'),
    );
    expect(await TokenStorage(secrets).read(), isNull);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.reminders).get(), isEmpty);
    expect(await db.select(db.syncStates).get(), isEmpty);
    expect(gateway.scheduled, isEmpty, reason: 'nothing is re-armed');
    expect(gateway.active, isEmpty, reason: 'the shown alarm is dismissed');
  });

  test('with unsent changes the replica stays for the next sign-in, but no '
      'alarm is re-armed from it', () async {
    await enqueueMutation(
      db,
      workspaceId: _ws,
      entityType: 'task',
      entityId: _id('T1'),
      operation: 'update',
      patch: {'title': 'offline edit'},
    );

    await turn();

    expect(await TokenStorage(secrets).read(), isNull);
    expect(await unsentChangeCount(db), 1);
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(gateway.scheduled, isEmpty, reason: 'nothing is re-armed');
    expect(gateway.active, isEmpty);
  });

  test(
    'a refresh that only failed (expired, not revoked) re-arms as before',
    () async {
      server = FakeHttpClientAdapter((options, _) async {
        if (options.path == '/api/v1/auth/refresh') {
          return jsonBody(401, {
            'statusCode': 401,
            'code': 'AUTH_INVALID_REFRESH_TOKEN',
          });
        }
        return jsonBody(401, {'statusCode': 401, 'code': 'AUTH_UNAUTHORIZED'});
      });

      await turn();

      expect(await db.select(db.tasks).get(), hasLength(1));
      expect(gateway.scheduled, isNotEmpty);
    },
  );

  // headless-revocation-wipe-race: the app comes back to the foreground while
  // the background turn is cleaning up, and the person's edit commits through
  // the foreground's own connection. The empty-outbox check and the wipe are
  // one decision; an edit that lands around them is never deleted unasked.
  group('an edit the foreground commits during the cleanup survives it', () {
    late AwDatabase background;
    late AwDatabase foreground;

    // Two connections on one file, opened the way the app opens them.
    AwDatabase connect() => AwDatabase(
      NativeDatabase.createInBackground(
        File('${dir.path}/alliswell.sqlite'),
        setup: (raw) {
          for (final pragma in awSqlitePragmas) {
            raw.execute(pragma);
          }
        },
      ),
    );

    setUp(() async {
      await db.close();
      background = connect();
      foreground = connect();
    });

    tearDown(() async {
      await background.close();
      await foreground.close();
      db = open();
    });

    Future<void> edit(AwDatabase on) async {
      await on
          .into(on.tasks)
          .insert(
            TasksCompanion.insert(
              id: _id('T2'),
              workspaceId: _ws,
              title: 'yeni',
            ),
          );
      await enqueueMutation(
        on,
        workspaceId: _ws,
        entityType: 'task',
        entityId: _id('T2'),
        operation: 'create',
        patch: {'title': 'yeni'},
      );
    }

    Future<void> expectEditKept() async {
      final tasks = await foreground.select(foreground.tasks).get();
      expect(tasks.map((t) => t.id), contains(_id('T2')));
      expect(await unsentChangeCount(foreground), 1);
      expect(gateway.active, isEmpty, reason: 'the alarms still go');
    }

    test('committed while the cleanup reads whose replica it is', () async {
      final kv = _HookKv(
        onOwnerRead: () => foreground.transaction(() => edit(foreground)),
      );

      await endRevokedSessionHeadless(
        background,
        userId: 'U1',
        gateway: gateway,
        kv: kv,
      );

      await expectEditKept();
      expect(kv.removed, isFalse, reason: 'the owner record stays with it');
    });

    // SQLite either makes the cleanup wait for this write or refuses it the
    // lock; in neither case may it judge the outbox empty and then delete.
    test('still being written when the cleanup checks the outbox', () async {
      final inserted = Completer<void>();
      final release = Completer<void>();
      late Future<void> writing;
      final kv = _HookKv(
        onOwnerRead: () async {
          writing = foreground.transaction(() async {
            await edit(foreground);
            inserted.complete();
            await release.future;
          });
          await inserted.future;
          // The write lock is held; it commits once the cleanup is waiting.
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 300),
              release.complete,
            ),
          );
        },
      );

      await endRevokedSessionHeadless(
        background,
        userId: 'U1',
        gateway: gateway,
        kv: kv,
      );
      await writing;

      await expectEditKept();
    });

    test('a clean replica is still wiped', () async {
      final kv = _HookKv();

      await endRevokedSessionHeadless(
        background,
        userId: 'U1',
        gateway: gateway,
        kv: kv,
      );

      expect(await foreground.select(foreground.tasks).get(), isEmpty);
      expect(kv.removed, isTrue);
    });
  });
}

/// An empty store that runs [onOwnerRead] while the replica owner is read.
class _HookKv implements LocalKv {
  _HookKv({this.onOwnerRead});

  final Future<void> Function()? onOwnerRead;
  bool removed = false;

  @override
  Future<String?> get(String key) async {
    if (key == kReplicaOwnerKey) await onOwnerRead?.call();
    return null;
  }

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    removed = true;
  }
}

/// A store that remembers nothing — the ordinary "app is not running" state.
class _NeverKv implements LocalKv {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeWhere(bool Function(String key) test) async {}
}
