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
/// schedule/cancel/stop across the `alliswell/alarmkit` channel and reports
/// which alarms exist, and what each one is, so that set-diff converges
/// (contract v2, docs/NOTIFICATIONS.md §2b.3).
///
/// **Ids.** The app-assigned integer id is mapped to a deterministic `UUID`
/// (fixed namespace + big-endian id), and back again. That round trip is what
/// makes `scheduledAlarms` possible at all: `AlarmKit.Alarm` exposes `id`,
/// `schedule`, `countdownDuration` and `state` — and NOT the attributes — so
/// what an alarm IS (members, occurrence, fingerprint, origin) lives in the App
/// Group ledger (`AWAlarmLedger`), joined with the OS list on every read.
///
/// **Buttons.** Pressing Onayla/Ertele works while the app is not running, so
/// the presses arrive as `LiveActivityIntent`s that park the action in the
/// shared App Group queue (`AWAlarmActionQueue`). Dart PULLS that queue
/// (`pullPendingActions`) and removes an entry only after applying it
/// (`ackActions`). The only thing ever pushed is `onActionsPending`, with no
/// payload — an acknowledgement dropped because no engine was running, or
/// because the process died before Dart committed it, is exactly the bug this
/// lane exists to avoid.
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
    case "scheduledAlarms":
      result(scheduledAlarms())
    case "scheduledIds":
      result(scheduledAlarms().compactMap { $0["id"] as? Int })
    case "schedule":
      schedule(call.arguments as? [String: Any] ?? [:], result)
    case "cancel":
      cancel(call.arguments as? [String: Any] ?? [:], result)
    case "stop":
      stop(call.arguments as? [String: Any] ?? [:], result)
    case "pullPendingActions":
      result(AWAlarmActionQueue.pending().map(\.dictionary))
    case "ackActions":
      let args = call.arguments as? [String: Any] ?? [:]
      AWAlarmActionQueue.ack(eventIds: args["eventIds"] as? [String] ?? [])
      result(nil)
    case "clearFallbacks":
      clearFallbacks(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "pullFailures":
      result(AWAlarmFailures.pull())
    case "drainPendingActions":
      // Contract v1's push drain. Kept answering for an older Dart, and a
      // no-op: the queue now empties only through `ackActions`, so an old
      // caller neither errors nor loses an entry.
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

  /// Tell Dart to pull when an intent enqueues in this process, and on every
  /// foreground — the two moments a queued press can become deliverable. No
  /// payload: the queue is the only carrier, and Dart acks what it applied.
  private func observeActionSources() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AWAlarmActionQueue.didEnqueue, object: nil, queue: .main
      ) { [weak self] _ in self?.notifyActionsPending() })
    #if canImport(UIKit)
      observers.append(
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.notifyActionsPending() })
    #endif
  }

  private func notifyActionsPending() {
    channel.invokeMethod("onActionsPending", arguments: nil)
  }

  /// Removes the local-notification fallbacks (`aw.fallback.<eventId>`) of
  /// snoozes Dart has applied and re-planned, pending and delivered alike.
  private func clearFallbacks(_ args: [String: Any]) {
    let eventIds = args["eventIds"] as? [String] ?? []
    guard !eventIds.isEmpty else { return }
    #if canImport(UIKit)
      let ids = eventIds.map(AWAlarmFallback.identifier(eventId:))
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: ids)
      center.removeDeliveredNotifications(withIdentifiers: ids)
    #endif
  }

  // MARK: - iOS 26 AlarmKit
  //
  // One implementation per channel method, with the OS check INSIDE it. (Swift
  // will not let two overloads differ only by `@available`, which is what the
  // hand-off draft assumed — it never compiled, because it was never compiled.)

  private func requestAuthorization(_ result: @escaping FlutterResult) {
    #if canImport(AlarmKit) && os(iOS)
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
    #if canImport(AlarmKit) && os(iOS)
      if #available(iOS 26.0, *) {
        result(AlarmManager.shared.authorizationState == .authorized)
        return
      }
    #endif
    result(false)
  }

  /// Every alarm of ours the OS holds, joined with its ledger record:
  /// `[{id, fp, state, members, fireAtMs, origin, eventId}]`. An OS alarm with
  /// no record reads `members: []`, `fp: 0`, `origin: "dart"` and the instant
  /// of its fixed schedule. Records the OS no longer holds are pruned — but
  /// only when the OS list was actually read: a throwing `alarms` prunes
  /// nothing.
  private func scheduledAlarms() -> [[String: Any]] {
    #if canImport(AlarmKit) && os(iOS)
      if #available(iOS 26.0, *) {
        guard let alarms = try? AlarmManager.shared.alarms else { return [] }
        let ours = alarms.compactMap { alarm in appId(from: alarm.id).map { (alarm, $0) } }
        let records = AWAlarmLedger.shared?.records(present: Set(ours.map { $0.1 })) ?? []
        let byId = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ours.map { alarm, id in
          let record = byId[id]
          var row: [String: Any] = [
            "id": id,
            "fp": record?.fp ?? 0,
            "state": stateName(alarm.state),
            "members": record?.members ?? [],
            "fireAtMs": NSNumber(value: record?.fireAtMs ?? fixedFireAtMs(alarm)),
            "origin": record?.origin ?? "dart",
          ]
          let eventId: Any = record?.eventId ?? NSNull()
          row["eventId"] = eventId
          return row
        }
      }
    #endif
    return []
  }

  #if canImport(AlarmKit) && os(iOS)
    @available(iOS 26.0, *)
    private func stateName(_ state: Alarm.State) -> String {
      switch state {
      case .scheduled: return "scheduled"
      case .countdown: return "countdown"
      case .paused: return "paused"
      case .alerting: return "alerting"
      @unknown default: return "scheduled"
      }
    }

    /// The instant of a `.fixed` schedule, floored to the second; 0 when the
    /// alarm has none (we only ever schedule `.fixed`).
    @available(iOS 26.0, *)
    private func fixedFireAtMs(_ alarm: Alarm) -> Int64 {
      if case .fixed(let date)? = alarm.schedule { return AWAlarmIdentity.fireAtMs(date) }
      return 0
    }
  #endif

  private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(AlarmKit) && os(iOS)
      if #available(iOS 26.0, *), let id = args["id"] as? Int {
        try? AlarmManager.shared.cancel(id: uuid(for: id))
        AWAlarmLedger.shared?.remove(id: id)
      }
    #endif
    result(nil)
  }

  /// Silences a ringing alarm: `AlarmManager.stop`, and `cancel` when stop
  /// throws (an alarm that is not alerting cannot be stopped). The ledger
  /// record goes either way. `{stopped, cancelled, error}`.
  private func stop(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["id"] as? Int else {
      result(FlutterError(code: "bad_args", message: "stop needs id", details: nil))
      return
    }
    #if canImport(AlarmKit) && os(iOS)
      if #available(iOS 26.0, *) {
        var stopped = false
        var cancelled = false
        var error: String?
        do {
          try AlarmManager.shared.stop(id: uuid(for: id))
          stopped = true
        } catch let stopError {
          error = "\(stopError)"
          do {
            try AlarmManager.shared.cancel(id: uuid(for: id))
            cancelled = true
          } catch let cancelError {
            error = "stop: \(stopError); cancel: \(cancelError)"
          }
        }
        AWAlarmLedger.shared?.remove(id: id)
        let errorValue: Any = error ?? NSNull()
        result(["stopped": stopped, "cancelled": cancelled, "error": errorValue])
        return
      }
    #endif
    result(["stopped": false, "cancelled": false, "error": "unsupported"])
  }

  private func schedule(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(AlarmKit) && os(iOS)
      if #available(iOS 26.0, *) {
        scheduleWithAlarmKit(args, result)
        return
      }
    #endif
    result(nil)
  }

  #if canImport(AlarmKit) && os(iOS)
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
      let reminderId = args["reminderId"] as? String ?? ""
      // Contract v2: the members (task ids) and the fingerprint. `taskId`
      // alone is what an older Dart sends.
      let legacyTaskId = args["taskId"] as? String ?? ""
      let members = AWAlarmIntentArgs.taskIds(args["members"] as? [String], legacy: legacyTaskId)
      let taskId = members.first ?? legacyTaskId
      // Pre-localized by Dart: the app knows the user's language, this file does
      // not (and a hard-coded "Onayla" was the round-9 bug in miniature).
      let stopLabel = args["stopLabel"] as? String ?? "OK"
      let snoozeLabel = args["snoozeLabel"] as? String ?? "Snooze"
      let snoozePreset = args["snoozePreset"] as? String ?? ""
      // The installed `Library/Sounds` file from OPH-181, or nil for the system
      // alarm sound.
      let soundName = args["soundName"] as? String
      let fp =
        args["fp"] as? Int
        ?? AWAlarmIdentity.fingerprint(
          title: title, body: body, soundName: soundName, stopLabel: stopLabel,
          snoozeLabel: snoozeLabel, snoozePreset: snoozePreset)
      let flooredMs = AWAlarmIdentity.floorToSecond(ms: Int64(fireAtMs))
      let fireDate = Date(timeIntervalSince1970: Double(flooredMs) / 1000.0)

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
            stopIntent = AWAlarmStopIntent(
              taskIds: members, alarmId: id, fireAtMs: flooredMs, reminderId: reminderId)
            if !snoozePreset.isEmpty {
              secondaryIntent = AWAlarmSnoozeIntent(
                taskIds: members, alarmId: id, fireAtMs: flooredMs, title: title, body: body,
                soundName: soundName ?? "", stopLabel: stopLabel, snoozeLabel: snoozeLabel,
                preset: snoozePreset, reminderId: reminderId)
            }
          }

          let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(fireDate),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent,
            sound: soundName.map { AlertConfiguration.AlertSound.named($0) } ?? .default)
          _ = try await AlarmManager.shared.schedule(id: uuid(for: id), configuration: configuration)
          // One record per id: a re-schedule under the same id (new `fp`)
          // replaces the old record.
          AWAlarmLedger.shared?.write(
            AWAlarmLedgerRecord(
              id: id, fp: fp, members: members, fireAtMs: flooredMs, origin: "dart"))
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
          // `.custom` — not `.countdown` — on purpose (see ADR-0015 §9): the
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
