import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/scheduler.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

import '../support/fake_notifications.dart';
import '../sync/sync_engine_test.dart' show FakeSyncApi;

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

void main() {
  late AwDatabase db;
  late TaskStore tasks;
  late ReminderStore reminders;
  var pokes = 0;

  setUp(() async {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    pokes = 0;
    tasks = TaskStore(db, () => pokes++);
    reminders = ReminderStore(db, () => pokes++);

    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id('T1'),
            workspaceId: ws,
            title: 'Acil iş',
            status: const Value('open'),
            isUrgent: const Value(true),
            remindAt: Value(DateTime.utc(2030, 6, 1, 9)),
          ),
        );
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id('R1'),
            taskId: id('T1'),
            remindAt: DateTime.utc(2030, 6, 1, 9),
            alarmLevel: const Value('urgent'),
            requiresAcknowledgement: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  String payload() => jsonEncode({'taskId': id('T1'), 'reminderId': id('R1')});

  Future<void> handle(String? actionId) => handleNotificationEvent(
    NotificationEvent(actionId: actionId, payload: payload()),
    tasks: tasks,
    reminders: reminders,
    navigate: (_) => fail('should not navigate for $actionId'),
  );

  test('plain tap deep-links to the task', () async {
    String? navigated;
    await handleNotificationEvent(
      NotificationEvent(payload: payload()),
      tasks: tasks,
      reminders: reminders,
      navigate: (location) => navigated = location,
    );
    expect(navigated, '/tasks/${id('T1')}');
  });

  test('complete action completes the task through the outbox', () async {
    await handle(kActionComplete);
    final task = await db.select(db.tasks).getSingle();
    expect(task.status, 'completed');
    expect(task.completedAt, isNotNull);
    final outbox = await db.select(db.pendingMutations).get();
    expect(outbox.single.entityType, 'task');
    expect(outbox.single.patchJson, contains('completed'));
    expect(pokes, 1);
  });

  // OPH-178: the notification's own way out that isn't "done".
  test('mute action silences the task without completing it', () async {
    await handle(kActionMute);

    final task = await db.select(db.tasks).getSingle();
    expect(task.alarmsMutedAt, isNotNull);
    expect(task.status, 'open');
    expect(task.completedAt, equals(null));

    final outbox = await db.select(db.pendingMutations).get();
    expect(outbox.single.patchJson, contains('alarmsMutedAt'));
    expect(pokes, 1);
  });

  test('snooze action moves the task AND its alarm, then enqueues', () async {
    await handle(snoozeActionId('30_min'));

    final task = await db.select(db.tasks).getSingle();
    expect(task.snoozedUntil, isNotNull);
    final reminder = await db.select(db.reminders).getSingle();
    expect(reminder.status, 'snoozed');
    expect(reminder.snoozedUntil, task.snoozedUntil);

    final outbox = await db.select(db.pendingMutations).get();
    final patch = jsonDecode(outbox.single.patchJson!) as Map<String, dynamic>;
    expect(patch.keys, ['snoozedUntil']);
    expect(DateTime.parse(patch['snoozedUntil'] as String), task.snoozedUntil);
  });

  test(
    'acknowledge flips the reminder locally and enqueues (OPH-063)',
    () async {
      await handle(kActionAcknowledge);

      final reminder = await db.select(db.reminders).getSingle();
      expect(reminder.status, 'acknowledged');
      expect(reminder.acknowledgedAt, isNotNull);

      final outbox = await db.select(db.pendingMutations).get();
      expect(outbox.single.entityType, 'reminder');
      expect(outbox.single.entityId, id('R1'));
      expect(jsonDecode(outbox.single.patchJson!), {'status': 'acknowledged'});

      // Idempotent: a second tap on a stale notification changes nothing.
      await handle(kActionAcknowledge);
      expect(await db.select(db.pendingMutations).get(), hasLength(1));
    },
  );

  test('snooze preset math matches the server presets', () {
    final base = DateTime.utc(2026, 7, 15, 12);
    expect(
      TaskStore.snoozeUntilFor('5_min', now: base),
      base.add(const Duration(minutes: 5)),
    );
    expect(
      TaskStore.snoozeUntilFor('1_hour', now: base),
      base.add(const Duration(hours: 1)),
    );
    final tomorrow = TaskStore.snoozeUntilFor('tomorrow_morning', now: base);
    expect(tomorrow.hour, 9);
    expect(() => TaskStore.snoozeUntilFor('never'), throwsArgumentError);
  });

  test('garbage payloads and unknown actions are ignored safely', () async {
    await handleNotificationEvent(
      const NotificationEvent(actionId: kActionComplete, payload: 'çöp{'),
      tasks: tasks,
      reminders: reminders,
      navigate: (_) => fail('no navigation'),
    );
    await handle('unknown_action');
    expect(await db.select(db.pendingMutations).get(), isEmpty);
  });

  // OPH-427 (#49, NOTIFICATIONS §2b.3): a pulled action is applied exactly
  // once — its receipt commits and rolls back with the model change.
  group('pulled actions applied exactly once (OPH-427)', () {
    final nineAm = DateTime.utc(2030, 6, 1, 9);

    Future<void> addUrgent(String task, String reminder, DateTime at) async {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id(task),
              workspaceId: ws,
              title: 'Acil $task',
              status: const Value('open'),
              isUrgent: const Value(true),
              remindAt: Value(at),
            ),
          );
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: id(reminder),
              taskId: id(task),
              remindAt: at,
              alarmLevel: const Value('urgent'),
              requiresAcknowledgement: const Value(true),
            ),
          );
    }

    AlarmKitActionEvent native(
      String eventId,
      String action, {
      List<String>? taskIds,
      int? untilMs,
      String? preset,
      int? occurrenceFireAtMs,
      int pressedAtMs = 1_000,
      String? scheduleOutcome,
    }) => AlarmKitActionEvent(
      eventId: eventId,
      action: action,
      taskIds: taskIds ?? [id('T1')],
      pressedAtMs: pressedAtMs,
      untilMs: untilMs,
      preset: preset,
      occurrenceFireAtMs: occurrenceFireAtMs,
      scheduleOutcome: scheduleOutcome,
    );

    AlarmKitActionPump pumpFor(
      AlarmKitHost host, {
      TaskStore? taskStore,
      ReminderStore? reminderStore,
      AlarmLog? log,
    }) => AlarmKitActionPump(
      host: host,
      log: log,
      apply: (event) => handleNotificationEvent(
        event,
        db: db,
        tasks: taskStore ?? tasks,
        reminders: reminderStore ?? reminders,
        log: log,
        navigate: (_) => fail('a pulled action never navigates'),
      ),
    );

    test(
      'a snooze redelivered after a crash between commit and ack is applied exactly once',
      () async {
        await addUrgent('T2', 'R2', nineAm);
        final until = DateTime.utc(2030, 6, 1, 9, 5);
        final host = _AckCrashingHost()
          ..queue.add(
            native(
              'ev-1',
              'snooze',
              taskIds: [id('T1'), id('T2'), id('T1')],
              untilMs: until.millisecondsSinceEpoch,
            ),
          );

        // The write commits, then the process dies before the ack.
        await pumpFor(host).pull();
        expect(host.acked, isEmpty);
        expect(host.queue, hasLength(1));

        // A new process: fresh stores and pump over the same database; the
        // native queue hands the same event over again.
        host.crash = false;
        final reborn = pumpFor(
          host,
          taskStore: TaskStore(db, () {}),
          reminderStore: ReminderStore(db, () {}),
        );
        await reborn.pull();
        await reborn.pull();

        expect(host.queue, isEmpty);
        expect(host.acked, [
          ['ev-1'],
        ]);
        final rows = await db.select(db.reminders).get();
        expect(rows.map((r) => r.snoozeCount), [1, 1]);
        expect(rows.map((r) => r.snoozedUntil), [until, until]);
        final outbox = await db.select(db.pendingMutations).get();
        expect(outbox.map((m) => m.entityId).toList()..sort(), [
          id('T1'),
          id('T2'),
        ]);
        final receipts = await db.select(db.actionReceipts).get();
        expect(receipts.map((r) => r.eventId), ['ev-1']);
      },
    );

    test(
      'a receipt written without its model change cannot exist (transaction rollback)',
      () async {
        final host = FakeAlarmKitHost()
          ..queue.add(
            native(
              'ev-1',
              'snooze',
              untilMs: DateTime.utc(2030, 6, 1, 9, 5).millisecondsSinceEpoch,
            ),
          );

        await pumpFor(host, taskStore: _ExplodingTaskStore(db)).pull();

        expect(await db.select(db.actionReceipts).get(), isEmpty);
        expect((await db.select(db.tasks).getSingle()).snoozedUntil, isNull);
        expect(await db.select(db.pendingMutations).get(), isEmpty);
        expect(host.acked, isEmpty, reason: 'nothing committed, nothing acked');

        // Redelivered to a store that works: applied now, exactly once.
        await pumpFor(host).pull();
        expect(
          (await db.select(db.tasks).getSingle()).snoozedUntil,
          DateTime.utc(2030, 6, 1, 9, 5),
        );
        expect(await db.select(db.actionReceipts).get(), hasLength(1));
        expect(host.acked, [
          ['ev-1'],
        ]);
      },
    );

    test('an alarmkit snooze event writes its untilMs unchanged', () async {
      // Pressed at 09:00:07 local-device time; the app opened hours later.
      // The press-time target stands — never recomputed from the drain.
      final until = DateTime.utc(2030, 6, 1, 9, 5, 7);
      final log = AlarmLog(db);
      final applied = await handleNotificationEvent(
        notificationEventForAlarmKit(
          native(
            'ev-1',
            'snooze',
            untilMs: until.millisecondsSinceEpoch,
            preset: '1_hour',
            pressedAtMs: DateTime.utc(
              2030,
              6,
              1,
              9,
              0,
              7,
            ).millisecondsSinceEpoch,
          ),
        ),
        db: db,
        tasks: tasks,
        reminders: reminders,
        log: log,
        navigate: (_) => fail('no navigation'),
      );
      expect(applied, isTrue);

      final task = await db.select(db.tasks).getSingle();
      expect(task.snoozedUntil, until);
      final reminder = await db.select(db.reminders).getSingle();
      expect(reminder.snoozedUntil, until);
      expect(reminder.snoozeCount, 1);
      final patch =
          jsonDecode(
                (await db.select(db.pendingMutations).getSingle()).patchJson!,
              )
              as Map<String, dynamic>;
      expect(DateTime.parse(patch['snoozedUntil'] as String), until);

      final rows = await db.select(db.alarmEvents).get();
      expect(rows, hasLength(1));
      expect(rows.single.event, AlarmLogEvent.action);
      expect(rows.single.lane, AlarmLogLane.alarmkit);
    });

    test(
      'a snooze event with a failed native schedule is applied and its fallback notification is cleared after the plan',
      () async {
        final until = DateTime.utc(2030, 6, 1, 9, 5);
        final host = _OrderRecordingHost()
          ..queue.addAll([
            native(
              'ev-failed',
              'snooze',
              untilMs: until.millisecondsSinceEpoch,
              scheduleOutcome: 'limitReached',
            ),
            native(
              'ev-ok',
              'snooze',
              untilMs: until.millisecondsSinceEpoch,
              pressedAtMs: 2_000,
              scheduleOutcome: 'ok',
            ),
          ]);
        final pump = pumpFor(host);
        await pump.pull();
        // The failed one stays queued until its fallback is cleared: the
        // entry is what remembers the clear across a restart.
        expect(host.acked.expand((e) => e), ['ev-ok']);
        expect(host.fallbacksCleared, isEmpty, reason: 'no plan yet');

        final input = [
          AlarmInput(
            reminderId: id('R1'),
            taskId: id('T1'),
            taskTitle: 'Acil iş',
            remindAt: nineAm,
            status: 'snoozed',
            snoozedUntil: until,
            urgent: true,
            requiresAcknowledgement: true,
          ),
        ];
        final scheduler = NotificationScheduler(
          gateway: FakeNotificationsGateway(),
          // Passes run only when the test says so.
          alarms: const Stream<List<AlarmInput>>.empty(),
          privacyMode: false,
          alarmKit: host,
          drainActions: pump.beforePlan,
          afterPlan: pump.afterPlan,
          clock: () => DateTime.utc(2030, 6, 1, 9, 1),
        );
        addTearDown(scheduler.dispose);
        await scheduler.start();
        await scheduler.applyOnce(input);

        // Only the failed one, and only once the plan had scheduled the
        // alarm that replaces it.
        expect(host.fallbacksCleared, [
          ['ev-failed'],
        ]);
        expect(
          host.calls.indexOf('schedule'),
          lessThan(host.calls.indexOf('clearFallbacks')),
        );
        expect(host.acked.last, ['ev-failed'], reason: 'acked after the clear');

        // An event the plan's own drain applies waits for the NEXT plan: the
        // pass that drained it planned from a model without it.
        host.queue.add(
          native(
            'ev-late',
            'snooze',
            untilMs: until.millisecondsSinceEpoch,
            pressedAtMs: 3_000,
            scheduleOutcome: 'failed',
          ),
        );
        await scheduler.applyOnce(input);
        expect(host.fallbacksCleared, hasLength(1));
        await scheduler.applyOnce(input);
        expect(host.fallbacksCleared.last, ['ev-late']);
      },
    );

    group('a failed native snooze keeps its fallback until a plan replaced '
        'it (OPH-431)', () {
      final until = DateTime.utc(2030, 6, 1, 9, 5);
      final snoozed = [
        AlarmInput(
          reminderId: id('R1'),
          taskId: id('T1'),
          taskTitle: 'Acil iş',
          remindAt: nineAm,
          status: 'snoozed',
          snoozedUntil: until,
          urgent: true,
          requiresAcknowledgement: true,
        ),
      ];

      NotificationScheduler schedulerFor(
        FakeAlarmKitHost host,
        AlarmKitActionPump pump,
        FakeNotificationsGateway gateway,
      ) {
        final scheduler = NotificationScheduler(
          gateway: gateway,
          alarms: const Stream<List<AlarmInput>>.empty(),
          privacyMode: false,
          alarmKit: host,
          drainActions: pump.beforePlan,
          afterPlan: pump.afterPlan,
          keepPendingIds: pump.heldFallbackIds,
          clock: () => DateTime.utc(2030, 6, 1, 9, 1),
        );
        addTearDown(scheduler.dispose);
        return scheduler;
      }

      test('a process killed before the plan still clears it on the next '
          'launch', () async {
        final host = FakeAlarmKitHost()
          ..queue.add(
            native(
              'ev-failed',
              'snooze',
              untilMs: until.millisecondsSinceEpoch,
              scheduleOutcome: 'limitReached',
            ),
          );
        // Applied and committed, then the process dies before any plan.
        await pumpFor(host).pull();
        expect(host.fallbacksCleared, isEmpty);

        // The next launch: a fresh pump, the native queue as it was left.
        final pump = pumpFor(host);
        final scheduler = schedulerFor(host, pump, FakeNotificationsGateway());
        await scheduler.start();
        await scheduler.applyOnce(snoozed);
        await scheduler.applyOnce(snoozed);

        expect(host.fallbacksCleared.expand((e) => e), contains('ev-failed'));
        expect(host.queue, isEmpty, reason: 'acked once the fallback went');
        expect(
          (await db.select(db.reminders).getSingle()).snoozeCount,
          1,
          reason: 'the redelivery applied nothing twice',
        );
      });

      test('a pass that could not schedule the replacement leaves the '
          'fallback, and the next one that could clears it', () async {
        final host = FakeAlarmKitHost()
          ..scheduleFailure = 'limit_reached'
          ..queue.add(
            native(
              'ev-failed',
              'snooze',
              taskIds: [id('T1')],
              untilMs: until.millisecondsSinceEpoch,
              scheduleOutcome: 'limitReached',
            ),
          );
        final gateway = FakeNotificationsGateway()
          ..failScheduleFor = (_) => true;
        final pump = pumpFor(host);
        await pump.pull();
        final scheduler = schedulerFor(host, pump, gateway);
        await scheduler.start();
        for (var i = 0; i < 3; i++) {
          await scheduler.applyOnce(snoozed);
        }
        expect(gateway.scheduled, isEmpty);
        expect(host.fallbacksCleared, isEmpty, reason: 'nothing else rings');
        expect(host.queue.map((e) => e.eventId), ['ev-failed']);

        gateway.failScheduleFor = null;
        await scheduler.applyOnce(snoozed);
        expect(gateway.scheduled, isNotEmpty);
        expect(host.fallbacksCleared, [
          ['ev-failed'],
        ]);
        expect(host.queue, isEmpty);
      });

      test('the notification diff does not cancel the fallback the plugin '
          'lists before a replacement is on the OS', () async {
        // The fallback is a request the notification plugin lists under its
        // numeric id, and that id is in no plan: the set-diff used to cancel
        // it before the pass even tried the replacement.
        final fallbackId = alarmKitFallbackNotificationId('ev-failed');
        final host = FakeAlarmKitHost()
          ..scheduleFailure = 'limit_reached'
          ..queue.add(
            native(
              'ev-failed',
              'snooze',
              taskIds: [id('T1')],
              untilMs: until.millisecondsSinceEpoch,
              scheduleOutcome: 'limitReached',
            ),
          );
        final gateway = FakeNotificationsGateway()
          ..scheduled[fallbackId] = PlannedNotification(
            id: fallbackId,
            title: 'Acil iş',
            body: '',
            fireAt: until,
            urgent: true,
            payload: '{"eventId":"ev-failed"}',
          )
          ..failScheduleFor = (n) => n.id != fallbackId;
        final pump = pumpFor(host);
        final scheduler = schedulerFor(host, pump, gateway);
        await scheduler.start();
        for (var i = 0; i < 3; i++) {
          await scheduler.applyOnce(snoozed);
        }
        expect(gateway.cancelled, isNot(contains(fallbackId)));
        expect(gateway.scheduled.keys, [fallbackId], reason: 'it still rings');
        expect(host.fallbacksCleared, isEmpty);

        // Once a pass put the replacement on the OS, the fallback goes.
        gateway.failScheduleFor = null;
        await scheduler.applyOnce(snoozed);
        expect(host.fallbacksCleared, [
          ['ev-failed'],
        ]);
        expect(host.queue, isEmpty);
      });
    });

    test('the fallback id is the one the native snooze gives its request', () {
      // AWAlarmFallback.notificationId(eventId: "E-1") on the Swift side.
      expect(alarmKitFallbackNotificationId('E-1'), 1019953648);
    });

    test('a receipted action pokes sync from inside its transaction, and '
        'the round still pushes it and the next write', () async {
      // The stores poke inside the receipt transaction; a debounce timer
      // born in drift's zone would query the closed transaction and wedge
      // the engine until a restart.
      final api = FakeSyncApi();
      final engine = SyncEngine(
        db: db,
        api: api,
        workspaceId: ws,
        debounce: const Duration(milliseconds: 1),
      );
      addTearDown(engine.dispose);
      await engine.start();
      final syncing = TaskStore(db, engine.notifyLocalWrite);
      final until = DateTime.utc(2030, 6, 1, 9, 5);

      expect(
        await handleNotificationEvent(
          notificationEventForAlarmKit(
            native('ev-sync', 'snooze', untilMs: until.millisecondsSinceEpoch),
          ),
          db: db,
          tasks: syncing,
          reminders: reminders,
          navigate: (_) => fail('no navigation'),
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.pushedBatches, hasLength(1));
      expect(await db.select(db.pendingMutations).get(), isEmpty);

      await syncing.complete(id('T1'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.pushedBatches, hasLength(2));
      expect(await db.select(db.pendingMutations).get(), isEmpty);
    });

    test('a native stop acknowledges the occurrence it rang for', () async {
      // T1 has a second urgent alarm at 10:00 (its deadline); T2 rang in the
      // same minute as T1's 09:00 — one grouped occurrence.
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: id('R1DUE'),
              taskId: id('T1'),
              kind: const Value('due'),
              remindAt: DateTime.utc(2030, 6, 1, 10),
              alarmLevel: const Value('urgent'),
              requiresAcknowledgement: const Value(true),
            ),
          );
      await addUrgent('T2', 'R2', nineAm.add(const Duration(seconds: 30)));
      final log = AlarmLog(db);
      final host = FakeAlarmKitHost()
        ..queue.add(
          native(
            'ev-stop',
            'acknowledge',
            taskIds: [id('T1'), id('T2')],
            occurrenceFireAtMs: nineAm.millisecondsSinceEpoch,
          ),
        );
      await pumpFor(host, log: log).pull();
      host.queue.add(
        native(
          'ev-stop',
          'acknowledge',
          taskIds: [id('T1'), id('T2')],
          occurrenceFireAtMs: nineAm.millisecondsSinceEpoch,
        ),
      );
      await pumpFor(host, log: log).pull();

      final byId = {
        for (final r in await db.select(db.reminders).get()) r.id: r.status,
      };
      expect(byId, {
        id('R1'): 'acknowledged',
        id('R1DUE'): 'scheduled',
        id('R2'): 'acknowledged',
      });
      final outbox = await db.select(db.pendingMutations).get();
      expect(outbox.map((m) => m.entityId).toList()..sort(), [
        id('R1'),
        id('R2'),
      ]);
      final actions = [
        for (final r in await db.select(db.alarmEvents).get())
          if (r.event == AlarmLogEvent.action) r,
      ];
      expect(actions, hasLength(1));
      expect(actions.single.lane, AlarmLogLane.alarmkit);
    });

    test(
      'a converted v1 snooze:<preset> entry is applied once with the preset target',
      () async {
        // Written by the build with the #49 bug: a preset, no untilMs. The
        // target is the press time plus the preset, not the read time.
        final pressedAt = DateTime.utc(2030, 6, 1, 9, 0, 12);
        final entry = native(
          'ev-v1',
          'snooze',
          preset: '30_min',
          pressedAtMs: pressedAt.millisecondsSinceEpoch,
        );
        final host = FakeAlarmKitHost()..queue.add(entry);
        await pumpFor(host).pull();
        host.queue.add(entry);
        await pumpFor(host).pull();

        final expected = pressedAt.add(const Duration(minutes: 30));
        expect((await db.select(db.tasks).getSingle()).snoozedUntil, expected);
        final reminder = await db.select(db.reminders).getSingle();
        expect(reminder.snoozedUntil, expected);
        expect(reminder.snoozeCount, 1);
        expect(await db.select(db.pendingMutations).get(), hasLength(1));
        expect(host.queue, isEmpty);
      },
    );

    // §2b.3 native snooze step 6: a group snooze whose native schedule failed
    // leaves one `aw.fallback.<eventId>` notification for every member. Its
    // buttons arrive on the notification lane and reach every member.
    String fallbackPayload(List<String> members) => jsonEncode({
      'taskId': members.first,
      'taskIds': members,
      'eventId': 'ev-fallback',
    });

    Future<bool> tapFallback(String action, List<String> members) =>
        handleNotificationEvent(
          NotificationEvent(
            actionId: action,
            payload: fallbackPayload(members),
          ),
          tasks: tasks,
          reminders: reminders,
          navigate: (_) => fail('a button never navigates'),
        );

    test(
      'a fallback notification button snoozes every member of the group',
      () async {
        await addUrgent('T2', 'R2', nineAm.add(const Duration(seconds: 30)));
        expect(
          await tapFallback(snoozeActionId('5_min'), [id('T1'), id('T2')]),
          isTrue,
        );

        final snoozed = {
          for (final t in await db.select(db.tasks).get()) t.id: t.snoozedUntil,
        };
        expect(snoozed[id('T1')], isNotNull);
        expect(snoozed[id('T2')], snoozed[id('T1')]); // one target, one ring
        final outbox = await db.select(db.pendingMutations).get();
        expect(outbox.map((m) => m.entityId).toList()..sort(), [
          id('T1'),
          id('T2'),
        ]);
      },
    );

    test(
      'a fallback notification button completes every member of the group',
      () async {
        await addUrgent('T2', 'R2', nineAm);
        await tapFallback(kActionComplete, [id('T1'), id('T2'), id('T1')]);

        final statuses = {
          for (final t in await db.select(db.tasks).get()) t.id: t.status,
        };
        expect(statuses, {id('T1'): 'completed', id('T2'): 'completed'});
        expect(await db.select(db.pendingMutations).get(), hasLength(2));
      },
    );

    test(
      'a fallback notification acknowledge silences every member that is due',
      () async {
        final past = DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        );
        await addUrgent('T3', 'R3', past);
        await addUrgent('T4', 'R4', past.add(const Duration(seconds: 20)));
        await tapFallback(kActionAcknowledge, [id('T3'), id('T4')]);

        final byId = {
          for (final r in await db.select(db.reminders).get()) r.id: r.status,
        };
        expect(byId, {
          id('R1'): 'scheduled', // not a member, not due
          id('R3'): 'acknowledged',
          id('R4'): 'acknowledged',
        });
        expect(await db.select(db.actionReceipts).get(), isEmpty);
      },
    );

    test(
      'a merged urgent chain acknowledges exactly the reminders it lists (OPH-440)',
      () async {
        // One chain for a whole minute (planNotifications): its payload lists
        // every task and reminder it rings for, ids only.
        await addUrgent('T2', 'R2', DateTime.utc(2030, 6, 1, 9, 0, 30));
        await db
            .into(db.reminders)
            .insert(
              RemindersCompanion.insert(
                id: id('R5'),
                taskId: id('T2'),
                remindAt: DateTime.utc(2030, 6, 1, 10),
                alarmLevel: const Value('urgent'),
                requiresAcknowledgement: const Value(true),
              ),
            );
        final handled = await handleNotificationEvent(
          NotificationEvent(
            actionId: kActionAcknowledge,
            payload: jsonEncode({
              'taskId': id('T1'),
              'taskIds': [id('T1'), id('T2')],
              'reminderIds': [id('R1'), id('R2')],
              'chainIndex': 0,
            }),
          ),
          tasks: tasks,
          reminders: reminders,
          navigate: (_) => fail('a button never navigates'),
        );
        expect(handled, isTrue);
        final byId = {
          for (final r in await db.select(db.reminders).get()) r.id: r.status,
        };
        expect(byId, {
          id('R1'): 'acknowledged',
          id('R2'): 'acknowledged',
          id('R5'): 'scheduled', // another minute: its own alarm
        });
      },
    );

    // OPH-439 (#47): a group action is one receipt, one batch write and one
    // outbox mutation per task.
    test(
      'a group snooze event moves every member to the same untilMs under one receipt',
      () async {
        // T1's deadline rings in the same minute as its reminder.
        await db
            .into(db.reminders)
            .insert(
              RemindersCompanion.insert(
                id: id('R1DUE'),
                taskId: id('T1'),
                kind: const Value('due'),
                remindAt: nineAm,
                alarmLevel: const Value('urgent'),
                requiresAcknowledgement: const Value(true),
              ),
            );
        await addUrgent('T2', 'R2', nineAm.add(const Duration(seconds: 30)));
        final until = DateTime.utc(2030, 6, 1, 9, 5, 7);
        final recording = _RecordingTaskStore(db);
        final host = FakeAlarmKitHost()
          ..queue.add(
            native(
              'ev-group',
              'snooze',
              taskIds: [id('T1'), id('T2'), id('T1')],
              untilMs: until.millisecondsSinceEpoch,
            ),
          );
        await pumpFor(host, taskStore: recording).pull();

        expect(recording.batches, [
          [id('T1'), id('T2')],
        ], reason: 'one batch call, members de-duplicated');
        expect(recording.singles, 0);
        final tasksNow = await db.select(db.tasks).get();
        expect(tasksNow.map((t) => t.snoozedUntil), [until, until]);
        final rows = await db.select(db.reminders).get();
        expect(rows.map((r) => r.snoozedUntil).toSet(), {until});
        expect(rows.map((r) => r.snoozeCount), [1, 1, 1]);
        expect(await db.select(db.actionReceipts).get(), hasLength(1));
        final outbox = await db.select(db.pendingMutations).get();
        expect(outbox.map((m) => m.entityId).toList()..sort(), [
          id('T1'),
          id('T2'),
        ]);
        expect(host.acked, [
          ['ev-group'],
        ]);
      },
    );

    test(
      'a snooze into a minute that already holds another urgent alarm is written unchanged',
      () async {
        // T3 already rings at 09:05; T1's snooze lands in that minute. Dart
        // never shifts: the planner groups the two into one alarm (OPH-440).
        final taken = DateTime.utc(2030, 6, 1, 9, 5);
        await addUrgent('T3', 'R3', taken);
        final until = DateTime.utc(2030, 6, 1, 9, 5, 20);
        for (final origin in ['alarmkit', 'inapp']) {
          final applied = await handleNotificationEvent(
            NotificationEvent(
              eventId: 'ev-$origin',
              actionId: 'snooze',
              taskIds: [id('T1')],
              untilMs: until.millisecondsSinceEpoch,
              pressedAtMs: nineAm.millisecondsSinceEpoch,
              origin: origin,
            ),
            db: db,
            tasks: tasks,
            reminders: reminders,
            navigate: (_) => fail('no navigation'),
          );
          expect(applied, isTrue);
          final t1 = await (db.select(
            db.tasks,
          )..where((t) => t.id.equals(id('T1')))).getSingle();
          expect(t1.snoozedUntil, until, reason: origin);
        }
        final t3 = await (db.select(
          db.reminders,
        )..where((r) => r.id.equals(id('R3')))).getSingle();
        expect(t3.remindAt, taken);
        expect(t3.status, 'scheduled');
        expect(t3.snoozedUntil, isNull);
      },
    );

    test(
      'a group stop acknowledges every member through one batch call',
      () async {
        await addUrgent('T2', 'R2', nineAm.add(const Duration(seconds: 30)));
        final recording = _RecordingReminderStore(db);
        final host = FakeAlarmKitHost()
          ..queue.add(
            native(
              'ev-stop',
              'acknowledge',
              taskIds: [id('T1'), id('T2'), id('T2')],
              occurrenceFireAtMs: nineAm.millisecondsSinceEpoch,
            ),
          );
        await pumpFor(host, reminderStore: recording).pull();

        expect(recording.batches, [
          [id('T1'), id('T2')],
        ]);
        expect(recording.minutes, [nineAm.millisecondsSinceEpoch ~/ 60000]);
        expect(
          (await db.select(db.reminders).get()).map((r) => r.status).toSet(),
          {'acknowledged'},
        );
        expect(await db.select(db.actionReceipts).get(), hasLength(1));
      },
    );

    // OPH-454: the scheduler hears of a commit before anything else runs.
    test(
      'onCommitted names a receipted event once, after its commit and before its log row',
      () async {
        final log = AlarmLog(db);
        final seen = <String>[];
        var receiptsAtCall = -1;
        var logRowsAtCall = -1;
        Future<bool> apply({TaskStore? store}) => handleNotificationEvent(
          notificationEventForAlarmKit(
            native(
              'ev-1',
              'snooze',
              untilMs: DateTime.utc(2030, 6, 1, 9, 5).millisecondsSinceEpoch,
            ),
          ),
          db: db,
          tasks: store ?? tasks,
          reminders: reminders,
          log: log,
          navigate: (_) => fail('no navigation'),
          onCommitted: (eventId) {
            seen.add(eventId);
            // Issued now, so they run ahead of the log row's insert.
            unawaited(
              db
                  .select(db.actionReceipts)
                  .get()
                  .then((r) => receiptsAtCall = r.length),
            );
            unawaited(
              db
                  .select(db.alarmEvents)
                  .get()
                  .then((r) => logRowsAtCall = r.length),
            );
          },
        );

        // A write that rolls back is never announced.
        await expectLater(
          apply(store: _ExplodingTaskStore(db)),
          throwsStateError,
        );
        expect(seen, isEmpty);

        expect(await apply(), isTrue);
        await pumpEventQueue();
        expect(seen, ['ev-1']);
        expect(receiptsAtCall, 1, reason: 'called after the commit');
        expect(logRowsAtCall, 0, reason: 'called before the log row');

        // A redelivery changes nothing and announces nothing.
        expect(await apply(), isFalse);
        expect(seen, ['ev-1']);
      },
    );

    test('a tap without a receipt id still writes as before', () async {
      final applied = await handleNotificationEvent(
        NotificationEvent(
          actionId: snoozeActionId('5_min'),
          payload: payload(),
        ),
        tasks: tasks,
        reminders: reminders,
        navigate: (_) => fail('no navigation'),
      );
      expect(applied, isTrue);
      expect(await db.select(db.actionReceipts).get(), isEmpty);
      expect((await db.select(db.reminders).getSingle()).snoozeCount, 1);
    });
  });
}

