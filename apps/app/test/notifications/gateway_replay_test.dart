import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/gateway_local.dart';

/// OPH-214 — the responses that used to fall on the floor.
///
/// A notification action LAUNCHES the app (every Android action ships
/// `showsUserInterface: true`), so its response is ready long before the only
/// listener exists: `notificationSchedulerProvider` is not born until HomeShell
/// is mounted and the workspace has resolved. A plain broadcast controller
/// drops anything sent to nobody — which is exactly what "the snooze icon does
/// nothing" was. The gateway queues instead.
void main() {
  test(
    'a response that arrives before anyone listens is delivered, not lost',
    () async {
      final gateway = LocalNotificationsGateway();
      gateway.debugEmit(
        const NotificationEvent(
          actionId: 'snooze:5_min',
          payload: '{"taskId":"T1"}',
        ),
      );

      final received = <NotificationEvent>[];
      gateway.events.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.actionId, 'snooze:5_min');
    },
  );

  test('the backlog goes to the FIRST listener only, never twice', () async {
    final gateway = LocalNotificationsGateway();
    gateway.debugEmit(
      const NotificationEvent(actionId: 'complete', payload: '{}'),
    );

    final first = <NotificationEvent>[];
    final second = <NotificationEvent>[];
    gateway.events.listen(first.add);
    await Future<void>.delayed(Duration.zero);
    gateway.events.listen(second.add);
    await Future<void>.delayed(Duration.zero);

    // Re-delivering would run the action a second time — completing a task
    // twice is harmless, snoozing it twice is not.
    expect(first, hasLength(1));
    expect(second, isEmpty);
  });

  test('once someone is listening, responses flow straight through', () async {
    final gateway = LocalNotificationsGateway();
    final received = <NotificationEvent>[];
    gateway.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    gateway.debugEmit(const NotificationEvent(actionId: 'mute', payload: '{}'));
    await Future<void>.delayed(Duration.zero);
    expect(received.single.actionId, 'mute');
  });
}
