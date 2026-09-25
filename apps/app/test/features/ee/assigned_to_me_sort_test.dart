import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ui/assigned_to_me_screen.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-241 — "Assigned to me" is in the order you chose, and it is the SAME
/// choice as Home's and the project Tasks tab's (OPH-338, DESIGN §34 L6).
///
/// Three tasks with three different answers — by date, by priority, by title —
/// so a list that ignored the choice, or kept its query's order, cannot pass
/// by accident. The fourth task is somebody else's and must never show.
Task _task(String id, String title, {required String priority, DateTime? due}) =>
    Task(
      id: id,
      workspaceId: 'W1',
      title: title,
      status: 'open',
      priority: priority,
      timezone: 'Europe/Istanbul',
      isUrgent: false,
      requiresAcknowledgement: false,
      sortOrder: 0,
      revision: 1,
      dueAt: due,
    );

void main() {
  // The choice lives in `localKv`, which keeps ONE SharedPreferences instance
  // for the whole process — `setMockInitialValues` does not reach it once a
  // test has written through it. So each test starts from the key removed,
  // through the same door the preference itself uses.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove('alliswell_tasks_sort');
  });

  testWidgets('EE-241: "assigned to me" is in the order you chose — and '
      'choosing here chooses for Home too', (tester) async {
    final now = DateTime.now();
    // In the workspace query's own order, which nobody chose: Beta first.
    final tasks = [
      _task('B', 'Beta', priority: 'urgent'),
      _task('X', 'Başkasının işi', priority: 'urgent'),
      _task('A', 'Alfa', priority: 'low', due: now.add(const Duration(days: 3))),
      _task('Z', 'Zeta', priority: 'high', due: now.add(const Duration(days: 1))),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          myAssignedTaskIdsProvider.overrideWith(
            (ref) => Stream.value({'A', 'B', 'Z'}),
          ),
          workspaceAssigneesProvider.overrideWith(
            (ref) => Stream.value(const <String, List<Assignee>>{}),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeAssignedToMeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    List<String> onScreen() {
      final rows = [
        for (final title in ['Alfa', 'Beta', 'Zeta'])
          (title, tester.getTopLeft(find.text(title)).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final (title, _) in rows) title];
    }

    Future<void> choose(String labelKey) async {
      await tester.tap(find.byKey(const Key('assigned-to-me-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(labelKey.tr()).last);
      await tester.pumpAndSettle();
    }

    // Somebody else's work is not on this list, whatever the order.
    expect(find.text('Başkasının işi'), findsNothing);

    // Home's default: the nearest deadline first, the dateless last — not
    // the query's order (Beta, Alfa, Zeta).
    expect(onScreen(), ['Zeta', 'Alfa', 'Beta']);

    await choose('sort.taskPriority');
    expect(onScreen(), ['Beta', 'Zeta', 'Alfa'], reason: 'urgent, high, low');

    await choose('sort.title');
    expect(onScreen(), ['Alfa', 'Beta', 'Zeta']);

    // One preference for every task list: Home opens in this order now too.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EeAssignedToMeScreen)),
    );
    expect(container.read(tasksSortProvider), startsWith('title'));
  });

  testWidgets('EE-241: a choice made on Home is the order here', (
    tester,
  ) async {
    // The preference as Home stores it — through the same door.
    await localKv.set('alliswell_tasks_sort', 'priority:desc');
    final tasks = [
      _task('A', 'Alfa', priority: 'low'),
      _task('B', 'Beta', priority: 'urgent'),
      _task('Z', 'Zeta', priority: 'high'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          myAssignedTaskIdsProvider.overrideWith(
            (ref) => Stream.value({'A', 'B', 'Z'}),
          ),
          workspaceAssigneesProvider.overrideWith(
            (ref) => Stream.value(const <String, List<Assignee>>{}),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeAssignedToMeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ys = [
      for (final title in ['Beta', 'Zeta', 'Alfa'])
        tester.getTopLeft(find.text(title)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'urgent, high, low');
  });
}
