import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/auth/data/secure_secret_store.dart';
import 'package:alliswell/src/features/widgets/widget_token_store.dart';

/// #50, WIDGETS §3.2 "Keychain item": the widget token lives in its own
/// Keychain item the WidgetKit extension can read after the first unlock, and
/// the session's items stay exactly as they were (ADR-0071).
///
/// The options reach the native side as the method channel's `options` map —
/// what `flutter_secure_storage_darwin` turns into the item's attributes — so
/// that map is what these tests read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'read' ? 'aww_stored' : null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<Object?, Object?> optionsOf(MethodCall call) =>
      (call.arguments as Map)['options'] as Map<Object?, Object?>;

  test(
    'widget token uses the app group and first_unlock_this_device',
    () async {
      final store = WidgetTokenStore();
      await store.write('aww_secret');
      expect(await store.read(), 'aww_stored');
      await store.delete();

      expect(calls.map((c) => c.method), ['write', 'read', 'delete']);
      for (final call in calls) {
        final args = call.arguments as Map;
        // The account the extension asks for, passed through unchanged.
        expect(args['key'], 'aw_widget_token');
        final options = optionsOf(call);
        // No team prefix: the plugin's groupId is the App Group itself.
        expect(options['groupId'], 'group.com.alliswell.alliswell');
        expect(options['accessibility'], 'first_unlock_this_device');
        // The plugin's default service — the contract's kSecAttrService.
        expect(options['accountName'], 'flutter_secure_storage_service');
        expect(options['synchronizable'], 'false');
      }
      expect((calls.first.arguments as Map)['value'], 'aww_secret');
      expect(kWidgetTokenKey, 'aw_widget_token');
    },
  );

  test('session tokens still use the default WhenUnlocked options', () async {
    final session = SecureSecretStore();
    await session.write('alliswell_session', '{"refreshToken":"r"}');
    await session.read('alliswell_session');
    await session.delete('alliswell_session');

    expect(calls.map((c) => c.method), ['write', 'read', 'delete']);
    for (final call in calls) {
      final options = optionsOf(call);
      // App-private and WhenUnlocked, as before #50: the extension never
      // sees the session (ADR-0071).
      expect(options.containsKey('groupId'), isFalse);
      expect(options['accessibility'], 'unlocked');
      expect(options['accountName'], 'flutter_secure_storage_service');
    }
  });
}
