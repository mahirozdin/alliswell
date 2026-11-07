import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarm_log_screen.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-395 (E-29) — the alarm log reads as a person's record first and a bug
/// report second.
///
/// It used to show every row as the raw diagnostic line: an ISO UTC instant,
/// `slot 2`, `level=webPush`, a ULID. That line is still what "Copy the log"
/// puts on the clipboard and what a developer needs, so it lives behind a
/// per-row "Details" toggle instead of on the face of the row.
final _ulid = '01JABCDEFGHJKMNPQRSTVWXYZ0';

AlarmEvent _event({
  int id = 1,
  String event = AlarmLogEvent.scheduled,
  String lane = AlarmLogLane.notification,
  bool urgent = true,
}) => AlarmEvent(
  id: id,
  at: DateTime.utc(2026, 11, 7, 9, 30),
  event: event,
  lane: lane,
  kind: 'remind',
  slotIndex: 2,
  urgent: urgent,
  sound: 'aw_alarm',
  level: 'webPush',
  fireAt: DateTime.utc(2026, 11, 7, 10),
  reminderId: _ulid,
);

Future<void> _pump(WidgetTester tester, List<AlarmEvent> rows) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alarmLogRowsProvider.overrideWith((ref) => Stream.value(rows)),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const AlarmLogScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a row shows words, not the raw diagnostic line', (tester) async {
    await _pump(tester, [_event()]);

    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.textContaining('Notification'), findsWidgets);
    expect(find.textContaining('Urgent'), findsOneWidget);
    // None of the developer fields are on the face of the row.
    expect(find.textContaining('level=webPush'), findsNothing);
    expect(find.textContaining('slot 2'), findsNothing);
    expect(find.textContaining(_ulid), findsNothing);
    expect(find.textContaining('2026-11-07T'), findsNothing);
  });

  testWidgets('"Details" opens the raw line and closes it again', (
    tester,
  ) async {
    await _pump(tester, [_event()]);
    final raw = formatAlarmLogLine(_event());

    expect(find.byKey(const Key('alarm-log-details-1')), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    await tester.tap(find.byKey(const Key('alarm-log-details-1')));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);

    await tester.tap(find.byKey(const Key('alarm-log-details-1')));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsNothing);
  });

  testWidgets('the Details toggle is a full-size tap target', (tester) async {
    await _pump(tester, [_event()]);
    final size = tester.getSize(find.byKey(const Key('alarm-log-details-1')));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('every event and lane has a name — no raw identifiers', (
    tester,
  ) async {
    const events = [
      AlarmLogEvent.delivered,
      AlarmLogEvent.dropped,
      AlarmLogEvent.test,
    ];
    await _pump(tester, [
      for (var i = 0; i < events.length; i++)
        _event(
          id: i + 1,
          event: events[i],
          lane: AlarmLogLane.alarmkit,
          urgent: false,
        ),
    ]);
    for (final raw in [...events, AlarmLogLane.alarmkit]) {
      expect(find.text(raw), findsNothing, reason: raw);
      expect(find.textContaining(' · $raw'), findsNothing, reason: raw);
    }
    expect(find.text('Shown by the system'), findsOneWidget);
    expect(find.text('Dropped by the system'), findsOneWidget);
    expect(find.text('Test alarm'), findsOneWidget);
  });
}
