import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
  /// Lives as long as the window: its channels answer for the whole session
  /// (OPH-335).
  private var widgetBridge: AWMacWidgetBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    widgetBridge = AWMacWidgetBridge(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// OPH-335 — the macOS half of what `home_widget` does on iOS and Android.
///
/// `home_widget` 0.9.3 declares android and ios only, so on a Mac every
/// snapshot write ended in a MissingPluginException nobody saw, and a macOS
/// widget would have had nothing to read. This writes the SAME key into the
/// SAME App Group the widget reads (`group.com.alliswell.alliswell`), and asks
/// WidgetKit to redraw.
///
/// It also answers `alliswell/alarmkit`'s drain on the Mac. The widget's
/// complete intent (`AWWidgetCompleteIntent`) parks the tap in the App Group
/// queue (`AWAlarmActionQueue`, `aw_alarm_pending_actions`) exactly as it does
/// on iOS, and Dart already listens for `onAlarmAction` on that channel and
/// already knows what "complete" means — so one Dart path serves both. Every
/// other method on that channel answers what a missing plugin answered before:
/// there is no AlarmKit on a Mac, and the urgent lane stays on notifications.
final class AWMacWidgetBridge {
  private static let appGroupId = "group.com.alliswell.alliswell"
  private static let actionsKey = "aw_alarm_pending_actions"

  private let widget: FlutterMethodChannel
  private let alarms: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    widget = FlutterMethodChannel(name: "alliswell/widget", binaryMessenger: messenger)
    alarms = FlutterMethodChannel(name: "alliswell/alarmkit", binaryMessenger: messenger)
    widget.setMethodCallHandler { [weak self] call, result in self?.onWidget(call, result) }
    alarms.setMethodCallHandler { [weak self] call, result in self?.onAlarms(call, result) }
    // A tap on the widget while the app sat in the background waits in the
    // queue; the app coming forward is when it becomes deliverable. (Dart asks
    // once more on its own, the moment its handler exists.)
    observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.drain() }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  private var defaults: UserDefaults? { UserDefaults(suiteName: Self.appGroupId) }

  private func onWidget(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "save":
      guard
        let args = call.arguments as? [String: Any],
        let key = args["key"] as? String,
        let value = args["value"] as? String
      else {
        result(FlutterError(code: "bad-args", message: "save needs key and value", details: nil))
        return
      }
      defaults?.set(value, forKey: key)
      result(nil)
    case "update":
      WidgetCenter.shared.reloadAllTimelines()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func onAlarms(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "drainPendingActions":
      drain()
      result(nil)
    case "isSupported", "isAuthorized", "requestAuthorization":
      result(false)
    case "scheduledIds":
      result([Int]())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Same payload shape as the iOS bridge's (`AlarmKitBridge.payloadJson`), so
  /// the one Dart handler cannot tell the platforms apart.
  private func drain() {
    guard
      let defaults,
      let queued = defaults.array(forKey: Self.actionsKey) as? [[String: String]],
      !queued.isEmpty
    else { return }
    defaults.removeObject(forKey: Self.actionsKey)
    for action in queued {
      guard let actionId = action["actionId"] else { continue }
      let payload = ["taskId": action["taskId"] ?? "", "reminderId": action["reminderId"] ?? ""]
      guard
        let data = try? JSONSerialization.data(withJSONObject: payload),
        let json = String(data: data, encoding: .utf8)
      else { continue }
      alarms.invokeMethod("onAlarmAction", arguments: ["actionId": actionId, "payload": json])
    }
  }
}
