import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/notifications/scheduler.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

import '../support/fake_notifications.dart';
import '../support/sync_overrides.dart';

/// OPH-454 (#47, #48, #49): the paths that cross lanes — the native AlarmKit
/// queue, the receipted batch write, the replica stream, the device gate and
/// the plan pass — wired the way `notificationSchedulerProvider` wires them,
/// against fakes only: a fake AlarmKit host with a ledger and an in-memory
/// replica. No device, no platform channel.

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

final nineAm = DateTime.utc(2030, 6, 1, 9);
final scope = TaskScope.workspace(ws);

void main() {
  late _Rig rig;

  setUp(() => rig = _Rig());
  tearDown(() => rig.dispose());

  /// Three urgent tasks due in one UTC minute: one grouped AlarmKit alarm.
  Future<void> threeInOneMinute(DateTime minute) async {
    await rig.addUrgent('T1', 'R1', minute);
    await rig.addUrgent('T2', 'R2', minute.add(const Duration(seconds: 20)));
    await rig.addUrgent('T3', 'R3', minute.add(const Duration(seconds: 40)));
  }

  final members = [id('T1'), id('T2'), id('T3')];
  final groupAt9 = alarmKitOccurrenceId(members, nineAm.millisecondsSinceEpoch);
  final fiveAfter = DateTime.utc(2030, 6, 1, 9, 5);
  final groupAt905 = alarmKitOccurrenceId(
    members,
    fiveAfter.millisecondsSinceEpoch,
  );

  /// The group rings at 09:00 and Ertele is pressed on the lock screen at
  /// 09:00:30: the native side schedules 09:05 for all three, stops the alarm
  /// that rang, writes its ledger record and queues ONE event.
  Future<void> ringAndSnoozeNatively() async {
    await threeInOneMinute(nineAm);
    rig.clock = DateTime.utc(2030, 6, 1, 8, 59);
    await rig.start();
    expect(rig.host.scheduled.keys, [groupAt9], reason: 'one grouped alarm');
    expect(rig.host.scheduled[groupAt9]!.members, members);

    rig.clock = DateTime.utc(2030, 6, 1, 9, 0, 40);
    rig.host.alerting.add(groupAt9);
    rig.host.pressSnooze(
      eventId: 'ev-group',
      alarmId: groupAt9,
      untilMs: fiveAfter.millisecondsSinceEpoch,
      pressedAtMs: DateTime.utc(2030, 6, 1, 9, 0, 30).millisecondsSinceEpoch,
    );
    await rig.settle();
  }

  test(
    'a native group snooze converges to one AlarmKit alarm after the pull, the batch and the plan',
    () async {
      await ringAndSnoozeNatively();

      // The batch: one receipt, every member at the native target unchanged.
      final receipts = await rig.db.select(rig.db.actionReceipts).get();
      expect(receipts.map((r) => r.eventId), ['ev-group']);
      final tasks = await rig.db.select(rig.db.tasks).get();
      expect(tasks.map((t) => t.snoozedUntil).toSet(), {fiveAfter});
      final reminders = await rig.db.select(rig.db.reminders).get();
      expect(reminders.map((r) => r.status).toSet(), {'snoozed'});
      expect(reminders.map((r) => r.snoozedUntil).toSet(), {fiveAfter});
      expect(reminders.map((r) => r.snoozeCount), [1, 1, 1]);
      final outbox = await rig.db.select(rig.db.pendingMutations).get();
      expect(outbox.map((m) => m.entityId).toList()..sort(), members);

      // The ack came after the commit, exactly once.
      expect(rig.host.acked, [
        ['ev-group'],
      ]);
      expect(rig.host.ackSawCommit, [true]);
      expect(rig.host.queue, isEmpty);

      // The plan: exactly one AlarmKit alarm, at 09:05, for all three — the
      // native record kept or replaced under its own id, never a second one.
      final held = await rig.host.scheduledAlarms();
      expect(held, hasLength(1));
      expect(held.single.id, groupAt905);
      expect(held.single.members, members);
      expect(held.single.fireAtMs, fiveAfter.millisecondsSinceEpoch);
      expect(rig.host.maxRowsInOneMinute, 1);
      expect(
        rig.host.scheduleCalls
            .where((a) => a.fireAt == fiveAfter)
            .map((a) => a.id)
            .toSet(),
        anyOf(isEmpty, {groupAt905}),
      );
      // The alarm that rang was stopped natively; Dart neither cancelled
      // nor re-scheduled 09:00.
      expect(rig.host.nativeStops, [groupAt9]);
      expect(rig.host.cancelled, isNot(contains(groupAt9)));
      expect(
        rig.host.scheduleCalls.where((a) => a.id == groupAt9),
        hasLength(1),
      );

      // AlarmKit holds the minute, so the notification lane never rang it.
      expect(rig.gateway.urgentEverScheduled, isEmpty);
      expect(rig.gateway.scheduled, isEmpty);
    },
  );

  test(
    'a native group snooze found on resume is held until the replica has heard of it',
    () async {
      await threeInOneMinute(nineAm);
      rig.clock = DateTime.utc(2030, 6, 1, 8, 59);
      await rig.start();

      // Pressed while the app was suspended: nothing announced it.
      rig.clock = DateTime.utc(2030, 6, 1, 9, 0, 40);
      rig.host.alerting.add(groupAt9);
      rig.host.pressSnooze(
        eventId: 'ev-resume',
        alarmId: groupAt9,
        untilMs: fiveAfter.millisecondsSinceEpoch,
        pressedAtMs: DateTime.utc(2030, 6, 1, 9, 0, 30).millisecondsSinceEpoch,
        announce: false,
      );
      // Resumed at 09:02: the resume pass reads the receipts, then its own
      // drain applies the snooze, so it plans from a replica that still says
      // 09:00. The native 09:05 alarm is not its to cancel, and the minute
      // it holds is not the notification lane's to ring.
      rig.clock = DateTime.utc(2030, 6, 1, 9, 2);
      rig.holdReplica = true;
      await rig.resume();

      expect(rig.host.acked, [
        ['ev-resume'],
      ], reason: 'the resume pass applied it');
      expect(rig.host.cancelled, isEmpty);
      expect(rig.host.stopped, isEmpty);
      expect(rig.gateway.urgentEverScheduled, isEmpty);

      // The replica's list arrives: the next pass converges.
      await rig.releaseReplica();

      final held = await rig.host.scheduledAlarms();
      expect(held.map((r) => (r.id, r.members.join(','), r.fireAtMs)), [
        (groupAt905, members.join(','), fiveAfter.millisecondsSinceEpoch),
      ]);
      expect(rig.host.maxRowsInOneMinute, 1);
      expect(rig.host.cancelled, isEmpty);
      expect(rig.host.stopped, isEmpty);
      expect(rig.host.acked, [
        ['ev-resume'],
      ]);
      expect(rig.host.ackSawCommit, [true]);
      final tasks = await rig.db.select(rig.db.tasks).get();
      expect(tasks.map((t) => t.snoozedUntil).toSet(), {fiveAfter});
      expect(rig.gateway.urgentEverScheduled, isEmpty);
    },
  );

  test('a redelivered native group snooze changes nothing', () async {
    await ringAndSnoozeNatively();
    final before = await rig.snapshot();
    final rowsBefore = await rig.host.scheduledAlarms();
    final calls = rig.host.scheduleCalls.length;
    final cancels = rig.host.cancelled.length;

    // The native queue hands the same event over again (its ack was lost).
    rig.host.redeliver('ev-group');
    await rig.settle();

    expect(await rig.snapshot(), before);
    expect(rig.host.acked, [
      ['ev-group'],
      ['ev-group'],
    ]);
    expect(rig.host.queue, isEmpty);
    final rowsAfter = await rig.host.scheduledAlarms();
    expect(rowsAfter.map((r) => (r.id, r.fp, r.fireAtMs)), [
      for (final r in rowsBefore) (r.id, r.fp, r.fireAtMs),
    ]);
    expect(rig.host.scheduleCalls, hasLength(calls));
    expect(rig.host.cancelled, hasLength(cancels));
    expect(rig.gateway.urgentEverScheduled, isEmpty);
    final applied = await rig.db.select(rig.db.alarmEvents).get();
    expect(
      applied.where((e) => e.event == AlarmLogEvent.action),
      hasLength(1),
      reason: 'one action row in the alarm log, not two',
    );
  });

  test(
    'a device that does not ring gets normal notifications for a grouped minute',
    () async {
      await threeInOneMinute(fiveAfter);
      rig.clock = DateTime.utc(2030, 6, 1, 9);

      // Rings here first: one grouped AlarmKit alarm, no notification.
      await rig.start(here: RingsUrgentHere.on);
      expect(rig.host.scheduled.keys, [groupAt905]);
      expect(rig.gateway.scheduled, isEmpty);

      // The person picks another device: this one stops ringing at once.
      rig.gate.add(RingsUrgentHere.off);
      await rig.settle();

      expect(await rig.host.scheduledAlarms(), isEmpty);
      expect(rig.host.cancelled, [groupAt905]);
      final shown = rig.gateway.scheduled.values.toList();
      expect(shown, hasLength(3), reason: 'one notification per task');
      expect(shown.map((n) => n.taskId).toSet(), members.toSet());
      expect(shown.map((n) => n.urgent).toSet(), {false});
      expect(rig.gateway.urgentEverScheduled, isEmpty);

      // No ring screen: the overlay decides on the same gate.
      rig.clock = DateTime.utc(2030, 6, 1, 9, 5, 50);
      expect(await rig.overlayRinging('off'), isEmpty);
      // The control: the same minute on a ringing device opens it.
      expect(
        (await rig.overlayRinging('on')).map((a) => a.taskId).toSet(),
        members.toSet(),
      );
    },
  );

  test('a remote acknowledge stops the alerting group alarm', () async {
    await threeInOneMinute(nineAm);
    rig.clock = DateTime.utc(2030, 6, 1, 8, 59);
    await rig.start();
    expect(rig.host.scheduled.keys, [groupAt9]);

    rig.clock = DateTime.utc(2030, 6, 1, 9, 0, 45);
    rig.host.alerting.add(groupAt9);

    // Another device acknowledged T1 only: the group still rings for T2/T3.
    await rig.syncDownAcknowledged(['R1']);
    expect(rig.host.alerting, {groupAt9});
    expect(rig.host.stopped, isEmpty);
    expect(rig.host.cancelled, isEmpty);

    // The rest arrive: the alarm is stopped, never cancelled.
    await rig.syncDownAcknowledged(['R2', 'R3']);
    expect(rig.host.stopped, [groupAt9]);
    expect(rig.host.cancelled, isEmpty);
    expect(await rig.host.scheduledAlarms(), isEmpty);
    expect(
      rig.host.scheduleCalls.map((a) => a.id),
      [groupAt9],
      reason: 'nothing re-scheduled after the stop',
    );
    expect(rig.gateway.urgentEverScheduled, isEmpty);
  });
}

