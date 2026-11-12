import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/persisted_prefs.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/alarm_action_tile.dart';
import 'package:alliswell/src/notifications/alarm_edge_fade.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/web_alert_mode.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/status_views.dart';

import '../support/created_tickers.dart';
import '../support/fake_notifications.dart';
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
    AlarmKitHost? alarmKitHost,
    List<Override> extra = const [],
    bool second = false,
    DateTime? clock,
  }) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(
          alarmOverlayAutoShow: true,
          alarmFeedback: feedback,
          alarmKitHost: alarmKitHost,
        ),
        alarmFeedProvider.overrideWith((ref) => Stream.value(feed)),
        alarmClockProvider.overrideWithValue(
          () => clock ?? at.add(const Duration(minutes: 1)),
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

  // S0 (CI on Flutter 3.44): a missed screen never starts its pulse, so a
  // lazily built controller was first constructed inside dispose(), on a
  // deactivated element. 3.44 throws there, dispose() aborts before the
  // minute tick's timer is cancelled and the test fails on a pending Timer.
  for (final missed in [true, false]) {
    final mode = missed ? 'a silent (missed)' : 'a ringing';
    testWidgets('$mode ring screen creates no animation controller while it '
        'is disposed', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _theme,
            home: Scaffold(
              body: AlarmRingScreen(
                alarm: theAlarm(),
                onHandled: handled.add,
                missed: missed,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AlarmRingScreen), findsOneWidget);

      final created = await tickersCreatedDuring(
        () => tester.pumpWidget(const SizedBox()),
      );

      expect(created, isEmpty);
      expect(tester.takeException(), isNull);
    });
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

    // A retry that succeeds hides the fallback again. W-04: on this 800x600
    // view the content above the pinned actions scrolls to it.
    sound.refuse = false;
    await tester.ensureVisible(find.byKey(const Key('alarm-start-sound')));
    await tester.pump();
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

    await tester.ensureVisible(find.byKey(const Key('alarm-start-sound')));
    await tester.pump();
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

  // An alarm shown two minutes or more after its instant
  // says how late, next to its time; one shown on time just shows its time.
  testWidgets('an alarm shown late says how late next to its time', (
    tester,
  ) async {
    // The layer's clock is `at` + 1 min: R1 is three minutes late.
    final late = AlarmInput(
      reminderId: id('R1'),
      taskId: id('T1'),
      taskTitle: 'Take pills',
      remindAt: at.subtract(const Duration(minutes: 2)),
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
    );
    await pumpLayer(tester, feed: [late]);
    final time = tester.widget<Text>(find.byKey(const Key('alarm-time')));
    expect(time.data, endsWith(' · 3 min ago'));
  });

  testWidgets('an alarm shown on time shows only its time', (tester) async {
    await pumpLayer(tester, feed: [theAlarm()]);
    final time = tester.widget<Text>(find.byKey(const Key('alarm-time')));
    expect(time.data, isNot(contains('ago')));
  });

  testWidgets('a late list says how late in its header', (tester) async {
    final late = [
      for (final a in [theAlarm(), secondAlarm()])
        AlarmInput(
          reminderId: a.reminderId,
          taskId: a.taskId,
          taskTitle: a.taskTitle,
          remindAt: a.remindAt.subtract(const Duration(minutes: 4)),
          status: 'scheduled',
          urgent: true,
          requiresAcknowledgement: true,
        ),
    ];
    await pumpLayer(tester, feed: late, second: true);
    expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
    final header = tester.widget<Text>(
      find.byKey(const Key('alarm-list-header-text')),
    );
    expect(header.textSpan!.toPlainText(), endsWith(' · 5 min ago'));
  });

  testWidgets(
    'acting on the first of two due alarms leaves the second fully actionable',
    (tester) async {
      await pumpLayer(tester, feed: [theAlarm(), secondAlarm()], second: true);
      // Two tasks ring: one list (#47, OPH-443), each row its own answer.
      expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
      expect(find.text('Take pills'), findsOneWidget);

      await tester.tap(find.byKey(Key('alarm-row-ack-${id('T1')}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The last row is the single layout, keyed per occurrence, not a list
      // State with a "busy" flag that disabled every button.
      expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
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

  // A snoozed task's reminder and deadline rows land on one instant: one
  // task, the single layout, and Acknowledge answers both of them — not the
  // shown row only, leaving its sibling active behind a closed screen.
  testWidgets('acknowledge answers every row of the task in the occurrence', (
    tester,
  ) async {
    final deadline = AlarmInput(
      reminderId: id('R1D'),
      taskId: id('T1'),
      taskTitle: 'Take pills',
      remindAt: at,
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
      kind: 'due',
    );
    await pumpLayer(tester, feed: [theAlarm(), deadline]);
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id('R1D'),
            taskId: id('T1'),
            remindAt: at,
            kind: const Value('due'),
            status: const Value('scheduled'),
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final rows = await tester.runAsync(
      () => (db.select(
        db.reminders,
      )..orderBy([(r) => OrderingTerm.asc(r.id)])).get(),
    );
    expect(
      {for (final r in rows!) r.id: r.status},
      {id('R1'): 'acknowledged', id('R1D'): 'acknowledged'},
    );
    await tester.pump(const Duration(seconds: 6));
  });

  // ADR-0068 decision 1: a task whose remind and due instants share the
  // minute is one member. The minute rings from :00, so at :14 the :32
  // deadline is already on this one screen: Acknowledge answers both and
  // the screen closes, instead of the :32 row taking its place.
  testWidgets('acknowledge answers the task\'s whole minute and closes at '
      'once, a row due after the press included', (tester) async {
    final deadline = AlarmInput(
      reminderId: id('R1D'),
      taskId: id('T1'),
      taskTitle: 'Take pills',
      remindAt: at.add(const Duration(seconds: 32)),
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
      kind: 'due',
    );
    await pumpLayer(
      tester,
      feed: [theAlarm(), deadline],
      clock: at.add(const Duration(seconds: 14)),
    );
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id('R1D'),
            taskId: id('T1'),
            remindAt: at.add(const Duration(seconds: 32)),
            kind: const Value('due'),
            status: const Value('scheduled'),
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
    expect(
      container.read(alarmOverlayControllerProvider).ringing,
      hasLength(2),
    );
    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    // Dismissed in the tap: the :32 row does not replace the screen.
    expect(container.read(alarmOverlayControllerProvider).ringing, isEmpty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('alarm-ring')), findsNothing);

    final rows = await tester.runAsync(
      () => (db.select(
        db.reminders,
      )..orderBy([(r) => OrderingTerm.asc(r.id)])).get(),
    );
    expect(
      {for (final r in rows!) r.id: r.status},
      {id('R1'): 'acknowledged', id('R1D'): 'acknowledged'},
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('cancelling the custom time dialog snoozes nothing', (
    tester,
  ) async {
    final log = <String>[];
    void write(String what) => log.add('write $what');
    await pumpLayer(
      tester,
      feed: [theAlarm()],
      feedback: _LogFeedback(log),
      extra: [
        taskStoreProvider.overrideWith(
          (ref) => _RecordingTaskStore(ref.watch(databaseProvider), write),
        ),
      ],
    );
    await tester.ensureVisible(find.byKey(const Key('alarm-snooze-custom')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-snooze-custom')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(log.where((e) => e.startsWith('write')), isEmpty);
    expect(log, ['start', 'stop', 'start']);
    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
  });

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
      // W-09: only the write that landed says so.
      expect(find.widgetWithText(SnackBar, 'Acknowledged'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  // ── #46 iOS 26+ leg / OPH-428 ─────────────────────────────────────────────

  testWidgets(
    'AlarmKit-covered alarm opens the screen without starting in-app sound',
    (tester) async {
      final log = <String>[];
      final host = FakeAlarmKitHost();
      await pumpLayer(
        tester,
        feed: [theAlarm()],
        feedback: _LogFeedback(log),
        alarmKitHost: host,
        extra: [
          alarmKitViewProvider.overrideWith(
            () => AlarmKitView([
              AlarmKitScheduled(
                id: 31,
                members: [id('T1')],
                fireAtMs: alarmKitFireAtMs(at),
              ),
            ]),
          ),
        ],
      );

      expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
      expect(log, isEmpty, reason: 'the AlarmKit alert is the sound');
      // One line says where the sound is; no "start the sound" to double it,
      // and no claim that somebody chose silence.
      expect(
        find.byKey(const Key('alarm-rings-on-lock-screen')),
        findsOneWidget,
      );
      expect(
        find.text('The alarm is ringing on the lock screen too.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('alarm-start-sound')), findsNothing);
      expect(find.byKey(const Key('alarm-silent-declared')), findsNothing);
      expect(find.byKey(const Key('alarm-silent-default')), findsNothing);

      // "Aç" is an action too: it silences the system alert as well.
      await tester.ensureVisible(find.byKey(const Key('alarm-open')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('alarm-open')));
      expect(host.stopped, [31]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('alarm-ring')), findsNothing);
      expect(log.where((e) => e == 'start'), isEmpty);
    },
  );

  testWidgets(
    'backing out of the custom pickers of a covered alarm rings in the app',
    (tester) async {
      final log = <String>[];
      final host = FakeAlarmKitHost();
      await pumpLayer(
        tester,
        feed: [theAlarm()],
        feedback: _LogFeedback(log),
        alarmKitHost: host,
        extra: [
          alarmKitViewProvider.overrideWith(
            () => AlarmKitView([
              AlarmKitScheduled(
                id: 31,
                state: AlarmKitAlarmState.alerting,
                members: [id('T1')],
                fireAtMs: alarmKitFireAtMs(at),
              ),
            ]),
          ),
        ],
      );
      expect(log, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('alarm-snooze-custom')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('alarm-snooze-custom')));
      // The person is dealing with it: the system alert stops at the tap.
      expect(host.stopped, [31]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Still unanswered, and the system alert is gone: the app rings it.
      expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
      expect(_squash(log).last, 'start');
      expect(find.byKey(const Key('alarm-rings-on-lock-screen')), findsNothing);
    },
  );

  // ── OPH-466: direction A — one grid, pinned actions, short screens ────────

  const snoozeKeys = [
    'alarm-snooze-5_min',
    'alarm-snooze-30_min',
    'alarm-snooze-1_hour',
    'alarm-snooze-tomorrow_morning',
    'alarm-snooze-custom',
    'alarm-silence',
  ];

  /// The ring screen alone at [size] logical px, as a phone shows it.
  Future<void> pumpSized(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    List<AlarmInput> alarms = const [],
    AlarmInput? alarm,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: AlarmRingScreen(
              alarm: alarm ?? theAlarm(),
              onHandled: handled.add,
              alarms: alarms,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(Key(key)));

  testWidgets('snooze grid cells share one width at 320 and 430 logical px', (
    tester,
  ) async {
    await seed();
    for (final width in [320.0, 430.0]) {
      await pumpSized(tester, Size(width, 932));

      final rects = [for (final k in snoozeKeys) rectOf(tester, k)];
      for (final r in rects) {
        expect(r.width, moreOrLessEquals(rects.first.width), reason: '$r');
        expect(r.height, moreOrLessEquals(56), reason: '$r');
      }
      // Two columns, three rows, one gap of AwSpace.x2 between columns.
      final lefts = {for (final r in rects) r.left.roundToDouble()};
      expect(lefts, hasLength(2), reason: '$width');
      expect(rects[1].left - rects[0].right, moreOrLessEquals(AwSpace.x2));
      // The content column: the screen minus 2 × 24.
      expect(
        rects[1].right - rects[0].left,
        moreOrLessEquals(width - 2 * AwSpace.x6),
      );
    }
  });

  testWidgets('acknowledge spans the grid width and sits below it', (
    tester,
  ) async {
    await seed();
    await pumpSized(tester, const Size(393, 852));

    final grid = [for (final k in snoozeKeys) rectOf(tester, k)];
    final left = grid.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    final right = grid.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    final bottom = grid.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
    final ack = rectOf(tester, 'alarm-acknowledge');
    expect(ack.left, moreOrLessEquals(left));
    expect(ack.right, moreOrLessEquals(right));
    expect(ack.top, greaterThan(bottom));
    expect(ack.height, moreOrLessEquals(56));
    // Tamamla | Aç: two equal 48 pt halves of the same width, below Onayla.
    final complete = rectOf(tester, 'alarm-complete');
    final open = rectOf(tester, 'alarm-open');
    expect(complete.height, moreOrLessEquals(48));
    expect(open.height, moreOrLessEquals(48));
    expect(complete.width, moreOrLessEquals(open.width));
    expect(complete.top, greaterThan(ack.bottom));
    expect(complete.left, moreOrLessEquals(left));
    expect(open.right, moreOrLessEquals(right));
    // The actions sit at the bottom of the phone, under the content.
    expect(complete.bottom, greaterThan(852 - 80));
  });

  testWidgets('no button ever renders disabled while an action runs', (
    tester,
  ) async {
    final write = Completer<void>();
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        taskStoreProvider.overrideWith(
          (ref) => _SlowTaskStore(ref.watch(databaseProvider), write.future),
        ),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    await seed();
    await pumpSized(tester, const Size(393, 852));

    await tester.tap(find.byKey(const Key('alarm-snooze-30_min')));
    await tester.pump();
    // Under 300 ms the tile shows nothing new.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));

    // Past 300 ms: a spinner in the pressed tile, and only there.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('alarm-snooze-30_min')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    for (final b in ringButtons(tester)) {
      expect(b.onPressed, isNotNull, reason: '${b.key}');
    }
    final tiles = tester.widgetList<AwAlarmActionTile>(
      find.byType(AwAlarmActionTile),
    );
    expect(tiles, isNotEmpty);
    for (final t in tiles) {
      expect(t.onPressed, isNotNull, reason: '${t.key}');
    }

    write.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a short screen under 700 pt keeps every action visible', (
    tester,
  ) async {
    await seed();
    for (final size in [const Size(360, 640), const Size(375, 667)]) {
      await pumpSized(tester, size);

      for (final k in [
        ...snoozeKeys,
        'alarm-acknowledge',
        'alarm-complete',
        'alarm-open',
      ]) {
        final r = rectOf(tester, k);
        expect(r.top, greaterThanOrEqualTo(0), reason: '$size $k');
        expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$size $k');
      }
      // A6/A7: badge 64, no "Snooze" section label.
      expect(tester.getSize(find.byKey(const Key('alarm-badge'))).width, 64);
      expect(find.byKey(const Key('alarm-snooze-label')), findsNothing);
    }
  });

  // OPH-467 (DESIGN §11 A9): the "Acil hatırlatma" label is text on the urgency wash.
  // prioUrgent measured 3.94:1 (light) / 4.36:1 (dark) there, so the label
  // takes errorOnPage (contrast.py: ring label "Acil hatırlatma"); the badge keeps
  // prioUrgent, which only needs 3:1 as a mark.
  for (final dark in [false, true]) {
    testWidgets(
      'the ringing label is errorOnPage, the badge prioUrgent (dark: $dark)',
      (tester) async {
        await seed();
        final tokens = dark ? AwTokens.dark : AwTokens.light;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF2563EB),
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                extensions: [tokens],
              ),
              home: Scaffold(
                body: AlarmRingScreen(
                  alarm: theAlarm(),
                  onHandled: handled.add,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final label = tester.widget<Text>(
          find.byKey(const Key('alarm-ringing-label')),
        );
        expect(label.style?.color, tokens.errorOnPage);
        final badge = tester.widget<Container>(
          find.byKey(const Key('alarm-badge')),
        );
        final border = (badge.decoration! as BoxDecoration).border! as Border;
        expect(border.top.color, tokens.prioUrgent);
      },
    );
  }

  testWidgets('a tall screen keeps the 96 badge and the section label', (
    tester,
  ) async {
    await seed();
    await pumpSized(tester, const Size(393, 852));
    expect(tester.getSize(find.byKey(const Key('alarm-badge'))).width, 96);
    expect(find.byKey(const Key('alarm-snooze-label')), findsOneWidget);
  });

  testWidgets('text scale above 1.3 switches the grid to one column', (
    tester,
  ) async {
    await seed();
    await pumpSized(tester, const Size(393, 852), textScale: 1.3);
    expect(
      rectOf(tester, 'alarm-snooze-30_min').left,
      greaterThan(rectOf(tester, 'alarm-snooze-5_min').right),
      reason: 'at 1.3 the grid keeps two columns',
    );

    await pumpSized(tester, const Size(393, 852), textScale: 1.5);
    final first = rectOf(tester, 'alarm-snooze-5_min');
    final second = rectOf(tester, 'alarm-snooze-30_min');
    expect(second.left, moreOrLessEquals(first.left));
    expect(second.top, greaterThan(first.bottom));
    expect(first.width, moreOrLessEquals(393 - 2 * AwSpace.x6));
    // The whole screen scrolls, and Onayla is still reachable at its end.
    await tester.scrollUntilVisible(
      find.byKey(const Key('alarm-open')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('alarm-ring')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('alarm-acknowledge')), findsOneWidget);
  });

  testWidgets('a failed write shows the inline error with the sound kept off', (
    tester,
  ) async {
    final log = <String>[];
    await pumpLayer(
      tester,
      feed: [theAlarm()],
      feedback: _LogFeedback(log),
      extra: [
        reminderStoreProvider.overrideWith(
          (ref) => _RecordingReminderStore(ref.watch(databaseProvider), (w) {
            log.add('write $w');
            throw StateError('database is locked');
          }),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('alarm-acknowledge')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final error = find.byType(AwInlineError);
    expect(error, findsOneWidget);
    expect(
      find.text("Couldn't save. The sound stopped, try again."),
      findsOneWidget,
    );
    // Above the actions: the error, then its retry, then the grid.
    final errorRect = tester.getRect(error);
    final retry = rectOf(tester, 'alarm-retry');
    expect(retry.top, greaterThanOrEqualTo(errorRect.bottom));
    expect(rectOf(tester, 'alarm-snooze-5_min').top, greaterThan(retry.bottom));
    expect(rectOf(tester, 'alarm-acknowledge').top, greaterThan(retry.bottom));
    // The sound stays off: no start after the stop.
    expect(_squash(log), ['start', 'stop', 'write acknowledge']);
    // The controller's no-interaction minute (OPH-441) is not this test's.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('a snooze into an occupied minute says it rings with another '
      'alarm', (tester) async {
    final now = DateTime(2030, 6, 1, 9);
    final other = AlarmInput(
      reminderId: id('R9'),
      taskId: id('T9'),
      taskTitle: 'Other',
      remindAt: now.add(const Duration(minutes: 5)).toUtc(),
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
    );
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    await seed();
    await pumpSized(tester, const Size(430, 932), alarms: [theAlarm(), other]);

    expect(
      find.descendant(
        of: find.byKey(const Key('alarm-snooze-5_min')),
        matching: find.textContaining('with another alarm'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('alarm-snooze-30_min')),
        matching: find.textContaining('with another alarm'),
      ),
      findsNothing,
    );
    expect(find.textContaining('with another alarm'), findsOneWidget);
  });

  testWidgets('Enter acknowledges, 1 snoozes with the first preset, Esc '
      'does nothing', (tester) async {
    await seed();
    await pumpSized(tester, const Size(1280, 800));
    // First focus is Onayla.
    final ack = find.byKey(const Key('alarm-acknowledge'));
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      find.descendant(
        of: ack,
        matching: find.byElementPredicate((e) => e == focused),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(handled, isEmpty);

    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(handled, [id('R1')]);
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id('T1')))).getSingle();
    expect(task.snoozedUntil, isNotNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Enter acknowledges', (tester) async {
    await seed();
    await pumpSized(tester, const Size(1280, 800));
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(handled, [id('R1')]);
    final row = await (db.select(
      db.reminders,
    )..where((r) => r.id.equals(id('R1')))).getSingle();
    expect(row.status, 'acknowledged');
  });

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

  // ── OPH-443: list mode (#47) — rows, the row sheet, Tümünü ertele/onayla ──

  AlarmInput thirdAlarm() => AlarmInput(
    reminderId: id('R3'),
    taskId: id('T3'),
    taskTitle: 'Share the meeting notes',
    remindAt: at.add(const Duration(seconds: 40)),
    status: 'scheduled',
    urgent: true,
    requiresAcknowledgement: true,
  );

  // Local 09:00: "5 min" lands on 09:05.
  final listNow = DateTime(2030, 6, 1, 9);

  /// The shell's layer with three ringing tasks; every action's in-app event
  /// is recorded instead of applied (the OPH-441 seam).
  Future<List<NotificationEvent>> pumpList(
    WidgetTester tester, {
    List<String>? log,
    List<AlarmInput>? feed,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final events = <NotificationEvent>[];
    await pumpLayer(
      tester,
      feed: feed ?? [theAlarm(), secondAlarm(), thirdAlarm()],
      feedback: log == null ? null : _LogFeedback(log),
      extra: [
        nowProvider.overrideWithValue(() => listNow),
        alarmActionApplierProvider.overrideWithValue((event) async {
          log?.add('write ${event.actionId}');
          events.add(event);
          return true;
        }),
      ],
    );
    return events;
  }

  int ms(Duration after) => listNow.add(after).millisecondsSinceEpoch;

  /// Snackbars run out, and the controller's no-interaction minute
  /// (OPH-441) goes with the container: it is not these tests'.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  testWidgets('snooze all emits one batch and silences once', (tester) async {
    final log = <String>[];
    final events = await pumpList(tester, log: log);
    expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
    expect(find.byKey(const Key('alarm-ring')), findsNothing);
    expect(find.text('3 URGENT REMINDERS · ${_clock(tester, at)}'), findsOne);
    // One sound for the whole list.
    expect(log, ['start']);
    // The bulk grid: the first three presets and "Pick a time…" — never
    // "Tomorrow morning" or "Silence indefinitely" for every row at once.
    for (final p in ['5_min', '30_min', '1_hour', 'custom']) {
      expect(find.byKey(Key('alarm-all-snooze-$p')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('alarm-all-snooze-tomorrow_morning')),
      findsNothing,
    );
    expect(find.byKey(const Key('alarm-silence')), findsNothing);

    await tester.tap(find.byKey(const Key('alarm-all-snooze-5_min')));
    // Silenced inside the tap, before the write; the list is gone at once.
    expect(log.take(2), ['start', 'stop']);
    expect(container.read(alarmOverlayControllerProvider).ringing, isEmpty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(log, ['start', 'stop', 'write snooze']);
    expect(events, hasLength(1));
    expect(events.single.actionId, 'snooze');
    expect(events.single.taskIds, [id('T1'), id('T2'), id('T3')]);
    expect(events.single.untilMs, ms(const Duration(minutes: 5)));
    expect(events.single.origin, 'inapp');
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
    // Said on the shell's messenger once the batch landed.
    expect(find.textContaining('3 alarms ring again at'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('acknowledge all (3) acknowledges every row in one batch', (
    tester,
  ) async {
    final log = <String>[];
    final events = await pumpList(tester, log: log);
    final all = find.byKey(const Key('alarm-acknowledge-all'));
    expect(
      find.descendant(of: all, matching: find.text('Acknowledge all (3)')),
      findsOneWidget,
    );

    await tester.tap(all);
    expect(log.take(2), ['start', 'stop']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(log, ['start', 'stop', 'write acknowledge']);
    expect(events, hasLength(1));
    expect(events.single.actionId, 'acknowledge');
    expect(events.single.taskIds, [id('T1'), id('T2'), id('T3')]);
    expect(events.single.untilMs, isNull);
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
    expect(find.text('3 alarms acknowledged'), findsOneWidget);
    await settle(tester);
  });

  testWidgets(
    'the row sheet offers presets with times, custom, silence, complete and '
    'open',
    (tester) async {
      final log = <String>[];
      final events = await pumpList(tester, log: log);
      final row = Key('alarm-row-snooze-${id('T2')}');

      await tester.tap(find.byKey(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Opening the sheet is the person dealing with it: quiet.
      expect(_squash(log), ['start', 'stop']);
      for (final (preset, after) in [
        ('5_min', const Duration(minutes: 5)),
        ('30_min', const Duration(minutes: 30)),
        ('1_hour', const Duration(hours: 1)),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('alarm-sheet-snooze-$preset')),
            matching: find.text(
              awFormatTime(listNow.add(after), format: kAwSystemDateFormat),
            ),
          ),
          findsOneWidget,
          reason: preset,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('alarm-sheet-snooze-tomorrow_morning')),
          matching: find.textContaining('tomorrow'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('alarm-sheet-custom')), findsOneWidget);
      expect(find.byKey(const Key('alarm-sheet-silence')), findsOneWidget);
      expect(
        find.text('The task stays open, the alarm stays quiet'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('alarm-sheet-complete')), findsOneWidget);
      expect(find.byKey(const Key('alarm-sheet-open')), findsOneWidget);

      // Closed without a choice: the row is still ringing, sound and all.
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('alarm-sheet-open')), findsNothing);
      expect(events, isEmpty);
      expect(
        container.read(alarmOverlayControllerProvider).ringing,
        hasLength(3),
      );
      expect(_squash(log), ['start', 'stop', 'start']);

      // A preset in the sheet answers that row only, as one event.
      await tester.tap(find.byKey(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('alarm-sheet-snooze-30_min')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(events, hasLength(1));
      expect(events.single.actionId, 'snooze');
      expect(events.single.taskIds, [id('T2')]);
      expect(events.single.untilMs, ms(const Duration(minutes: 30)));
      expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
      expect(find.byKey(Key('alarm-row-${id('T2')}')), findsNothing);
      expect(find.byKey(Key('alarm-row-${id('T1')}')), findsOneWidget);
      expect(find.byKey(Key('alarm-row-${id('T3')}')), findsOneWidget);
      expect(find.text('2 URGENT REMINDERS · ${_clock(tester, at)}'), findsOne);
      expect(find.text('Acknowledge all (2)'), findsOneWidget);

      // Silence, complete and open from the sheet: each answers its row.
      await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T3')}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.byKey(const Key('alarm-sheet-silence')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('alarm-sheet-silence')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(events.last.actionId, 'mute');
      expect(events.last.taskIds, [id('T3')]);
      // One row left: the single layout (OPH-466).
      expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
      expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
      await settle(tester);
    },
  );

  testWidgets('cancelling the bulk time picker snoozes nothing', (
    tester,
  ) async {
    final log = <String>[];
    final events = await pumpList(tester, log: log);
    await tester.ensureVisible(
      find.byKey(const Key('alarm-all-snooze-custom')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-all-snooze-custom')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Today's date accepted, then the time dialog cancelled.
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(events, isEmpty);
    expect(
      container.read(alarmOverlayControllerProvider).ringing,
      hasLength(3),
    );
    // A back-out: the list rings again.
    expect(_squash(log), ['start', 'stop', 'start']);
    await settle(tester);
  });

  testWidgets('a row sheet preset counts from the press, not from opening', (
    tester,
  ) async {
    var clock = listNow;
    final events = <NotificationEvent>[];
    await pumpLayer(
      tester,
      feed: [theAlarm(), secondAlarm(), thirdAlarm()],
      extra: [
        nowProvider.overrideWithValue(() => clock),
        alarmActionApplierProvider.overrideWithValue((event) async {
          events.add(event);
          return true;
        }),
      ],
    );
    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T2')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The sheet opened at 09:00; "5 min" is pressed at 09:06.
    clock = listNow.add(const Duration(minutes: 6));
    await tester.tap(find.byKey(const Key('alarm-sheet-snooze-5_min')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(events.single.taskIds, [id('T2')]);
    expect(events.single.untilMs, ms(const Duration(minutes: 11)));
    await settle(tester);
  });

  testWidgets('the row sheet completes or opens its own row', (tester) async {
    final events = await pumpList(tester);
    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T1')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byKey(const Key('alarm-sheet-complete')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-sheet-complete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(events.single.actionId, 'complete');
    expect(events.single.taskIds, [id('T1')]);

    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T2')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byKey(const Key('alarm-sheet-open')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('alarm-sheet-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // "Aç" opens the task and acknowledges nothing.
    expect(events, hasLength(1));
    expect(find.text('task ${id('T2')}'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('a failed bulk write brings every row back flagged; Try again '
      'repeats the same event', (tester) async {
    final log = <String>[];
    final events = <NotificationEvent>[];
    var failuresLeft = 1;
    await pumpLayer(
      tester,
      feed: [theAlarm(), secondAlarm(), thirdAlarm()],
      feedback: _LogFeedback(log),
      extra: [
        nowProvider.overrideWithValue(() => listNow),
        alarmActionApplierProvider.overrideWithValue((event) async {
          events.add(event);
          if (failuresLeft-- > 0) throw StateError('database is locked');
          return true;
        }),
      ],
    );
    await tester.tap(find.byKey(const Key('alarm-acknowledge-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Back as the list, every row flagged, the sound still off.
    expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
    expect(find.byKey(const Key('alarm-action-failed')), findsOneWidget);
    expect(container.read(alarmOverlayControllerProvider).failed, hasLength(3));
    // The rows on screen say which ones did not save.
    for (final t in ['T1', 'T2']) {
      expect(find.byKey(Key('alarm-row-failed-${id(t)}')), findsOneWidget);
    }
    expect(_squash(log), ['start', 'stop']);

    await tester.tap(find.byKey(const Key('alarm-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, hasLength(2));
    expect(events.last.eventId, events.first.eventId);
    expect(events.last.taskIds, [id('T1'), id('T2'), id('T3')]);
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
    expect(_squash(log), ['start', 'stop']);
    await settle(tester);
  });

  testWidgets('the last remaining row switches back to the single layout', (
    tester,
  ) async {
    final events = await pumpList(tester, feed: [theAlarm(), secondAlarm()]);
    expect(find.byKey(const Key('alarm-ring-list')), findsOneWidget);
    expect(find.text('Acknowledge all (2)'), findsOneWidget);

    await tester.tap(find.byKey(Key('alarm-row-ack-${id('T1')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.single.actionId, 'acknowledge');
    expect(events.single.taskIds, [id('T1')]);
    expect(find.byKey(const Key('alarm-ring-list')), findsNothing);
    expect(find.byKey(const Key('alarm-ring')), findsOneWidget);
    expect(find.text('Call the clinic'), findsOneWidget);
    expect(find.byKey(const Key('alarm-acknowledge')), findsOneWidget);
    expect(find.byKey(const Key('alarm-snooze-5_min')), findsOneWidget);
    await settle(tester);
  });

  testWidgets('list mode fits 360×640 with the bulk actions pinned', (
    tester,
  ) async {
    await pumpList(tester, size: const Size(360, 640));
    const bulk = [
      'alarm-all-snooze-5_min',
      'alarm-all-snooze-30_min',
      'alarm-all-snooze-1_hour',
      'alarm-all-snooze-custom',
      'alarm-acknowledge-all',
    ];
    final before = {for (final k in bulk) k: rectOf(tester, k)};
    for (final k in bulk) {
      final r = before[k]!;
      expect(r.top, greaterThanOrEqualTo(0), reason: k);
      expect(r.bottom, lessThanOrEqualTo(640), reason: k);
      expect(r.height, greaterThanOrEqualTo(56), reason: k);
    }
    // Two equal columns.
    expect(
      before['alarm-all-snooze-5_min']!.width,
      before['alarm-all-snooze-30_min']!.width,
    );
    final header = rectOf(tester, 'alarm-list-header');
    expect(header.top, greaterThanOrEqualTo(0));
    expect(header.bottom, lessThan(100));
    // Row pills are 44, the two of a row the same width.
    final snooze = rectOf(tester, 'alarm-row-snooze-${id('T1')}');
    final ack = rectOf(tester, 'alarm-row-ack-${id('T1')}');
    expect(snooze.height, greaterThanOrEqualTo(44));
    expect(snooze.width, ack.width);
    expect(tester.takeException(), isNull);

    // The list scrolls under the pinned actions.
    final rows = find.byKey(const Key('alarm-ring-rows'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: rows, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    final firstTop = rectOf(tester, 'alarm-row-${id('T1')}').top;
    await tester.drag(rows, const Offset(0, -200));
    await tester.pump();
    expect(rectOf(tester, 'alarm-row-${id('T1')}').top, lessThan(firstTop));
    for (final k in bulk) {
      expect(rectOf(tester, k), before[k], reason: '$k stays pinned');
    }
    await settle(tester);
  });

  // ── P2 polish: the single screen (OPH-466) ─────────────────────────────

  // W-03: a label built once said 09:05 while the tap, a minute later,
  // wrote 09:06. The label follows the minute, and the tap writes the very
  // instant the label states.
  testWidgets(
    'a snooze tile label follows the clock across a minute change and equals '
    'what the tap writes',
    (tester) async {
      var clock = DateTime(2030, 6, 1, 9, 0, 50);
      container = ProviderContainer(
        overrides: [
          ...syncTestOverrides(),
          nowProvider.overrideWithValue(() => clock),
        ],
      );
      addTearDown(container.dispose);
      db = container.read(databaseProvider);
      AwI18n.instance.setActiveCached(const Locale('tr'));
      addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
      await seed();
      await pumpRing(tester);
      expect(find.text('09:05’te çalar'), findsOneWidget);

      // The minute changes while the screen sits there: no tap, no rebuild
      // from anything else — the tile has to notice by itself.
      clock = DateTime(2030, 6, 1, 9, 1, 5);
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('09:06’da çalar'), findsOneWidget);
      expect(find.text('09:05’te çalar'), findsNothing);

      // Pressed at 09:01:30: the write lands in 09:06, the minute shown.
      clock = DateTime(2030, 6, 1, 9, 1, 30);
      await tester.tap(find.byKey(const Key('alarm-snooze-5_min')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id('T1')))).getSingle();
      final until = task.snoozedUntil!.toLocal();
      expect((until.hour, until.minute), (9, 6));
      expect(find.text('09:06’da tekrar çalacak'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the "with another alarm" hint reads the same minute as the '
      'label', (tester) async {
    var clock = DateTime(2030, 6, 1, 9, 0, 50);
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => clock),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    await seed();
    // Another task's urgent alarm holds 09:06, not 09:05.
    final other = AlarmInput(
      reminderId: id('R9'),
      taskId: id('T9'),
      taskTitle: 'Other',
      remindAt: DateTime(2030, 6, 1, 9, 6, 20),
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
    );
    await pumpSized(tester, const Size(430, 932), alarms: [other]);
    final five = find.byKey(const Key('alarm-snooze-5_min'));
    expect(
      find.descendant(of: five, matching: find.textContaining('another')),
      findsNothing,
    );
    clock = DateTime(2030, 6, 1, 9, 1, 2);
    await tester.pump(const Duration(seconds: 12));
    expect(
      find.descendant(of: five, matching: find.textContaining('another')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  // X-01 (OPH-466): with the silent hint at 360x640 the pinned actions left
  // the content a region too small for it — the sentence was cut and "Start
  // sound" sat under the grid, out of reach. The actions are pinned only
  // when the content fits above them; otherwise the whole screen scrolls in
  // its natural order, nothing overlapping, nothing clipped.
  Finder ringPage() => find
      .descendant(
        of: find.byKey(const Key('alarm-ring')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Every piece of the single screen, in reading order.
  List<Finder> ringParts({required bool silent, bool chosen = false}) => [
    find.byKey(const Key('alarm-ringing-label')),
    find.byKey(const Key('alarm-time')),
    find.text('Take pills'),
    if (silent)
      find.byKey(
        Key(chosen ? 'alarm-silent-declared' : 'alarm-silent-default'),
      ),
    if (silent) find.byKey(const Key('alarm-start-sound')),
    for (final k in snoozeKeys) find.byKey(Key(k)),
    find.byKey(const Key('alarm-acknowledge')),
    find.byKey(const Key('alarm-complete')),
    find.byKey(const Key('alarm-open')),
  ];

  void expectNoOverlap(WidgetTester tester, List<Finder> parts, String why) {
    final rects = [for (final f in parts) tester.getRect(f)];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final o = rects[i].intersect(rects[j]);
        expect(
          o.width <= 0.5 || o.height <= 0.5,
          isTrue,
          reason: '$why: ${parts[i]} overlaps ${parts[j]}',
        );
      }
    }
    // Natural order: nothing starts above the piece before it.
    for (var i = 1; i < rects.length; i++) {
      expect(
        rects[i].top,
        greaterThanOrEqualTo(rects[i - 1].top - 0.5),
        reason: '$why: ${parts[i]} is above ${parts[i - 1]}',
      );
    }
  }

  for (final silent in [true, false]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('at 360x640 with the silent hint the start-sound button and '
          'every action are visible or reachable and nothing overlaps '
          '(silent: $silent, text scale $scale)', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpSilentByChoice(
          tester,
          _SpyFeedback(),
          silent: silent,
          chosen: false,
        );
        final parts = ringParts(silent: silent);
        expectNoOverlap(tester, parts, '360x640 ×$scale');
        // One page scrolls, or nothing does: no region nested in the screen
        // that could hide a control under the actions.
        expect(
          find.descendant(
            of: find.byKey(const Key('alarm-ring')),
            matching: find.byType(Scrollable),
          ),
          findsOneWidget,
        );
        for (final part in parts) {
          await tester.scrollUntilVisible(part, 80, scrollable: ringPage());
          await tester.pump();
          final r = tester.getRect(part);
          expect(r.top, greaterThanOrEqualTo(0), reason: '$part ×$scale');
          expect(r.bottom, lessThanOrEqualTo(640), reason: '$part ×$scale $r');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a 360x640 screen without a hint keeps every action on screen '
      'with nothing to scroll', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSilentByChoice(tester, _SpyFeedback(), silent: false);
    final position = tester.state<ScrollableState>(ringPage()).position;
    expect(position.maxScrollExtent, 0);
    // The actions sit at the bottom: 640 − 16 bottom padding (the 48 pt
    // text button centred in its row).
    expect(rectOf(tester, 'alarm-open').bottom, closeTo(624, 4));
  });

  testWidgets('a screen taller than the window fades at its bottom edge, and '
      'not once it is scrolled to the end', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSilentByChoice(tester, _SpyFeedback(), silent: true);
    await tester.pump();
    final fade = tester.state<AlarmEdgeFadeState>(find.byType(AlarmEdgeFade));
    final position = tester.state<ScrollableState>(ringPage()).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(fade.fading, isTrue);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(fade.fading, isFalse);
  });

  // X-07 (OPH-466): the whole screen was one group labelled "Snooze" — the
  // section label had no node of its own and merged into the screen's. A
  // screen reader reads it in spec 1.8's order: label, time, title, "Snooze",
  // each tile as its own button, Acknowledge, Complete, Open.
  testWidgets('each tile is its own button for a screen reader with the time '
      'in its label', (tester) async {
    final semantics = tester.ensureSemantics();
    await seed();
    await pumpSized(tester, const Size(430, 932));

    for (final (key, spoken) in [
      ('alarm-snooze-5_min', 'Snooze 5 minutes'),
      ('alarm-snooze-30_min', 'Snooze 30 minutes'),
      ('alarm-snooze-1_hour', 'Snooze 1 hour'),
      ('alarm-snooze-tomorrow_morning', 'Snooze until tomorrow morning'),
    ]) {
      final tile = find.bySemanticsLabel(
        RegExp('^${RegExp.escape(spoken)}, rings at \\S+'),
      );
      expect(tile, findsOneWidget, reason: key);
      expect(
        tester.getSemantics(tile),
        isSemantics(isButton: true, hasTapAction: true),
        reason: key,
      );
      // The node is the tile, not a group around the screen.
      expect(
        tester.getSemantics(tile).rect.height,
        lessThanOrEqualTo(kAwAlarmTileHeight + 1),
      );
    }
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Silence indefinitely, '
          '${'alarm.silenceHint'.tr()}',
        ),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );

    // "Snooze" is a heading of its own, not the screen's name.
    final section = tester.getSemantics(find.bySemanticsLabel('Snooze'));
    expect(section, isSemantics(isHeader: true));
    expect(section.rect.height, lessThan(60));
    expect(section.childrenCount, 0);

    final order = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        if (node.label.isNotEmpty) node.label,
    ];
    int at(Pattern p) => order.indexWhere((l) => l.startsWith(p));
    final expected = [
      at('URGENT REMINDER'),
      at(RegExp(r'\d')),
      at('Take pills'),
      at('Snooze'),
      at('Snooze 5 minutes'),
      at('Snooze 30 minutes'),
      at('Snooze 1 hour'),
      at('Snooze until tomorrow'),
      at('Pick a time'),
      at('Silence indefinitely'),
      at('Acknowledge'),
      at('Complete'),
      at('Open'),
    ];
    expect(expected, everyElement(greaterThanOrEqualTo(0)), reason: '$order');
    expect(expected, orderedEquals([...expected]..sort()), reason: '$order');
    // No node reads the title and the actions as one.
    expect(
      order.where((l) => l.contains('Take pills') && l.contains('Snooze')),
      isEmpty,
    );
    semantics.dispose();
  });

  // Y-04 (OPH-466): a two-line title got a hover tooltip repeating it — it
  // covered the silent sentence, and its text was a second copy of the title
  // in the semantics tree. Only a title the screen actually cuts gets one, and
  // the tooltip never reaches a screen reader.
  AlarmInput titled(String title) => AlarmInput(
    reminderId: id('R1'),
    taskId: id('T1'),
    taskTitle: title,
    remindAt: at,
    status: 'scheduled',
    urgent: true,
    requiresAcknowledgement: true,
  );

  Future<void> hoverTitle(WidgetTester tester, String title) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text(title)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  int titleNodes(WidgetTester tester, String title) => [
    for (final node in tester.semantics.simulatedAccessibilityTraversal())
      if (node.label.contains(title)) node,
  ].length;

  testWidgets('a two-line title that fits gets no tooltip and is read once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // Two lines in the test font (each glyph as wide as it is tall).
    const title = 'Annemi ara ve ilacini sor';
    await seed();
    await pumpSized(tester, const Size(430, 932), alarm: titled(title));
    // Two lines at 430, inside the three the screen allows.
    final lines = tester
        .renderObject<RenderParagraph>(find.text(title))
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: title.length),
        )
        .map((b) => b.top)
        .toSet();
    expect(lines.length, 2);
    expect(
      find.ancestor(of: find.text(title), matching: find.byType(Tooltip)),
      findsNothing,
    );

    await hoverTitle(tester, title);
    // Nothing pops over the silent sentence, and the title is read once.
    expect(find.text(title), findsOneWidget);
    expect(titleNodes(tester, title), 1);
    semantics.dispose();
  });

  testWidgets('a title the screen cuts gets a tooltip a screen reader never '
      'reads', (tester) async {
    final semantics = tester.ensureSemantics();
    final title = List.filled(12, 'KDV beyannamesini gönder').join(' ');
    await seed();
    await pumpSized(tester, const Size(430, 932), alarm: titled(title));
    expect(
      tester.renderObject<RenderParagraph>(find.text(title)).didExceedMaxLines,
      isTrue,
    );
    expect(
      find.ancestor(of: find.text(title), matching: find.byType(Tooltip)),
      findsOneWidget,
    );

    await hoverTitle(tester, title);
    // The full title shows on hover…
    expect(find.text(title), findsNWidgets(2));
    // …and a screen reader still meets it once: the title node itself.
    expect(titleNodes(tester, title), 1);
    semantics.dispose();
  });

  testWidgets('a short screen still names the snooze section for a screen '
      'reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await seed();
    await pumpSized(tester, const Size(360, 640));
    expect(find.byKey(const Key('alarm-snooze-label')), findsNothing);
    final order = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        if (node.label.isNotEmpty) node.label,
    ];
    final section = order.indexOf('Snooze');
    expect(section, greaterThan(order.indexOf('Take pills')), reason: '$order');
    expect(
      section,
      lessThan(order.indexWhere((l) => l.startsWith('Snooze 5 minutes'))),
      reason: '$order',
    );
    semantics.dispose();
  });

  testWidgets('Turkish: the tile reads "5 dakika ertele, 09:05’te çalar"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => DateTime(2030, 6, 1, 9, 0, 50)),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    AwI18n.instance.setActiveCached(const Locale('tr'));
    addTearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));
    await seed();
    await pumpSized(tester, const Size(430, 932));
    expect(
      find.bySemanticsLabel('5 dakika ertele, 09:05’te çalar'),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tall screen pins the actions and fades nothing', (
    tester,
  ) async {
    await seed();
    await pumpSized(tester, const Size(430, 932));
    await tester.pump();
    final fade = tester.state<AlarmEdgeFadeState>(find.byType(AlarmEdgeFade));
    expect(fade.fading, isFalse);
    // Pinned to the bottom: 932 − 16 bottom padding.
    expect(rectOf(tester, 'alarm-open').bottom, moreOrLessEquals(916));
  });

  testWidgets('at text scale 2.0 on 360x640 every action is reached by '
      'scrolling the screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSilentByChoice(tester, _SpyFeedback(), silent: true);
    final page = find
        .descendant(
          of: find.byKey(const Key('alarm-ring')),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final k in [
      'alarm-start-sound',
      ...snoozeKeys,
      'alarm-acknowledge',
      'alarm-complete',
      'alarm-open',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(k)),
        100,
        scrollable: page,
      );
      final r = rectOf(tester, k);
      expect(r.top, greaterThanOrEqualTo(0), reason: k);
      expect(r.bottom, lessThanOrEqualTo(640), reason: '$k $r');
    }
    expect(tester.takeException(), isNull);
  });

  // W-09, spec §1.6: an answer says what it did, as the snooze does.
  testWidgets('acknowledge and complete confirm with a snackbar', (
    tester,
  ) async {
    await seed();
    await pumpRing(tester);
    await tester.tap(find.byKey(const Key('alarm-acknowledge')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.widgetWithText(SnackBar, 'Acknowledged'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));

    await tester.pumpWidget(const SizedBox());
    await pumpRing(tester);
    await tester.tap(find.byKey(const Key('alarm-complete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.widgetWithText(SnackBar, 'Completed'), findsOneWidget);
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id('T1')))).getSingle();
    expect(task.status, 'completed');
    await tester.pump(const Duration(seconds: 6));
  });

  // W-05: the header said 05:13 while the tiles said 5:18 AM.
  testWidgets('the ring header time uses the time format of the tiles', (
    tester,
  ) async {
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(),
        nowProvider.overrideWithValue(() => DateTime(2030, 6, 1, 9)),
      ],
    );
    addTearDown(container.dispose);
    db = container.read(databaseProvider);
    await seed();
    for (final format in ['iso', 'mdy_12h']) {
      await container.read(dateFormatProvider.notifier).set(format);
      await pumpRing(tester);
      final time = tester.widget<Text>(find.byKey(const Key('alarm-time')));
      expect(time.data, awFormatTime(at, format: format), reason: format);
      final tile = awFormatTime(DateTime(2030, 6, 1, 9, 5), format: format);
      expect(find.textContaining(tile), findsOneWidget, reason: format);
    }
    await container.read(dateFormatProvider.notifier).set(kAwSystemDateFormat);
  });

  // ── P2 polish: the list and the row sheet (OPH-443) ────────────────────

  /// The list of three with a clock the test moves.
  Future<List<NotificationEvent>> pumpListAt(
    WidgetTester tester,
    DateTime Function() clock, {
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final events = <NotificationEvent>[];
    await pumpLayer(
      tester,
      feed: [theAlarm(), secondAlarm(), thirdAlarm()],
      extra: [
        nowProvider.overrideWithValue(clock),
        alarmActionApplierProvider.overrideWithValue((event) async {
          events.add(event);
          return true;
        }),
      ],
    );
    return events;
  }

  Finder inTile(String key, String text) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.textContaining(text),
  );

  // W-03: "Tümünü ertele" said 5:24 at 05:20:03 and wrote 5:25.
  testWidgets('the bulk snooze tile follows the minute and equals what '
      'Tümünü ertele writes', (tester) async {
    var clock = DateTime(2030, 6, 1, 9, 0, 50);
    final events = await pumpListAt(tester, () => clock);
    String hm(int h, int m) =>
        awFormatTime(DateTime(2030, 6, 1, h, m), format: kAwSystemDateFormat);
    expect(inTile('alarm-all-snooze-5_min', hm(9, 5)), findsOneWidget);

    clock = DateTime(2030, 6, 1, 9, 1, 5);
    await tester.pump(const Duration(seconds: 15));
    expect(inTile('alarm-all-snooze-5_min', hm(9, 6)), findsOneWidget);

    clock = DateTime(2030, 6, 1, 9, 1, 40);
    await tester.tap(find.byKey(const Key('alarm-all-snooze-5_min')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final until = DateTime.fromMillisecondsSinceEpoch(events.single.untilMs!);
    expect((until.hour, until.minute), (9, 6));
    expect(find.textContaining(hm(9, 6)), findsWidgets);
    await settle(tester);
  });

  testWidgets('the row sheet\'s landing minutes follow the clock while it is '
      'open', (tester) async {
    var clock = DateTime(2030, 6, 1, 9, 0, 50);
    final events = await pumpListAt(tester, () => clock);
    String hm(int h, int m) =>
        awFormatTime(DateTime(2030, 6, 1, h, m), format: kAwSystemDateFormat);
    await tester.tap(find.byKey(Key('alarm-row-snooze-${id('T2')}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(inTile('alarm-sheet-snooze-5_min', hm(9, 5)), findsOneWidget);

    clock = DateTime(2030, 6, 1, 9, 1, 5);
    await tester.pump(const Duration(seconds: 15));
    expect(inTile('alarm-sheet-snooze-5_min', hm(9, 6)), findsOneWidget);

    await tester.tap(find.byKey(const Key('alarm-sheet-snooze-5_min')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final until = DateTime.fromMillisecondsSinceEpoch(events.single.untilMs!);
    expect((until.hour, until.minute), (9, 6));
    await settle(tester);
  });

  // W-13 + W-05: the count in the urgent ink, the time in the page's ink and
  // in the user's format.
  testWidgets('the list header: count in the urgent ink, time onSurface', (
    tester,
  ) async {
    await pumpList(tester);
    final context = tester.element(find.byKey(const Key('alarm-ring-list')));
    final tokens = context.awTokens;
    final scheme = Theme.of(context).colorScheme;
    final header = tester.widget<Text>(
      find.byKey(const Key('alarm-list-header-text')),
    );
    final spans = (header.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, '3 URGENT REMINDERS');
    expect(spans.first.style!.color, tokens.errorOnPage);
    expect(spans.last.text, ' · ${_clock(tester, at)}');
    expect(spans.last.style!.color, scheme.onSurface);
    await settle(tester);
  });

  testWidgets('the list header time follows the user\'s time format', (
    tester,
  ) async {
    await pumpList(tester);
    await container.read(dateFormatProvider.notifier).set('iso');
    await tester.pump();
    final header = tester.widget<Text>(
      find.byKey(const Key('alarm-list-header-text')),
    );
    expect(
      header.textSpan!.toPlainText(),
      endsWith(' · ${awFormatTime(at, format: 'iso')}'),
    );
    final card = find.descendant(
      of: find.byKey(Key('alarm-row-${id('T1')}')),
      matching: find.text(awFormatTime(at, format: 'iso')),
    );
    expect(card, findsOneWidget);
    await container.read(dateFormatProvider.notifier).set(kAwSystemDateFormat);
    await settle(tester);
  });

  testWidgets('the list keeps the single layout\'s 24 pt side margins', (
    tester,
  ) async {
    await pumpList(tester, size: const Size(360, 640));
    final card = rectOf(tester, 'alarm-row-${id('T1')}');
    expect(card.left, AwSpace.x6);
    expect(card.right, 360 - AwSpace.x6);
    final ack = rectOf(tester, 'alarm-acknowledge-all');
    expect(ack.left, AwSpace.x6);
    expect(ack.right, 360 - AwSpace.x6);
    await settle(tester);
  });

  testWidgets('on a wide screen the list is the single layout\'s centred '
      'column', (tester) async {
    await pumpList(tester, size: const Size(1280, 800));
    final ack = rectOf(tester, 'alarm-acknowledge-all');
    expect(ack.width, kAlarmRingMaxWidth);
    expect(ack.center.dx, 640);
    final header = rectOf(tester, 'alarm-list-header');
    // Centred vertically: the space above the header and below the
    // answers is the same, not a header stuck to the top.
    final above = header.top;
    final below = 800 - ack.bottom;
    expect(above, greaterThan(AwSpace.x8));
    expect((above - below).abs(), lessThanOrEqualTo(1));
    await settle(tester);
  });

  // W-15: a card cut by the edge fades; the end of the list does not.
  testWidgets('the rows fade at their bottom edge while more lie below', (
    tester,
  ) async {
    await pumpList(tester, size: const Size(360, 640));
    await tester.pump();
    final rows = find.byKey(const Key('alarm-ring-rows'));
    final fade = tester.state<AlarmEdgeFadeState>(
      find.ancestor(of: rows, matching: find.byType(AlarmEdgeFade)),
    );
    expect(fade.fading, isTrue);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: rows, matching: find.byType(Scrollable)).first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(fade.fading, isFalse);
    await settle(tester);
  });

  testWidgets('two rows that fit are not faded', (tester) async {
    await pumpList(
      tester,
      feed: [theAlarm(), secondAlarm()],
      size: const Size(430, 932),
    );
    await tester.pump();
    final fade = tester.state<AlarmEdgeFadeState>(
      find.ancestor(
        of: find.byKey(const Key('alarm-ring-rows')),
        matching: find.byType(AlarmEdgeFade),
      ),
    );
    expect(fade.fading, isFalse);
    await settle(tester);
  });
}

/// [when] as the ring screen prints it: the user's time format (W-05),
/// the system default in these tests, local time.
String _clock(WidgetTester tester, DateTime when) =>
    awFormatTime(when.toLocal(), format: kAwSystemDateFormat);

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

/// A task store whose snooze lands only when the test says so (OPH-466).
class _SlowTaskStore extends TaskStore {
  _SlowTaskStore(AwDatabase db, this.landed) : super(db, () {});

  final Future<void> landed;

  @override
  Future<void> snooze(
    String taskId, {
    String? preset,
    DateTime? until,
    String? receiptId,
  }) => landed;
}

/// A reminder store whose acknowledge is the test's to decide.
class _RecordingReminderStore extends ReminderStore {
  _RecordingReminderStore(AwDatabase db, this.onWrite) : super(db, () {});

  final void Function(String what) onWrite;

  @override
  Future<void> acknowledge(String reminderId, {String? receiptId}) async =>
      onWrite('acknowledge');
}
