// H-5 (OPH-400): the task detail's "Urgent alarm" row was the only switch row
// without a leading icon, so its title started ~38 pt left of every other
// row's title and broke the icon column. Its subtitle also repeated the title
// ("Acil alarm / Onaylanması gereken acil alarm"). This test pins the row to
// the same icon column and title line as the mute and repeat rows, at 1.0x and
// 2.0x text, and checks the subtitle says what the switch does instead.
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';

import '../projects/fake_api.dart';
import 'tasks_flow_test.dart' show signedInAppWith, wideSurface, isoAt;

Finder _titleOf(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

Finder _iconOf(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon));

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('urgent alarm row shares the icon column and title line '
        '(text ${scale}x)', (tester) async {
      await wideSurface(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final now = DateTime.now();
      final api = FakeApi()
        ..seedTask(
          title: 'Hizalı görev',
          dueAt: isoAt(
            DateTime(
              now.year,
              now.month,
              now.day,
            ).add(const Duration(days: 1, hours: 10)),
          ),
        );

      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hizalı görev'));
      await tester.pumpAndSettle();

      final detailList = find.descendant(
        of: find.byType(TaskDetailScreen),
        matching: find.byType(ListView),
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('urgent-switch')),
        detailList,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      // A leading icon, in the same column as the mute row's icon.
      expect(_iconOf('urgent-switch'), findsOneWidget);
      final urgentIcon = tester.getRect(_iconOf('urgent-switch'));
      final muteIcon = tester.getRect(_iconOf('mute-alarms-switch'));
      expect(urgentIcon.left, moreOrLessEquals(muteIcon.left, epsilon: 0.5));
      expect(urgentIcon.width, moreOrLessEquals(muteIcon.width, epsilon: 0.5));
      expect(
        urgentIcon.center.dy,
        lessThan(tester.getRect(find.byKey(const Key('urgent-switch'))).bottom),
      );

      // The title starts on the same x as the other switch rows' titles.
      final urgentTitle = tester.getTopLeft(
        _titleOf('urgent-switch', 'task.urgentAlarm'.tr()),
      );
      final muteTitle = tester.getTopLeft(
        _titleOf('mute-alarms-switch', 'task.muteAlarms'.tr()),
      );
      final repeatTitle = tester.getTopLeft(
        find
            .descendant(
              of: find.byKey(const Key('repeat-switch')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(urgentTitle.dx, moreOrLessEquals(muteTitle.dx, epsilon: 0.5));
      expect(urgentTitle.dx, moreOrLessEquals(repeatTitle.dx, epsilon: 0.5));

      // The subtitle says what the switch does, not the title again.
      final subtitle = find.descendant(
        of: find.byKey(const Key('urgent-switch')),
        matching: find.text('task.urgentAlarmSub'.tr()),
      );
      expect(subtitle, findsOneWidget);
      // Whatever the locale, the subtitle does not restate the title.
      expect(
        'task.urgentAlarmSub'.tr().toLowerCase(),
        isNot(contains('task.urgentAlarm'.tr().toLowerCase())),
      );
    });
  }
}
