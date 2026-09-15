import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/firebase/push_messaging.dart';
import 'package:alliswell/src/features/devices/device_registry.dart';
import 'package:alliswell/src/notifications/platform_matrix.dart';

/// OPH-317 — the half of the gate that runs in Dart.
///
/// `scripts/notifications/matrix.mjs` checks that the document says what the
/// declaration says. This checks that the declaration says what the CODE does.
/// Neither alone would be worth much: a table checked only against itself is
/// the circular fixture the repo keeps refusing to write.
void main() {
  test('every platform the registry can name has a row', () {
    for (final entry in kMatrixTargets.entries) {
      final id = awDevicePlatform(isWeb: false, target: entry.value);
      expect(id, entry.key);
      expect(notificationPlatformFor(id), isNotNull, reason: 'no row for $id');
    }
    expect(
      awDevicePlatform(isWeb: true, target: kMatrixTargets.values.first),
      'web',
    );
    expect(notificationPlatformFor('web'), isNotNull);
  });

  test('the gateway column is the decision the provider makes', () {
    for (final row in kNotificationMatrix) {
      expect(
        row.gateway,
        gatewayKindFor(isWeb: row.id == 'web'),
        reason: '${row.id} claims a gateway the provider would not pick',
      );
    }
  });

  test('the token path obeys the table, which is what makes it not a note', () {
    for (final row in kNotificationMatrix) {
      final messaging = AwPushMessaging(
        isWeb: row.id == 'web',
        isConfigured: () => true,
        platformId: row.id,
      );
      // Change `serverPush` in the declaration and the app stops (or starts)
      // asking the plugin for a token. That is the whole difference between a
      // table and a comment.
      expect(
        messaging.isAvailable,
        row.serverPush == 'fcm',
        reason: '${row.id}: serverPush and the token path disagree',
      );
    }
  });

  test(
    'a build with no Firebase config asks nobody, whatever the table says',
    () {
      for (final row in kNotificationMatrix) {
        final messaging = AwPushMessaging(
          isWeb: row.id == 'web',
          isConfigured: () => false,
          platformId: row.id,
        );
        expect(messaging.isAvailable, isFalse, reason: row.id);
      }
    },
  );

  test('exactly one platform cannot schedule, and it is the browser', () {
    // The single `false` in that column is what ADR-0038 §3 amends the
    // delivery model for. If a second one ever appears, the amendment covers
    // one platform and the table has started lying.
    final cannot = kNotificationMatrix.where((r) => !r.localSchedule).toList();
    expect(cannot, hasLength(1));
    expect(cannot.single.id, 'web');
    expect(cannot.single.gateway, NotificationGatewayKind.web);
    expect(cannot.single.serverPush, 'webpush');
  });

  test('AlarmKit is claimed by iOS alone', () {
    expect(kNotificationMatrix.where((r) => r.alarmKit).map((r) => r.id), [
      'ios',
    ]);
  });

  test('every platform has the in-app screen — it is the floor', () {
    // On desktop and web it is the ONLY alarm surface (NOTIFICATIONS §3), so a
    // row without it would describe a platform that cannot ring at all.
    expect(kNotificationMatrix.every((r) => r.inAppScreen), isTrue);
  });
}
