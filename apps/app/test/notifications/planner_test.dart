import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/notifications/reminder_store.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm({
  String id = 'R1',
  String status = 'scheduled',
  bool urgent = false,
  bool requiresAck = false,
  DateTime? remindAt,
  DateTime? snoozedUntil,
  String title = 'Görev',
  String kind = 'remind',
  int snoozeRound = 0,
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: title,
  kind: kind,
  snoozeRound: snoozeRound,
  remindAt: remindAt ?? now.add(const Duration(hours: 1)),
  status: status,
  urgent: urgent,
  requiresAcknowledgement: requiresAck,
  snoozedUntil: snoozedUntil,
);

void main() {
  test('a normal reminder plans exactly one exact notification', () {
    final plan = planNotifications(
      alarms: [alarm(title: 'Süt al')],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(1));
    expect(plan.single.title, 'Süt al');
    expect(plan.single.urgent, isFalse);
    expect(plan.single.fireAt, now.add(const Duration(hours: 1)));
    expect(plan.single.payload, contains('"chainIndex":0'));
  });

  test('urgent+ack reminders pre-schedule the full re-alert chain', () {
    final plan = planNotifications(
      alarms: [alarm(urgent: true, requiresAck: true)],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(ReminderProfile.factory.offsets.length));
    final base = now.add(const Duration(hours: 1));
    expect(plan.map((n) => n.fireAt), [
      for (final offset in ReminderProfile.factory.offsets) base.add(offset),
    ]);
    expect(plan.first.body, contains('waiting for acknowledgement'));
    expect(plan.last.body, contains('alert 5'));
    // Urgent WITHOUT ack requirement rings once.
    expect(
      planNotifications(
        alarms: [alarm(urgent: true)],
        now: now,
        privacyMode: false,
      ),
      hasLength(1),
    );
  });

  test('snoozed alarms fire at snoozedUntil; past instants are skipped', () {
    final plan = planNotifications(
      alarms: [
        alarm(
          id: 'R1',
          status: 'snoozed',
          remindAt: now.subtract(const Duration(hours: 2)),
          snoozedUntil: now.add(const Duration(minutes: 30)),
        ),
        alarm(id: 'R2', remindAt: now.subtract(const Duration(minutes: 1))),
        alarm(id: 'R3', status: 'acknowledged'),
        alarm(id: 'R4', status: 'cancelled'),
      ],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(1));
    expect(plan.single.fireAt, now.add(const Duration(minutes: 30)));
  });

  test('windows to the soonest maxPending fire-times (iOS 64 cap)', () {
    final plan = planNotifications(
      alarms: [
        for (var i = 0; i < 60; i++)
          alarm(
            id: 'R$i',
            remindAt: now.add(Duration(minutes: 10 + i)),
          ),
      ],
      now: now,
      privacyMode: false,
    );
    expect(plan, hasLength(40));
    expect(plan.first.fireAt, now.add(const Duration(minutes: 10)));
    expect(plan.last.fireAt, now.add(const Duration(minutes: 49)));
  });

  test('privacy mode hides task titles everywhere (OPH-064)', () {
    final plan = planNotifications(
      alarms: [alarm(title: 'Çok gizli iş', urgent: true, requiresAck: true)],
      now: now,
      privacyMode: true,
    );
    for (final n in plan) {
      expect(n.title, 'AllisWell');
      expect(n.body, 'You have a reminder');
      expect(n.title.contains('gizli'), isFalse);
      // The payload still routes taps by id — content stays off the lock screen.
      expect(n.payload, isNot(contains('gizli')));
    }
  });

  test('ids are stable for identical input and change with content', () {
    List<int> ids(bool privacy) => planNotifications(
      alarms: [alarm()],
      now: now,
      privacyMode: privacy,
    ).map((n) => n.id).toList();
    expect(ids(false), ids(false)); // deterministic
    expect(ids(false), isNot(ids(true))); // content change → new identity
  });

  // OPH-175: the deadline alarm says WHY it rings. Same loudness, different
  // sentence — "the time you gave this task is now", not "a reminder".
  test('a deadline alarm reads differently from a reminder', () {
    final plan = planNotifications(
      alarms: [
        alarm(id: 'R1', urgent: true, requiresAck: true, kind: 'remind'),
        alarm(
          id: 'R2',
          urgent: true,
          requiresAck: true,
          kind: 'due',
          remindAt: now.add(const Duration(hours: 1, minutes: 3)),
        ),
      ],
      now: now,
      privacyMode: false,
    );

    final firstOfEach = {
      for (final n in plan)
        if (n.payload.contains('"chainIndex":0')) n.title + n.body: n,
    };
    final bodies = firstOfEach.values.map((n) => n.body).toList();
    expect(bodies, hasLength(2));
    expect(bodies.where((b) => b.contains('time you set')), hasLength(1));
    expect(
      bodies.where((b) => b.contains('waiting for acknowledgement')),
      hasLength(1),
    );
    // Repeats stay the shared "still waiting" wording for both.
    expect(plan.where((n) => n.body.contains('alert 2')), hasLength(2));
  });

  test('privacy mode hides which alarm it is, for both kinds', () {
    final plan = planNotifications(
      alarms: [alarm(urgent: true, kind: 'due')],
      now: now,
      privacyMode: true,
    );
    expect(plan.single.title, 'AllisWell');
    expect(plan.single.body, isNot(contains('time you set')));
  });

  // OPH-177: the post-snooze ring names its ROUND, so "it came like the 1st
  // notification again" cannot happen twice.
  test('a post-snooze ring says which round it is', () {
    final plan = planNotifications(
      alarms: [
        alarm(
          urgent: true,
          requiresAck: true,
          status: 'snoozed',
          snoozeRound: 3,
          snoozedUntil: now.add(const Duration(minutes: 5)),
        ),
      ],
      now: now,
      privacyMode: false,
    );
    expect(plan.first.body, contains('round 3'));
    // An un-counted snooze (a row from before the counter) still reads honestly.
    final legacy = planNotifications(
      alarms: [
        alarm(
          urgent: true,
          requiresAck: true,
          status: 'snoozed',
          snoozedUntil: now.add(const Duration(minutes: 5)),
        ),
      ],
      now: now,
      privacyMode: false,
    );
    expect(legacy.first.body, contains('round 1'));
  });
  group('AlarmKit occurrence identity (OPH-424, #49)', () {
    const taskId = '01JTASK0000000000000000001';
    AlarmInput urgent({
      String reminderId = '01JREM00000000000000000001',
      String title = 'Toplantı',
      DateTime? at,
      String kind = 'remind',
    }) => AlarmInput(
      reminderId: reminderId,
      taskId: taskId,
      taskTitle: title,
      kind: kind,
      remindAt: at ?? DateTime.utc(2026, 7, 16, 9),
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
    );
    AlarmKitAlarm plan(AlarmInput a) =>
        planAlarmKitAlarms(alarms: [a], now: now, privacyMode: false).single;

    test(
      'moving an urgent task from 09:00 to 10:00 changes its AlarmKit id',
      () {
        final nine = plan(urgent(at: DateTime.utc(2026, 7, 16, 9)));
        final ten = plan(urgent(at: DateTime.utc(2026, 7, 16, 10)));
        expect(nine.id, isNot(ten.id));
        expect(
          ten.id,
          alarmKitOccurrenceId([
            taskId,
          ], DateTime.utc(2026, 7, 16, 10).millisecondsSinceEpoch),
        );
        expect(ten.members, [taskId]);
      },
    );

    test(
      'a renamed task keeps its AlarmKit id and changes only its fingerprint',
      () {
        final before = plan(urgent(title: 'Toplantı'));
        final after = plan(urgent(title: 'Toplantı (ertelendi)'));
        expect(after.id, before.id);
        expect(after.fp, isNot(before.fp));
        // Sound, labels and preset are presentation too.
        AlarmKitAlarm withSound(String? s) => planAlarmKitAlarms(
          alarms: [urgent()],
          now: now,
          privacyMode: false,
          soundName: s,
        ).single;
        expect(withSound('aw_chime.caf').id, withSound(null).id);
        expect(withSound('aw_chime.caf').fp, isNot(withSound(null).fp));
        AlarmKitAlarm withPreset(String p) => planAlarmKitAlarms(
          alarms: [urgent()],
          now: now,
          privacyMode: false,
          snoozePreset: p,
        ).single;
        expect(withPreset('30_min').id, withPreset('5_min').id);
        expect(withPreset('30_min').fp, isNot(withPreset('5_min').fp));
      },
    );

    test(
      'a synthetic alarm and its synced reminder row share one AlarmKit id',
      () {
        final synthetic = plan(
          urgent(reminderId: syntheticReminderId('remind', taskId)),
        );
        final synced = plan(urgent(reminderId: '01JREM00000000000000000009'));
        expect(synced.id, synthetic.id);
        expect(synced.fp, synthetic.fp);
      },
    );

    test('remind and due of one task at one instant are one alarm', () {
      final out = planAlarmKitAlarms(
        alarms: [
          urgent(),
          urgent(reminderId: '01JREM00000000000000000002', kind: 'due'),
        ],
        now: now,
        privacyMode: false,
      );
      expect(out, hasLength(1));
      // Both rows are covered, so neither keeps a notification chain.
      final covered = {for (final a in out) ...a.reminderIds};
      expect(covered, {
        '01JREM00000000000000000001',
        '01JREM00000000000000000002',
      });
      expect(
        planNotifications(
          alarms: [
            urgent(),
            urgent(reminderId: '01JREM00000000000000000002', kind: 'due'),
          ],
          now: now,
          privacyMode: false,
          alarmKitReminderIds: covered,
        ),
        isEmpty,
      );
    });

    test('the bridge gets members, fp and a second-floored fireAtMs', () {
      final at = DateTime.utc(2026, 7, 16, 9, 0, 0, 750);
      final args = plan(urgent(at: at)).toArgs();
      expect(args['fireAtMs'], at.millisecondsSinceEpoch - 750);
      expect(args['members'], [taskId]);
      expect(args['taskId'], taskId);
      expect(args['fp'], isA<int>());
      expect(
        args['id'],
        alarmKitOccurrenceId([taskId], at.millisecondsSinceEpoch - 750),
      );
    });
  });

  group('one alarm per UTC minute (OPH-440, #47)', () {
    final nine = DateTime.utc(2026, 7, 16, 9);
    AlarmInput urgent(
      String task, {
      String? reminder,
      DateTime? at,
      String kind = 'remind',
      String title = 'Görev',
    }) => AlarmInput(
      reminderId: reminder ?? 'REM-$task',
      taskId: task,
      taskTitle: '$title $task',
      kind: kind,
      remindAt: at ?? nine,
      status: 'scheduled',
      urgent: true,
      requiresAcknowledgement: true,
    );
    Map<String, Object?> payloadOf(PlannedNotification n) =>
        (jsonDecode(n.payload) as Map).cast<String, Object?>();

    // ADR-0068 (#47): a pass in the middle of a minute that already started
    // ringing at its first member's second plans nothing at a later member's
    // own second — the chain re-alerts from the minute's first instant.
    test('a pass inside a ringing minute plans no notification at a later '
        'member\'s own second', () {
      final a = urgent('TA', at: nine.add(const Duration(seconds: 11)));
      final b = urgent('TB', at: nine.add(const Duration(seconds: 32)));
      final plan = planNotifications(
        alarms: [a, b],
        now: nine.add(const Duration(seconds: 20)),
        privacyMode: false,
      );
      expect(plan, isNotEmpty); // the minute's later re-alerts
      for (final n in plan) {
        expect(n.fireAt, isNot(b.remindAt));
        expect(
          n.fireAt.difference(a.remindAt).inSeconds % 60,
          0,
          reason: 'every slot counts from the minute\'s first instant',
        );
      }
    });

    test(
      'urgent alarms sharing a minute become one AlarmKit alarm with every task id',
      () {
        final inputs = [
          urgent('TASK3', at: nine.add(const Duration(seconds: 40))),
          urgent(
            'TASK1',
            at: nine.add(const Duration(seconds: 12, milliseconds: 500)),
          ),
          urgent('TASK2', at: nine.add(const Duration(seconds: 59))),
          // Another minute: its own alarm, exactly as before grouping.
          urgent('TASK4', at: nine.add(const Duration(minutes: 1))),
        ];
        final out = planAlarmKitAlarms(
          alarms: inputs,
          now: now,
          privacyMode: false,
        );
        expect(out, hasLength(2));
        final group = out.first;
        expect(group.members, ['TASK1', 'TASK2', 'TASK3']);
        final fireAtMs = nine
            .add(const Duration(seconds: 12))
            .millisecondsSinceEpoch;
        expect(group.toArgs()['fireAtMs'], fireAtMs);
        expect(group.id, alarmKitOccurrenceId(group.members, fireAtMs));
        expect(group.title, '3 urgent alarms');
        for (final t in ['TASK1', 'TASK2', 'TASK3']) {
          expect(group.body, isNot(contains(t)));
        }
        expect(group.taskId, 'TASK1');
        expect(group.reminderIds.toSet(), {
          'REM-TASK1',
          'REM-TASK2',
          'REM-TASK3',
        });

        // A lone alarm keeps its OPH-424 id and its own title.
        final lone = out.last;
        expect(lone.members, ['TASK4']);
        expect(
          lone.id,
          alarmKitOccurrenceId([
            'TASK4',
          ], nine.add(const Duration(minutes: 1)).millisecondsSinceEpoch),
        );
        expect(lone.title, 'Görev TASK4');
        expect(
          lone.id,
          planAlarmKitAlarms(
            alarms: [inputs.last],
            now: now,
            privacyMode: false,
          ).single.id,
        );

        // Privacy mode names nothing, not even the count's tasks.
        final private = planAlarmKitAlarms(
          alarms: inputs,
          now: now,
          privacyMode: true,
        ).first;
        expect(private.title, 'AllisWell');
        expect(private.id, group.id);
      },
    );

    test('urgent alarms sharing a minute become one notification chain', () {
      final inputs = [
        urgent('TASK2', at: nine.add(const Duration(seconds: 30))),
        urgent('TASK1'),
        urgent('TASK3', at: nine.add(const Duration(seconds: 59))),
      ];
      final lone = urgent('TASK4', at: nine.add(const Duration(hours: 1)));
      final normal = AlarmInput(
        reminderId: 'REM-N',
        taskId: 'TASK5',
        taskTitle: 'Süt al',
        remindAt: nine,
        status: 'scheduled',
        urgent: false,
        requiresAcknowledgement: false,
      );
      final plan = planNotifications(
        alarms: [...inputs, lone, normal],
        now: now,
        privacyMode: false,
      );
      final slots = ReminderProfile.factory.offsets.length;
      final group = plan
          .where(
            (n) =>
                n.urgent &&
                n.fireAt.isBefore(nine.add(const Duration(hours: 1))),
          )
          .toList();
      expect(group, hasLength(slots), reason: 'one chain, not three');
      expect(group.map((n) => n.fireAt), [
        for (final o in ReminderProfile.factory.offsets) nine.add(o),
      ]);
      for (final (i, n) in group.indexed) {
        final p = payloadOf(n);
        expect(p['taskIds'], ['TASK1', 'TASK2', 'TASK3']);
        expect((p['reminderIds'] as List).toSet(), {
          'REM-TASK1',
          'REM-TASK2',
          'REM-TASK3',
        });
        expect(p['taskId'], 'TASK1');
        expect(p['chainIndex'], i);
        // IDs only: nothing a task says rides in the payload.
        expect(n.payload, isNot(contains('Görev')));
        expect(n.title, contains('3 urgent alarms'));
        expect(n.body, isNot(contains('Görev')));
      }
      expect(group.first.body, contains('3 urgent alarms'));
      expect(group.map((n) => n.id).toSet(), hasLength(slots));

      // The normal reminder in the same minute keeps its own notification.
      expect(plan.where((n) => !n.urgent).single.title, 'Süt al');
      // A lone urgent alarm keeps today's ids and payload (no churn).
      final alone = planNotifications(
        alarms: [lone],
        now: now,
        privacyMode: false,
      );
      final loneSlots = plan
          .where((n) => n.urgent && !n.fireAt.isBefore(lone.remindAt))
          .toList();
      expect(loneSlots.map((n) => n.id), alone.map((n) => n.id));
      expect(payloadOf(alone.first).keys, {
        'taskId',
        'reminderId',
        'chainIndex',
      });
    });

    test(
      'a task appearing twice in a minute (remind and due) is one member',
      () {
        final remind = urgent('TASK1', reminder: 'REM-R');
        final due = urgent(
          'TASK1',
          reminder: 'REM-D',
          kind: 'due',
          at: nine.add(const Duration(seconds: 30)),
        );
        final kit = planAlarmKitAlarms(
          alarms: [remind, due],
          now: now,
          privacyMode: false,
        );
        expect(kit, hasLength(1));
        expect(kit.single.members, ['TASK1']);
        expect(
          kit.single.title,
          'Görev TASK1',
          reason: 'one member, its title',
        );
        expect(kit.single.reminderIds.toSet(), {'REM-R', 'REM-D'});
        expect(
          kit.single.id,
          alarmKitOccurrenceId(['TASK1'], nine.millisecondsSinceEpoch),
        );

        // With a second task it is a group of two, not three.
        final withOther = planAlarmKitAlarms(
          alarms: [remind, due, urgent('TASK2')],
          now: now,
          privacyMode: false,
        ).single;
        expect(withOther.members, ['TASK1', 'TASK2']);
        expect(withOther.title, '2 urgent alarms');

        final chain = planNotifications(
          alarms: [remind, due],
          now: now,
          privacyMode: false,
        );
        expect(chain, hasLength(ReminderProfile.factory.offsets.length));
        expect(chain.first.title, contains('Görev TASK1'));
        final p = payloadOf(chain.first);
        expect(p['taskId'], 'TASK1');
        expect((p['reminderIds'] as List).toSet(), {'REM-R', 'REM-D'});
      },
    );
  });
}
