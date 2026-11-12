import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/app_liveness.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/features/devices/providers.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/notifications/headless.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../support/fake_notifications.dart';
import '../support/sync_overrides.dart';

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// OPH-321 — the gate of the headless refresh.
///
/// A background turn schedules OS alarms while the app is not running, and the
/// notification id is a hash of the rendered text. Two things therefore have to
/// hold, and neither is visible from any other test:
///
/// 1. The headless reader and the live app must see the SAME alarms. Two
///    implementations of "which alarms exist" is how a background turn ends up
///    scheduling something the app would not have — and then cancelling
///    nothing, because the ids do not match.
/// 2. The headless isolate must boot i18n. An unbooted catalogue renders keys,
///    the hash changes, and the user gets every alarm twice.
void main() {
  late AwDatabase db;
  late ReminderStore store;

  final now = DateTime.utc(2030, 6, 1, 9);

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = ReminderStore(db, () {});
  });

  tearDown(() => db.close());

  Future<void> seedTask({
    required String tid,
    DateTime? remindAt,
    DateTime? dueAt,
    bool urgent = false,
    String status = 'open',
    DateTime? alarmsMutedAt,
  }) => db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id(tid),
          workspaceId: ws,
          title: 'Görev $tid',
          status: Value(status),
          isUrgent: Value(urgent),
          requiresAcknowledgement: Value(urgent),
          remindAt: Value(remindAt),
          dueAt: Value(dueAt),
          alarmsMutedAt: Value(alarmsMutedAt),
        ),
      );

  Future<void> seedReminder({
    required String rid,
    required String tid,
    required DateTime remindAt,
    String kind = 'remind',
    String status = 'scheduled',
    bool urgent = false,
  }) => db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          id: id(rid),
          taskId: id(tid),
          kind: Value(kind),
          remindAt: remindAt,
          status: Value(status),
          alarmLevel: Value(urgent ? 'urgent' : 'normal'),
          requiresAcknowledgement: Value(urgent),
        ),
      );

  /// Everything a real replica has at once: a synced row, a task still waiting
  /// for one, a task that owns TWO alarm kinds, and two that must produce none.
  Future<void> seedMixedReplica() async {
    await seedTask(tid: 'T1', remindAt: now.add(const Duration(minutes: 10)));
    await seedReminder(
      rid: 'R1',
      tid: 'T1',
      remindAt: now.add(const Duration(minutes: 10)),
    );
    await seedTask(tid: 'T2', remindAt: now.add(const Duration(hours: 1)));
    await seedTask(
      tid: 'T3',
      remindAt: now.add(const Duration(hours: 2)),
      dueAt: now.add(const Duration(hours: 3)),
      urgent: true,
    );
    await seedTask(
      tid: 'T4',
      remindAt: now.add(const Duration(hours: 4)),
      alarmsMutedAt: now,
    );
    await seedTask(
      tid: 'T5',
      remindAt: now.add(const Duration(hours: 5)),
      status: 'completed',
    );
  }

  List<PlannedNotification> plan(List<AlarmInput> alarms) =>
      planNotifications(alarms: alarms, now: now, privacyMode: false);

  test('the headless reader and the live app see the same alarms', () async {
    await seedMixedReplica();

    final live = await store.watchAlarms(ws).first;
    final headless = await store.readAlarms(ws);

    Set<String> keys(List<AlarmInput> alarms) => {
      for (final a in alarms) '${a.reminderId}|${a.kind}|${a.remindAt}',
    };

    expect(keys(headless), keys(live));
    // Four alarms: T1's synced row, T2's stand-in, and T3's two kinds. The
    // muted and completed tasks produce none.
    expect(headless, hasLength(4));
  });

  test('...and therefore schedule the identical notification ids', () async {
    await seedMixedReplica();

    final live = plan(await store.watchAlarms(ws).first);
    final headless = plan(await store.readAlarms(ws));

    // The id is what cancellation and replacement are keyed on. If these two
    // sets differ by one entry, a background turn adds an alarm the app will
    // never cancel and the user is told twice.
    expect({for (final p in headless) p.id}, {for (final p in live) p.id});
    expect(headless, isNotEmpty);
  });

  test(
    'an unbooted catalogue would schedule everything under new ids',
    () async {
      await seedMixedReplica();
      final alarms = await store.readAlarms(ws);
      final booted = {for (final p in plan(alarms)) p.id};

      // Exactly the state a background isolate is in before `AwI18n.boot()`:
      // `.tr()` answers with keys, so every rendered title changes and so does
      // every hash. This is why that call is the first line of the headless
      // entry and not a nicety.
      AwI18n.instance.forgetForTest();
      addTearDown(
        () => AwI18n.instance.loadForTest(
          const Locale('tr'),
          also: const [Locale('en')],
        ),
      );
      final unbooted = {for (final p in plan(alarms)) p.id};

      expect(unbooted.intersection(booted), isEmpty);
      expect(unbooted, hasLength(booted.length));
    },
  );

  test(
    "a member's alarms: the same set both ways, and only their own",
    () async {
      // In an organisation's workspaces the alarms are the person's work, not
      // every task of the unit on screen — a colleague's reminder rang on every
      // phone that had that unit open. The headless read must draw the same
      // line as the live one, or the background turn schedules what the app
      // would never have.
      const me = '01USERMEAAAAAAAAAAAAAAAAAA';
      const colleague = '01USERCOLLEAGUEAAAAAAAAAAA';
      const unitB = '01WSUNITBBBBBBBBBBBBBBBBBB';
      Future<void> task(
        String tid,
        String unit, {
        required String createdBy,
        String? assignee,
      }) async {
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: id(tid),
                workspaceId: unit,
                title: 'Görev $tid',
                remindAt: Value(now.add(const Duration(hours: 1))),
                createdBy: Value(createdBy),
              ),
            );
        if (assignee == null) return;
        await db
            .into(db.taskAssignments)
            .insert(
              TaskAssignmentsCompanion.insert(
                id: id('A$tid'),
                workspaceId: unit,
                taskId: id(tid),
                userId: assignee,
              ),
            );
      }

      await task('MINE', ws, createdBy: colleague, assignee: me);
      await task('MADE', unitB, createdBy: me);
      await task('THEIRS', ws, createdBy: me, assignee: colleague);
      await task('TEAM', unitB, createdBy: colleague);
      final scope = TaskScope.mine([ws, unitB], me);

      final live = await store.watchAlarmsIn(scope).first;
      final headless = await store.readAlarmsIn(scope);

      expect({for (final a in headless) a.taskId}, {id('MINE'), id('MADE')});
      expect(
        {for (final a in live) a.taskId},
        {for (final a in headless) a.taskId},
      );
    },
  );

  test('the headless turn boots i18n before it can schedule anything', () async {
    // The literal negative control the contract asks for: delete
    // `AwI18n.boot()` from `headless.dart` and this goes red. Everything after
    // the boot is skipped here (no session on a VM), which is the point — the
    // boot has to happen BEFORE anything can decline.
    AwI18n.instance.forgetForTest();
    addTearDown(
      () => AwI18n.instance.loadForTest(
        const Locale('tr'),
        also: const [Locale('en')],
      ),
    );
    expect(
      'notif.dueNow'.tr(),
      'notif.dueNow',
    ); // keys, because nothing is loaded

    await runHeadlessRefresh(
      openDatabase: () => db,
      liveness: AppLiveness(_NeverKv()),
    );

    expect('notif.dueNow'.tr(), isNot('notif.dueNow'));
  });

  test('a turn declines outright while the app is in the foreground', () async {
    // OPH-318's stamp, used for the first time. Nothing else may happen: the
    // running app is already syncing this replica.
    AwI18n.instance.forgetForTest();
    addTearDown(
      () => AwI18n.instance.loadForTest(
        const Locale('tr'),
        also: const [Locale('en')],
      ),
    );

    await runHeadlessRefresh(
      openDatabase: () => db,
      liveness: AppLiveness(_ForegroundKv()),
    );

    // It returned before even booting i18n, which is the cheapest possible
    // proof that it did nothing at all.
    expect('notif.dueNow'.tr(), 'notif.dueNow');
  });

  group('the device gate (OPH-452)', deviceGateTests);
}

