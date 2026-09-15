import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/app_liveness.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/notifications/headless.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

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
}

/// A store that remembers nothing — the ordinary "app is not running" state.
class _NeverKv implements LocalKv {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
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
}
