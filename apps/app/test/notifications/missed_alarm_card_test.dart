import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/missed_alarm_card.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/theme/theme.dart';

/// Round 19 #2 — the other half of bounding the ring window.
///
/// Silencing a three-day-old alarm is only right if the user can still SEE it
/// went unanswered. This card is that, and these tests are what stop it from
/// being quietly dropped in a future refactor.
void main() {
  final now = DateTime.utc(2030, 6, 1, 12);

  AlarmInput alarm({
    String rid = 'R1',
    String title = 'Faturayı öde',
    bool urgent = true,
    required Duration ago,
  }) => AlarmInput(
    reminderId: rid,
    taskId: 'T-$rid',
    taskTitle: title,
    remindAt: now.subtract(ago),
    status: 'scheduled',
    urgent: urgent,
    requiresAcknowledgement: urgent,
  );

  Future<void> pumpCard(WidgetTester tester, List<AlarmInput> alarms) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmFeedProvider.overrideWith((ref) => Stream.value(alarms)),
          alarmClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const Scaffold(body: MissedAlarmCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is drawn when nothing was missed', (tester) async {
    await pumpCard(tester, [alarm(ago: const Duration(minutes: 2))]);
    expect(find.byKey(const Key('missed-alarm-card')), findsNothing);
  });

  testWidgets('a long-gone alarm is named, with how long ago', (tester) async {
    await pumpCard(tester, [alarm(ago: const Duration(hours: 8))]);
    expect(find.byKey(const Key('missed-alarm-card')), findsOneWidget);
    expect(find.text('Faturayı öde'), findsOneWidget);
    expect(find.textContaining('8 h ago'), findsOneWidget);
  });

  testWidgets('several missed alarms are counted, newest named', (
    tester,
  ) async {
    await pumpCard(tester, [
      alarm(rid: 'R1', title: 'Eski', ago: const Duration(hours: 20)),
      alarm(rid: 'R2', title: 'Yeni', ago: const Duration(hours: 5)),
    ]);
    expect(find.text('Yeni'), findsOneWidget);
    expect(find.text('+1 more'), findsOneWidget);
  });

  testWidgets('tapping it opens the ring screen SILENTLY', (tester) async {
    await pumpCard(tester, [alarm(ago: const Duration(hours: 8))]);
    await tester.tap(find.byKey(const Key('missed-alarm-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
    // The label says history, not emergency — and no `AlarmFeedback` was
    // started, which is what the `SilentAlarmFeedback` branch guarantees.
    expect(find.text('MISSED ALARM'), findsOneWidget);
    expect(
      find.text('3 days ago'),
      findsNothing,
      reason: 'shown with the time',
    );
    expect(find.textContaining('8 h ago'), findsOneWidget);
  });
}
