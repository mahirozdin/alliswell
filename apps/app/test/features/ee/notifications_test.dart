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
        currentUserIdProvider.overrideWithValue(me),
        // The list the current workspace comes from, so everything derived
        // from it — which workspaces sync, and so what the badge counts —
        // agrees with the override below (EE-296).
        workspacesProvider.overrideWith(
          (ref) async => const [
            WorkspaceSummary(
              id: ws,
              name: 'Saha',
              slug: 'saha',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ],
        ),
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
      // No dead controls (DESIGN §22): `ticket` is not a type this build
      // routes (the ticket's type is `ee_ticket`, EE-251), so tapping must do
      // nothing rather than land on an error page.
      expect(rows.first.destination, isNull);
    },
  );

  // ── EE-230: approvals ────────────────────────────────────────────────

  test('an approval outcome is drawn in the device\'s language, over the raw '
      'word an integration reads', () async {
    await pull(
      'N5',
      data: {
        ...notification('N5', titleKey: 'ee.notif.approval.decided.title'),
        'eventClass': 'approval.decided',
        'bodyKey': 'ee.notif.approval.decided.body',
        'params': {
          // Both travel: the machine word for webhooks, the KEY for people.
          'decision': 'rejected',
          'decisionKey': 'ee.notif.approval.decision.rejected',
          'detail': '#1042 — Dizüstü bilgisayar — “bütçe yok”',
        },
        'entityType': 'ee_ticket',
        'entityId': 'K1',
      },
    );
    final row = (await readCentre(containerWith())).single;
    expect(row.args['decision'], 'Your approval request was rejected');
    expect(
      row.titleKey.tr(args: row.args),
      'Your approval request was rejected',
    );
    expect(
      row.bodyKey!.tr(args: row.args),
      '#1042 — Dizüstü bilgisayar — “bütçe yok”',
    );

    // The same stored row, read on a phone set to Turkish: the KEY was kept,
    // so the sentence follows the device, not the server's language.
    AwI18n.instance.setActiveCached(const Locale('tr'));
    expect(row.args['decision'], 'Onay isteğiniz reddedildi');
    // EE-251: a request has an address now, so the outcome opens it.
    expect(row.destination, '/tickets/K1');
  });

  test('an approval request opens the screen where it is answered', () async {
    await pull(
      'N6',
      data: {
        ...notification('N6', titleKey: 'ee.notif.approval.requested.title'),
        'eventClass': 'approval.requested',
        'bodyKey': 'ee.notif.approval.requested.body',
        'params': {'summary': '#1042 — Dizüstü bilgisayar'},
        'entityType': 'ee_approval',
        'entityId': 'A1',
      },
    );
    final row = (await readCentre(containerWith())).single;
    // EE-295: the approval itself, read whole — not Settings, not the list.
    expect(row.destination, '/approvals/A1');
    expect(row.titleKey.tr(args: row.args), 'Your approval is needed');
    expect(row.bodyKey!.tr(args: row.args), '#1042 — Dizüstü bilgisayar');
  });

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

      final count = await NotificationStore(db).markAllRead(const [ws]);

      expect(count, 2);
      final queued = await db.select(db.pendingMutations).get();
      // The server has no bulk verb, and inventing a client-only one would make
      // the two paths disagree the first time a push failed halfway.
      expect(queued, hasLength(2));
    },
  );

  test(
    "EE-296: the centre and the badge gather every unit this device syncs",
    () async {
      // A member of an organisation syncs each of their units. What happened
      // to them in one unit is news whichever unit is on screen: a request
      // assigned in another unit reached the centre only once they switched.
      const other = 'W2';
      await pull('N1', data: notification('N1'));
      await applyPulledChanges(
        db,
        workspaceId: other,
        changes: [
          SyncChange(
            revision: 1,
            entityType: 'ee_notification',
            entityId: 'N2',
            operation: 'upsert',
            data: {
              ...notification('N2', createdAt: '2026-08-24T12:00:00.000Z'),
              'workspaceId': other,
            },
          ),
        ],
        toRevision: 1,
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue(me),
          syncWorkspaceIdsProvider.overrideWithValue(const [ws, other]),
        ],
      );
      addTearDown(container.dispose);

      final rows = await readCentre(container);
      expect([for (final r in rows) r.id], ['N2', 'N1']);
      final badge = container.listen(
        unreadNotificationCountProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(badge.close);
      expect(await container.read(unreadNotificationCountProvider.future), 2);

      expect(await NotificationStore(db).markAllRead(const [ws, other]), 2);
      final queued = await db.select(db.pendingMutations).get();
      // Each mark goes out through its own workspace's outbox.
      expect({for (final m in queued) m.workspaceId}, {ws, other});
    },
  );

  test(
    'EE-251: a ticket notification opens the ticket at its address',
    () async {
      await pull(
        'N7',
        data: {
          ...notification('N7', titleKey: 'ee.notif.ticket.assigned.title'),
          'eventClass': 'ticket.assigned',
          'entityType': 'ee_ticket',
          'entityId': '01JABCDEFGHJKMNPQRSTVWXYZ0',
        },
      );
      final row = (await readCentre(containerWith())).single;
      expect(row.destination, '/tickets/01JABCDEFGHJKMNPQRSTVWXYZ0');
    },
  );

  test(
    "UI-AUDIT #3: the centre and the badge show only the signed-in person's rows",
    () async {
      // Saha3's request notifications were still in the replica when saha2
      // signed in on the same browser, and the centre — filtering by unit
      // only — listed them. Sign-out wipes the replica now (OPH-355); this
      // is the second wall, for a row that outlives it anyway.
      await pull('N1', data: notification('N1'));
      await pull(
        'N2',
        data: {
          ...notification('N2', createdAt: '2026-08-24T12:00:00.000Z'),
          'userId': 'U-previous',
          'params': {'taskTitle': 'VPN erişimi', 'actorName': 'Saha3'},
        },
      );
      final container = containerWith();

      final rows = await readCentre(container);
      expect([for (final r in rows) r.id], ['N1']);
      final badge = container.listen(
        unreadNotificationCountProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(badge.close);
      expect(await container.read(unreadNotificationCountProvider.future), 1);

      // "Mark all read" marks what the centre lists — not somebody else's row.
      expect(
        await NotificationStore(db).markAllRead(const [ws], userId: me),
        1,
      );
      final queued = await db.select(db.pendingMutations).get();
      expect([for (final m in queued) m.entityId], ['N1']);
    },
  );

  test('UI-AUDIT #3: signed out, the centre and the badge are empty', () async {
    await pull('N1', data: notification('N1'));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(null),
        syncWorkspaceIdsProvider.overrideWithValue(const [ws]),
      ],
    );
    addTearDown(container.dispose);
    expect(await readCentre(container), isEmpty);
    final badge = container.listen(
      unreadNotificationCountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(badge.close);
    expect(await container.read(unreadNotificationCountProvider.future), 0);
  });
}
