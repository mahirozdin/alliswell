import 'package:alliswell/src/notifications/gateway_local.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-370 — flutter_local_notifications throws "Windows settings must be set
/// when targeting Windows platform" when `windows` is null, which left every
/// local reminder on Windows failing (`degraded`). The desktop zip made that a
/// shipped build, so the settings are guarded here.
void main() {
  const darwin = DarwinInitializationSettings();

  InitializationSettings settings() => localInitializationSettings(
    darwin: darwin,
    linuxDefaultActionName: 'Open',
  );

  test('carries Windows settings with the AllisWell toast identity', () {
    final windows = settings().windows;
    expect(windows, isNotNull);
    expect(windows!.appName, 'AllisWell');
    expect(windows.appUserModelId, kWindowsAppUserModelId);
    expect(windows.appUserModelId, isNotEmpty);
    expect(
      windows.guid,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('the toast identity is a constant — stable across starts', () {
    final a = settings().windows!;
    final b = settings().windows!;
    expect(a.guid, b.guid);
    expect(a.appUserModelId, b.appUserModelId);
    // Changing either makes Windows treat the update as a different app:
    // pinned toast settings and pending activations would be orphaned.
    expect(kWindowsNotificationGuid, '2db36880-ee5f-43dc-a408-41559f20642a');
    expect(kWindowsAppUserModelId, 'BubiApps.AllisWell.Desktop');
  });

  test('the other platforms keep their entries', () {
    final s = settings();
    expect(s.android?.defaultIcon, '@mipmap/ic_launcher');
    expect(s.iOS, same(darwin));
    expect(s.macOS, same(darwin));
    expect(s.linux?.defaultActionName, 'Open');
  });
}
