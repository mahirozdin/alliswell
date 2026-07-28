import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the app's lifetime: the bridge owns the AlarmKit method channel
  /// and the observers that drain queued Onayla/Ertele presses (OPH-182).
  private var alarmKitBridge: AlarmKitBridge?

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
  }
}
