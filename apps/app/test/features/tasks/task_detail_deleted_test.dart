import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../projects/fake_api.dart';
import '../shell/shell_harness.dart';
import 'tasks_flow_test.dart' show signedInAppWith;

/// OPH-419 — the open task's row leaves the replica (a pull applied its
/// tombstone: deleted on another device, or no longer this person's). The
/// detail used to keep showing the last task it had: stale, still editable,
/// and every control a write for an entity that no longer exists.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  void coldStartAt(WidgetTester tester, String location) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }

  /// What the sync applier's task tombstone does to the replica.
  Future<void> dropTaskRow(WidgetTester tester, String taskId) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskDetailScreen)),
    );
    final db = container.read(databaseProvider);
    await (db.delete(db.tasks)..where((t) => t.id.equals(taskId))).go();
    await tester.pumpAndSettle();
  }

  testWidgets('the open task deleted elsewhere: the detail says so and '
      'offers a way out instead of the stale, editable task', (tester) async {
    final api = FakeApi();
    final task = api.seedTask(title: 'Pay the rent');
    final id = task['id'] as String;
    coldStartAt(tester, '/tasks/$id');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);

    await dropTaskRow(tester, id);

    expect(find.byKey(const Key('task-detail-deleted')), findsOneWidget);
    expect(find.text('task.goneWhileOpen'.tr()), findsOneWidget);
    expect(find.text('Pay the rent'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // A cold start has nothing to go back to: the way out is Home.
    await tester.tap(find.text('error.goHome'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsNothing);
  });

  testWidgets('the row coming back (moved between workspaces) shows the task '
      'again', (tester) async {
    final api = FakeApi();
    final task = api.seedTask(title: 'Pay the rent');
    final id = task['id'] as String;
    coldStartAt(tester, '/tasks/$id');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskDetailScreen)),
    );
    final db = container.read(databaseProvider);
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();

    await dropTaskRow(tester, id);
    expect(find.byKey(const Key('task-detail-deleted')), findsOneWidget);

    await db.into(db.tasks).insert(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-detail-deleted')), findsNothing);
    expect(find.text('Pay the rent'), findsWidgets);
  });

  testWidgets('first load: the row not pulled yet is a wait, not a deletion', (
    tester,
  ) async {
    final api = FakeApi();
    final task = api.seedTask(title: 'Pay the rent');
    coldStartAt(tester, '/tasks/${task['id']}');
    await tester.pumpWidget(await signedInAppWith(api));
    // Frame by frame through the start: the replica is empty until the
    // first pull lands, and the detail must never call that a deletion.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const Key('task-detail-deleted')), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-detail-deleted')), findsNothing);
    expect(find.text('Pay the rent'), findsWidgets);
  });

  testWidgets('the task open in the desktop pane deleted elsewhere: the pane '
      'says so, and its action closes the pane', (tester) async {
    sizeTo(tester, const Size(1440, 900));
    final api = FakeApi();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final task = api.seedTask(
      title: 'Alpha',
      dueAt: DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        9,
      ).toUtc().toIso8601String(),
    );
    await tester.pumpWidget(
      await teamApp(api, serverUrl: 'https://api.example.com'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('shell-content')),
            matching: find.text('Alpha'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final pane = find.byKey(const Key('list-detail-pane'));
    expect(pane, findsOneWidget);

    await dropTaskRow(tester, task['id'] as String);

    expect(
      find.descendant(
        of: pane,
        matching: find.byKey(const Key('task-detail-deleted')),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: pane, matching: find.text('common.close'.tr())),
    );
    await tester.pumpAndSettle();
    expect(pane, findsNothing);
  });
}
