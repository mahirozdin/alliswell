import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

Future<Widget> signedInAppWith(
  FakeApi api, {
  List<Override> extra = const [],
}) async {
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
      ...extra,
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

/// The grid shows adjacent months, so a day NUMBER matches more than one cell
/// whenever the window reaches the same date next month — which depends on
/// today's date, and is why these taps were ambiguous on 2026-09-02 and not
/// before. The full date is unique.
Finder _calendarDay(DateTime day) =>
    find.byKey(Key('calendar-day-${day.year}-${day.month}-${day.day}'));

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

    await tester.tap(_calendarDay(target));
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
    await tester.tap(_calendarDay(target));
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

    // type → Enter → type → Enter: no re-tap between entries. Round 14 puts a
    // deadline picker on every Enter; Cancel is the "skip" path and must keep
    // the rapid-entry chain (and its focus) intact.
    Future<void> submitThenSkipDate(String title) async {
      await tester.enterText(find.byKey(const Key('home-quick-add')), title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // No pumpAndSettle while the deadline dialog is up: the bar's own
      // in-flight spinner animates until onAdd returns, so settle would spin
      // forever. Bounded pumps open the dialog; Cancel is the skip path.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    await submitThenSkipDate('Birinci');
    await submitThenSkipDate('İkinci');

    expect(api.tasks, hasLength(2));
    expect(find.text('Birinci'), findsOneWidget);
    expect(find.text('İkinci'), findsOneWidget);
    // Dateless quick adds land in the No date group, visible immediately.
    expect(find.textContaining('No date ·'), findsOneWidget);
    expect(api.tasks.every((t) => t['dueAt'] == null), isTrue);
    // Skipping the date skips the derived reminder too — but the round-14
    // creation defaults (medium priority, urgent alarm on) always apply.
    expect(api.tasks.every((t) => t['remindAt'] == null), isTrue);
    expect(api.tasks.every((t) => t['priority'] == 'medium'), isTrue);
    expect(api.tasks.every((t) => t['isUrgent'] == true), isTrue);
  });

  testWidgets('home quick-add targets the selected calendar day', (
    tester,
  ) async {
    await wideSurface(tester);
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final target = DateTime(today.year, today.month, targetDay);
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(_calendarDay(target));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'Seçili güne iş',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Round 14: the deadline dialog opens prefilled with the selected day —
    // accepting both steps keeps the bar's "for that day" promise. Bounded
    // pumps: the bar's spinner animates until onAdd returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final due = DateTime.parse(api.tasks.single['dueAt'] as String).toLocal();
    expect(due.day, targetDay);
    // OPH-161: day-only quick-adds are due by the END of that day (23:59
    // factory default), not at an invented 09:00 morning deadline.
    expect(due.hour, 23);
    expect(due.minute, 59);
    // Round 14: a picked deadline auto-arms the reminder an hour earlier.
    final remind = DateTime.parse(
      api.tasks.single['remindAt'] as String,
    ).toLocal();
    expect(due.difference(remind), const Duration(hours: 1));
    expect(find.textContaining('Selected day ·'), findsOneWidget);
    expect(find.text('Seçili güne iş'), findsOneWidget);
  });

  testWidgets('quick-add honors the default-task-time setting', (tester) async {
    await wideSurface(tester);
    final targetDay = today.day <= 20 ? today.day + 5 : today.day - 5;
    final target = DateTime(today.year, today.month, targetDay);
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

    await tester.tap(_calendarDay(target));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('home-quick-add')),
      'Sabahçı iş',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Round 14: accept the deadline dialog — its clock opens on the user's
    // default task time, so OK+OK must land on 07:15, not a hardcoded hour.
    // Bounded pumps: the bar's spinner animates until onAdd returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
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
    // OPH-164: the sheet carries the task's own description field.
    await tester.enterText(
      find.byKey(const Key('task-sheet-description')),
      'bağlam: https://x.dev/spec',
    );
    // Pick a due date via the date + time dialogs (defaults accepted).
    await tester.tap(find.byKey(const Key('task-sheet-due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Round 14: urgent is ON and priority is medium out of the box — no taps.
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    expect(api.tasks, hasLength(1));
    final created = api.tasks.single;
    expect(created['title'], 'Opsiyonlu görev');
    expect(created['description'], 'bağlam: https://x.dev/spec');
    expect(created['isUrgent'], isTrue);
    expect(created['priority'], 'medium');
    expect(created['dueAt'], isNotNull);
    // Round 14: picking the deadline auto-armed a reminder an hour before it,
    // visibly in the sheet, without the user touching the reminder row.
    final due = DateTime.parse(created['dueAt'] as String);
    final remind = DateTime.parse(created['remindAt'] as String);
    expect(due.difference(remind), const Duration(hours: 1));
    expect(find.text('Opsiyonlu görev'), findsOneWidget);
  });

  testWidgets('task description edits in place and autosaves (OPH-164)', (
    tester,
  ) async {
    await wideSurface(tester);
    final soon = isoAt(today.add(const Duration(days: 2, hours: 12)));
    final api = FakeApi()
      ..seedTask(title: 'Açıklamalı iş', description: 'eski metin', dueAt: soon)
      ..seedTask(title: 'Açıklamasız iş', dueAt: soon);
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    // Existing description renders in display mode; tapping starts the edit.
    await tester.tap(find.text('Açıklamalı iş'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-description-display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-description')),
      'yeni metin https://x.dev',
    );
    await tester.pump(const Duration(milliseconds: 1600)); // autosave debounce
    await tester.pumpAndSettle();
    expect(
      api.tasks.firstWhere((t) => t['title'] == 'Açıklamalı iş')['description'],
      'yeni metin https://x.dev',
    );

    // A task without one offers "Add description" instead of a blank row.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Açıklamasız iş'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-add-description')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-add-description')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-description')),
      'ilk açıklama',
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(
      api.tasks.firstWhere(
        (t) => t['title'] == 'Açıklamasız iş',
      )['description'],
      'ilk açıklama',
    );
  });

  testWidgets('the project picker creates a project inline (OPH-163)', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Yeni projeli iş',
    );

    // Open the picker; its last entry creates a project without leaving the
    // task flow (round 8 #2).
    await tester.tap(find.byKey(const Key('task-sheet-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add project').last);
    await tester.pumpAndSettle();

    // The project sheet stacked on top: name it and create.
    await tester.enterText(find.byType(TextFormField).last, 'Anında Proje');
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();

    // Back in the task sheet with the NEW project selected in the field.
    expect(find.text('Anında Proje'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    final pushedProject = api.projects.single;
    expect(pushedProject['name'], 'Anında Proje');
    expect(api.tasks.single['projectId'], pushedProject['id']);
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

  testWidgets('home shows the day’s meetings beside its tasks (read-only)', (
    tester,
  ) async {
    // The gap the product lead found by connecting his real Google account:
    // tasks alone cannot answer "what does my day look like". Since OPH-162
    // removed the Calendar tab, Home IS the calendar surface — the meeting
    // must ride the same chronological list as the task.
    await wideSurface(tester);
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

      // OPH-165: tags assign through the chip-input now — typing an existing
      // name fold-matches it instead of creating a duplicate.
      await tester.dragUntilVisible(
        find.byKey(const Key('tag-input')),
        detailList,
        const Offset(0, -120),
      );
      await tester.enterText(find.byKey(const Key('tag-input')), 'focus');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.tasks.single['tagIds'], [tag['id']]);
      expect(api.tags, hasLength(1)); // matched, not duplicated

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
    'with no projects the picker stays, WITHOUT a hint line (round 9 #3)',
    (tester) async {
      await wideSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The picker is still there (OPH-106) and still carries "+ Add project"
      // (OPH-163) — but the old helper line is gone: it added height to ONE
      // field and knocked the project/priority pair out of line.
      expect(find.byKey(const Key('task-sheet-project')), findsOneWidget);
      expect(
        find.text('No projects yet — create one in the Projects tab'),
        findsNothing,
      );

      // Round 9 #3: the two fields read as one row — same height, same top.
      final project = tester.getRect(
        find.byKey(const Key('task-sheet-project')),
      );
      final priority = tester.getRect(
        find.byKey(const Key('task-sheet-priority')),
      );
      expect(project.top, priority.top);
      expect(project.height, priority.height);
    },
  );

  // ── OPH-173: an empty date field opens on TOMORROW (round 9 #4) ────────────

  testWidgets('the due picker opens on tomorrow, not today', (tester) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Yarına iş',
    );
    // Accept both pickers untouched: whatever they OPENED on is what lands.
    await tester.tap(find.byKey(const Key('task-sheet-due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final due = DateTime.parse(api.tasks.single['dueAt'] as String).toLocal();
    expect(
      DateTime(due.year, due.month, due.day),
      tomorrow,
      reason: 'you tap for today; you plan for tomorrow',
    );
    // …at the user's default task time (23:59 factory, OPH-161).
    expect(due.hour, 23);
    expect(due.minute, 59);
  });

  testWidgets('the reminder picker opens on the DUE day, not tomorrow', (
    tester,
  ) async {
    await wideSurface(tester);
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-sheet-title')),
      'Hatırlatıcılı iş',
    );

    // The day cells are plain numbers, so the tap must be unambiguous in BOTH
    // directions, and this assertion has now been caught out twice by the
    // calendar:
    //
    //  1. The picker opens on the sheet's default due date, which is TOMORROW
    //     (OPH-173) — so on the last day of a month it is already showing the
    //     NEXT month. Anchoring the target on `now` picked a day the grid was
    //     not displaying, and the test failed every 31st.
    //  2. A month grid also renders the neighbouring months' edge days (~1–9
    //     trailing, ~25–31 leading), so those numbers can appear twice and
    //     `.last` silently picks the wrong one.
    //
    // Mid-month is the only range that is unambiguous in every grid, so the
    // target is pinned there rather than computed as an offset from today.
    final opensOn = DateTime.now().add(const Duration(days: 1));
    final target = DateTime(
      opensOn.year,
      opensOn.month,
      opensOn.day == 15 ? 16 : 15,
    );
    await tester.tap(find.byKey(const Key('task-sheet-due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${target.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // …and the reminder picker, accepted untouched, lands on THAT day.
    await tester.tap(find.byKey(const Key('task-sheet-remind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();

    final remind = DateTime.parse(
      api.tasks.single['remindAt'] as String,
    ).toLocal();
    expect(
      DateTime(remind.year, remind.month, remind.day),
      target,
      reason: 'a nudge belongs next to its deadline, not next to today',
    );
  });

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
