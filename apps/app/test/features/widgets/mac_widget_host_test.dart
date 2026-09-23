import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/widgets/widget_host.dart';

/// OPH-335 — the Mac writes the widget's data through the app's own channel.
///
/// `home_widget` 0.9.3 declares android and ios only: on a Mac every snapshot
/// write ended in a MissingPluginException nobody saw, and a macOS widget
/// would have had nothing to read. The macOS Runner answers `alliswell/widget`
/// itself (`AWMacWidgetBridge`); these pin the Dart half of that contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('on macOS the app speaks its own channel', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(defaultWidgetHost(), isA<MacWidgetHost>());
  });

  test('everywhere else it stays home_widget', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(defaultWidgetHost(), isA<HomeWidgetHost>(), reason: '$platform');
    }
  });

  test('it writes the key the widget reads, then asks for a redraw', () async {
    const channel = MethodChannel('alliswell/widget');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const host = MacWidgetHost();
    // Nothing to configure: the App Group is fixed on the native side, and a
    // round-trip that does nothing is a round-trip that can fail for nothing.
    await host.configure();
    await host.save(kWidgetSnapshotKey, '{"v":3}');
    await host.requestUpdate();

    expect(calls.map((call) => call.method), ['save', 'update']);
    expect(calls.first.arguments, {
      'key': 'aw_widget_snapshot',
      'value': '{"v":3}',
    });
  });
}
