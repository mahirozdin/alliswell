import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

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
      final ringing = container.read(alarmOverlayControllerProvider).ringing;
      expect(ringing, isNotNull);
      expect(ringing!.taskId, id('T1'));
      expect(ringing.urgent, isTrue);
    });

    test(
      'the gate keeps the overlay off (tests default OFF, OPH-111)',
      () async {
        await boot(autoShow: false);
        expect(container.read(alarmOverlayControllerProvider).ringing, isNull);
      },
    );
  });
}
