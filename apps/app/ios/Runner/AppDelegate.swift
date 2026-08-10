import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the app's lifetime: the bridge owns the AlarmKit method channel
  /// and the observers that drain queued Onayla/Ertele presses (OPH-182).
  private var alarmKitBridge: AlarmKitBridge?

  /// Held for the app's lifetime for the same reason: the bridge owns the
  /// channel Dart calls to drain the Share Extension's App Group mailbox
  /// (OPH-242, ADR-0029).
  private var shareInboxBridge: ShareInboxBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // OPH-182: the iOS 26 AlarmKit lane. Without this line the channel is never
    // registered, `isSupported()` throws MissingPluginException, and every
    // urgent alarm silently stays on the notification lane that the mute switch
    // can silence — which is exactly how round 9 lost its evening.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlarmKitBridge") {
      alarmKitBridge = AlarmKitBridge(messenger: registrar.messenger())
    }
    // OPH-242 (ADR-0029): without this line the shared payload reaches the App
    // Group and is never read — the plugin only fills its buffers from a URL
    // open, and an appex can no longer trigger one.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareInboxBridge") {
      shareInboxBridge = ShareInboxBridge(messenger: registrar.messenger())
    }
  }
}
