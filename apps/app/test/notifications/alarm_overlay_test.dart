import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_ring_screen.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/tokens.dart';

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

  // ── #46 / OPH-423: occurrences, and one owner for the sound ───────────────
  group('AlarmOverlayController (#46)', () {
    late List<String> log;
    late DateTime clock;
    late StreamController<List<AlarmInput>> feed;
    late ProviderContainer container;

    ProviderContainer boot({List<Override> extra = const []}) {
      log = [];
      clock = now;
      feed = StreamController<List<AlarmInput>>();
      container = ProviderContainer(
        overrides: [
          ...syncTestOverrides(
            alarmOverlayAutoShow: true,
            alarmFeedback: _LogFeedback(log),
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
  Future<void> acknowledge(String reminderId) async {}
}
