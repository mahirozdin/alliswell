import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';
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
          // A Scaffold has to be mounted somewhere for the snooze confirmation
          // snackbar (OPH-177) — in the app the ring screen is layered over the
          // shell's Scaffold, so this mirrors production.
          home: Scaffold(
            body: AlarmRingScreen(alarm: theAlarm(), onHandled: handled.add),
          ),
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

  // ── OPH-177: "5 dk sonra ne olacak?" must not be a question ────────────────

  testWidgets('each preset shows the instant it will ring at', (tester) async {
    await seed();
    await pumpRing(tester);
    // The offset AND the clock time it lands on.
    expect(find.text('5 min'), findsOneWidget);
    final expected = awFormatTime(
      TaskStore.snoozeUntilFor('5_min'),
      format: kAwSystemDateFormat,
    );
    expect(
      find.textContaining(expected),
      findsWidgets,
      reason: 'the button says when the alarm comes back',
    );
  });

  testWidgets('snoozing confirms when it will ring again', (tester) async {
    await seed();
    await pumpRing(tester);
    await tester.tap(find.byKey(const Key('alarm-snooze-5_min')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Rings again at'), findsOneWidget);
    // Let the snackbar's own dismiss timer (and the session's) run out, or the
    // test tears down with a pending timer.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a custom snooze picks an exact time', (tester) async {
    await seed();
    await pumpRing(tester);
    expect(find.byKey(const Key('alarm-snooze-custom')), findsOneWidget);

    // The ring screen pulses forever (DESIGN §11 A1), so this file drives it
    // with pump(), never pumpAndSettle.
    Future<void> settleDialog() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // The ring screen scrolls (four snooze presets + custom + silence), and on
    // the 800x600 test surface this button sits right at the fold: it happened
    // to be tappable with macOS font metrics and was off-screen with Linux ones,
    // so this test passed locally and failed on CI. Scroll to it like the
    // silence test below does, instead of trusting where it lands.
    await tester.ensureVisible(find.byKey(const Key('alarm-snooze-custom')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-snooze-custom')));
    await settleDialog();
    // Accept both pickers untouched (tomorrow at now + 30 min).
    await tester.tap(find.text('OK'));
    await settleDialog();
    await tester.tap(find.text('OK'));
    await settleDialog();
    await tester.pump(const Duration(milliseconds: 500));

    final row = await db.select(db.tasks).getSingle();
    expect(
      row.snoozedUntil,
      isNotNull,
      reason: 'BLUEPRINT §8.2 promised a custom snooze; now it exists',
    );
    expect(row.snoozedUntil!.isAfter(DateTime.now().toUtc()), isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('silencing from the alarm mutes the task but keeps it open', (
    tester,
  ) async {
    await seed();
    await pumpRing(tester);

    // The ring screen scrolls (four snooze presets + custom + silence), so make
    // sure the button is on screen before tapping it.
    await tester.ensureVisible(find.byKey(const Key('alarm-silence')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-silence')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Says what it did…
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Alarm silenced'), findsOneWidget);

    final task = await db.select(db.tasks).getSingle();
    expect(task.alarmsMutedAt, isNotNull);
    // …and did NOT quietly complete the task to shut it up (round 9 #6.7).
    expect(task.status, 'open');
    expect(task.completedAt, equals(null));
    // The alarm surface is dismissed like any other answered alarm.
    expect(handled, contains(id('R1')));
    await tester.pump(const Duration(seconds: 6));
  });

  // OPH-180: when the platform refuses to make noise, the screen SAYS so and
  // offers to start it — the honest alternative to a silent alarm that looks
  // like it is ringing.
  testWidgets('a blocked sound offers a manual start', (tester) async {
    final sound = _RefusingSound();
    final feedback = AudioAlarmFeedback(sound);
    addTearDown(feedback.dispose);
    container = ProviderContainer(
      overrides: syncTestOverrides(alarmFeedback: feedback),
    );
    addTearDown(container.dispose);
    await seed();
    await pumpRing(tester);
    await tester.pump();

    expect(find.byKey(const Key('alarm-start-sound')), findsOneWidget);

    // A retry that succeeds hides the fallback again.
    sound.refuse = false;
    await tester.tap(find.byKey(const Key('alarm-start-sound')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('alarm-start-sound')), findsNothing);
    feedback.stop();
  });
}

/// Refuses to play, the way a browser's autoplay policy does.
class _RefusingSound implements AlarmSoundPlayer {
  bool refuse = true;

  @override
  Future<void> loop(String asset) async {
    if (refuse) throw StateError('blocked');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