/// OPH-452 (#48): the headless turn and the foreground scheduler apply the
/// same device gate, and the headless turn keeps the Android active-notification
/// reconcile (OPH-445).
void deviceGateTests() {
  late ProviderContainer container;
  late FakeNotificationsGateway foreground;
  late _MemoryKv kv;

  // The scheduler reads the wall clock, so the replica is seeded around it.
  final base = DateTime.now().toUtc();

  setUp(() {
    foreground = FakeNotificationsGateway();
    kv = _MemoryKv();
    container = ProviderContainer(
      overrides: [
        ...syncTestOverrides(notificationsGateway: foreground),
        taskScopeProvider.overrideWith((ref) async => TaskScope.workspace(ws)),
        ringsUrgentStoreProvider.overrideWithValue(RingsUrgentStore(kv: kv)),
      ],
    );
  });

  tearDown(() => container.dispose());

  AwDatabase replica() => container.read(databaseProvider);

  /// An urgent task with a synced urgent reminder, and an ordinary one.
  Future<void> seed() async {
    final db = replica();
    for (final (tid, urgent, after) in [
      ('U1', true, const Duration(hours: 2)),
      ('N1', false, const Duration(hours: 3)),
    ]) {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id(tid),
              workspaceId: ws,
              title: 'Görev $tid',
              isUrgent: Value(urgent),
              requiresAcknowledgement: Value(urgent),
              remindAt: Value(base.add(after)),
            ),
          );
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: id('R$tid'),
              taskId: id(tid),
              remindAt: base.add(after),
              alarmLevel: Value(urgent ? 'urgent' : 'normal'),
              requiresAcknowledgement: Value(urgent),
            ),
          );
    }
  }

  /// The foreground's plan once it has settled on the OS.
  Future<Map<int, PlannedNotification>> foregroundPlan() async {
    final sub = container.listen(notificationSchedulerProvider, (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (foreground.scheduled.isNotEmpty) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Map.of(foreground.scheduled);
  }

  Future<FakeNotificationsGateway> headlessPlan() async {
    final gateway = FakeNotificationsGateway();
    await rearmAlarmsFromReplica(
      replica(),
      scope: TaskScope.workspace(ws),
      gateway: gateway,
      kv: kv,
    );
    return gateway;
  }

  Set<(String, bool)> lanes(Iterable<PlannedNotification> plan) => {
    for (final n in plan) (n.payload, n.urgent),
  };

  for (final here in [...RingsUrgentHere.values, null]) {
    test(
      'headless applies the same device gate as the foreground (${here?.name ?? 'nothing stored'})',
      () async {
        if (here != null) await kv.set(kRingsUrgentKey, here.name);
        await seed();

        final live = await foregroundPlan();
        final headless = await headlessPlan();

        expect(live, isNotEmpty);
        expect(headless.scheduled.keys.toSet(), live.keys.toSet());
        expect(lanes(headless.scheduled.values), lanes(live.values));
        // On and legacy (a stored "legacy" or nothing stored) ring as before.
        final rings =
            here != RingsUrgentHere.off && here != RingsUrgentHere.unknown;
        expect(live.values.any((n) => n.urgent), rings);
      },
    );
  }

  test(
    'an off device still schedules the reminder as a normal notification',
    () async {
      await kv.set(kRingsUrgentKey, RingsUrgentHere.off.name);
      await seed();

      final headless = await headlessPlan();

      final urgentTask = [
        for (final n in headless.scheduled.values)
          if (n.payload.contains(id('RU1'))) n,
      ];
      // Same reminder, same time: it only stops ringing.
      expect(urgentTask, isNotEmpty);
      expect(urgentTask.every((n) => !n.urgent), isTrue);
      expect(
        urgentTask.map((n) => n.fireAt),
        contains(base.add(const Duration(hours: 2))),
      );
    },
  );

  test('a reused wake isolate re-reads the gate the foreground changed, '
      'both ways', () async {
    await seed();
    // The Android wake isolate lives as long as the process and keeps the
    // preferences copy it loaded first.
    final disk = <String, String>{kRingsUrgentKey: RingsUrgentHere.off.name};
    final isolate = _IsolateKv(disk);
    Future<FakeNotificationsGateway> wake() async {
      final gateway = FakeNotificationsGateway();
      await rearmAlarmsFromReplica(
        replica(),
        scope: TaskScope.workspace(ws),
        gateway: gateway,
        kv: isolate,
        refreshKv: isolate.reload,
      );
      return gateway;
    }

    expect((await wake()).scheduled.values.any((n) => n.urgent), isFalse);

    // The foreground turned this device on; the server's answer is on disk.
    disk[kRingsUrgentKey] = RingsUrgentHere.on.name;
    expect((await wake()).scheduled.values.any((n) => n.urgent), isTrue);

    // And off again: the wake must not put the urgent alarms back.
    disk[kRingsUrgentKey] = RingsUrgentHere.off.name;
    expect((await wake()).scheduled.values.any((n) => n.urgent), isFalse);
    expect(isolate.reloads, 3);
  });

  test('headless turn runs the active-notification reconcile', () async {
    await seed();
    // An urgent alarm that rang here and was acknowledged on another device:
    // the sync took it out of the replica, its notification is still on screen.
    final gateway = FakeNotificationsGateway()
      ..active[77] = const ActiveAlarmNotification(
        id: 77,
        urgent: true,
        reminderIds: ['01GONEAAAAAAAAAAAAAAAAAAAA'],
      );

    await rearmAlarmsFromReplica(
      replica(),
      scope: TaskScope.workspace(ws),
      gateway: gateway,
      kv: kv,
    );

    expect(gateway.cancelled, contains(77));
    expect(gateway.active, isEmpty);
  });

  test(
    'turning the switch on re-plans the foreground without a restart',
    () async {
      await kv.set(kRingsUrgentKey, RingsUrgentHere.off.name);
      await seed();
      final before = await foregroundPlan();
      expect(before.values.any((n) => n.urgent), isFalse);

      await kv.set(kRingsUrgentKey, RingsUrgentHere.on.name);
      container.invalidate(ringsUrgentHereProvider);
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (foreground.scheduled.values.any((n) => n.urgent)) break;
      }

      expect(foreground.scheduled.values.any((n) => n.urgent), isTrue);
    },
  );
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

/// One process's preferences seen from the wake isolate: the copy it loaded
/// first, until a reload reads the file another isolate wrote.
class _IsolateKv implements LocalKv {
  _IsolateKv(this._disk);

  final Map<String, String> _disk;
  Map<String, String>? _cache;
  var reloads = 0;

  Map<String, String> get _view => _cache ??= Map.of(_disk);

  Future<void> reload() async {
    reloads++;
    _cache = Map.of(_disk);
  }

  @override
  Future<String?> get(String key) async => _view[key];

  @override
  Future<void> set(String key, String value) async {
    _view[key] = value;
    _disk[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _view.remove(key);
    _disk.remove(key);
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    for (final key in _view.keys.where(test).toList()) {
      await remove(key);
    }
  }
}

/// A store that remembers nothing — the ordinary "app is not running" state.
class _NeverKv implements LocalKv {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeWhere(bool Function(String key) test) async {}
}

/// A store holding a foreground stamp from a minute ago.
///
/// A minute rather than "now": the turn captures its clock BEFORE reading the
/// store, so a stamp minted during the read is in the future, and
/// [AppLiveness.isForeground] rightly refuses to believe those.
class _ForegroundKv implements LocalKv {
  @override
  Future<String?> get(String key) async => DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 1))
      .toIso8601String();

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeWhere(bool Function(String key) test) async {}
}
