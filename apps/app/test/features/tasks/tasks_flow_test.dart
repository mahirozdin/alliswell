import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

Future<Widget> signedInAppWith(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

String isoAt(DateTime local) => local.toUtc().toIso8601String();

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('home groups tasks chronologically with overdue and no-date', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Gecikmiş iş',
        dueAt: isoAt(today.subtract(const Duration(days: 2, hours: -9))),
      )
      ..seedTask(
        title: 'Bugünkü iş',
        dueAt: isoAt(today.add(const Duration(hours: 17))),
      )
      ..seedTask(title: 'Tarihsiz iş')
      ..seedTask(
        title: 'Uzak iş',
        dueAt: isoAt(today.add(const Duration(days: 40, hours: 9))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Home is the initial section now.
    expect(find.textContaining('Overdue ·'), findsOneWidget);
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(find.text('Gecikmiş iş'), findsOneWidget);

    // Lower groups live below the fold of the lazy list — scroll each group
    // HEADER into view (rows alone can leave the header offstage above).
    await tester.dragUntilVisible(
      find.textContaining('Later ·'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.textContaining('Later ·'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('No date ·'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.textContaining('No date ·'), findsOneWidget);
  });

  testWidgets('completing a task on home removes it after refetch', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Bitecek iş',
        dueAt: isoAt(today.add(const Duration(hours: 15))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(api.tasks.single['status'], 'completed');
    expect(find.text('Bitecek iş'), findsNothing);
    expect(api.requests.any((r) => r.contains('/complete')), isTrue);
  });

  testWidgets('selecting a calendar day highlights it and dims the rest', (
    tester,
  ) async {
    // Pick a day in the current month that is not today (grid shows one month).
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final target = DateTime(today.year, today.month, targetDay, 9);
    final api = FakeApi()
      ..seedTask(title: 'Seçilen gün işi', dueAt: isoAt(target))
      ..seedTask(
        title: 'Bugünkü iş',
        dueAt: isoAt(today.add(const Duration(hours: 18))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected day ·'), findsOneWidget);
    expect(find.text('Seçilen gün işi'), findsOneWidget);
    // The other group is still there, just dimmed — scroll its row into view
    // (the lazy list only materializes visible rows).
    await tester.dragUntilVisible(
      find.text('Bugünkü iş'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .any((o) => o.opacity < 0.5),
      isTrue,
      reason: 'non-selected tasks render dimmed',
    );

    // Tapping the same day again clears the selection.
    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected day ·'), findsNothing);
  });

  testWidgets('home quick-add chains rapid entries without losing focus', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // type → Enter → type → Enter: no re-tap between entries.
    await tester.enterText(find.byKey(const Key('home-quick-add')), 'Birinci');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('home-quick-add')), 'İkinci');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(api.tasks, hasLength(2));
    expect(find.text('Birinci'), findsOneWidget);
    expect(find.text('İkinci'), findsOneWidget);
    // Dateless quick adds land in the No date group, visible immediately.
    expect(find.textContaining('No date ·'), findsOneWidget);
    expect(api.tasks.every((t) => t['dueAt'] == null), isTrue);
  });

  testWidgets('home quick-add targets the selected calendar day', (
    tester,
  ) async {
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'Seçili güne iş',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final due = DateTime.parse(api.tasks.single['dueAt'] as String).toLocal();
    expect(due.day, targetDay);
    expect(find.textContaining('Selected day ·'), findsOneWidget);
    expect(find.text('Seçili güne iş'), findsOneWidget);
  });

  testWidgets('FAB sheet creates a task with options', (tester) async {
    final api = FakeApi();
    api.seedProject(name: 'Hedef Proje');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Opsiyonlu görev',
    );
    // Pick a due date via the date + time dialogs (defaults accepted).
    await tester.tap(find.byKey(const Key('task-sheet-due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-sheet-urgent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    expect(api.tasks, hasLength(1));
    final created = api.tasks.single;
    expect(created['title'], 'Opsiyonlu görev');
    expect(created['isUrgent'], isTrue);
    expect(created['dueAt'], isNotNull);
    expect(find.text('Opsiyonlu görev'), findsOneWidget);
  });

  testWidgets('quick-add on Inbox posts with status inbox and refreshes', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quick-add')), 'Yeni fikir');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Yeni fikir'), findsOneWidget);
    expect(api.tasks.single['status'], 'inbox');
  });

  testWidgets('calendar tab lists the selected day', (tester) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Bugünün işi',
        dueAt: isoAt(today.add(const Duration(hours: 16))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();

    // Defaults to today when nothing is selected.
    expect(find.textContaining('· 1 task'), findsOneWidget);
    expect(find.text('Bugünün işi'), findsOneWidget);
  });

  testWidgets('task tiles show status icons and priority colors', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Öncelikli iş',
        priority: 'high',
        dueAt: isoAt(today.add(const Duration(hours: 12))),
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Priority flag (colored) + status icon on the tile.
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('task title edits in place and autosaves', (tester) async {
    final api = FakeApi()
      ..seedTask(
        title: 'Eski görev adı',
        dueAt: isoAt(today.add(const Duration(hours: 12))),
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eski görev adı'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('task-title')),
      'Yeni görev adı',
    );
    await tester.pump(const Duration(seconds: 2)); // debounce fires
    await tester.pumpAndSettle();

    expect(api.tasks.single['title'], 'Yeni görev adı');
    expect(
      api.requests.any((r) => r.startsWith('PATCH /api/v1/tasks/')),
      isTrue,
    );
  });

  testWidgets('task detail edits urgent, tags and checklist via the API', (
    tester,
  ) async {
    final api = FakeApi();
    final tag = api.seedTag(name: 'Focus');
    api.seedTask(
      title: 'Detaylı görev',
      dueAt: isoAt(today.add(const Duration(hours: 16))),
      checklist: [
        {
          'id': 'CHKSEED'.padRight(26, '0'),
          'taskId': 'x',
          'title': 'Hazırlık',
          'isDone': false,
          'sortOrder': 0,
          'revision': 1,
        },
      ],
    );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Detaylı görev'));
    await tester.pumpAndSettle();

    // The detail page scrolls; bring each control into view before tapping
    // (sections live in cards below the fold on small windows).
    final detailList = find.descendant(
      of: find.byType(TaskDetailScreen),
      matching: find.byType(ListView),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('urgent-switch')),
      detailList,
      const Offset(0, -120),
    );
    await tester.tap(find.byKey(const Key('urgent-switch')));
    await tester.pumpAndSettle();
    expect(api.tasks.single['isUrgent'], isTrue);

    await tester.dragUntilVisible(
      find.text('Focus'),
      detailList,
      const Offset(0, -120),
    );
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    expect(api.tasks.single['tagIds'], [tag['id']]);

    await tester.dragUntilVisible(
      find.text('Hazırlık'),
      detailList,
      const Offset(0, -120),
    );
    await tester.tap(find.text('Hazırlık'));
    await tester.pumpAndSettle();
    final checklist = (api.tasks.single['checklist'] as List)
        .cast<Map<String, dynamic>>();
    expect(checklist.first['isDone'], isTrue);

    await tester.enterText(find.byKey(const Key('checklist-add')), 'Yeni adım');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Yeni adım'), findsOneWidget);
    expect((api.tasks.single['checklist'] as List).length, 2);
  });
}
