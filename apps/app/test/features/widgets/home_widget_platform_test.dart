import 'package:alliswell/src/features/widgets/widget_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-370 — `home_widget` 0.9.3 declares android and ios only. Registering
/// its interactivity callback anywhere else (web, Windows, Linux, macOS — whose
/// widget runs over MacWidgetHost) ended in an unawaited MissingPluginException
/// at every start of the desktop downloads.
void main() {
  test('android and iOS register the callback', () {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        homeWidgetCallbackSupported(isWeb: false, platform: p),
        isTrue,
        reason: '$p',
      );
    }
  });

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
