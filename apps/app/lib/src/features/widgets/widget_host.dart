import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

/// App Group / widget identifiers (OPH-130, ADR-0010). The App Group must be
/// byte-identical here, in the iOS/macOS entitlements, and on the native widget
/// targets (OPH-131/133/134).
const String kWidgetAppGroupId = 'group.com.alliswell.alliswell';
const String kWidgetSnapshotKey = 'aw_widget_snapshot';
const String kWidgetIosName = 'AllisWellWidget';
const String kWidgetAndroidProvider = 'TasksWidgetProvider';

/// The seam over `home_widget`'s static API so the bridge is unit-testable with a
/// fake (ADR-0010: "the bridge is verified against a fake HomeWidget").
abstract class WidgetHost {
  /// One-time setup (the iOS/macOS App Group). Safe to call more than once.
  Future<void> configure();

  /// Persist a value into the shared container.
  Future<void> save(String key, String value);

  /// Ask the OS to re-render the widget with the freshly-saved data.
  Future<void> requestUpdate();
}

/// Production implementation backed by `home_widget`.
class HomeWidgetHost implements WidgetHost {
  const HomeWidgetHost();

  @override
  Future<void> configure() => HomeWidget.setAppGroupId(kWidgetAppGroupId);

  @override
  Future<void> save(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  @override
  Future<void> requestUpdate() => HomeWidget.updateWidget(
    iOSName: kWidgetIosName,
    androidName: kWidgetAndroidProvider,
    qualifiedAndroidName: 'com.alliswell.alliswell.$kWidgetAndroidProvider',
  );
}

/// macOS implementation over the app's own channel (OPH-335).
///
/// `home_widget` 0.9.3 declares android and ios only, so on a Mac its calls
/// ended in a MissingPluginException nobody saw. The macOS Runner answers
/// `alliswell/widget` itself (`AWMacWidgetBridge` in MainFlutterWindow.swift):
/// the same key, the same App Group, then a WidgetKit reload. The group is
/// fixed on the native side, so there is nothing to configure.
class MacWidgetHost implements WidgetHost {
  const MacWidgetHost([
    this._channel = const MethodChannel('alliswell/widget'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> configure() async {}

  @override
  Future<void> save(String key, String value) =>
      _channel.invokeMethod<void>('save', {'key': key, 'value': value});

  @override
  Future<void> requestUpdate() => _channel.invokeMethod<void>('update');
}

/// The host this platform has: the app's own channel on macOS, `home_widget`
/// everywhere else it runs. One answer for the live graph and the background
/// turn alike (OPH-334/335).
WidgetHost defaultWidgetHost() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
    ? const MacWidgetHost()
    : const HomeWidgetHost();

/// The active host. Tests override this with a fake.
final widgetHostProvider = Provider<WidgetHost>((_) => defaultWidgetHost());
