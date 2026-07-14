import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

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

    // Lower groups live below the fold of the lazy list — scroll to the last
    // tile; its header and the one above scroll into view with it.
    await tester.dragUntilVisible(
      find.text('Tarihsiz iş'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.textContaining('No date ·'), findsOneWidget);
    expect(find.textContaining('Later ·'), findsOneWidget);
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
    // The other group is still there, just dimmed.
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

    await tester.tap(find.byKey(const Key('urgent-switch')));
    await tester.pumpAndSettle();
    expect(api.tasks.single['isUrgent'], isTrue);

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    expect(api.tasks.single['tagIds'], [tag['id']]);

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
