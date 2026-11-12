import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_snooze_sheet.dart';
import 'package:alliswell/src/notifications/planner.dart';

String id(String p) => p.padRight(26, '0');

/// A ring-screen row's snooze sheet for a screen reader (#47, S3 / Z-04):
/// every option is ONE button whose label says what it does — a preset with
/// the minute it lands on, as the single layout's tiles do.
void main() {
  // Local 09:00: "5 min" lands on 09:05, "tomorrow morning" on 09:00 next day.
  final now = DateTime(2030, 6, 1, 9);

  AlarmInput alarm(String n, {DateTime? snoozedUntil}) => AlarmInput(
    reminderId: id('R$n'),
    taskId: id('T$n'),
    taskTitle: 'Task $n',
    remindAt: now,
    snoozedUntil: snoozedUntil,
    status: snoozedUntil == null ? 'scheduled' : 'snoozed',
    urgent: true,
    requiresAcknowledgement: true,
  );

  Future<List<AlarmSheetChoice>> pumpSheet(
    WidgetTester tester, {
    List<AlarmInput> alarms = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chosen = <AlarmSheetChoice>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAlarmSnoozeSheet(
                context,
                alarm: alarm('1'),
                presets: const [
                  '5_min',
                  '30_min',
                  '1_hour',
                  'tomorrow_morning',
                ],
                now: () => now,
                dateFormat: kAwSystemDateFormat,
                alarms: alarms,
                onChoose: chosen.add,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  /// [label] with the narrow no-break space an en time puts before AM/PM
  /// read as a plain space.
  String plain(String label) => label.replaceAll(' ', ' ');

  SemanticsNode node(WidgetTester tester, String key) =>
      tester.getSemantics(find.byKey(Key(key)));

  testWidgets('every sheet option is a button with a spoken label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSheet(tester);

    final expected = {
      'alarm-sheet-snooze-5_min': 'Snooze 5 minutes, rings at 9:05 AM',
      'alarm-sheet-snooze-30_min': 'Snooze 30 minutes, rings at 9:30 AM',
      'alarm-sheet-snooze-1_hour': 'Snooze 1 hour, rings at 10:00 AM',
      'alarm-sheet-snooze-tomorrow_morning':
          'Snooze until tomorrow morning, rings at 9:00 AM',
      'alarm-sheet-custom': 'Pick a time…',
      'alarm-sheet-silence':
          'Silence indefinitely, The task stays open, the alarm stays quiet',
      'alarm-sheet-complete': 'Complete',
      'alarm-sheet-open': 'Open',
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      final n = node(tester, key);
      expect(plain(n.label), value, reason: key);
      expect(n, isSemantics(isButton: true, hasTapAction: true), reason: key);
      // One node: nothing inside it is read on its own.
      expect(n.childrenCount, 0, reason: key);
    }
    semantics.dispose();
  });

  testWidgets('a preset that joins another alarm says so in its label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // Task 9 rings at 09:05: "5 min" joins it.
    await pumpSheet(
      tester,
      alarms: [alarm('9', snoozedUntil: now.add(const Duration(minutes: 5)))],
    );
    expect(
      plain(node(tester, 'alarm-sheet-snooze-5_min').label),
      'Snooze 5 minutes, rings at 9:05 AM · with another alarm',
    );
    expect(
      plain(node(tester, 'alarm-sheet-snooze-30_min').label),
      'Snooze 30 minutes, rings at 9:30 AM',
    );
    semantics.dispose();
  });

  testWidgets('a screen reader\'s tap chooses the option', (tester) async {
    final semantics = tester.ensureSemantics();
    final chosen = await pumpSheet(tester);
    tester.semantics.tap(
      find.semantics.byLabel(RegExp(r'^Snooze 30 minutes, ')),
    );
    await tester.pumpAndSettle();
    expect(chosen, hasLength(1));
    expect(
      (chosen.single as AlarmSheetSnooze).until,
      now.add(const Duration(minutes: 30)),
    );
    expect(find.byKey(const Key('alarm-sheet-open')), findsNothing);
    semantics.dispose();
  });

  testWidgets('Turkish labels read the snooze keys with the landing time', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    final semantics = tester.ensureSemantics();
    await pumpSheet(tester);
    expect(
      node(tester, 'alarm-sheet-snooze-5_min').label,
      startsWith('5 dakika ertele, '),
    );
    expect(node(tester, 'alarm-sheet-complete').label, 'Tamamla');
    expect(node(tester, 'alarm-sheet-open').label, 'Aç');
    semantics.dispose();
  });
}
