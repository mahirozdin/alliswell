import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ui/assignee_avatars.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// EE-068 — the avatar row, the join behind it, and the write path.
///
/// The claim under test that would be easiest to get wrong is the MISS: an
/// assignment whose roster row is gone. Item 9's churn case is somebody who
/// left the unit, and the wrong answer — dropping the avatar — would make a
/// task look unowned on this device and owned on every other one. The right
/// answer is a tombstone avatar, and it stays until the server releases the
/// assignment.
void main() {
  late AwDatabase db;
  const ws = 'W1';
  const task = 'T1';

  setUp(() {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    AwI18n.instance.setActiveCached(const Locale('en'));
  });
  tearDown(() => db.close());

  /// Riverpod keeps a provider alive only while something listens; reading
  /// `.future` on a stream nobody subscribed to hangs rather than answering.
  /// The subscription is the point, not ceremony.
  Future<List<Assignee>> readAssignees(String taskId) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      taskAssigneesProvider(taskId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return container.read(taskAssigneesProvider(taskId).future);
  }

  /// One pulled change, applied the way a real pull applies it — through
  /// `applyPulledChanges`, not through a private helper, so the test exercises
  /// the same switch the engine does.
  Future<void> pull(
    String entityType,
    String entityId, {
    Map<String, dynamic>? data,
  }) => applyPulledChanges(
    db,
    workspaceId: ws,
    toRevision: 1,
    changes: [
      SyncChange(
        entityType: entityType,
        entityId: entityId,
        operation: data == null ? 'delete' : 'create',
        revision: 1,
        data: data,
      ),
    ],
  );

  Future<void> profile(String userId, String name, String colour) => db
      .into(db.memberProfiles)
      .insert(
        MemberProfilesCompanion.insert(
          id: 'P-$userId',
          workspaceId: ws,
          userId: userId,
          displayName: Value(name),
          initials: Value(name.substring(0, 2).toUpperCase()),
          colorRgb: colour,
        ),
      );

  Future<void> assignment(String id, String userId, {String taskId = task}) =>
      db
          .into(db.taskAssignments)
          .insert(
            TaskAssignmentsCompanion.insert(
              id: id,
              workspaceId: ws,
              taskId: taskId,
              userId: userId,
              assignedAt: Value(DateTime.utc(2026, 8, 22)),
            ),
          );

  group('the roster reaches the replica at all (the EE-017 repair)', () {
    test('a member profile snapshot is stored, not dropped', () async {
      await pull(
        'ee_member_profile',
        'P1',
        data: {
          'id': 'P1',
          'workspaceId': ws,
          'userId': 'U1',
          'displayName': 'Ayla Yönetici',
          'initials': 'AY',
          'colorRgb': '#2563EB',
          'revision': 4,
          'updatedAt': '2026-08-22T00:00:00.000Z',
        },
      );
      final rows = await db.select(db.memberProfiles).get();
      // Before EE-068 the applier had no case for this type and the switch has
      // no default, so every one of these went to the floor in silence.
      expect(rows, hasLength(1));
      expect(rows.single.displayName, 'Ayla Yönetici');
      expect(rows.single.colorRgb, '#2563EB');
    });

    test(
      'an assignment snapshot is stored, and a tombstone removes it',
      () async {
        await pull(
          'ee_task_assignment',
          'A1',
          data: {
            'id': 'A1',
            'workspaceId': ws,
            'taskId': task,
            'userId': 'U1',
            'assignedBy': 'U2',
            'assignedAt': '2026-08-22T00:00:00.000Z',
            'revision': 5,
            'updatedAt': '2026-08-22T00:00:00.000Z',
          },
        );
        expect(await db.select(db.taskAssignments).get(), hasLength(1));
        await pull('ee_task_assignment', 'A1');
        expect(await db.select(db.taskAssignments).get(), isEmpty);
      },
    );

    test('losing a roster row does NOT cascade the assignment away', () async {
      await profile('U1', 'Ayla', '#2563EB');
      await assignment('A1', 'U1');
      await pull('ee_member_profile', 'P-U1');
      // The person left the unit; the work is still theirs until the server
      // says otherwise. Dropping it here would disagree with every other
      // device that has the same assignment.
      expect(await db.select(db.taskAssignments).get(), hasLength(1));
      expect(await db.select(db.memberProfiles).get(), isEmpty);
    });
  });

  group('the join', () {
    test('names and colours come from the roster', () async {
      await profile('U1', 'Ayla', '#2563EB');
      await assignment('A1', 'U1');
      final assignees = await readAssignees(task);
      expect(assignees, hasLength(1));
      expect(assignees.single.displayName, 'Ayla');
      expect(assignees.single.colorRgb, '#2563EB');
      expect(assignees.single.isKnown, isTrue);
    });

    test('a missing roster row is a KNOWN state, not an absent row', () async {
      await assignment('A1', 'U-GONE');
      final assignees = await readAssignees(task);
      expect(assignees, hasLength(1));
      expect(assignees.single.isKnown, isFalse);
      expect(assignees.single.userId, 'U-GONE');
    });
  });

  group('the avatar', () {
    Future<void> pump(WidgetTester tester, Assignee assignee) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: AwAssigneeAvatar(assignee: assignee)),
            ),
          ),
        );

    testWidgets('a known person shows their initials', (tester) async {
      await pump(
        tester,
        const Assignee(
          assignmentId: 'A1',
          userId: 'U1',
          displayName: 'Ayla Yönetici',
          initials: 'AY',
          colorRgb: '#2563EB',
        ),
      );
      expect(find.text('AY'), findsOneWidget);
    });

    testWidgets('a former member shows a tombstone, never a blank', (
      tester,
    ) async {
      await pump(tester, const Assignee(assignmentId: 'A1', userId: 'U-GONE'));
      // Not their initials (we do not have them) and not nothing: a mark that
      // says somebody is here and is no longer one of us.
      expect(find.text('—'), findsOneWidget);
      expect(find.byKey(const Key('assignee-U-GONE')), findsOneWidget);
    });

    testWidgets('the colour never becomes the contrast', (tester) async {
      // The ring carries the shape (OPH-199's idiom) — a fill-only avatar
      // would fail 3:1 for half the roster palette, measured in contrast.py.
      await pump(
        tester,
        const Assignee(
          assignmentId: 'A1',
          userId: 'U1',
          initials: 'AY',
          colorRgb: '#CA8A04', // the worst entry in the palette
        ),
      );
      // The key is ON the container, so this is byKey — `descendant` would
      // look strictly below it and find nothing.
      final circle = tester.widget<Container>(
        find.byKey(const Key('assignee-U1')),
      );
      final decoration = circle.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border, isNotNull);
    });
  });

  group('writing', () {
    test(
      'assign puts a row and an outbox mutation in one transaction',
      () async {
        final store = AssignmentStore(db);
        final id = await store.assign(
          workspaceId: ws,
          taskId: task,
          userId: 'U1',
        );
        expect(await db.select(db.taskAssignments).get(), hasLength(1));
        final pending = await db.select(db.pendingMutations).get();
        expect(pending, hasLength(1));
        expect(pending.single.entityType, 'ee_task_assignment');
        expect(pending.single.operation, 'create');
        expect(pending.single.entityId, id);
      },
    );

    test('release deletes locally and queues the delete', () async {
      final store = AssignmentStore(db);
      final id = await store.assign(
        workspaceId: ws,
        taskId: task,
        userId: 'U1',
      );
      await store.release(id);
      // A tombstone locally, exactly as the server records it — not a flag
      // this replica would then have to reconcile on the next pull.
      expect(await db.select(db.taskAssignments).get(), isEmpty);
      final ops = (await db.select(db.pendingMutations).get())
          .map((m) => m.operation)
          .toList();
      expect(ops, ['create', 'delete']);
    });

    test('releasing something that is not there does nothing', () async {
      final store = AssignmentStore(db);
      await store.release('NOPE');
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    });
  });
}
