import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

/// App Group / widget identifiers (OPH-130, ADR-0010). The App Group must be
/// byte-identical here, in the iOS/macOS entitlements, and on the native widget
/// targets (OPH-131/133/134).
const String kWidgetAppGroupId = 'group.com.alliswell.alliswell';
const String kWidgetSnapshotKey = 'aw_widget_snapshot';

/// The widget self-fetch keys the app writes (iOS, #50, WIDGETS §3.2). The
/// profile is what a fetch needs — absent, the extension never fetches; the
/// server snapshot is the extension's own copy of the last answer, which the
/// app only ever removes.
const String kWidgetFetchProfileKey = 'aw_widget_fetch_profile';
const String kWidgetServerSnapshotKey = 'aw_widget_server_snapshot';

/// What a removed App Group key holds (#50, PR2-01; WIDGETS §3.2). The app
/// never saves a null: `home_widget` 0.9.3 hands it to iOS as `NSNull`, and
/// `NSUserDefaults` aborts the app on it — a sign-out, a refused session and
/// a "Private widget" change crashed there and left the keys behind. Every
/// reader, Dart and Swift, treats the empty string as no value at all.
const String kWidgetRemovedValue = '';
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

/// A host that can also take a key away (#50). Separate from [WidgetHost] so
/// a host that only saves — every test fake — stays a host.
abstract interface class WidgetKeyRemover {
  Future<void> remove(String key);
}

/// Production implementation backed by `home_widget`.
class HomeWidgetHost implements WidgetHost, WidgetKeyRemover {
  const HomeWidgetHost();

  @override
  Future<void> configure() => HomeWidget.setAppGroupId(kWidgetAppGroupId);

  @override
  Future<void> save(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  /// Written as [kWidgetRemovedValue], never as null (PR2-01).
  @override
  Future<void> remove(String key) =>
      HomeWidget.saveWidgetData<String>(key, kWidgetRemovedValue);

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

/// Whether `home_widget`'s interactivity callback is registered (OPH-370,
/// OPH-438). Android only. The plugin declares android and ios: on web,
/// Windows, Linux — and macOS, whose widget runs over [MacWidgetHost]'s own
/// channel — the call ended in an unawaited MissingPluginException at every
/// start. On iOS `main()` registers before [HomeWidgetHost.configure] sets the
/// App Group, and home_widget 0.9.3 answers that with error -7 (#50, RC4) —
/// and iOS never runs `HomeWidgetBackgroundWorker` anyway: its widget writes
/// through the app's own App Intent and App Group queue (ADR-0016).
bool homeWidgetCallbackSupported({
  required bool isWeb,
  required TargetPlatform platform,
}) => !isWeb && platform == TargetPlatform.android;

/// The active host. Tests override this with a fake.
final widgetHostProvider = Provider<WidgetHost>((_) => defaultWidgetHost());
