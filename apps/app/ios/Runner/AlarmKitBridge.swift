import Flutter
import Foundation

#if canImport(AlarmKit)
  import ActivityKit
  import AlarmKit
#endif
#if canImport(AppIntents)
  import AppIntents
#endif
#if canImport(UIKit)
  import UIKit
  import UserNotifications
#endif

/// Runner-side bridge for the iOS 26+ AlarmKit URGENT lane (OPH-141 wrote it,
/// OPH-182 connected it — docs/NOTIFICATIONS.md §2b).
///
/// The Dart side (`lib/src/notifications/alarmkit.dart` + `planner.dart` +
/// `scheduler.dart`) is the single source of truth: it decides WHICH alarms
/// should exist, in which language their buttons are labelled, which sound they
/// carry and how long "Ertele" postpones them. This class only carries
/// schedule/cancel across the `alliswell/alarmkit` channel and reports which
/// alarms exist so that set-diff converges.
///
/// **Ids.** The app-assigned integer id is mapped to a deterministic `UUID`
/// (fixed namespace + big-endian id), and back again. That round trip is what
/// makes `scheduledIds` possible at all: `AlarmKit.Alarm` exposes `id`,
/// `schedule`, `countdownDuration` and `state` — and NOT the attributes — so
/// there is no metadata to read back after a relaunch.
///
/// **Buttons.** Pressing Onayla/Ertele works while the app is not running, so
/// the presses arrive as `LiveActivityIntent`s that park the action in the
/// shared App Group queue (`AWAlarmActionQueue`). Dart drains that queue as soon
/// as it has a handler installed, and again on every foreground. Nothing is
/// pushed down the channel speculatively — an acknowledgement dropped because no
/// engine was running is exactly the bug this lane exists to avoid.
///
/// Gated on iOS 26: on older systems `isSupported` returns false and the whole
/// URGENT lane stays on OPH-139 time-sensitive notifications.
final class AlarmKitBridge {
  static let channelName = "alliswell/alarmkit"

  private let channel: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    observeActionSources()
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
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
    case "isAuthorized":
      isAuthorized(result)
    case "timeSensitiveEnabled":
      timeSensitiveEnabled(result)
    case "scheduledIds":
      scheduledIds(result)
    case "schedule":
      schedule(call.arguments as? [String: Any] ?? [:], result)
    case "cancel":
      cancel(call.arguments as? [String: Any] ?? [:], result)
    case "drainPendingActions":
      drainPendingActions()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Deterministic id <-> UUID mapping

  /// Namespace bytes that mark a UUID as ours, so a foreign alarm (or a stale
  /// one from another app writing into the same store) is never decoded as an
  /// app id.
  private static let namespace: [UInt8] = [0xA1, 0x15, 0x00, 0x00, 0xA1, 0x15, 0x00, 0x00]

