import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
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

        await tester.tap(find.byKey(const Key('alarm-acknowledge')));
        // Several frames: the first screen is torn down after the second one
        // mounted — the moment its dispose() used to stop the shared player.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Task R2'), findsOneWidget);
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

        await tester.tap(find.byKey(const Key('alarm-acknowledge')));
        await tester.pump();
        await tester.pump();
        // The system alert is gone, so the next member is not left silent.
        expect(host.stopped, [7]);
        expect(find.text('Task R2'), findsOneWidget);
        expect(overlay().ringsOnLockScreen, isFalse);
        expect(_squash(log), ['start']);
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
}

/// [log] with repeated neighbours folded: `silence()` and `handled()` both
/// stop, and stopping twice is one silence.
List<String> _squash(List<String> log) => [
  for (var i = 0; i < log.length; i++)
    if (i == 0 || log[i] != log[i - 1]) log[i],
];

/// Records the order of start/stop calls (#46).
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

/// An AlarmKit bridge whose `stop` throws the way a dead channel does.
class _ThrowingStopHost extends FakeAlarmKitHost {
  @override
  Future<AlarmKitStopResult> stop(int id) async =>
      throw StateError('channel gone');
}
