import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/calendar/ui/external_event_tile.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

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

String isoAt(DateTime local) => local.toUtc().toIso8601String();

/// Render Home in its two-pane wide layout (task ListView + side calendar) so
/// tasks stay visible instead of being pushed past the fold by the scrollable
/// calendar. The narrow scrolling layout has its own coverage in
/// home_scroll_test.dart. Call FIRST in a test, before pumpWidget.
Future<void> wideSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('home groups tasks chronologically with overdue and no-date', (
    tester,
  ) async {
    await wideSurface(tester);
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
        title: 'Ay içi iş', // +20d → within the 30-day horizon
        dueAt: isoAt(today.add(const Duration(days: 20, hours: 9))),
      )
      ..seedTask(
        title: 'Çok uzak iş', // +40d → beyond the horizon, dropped from Home
        dueAt: isoAt(today.add(const Duration(days: 40, hours: 9))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Home is the initial section. No date now sits directly under Overdue.
    expect(find.textContaining('Overdue ·'), findsOneWidget);
    expect(find.text('Gecikmiş iş'), findsOneWidget);
    expect(find.textContaining('No date ·'), findsOneWidget);
    expect(find.textContaining('Today ·'), findsOneWidget);

    // Scroll the far group into view; the 30-day horizon keeps '+40d' off Home.
    await tester.dragUntilVisible(
      find.textContaining('Next 30 days ·'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text('Ay içi iş'), findsOneWidget);
    expect(
      find.text('Çok uzak iş'),
      findsNothing,
      reason: 'a +40d task lives on the Calendar tab, not Home',
    );
  });

  testWidgets('completing a task on home removes it after refetch', (
    tester,
  ) async {
    await wideSurface(tester);
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
    // Local-first: the write reaches the server through the sync outbox.
    expect(api.requests.any((r) => r.contains('/sync/push')), isTrue);
  });

  testWidgets('selecting a calendar day dims future groups but never Today', (
    tester,
  ) async {
    await wideSurface(tester);
    // Pick a day in the current month that is not today (grid shows one month).
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final target = DateTime(today.year, today.month, targetDay, 9);
    final api = FakeApi()
      ..seedTask(title: 'Seçilen gün işi', dueAt: isoAt(target))
      ..seedTask(
        title: 'Bugünkü iş',
        dueAt: isoAt(today.add(const Duration(hours: 18))),
      )
      ..seedTask(
        title: 'Yarınki iş',
        dueAt: isoAt(today.add(const Duration(days: 1, hours: 9))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected day ·'), findsOneWidget);
    expect(find.text('Seçilen gün işi'), findsOneWidget);
    // Today is a current debt, not a future plan — it must never look
    // disabled while some other day is selected (feedback round 6).
    await tester.dragUntilVisible(
      find.text('Bugünkü iş'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Bugünkü iş'),
              matching: find.byType(Opacity),
            ),
          )
          .every((o) => o.opacity >= 0.99),
      isTrue,
      reason: "today's work never dims",
    );
    // Future groups are still there, just dimmed — scroll a row into view
    // (the lazy list only materializes visible rows).
    await tester.dragUntilVisible(
      find.text('Yarınki iş'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Yarınki iş'),
              matching: find.byType(Opacity),
            ),
          )
          .any((o) => o.opacity < 0.5),
      isTrue,
      reason: 'future-day tasks render dimmed while a day is selected',
    );

    // Tapping the same day again clears the selection.
    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected day ·'), findsNothing);
  });

  testWidgets('home quick-add chains rapid entries without losing focus', (
    tester,
  ) async {
    await wideSurface(tester);
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
    await wideSurface(tester);
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
    // OPH-161: day-only quick-adds are due by the END of that day (23:59
    // factory default), not at an invented 09:00 morning deadline.
    expect(due.hour, 23);
    expect(due.minute, 59);
    expect(find.textContaining('Selected day ·'), findsOneWidget);
    expect(find.text('Seçili güne iş'), findsOneWidget);
  });

  testWidgets('quick-add honors the default-task-time setting', (tester) async {
    await wideSurface(tester);
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    // Change the preference exactly the way the Settings row does — through
    // the notifier (also persists to localKv).
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('home-quick-add'))),
      listen: false,
    );
    await container.read(defaultTaskTimeProvider.notifier).set('07:15');

    await tester.tap(find.text('$targetDay'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'Sabahçı iş',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final due = DateTime.parse(api.tasks.single['dueAt'] as String).toLocal();
    expect(due.day, targetDay);
    expect(due.hour, 7);
    expect(due.minute, 15);
  });

  testWidgets('FAB sheet creates a task with options', (tester) async {
    await wideSurface(tester);
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

    // Defaults to today when nothing is selected. "items", not "tasks": since
    // OPH-083 the day also counts calendar events (there are none here).
    expect(find.textContaining('· 1 item'), findsOneWidget);
    expect(find.text('Bugünün işi'), findsOneWidget);
  });

  testWidgets('calendar tab shows the day’s meetings beside its tasks', (
    tester,
  ) async {
    // The gap the product lead found by connecting his real Google account:
    // tasks alone cannot answer "what does my day look like".
    final api = FakeApi()
      ..seedTask(
        title: 'Bugünün işi',
        dueAt: isoAt(today.add(const Duration(hours: 16))),
      )
      ..seedExternalEvent(
        summary: 'Ekip toplantısı',
        location: 'Kadıköy',
        startsAt: isoAt(today.add(const Duration(hours: 10))),
        endsAt: isoAt(today.add(const Duration(hours: 11))),
      );

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('· 2 items'), findsOneWidget);
    expect(find.text('Ekip toplantısı'), findsOneWidget);
    expect(find.text('Kadıköy'), findsOneWidget);
    expect(find.text('Bugünün işi'), findsOneWidget);
    // Read-only: a meeting has no checkbox to complete it.
    expect(
      find.descendant(
        of: find.byType(ExternalEventTile),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );
  });

  testWidgets('task tiles show status icons and priority colors', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()
      ..seedTask(
        title: 'Öncelikli iş',
        priority: 'high',
        dueAt: isoAt(today.add(const Duration(hours: 12))),
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Priority flag (colored) + status icon on the tile (open → hourglass).
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
  });

  testWidgets('task title edits in place and autosaves', (tester) async {
    await wideSurface(tester);
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
    expect(api.requests.any((r) => r.contains('/sync/push')), isTrue);
  });

  testWidgets(
    'task detail edits urgent, tags and checklist through the outbox',
    (tester) async {
      await wideSurface(tester);
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

      await tester.enterText(
        find.byKey(const Key('checklist-add')),
        'Yeni adım',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Yeni adım'), findsOneWidget);
      expect((api.tasks.single['checklist'] as List).length, 2);
    },
  );

  testWidgets('task detail assigns a project through the picker (OPH-106)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    final project = api.seedProject(name: 'Hedef Proje');
    api.seedTask(
      title: 'Projesiz görev',
      dueAt: isoAt(today.add(const Duration(hours: 12))),
    );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projesiz görev'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('detail-project')));
    await tester.tap(find.byKey(const Key('detail-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hedef Proje').last);
    await tester.pumpAndSettle();

    expect(api.tasks.single['projectId'], project['id']);
    expect(api.requests.any((r) => r.contains('/sync/push')), isTrue);
  });

  testWidgets(
    'create sheet explains when there are no projects yet (OPH-106)',
    (tester) async {
      await wideSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The picker stays visible (not hidden) with a hint pointing to Projects.
      expect(find.byKey(const Key('task-sheet-project')), findsOneWidget);
      expect(
        find.text('No projects yet — create one in the Projects tab'),
        findsOneWidget,
      );
    },
  );

  testWidgets('an inbox capture stays off Home and has no checkbox (OPH-107)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()
      ..seedTask(title: 'Yakalanan fikir', status: 'inbox')
      ..seedTask(
        title: 'Gerçek iş',
        dueAt: isoAt(today.add(const Duration(hours: 12))),
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Home shows the real task but NOT the capture.
    expect(find.text('Gerçek iş'), findsOneWidget);
    expect(find.text('Yakalanan fikir'), findsNothing);

    // The Inbox shows the capture with triage actions and no completion box.
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    expect(find.text('Yakalanan fikir'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const Key('capture-plan')), findsOneWidget);
  });

  testWidgets('planning a capture with a date moves it to Home (OPH-107)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTask(title: 'Planlanacak', status: 'inbox');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    // Plan opens the sheet in edit mode.
    await tester.tap(find.byKey(const Key('capture-plan')));
    await tester.pumpAndSettle();
    expect(find.text('Plan task'), findsOneWidget);

    // Give it a due date (accept picker defaults) and save.
    await tester.tap(find.byKey(const Key('task-sheet-due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    // It left the Inbox and now shows on Home as a real 'open' task.
    expect(find.text('Planlanacak'), findsNothing);
    expect(api.tasks.single['status'], 'open');
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Planlanacak'), findsOneWidget);
  });

  testWidgets('converting a capture to a note removes it (OPH-107)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi()..seedTask(title: 'Nota gidecek', status: 'inbox');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('capture-to-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();

    // The capture is gone from the Inbox and a note carries its title.
    expect(find.text('Nota gidecek'), findsNothing);
    expect(api.notes.any((n) => n['title'] == 'Nota gidecek'), isTrue);
  });

  testWidgets('a long capture title fits a phone row without overflow (OPH-107)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeApi()
      ..seedTask(
        title:
            'Çok uzun bir yakalama başlığı ki satıra sığmasın ve taşma olmasın',
        status: 'inbox',
      );
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    // A RenderFlex overflow would have thrown during layout; the three actions
    // and the title coexist at 375 px.
    expect(find.byKey(const Key('capture-plan')), findsOneWidget);
    expect(find.byKey(const Key('capture-delete')), findsOneWidget);
  });
}
