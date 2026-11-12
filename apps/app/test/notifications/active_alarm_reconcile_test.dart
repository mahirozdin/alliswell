import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/gateway_local.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/scheduler.dart';

/// OPH-445 (#48 gap A): a delivered urgent notification on Android loops its
/// sound (FLAG_INSISTENT) until it is cancelled. The scheduler's set-diff only
/// sees PENDING requests, so an alarm acknowledged or snoozed on another
/// device stopped its future slots and kept ringing the one on screen.
final now = DateTime.utc(2030, 6, 1, 12);
const window = Duration(minutes: 30);

AlarmInput alarm(
  String rid, {
  Duration ago = const Duration(minutes: 1),
  String status = 'delivered',
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: rid,
  taskId: 'T-$rid',
  taskTitle: 'Task $rid',
  remindAt: now.subtract(ago),
  status: status,
  urgent: true,
  requiresAcknowledgement: true,
  snoozedUntil: snoozedUntil,
);

ActiveAlarmNotification shown(int id, String rid, {bool urgent = true}) =>
    ActiveAlarmNotification(id: id, urgent: urgent, reminderIds: [rid]);

/// One process's preferences file seen from two isolates (the app and the
/// headless wake), the way the legacy SharedPreferences behaves: each isolate
/// keeps the copy it loaded first and only sees another isolate's write after
/// a reload. A write goes through to the shared file.
class _Disk {
  final Map<String, String> values = {};
}

class _IsolateKv implements LocalKv {
  _IsolateKv(this._disk);

  final _Disk _disk;
  Map<String, String>? _cache;
  var reloads = 0;

  Map<String, String> get _view => _cache ??= Map.of(_disk.values);

  Future<void> reload() async {
    reloads++;
    _cache = Map.of(_disk.values);
  }

  @override
  Future<String?> get(String key) async => _view[key];

  @override
  Future<void> set(String key, String value) async {
    _view[key] = value;
    _disk.values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _view.remove(key);
    _disk.values.remove(key);
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    for (final key in _view.keys.where(test).toList()) {
      await remove(key);
    }
  }
}

class _ShownPlugin extends Fake implements FlutterLocalNotificationsPlugin {
  List<ActiveNotification> shown = const [];

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => shown;
}

PlannedNotification urgentPlan(int id, String rid) => PlannedNotification(
  id: id,
  title: 'AllisWell',
  body: '',
  fireAt: DateTime.now().toUtc(),
  urgent: true,
  payload: jsonEncode({'taskId': 'T-$rid', 'reminderId': rid}),
);

void main() {
  group('activeToCancel (pure)', () {
    test(
      'cancels the delivered urgent notification of a reminder acknowledged elsewhere',
      () {
        // R1 was acknowledged on the other device: the sync dropped it from the
        // active set, so the model no longer has it at all.
        expect(activeToCancel([shown(11, 'R1')], const [], now, window), {11});

        // A remote snooze moves the occurrence: the old one is no longer ringing.
        final snoozed = alarm(
          'R2',
          status: 'snoozed',
          snoozedUntil: now.add(const Duration(minutes: 10)),
        );
        expect(activeToCancel([shown(12, 'R2')], [snoozed], now, window), {12});
      },
    );

    test(
      'leaves the delivered notification of a still ringing reminder alone',
      () {
        final ringing = alarm('R1');
        expect(
          activeToCancel([shown(11, 'R1')], [ringing], now, window),
          isEmpty,
        );

        // A grouped minute keeps ringing while any member still rings.
        const group = ActiveAlarmNotification(
          id: 13,
          urgent: true,
          reminderIds: ['R1', 'R9'],
        );
        expect(activeToCancel([group], [ringing], now, window), isEmpty);
      },
    );

    test('ignores delivered notifications it cannot map to a reminder', () {
      expect(
        activeToCancel(
          [
            // A row the gateway could not tie to a reminder.
            const ActiveAlarmNotification(id: 21, urgent: true),
            // The rehearsal alarm is a diagnostic, not a reminder.
            const ActiveAlarmNotification(
              id: kAlarmTestNotificationId,
              urgent: true,
              reminderIds: ['R1'],
            ),
            // A normal reminder does not loop; it stays in the tray.
            shown(22, 'R1', urgent: false),
          ],
          const [],
          now,
          window,
        ),
        isEmpty,
      );
    });

    test('a stand-in that synced into its real reminder keeps ringing, and '
        'stops once that reminder is answered', () {
      // An offline-created task rang through its stand-in; a background sync
      // then brought the real row for the same task, kind and instant.
      const shownSynthetic = ActiveAlarmNotification(
        id: 31,
        urgent: true,
        reminderIds: ['local:remind:T-R1'],
        taskIds: ['T-R1'],
      );
      final real = alarm('R1'); // taskId T-R1, kind remind
      expect(activeToCancel([shownSynthetic], [real], now, window), isEmpty);

      // The real reminder acknowledged (left the active set): it stops.
      expect(activeToCancel([shownSynthetic], const [], now, window), {31});

      // Another kind of the same task ringing is not this alarm.
      const shownDue = ActiveAlarmNotification(
        id: 32,
        urgent: true,
        reminderIds: ['local:due:T-R1'],
        taskIds: ['T-R1'],
      );
      expect(activeToCancel([shownDue], [real], now, window), {32});
    });

    test('is idempotent across two passes', () {
      final active = [shown(11, 'R1'), shown(12, 'R2')];
      final alarms = [alarm('R2')];
      final first = activeToCancel(active, alarms, now, window);
      expect(first, {11});
      // The OS removed what was cancelled; the second pass finds nothing new.
      final left = active.where((n) => !first.contains(n.id)).toList();
      expect(activeToCancel(left, alarms, now, window), isEmpty);
    });
  });

  group('payload mapping', () {
    test('a planned payload names its reminders and tasks', () {
      final single = ActiveAlarmNotification.fromPayload(
        id: 1,
        urgent: true,
        payload: jsonEncode({'taskId': 'T1', 'reminderId': 'R1'}),
      );
      expect(single.reminderIds, ['R1']);
      expect(single.taskIds, ['T1']);

      final group = ActiveAlarmNotification.fromPayload(
        id: 2,
        urgent: true,
        payload: jsonEncode({
          'taskId': 'T1',
          'taskIds': ['T1', 'T2'],
          'reminderIds': ['R1', 'R2'],
        }),
      );
      expect(group.reminderIds, ['R1', 'R2']);
      expect(group.taskIds, ['T1', 'T2']);

      for (final payload in [null, '', 'not json', '[1]', '{"test":true}']) {
        expect(
          ActiveAlarmNotification.fromPayload(
            id: 3,
            urgent: true,
            payload: payload,
          ).reminderIds,
          isEmpty,
        );
      }
    });

    test(
      'Android omits the payload of a shown notification, the stored one maps it',
      () {
        final stored = rememberUrgentPayload(
          null,
          id: 7,
          payload: jsonEncode({'reminderId': 'R1'}),
          fireAt: now,
          now: now,
        );
        final active = activeAlarmsFrom([
          const ActiveNotification(id: 7, channelId: 'urgent_alarms_v2_aw'),
          const ActiveNotification(id: 8, channelId: 'reminders_default'),
          const ActiveNotification(id: 9, channelId: 'urgent_alarms_v2_aw'),
        ], readUrgentPayloads(stored));

        expect(active.map((n) => n.id), [7, 8, 9]);
        expect(active[0].urgent, isTrue);
        expect(active[0].reminderIds, ['R1']);
        expect(active[1].urgent, isFalse);
        // Scheduled before the record existed: nothing to map it with.
        expect(active[2].reminderIds, isEmpty);
      },
    );

    test('the stored record forgets old entries and survives junk', () {
      var json = rememberUrgentPayload(
        'not json',
        id: 1,
        payload: '{"reminderId":"R1"}',
        fireAt: now.subtract(const Duration(days: 3)),
        now: now,
      );
      json = rememberUrgentPayload(
        json,
        id: 2,
        payload: '{"reminderId":"R2"}',
        fireAt: now,
        now: now,
      );
      expect(readUrgentPayloads(json).keys, [2]);
      expect(readUrgentPayloads(null), isEmpty);
      expect(readUrgentPayloads('{"x":1}'), isEmpty);
    });
  });

  group('the urgent payload record across isolates', () {
    test(
      'the wake isolate maps a ringing alarm the app isolate scheduled after the wake isolate loaded its copy',
      () async {
        final disk = _Disk();
        final appKv = _IsolateKv(disk);
        final wakeKv = _IsolateKv(disk);
        final plugin = _ShownPlugin();
        final wake = LocalNotificationsGateway(
          plugin: plugin,
          kv: wakeKv,
          android: true,
          refreshKv: wakeKv.reload,
        );
        final app = LocalNotificationsGateway(
          plugin: _ShownPlugin(),
          kv: appKv,
          android: true,
          refreshKv: appKv.reload,
        );

        // (1) An earlier wake loaded the preferences in the wake isolate.
        expect(await wake.activeNotifications(), isEmpty);
        await wakeKv.get(kUrgentPayloadsKey);
        // (2) The app isolate schedules urgent R5 and stores its payload.
        await app.rememberUrgent(urgentPlan(55, 'R5'));
        // (3) R5 rings; (4) the next wake reads the record.
        plugin.shown = const [
          ActiveNotification(id: 55, channelId: 'urgent_alarms_v2_aw'),
        ];
        final active = await wake.activeNotifications();

        expect(active.single.reminderIds, ['R5']);
        // Acknowledged on the other device: the reconcile now cancels it.
        expect(activeToCancel(active, const [], now, window), {55});
      },
    );

    test(
      'a write from the wake isolate keeps the entries the app isolate wrote after it loaded',
      () async {
        final disk = _Disk();
        final appKv = _IsolateKv(disk);
        final wakeKv = _IsolateKv(disk);
        final wake = LocalNotificationsGateway(
          plugin: _ShownPlugin(),
          kv: wakeKv,
          android: true,
          refreshKv: wakeKv.reload,
        );
        final app = LocalNotificationsGateway(
          plugin: _ShownPlugin(),
          kv: appKv,
          android: true,
          refreshKv: appKv.reload,
        );

        await wake.rememberUrgent(urgentPlan(1, 'R1'));
        await app.rememberUrgent(urgentPlan(5, 'R5'));
        await wake.rememberUrgent(urgentPlan(2, 'R2'));

        expect(
          readUrgentPayloads(disk.values[kUrgentPayloadsKey]).keys.toSet(),
          {1, 2, 5},
        );
      },
    );
  });
}
