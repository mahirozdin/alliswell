import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/notifications_providers.dart';
import 'package:alliswell/src/features/ee/ui/notification_badge.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// EE-077 — the centre's data and the badge, from the replica.
///
/// The acceptance says the badge count is LIVE FROM THE DRIFT STREAM. That is
/// the claim worth testing, because the wrong implementation — a count fetched
/// once, or refreshed on a timer — looks identical on screen until the moment
/// it matters: a pull arrives and the number does not move. So every case here
/// writes through `applyPulledChanges`, the same switch a real pull uses, and
/// asserts what the widget shows AFTERWARDS without anyone telling it to
/// refresh.
void main() {
  late AwDatabase db;
  const ws = 'W1';
  const me = 'U1';

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    AwI18n.instance.setActiveCached(const Locale('en'));
  });
  tearDown(() => db.close());

  /// One pulled change, applied the way the engine applies it.
  Future<void> pull(String id, {Map<String, dynamic>? data}) =>
      applyPulledChanges(
        db,
        workspaceId: ws,
        changes: [
          SyncChange(
            revision: 1,
            entityType: 'ee_notification',
            entityId: id,
            operation: data == null ? 'delete' : 'upsert',
            data: data,
          ),
        ],
        toRevision: 1,
      );

  Map<String, dynamic> notification(
    String id, {
    String titleKey = 'ee.notif.task.assigned.title',
    Map<String, dynamic>? params,
    String? readAt,
    String createdAt = '2026-08-24T10:00:00.000Z',
  }) => {
    'id': id,
    'workspaceId': ws,
    'userId': me,
    'eventClass': 'task.assigned',
    'titleKey': titleKey,
    'bodyKey': 'ee.notif.task.assigned.body',
    'params': params ?? {'taskTitle': 'Kompresör bakımı', 'actorName': 'Ayla'},
    'entityType': 'task',
    'entityId': 'T1',
    'readAt': readAt,
    'createdAt': createdAt,
    'revision': 1,
    'updatedAt': createdAt,
  };

  ProviderContainer containerWith() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: ws,
              name: 'Saha',
              slug: 'saha',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<NotificationItem>> readCentre(ProviderContainer container) async {
    final sub = container.listen(
      notificationCenterProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return container.read(notificationCenterProvider.future);
  }

  test(
    'a pulled notification reaches the centre with its keys and params',
    () async {
      await pull('N1', data: notification('N1'));
      final rows = await readCentre(containerWith());

      expect(rows, hasLength(1));
      expect(rows.first.titleKey, 'ee.notif.task.assigned.title');
      // Params survive as a MAP, not as the JSON string the row stores. A string
      // here would print quotes and braces on somebody's screen.
      expect(rows.first.params['taskTitle'], 'Kompresör bakımı');
      expect(rows.first.isUnread, isTrue);
      expect(rows.first.destination, '/tasks/T1');
    },
  );

  test(
    'a malformed params payload costs one subtitle, not the whole pull',
    () async {
      // The decode happens at draw time precisely so this is survivable.
      await db.customStatement(
        "INSERT INTO notifications (id, workspace_id, user_id, event_class, "
        "title_key, params, revision) VALUES "
        "('N9', '$ws', '$me', 'task.assigned', 'ee.notif.task.assigned.title', "
        "'{not json', 0)",
      );
      final rows = await readCentre(containerWith());
      expect(rows, hasLength(1));
      expect(rows.first.params, isEmpty);
    },
  );

  test('a tombstone removes it — the server no longer holds it, nor does this '
      'phone', () async {
    await pull('N1', data: notification('N1'));
    await pull('N1');
    expect(await readCentre(containerWith()), isEmpty);
  });

  test(
    'a row that points at a type this build cannot route stays a plain line',
    () async {
      await pull(
        'N2',
        data: {...notification('N2'), 'entityType': 'ticket', 'entityId': 'K1'},
      );
      final rows = await readCentre(containerWith());
      // No dead controls (DESIGN §22): E09 has not shipped a ticket route yet,
      // so tapping must do nothing rather than land on an error page.
      expect(rows.first.destination, isNull);
    },
  );

  testWidgets('the badge counts unread, and MOVES when a pull arrives', (
    tester,
  ) async {
    final container = containerWith();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: AwNotificationBadge())),
      ),
    );
    await tester.pumpAndSettle();
    // Zero draws NOTHING: a badge that is always there stops being a signal.
    expect(find.byKey(const Key('notif-badge')), findsNothing);

    await pull('N1', data: notification('N1'));
    await pull('N2', data: notification('N2'));
    await tester.pumpAndSettle();

    // Nobody told it to refresh. This is the acceptance's "live from the drift
    // stream", and the fetched-once implementation fails exactly here.
    expect(find.text('2'), findsOneWidget);

    await pull('N3', data: notification('N3', readAt: '2026-08-24T11:00:00Z'));
    await tester.pumpAndSettle();
    // A read one does not count — the badge is unread, not total.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a big number becomes 99+ rather than a layout problem', (
    tester,
  ) async {
    for (var i = 0; i < 101; i++) {
      await pull('N$i', data: notification('N$i'));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: containerWith(),
        child: const MaterialApp(home: Scaffold(body: AwNotificationBadge())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
  });

  test(
    'marking read is a local write AND a queued mutation, in one breath',
    () async {
      await pull('N1', data: notification('N1'));
      final store = NotificationStore(db);

      await store.markRead('N1');

      final row = await (db.select(
        db.notifications,
      )..where((n) => n.id.equals('N1'))).getSingle();
      expect(row.readAt, isNotNull);

      final queued = await db.select(db.pendingMutations).get();
      expect(queued, hasLength(1));
      expect(queued.first.entityType, 'ee_notification');
      expect(queued.first.operation, 'update');
      // A badge that dropped with no mutation behind it would be a promise
      // nothing keeps.
      expect(queued.first.patchJson, contains('readAt'));
    },
  );

  test('marking an already-read one writes nothing at all', () async {
    await pull('N1', data: notification('N1', readAt: '2026-08-24T11:00:00Z'));
    await NotificationStore(db).markRead('N1');
    // No row, no mutation, no push: tapping something already read must not
    // queue traffic (the "no-op writes nothing" invariant, on this side).
    expect(await db.select(db.pendingMutations).get(), isEmpty);
  });

  test(
    'mark-all-read queues one mutation per row, not one bulk verb',
    () async {
      await pull('N1', data: notification('N1'));
      await pull('N2', data: notification('N2'));
      await pull(
        'N3',
        data: notification('N3', readAt: '2026-08-24T11:00:00Z'),
      );

      final count = await NotificationStore(db).markAllRead();

      expect(count, 2);
      final queued = await db.select(db.pendingMutations).get();
      // The server has no bulk verb, and inventing a client-only one would make
      // the two paths disagree the first time a push failed halfway.
      expect(queued, hasLength(2));
    },
  );
}
