import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/actions.dart';
import 'package:alliswell/src/notifications/alarm_log.dart';
import 'package:alliswell/src/notifications/alarmkit.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';
import 'package:alliswell/src/sync/db/database.dart';

final now = DateTime.utc(2026, 7, 15, 12);

AlarmInput alarm(
  String id, {
  bool urgent = false,
  String status = 'scheduled',
  Duration offset = const Duration(hours: 1),
  DateTime? snoozedUntil,
}) => AlarmInput(
  reminderId: id.padRight(26, '0'),
  taskId: 'T$id'.padRight(26, '0'),
  taskTitle: 'Görev $id',
  remindAt: now.add(offset),
  status: status,
  urgent: urgent,
  requiresAcknowledgement: urgent,
  snoozedUntil: snoozedUntil,
);

/// A scripted native side of `alliswell/alarmkit` (§2b.3): a pending-action
/// queue that only `ackActions` empties, a failure ring that a pull empties,
/// and per-method answers. A method listed in [unimplemented] answers the way
/// an older bridge does (`notImplemented` → `MissingPluginException`).
class FakeNativeBridge {
  FakeNativeBridge(this.channel) {
    _messenger.setMockMethodCallHandler(channel, _handle);
  }

  final MethodChannel channel;
  final List<MethodCall> calls = [];
  final List<Map<String, Object?>> queue = [];
  final List<Map<String, Object?>> failures = [];
  List<Map<String, Object?>> alarms = [];
  List<int> ids = [];
  Set<String> unimplemented = {};

  static TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    // What the engine makes of `FlutterMethodNotImplemented`.
    if (unimplemented.contains(call.method)) throw MissingPluginException();
    final args = (call.arguments as Map?)?.cast<String, Object?>();
    switch (call.method) {
      case 'pullPendingActions':
        return [...queue];
      case 'ackActions':
        final acked = (args!['eventIds'] as List).cast<String>().toSet();
        queue.removeWhere((e) => acked.contains(e['eventId']));
        return null;
      case 'pullFailures':
        final out = [...failures];
        failures.clear();
        return out;
      case 'scheduledAlarms':
        return alarms;
      case 'scheduledIds':
        return ids;
      case 'stop':
        return {'stopped': true, 'cancelled': false, 'error': null};
    }
    return null;
  }

  /// Native → Dart, the way `FlutterMethodChannel.invokeMethod` arrives.
  Future<void> push(String method, [Object? arguments]) async {
    await _messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  List<String> get methods => [for (final c in calls) c.method];

  void dispose() => _messenger.setMockMethodCallHandler(channel, null);
}

