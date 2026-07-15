import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

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
}
