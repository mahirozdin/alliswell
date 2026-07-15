import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart' show SyncChange;
import 'package:alliswell/src/sync/sync_applier.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-081 — `calendarMirrorEnabled` end to end through the local-first stack.
/// The server has carried this field since OPH-072 (REST + sync push + pull
/// snapshots); until now the app dropped it on the floor at every layer.
void main() {
  group('replica carries the mirror flag (OPH-081)', () {
    late AwDatabase db;

    setUp(() => db = AwDatabase(DatabaseConnection(NativeDatabase.memory())));
    tearDown(() => db.close());

    test(
      'a pulled snapshot round-trips the flag instead of dropping it',
      () async {
        await applyPulledChanges(
          db,
          workspaceId: 'W1'.padRight(26, '0'),
          toRevision: 4,
          changes: [
            SyncChange(
              entityType: 'task',
              entityId: 'T1'.padRight(26, '0'),
              operation: 'update',
              revision: 4,
              data: {
                'id': 'T1'.padRight(26, '0'),
                'workspaceId': 'W1'.padRight(26, '0'),
                'title': 'Aynalanan iş',
                'calendarMirrorEnabled': true,
                'scheduledStartAt': '2030-06-05T14:00:00.000Z',
                'scheduledEndAt': '2030-06-05T15:00:00.000Z',
                'revision': 4,
              },
            ),
          ],
        );

        final row = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals('T1'.padRight(26, '0')))).getSingle();
        expect(row.calendarMirrorEnabled, isTrue);
        // The other half of OPH-076: a calendar drag lands on scheduled_*, so
        // the replica has to carry those too or the move is invisible.
        expect(row.scheduledStartAt, DateTime.utc(2030, 6, 5, 14));
        expect(row.scheduledEndAt, DateTime.utc(2030, 6, 5, 15));
      },
    );

    test('a missing flag defaults to off (old server, new app)', () async {
      await applyPulledChanges(
        db,
        workspaceId: 'W1'.padRight(26, '0'),
        toRevision: 1,
        changes: [
          SyncChange(
            entityType: 'task',
            entityId: 'T2'.padRight(26, '0'),
            operation: 'create',
            revision: 1,
            data: {
              'id': 'T2'.padRight(26, '0'),
              'workspaceId': 'W1'.padRight(26, '0'),
              'title': 'Alanı bilmeyen sunucu',
              'revision': 1,
            },
          ),
        ],
      );

      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('T2'.padRight(26, '0')))).getSingle();
      expect(row.calendarMirrorEnabled, isFalse);
    });

    test('a local toggle writes the row AND the outbox in one go', () async {
      final store = TaskStore(db, () {});
      final id = await store.create('W1'.padRight(26, '0'), {
        'title': 'Takvime koy',
        'dueAt': '2030-06-01T12:00:00.000Z',
      });

      await store.update(id, {'calendarMirrorEnabled': true});

      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.calendarMirrorEnabled, isTrue); // optimistic, visible at once

      // …and queued for the server, or the switch would snap back on the next pull.
      final queued = await (db.select(
        db.pendingMutations,
      )..where((m) => m.operation.equals('update'))).getSingle();
      expect(queued.patchJson, contains('calendarMirrorEnabled'));
      expect(queued.entityId, id);
    });
  });

  group('task detail (OPH-081)', () {
    Future<Widget> signedInAppWith(FakeApi api) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemorySecretStore();
      await TokenStorage(store).save(fakeSession());
      return ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      );
    }

    Future<Finder> openDetail(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      return find.descendant(
        of: find.byType(TaskDetailScreen),
        matching: find.byType(ListView),
      );
    }

    testWidgets('the switch reaches the server and explains itself', (
      tester,
    ) async {
      final api = FakeApi();
      api.seedTask(title: 'Takvimli iş', dueAt: '2030-06-01T12:00:00.000Z');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      final list = await openDetail(tester, 'Takvimli iş');
      final toggle = find.byKey(const Key('calendar-mirror-switch'));
      await tester.dragUntilVisible(toggle, list, const Offset(0, -120));

      // The task has a due date, so it has something to put on a calendar.
      expect(
        find.text('Adds a block to your connected calendar'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(api.tasks.single['calendarMirrorEnabled'], isTrue);
    });

    testWidgets('a task with no dates says why nothing will show up', (
      tester,
    ) async {
      final api = FakeApi();
      api.seedTask(title: 'Tarihsiz iş');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      final list = await openDetail(tester, 'Tarihsiz iş');
      final toggle = find.byKey(const Key('calendar-mirror-switch'));
      await tester.dragUntilVisible(toggle, list, const Offset(0, -120));

      // Honest instead of silently doing nothing — and still switchable, since
      // adding a date later starts the mirror on its own.
      expect(find.text('Add a date below and it will appear'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(api.tasks.single['calendarMirrorEnabled'], isTrue);
    });

    testWidgets('a scheduled block arriving from the calendar is visible', (
      tester,
    ) async {
      final api = FakeApi();
      // What OPH-076 writes when the user drags our event in Google.
      api.seedTask(
        title: 'Sürüklenmiş iş',
        scheduledStartAt: '2030-06-05T14:00:00.000Z',
        scheduledEndAt: '2030-06-05T15:00:00.000Z',
      );
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      final list = await openDetail(tester, 'Sürüklenmiş iş');
      final row = find.byKey(const Key('scheduled-row'));
      await tester.dragUntilVisible(row, list, const Offset(0, -120));

      expect(find.text('Scheduled'), findsOneWidget);
      final local = DateTime.utc(2030, 6, 5, 14).toLocal();
      expect(
        find.descendant(
          of: row,
          matching: find.text(local.toString().split('.').first),
        ),
        findsOneWidget,
      );
    });
  });
}
