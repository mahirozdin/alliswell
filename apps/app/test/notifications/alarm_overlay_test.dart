import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../support/fake_notifications.dart';
import '../support/sync_overrides.dart';

const wsId = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String p) => p.padRight(26, '0');

AlarmInput alarm({
  String rid = 'R1',
  bool urgent = true,
  required DateTime remindAt,
  String status = 'scheduled',
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: rid,
  taskId: 'T-$rid',
  taskTitle: 'Task $rid',
  remindAt: remindAt,
  status: status,
  urgent: urgent,
  requiresAcknowledgement: urgent,
  snoozedUntil: snoozedUntil,
);

void main() {
  final now = DateTime.utc(2030, 6, 1, 12);

  group('ringingAlarm (pure — the DoD fake clock is just `now`)', () {
    test('nothing rings when there are no alarms', () {
      expect(ringingAlarm(const [], now), isNull);
    });

    test('a non-urgent due alarm never takes over the screen', () {
      final a = alarm(
        urgent: false,
        remindAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(ringingAlarm([a], now), isNull);
    });

    test('an urgent alarm rings once its fire time has arrived', () {
      final a = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
      expect(ringingAlarm([a], now)?.reminderId, 'R1');
    });

    test('an urgent alarm still in the future does not ring', () {
      final a = alarm(remindAt: now.add(const Duration(minutes: 1)));
      expect(ringingAlarm([a], now), isNull);
    });

    test('the earliest-due urgent alarm wins when several are due', () {
      final older = alarm(
        rid: 'R1',
        remindAt: now.subtract(const Duration(minutes: 10)),
      );
      final newer = alarm(
        rid: 'R2',
        remindAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(ringingAlarm([newer, older], now)?.reminderId, 'R1');
    });

    test('a snooze pushes the fire out, then rings again when it elapses', () {
      final a = alarm(
        remindAt: now.subtract(const Duration(hours: 1)),
        status: 'snoozed',
        snoozedUntil: now.add(const Duration(minutes: 5)),
      );
      expect(ringingAlarm([a], now), isNull);
      expect(
        ringingAlarm([a], now.add(const Duration(minutes: 6)))?.reminderId,
        'R1',
      );
    });
  });

  // ── Round 19 #2 ─────────────────────────────────────────────────────────
  //
  // "When I open the app a long-gone alarm suddenly goes off in red — but its
  // time is long past." `ringingAlarm` had no lower bound, so an alarm from
  // Tuesday still counted as ringing on Friday: it seized the screen, sounded
  // the bed, and made a device whose alarms had STOPPED working look like they
  // finally had.
  group('the staleness window', () {
    test('an alarm that just came due still rings', () {
      final a = alarm(remindAt: now.subtract(const Duration(minutes: 5)));
      expect(ringingAlarm([a], now)?.reminderId, 'R1');
      expect(missedAlarms([a], now), isEmpty);
    });

    test('an alarm from three days ago does NOT ring', () {
      final a = alarm(remindAt: now.subtract(const Duration(days: 3)));
      expect(ringingAlarm([a], now), isNull);
    });

    test('…but a recent one is not forgotten either', () {
      // Swallowing it would trade one wrong behaviour for another: the user
      // still needs to know last night's alarm went unanswered.
      final a = alarm(remindAt: now.subtract(const Duration(hours: 8)));
      expect(missedAlarms([a], now).single.reminderId, 'R1');
    });

    test('a task overdue for a week is the LIST\'s job, not a card', () {
      // Found by `tasks_flow_test`, not by reasoning: without this bound an
      // urgent task overdue since March showed a "missed alarm" card forever.
      final a = alarm(remindAt: now.subtract(const Duration(days: 7)));
      expect(ringingAlarm([a], now), isNull);
      expect(missedAlarms([a], now), isEmpty);
    });

    test('missed alarms come back newest first', () {
      final old = alarm(
        rid: 'R1',
        remindAt: now.subtract(const Duration(hours: 20)),
      );
      final recent = alarm(
        rid: 'R2',
        remindAt: now.subtract(const Duration(hours: 2)),
      );
      expect(missedAlarms([old, recent], now).map((a) => a.reminderId), [
        'R2',
        'R1',
      ]);
    });

    test('a non-urgent alarm is never "missed" — it lives in the tray', () {
      final a = alarm(
        urgent: false,
        remindAt: now.subtract(const Duration(hours: 8)),
      );
      expect(missedAlarms([a], now), isEmpty);
    });

    // The window is derived from the chain, not fixed: an `insistent` profile
    // re-alerts up to 40 minutes out, and a flat 15-minute window would call an
    // alarm "missed" while the OS was still ringing it.
    test('the window follows the user\'s own re-alert chain', () {
      const insistent = ReminderProfile(
        slots: [0, 1, 2, 3, 5, 8, 12, 17, 25, 40],
      );
      final window = alarmStaleWindowFor(insistent);
      expect(window, const Duration(minutes: 45));

      final a = alarm(remindAt: now.subtract(const Duration(minutes: 35)));
      expect(
        ringingAlarm([a], now, staleAfter: window)?.reminderId,
        'R1',
        reason: 'the chain is still ringing this one',
      );
    });

    test('a calm chain still gets a floor, not a 5-minute window', () {
      // `calm` is a single slot at +0. Without a floor the window would be five
      // minutes, and a phone picked up six minutes late would show nothing.
      expect(
        alarmStaleWindowFor(const ReminderProfile(slots: [0])),
        const Duration(minutes: 15),
      );
    });
  });

  group('nextUrgentFireAfter (pure)', () {
    test('returns the soonest future urgent fire', () {
      final soon = alarm(
        rid: 'R1',
        remindAt: now.add(const Duration(minutes: 5)),
      );
      final later = alarm(
        rid: 'R2',
        remindAt: now.add(const Duration(minutes: 30)),
      );
      final nonUrgent = alarm(
        rid: 'R3',
        urgent: false,
        remindAt: now.add(const Duration(minutes: 1)),
      );
      expect(
        nextUrgentFireAfter([later, soon, nonUrgent], now),
        now.add(const Duration(minutes: 5)),
      );
    });

    test('ignores past fires and returns null when none remain', () {
      final past = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
      expect(nextUrgentFireAfter([past], now), isNull);
    });
  });

  group('AlarmOverlayController (gate + wiring)', () {
    late ProviderContainer container;

    Future<void> boot({required bool autoShow}) async {
      container = ProviderContainer(
        overrides: [
          ...syncTestOverrides(alarmOverlayAutoShow: autoShow),
          // The world the alarm feed reads its scope from (EE-296): who is
          // signed in, and the one workspace they own.
          currentUserIdProvider.overrideWithValue('U1'),
          workspacesProvider.overrideWith(
            (ref) async => const [
              WorkspaceSummary(
                id: wsId,
                name: 'Personal',
                slug: 'personal',
                colorRgb: '#2563EB',
                role: 'owner',
                owned: true,
              ),
            ],
          ),
          currentWorkspaceProvider.overrideWithValue(
            const AsyncData<WorkspaceSummary?>(
              WorkspaceSummary(
                id: wsId,
                name: 'Personal',
                slug: 'personal',
                colorRgb: '#2563EB',
                role: 'owner',
              ),
            ),
          ),
          alarmClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final db = container.read(databaseProvider);
      // An urgent task one minute past its due time → a due synthetic alarm.
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
              dueAt: Value(now.subtract(const Duration(minutes: 1))),
            ),
          );
      // Pin the autoDispose feed so it can't dispose mid-load in the gate case
      // (where the controller returns early and never watches it).
      container.listen(alarmFeedProvider, (_, _) {});
      container.listen(alarmOverlayControllerProvider, (_, _) {});
      await container.read(alarmFeedProvider.future);
    }

    test('rings a due urgent alarm when auto-show is on', () async {
      await boot(autoShow: true);
      final ringing = container
          .read(alarmOverlayControllerProvider)
          .ringing
          .single;
      expect(ringing.taskId, id('T1'));
      expect(ringing.urgent, isTrue);
    });

    test(
      'the gate keeps the overlay off (tests default OFF, OPH-111)',
      () async {
        await boot(autoShow: false);
        expect(container.read(alarmOverlayControllerProvider).ringing, isEmpty);
      },
    );
  });

  // ── #46 iOS 26+ leg / OPH-428: the view the overlay reads ────────────────
  group('AlarmKitViewHost (the scheduler\'s AlarmKit lane, watched)', () {
    AlarmKitAlarm akAlarm(String taskId, DateTime at) => AlarmKitAlarm(
      id: alarmKitOccurrenceId([taskId], alarmKitFireAtMs(at)),
      members: [taskId],
      fp: 1,
      title: 't',
      body: 'b',
      fireAt: at,
      taskId: taskId,
      reminderId: 'R-$taskId',
    );

    test(
      'follows what the scheduler read, scheduled, cancelled and stopped',
      () async {
        final inner = FakeAlarmKitHost();
        final views = <List<AlarmKitScheduled>>[];
        final host = AlarmKitViewHost(inner, onView: views.add);
        final a = akAlarm('T1', now);
        final b = akAlarm('T2', now.add(const Duration(minutes: 5)));
        inner.foreign[9] = const AlarmKitScheduled(id: 9, members: ['T9']);

        await host.scheduledAlarms();
        expect(views.last.map((r) => r.id), [9]);

        await host.schedule(a);
        await host.schedule(b);
        final row = views.last.firstWhere((r) => r.id == a.id);
        expect(row.members, ['T1']);
        expect(row.fireAtMs, alarmKitFireAtMs(now));
        expect(
          alarmKitCovering(
            views.last,
            AlarmInput(
              reminderId: 'R-T1',
              taskId: 'T1',
              taskTitle: 't',
              remindAt: now,
              status: 'scheduled',
              urgent: true,
              requiresAcknowledgement: true,
            ),
          ).single.id,
          a.id,
        );

        await host.cancel(b.id);
        await host.stop(9);
        expect(views.last.map((r) => r.id), [a.id]);

        // A refused schedule is not on the OS, so it covers nothing.
        inner.scheduleFailure = 'limit_reached';
        await host.schedule(akAlarm('T3', now));
        expect(views.last.map((r) => r.id), [a.id]);

        // The permission went away: nothing rings as a system alert any more.
        inner.authorized = false;
        expect(await host.isAuthorized(), isFalse);
        expect(views.last, isEmpty);
      },
    );
  });

  // ── #46 / OPH-423: occurrences, and one owner for the sound ───────────────
  group('AlarmOverlayController (#46)', () {
    late List<String> log;
    late DateTime clock;
    late StreamController<List<AlarmInput>> feed;
    late ProviderContainer container;

    ProviderContainer boot({
      List<Override> extra = const [],
      AlarmKitHost? alarmKitHost,
    }) {
      log = [];
      clock = now;
      feed = StreamController<List<AlarmInput>>();
      container = ProviderContainer(
        overrides: [
          ...syncTestOverrides(
            alarmOverlayAutoShow: true,
            alarmFeedback: _LogFeedback(log),
            alarmKitHost: alarmKitHost,
          ),
          alarmFeedProvider.overrideWith((ref) => feed.stream),
          alarmClockProvider.overrideWithValue(() => clock),
          ...extra,
        ],
      );
      addTearDown(() async {
        container.dispose();
        await feed.close();
      });
      container.listen(alarmOverlayControllerProvider, (_, _) {});
      return container;
    }

    AlarmOverlayState overlay() =>
        container.read(alarmOverlayControllerProvider);
    AlarmOverlayController controller() =>
        container.read(alarmOverlayControllerProvider.notifier);

    testWidgets(
      'a snoozed alarm rings again at snoozedUntil in the same session',
      (tester) async {
        boot();
        final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
        feed.add([due]);
        await tester.pump();
        expect(overlay().ringing.single.reminderId, 'R1');

        controller().handled(due);
        expect(overlay().ringing, isEmpty);
        // The snooze lands: the same reminder, a new instant five minutes out.
        final snoozed = alarm(
          remindAt: due.remindAt,
          status: 'snoozed',
          snoozedUntil: now.add(const Duration(minutes: 5)),
        );
        feed.add([snoozed]);
        await tester.pump();
        expect(overlay().ringing, isEmpty);

        // The foreground timer wheel brings it back on time — the old
        // reminder-keyed "handled" set kept it quiet until the app restarted.
        clock = now.add(const Duration(minutes: 5));
        await tester.pump(const Duration(minutes: 5));
        expect(overlay().ringing.single.reminderId, 'R1');
        expect(_squash(log), ['start', 'stop', 'start']);
      },
    );

    testWidgets(
      'a device that does not ring urgent alarms never opens the ring screen',
      (tester) async {
        // OPH-452 (#48): off, and unknown (a fresh sign-in before the server
        // answered), leave the alarm to the OS as an ordinary notification.
        final kv = _MemoryKv()..values[kRingsUrgentKey] = 'off';
        boot(
          extra: [
            ringsUrgentStoreProvider.overrideWithValue(
              RingsUrgentStore(kv: kv),
            ),
          ],
        );
        final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
        feed.add([due]);
        await container.read(ringsUrgentHereProvider.future);
        await tester.pump();
        expect(overlay().ringing, isEmpty);
        expect(log, isEmpty);

        kv.values[kRingsUrgentKey] = 'unknown';
        container.invalidate(ringsUrgentHereProvider);
        await container.read(ringsUrgentHereProvider.future);
        await tester.pump();
        expect(overlay().ringing, isEmpty);
        expect(log, isEmpty);

        // The person switches this device on: the screen opens without a
        // restart.
        kv.values[kRingsUrgentKey] = 'on';
        container.invalidate(ringsUrgentHereProvider);
        await container.read(ringsUrgentHereProvider.future);
        await tester.pump();
        expect(overlay().ringing.single.reminderId, 'R1');
        expect(log, contains('start'));

        controller().handled(due);
        await tester.pump();
        expect(overlay().ringing, isEmpty);
        await tester.pump(const Duration(minutes: 2));
      },
    );

    testWidgets(
      'swapping the ringing alarm never stops the sound it just started',
      (tester) async {
        final first = alarm(
          rid: 'R1',
          remindAt: now.subtract(const Duration(minutes: 1)),
        );
        final second = alarm(
          rid: 'R2',
          remindAt: now.subtract(const Duration(seconds: 40)),
        );
        boot(
          extra: [
            reminderStoreProvider.overrideWith(
              (ref) => _NoopReminderStore(ref.watch(databaseProvider)),
            ),
          ],
        );
        feed.add([first, second]);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(extensions: const [AwTokens.light]),
              home: const Scaffold(body: AlarmOverlayLayer()),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Task R1'), findsOneWidget);
        expect(log, ['start']);

        // Two tasks ring as one list (#47, OPH-443): answer the first row.
        await tester.tap(find.byKey(const Key('alarm-row-ack-T-R1')));
        // Several frames: the list is torn down after the single layout
        // mounted — the moment a dispose() used to stop the shared player.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Task R2'), findsOneWidget);
        // #47 / decisions §3.1: the first action silences the whole list;
        // the next member shows without a second start…
        expect(_squash(log), ['start', 'stop']);
        expect(controller().sounding, isFalse);
        // …and its sound comes back after a minute nobody touched it.
        await tester.pump(kAlarmResumeAfter);
        expect(_squash(log), ['start', 'stop', 'start']);
        expect(controller().sounding, isTrue);
      },
    );

    test('a failed write re-shows the alarm silently with the error', () async {
      boot();
      final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
      feed.add([due]);
      await pumpEventQueue();
      expect(log, ['start']);

      // The screen's order: silence, dismiss, then the write.
      controller().silence();
      controller().handled(due);
      expect(overlay().ringing, isEmpty);
      final saved = await controller().commit(
        due,
        AlarmPendingAction(() async => throw StateError('database is locked')),
      );

      expect(saved, isFalse);
      expect(overlay().ringing.single.reminderId, 'R1');
      expect(overlay().isFailed(due), isTrue);
      expect(controller().failedAction(due), isNotNull);
      // Silent: only the no-interaction rule may bring its sound back.
      expect(_squash(log), ['start', 'stop']);
      expect(controller().sounding, isFalse);

      // A feed emission does not restart it either.
      feed.add([due]);
      await pumpEventQueue();
      expect(overlay().isFailed(due), isTrue);
      expect(_squash(log), ['start', 'stop']);

      // Tekrar dene: it stays out of the handled set only until this lands.
      var confirmed = false;
      controller().handled(due);
      final retried = await controller().commit(
        due,
        AlarmPendingAction(() async {}, onSaved: () => confirmed = true),
      );
      expect(retried, isTrue);
      expect(confirmed, isTrue);
      expect(overlay().ringing, isEmpty);
      expect(controller().failedAction(due), isNull);
    });

    // ── #46 iOS 26+ leg / OPH-428: the AlarmKit alert and the ring screen ──

    /// The AlarmKit record that rings [a]'s occurrence, as the scheduler last
    /// saw it.
    AlarmKitScheduled covering(
      AlarmInput a, {
      int id = 4242,
      AlarmKitAlarmState state = AlarmKitAlarmState.alerting,
      Duration shift = Duration.zero,
    }) => AlarmKitScheduled(
      id: id,
      state: state,
      members: [a.taskId],
      fireAtMs: alarmKitFireAtMs(alarmFireAt(a).add(shift)),
    );

    Future<void> pumpOverlay(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [AwTokens.light]),
            home: const Scaffold(body: AlarmOverlayLayer()),
          ),
        ),
      );
      await tester.pump();
    }

    List<Override> quietStores() => [
      taskStoreProvider.overrideWith(
        (ref) => _NoopTaskStore(ref.watch(databaseProvider)),
      ),
      reminderStoreProvider.overrideWith(
        (ref) => _NoopReminderStore(ref.watch(databaseProvider)),
      ),
    ];

    testWidgets(
      'an in-app snooze stops the alerting AlarmKit alarm of that occurrence',
      (tester) async {
        final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
        final host = FakeAlarmKitHost();
        boot(
          alarmKitHost: host,
          extra: [
            ...quietStores(),
            alarmKitViewProvider.overrideWith(
              () => AlarmKitView([covering(due)]),
            ),
          ],
        );
        feed.add([due]);
        await pumpOverlay(tester);

        // The system alert is the sound: the screen shows, the app is quiet.
        expect(overlay().ringing.single.reminderId, 'R1');
        expect(overlay().silentHere, isTrue);
        expect(overlay().ringsOnLockScreen, isTrue);
        expect(log, isEmpty);

        await tester.ensureVisible(find.byKey(const Key('alarm-snooze-5_min')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('alarm-snooze-5_min')));
        // Stopped inside the tap, with the dismissal — not after the write.
        expect(host.stopped, [4242]);
        expect(overlay().ringing, isEmpty);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('alarm-ring')), findsNothing);
        expect(host.stopped, [4242], reason: 'stopped once');
        expect(log.where((e) => e == 'start'), isEmpty);
        expect(container.read(alarmKitViewProvider), isEmpty);
      },
    );

    testWidgets('every in-app action stops the covering AlarmKit alarm', (
      tester,
    ) async {
      const actions = [
        'alarm-snooze-30_min',
        'alarm-snooze-1_hour',
        'alarm-snooze-tomorrow_morning',
        'alarm-silence',
        'alarm-acknowledge',
        'alarm-complete',
      ];
      for (final action in actions) {
        final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
        final host = FakeAlarmKitHost();
        await tester.pumpWidget(const SizedBox());
        boot(
          alarmKitHost: host,
          extra: [
            ...quietStores(),
            alarmKitViewProvider.overrideWith(
              () => AlarmKitView([covering(due)]),
            ),
          ],
        );
        feed.add([due]);
        await pumpOverlay(tester);
        await tester.ensureVisible(find.byKey(Key(action)));
        await tester.pump();
        await tester.tap(find.byKey(Key(action)));
        expect(host.stopped, [4242], reason: action);
        expect(overlay().ringing, isEmpty, reason: action);
        await tester.pump();
        expect(log.where((e) => e == 'start'), isEmpty, reason: action);
        // The snackbars and button feedback of the action run out.
        await tester.pump(const Duration(seconds: 6));
      }
    });

    testWidgets(
      'a failed AlarmKit stop is logged and never keeps the screen open',
      (tester) async {
        final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
        final host = _ThrowingStopHost();
        boot(
          alarmKitHost: host,
          extra: [
            ...quietStores(),
            alarmKitViewProvider.overrideWith(
              () => AlarmKitView([covering(due)]),
            ),
          ],
        );
        feed.add([due]);
        await pumpOverlay(tester);

        await tester.tap(find.byKey(const Key('alarm-acknowledge')));
        expect(overlay().ringing, isEmpty);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('alarm-ring')), findsNothing);
        expect(log.where((e) => e == 'start'), isEmpty);
        expect(controller().sounding, isFalse);

        final rows = await tester.runAsync(
          () => container.read(alarmLogProvider).recent(),
        );
        final degraded = rows!.where(
          (r) =>
              r.event == AlarmLogEvent.degraded &&
              r.lane == AlarmLogLane.alarmkit,
        );
        expect(degraded, hasLength(1));
        expect(degraded.single.detail, contains('stop'));
      },
    );

    testWidgets('without AlarmKit the in-app sound path is unchanged', (
      tester,
    ) async {
      final due = alarm(remindAt: now.subtract(const Duration(minutes: 1)));
      final host = FakeAlarmKitHost(supported: false, authorized: false);
      boot(
        alarmKitHost: host,
        extra: [
          ...quietStores(),
          // A record for the same task at ANOTHER instant covers nothing.
          alarmKitViewProvider.overrideWith(
            () => AlarmKitView([
              covering(due, shift: const Duration(minutes: 5)),
            ]),
          ),
        ],
      );
      feed.add([due]);
      await pumpOverlay(tester);

      expect(overlay().silentHere, isFalse);
      expect(overlay().ringsOnLockScreen, isFalse);
      expect(log, ['start']);
      expect(find.byKey(const Key('alarm-rings-on-lock-screen')), findsNothing);

      await tester.tap(find.byKey(const Key('alarm-acknowledge')));
      await tester.pump();
      expect(_squash(log), ['start', 'stop']);
      expect(host.stopped, isEmpty);
      expect(overlay().ringing, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
      'a stopped grouped alarm leaves its other member ringing in the app',
      (tester) async {
        final first = alarm(
          rid: 'R1',
          remindAt: now.subtract(const Duration(minutes: 1)),
        );
        final second = alarm(
          rid: 'R2',
          remindAt: now.subtract(const Duration(minutes: 1)),
        );
        final host = FakeAlarmKitHost();
        boot(
          alarmKitHost: host,
          extra: [
            ...quietStores(),
            alarmKitViewProvider.overrideWith(
              () => AlarmKitView([
                AlarmKitScheduled(
                  id: 7,
                  state: AlarmKitAlarmState.alerting,
                  members: [first.taskId, second.taskId],
                  fireAtMs: alarmKitFireAtMs(alarmFireAt(first)),
                ),
              ]),
            ),
          ],
        );
        feed.add([first, second]);
        await pumpOverlay(tester);
        expect(log, isEmpty);

        // The list's first row (#47, OPH-443).
        await tester.tap(find.byKey(const Key('alarm-row-ack-T-R1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(host.stopped, [7]);
        expect(find.text('Task R2'), findsOneWidget);
        expect(overlay().ringsOnLockScreen, isFalse);
        // #47: the action silenced the list; the system alert is gone, so a
        // minute without interaction brings the in-app sound back — never
        // the AlarmKit alert.
        expect(log, isEmpty);
        await tester.pump(kAlarmResumeAfter);
        expect(_squash(log), ['start']);
        expect(host.stopped, [7]);
        expect(host.scheduled, isEmpty);
        await tester.pump(const Duration(seconds: 6));
      },
    );

    test(
      'a silent-here device shows the alarm without starting the sound',
      () async {
        boot(extra: [alarmOpensSilentProvider.overrideWithValue(true)]);
        feed.add([alarm(remindAt: now.subtract(const Duration(minutes: 1)))]);
        await pumpEventQueue();
        expect(overlay().ringing, hasLength(1));
        expect(overlay().silentHere, isTrue);
        expect(log, isEmpty);
        controller().startSound();
        expect(log, ['start']);
      },
    );
  });

  // ── #47 / OPH-441: every alarm ringing in the minute, one screen ─────────
  group('AlarmOverlayController ring list (#47)', () {
    late List<String> log;
    late DateTime clock;
    late StreamController<List<AlarmInput>> feed;
    late ProviderContainer container;
    late List<NotificationEvent> events;

    ProviderContainer boot({
      List<Override> extra = const [],
      AlarmKitHost? alarmKitHost,
      NotificationsGateway? gateway,
      bool recordEvents = true,
    }) {
      log = [];
      events = [];
      clock = now;
      feed = StreamController<List<AlarmInput>>();
      container = ProviderContainer(
        overrides: [
          ...syncTestOverrides(
            alarmOverlayAutoShow: true,
            alarmFeedback: _LogFeedback(log),
            alarmKitHost: alarmKitHost,
            notificationsGateway: gateway,
          ),
          alarmFeedProvider.overrideWith((ref) => feed.stream),
          alarmClockProvider.overrideWithValue(() => clock),
          if (recordEvents)
            alarmActionApplierProvider.overrideWithValue((event) async {
              events.add(event);
              return true;
            }),
          ...extra,
        ],
      );
      addTearDown(() async {
        container.dispose();
        await feed.close();
      });
      container.listen(alarmOverlayControllerProvider, (_, _) {});
      return container;
    }

    // A feed emission reaches the controller through Riverpod's scheduler,
    // a zero timer of its own.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    AlarmOverlayState overlay() =>
        container.read(alarmOverlayControllerProvider);
    AlarmOverlayController controller() =>
        container.read(alarmOverlayControllerProvider.notifier);

    // 11:59:00Z, 11:59:20Z and 11:59:40Z: one UTC minute. R2 is older data
    // (a snooze that landed in this minute), R3 came from another device.
    List<AlarmInput> minute() => [
      alarm(rid: 'R1', remindAt: now.subtract(const Duration(seconds: 60))),
      alarm(
        rid: 'R2',
        remindAt: now.subtract(const Duration(hours: 2)),
        status: 'snoozed',
        snoozedUntil: now.subtract(const Duration(seconds: 40)),
      ),
      alarm(rid: 'R3', remindAt: now.subtract(const Duration(seconds: 20))),
    ];

    // OPH-445 (#48 gap A): the sync closed the screen, but the Android
    // notification it came from kept looping its sound until cancelled.
    test(
      'closing the overlay because the alarm was handled elsewhere cancels its OS notification',
      () async {
        final gateway = FakeNotificationsGateway();
        gateway.active[41] = const ActiveAlarmNotification(
          id: 41,
          urgent: true,
          reminderIds: ['R1'],
        );
        gateway.active[42] = const ActiveAlarmNotification(
          id: 42,
          urgent: true,
          reminderIds: ['R3'],
        );
        boot(gateway: gateway);
        final r1 = alarm(
          rid: 'R1',
          remindAt: now.subtract(const Duration(seconds: 60)),
        );
        final r3 = alarm(
          rid: 'R3',
          remindAt: now.subtract(const Duration(seconds: 20)),
        );
        feed.add([r1, r3]);
        await pumpEventQueue();
        expect(overlay().ringing, hasLength(2));
        expect(gateway.cancelled, isEmpty);

        // R1 was acknowledged on another device: its row leaves, R3 still
        // rings and keeps its notification.
        feed.add([r3]);
        await pumpEventQueue();
        expect(gateway.cancelled, [41]);

        // R3 too: the screen closes and the last notification goes with it.
        feed.add(const []);
        await pumpEventQueue();
        expect(overlay().ringing, isEmpty);
        expect(gateway.cancelled, [41, 42]);
        expect(gateway.active, isEmpty);
      },
    );

    // #47 / decisions §3.1: the first action silences the list — the
    // Android notification looping for the minute included, though another
    // of its members still rings in the app.
    test(
      'a local row action cancels the shown notification ringing the list',
      () async {
        final gateway = FakeNotificationsGateway();
        gateway.active[50] = const ActiveAlarmNotification(
          id: 50,
          urgent: true,
          reminderIds: ['R1', 'R3'],
          taskIds: ['T-R1', 'T-R3'],
        );
        // An ordinary reminder of the same task is not the alarm's sound.
        gateway.active[51] = const ActiveAlarmNotification(
          id: 51,
          urgent: false,
          reminderIds: ['R1'],
        );
        boot(gateway: gateway);
        final r1 = alarm(
          rid: 'R1',
          remindAt: now.subtract(const Duration(seconds: 60)),
        );
        final r3 = alarm(
          rid: 'R3',
          remindAt: now.subtract(const Duration(seconds: 20)),
        );
        feed.add([r1, r3]);
        await pumpEventQueue();
        expect(overlay().ringing, hasLength(2));

        expect(
          await controller().actOnRow('T-R1', AlarmRowAction.acknowledge),
          isTrue,
        );
        await pumpEventQueue();
        expect(overlay().ringing.single.reminderId, 'R3');
        expect(gateway.cancelled, [50]);
        expect(gateway.active.keys, [51]);
      },
    );

    test(
      'three urgent alarms in one minute ring as one screen listing all three',
      () async {
        boot();
        feed.add(minute().reversed.toList());
        await pumpEventQueue();

        // Earliest first, every one of them, one sound for the list.
        expect(overlay().ringing.map((a) => a.reminderId), ['R1', 'R2', 'R3']);
        expect(log, ['start']);
        expect(controller().sounding, isTrue);

        // The pure rule the controller uses agrees.
        expect(ringingAlarms(minute(), now).map((a) => a.reminderId), [
          'R1',
          'R2',
          'R3',
        ]);
        expect(ringingAlarm(minute(), now)?.reminderId, 'R1');
      },
    );

    testWidgets(
      'the first row action silences once and the screen stays for the rest',
      (tester) async {
        final rows = minute();
        final host = FakeAlarmKitHost();
        boot(
          alarmKitHost: host,
          extra: [
            alarmKitViewProvider.overrideWith(
              () => AlarmKitView([
                AlarmKitScheduled(
                  id: 7,
                  state: AlarmKitAlarmState.alerting,
                  members: [for (final r in rows) r.taskId],
                  fireAtMs: alarmKitFireAtMs(alarmFireAt(rows.first)),
                ),
              ]),
            ),
          ],
        );
        feed.add(rows);
        await settle(tester);
        // R1's occurrence rings on the system alert: the app adds no sound.
        expect(overlay().ringing, hasLength(3));
        expect(overlay().ringsOnLockScreen, isTrue);
        expect(log, isEmpty);

        final saved = controller().actOnRow('T-R1', AlarmRowAction.acknowledge);
        // Inside the call: the alert is stopped and the row is gone.
        expect(host.stopped, [7]);
        expect(overlay().ringing.map((a) => a.reminderId), ['R2', 'R3']);
        expect(await saved, isTrue);

        await tester.pump();
        expect(overlay().ringsOnLockScreen, isFalse);
        expect(overlay().silentHere, isFalse);
        expect(controller().sounding, isFalse);
        expect(log.where((e) => e == 'start'), isEmpty);

        // The second row: no second stop, no sound, the last row stays.
        await controller().actOnRow(
          'T-R2',
          AlarmRowAction.snooze(now.add(const Duration(minutes: 5))),
        );
        expect(host.stopped, [7]);
        expect(overlay().ringing.single.reminderId, 'R3');
        expect(log.where((e) => e == 'start'), isEmpty);

        // Each row action is its own in-app event for that row only.
        expect(events, hasLength(2));
        expect(events[0].actionId, kActionAcknowledge);
        expect(events[0].taskIds, ['T-R1']);
        expect(events[0].origin, 'inapp');
        expect(events[0].lane, AlarmLogLane.inapp);
        expect(events[0].eventId, isNotNull);
        expect(
          events[0].occurrenceFireAtMs,
          alarmFireAt(rows.first).millisecondsSinceEpoch,
        );
        expect(events[1].actionId, 'snooze');
        expect(events[1].taskIds, ['T-R2']);
        expect(
          events[1].untilMs,
          now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        );
        expect(events[1].eventId, isNot(events[0].eventId));

        // The last row answered: the screen closes, nothing is pending.
        await controller().actOnRow('T-R3', AlarmRowAction.complete);
        expect(overlay().ringing, isEmpty);
        expect(events.last.actionId, kActionComplete);
        await tester.pump(kAlarmResumeAfter * 2);
        expect(log.where((e) => e == 'start'), isEmpty);
      },
    );

    // A grouped AlarmKit alarm rings at its earliest member's second; a
    // later member of the same minute is covered by it all the same.
    testWidgets(
      'acting first on a later member of the minute stops the grouped alert',
      (tester) async {
        final rows = minute();
        final host = FakeAlarmKitHost();
        final grouped = AlarmKitScheduled(
          id: 7,
          state: AlarmKitAlarmState.alerting,
          members: [for (final r in rows) r.taskId],
          fireAtMs: alarmKitFireAtMs(alarmFireAt(rows.first)),
        );
        expect(alarmKitCovering([grouped], rows.last).single.id, 7);
        boot(
          alarmKitHost: host,
          extra: [
            alarmKitViewProvider.overrideWith(() => AlarmKitView([grouped])),
          ],
        );
        feed.add(rows);
        await settle(tester);
        expect(overlay().ringsOnLockScreen, isTrue);

        // R3 rang at 11:59:40, the alarm says 11:59:00: same minute.
        expect(controller().ringsOnLockScreen(rows.last), isTrue);
        final saved = controller().actOnRow('T-R3', AlarmRowAction.acknowledge);
        expect(host.stopped, [7]);
        expect(await saved, isTrue);
        await tester.pump();
        expect(overlay().ringsOnLockScreen, isFalse);

        // Another minute is another alarm.
        expect(
          alarmKitCovering([
            grouped,
          ], alarm(rid: 'R1', remindAt: now.add(const Duration(minutes: 1)))),
          isEmpty,
        );
        await controller().acknowledgeAll();
        await tester.pump(kAlarmResumeAfter * 2);
      },
    );

    testWidgets(
      'sound resumes after 60 s without interaction while rows remain',
      (tester) async {
        boot();
        feed.add(minute());
        await settle(tester);
        expect(log, ['start']);

        await controller().actOnRow('T-R1', AlarmRowAction.acknowledge);
        expect(_squash(log), ['start', 'stop']);

        // Any interaction restarts the minute.
        await tester.pump(const Duration(seconds: 50));
        controller().interacted();
        await tester.pump(const Duration(seconds: 50));
        expect(_squash(log), ['start', 'stop']);

        await tester.pump(const Duration(seconds: 10));
        expect(_squash(log), ['start', 'stop', 'start']);
        expect(controller().sounding, isTrue);
        expect(overlay().ringing, hasLength(2));

        // Never two in-app sounds at once: another minute changes nothing,
        // and a manual start on a playing bed is a no-op.
        await tester.pump(kAlarmResumeAfter * 2);
        controller().startSound();
        expect(log.where((e) => e == 'start'), hasLength(2));

        await controller().acknowledgeAll();
        expect(overlay().ringing, isEmpty);
        expect(controller().sounding, isFalse);
      },
    );

    testWidgets(
      'an alarm arriving while the screen is open joins the list without a '
      'second sound',
      (tester) async {
        boot();
        final first = alarm(
          rid: 'R1',
          remindAt: now.subtract(const Duration(seconds: 10)),
        );
        final later = alarm(
          rid: 'R2',
          remindAt: now.add(const Duration(seconds: 30)),
        );
        feed.add([first, later]);
        await settle(tester);
        expect(overlay().ringing.single.reminderId, 'R1');
        expect(log, ['start']);

        // The timer wheel brings R2 due while R1's screen is open.
        clock = now.add(const Duration(seconds: 30));
        await tester.pump(const Duration(seconds: 30));
        expect(overlay().ringing.map((a) => a.reminderId), ['R1', 'R2']);
        expect(log, ['start']);

        // A synced alarm in the same minute arrives through the feed.
        final synced = alarm(
          rid: 'R3',
          remindAt: now.add(const Duration(seconds: 20)),
        );
        feed.add([first, later, synced]);
        await settle(tester);
        expect(overlay().ringing.map((a) => a.reminderId), ['R1', 'R3', 'R2']);
        expect(log, ['start']);
        expect(controller().sounding, isTrue);

        // Silenced by an action, the open screen stays quiet when one more
        // alarm joins: only the untouched minute brings the sound back.
        await controller().actOnRow('T-R1', AlarmRowAction.acknowledge);
        expect(_squash(log), ['start', 'stop']);
        final late = alarm(
          rid: 'R4',
          remindAt: now.add(const Duration(seconds: 25)),
        );
        feed.add([first, later, synced, late]);
        await settle(tester);
        expect(overlay().ringing.map((a) => a.reminderId), ['R3', 'R4', 'R2']);
        expect(_squash(log), ['start', 'stop']);
        await tester.pump(kAlarmResumeAfter);
        expect(_squash(log), ['start', 'stop', 'start']);
      },
    );

    test('snooze all is one batch event', () async {
      final batches = <(List<String>, DateTime, String?)>[];
      boot(
        recordEvents: false,
        extra: [
          taskStoreProvider.overrideWith(
            (ref) => _BatchTaskStore(ref.watch(databaseProvider), batches),
          ),
        ],
      );
      feed.add(minute());
      await pumpEventQueue();
      expect(overlay().ringing, hasLength(3));

      final until = now.add(const Duration(minutes: 5));
      final saved = controller().snoozeAll(until);
      // Silenced and dismissed before the write lands.
      expect(overlay().ringing, isEmpty);
      expect(controller().sounding, isFalse);
      expect(await saved, isTrue);

      // One snoozeBatch for the three members, under one receipt.
      expect(batches, hasLength(1));
      expect(batches.single.$1, ['T-R1', 'T-R2', 'T-R3']);
      expect(batches.single.$2, until);
      final db = container.read(databaseProvider);
      final receipts = await db.select(db.actionReceipts).get();
      expect(receipts, hasLength(1));
      expect(receipts.single.eventId, batches.single.$3);
      expect(receipts.single.action, 'snooze');

      // "Tümünü onayla" on a fresh list: one more receipt, one more event.
      feed.add([
        alarm(rid: 'R4', remindAt: now.subtract(const Duration(seconds: 5))),
        alarm(rid: 'R5', remindAt: now.subtract(const Duration(seconds: 5))),
      ]);
      await pumpEventQueue();
      expect(overlay().ringing, hasLength(2));
      expect(await controller().acknowledgeAll(), isTrue);
      expect(overlay().ringing, isEmpty);
      final after = await db.select(db.actionReceipts).get();
      expect(after.map((r) => r.action), contains(kActionAcknowledge));
      expect(after, hasLength(2));
    });

    testWidgets('a failed group write brings every row back, silently', (
      tester,
    ) async {
      boot(
        recordEvents: false,
        extra: [
          alarmActionApplierProvider.overrideWithValue(
            (_) async => throw StateError('database is locked'),
          ),
        ],
      );
      feed.add(minute());
      await settle(tester);
      expect(await controller().acknowledgeAll(), isFalse);
      expect(overlay().ringing, hasLength(3));
      expect(overlay().ringing.every(overlay().isFailed), isTrue);
      expect(controller().failedAction(overlay().ringing.first), isNotNull);
      expect(_squash(log), ['start', 'stop']);
      // Only the untouched minute brings its sound back.
      await tester.pump(kAlarmResumeAfter - const Duration(seconds: 1));
      expect(_squash(log), ['start', 'stop']);
      await tester.pump(const Duration(seconds: 1));
      expect(_squash(log), ['start', 'stop', 'start']);
    });
  });
}

/// [log] with repeated neighbours folded: `silence()` and `handled()` both
/// stop, and stopping twice is one silence.
List<String> _squash(List<String> log) => [
  for (var i = 0; i < log.length; i++)
    if (i == 0 || log[i] != log[i - 1]) log[i],
];

/// Records the order of start/stop calls (#46).
class _MemoryKv implements LocalKv {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> removeWhere(bool Function(String key) test) async =>
      values.removeWhere((key, _) => test(key));
}

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

/// Acknowledges nothing: this file is about the sound, not the row.
class _NoopReminderStore extends ReminderStore {
  _NoopReminderStore(AwDatabase db) : super(db, () {});

  @override
  Future<void> acknowledge(String reminderId, {String? receiptId}) async {}
}

/// Snoozes, completes and mutes nothing: this file is about the sound.
class _NoopTaskStore extends TaskStore {
  _NoopTaskStore(AwDatabase db) : super(db, () {});

  @override
  Future<void> snooze(
    String taskId, {
    String? preset,
    DateTime? until,
    String? receiptId,
  }) async {}

  @override
  Future<void> complete(String taskId, {String? receiptId}) async {}

  @override
  Future<void> muteAlarms(String taskId, {String? receiptId}) async {}
}

/// Records every group snooze, then writes it for real (#47).
class _BatchTaskStore extends TaskStore {
  _BatchTaskStore(AwDatabase db, this.batches) : super(db, () {});

  final List<(List<String>, DateTime, String?)> batches;

  @override
  Future<void> snoozeBatch(
    List<String> taskIds, {
    required DateTime until,
    String? receiptId,
  }) async {
    batches.add((taskIds, until, receiptId));
    await super.snoozeBatch(taskIds, until: until, receiptId: receiptId);
  }
}

/// An AlarmKit bridge whose `stop` throws the way a dead channel does.
class _ThrowingStopHost extends FakeAlarmKitHost {
  @override
  Future<AlarmKitStopResult> stop(int id) async =>
      throw StateError('channel gone');
}