  /// A stable UUID for an app id: fixed 8-byte namespace + the id big-endian.
  /// Lets `cancel` target the exact AlarmKit alarm without a stored table.
  private func uuid(for id: Int) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<8 { bytes[i] = Self.namespace[i] }
    let value = UInt64(bitPattern: Int64(id))
    for i in 0..<8 { bytes[8 + i] = UInt8((value >> (UInt64(56 - i * 8))) & 0xff) }
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
        bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13],
        bytes[14], bytes[15]
      ))
  }

  /// The inverse, or nil when the UUID was not minted by [uuid(for:)].
  private func appId(from id: UUID) -> Int? {
    let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
    guard bytes.count == 16 else { return nil }
    for i in 0..<8 where bytes[i] != Self.namespace[i] { return nil }
    var value: UInt64 = 0
    for i in 0..<8 { value = (value << 8) | UInt64(bytes[8 + i]) }
    return Int(Int64(bitPattern: value))
  }

  // MARK: - Button presses

  /// Forward whatever the intents parked while we may or may not have been
  /// running. Safe to call at any time: the queue empties as it is read.
  private func drainPendingActions() {
    let queued = AWAlarmActionQueue.drain()
    guard !queued.isEmpty else { return }
    for action in queued {
      guard let actionId = action["actionId"] else { continue }
      let payload = payloadJson(
        taskId: action["taskId"] ?? "", reminderId: action["reminderId"] ?? "")
      DispatchQueue.main.async { [weak self] in
        self?.channel.invokeMethod(
          "onAlarmAction", arguments: ["actionId": actionId, "payload": payload])
      }
    }
  }

  /// Drain when an intent runs in this process, and on every foreground — the
  /// two moments a queued press can become deliverable.
  private func observeActionSources() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AWAlarmActionQueue.didEnqueue, object: nil, queue: .main
      ) { [weak self] _ in self?.drainPendingActions() })
    #if canImport(UIKit)
      observers.append(
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.drainPendingActions() })
    #endif
  }

  /// The same JSON shape the notification lane's payload uses, so one Dart
  /// handler serves both lanes.
  private func payloadJson(taskId: String, reminderId: String) -> String {
    let payload: [String: String] = ["taskId": taskId, "reminderId": reminderId]
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }

  // MARK: - iOS 26 AlarmKit
  //
  // One implementation per channel method, with the OS check INSIDE it. (Swift
  // will not let two overloads differ only by `@available`, which is what the
  // hand-off draft assumed — it never compiled, because it was never compiled.)

  private func requestAuthorization(_ result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          do {
            let state = try await AlarmManager.shared.requestAuthorization()
            result(state == .authorized)
          } catch {
            result(false)
          }
        }
        return
      }
    #endif
    result(false)
  }

  /// The iOS 15+ Time Sensitive allowance (round 19, OPH-277).
  ///
  /// Not an AlarmKit question, and it lives here anyway: this file is the only
  /// Runner source already in the Xcode target, and adding a second one means
  /// editing `project.pbxproj` — which this project has been bitten by before
  /// (see the `flutter_launcher_icons` note in `pubspec.yaml`).
  ///
  /// It matters because the failure is invisible. Without the allowance iOS
  /// silently demotes `.timeSensitive` to `.active`, and from then on every
  /// Focus mode — including Sleep — buries the alarm with no error anywhere.
  /// NOTIFICATIONS §2 has called this "the most common silent failure" since
  /// the entitlement was added, and nothing was checking it.
  private func timeSensitiveEnabled(_ result: @escaping FlutterResult) {
    #if canImport(UIKit)
      if #available(iOS 15.0, *) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          switch settings.timeSensitiveSetting {
          case .enabled:
            result(true)
          case .disabled:
            result(false)
          default:
            // `.notSupported` — the device cannot answer, so neither can we.
            // Reporting `false` here would nag every iPad on an old OS.
            result(nil)
          }
        }
        return
      }
    #endif
    result(nil)
  }

  /// The grant, READ rather than requested (round 19 K4).
  ///
  /// `requestAuthorization` is documented to answer from the OS record after
  /// the first decision, but it is still the *asking* call, and the scheduler
  /// now consults this on every apply — a permission dialog that appears
  /// because a task's due date changed would be its own bug. So this reads the
  /// state and never prompts.
  private func isAuthorized(_ result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        result(AlarmManager.shared.authorizationState == .authorized)
        return
      }
    #endif
    result(false)
  }

  private func scheduledIds(_ result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        // `Alarm` carries no attributes, so the id round trip IS the recovery
        // mechanism — see the note on `uuid(for:)`.
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        result(alarms.compactMap { appId(from: $0.id) })
        return
      }
    #endif
    result([Int]())
  }

  private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *), let id = args["id"] as? Int {
        try? AlarmManager.shared.cancel(id: uuid(for: id))
      }
    #endif
    result(nil)
  }

  private func schedule(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        scheduleWithAlarmKit(args, result)
        return
      }
    #endif
    result(nil)
  }

  #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleWithAlarmKit(_ args: [String: Any], _ result: @escaping FlutterResult) {
      guard
        let id = args["id"] as? Int,
        let title = args["title"] as? String,
        let fireAtMs = args["fireAtMs"] as? Int
      else {
        result(
          FlutterError(code: "bad_args", message: "schedule needs id/title/fireAtMs", details: nil))
        return
      }
      let body = args["body"] as? String ?? ""
      let taskId = args["taskId"] as? String ?? ""
      let reminderId = args["reminderId"] as? String ?? ""
      // Pre-localized by Dart: the app knows the user's language, this file does
      // not (and a hard-coded "Onayla" was the round-9 bug in miniature).
      let stopLabel = args["stopLabel"] as? String ?? "OK"
      let snoozeLabel = args["snoozeLabel"] as? String ?? "Snooze"
      let snoozePreset = args["snoozePreset"] as? String ?? ""
      // The installed `Library/Sounds` file from OPH-181, or nil for the system
      // alarm sound.
      let soundName = args["soundName"] as? String
      let fireDate = Date(timeIntervalSince1970: Double(fireAtMs) / 1000.0)

      Task {
        do {
          let alert = alertPresentation(
            title: title, stopLabel: stopLabel, snoozeLabel: snoozeLabel)
          let attributes = AlarmAttributes<AWAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: AWAlarmMetadata(
              awId: id, taskId: taskId, reminderId: reminderId, body: body),
            tintColor: .accentColor)

          var stopIntent: (any LiveActivityIntent)?
          var secondaryIntent: (any LiveActivityIntent)?
          if #available(iOS 17.0, *) {
            stopIntent = AWAlarmStopIntent(taskId: taskId, reminderId: reminderId)
            if !snoozePreset.isEmpty {
              secondaryIntent = AWAlarmSnoozeIntent(
                taskId: taskId, reminderId: reminderId, preset: snoozePreset)
            }
          }

          let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent,
            sound: soundName.map { AlertConfiguration.AlertSound.named($0) } ?? .default)
          _ = try await AlarmManager.shared.schedule(id: uuid(for: id), configuration: configuration)
          result(nil)
        } catch AlarmManager.AlarmError.maximumLimitReached {
          // The per-app ceiling is undocumented, so this is the only honest way
          // to learn it. Dart writes it to the alarm log and leaves the alarm on
          // the notification lane rather than pretending it is covered.
          result(
            FlutterError(code: "limit_reached", message: "AlarmKit alarm limit reached", details: nil)
          )
        } catch {
          result(FlutterError(code: "schedule_failed", message: "\(error)", details: nil))
        }
      }
    }

    /// iOS 26.1 retired `stopButton` (the system draws its own); 26.0 still
    /// requires it. Both initializers exist in the SDK — pick by OS so a 26.0
    /// device is not left without an alert.
    @available(iOS 26.0, *)
    private func alertPresentation(
      title: String, stopLabel: String, snoozeLabel: String
    ) -> AlarmPresentation.Alert {
      let snoozeButton = AlarmButton(
        text: LocalizedStringResource(stringLiteral: snoozeLabel),
        textColor: .white,
        systemImageName: "clock")
      if #available(iOS 26.1, *) {
        return AlarmPresentation.Alert(
          title: LocalizedStringResource(stringLiteral: title),
          secondaryButton: snoozeButton,
          // `.custom` — not `.countdown` — on purpose (see ADR-0015 §8): the
          // Dart planner owns WHEN an alarm exists. A native countdown would
          // re-ring an alarm the planner also re-schedules (two alerts), and the
          // snooze would stay invisible to the task row and to every other
          // device.
          secondaryButtonBehavior: .custom)
      }
      return AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        stopButton: AlarmButton(
          text: LocalizedStringResource(stringLiteral: stopLabel),
          textColor: .white,
          systemImageName: "checkmark"),
        secondaryButton: snoozeButton,
        secondaryButtonBehavior: .custom)
    }
  #endif
}