/// Acks crash the way a killed process does: the write is committed, the
/// native queue never hears about it.
class _AckCrashingHost extends FakeAlarmKitHost {
  bool crash = true;

  @override
  Future<void> ackActions(List<String> eventIds) async {
    if (crash) throw StateError('process killed');
    await super.ackActions(eventIds);
  }
}

/// Records the order of the host calls a plan pass makes.
class _OrderRecordingHost extends FakeAlarmKitHost {
  final List<String> calls = [];

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) {
    calls.add('schedule');
    return super.schedule(alarm);
  }

  @override
  Future<void> clearFallbacks(List<String> eventIds) {
    calls.add('clearFallbacks');
    return super.clearFallbacks(eventIds);
  }
}

/// The model write fails AFTER the store has written: the receipt must roll
/// back with it.
class _ExplodingTaskStore extends TaskStore {
  _ExplodingTaskStore(AwDatabase db) : super(db, () {});

  @override
  Future<void> snoozeBatch(
    List<String> taskIds, {
    required DateTime until,
    String? receiptId,
  }) async {
    await super.snoozeBatch(taskIds, until: until, receiptId: receiptId);
    throw StateError('disk full');
  }
}

/// Records how a pulled snooze reaches the store.
class _RecordingTaskStore extends TaskStore {
  _RecordingTaskStore(AwDatabase db) : super(db, () {});

  final List<List<String>> batches = [];
  int singles = 0;

  @override
  Future<void> snooze(
    String taskId, {
    String? preset,
    DateTime? until,
    String? receiptId,
  }) {
    singles++;
    return super.snooze(
      taskId,
      preset: preset,
      until: until,
      receiptId: receiptId,
    );
  }

  @override
  Future<void> snoozeBatch(
    List<String> taskIds, {
    required DateTime until,
    String? receiptId,
  }) {
    batches.add([...taskIds]);
    return super.snoozeBatch(taskIds, until: until, receiptId: receiptId);
  }
}

/// Records how a pulled stop reaches the store.
class _RecordingReminderStore extends ReminderStore {
  _RecordingReminderStore(AwDatabase db) : super(db, () {});

  final List<List<String>> batches = [];
  final List<int> minutes = [];

  @override
  Future<void> acknowledgeBatch(
    List<String> taskIds, {
    required int occurrenceMinute,
    String? receiptId,
  }) {
    batches.add([...taskIds]);
    minutes.add(occurrenceMinute);
    return super.acknowledgeBatch(
      taskIds,
      occurrenceMinute: occurrenceMinute,
      receiptId: receiptId,
    );
  }
}
