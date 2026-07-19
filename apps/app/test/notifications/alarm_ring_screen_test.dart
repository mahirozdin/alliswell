import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/sync_overrides.dart';

const wsId = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String p) => p.padRight(26, '0');

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
  extensions: const [AwTokens.light],
);

void main() {
  final at = DateTime.utc(2030, 6, 1, 9, 30);

  late ProviderContainer container;
  late AwDatabase db;
  late List<String> handled;

  setUp(() {
    container = ProviderContainer(overrides: syncTestOverrides());
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    handled = [];
  });

  Future<void> seed() async {
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id('T1'),
            workspaceId: wsId,
            title: 'Take pills',
            status: const Value('open'),
            isUrgent: const Value(true),
            requiresAcknowledgement: const Value(true),
            dueAt: Value(at),
          ),
        );
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id('R1'),
            taskId: id('T1'),
            remindAt: at,
            status: const Value('scheduled'),
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
  }

  AlarmInput theAlarm() => AlarmInput(
    reminderId: id('R1'),
    taskId: id('T1'),
    taskTitle: 'Take pills',
    remindAt: at,
    status: 'scheduled',
    urgent: true,
    requiresAcknowledgement: true,
  );

  Future<void> pumpRing(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _theme,
          home: AlarmRingScreen(alarm: theAlarm(), onHandled: handled.add),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the task, an acknowledge and snooze presets', (
    tester,
  ) async {
    await seed();
    await pumpRing(tester);

    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
    expect(find.text('Take pills'), findsOneWidget);
    expect(find.byKey(const Key('alarm-acknowledge')), findsOneWidget);
    expect(find.byKey(const Key('alarm-snooze-5_min')), findsOneWidget);
    expect(find.byKey(const Key('alarm-snooze-30_min')), findsOneWidget);
    expect(find.byKey(const Key('alarm-snooze-1_hour')), findsOneWidget);
  });

  testWidgets('Acknowledge flips the reminder row and dismisses', (
    tester,
  ) async {
    await seed();
    await pumpRing(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(handled, contains(id('R1')));
    final row = await (db.select(
      db.reminders,
    )..where((r) => r.id.equals(id('R1')))).getSingle();
    expect(row.status, 'acknowledged');
  });

  testWidgets('a snooze preset moves the task and dismisses', (tester) async {
    await seed();
    await pumpRing(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('alarm-snooze-30_min')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(handled, contains(id('R1')));
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id('T1')))).getSingle();
    expect(task.snoozedUntil, isNotNull);
  });
}
