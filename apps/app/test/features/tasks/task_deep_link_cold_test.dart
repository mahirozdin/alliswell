import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import '../projects/fake_api.dart';
import 'tasks_flow_test.dart' show signedInAppWith;

/// OPH-392 (E-17) — a cold start straight on a task's address.
///
/// The web opens at the URL it was given (`/#/tasks/<id>` from a notification
/// or a shared link). The session restore parked that on the splash, and the
/// destination was never written down: the first redirect runs while the app
/// builds, where a provider write is refused, so it went to `/not-found` and
/// looped. And a task that is not on the device — deleted, or never this
/// person's — kept the detail on its spinner forever.
void main() {
  void coldStartAt(WidgetTester tester, String location) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }

  testWidgets('a cold start on /tasks/<id> opens that task', (tester) async {
    final api = FakeApi();
    final task = api.seedTask(title: 'Pay the rent');
    coldStartAt(tester, '/tasks/${task['id']}');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Pay the rent'), findsWidgets);
  });

  testWidgets('a cold start on a task the server does not have ends in an '
      'answer with a way home, not an endless spinner', (tester) async {
    final api = FakeApi()..seedTask(title: 'Something else');
    coldStartAt(tester, '/tasks/TSK0000000000000000000GONE');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('task-detail-gone')), findsOneWidget);
    expect(find.text('error.notFound'.tr()), findsOneWidget);

    await tester.tap(find.text('error.goHome'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsNothing);
  });

  testWidgets('a mistyped task link the API rejects as a bad id (400) says '
      'not found too, not an endless spinner', (tester) async {
    final api = FakeApi()..seedTask(title: 'Something else');
    coldStartAt(tester, '/tasks/typo');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('task-detail-gone')), findsOneWidget);
    expect(find.text('error.notFound'.tr()), findsOneWidget);
    expect(find.text('error.goHome'.tr()), findsOneWidget);
  });
}
