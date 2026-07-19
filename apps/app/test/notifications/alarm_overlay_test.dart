import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/planner.dart';
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