/// The foreground wiring of `notificationSchedulerProvider` without Riverpod:
/// replica stream → device gate → scheduler; the AlarmKit pump on the host's
/// `actionsPending` and in the plan's drain; receipts read from the replica.
class _Rig {
  _Rig() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    tasks = TaskStore(db, () {});
    reminders = ReminderStore(db, () {});
    log = AlarmLog(db);
    host = _LedgerAlarmKitHost(db);
    gateway = _RecordingGateway();
  }

  late final AwDatabase db;
  late final TaskStore tasks;
  late final ReminderStore reminders;
  late final AlarmLog log;
  late final _LedgerAlarmKitHost host;
  late final _RecordingGateway gateway;
  StreamController<RingsUrgentHere> gate = StreamController();
  DateTime clock = nineAm;
  NotificationScheduler? _scheduler;
  AlarmKitActionPump? _pump;
  void Function()? _onResume;
  StreamSubscription<void>? _pending;
  final List<ProviderContainer> _containers = [];

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

  Future<void> start({RingsUrgentHere here = RingsUrgentHere.on}) async {
    late final NotificationScheduler scheduler;
    final pump = AlarmKitActionPump(
      host: host,
      log: log,
      apply: (event) => handleNotificationEvent(
        event,
        db: db,
        tasks: tasks,
        reminders: reminders,
        log: log,
        navigate: (_) => fail('a pulled action never navigates'),
        onCommitted: (eventId) => scheduler.noteEventApplied(eventId),
      ),
    );
    gate = StreamController<RingsUrgentHere>()..add(here);
    scheduler = NotificationScheduler(
      gateway: gateway,
      alarmKit: host,
      alarms: gateAlarms(
        _holdable(reminders.watchAlarmsIn(scope)),
        gate.stream,
      ),
      privacyMode: false,
      log: log,
      drainActions: pump.beforePlan,
      afterPlan: pump.afterPlan,
      appliedEventIds: () async => {
        for (final r in await db.select(db.actionReceipts).get()) r.eventId,
      },
      clock: () => clock,
      onForeground: (onResume) {
        _onResume = onResume;
        return () => _onResume = null;
      },
    );
    _pump = pump;
    _scheduler = scheduler;
    await scheduler.start();
    _pending = host.actionsPending.listen((_) => unawaited(pump.pull()));
    await settle();
  }

  /// Lets the replica stream, the pump and every re-plan run to quiet.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await pumpEventQueue(times: 40);
    }
  }

  /// The server's rows as a pull applies them: the reminder acknowledged
  /// on another device.
  Future<void> syncDownAcknowledged(List<String> reminderIds) async {
    final rows = await db.select(db.reminders).get();
    await applyPulledChanges(
      db,
      workspaceId: ws,
      toRevision: 2,
      changes: [
        for (final r in rows)
          if (reminderIds.map(id).contains(r.id))
            SyncChange(
              revision: 2,
              entityType: 'reminder',
              entityId: r.id,
              operation: 'update',
              data: {
                'id': r.id,
                'taskId': r.taskId,
                'kind': r.kind,
                'remindAt': r.remindAt.toIso8601String(),
                'alarmLevel': r.alarmLevel,
                'requiresAcknowledgement': r.requiresAcknowledgement,
                'status': 'acknowledged',
                'acknowledgedAt': clock.toIso8601String(),
                'revision': 2,
              },
            ),
      ],
    );
    await settle();
  }

  /// The replica's state a redelivery must leave alone.
  Future<List<Object?>> snapshot() async => [
    for (final t in await db.select(db.tasks).get()) (t.id, t.snoozedUntil),
    for (final r in await db.select(db.reminders).get())
      (r.id, r.status, r.snoozedUntil, r.snoozeCount),
    (await db.select(db.pendingMutations).get()).length,
    [for (final r in await db.select(db.actionReceipts).get()) r.eventId],
  ];

  /// What the ring screen shows at [clock] on a device whose stored answer
  /// is [stored], from this replica.
  Future<List<AlarmInput>> overlayRinging(String stored) async {
    final kv = _MemoryKv()..values[kRingsUrgentKey] = stored;
    final container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(alarmOverlayAutoShow: true),
        alarmFeedProvider.overrideWith((ref) => reminders.watchAlarmsIn(scope)),
        ringsUrgentStoreProvider.overrideWithValue(RingsUrgentStore(kv: kv)),
        alarmClockProvider.overrideWithValue(() => clock),
      ],
    );
    _containers.add(container);
    container.listen(alarmOverlayControllerProvider, (_, _) {});
    await container.read(ringsUrgentHereProvider.future);
    await container.read(alarmFeedProvider.future);
    await settle();
    return container.read(alarmOverlayControllerProvider).ringing;
  }

  /// While true, the replica's next list waits: drift re-runs a watched
  /// query after the commit, so a pass can plan before the list arrives.
  bool holdReplica = false;
  List<AlarmInput>? _held;
  void Function(List<AlarmInput>)? _emit;

  Stream<List<AlarmInput>> _holdable(Stream<List<AlarmInput>> source) {
    final out = StreamController<List<AlarmInput>>();
    StreamSubscription<List<AlarmInput>>? sub;
    _emit = out.add;
    out
      ..onListen = () {
        sub = source.listen((list) {
          if (holdReplica) {
            _held = list;
          } else {
            out.add(list);
          }
        }, onError: out.addError);
      }
      ..onCancel = () => sub?.cancel();
    return out.stream;
  }

  /// The held list arrives.
  Future<void> releaseReplica() async {
    holdReplica = false;
    final list = _held;
    _held = null;
    if (list != null) _emit!(list);
    await settle();
  }

  /// The app comes back to the foreground, wired as the provider wires it:
  /// the scheduler's re-plan first, then a pull.
  Future<void> resume() async {
    _onResume!();
    unawaited(_pump!.pull());
    await settle();
  }

  Future<void> dispose() async {
    for (final c in _containers) {
      c.dispose();
    }
    await _pending?.cancel();
    _scheduler?.dispose();
    await gate.close();
    await db.close();
  }
}

