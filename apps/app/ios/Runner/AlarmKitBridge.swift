import Flutter
import Foundation

#if canImport(AlarmKit)
  import AlarmKit
#endif

/// Runner-side bridge for the iOS 26+ AlarmKit URGENT lane (OPH-141,
/// docs/NOTIFICATIONS.md §2b).
///
/// The Dart side (`lib/src/notifications/alarmkit.dart` + `planner.dart` +
/// `scheduler.dart`) is the single source of truth: it decides WHICH alarms
/// should exist and diffs desired-vs-scheduled by an integer content-hash id.
/// This class only carries schedule/cancel across the `alliswell/alarmkit`
/// channel and reports which alarms exist so that set-diff converges. The
/// app-assigned integer id is both stored in the alarm metadata AND mapped to a
/// deterministic `UUID`, so `cancel(id:)` needs no lookup and `scheduledIds`
/// recovers the ids after a relaunch.
///
/// Gated on iOS 26: on older systems `isSupported` returns false and the whole
/// URGENT lane stays on OPH-139 time-sensitive notifications — no behavioural
/// change for < 26 or non-urgent reminders.
///
/// STATUS: written for the device pass (AlarmKit only compiles against the iOS
/// 26 SDK on a real target/device — `flutter analyze`/`test` never touch it).
/// The channel contract + id mapping are final; confirm the exact AlarmKit
/// value types (`AlarmPresentation`, `AlarmConfiguration`) against the SDK on
/// first build. Same hand-off shape as the widget extension (OPH-131).
final class AlarmKitBridge {
  static let channelName = "alliswell/alarmkit"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    if #available(iOS 26.0, *) {
      startObservingAlarmUpdates()
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      if #available(iOS 26.0, *) {
        result(true)
      } else {
        result(false)
      }
    case "requestAuthorization":
      requestAuthorization(result)
    case "scheduledIds":
      scheduledIds(result)
    case "schedule":
      schedule(call.arguments as? [String: Any] ?? [:], result)
    case "cancel":
      cancel(call.arguments as? [String: Any] ?? [:], result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Deterministic id <-> UUID mapping

  /// A stable UUID for an app id: fixed 8-byte namespace + the id big-endian.
  /// Lets `cancel` target the exact AlarmKit alarm without a stored table.
  private func uuid(for id: Int) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    let ns: [UInt8] = [0xA1, 0x15, 0x00, 0x00, 0xA1, 0x15, 0x00, 0x00]  // "AllisWell"
    for i in 0..<8 { bytes[i] = ns[i] }
    let value = UInt64(bitPattern: Int64(id))
    for i in 0..<8 { bytes[8 + i] = UInt8((value >> (UInt64(56 - i * 8))) & 0xff) }
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
      bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
      bytes[15]))
  }

  // MARK: - iOS 26 AlarmKit

  #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func requestAuthorization(_ result: @escaping FlutterResult) {
      Task {
        do {
          let state = try await AlarmManager.shared.requestAuthorization()
          result(state == .authorized)
        } catch {
          result(false)
        }
      }
    }

    @available(iOS 26.0, *)
    private func scheduledIds(_ result: @escaping FlutterResult) {
      Task {
        // Recover the app ids from live alarms' metadata (survives relaunch).
        let ids = (try? await AlarmManager.shared.alarms)?.compactMap { alarm in
          (alarm.attributes.metadata as? AWAlarmMetadata)?.awId
        } ?? []
        result(ids)
      }
    }

    @available(iOS 26.0, *)
    private func schedule(_ args: [String: Any], _ result: @escaping FlutterResult) {
      guard
        let id = args["id"] as? Int,
        let title = args["title"] as? String,
        let fireAtMs = args["fireAtMs"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "schedule needs id/title/fireAtMs", details: nil))
        return
      }
      let body = args["body"] as? String ?? ""
      let taskId = args["taskId"] as? String ?? ""
      let reminderId = args["reminderId"] as? String ?? ""
      let fireDate = Date(timeIntervalSince1970: Double(fireAtMs) / 1000.0)

      Task {
        do {
          let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(
              text: "Onayla", textColor: .white, systemImageName: "checkmark"),
            secondaryButton: AlarmButton(
              text: "Ertele", textColor: .white, systemImageName: "clock"),
            secondaryButtonBehavior: .countdown)
          let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: AWAlarmMetadata(
              awId: id, taskId: taskId, reminderId: reminderId, body: body),
            tintColor: .accentColor)
          let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(fireDate), attributes: attributes)
          _ = try await AlarmManager.shared.schedule(
            id: uuid(for: id), configuration: configuration)
          result(nil)
        } catch {
          result(FlutterError(code: "schedule_failed", message: "\(error)", details: nil))
        }
      }
    }

    @available(iOS 26.0, *)
    private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) {
      guard let id = args["id"] as? Int else {
        result(nil)
        return
      }
      Task {
        try? AlarmManager.shared.cancel(id: uuid(for: id))
        result(nil)
      }
    }

    /// Forward Onayla (stop) presses to Dart as an `acknowledge` action so the
    /// task's reminder is acknowledged in our data model (and cancels the alarm
    /// on every other device via sync). Ertele/countdown is handled by AlarmKit
    /// natively; the reschedule then flows back through the planner. Exact
    /// state-transition names to be confirmed on the device pass.
    @available(iOS 26.0, *)
    private func startObservingAlarmUpdates() {
      Task {
        for await alarms in AlarmManager.shared.alarmUpdates {
          for alarm in alarms where alarm.state == .stopped {
            guard let meta = alarm.attributes.metadata as? AWAlarmMetadata else { continue }
            forwardAction("acknowledge", meta: meta)
          }
        }
      }
    }

    private func forwardAction(_ actionId: String, meta: AWAlarmMetadata) {
      let payload = "{\"taskId\":\"\(meta.taskId)\",\"reminderId\":\"\(meta.reminderId)\"}"
      DispatchQueue.main.async {
        self.channel.invokeMethod(
          "onAlarmAction", arguments: ["actionId": actionId, "payload": payload])
      }
    }
  #endif

  // MARK: - Pre-iOS 26 / no AlarmKit — every method degrades to a no-op

  #if !canImport(AlarmKit)
    private func requestAuthorization(_ result: @escaping FlutterResult) { result(false) }
    private func scheduledIds(_ result: @escaping FlutterResult) { result([Int]()) }
    private func schedule(_ args: [String: Any], _ result: @escaping FlutterResult) { result(nil) }
    private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) { result(nil) }
  #endif

  // Fallbacks used when AlarmKit imports but the OS is < 26 (guards above pick
  // the @available paths; these satisfy the compiler for the older branch).
  #if canImport(AlarmKit)
    @available(iOS, obsoleted: 26.0)
    private func requestAuthorization(_ result: @escaping FlutterResult) { result(false) }
    @available(iOS, obsoleted: 26.0)
    private func scheduledIds(_ result: @escaping FlutterResult) { result([Int]()) }
    @available(iOS, obsoleted: 26.0)
    private func schedule(_ args: [String: Any], _ result: @escaping FlutterResult) { result(nil) }
    @available(iOS, obsoleted: 26.0)
    private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) { result(nil) }
  #endif
}

#if canImport(AlarmKit)
  /// Metadata rides with each AlarmKit alarm so `scheduledIds` recovers the
  /// app id after a relaunch and an acknowledge knows which task/reminder to
  /// resolve. Confirm `AlarmMetadata` conformance requirements on the device.
  @available(iOS 26.0, *)
  struct AWAlarmMetadata: AlarmMetadata {
    let awId: Int
    let taskId: String
    let reminderId: String
    let body: String
  }
#endif
