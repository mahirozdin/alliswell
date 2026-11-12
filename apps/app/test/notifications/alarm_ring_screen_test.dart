import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/web_alert_mode.dart';
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

  // The second urgent alarm of the same minute (#46).
  Future<void> seedSecond() async {
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id('T2'),
            workspaceId: wsId,
            title: 'Call the clinic',
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
            id: id('R2'),
            taskId: id('T2'),
            remindAt: at.add(const Duration(seconds: 20)),
            status: const Value('scheduled'),
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
  }

  AlarmInput secondAlarm() => AlarmInput(
    reminderId: id('R2'),
    taskId: id('T2'),
    taskTitle: 'Call the clinic',
    remindAt: at.add(const Duration(seconds: 20)),
    status: 'scheduled',
    urgent: true,
    requiresAcknowledgement: true,
  );

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

  /// The production composition (#46): the controller decides what rings and
  /// owns the sound; the shell's [AlarmOverlayLayer] shows the keyed screen.
  /// A GoRouter so "Aç" has somewhere to go.
  Future<void> pumpLayer(
    WidgetTester tester, {
    required List<AlarmInput> feed,
    AlarmFeedback? feedback,
    List<Override> extra = const [],
    bool second = false,
  }) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(
          alarmOverlayAutoShow: true,
          alarmFeedback: feedback,
        ),
        alarmFeedProvider.overrideWith((ref) => Stream.value(feed)),
        alarmClockProvider.overrideWithValue(
          () => at.add(const Duration(minutes: 1)),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    await seed();
    if (second) await seedSecond();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Stack(
              children: [
                Center(child: Text('home')),
                Positioned.fill(child: AlarmOverlayLayer()),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/tasks/:id',
          builder: (_, state) =>
              Scaffold(body: Text('task ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: _theme, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Iterable<ButtonStyleButton> ringButtons(WidgetTester tester) =>
      tester.widgetList<ButtonStyleButton>(
        find.descendant(
          of: find.byKey(const Key('alarm-ring')),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );

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

  // ── #46 / OPH-422: the Turkish suffix follows the spoken time ─────────────

  testWidgets('Turkish snooze tile reads 09:05’te çalar, not 09:05’de', (
    tester,
  ) async {
    // A fixed 09:00 so "5 dk" lands on 09:05 and "30 dk" on 09:30.
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => DateTime(2030, 6, 1, 9)),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    await seed();
    await pumpRing(tester);

    expect(find.text('09:05’te çalar'), findsOneWidget);
    expect(find.text('09:30’da çalar'), findsOneWidget);
    expect(find.text('10:00’da çalar'), findsOneWidget);
    expect(find.textContaining('09:05’de'), findsNothing);

    await tester.tap(find.byKey(const Key('alarm-snooze-30_min')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('09:30’da tekrar çalacak'), findsOneWidget);
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
      reason:
          'BLUEPRINT §8.2 promised a custom snooze; now it exists. This assertion '
          'used to fail for the half hour before local midnight: the time picker '
          'suggested now+30m (which is tomorrow) while the date picker opened on '
          'today, so accepting both defaults composed a time ~24h in the past and '
          'the handler discarded it silently. It only ever showed up on CI, which '
          'runs in UTC.',
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
    await pumpLayer(tester, feed: [theAlarm()], feedback: feedback);
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

  // ── OPH-316: silence the user chose, said out loud ──────────────────────
  //
  // `SilentAlarmFeedback` is deliberately NOT what the screen switches to: its
  // `start()` is a no-op, so the manual "start the sound" it offers would be a
  // dead button — the same lie as an alarm that looks like it is ringing.

  Future<void> pumpSilentByChoice(
    WidgetTester tester,
    _SpyFeedback spy, {
    required bool silent,
    bool chosen = true,
  }) async {
    await pumpLayer(
      tester,
      feed: [theAlarm()],
      feedback: spy,
      extra: [
        alarmOpensSilentProvider.overrideWithValue(silent),
        alarmSilenceChosenProvider.overrideWithValue(chosen),
      ],
    );
  }

  testWidgets('declares a silence the user asked for, and still offers sound', (
    tester,
  ) async {
    final spy = _SpyFeedback();
    await pumpSilentByChoice(tester, spy, silent: true);

    expect(find.byKey(const Key('alarm-silent-declared')), findsOneWidget);
    expect(find.byKey(const Key('alarm-start-sound')), findsOneWidget);
    // Nothing was played: the whole point of the setting.
    expect(spy.starts, 0);

    await tester.tap(find.byKey(const Key('alarm-start-sound')));
    await tester.pump();
    // ...and the offer is real. An affordance that does nothing would be the
    // same failure the declaration exists to prevent.
    expect(spy.starts, 1);
  });

  testWidgets('says nothing about silence when the alarm is meant to ring', (
    tester,
  ) async {
    final spy = _SpyFeedback();
    await pumpSilentByChoice(tester, spy, silent: false);

    expect(find.byKey(const Key('alarm-silent-declared')), findsNothing);
    expect(find.byKey(const Key('alarm-silent-default')), findsNothing);
    expect(spy.starts, 1);
  });

  // ── OPH-393 (E-20): nobody chose Silent in a fresh browser ──────────────
  testWidgets('a silent DEFAULT is not claimed as the person\'s choice', (
    tester,
  ) async {
    final spy = _SpyFeedback();
    await pumpSilentByChoice(tester, spy, silent: true, chosen: false);

    expect(find.byKey(const Key('alarm-silent-declared')), findsNothing);
    expect(find.textContaining('you set this browser'), findsNothing);
    // Still not a silent alarm that looks like a failure: it says why, and
    // the sound is one press away.
    expect(find.byKey(const Key('alarm-silent-default')), findsOneWidget);
    expect(find.textContaining('silent by default'), findsOneWidget);
    expect(find.byKey(const Key('alarm-start-sound')), findsOneWidget);
    expect(spy.starts, 0, reason: 'ADR-0039: the web default stays silent');
  });

  test('an untouched browser has not chosen anything', () async {
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await localKv.remove('alliswell_web_alert_mode');
    expect(fresh.read(alarmSilenceChosenProvider), isFalse);
    // ...and still behaves silently, as before (ADR-0039).
    expect(fresh.read(webAlertModeProvider), WebAlertMode.silent);

    await fresh.read(webAlertModeRawProvider.notifier).set('silent');
    addTearDown(() => localKv.remove('alliswell_web_alert_mode'));
    expect(fresh.read(alarmSilenceChosenProvider), isTrue);

    await fresh.read(webAlertModeRawProvider.notifier).set('loud');
    expect(fresh.read(alarmSilenceChosenProvider), isFalse);
  });

  // ── #46 / OPH-423: one sound owner, silence → dismiss → write ─────────────

  testWidgets(
    'acting on the first of two due alarms leaves the second fully actionable',
    (tester) async {
      await pumpLayer(tester, feed: [theAlarm(), secondAlarm()], second: true);
      expect(find.text('Take pills'), findsOneWidget);

      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await tester.pump();
      await tester.pump();

      // The second alarm has its own screen (keyed per occurrence), not the
      // first one's State with a "busy" flag that disabled every button.
      expect(find.text('Call the clinic'), findsOneWidget);
      expect(find.text('Take pills'), findsNothing);
      expect(
        find.byKey(
          ValueKey<String>(
            '${id('T2')}|${secondAlarm().remindAt.millisecondsSinceEpoch}',
          ),
        ),
        findsOneWidget,
      );
      final buttons = ringButtons(tester).toList();
      expect(buttons, isNotEmpty);
      for (final b in buttons) {
        expect(b.onPressed, isNotNull, reason: '${b.key} is never disabled');
      }

      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('alarm-ring')), findsNothing);
      final rows = await db.select(db.reminders).get();
      expect(
        {for (final r in rows) r.id: r.status},
        {id('R1'): 'acknowledged', id('R2'): 'acknowledged'},
      );
      // The real stores poke sync, whose auth probe arms a short timer.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'every action silences feedback before the write and dismisses at once',
    (tester) async {
      const actions = [
        'alarm-snooze-5_min',
        'alarm-snooze-30_min',
        'alarm-snooze-1_hour',
        'alarm-snooze-tomorrow_morning',
        'alarm-snooze-custom',
        'alarm-silence',
        'alarm-acknowledge',
        'alarm-complete',
        'alarm-open',
      ];
      for (final action in actions) {
        final log = <String>[];
        void write(String what) => log.add(
          'write $what, overlay '
          '${container.read(alarmOverlayControllerProvider).ringing.length}',
        );
        await pumpLayer(
          tester,
          feed: [theAlarm()],
          feedback: _LogFeedback(log),
          extra: [
            taskStoreProvider.overrideWith(
              (ref) => _RecordingTaskStore(ref.watch(databaseProvider), write),
            ),
            reminderStoreProvider.overrideWith(
              (ref) =>
                  _RecordingReminderStore(ref.watch(databaseProvider), write),
            ),
          ],
        );
        expect(log, ['start'], reason: '$action: the controller starts it');
        for (final b in ringButtons(tester)) {
          expect(b.onPressed, isNotNull, reason: '$action: ${b.key}');
        }

        await tester.ensureVisible(find.byKey(Key(action)));
        await tester.pump();
        await tester.tap(find.byKey(Key(action)));
        // No pump yet: the sound stopped inside the tap, before any await.
        expect(log.take(2), ['start', 'stop'], reason: action);

        if (action == 'alarm-snooze-custom') {
          // Silent while the pickers are open; accept both.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('OK'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('OK'));
          await tester.pump();
          expect(log.where((e) => e == 'start'), hasLength(1));
        } else {
          // Dismissed in the same tap, not after the write.
          expect(
            container.read(alarmOverlayControllerProvider).ringing,
            isEmpty,
            reason: action,
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('alarm-ring')), findsNothing);

        if (action == 'alarm-open') {
          // Aç silences and opens; it acknowledges nothing.
          expect(log.where((e) => e.startsWith('write')), isEmpty);
          expect(find.text('task ${id('T1')}'), findsOneWidget);
        } else {
          final writes = log.where((e) => e.startsWith('write')).toList();
          expect(writes, hasLength(1), reason: action);
          expect(writes.single, endsWith('overlay 0'), reason: action);
          expect(
            log.indexOf('stop'),
            lessThan(log.indexOf(writes.single)),
            reason: action,
          );
        }
        expect(log.where((e) => e == 'start'), hasLength(1), reason: action);
        await tester.pump(const Duration(seconds: 6));
      }
    },
  );

  testWidgets('backing out of the custom pickers brings the sound back', (
    tester,
  ) async {
    final log = <String>[];
    await pumpLayer(tester, feed: [theAlarm()], feedback: _LogFeedback(log));
    await tester.ensureVisible(find.byKey(const Key('alarm-snooze-custom')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-snooze-custom')));
    expect(log, ['start', 'stop']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(log, ['start', 'stop', 'start']);
    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
  });

  testWidgets(
    'a failed write comes back with the error; Try again repeats it',
    (tester) async {
      final log = <String>[];
      var failuresLeft = 1;
      await pumpLayer(
        tester,
        feed: [theAlarm()],
        feedback: _LogFeedback(log),
        extra: [
          reminderStoreProvider.overrideWith(
            (ref) => _RecordingReminderStore(ref.watch(databaseProvider), (w) {
              log.add('write $w');
              if (failuresLeft-- > 0) throw StateError('database is locked');
            }),
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await tester.pump();
      await tester.pump();

      // Back, with the error above the actions and the sound still off.
      expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
      expect(find.byKey(const Key('alarm-action-failed')), findsOneWidget);
      expect(
        find.text("Couldn't save. The sound stopped, try again."),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      // Stopped before the write, and not restarted by the re-show.
      expect(_squash(log), ['start', 'stop', 'write acknowledge']);
      for (final b in ringButtons(tester)) {
        expect(b.onPressed, isNotNull, reason: '${b.key}');
      }

      await tester.ensureVisible(find.byKey(const Key('alarm-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('alarm-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('alarm-ring')), findsNothing);
      expect(_squash(log), [
        'start',
        'stop',
        'write acknowledge',
        'stop',
        'write acknowledge',
      ]);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('E-20: the screen underneath leaves the semantics tree', (
    tester,
  ) async {
    await seed();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _theme,
          // The shell's own layering (`home_shell.dart`): the ring screen is
          // the last child of a Stack over Home.
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Home control behind'),
                  ),
                ),
                Positioned.fill(
                  child: AlarmRingScreen(
                    alarm: theAlarm(),
                    onHandled: handled.add,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Take pills'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Home control behind'),
      findsNothing,
      reason: 'a screen reader must not land behind a ringing alarm',
    );
    expect(find.bySemanticsLabel(RegExp('Take pills')), findsWidgets);
    semantics.dispose();
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

/// Records whether the alarm was actually played.
class _SpyFeedback implements AlarmFeedback {
  int starts = 0;
  final ValueNotifier<bool> _blocked = ValueNotifier(false);

  @override
  ValueListenable<bool> get soundBlocked => _blocked;

  @override
  void start() => starts += 1;

  @override
  void stop() {}
}

/// [log] with repeated neighbours folded: `silence()` and `handled()` both
/// stop, and stopping twice is one silence.
List<String> _squash(List<String> log) => [
  for (var i = 0; i < log.length; i++)
    if (i == 0 || log[i] != log[i - 1]) log[i],
];

/// Records the order of start/stop calls into a shared log (#46).
class _LogFeedback implements AlarmFeedback {
  _LogFeedback(this.log);

  final List<String> log;
  final ValueNotifier<bool> _blocked = ValueNotifier(false);

  @override
  ValueListenable<bool> get soundBlocked => _blocked;

  @override
  void start() => log.add('start');

  @override
  void stop() => log.add('stop');
}

/// A task store that records each write instead of performing it.
class _RecordingTaskStore extends TaskStore {
  _RecordingTaskStore(AwDatabase db, this.onWrite) : super(db, () {});

  final void Function(String what) onWrite;

  @override
  Future<void> snooze(
    String taskId, {
    String? preset,
    DateTime? until,
    String? receiptId,
  }) async => onWrite('snooze');

  @override
  Future<void> complete(String taskId, {String? receiptId}) async =>
      onWrite('complete');

  @override
  Future<void> muteAlarms(String taskId, {String? receiptId}) async =>
      onWrite('mute');
}

/// A reminder store whose acknowledge is the test's to decide.
class _RecordingReminderStore extends ReminderStore {
  _RecordingReminderStore(AwDatabase db, this.onWrite) : super(db, () {});

  final void Function(String what) onWrite;

  @override
  Future<void> acknowledge(String reminderId, {String? receiptId}) async =>
      onWrite('acknowledge');
}
