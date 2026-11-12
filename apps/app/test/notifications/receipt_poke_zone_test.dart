import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_api.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

import '../sync/sync_engine_test.dart' show FakeSyncApi, taskSnapshot;

const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// A receipted alarm action (OPH-427) writes inside its receipt transaction.
/// A store that poked sync from in there armed the engine's debounce in
/// drift's transaction zone; on the remote executor of a release build the
/// round then waited on the closed transaction forever and every later round
/// only queued behind it (a ring-list action stopped sync until a reload).
/// The real stores, a real engine and a fake API: the
/// applier pokes once, after the commit, and the push lands.
void main() {
  late AwDatabase db;
  late _RecordingApi api;
  late SyncEngine engine;
  late TaskStore tasks;
  late ReminderStore reminders;
  late List<bool> pokeInTransaction;
  final due = DateTime.now().toUtc().subtract(const Duration(seconds: 20));

  setUp(() async {
    db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
    api = _RecordingApi(db);
    engine = SyncEngine(
      db: db,
      api: api,
      workspaceId: ws,
      debounce: const Duration(milliseconds: 5),
    );
    pokeInTransaction = [];
    void poke() {
      pokeInTransaction.add(db.inTransactionZone);
      engine.notifyLocalWrite();
    }

    tasks = TaskStore(db, poke);
    reminders = ReminderStore(db, poke);
    for (final t in ['T1', 'T2']) {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: id(t),
              workspaceId: ws,
              title: 'Acil $t',
              isUrgent: const Value(true),
              requiresAcknowledgement: const Value(true),
              remindAt: Value(due),
            ),
          );
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              id: id('R$t'),
              taskId: id(t),
              remindAt: due,
              alarmLevel: const Value('urgent'),
              requiresAcknowledgement: const Value(true),
            ),
          );
    }
    await engine.start();
    api.pushedBatches.clear();
    api.roundInTransaction.clear();
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  Future<bool> apply(NotificationEvent event) => handleNotificationEvent(
    event,
    tasks: tasks,
    reminders: reminders,
    navigate: (_) {},
    db: db,
  );

  NotificationEvent inApp(
    String eventId,
    String action, {
    int? untilMs,
    DateTime? occurrence,
  }) => NotificationEvent(
    eventId: eventId,
    actionId: action,
    taskIds: [id('T1'), id('T2')],
    untilMs: untilMs,
    occurrenceFireAtMs: (occurrence ?? due).millisecondsSinceEpoch,
    origin: 'inapp',
  );

  Future<List<PendingMutation>> outbox() =>
      db.select(db.pendingMutations).get();

  test('a receipted group snooze pokes sync outside the transaction and the '
      'push lands', () async {
    final until = DateTime.now().toUtc().add(const Duration(minutes: 5));
    expect(
      await apply(
        inApp(
          '01EVAAAAAAAAAAAAAAAAAAAAAA',
          'snooze',
          untilMs: until.millisecondsSinceEpoch,
        ),
      ),
      isTrue,
    );
    // One poke for the whole event, after its transaction committed.
    expect(pokeInTransaction, [false]);
    await settle();
    expect(api.pushedBatches, hasLength(1));
    expect(api.pushedBatches.single, hasLength(2));
    expect(await outbox(), isEmpty);
    expect(api.roundInTransaction, everyElement(isFalse));
  });

  test('a receipted acknowledge, complete and mute each poke once, after '
      'the commit, and push', () async {
    final events = [
      inApp('01EVBBBBBBBBBBBBBBBBBBBBBB', kActionAcknowledge),
      inApp('01EVCCCCCCCCCCCCCCCCCCCCCC', kActionMute),
      inApp('01EVDDDDDDDDDDDDDDDDDDDDDD', kActionComplete),
    ];
    for (final (i, event) in events.indexed) {
      expect(await apply(event), isTrue);
      expect(pokeInTransaction, List.filled(i + 1, false));
      await settle();
      expect(api.pushedBatches, hasLength(i + 1), reason: event.actionId);
      expect(await outbox(), isEmpty, reason: event.actionId);
    }
    // The acknowledge answered both members' reminders of the minute.
    final acked = await (db.select(
      db.reminders,
    )..where((r) => r.status.equals('acknowledged'))).get();
    expect(acked, hasLength(2));
    expect(api.roundInTransaction, everyElement(isFalse));
  });

  test('a redelivered event pokes nothing', () async {
    final event = inApp('01EVEEEEEEEEEEEEEEEEEEEEEE', kActionAcknowledge);
    expect(await apply(event), isTrue);
    expect(await apply(event), isFalse);
    expect(pokeInTransaction, [false]);
  });

  test('a pulled AlarmKit action takes the same path', () async {
    final event = notificationEventForAlarmKit(
      AlarmKitActionEvent(
        eventId: '01EVFFFFFFFFFFFFFFFFFFFFFF',
        action: 'snooze',
        taskIds: [id('T1'), id('T2')],
        untilMs: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        occurrenceFireAtMs: due.millisecondsSinceEpoch,
        pressedAtMs: DateTime.now().millisecondsSinceEpoch,
        origin: 'native',
      ),
    );
    expect(await apply(event), isTrue);
    expect(pokeInTransaction, [false]);
    await settle();
    expect(api.pushedBatches, hasLength(1));
    expect(await outbox(), isEmpty);
  });

  test('after a receipted action a later write still pushes and a pull '
      'still applies', () async {
    final until = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await apply(
      inApp(
        '01EVGGGGGGGGGGGGGGGGGGGGGG',
        'snooze',
        untilMs: until.millisecondsSinceEpoch,
      ),
    );
    await settle();
    // The snoozed minute rings and is answered.
    await apply(
      inApp(
        '01EVHHHHHHHHHHHHHHHHHHHHHH',
        kActionAcknowledge,
        occurrence: until,
      ),
    );
    await settle();
    expect(api.pushedBatches, hasLength(2));

    // A plain write afterwards: the engine is not stuck in a dead round.
    await tasks.update(id('T1'), {'title': 'Sonra'});
    await settle();
    expect(api.pushedBatches, hasLength(3));
    expect(await outbox(), isEmpty);

    // A pull still lands its page.
    final state = await db.select(db.syncStates).getSingle();
    api.pullPages.add(
      SyncPullPage(
        fromRevision: state.lastRevision,
        toRevision: state.lastRevision + 1,
        hasMore: false,
        changes: [
          SyncChange(
            revision: state.lastRevision + 1,
            entityType: 'task',
            entityId: id('T9'),
            operation: 'create',
            data: taskSnapshot(id('T9'), title: 'Sunucudan'),
          ),
        ],
      ),
    );
    expect(await engine.syncNow().timeout(const Duration(seconds: 5)), isTrue);
    final pulled = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id('T9')))).getSingle();
    expect(pulled.title, 'Sunucudan');
    expect(api.roundInTransaction, everyElement(isFalse));
    expect(jsonEncode(pokeInTransaction), jsonEncode([false, false, false]));
  });
}

/// Records whether each push and pull ran inside a drift transaction.
class _RecordingApi extends FakeSyncApi {
  _RecordingApi(this.db);

  final AwDatabase db;
  final List<bool> roundInTransaction = [];

  void _note() => roundInTransaction.add(db.inTransactionZone);

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) {
    _note();
    return super.pull(workspaceId, sinceRevision: sinceRevision, limit: limit);
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) {
    _note();
    return super.push(
      clientId: clientId,
      workspaceId: workspaceId,
      baseRevision: baseRevision,
      mutations: mutations,
    );
  }
}