Map<String, Object?> snoozeEntry(String eventId, int pressedAtMs) => {
  'eventId': eventId,
  'action': 'snooze',
  'taskIds': ['T1'],
  'untilMs': 1_800_000_000_000,
  'occurrenceFireAtMs': 1_799_999_000_000,
  'pressedAtMs': pressedAtMs,
  'origin': 'alarmkit',
  'alarmId': 42,
  'newId': 43,
  'scheduleOutcome': 'limitReached',
  'stopOutcome': 'stopped',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlarmKit channel contract v2 (OPH-425, NOTIFICATIONS §2b.3)', () {
    const channel = MethodChannel('alliswell/alarmkit');
    late FakeNativeBridge native;

    setUp(() => native = FakeNativeBridge(channel));
    tearDown(() => native.dispose());

    test(
      'actions queued before the listener exists are delivered after it attaches',
      () async {
        // An Ertele pressed while the app was dead: the intent queued it in the
        // App Group, and the bridge announced it before Dart listened.
        native.queue.add(snoozeEntry('ev-1', 1000));
        final host = MethodChannelAlarmKitHost(channel: channel);
        await native.push('onActionsPending');

        // Nothing is pulled — let alone drained — by merely existing.
        expect(native.calls, isEmpty);

        final delivered = <AlarmKitActionEvent>[];
        final sub = host.actionsPending.listen((_) async {
          delivered.addAll(await host.pullPendingActions());
        });
        await pumpEventQueue();

        expect(delivered.map((e) => e.eventId), ['ev-1']);
        final event = delivered.single;
        expect(event.action, 'snooze');
        expect(event.taskIds, ['T1']);
        expect(event.untilMs, 1_800_000_000_000);
        expect(event.occurrenceFireAtMs, 1_799_999_000_000);
        expect(event.origin, 'alarmkit');
        expect(event.alarmId, 42);
        expect(event.newId, 43);
        expect(event.scheduleOutcome, 'limitReached');
        expect(event.stopOutcome, 'stopped');
        // A pull never removes: only an ack after the commit does.
        expect(native.queue, hasLength(1));
        expect(native.methods, isNot(contains('drainPendingActions')));

        // A later announcement is a pull signal, not a pushed event.
        native.queue.add(snoozeEntry('ev-2', 2000));
        delivered.clear();
        await native.push('onActionsPending');
        await pumpEventQueue();
        expect(delivered.map((e) => e.eventId), ['ev-1', 'ev-2']);

        await host.ackActions(['ev-1', 'ev-2']);
        expect(native.queue, isEmpty);
        await sub.cancel();
      },
    );

    test('pulled actions come back in press order', () async {
      native.queue
        ..add(snoozeEntry('late', 3000))
        ..add(snoozeEntry('early', 1000))
        ..add({'garbage': true});
      final host = MethodChannelAlarmKitHost(channel: channel);
      final events = await host.pullPendingActions();
      expect(events.map((e) => e.eventId), ['early', 'late']);
    });

    test(
      'native failures are copied into the alarm log as degraded and removed',
      () async {
        final db = AwDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        );
        addTearDown(db.close);
        final log = AlarmLog(db);
        native.failures.addAll([
          {
            'eventId': 'ev-1',
            'atMs': DateTime.utc(2026, 11, 12, 9).millisecondsSinceEpoch,
            'stage': 'schedule',
            'code': 'maximumLimitReached',
            'message': 'limit',
          },
          {
            'eventId': 'ev-1',
            'atMs': DateTime.utc(2026, 11, 12, 9, 0, 1).millisecondsSinceEpoch,
            'stage': 'stop',
            'code': 'other',
            'message': 'boom',
          },
        ]);
        final host = MethodChannelAlarmKitHost(channel: channel);

        await host.copyNativeFailures(log);
        await host.copyNativeFailures(log); // the second pull finds nothing

        final rows = await log.recent();
        expect(rows, hasLength(2));
        expect(rows.every((r) => r.event == AlarmLogEvent.degraded), isTrue);
        expect(rows.every((r) => r.lane == AlarmLogLane.alarmkit), isTrue);
        expect(rows.map((r) => r.detail).join(' '), contains('schedule'));
        expect(
          rows.map((r) => r.detail).join(' '),
          contains('maximumLimitReached'),
        );
        expect(rows.map((r) => r.detail).join(' '), contains('stop'));
        expect(
          rows.map((r) => r.at.toUtc()),
          containsAll([
            DateTime.utc(2026, 11, 12, 9),
            DateTime.utc(2026, 11, 12, 9, 0, 1),
          ]),
        );
        expect(native.failures, isEmpty);
        expect(native.methods.where((m) => m == 'pullFailures'), hasLength(2));
      },
    );

    test('scheduledIds is derived from scheduledAlarms', () async {
      native.alarms = [
        {
          'id': 7,
          'fp': 99,
          'state': 'alerting',
          'members': ['A', 'B'],
          'fireAtMs': 1_800_000_000_000,
          'origin': 'native',
          'eventId': 'ev-9',
        },
        {
          'id': 8,
          'fp': 0,
          'state': 'scheduled',
          'members': <String>[],
          'fireAtMs': 1_800_000_060_000,
          'origin': 'dart',
          'eventId': null,
        },
      ];
      native.ids = [1, 2, 3]; // a stale answer that must not be consulted
      final host = MethodChannelAlarmKitHost(channel: channel);

      final alarms = await host.scheduledAlarms();
      expect(alarms.map((a) => a.id), [7, 8]);
      final ringing = alarms.first;
      expect(ringing.state, AlarmKitAlarmState.alerting);
      expect(ringing.members, ['A', 'B']);
      expect(ringing.fp, 99);
      expect(ringing.origin, 'native');
      expect(ringing.eventId, 'ev-9');
      expect(ringing.hasLedger, isTrue);
      expect(alarms.last.hasLedger, isFalse);

      expect(await host.scheduledIds(), {7, 8});
      expect(native.methods, isNot(contains('scheduledIds')));
    });

    test(
      'an old native side without scheduledAlarms degrades to scheduledIds',
      () async {
        native
          ..unimplemented = {'scheduledAlarms'}
          ..ids = [5, 6];
        final host = MethodChannelAlarmKitHost(channel: channel);

        final alarms = await host.scheduledAlarms();
        expect(alarms.map((a) => a.id), [5, 6]);
        for (final a in alarms) {
          expect(a.state, AlarmKitAlarmState.scheduled);
          expect(a.members, isEmpty);
          expect(a.fp, 0);
          expect(a.origin, 'dart');
          expect(a.fireAtMs, isNull);
          expect(a.eventId, isNull);
          expect(a.hasLedger, isFalse);
        }
        expect(await host.scheduledIds(), {5, 6});
      },
    );

    test('stop answers what the native side did', () async {
      final host = MethodChannelAlarmKitHost(channel: channel);
      final result = await host.stop(7);
      expect(result.stopped, isTrue);
      expect(result.cancelled, isFalse);
      expect(result.error, isNull);
      expect(native.calls.last.arguments, {'id': 7});

      native.unimplemented = {'stop'};
      final missing = await host.stop(7);
      expect(missing.stopped, isFalse);
      expect(missing.error, 'missing-plugin');
    });

    test('clearFallbacks and ackActions send the event ids', () async {
      final host = MethodChannelAlarmKitHost(channel: channel);
      await host.clearFallbacks(['ev-1']);
      await host.ackActions(const []); // nothing to ack: no call
      expect(native.methods, ['clearFallbacks']);
      expect(native.calls.single.arguments, {
        'eventIds': ['ev-1'],
      });
    });

    test(
      'the legacy path (macOS, older bridge): drain, then pushed onAlarmAction',
      () async {
        native.unimplemented = {'pullPendingActions', 'ackActions'};
        final host = MethodChannelAlarmKitHost(channel: channel);
        final delivered = <AlarmKitActionEvent>[];
        final sub = host.actionsPending.listen((_) async {
          delivered.addAll(await host.pullPendingActions());
        });
        await pumpEventQueue();
        expect(native.methods, contains('drainPendingActions'));

        // The old bridge answers a drain by pushing each entry.
        await native.push('onAlarmAction', {
          'actionId': 'snooze:30_min',
          'payload': '{"taskId":"T1","reminderId":"R1"}',
        });
        await native.push('onAlarmAction', {
          'actionId': 'complete',
          'payload': '{"taskId":"T2","reminderId":""}',
        });
        await pumpEventQueue();

        expect(delivered, hasLength(2));
        final snooze = delivered.first;
        expect(snooze.action, 'snooze');
        expect(snooze.preset, '30_min');
        expect(snooze.untilMs, isNull);
        expect(snooze.taskIds, ['T1']);
        expect(snooze.reminderId, 'R1');
        expect(snooze.eventId, isNotEmpty);
        expect(delivered.last.action, 'complete');
        expect(delivered.last.taskIds, ['T2']);
        expect(delivered.last.origin, 'widget');
        expect(delivered.first.eventId, isNot(delivered.last.eventId));

        // Already removed natively by the drain: an ack is a local no-op.
        await host.ackActions([snooze.eventId]);
        expect(native.methods, isNot(contains('ackActions')));
        await sub.cancel();
      },
    );

    // OPH-427: the ack is the native side's permission to forget an action,
    // so it may only follow a committed write.
    test('actions are acked only after their transaction commits', () async {
      final db = AwDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      // Snoozes AlarmKit scheduled itself: one that left a fallback is
      // acked only after the plan that clears it (OPH-431).
      native.queue
        ..add({...snoozeEntry('ev-1', 1000), 'scheduleOutcome': 'ok'})
        ..add({...snoozeEntry('ev-2', 2000), 'scheduleOutcome': 'ok'});
      final host = MethodChannelAlarmKitHost(channel: channel);

      final gate = Completer<void>();
      var failNext = true;
      final pump = AlarmKitActionPump(
        host: host,
        apply: (event) async {
          var inserted = false;
          await db.transaction(() async {
            inserted = await db.insertReceiptIfAbsent(
              eventId: event.eventId!,
              action: 'snooze',
              appliedAt: now,
            );
            if (event.eventId == 'ev-1') await gate.future;
            if (event.eventId == 'ev-2' && failNext) {
              failNext = false;
              throw StateError('write failed');
            }
          });
          return inserted;
        },
      );

      final pulling = pump.pull();
      await pumpEventQueue();
      // ev-1's transaction is still open: nothing may be acked yet.
      expect(native.methods, isNot(contains('ackActions')));

      gate.complete();
      await pulling;
      // ev-1 committed → acked; ev-2 rolled back → stays queued, unacked.
      final acks = [
        for (final c in native.calls)
          if (c.method == 'ackActions') (c.arguments as Map)['eventIds'],
      ];
      expect(acks, [
        ['ev-1'],
      ]);
      expect(native.queue.map((e) => e['eventId']), ['ev-2']);
      final receipts = await db.select(db.actionReceipts).get();
      expect(receipts.map((r) => r.eventId), ['ev-1']);

      // The next pull applies ev-2 and acks it after its commit.
      await pump.pull();
      expect(native.queue, isEmpty);
      expect(
        (await db.select(db.actionReceipts).get()).map((r) => r.eventId),
        unorderedEquals(['ev-1', 'ev-2']),
      );
    });

    test('the unsupported host (Android, web, desktop) stays inert', () async {
      const host = UnsupportedAlarmKitHost();
      expect(await host.scheduledAlarms(), isEmpty);
      expect(await host.scheduledIds(), isEmpty);
      expect(await host.pullPendingActions(), isEmpty);
      expect(await host.pullFailures(), isEmpty);
      expect((await host.stop(1)).stopped, isFalse);
      await host.ackActions(['x']);
      await host.clearFallbacks(['x']);
      expect(await host.actionsPending.isEmpty, isTrue);
    });
  });

  group('planAlarmKitAlarms (OPH-141)', () {
    test('emits one alarm per URGENT reminder, no chain', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true), alarm('R2')],
        now: now,
        privacyMode: false,
      );
      expect(
        out,
        hasLength(1),
      ); // urgent only, a single entry (no 5-slot chain)
      expect(out.single.taskId, 'TR1'.padRight(26, '0'));
      expect(out.single.fireAt, now.add(const Duration(hours: 1)));
    });

    test('skips past instants', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true, offset: const Duration(hours: -1))],
        now: now,
        privacyMode: false,
      );
      expect(out, isEmpty);
    });

    test('honours a snooze', () {
      final snoozed = now.add(const Duration(hours: 3));
      final out = planAlarmKitAlarms(
        alarms: [
          alarm('R1', urgent: true, status: 'snoozed', snoozedUntil: snoozed),
        ],
        now: now,
        privacyMode: false,
      );
      expect(out.single.fireAt, snoozed);
    });

    test('privacy mode hides the task title', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: true,
      );
      expect(out.single.title, 'AllisWell');
    });

    test('ids are stable for identical input and change with fire time', () {
      AlarmKitAlarm one(Duration offset) => planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true, offset: offset)],
        now: now,
        privacyMode: false,
      ).single;

      expect(
        one(const Duration(hours: 1)).id,
        one(const Duration(hours: 1)).id,
      );
      expect(
        one(const Duration(hours: 1)).id,
        isNot(one(const Duration(hours: 2)).id),
      );
    });
  });

  group('the alert carries the app\'s own words and sound (OPH-182)', () {
    test('buttons are localized here, and the snooze says what it will do', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        snoozePreset: '30_min',
      ).single;

      // Whatever the fixture locale resolves these to, they must be the app's
      // strings — never empty, and never a Swift-side literal.
      expect(out.stopLabel, isNotEmpty);
      expect(out.snoozeLabel, isNotEmpty);
      expect(out.snoozeLabel, isNot(out.stopLabel));
      expect(out.snoozePreset, '30_min');
    });

    test('an unknown preset still gets a button rather than an empty one', () {
      final out = planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        snoozePreset: 'from_a_future_version',
      ).single;
      expect(out.snoozeLabel, isNotEmpty);
    });

    test('the sound name rides along AND reschedules when it changes', () {
      AlarmKitAlarm withSound(String? sound) => planAlarmKitAlarms(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
        soundName: sound,
      ).single;

      expect(withSound('aw_chime.caf').soundName, 'aw_chime.caf');
      expect(withSound('aw_chime.caf').fp, withSound('aw_chime.caf').fp);
      // OPH-181's rule, applied to this lane too: changing the sound must
      // re-schedule, not quietly apply "from the next alarm on". Since OPH-424
      // the sound is presentation: same occurrence id, new fingerprint.
      expect(withSound('aw_chime.caf').id, withSound('aw_ping.caf').id);
      expect(withSound('aw_chime.caf').fp, isNot(withSound('aw_ping.caf').fp));
    });
  });

  group(
    'the AlarmKit lane is capped, and the overflow is not lost (OPH-182)',
    () {
      List<AlarmInput> urgentAlarms(int count) => [
        for (var i = 0; i < count; i++)
          alarm('R$i', urgent: true, offset: Duration(hours: i + 1)),
      ];

      test('keeps the NEAREST maxAlarms and drops the far ones', () {
        final out = planAlarmKitAlarms(
          alarms: urgentAlarms(kMaxAlarmKitAlarms + 3),
          now: now,
          privacyMode: false,
        );
        expect(out, hasLength(kMaxAlarmKitAlarms));
        expect(out.first.fireAt, now.add(const Duration(hours: 1)));
        expect(out.last.fireAt, now.add(Duration(hours: kMaxAlarmKitAlarms)));
      });

      test('what did not fit keeps its notification chain', () {
        final alarms = urgentAlarms(kMaxAlarmKitAlarms + 2);
        final ak = planAlarmKitAlarms(
          alarms: alarms,
          now: now,
          privacyMode: false,
        );
        final covered = {for (final a in ak) a.reminderId};

        final notifications = planNotifications(
          alarms: alarms,
          now: now,
          privacyMode: false,
          alarmKitReminderIds: covered,
        );

        // The two alarms past the cap are the ONLY ones still on notifications —
        // an urgent alarm must never fall between the two lanes.
        final onNotifications = notifications.map((n) => n.reminderId).toSet();
        expect(onNotifications, hasLength(2));
        expect(onNotifications.intersection(covered), isEmpty);
        expect(
          notifications.where((n) => n.reminderId == onNotifications.first),
          hasLength(ReminderProfile.factory.offsets.length),
        );
      });
    },
  );

  group('planNotifications alarmKitReminderIds (OPH-141)', () {
    test('skips the alarms AlarmKit took so they only ring there', () {
      final urgent = alarm('R1', urgent: true);
      final out = planNotifications(
        alarms: [urgent, alarm('R2')],
        now: now,
        privacyMode: false,
        alarmKitReminderIds: {urgent.reminderId},
      );
      expect(out, hasLength(1)); // only the non-urgent reminder survives
      expect(out.single.urgent, isFalse);
    });

    test('without the set, urgent still produces its notification chain', () {
      final out = planNotifications(
        alarms: [alarm('R1', urgent: true)],
        now: now,
        privacyMode: false,
      );
      expect(out, hasLength(ReminderProfile.factory.offsets.length));
    });
  });
}