/// [FakeAlarmKitHost] with the App Group ledger and the native snooze of
/// NOTIFICATIONS §2b.3: `schedule` replaces any record under its id, a native
/// snooze writes an `origin: native` record carrying its event id.
class _LedgerAlarmKitHost extends FakeAlarmKitHost {
  _LedgerAlarmKitHost(this.db);

  final AwDatabase db;
  final List<AlarmKitAlarm> scheduleCalls = [];
  final List<int> nativeStops = [];

  /// Per ack: whether the event's receipt and its write were committed.
  final List<bool> ackSawCommit = [];

  /// The most rows the lane ever held for one UTC minute.
  int maxRowsInOneMinute = 0;
  final Map<String, AlarmKitActionEvent> _sent = {};

  @override
  Future<AlarmKitScheduleResult> schedule(AlarmKitAlarm alarm) async {
    scheduleCalls.add(alarm);
    foreign.remove(alarm.id); // one ledger record per id
    final result = await super.schedule(alarm);
    await _measure();
    return result;
  }

  Future<void> _measure() async {
    final perMinute = <int, int>{};
    for (final row in await scheduledAlarms()) {
      final minute = row.fireAtMs! ~/ 60000;
      perMinute[minute] = (perMinute[minute] ?? 0) + 1;
    }
    for (final n in perMinute.values) {
      if (n > maxRowsInOneMinute) maxRowsInOneMinute = n;
    }
  }

