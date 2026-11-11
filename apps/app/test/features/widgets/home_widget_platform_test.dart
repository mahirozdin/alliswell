import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-370 — `home_widget` 0.9.3 declares android and ios only. Registering
/// its interactivity callback anywhere else (web, Windows, Linux, macOS — whose
/// widget runs over MacWidgetHost) ended in an unawaited MissingPluginException
/// at every start of the desktop downloads.
///
/// OPH-438 (#50, RC4) — and on iOS the plugin answers -7 when the callback is
/// registered before `setAppGroupId`, which `main()` does before the first
/// frame. iOS never runs `HomeWidgetBackgroundWorker`: its widget writes
/// through our own App Intent and App Group queue. So the callback is
/// registered on Android only, where the widget's buttons need it.
void main() {
  test(
    'interactivity callback is registered after the app group (or Android only)',
    () {
      expect(
        homeWidgetCallbackSupported(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
        reason: 'Android widget taps run through the callback',
      );
      expect(
        homeWidgetCallbackSupported(isWeb: false, platform: TargetPlatform.iOS),
        isFalse,
        reason:
            'main() registers before setAppGroupId; home_widget answers -7 '
            'on iOS, and iOS widget taps never use the callback',
      );
    },
  );

  test('web, Windows, Linux and macOS do not', () {
    expect(
      homeWidgetCallbackSupported(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    for (final p in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      expect(
        homeWidgetCallbackSupported(isWeb: false, platform: p),
        isFalse,
        reason: '$p',
      );
    }
  });
}
