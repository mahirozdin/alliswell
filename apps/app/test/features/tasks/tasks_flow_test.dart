import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';

Future<Widget> signedInAppWith(FakeApi api) async {
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

String todayAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour).toUtc().toIso8601String();
}

void main() {
  testWidgets('Today lists only tasks due today; Inbox only inbox ones', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedTask(title: 'Bugün bitir', dueAt: todayAt(17))
      ..seedTask(title: 'Gelecek hafta', dueAt: '2026-09-01T09:00:00.000Z')
      ..seedTask(title: 'Toplanmamış fikir', status: 'inbox');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle(); // splash → Today (initial section)

    expect(find.text('Bugün bitir'), findsOneWidget);
    expect(find.text('Gelecek hafta'), findsNothing);
    expect(find.text('Toplanmamış fikir'), findsNothing);

    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    expect(find.text('Toplanmamış fikir'), findsOneWidget);
    expect(find.text('Bugün bitir'), findsNothing);

    await tester.tap(find.text('Upcoming').last);
    await tester.pumpAndSettle();
    expect(find.text('Gelecek hafta'), findsOneWidget);
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
    expect(api.tasks.single['title'], 'Yeni fikir');
  });

  testWidgets('checkbox completes the task and it leaves the Today list', (
    tester,
  ) async {
    final api = FakeApi()..seedTask(title: 'Bitirilecek', dueAt: todayAt(15));
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(api.tasks.single['status'], 'completed');
    // Today filters to open statuses — the completed task drops off.
    expect(find.text('Bitirilecek'), findsNothing);
    expect(
      api.requests.any((r) => r.contains('/complete')),
      isTrue,
      reason: 'completion should go through POST /tasks/:id/complete',
    );
  });

  testWidgets('task detail edits urgent, tags and checklist via the API', (
    tester,
  ) async {
    final api = FakeApi();
    final tag = api.seedTag(name: 'Focus');
    api.seedTask(
      title: 'Detaylı görev',
      dueAt: todayAt(16),
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

    // Urgent toggle → PATCH isUrgent.
    await tester.tap(find.byKey(const Key('urgent-switch')));
    await tester.pumpAndSettle();
    expect(api.tasks.single['isUrgent'], isTrue);

    // Tag chip → PUT /tasks/:id/tags.
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    expect(api.tasks.single['tagIds'], [tag['id']]);

    // Checklist: toggle the seeded item, then add a new one.
    await tester.tap(find.text('Hazırlık'));
    await tester.pumpAndSettle();
    final checklist = (api.tasks.single['checklist'] as List)
        .cast<Map<String, dynamic>>();
    expect(checklist.first['isDone'], isTrue);

    await tester.enterText(find.byKey(const Key('checklist-add')), 'Yeni adım');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Yeni adım'), findsOneWidget);
    expect(
      (api.tasks.single['checklist'] as List).length,
      2,
      reason: 'POST /tasks/:id/checklist should have appended',
    );
  });
}