  @override
  Future<void> ackActions(List<String> eventIds) async {
    final receipts = {
      for (final r in await db.select(db.actionReceipts).get()) r.eventId,
    };
    final snoozed = (await db.select(db.tasks).get()).every(
      (t) => t.snoozedUntil != null,
    );
    ackSawCommit.add(eventIds.every(receipts.contains) && snoozed);
    await super.ackActions(eventIds);
  }

  /// Ertele on the alert of [alarmId], as `AWAlarmSnoozeIntent.perform()`
  /// does it: a target for every member, the new alarm with the same
  /// presentation, `stop` on the old one, then one queued event.
  void pressSnooze({
    required String eventId,
    required int alarmId,
    required int untilMs,
    required int pressedAtMs,
    bool announce = true,
  }) {
    final rang = scheduled[alarmId]!;
    final target = untilMs - untilMs % 1000;
    final newId = alarmKitOccurrenceId(rang.members, target);
    foreign[newId] = AlarmKitScheduled(
      id: newId,
      fp: alarmKitFingerprint(
        title: rang.title,
        body: rang.body,
        soundName: rang.soundName,
        stopLabel: rang.stopLabel,
        snoozeLabel: rang.snoozeLabel,
        snoozePreset: rang.snoozePreset,
      ),
      members: rang.members,
      fireAtMs: target,
      origin: 'native',
      eventId: eventId,
    );
    scheduled.remove(alarmId);
    alerting.remove(alarmId);
    nativeStops.add(alarmId);
    final event = AlarmKitActionEvent(
      eventId: eventId,
      action: 'snooze',
      taskIds: rang.members,
      pressedAtMs: pressedAtMs,
      untilMs: target,
      occurrenceFireAtMs: alarmKitFireAtMs(rang.fireAt),
      alarmId: alarmId,
      newId: newId,
      scheduleOutcome: 'ok',
      stopOutcome: 'stopped',
    );
    _sent[eventId] = event;
    // A suspended app hears nothing until it is resumed.
    announce ? enqueue(event) : queue.add(event);
  }

  /// The native queue hands an already-acked event over again.
  void redeliver(String eventId) => enqueue(_sent[eventId]!);
}

/// Remembers every urgent notification ever scheduled: AlarmKit holding a
/// minute means the notification lane must never have rung it too.
class _RecordingGateway extends FakeNotificationsGateway {
  final List<PlannedNotification> urgentEverScheduled = [];

  @override
  Future<ScheduledDelivery> schedule(PlannedNotification notification) {
    if (notification.urgent) urgentEverScheduled.add(notification);
    return super.schedule(notification);
  }
}

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
