import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/widgets/widget_bridge.dart';
import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:alliswell/src/features/widgets/widget_token_store.dart';
import 'package:alliswell/src/i18n/i18n.dart';

import 'widget_app_group_fake.dart';

/// #50, PR2-01 — `home_widget` 0.9.3 hands a Dart null to iOS as `NSNull`,
/// and `-[NSUserDefaults setObject:forKey:]` aborts the app on it. The app
/// removed App Group keys by saving null, so a sign-out, a refused session
/// and a "Private widget" change crashed it on iOS and left the keys behind.
///
/// Measured at the channel: every way the app takes a widget key away goes
/// through the plugin's `saveWidgetData`, and not one carries a null.
Task _task(String id) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'SECRET $id',
  status: 'open',
  priority: 'none',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  late FakeHomeWidgetChannel plugin;
  setUp(() async {
    AwI18n.instance.setActiveCached(const Locale('en'));
    await localKv.removeWhere((_) => true);
    plugin = FakeHomeWidgetChannel()..install();
  });
  tearDown(() => plugin.uninstall());

  test('no removal path sends a null value to the widget plugin', () async {
    const keys = [
      kWidgetFetchProfileKey,
      kWidgetTokenStateKey,
      kWidgetServerSnapshotKey,
      kWidgetFetchedAtKey,
      kWidgetFetchFailuresKey,
      kWidgetBackoffUntilKey,
    ];

    // A profile change ("Private widget" turned on) removes the extension's
    // copy of the old answer right after the new profile.
    final bridge = WidgetBridge(const HomeWidgetHost());
    Future<void> publish({required bool hideTitles}) => bridge.publish(
      [_task('A')],
      now: DateTime(2026, 11, 12, 9),
      hideTitles: hideTitles,
      fetch: WidgetFetchSource(
        baseUrl: 'https://api.example.com',
        scope: TaskScope.workspace('W1'),
        pendingOutbox: 0,
      ),
    );
    await publish(hideTitles: false);
    plugin.values[kWidgetServerSnapshotKey] = '{"query":"private=0"}';
    await publish(hideTitles: true);
    expect(plugin.isAbsent(kWidgetServerSnapshotKey), isTrue);

    // The token removal and the envelope removal one by one, through both
    // of the app's removers.
    for (final key in keys) {
      plugin.values[key] = 'x';
      await const HomeWidgetHost().remove(key);
      expect(plugin.isAbsent(key), isTrue, reason: key);
      plugin.values[key] = 'x';
      await const HomeWidgetGroupKeys().remove(key);
      expect(plugin.isAbsent(key), isTrue, reason: key);
      // A removed key reads as no value at all.
      expect(await const HomeWidgetGroupKeys().read(key), isNull, reason: key);
    }

    // Sign-out — and a refused or revoked session, which runs the same
    // signOut — with everything the extension and the app had written.
    for (final key in keys) {
      plugin.values[key] = 'x';
    }
    final lifecycle = WidgetTokenLifecycle(
      api: _NoMint(),
      store: _MemoryTokenStore(),
      groupKeys: const HomeWidgetGroupKeys(),
      enabled: true,
      forgetProfile: bridge.forgetFetch,
    );
    await lifecycle.signOut();
    await bridge.showSignedOut();
    for (final key in keys) {
      expect(plugin.isAbsent(key), isTrue, reason: key);
    }

    final saves = plugin.calls.where((c) => c.method == 'saveWidgetData');
    expect(saves, isNotEmpty);
    expect(
      [
        for (final call in saves)
          if ((call.arguments as Map)['data'] == null)
            (call.arguments as Map)['id'],
      ],
      isEmpty,
      reason: 'home_widget 0.9.3 writes a null as NSNull on iOS and aborts',
    );
  });
}

class _NoMint implements WidgetTokenApi {
  @override
  Future<WidgetTokenMint> mint(String deviceId) =>
      throw const WidgetTokenException(WidgetTokenRefusal.failed);
}

class _MemoryTokenStore implements WidgetTokenStore {
  String? token = 'aww_1';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}
