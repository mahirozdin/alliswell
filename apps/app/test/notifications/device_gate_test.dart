import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/device_gate.dart';
import 'package:alliswell/src/notifications/planner.dart';

/// OPH-446 (#48) — urgent alarms ring only on the devices the server says
/// ring. The gate is the one pure function the foreground scheduler, the
/// in-app overlay and the headless pass all apply, so its four answers are
/// pinned here once.
AlarmInput _alarm(
  String id, {
  bool urgent = true,
  bool requiresAcknowledgement = true,
}) => AlarmInput(
  reminderId: id,
  taskId: 'task-$id',
  taskTitle: 'Title $id',
  remindAt: DateTime.utc(2026, 11, 12, 9),
  status: 'snoozed',
  urgent: urgent,
  requiresAcknowledgement: requiresAcknowledgement,
  kind: 'due',
  snoozeRound: 2,
  snoozedUntil: DateTime.utc(2026, 11, 12, 9, 5),
);

void main() {
  final alarms = [
    _alarm('r1'),
    _alarm('r2', urgent: false, requiresAcknowledgement: false),
  ];

  test('unknown demotes, legacy keeps, off demotes, on keeps', () {
    for (final here in [RingsUrgentHere.on, RingsUrgentHere.legacy]) {
      expect(
        forThisDevice(alarms, here),
        same(alarms),
        reason: '$here rings as today',
      );
    }
    for (final here in [RingsUrgentHere.off, RingsUrgentHere.unknown]) {
      final gated = forThisDevice(alarms, here);
      expect(gated, hasLength(2), reason: '$here never drops a reminder');
      expect(gated.every((a) => !a.urgent), isTrue, reason: '$here');
      expect(gated.every((a) => !a.requiresAcknowledgement), isTrue);
      // The demoted alarm is still the same reminder, at the same time.
      final demoted = gated.first;
      expect(demoted.reminderId, 'r1');
      expect(demoted.taskId, 'task-r1');
      expect(demoted.taskTitle, 'Title r1');
      expect(demoted.remindAt, DateTime.utc(2026, 11, 12, 9));
      expect(demoted.status, 'snoozed');
      expect(demoted.kind, 'due');
      expect(demoted.snoozeRound, 2);
      expect(demoted.snoozedUntil, DateTime.utc(2026, 11, 12, 9, 5));
      // A normal reminder passes through untouched.
      expect(gated.last, same(alarms.last));
    }
  });

  test('the stored form round-trips and a missing key reads legacy', () {
    for (final here in RingsUrgentHere.values) {
      expect(ringsUrgentHereFromStored(here.name), here);
    }
    expect(ringsUrgentHereFromStored(null), RingsUrgentHere.legacy);
    // A value this build does not know must not ring on a guess.
    expect(ringsUrgentHereFromStored('maybe'), RingsUrgentHere.unknown);
  });

  test('what the server answered maps to on, off or legacy', () {
    expect(ringsUrgentHereFromServer(true), RingsUrgentHere.on);
    expect(ringsUrgentHereFromServer(false), RingsUrgentHere.off);
    expect(ringsUrgentHereFromServer(null), RingsUrgentHere.legacy);
  });
}
