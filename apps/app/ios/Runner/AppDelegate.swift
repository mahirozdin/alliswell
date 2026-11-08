import AVFoundation
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

  /// Held for the app's lifetime: the channel Dart drains Siri / Shortcuts
  /// requests through (OPH-376, ADR-0057; `Shared/AWAppShortcuts.swift`).
  private var captureBridge: AWCaptureBridge?

  /// R-10 (OPH-402): Dart asks this before dictation starts. Held for the
  /// app's lifetime like the bridges above.
  private var audioInputChannel: FlutterMethodChannel?

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
    // OPH-376 (ADR-0057): without this line a "Hey Siri, add a task" request
    // waits in its mailbox forever — the intent parks it, nobody hands it over.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AWCaptureBridge") {
      captureBridge = AWCaptureBridge(messenger: registrar.messenger())
    }
    // R-10 (OPH-402): `speech_to_text` reads `AVAudioEngine.inputNode` when
    // it starts listening. On a device with no audio input (a simulator on a
    // Mac without a microphone) AudioToolbox times out on an RPC and calls
    // abort() — a SIGABRT nothing can catch. A plain property read on the
    // session is safe, so Dart asks here first and does not start the
    // recognizer when the answer is no (`lib/src/features/ai/data/stt.dart`).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AWAudioInput") {
      let channel = FlutterMethodChannel(
        name: "alliswell/audio_input", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "isInputAvailable":
          result(AVAudioSession.sharedInstance().isInputAvailable)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      audioInputChannel = channel
    }
  }
}
