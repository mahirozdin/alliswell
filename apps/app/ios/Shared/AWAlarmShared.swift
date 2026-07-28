import Foundation

#if canImport(AlarmKit)
  import AlarmKit
#endif
#if canImport(AppIntents)
  import AppIntents
#endif

/// Types the app target and the widget extension BOTH compile (OPH-182).
///
/// AlarmKit's alert is an `ActivityAttributes`, so the alarm's metadata type has
/// to exist on both sides of the app/extension boundary: the app builds the
/// `AlarmAttributes` it schedules, and the widget extension's
/// `ActivityConfiguration` decodes the same type to render the Live Activity.
/// One file, two target memberships — see `ALARMKIT_SETUP.md`.

// MARK: - The alarm's own metadata

#if canImport(AlarmKit)
  /// Rides with every AlarmKit alarm. `awId` is the app's content-hash id (the
  /// same integer the Dart set-diff uses), so a relaunch can map an OS alarm back
  /// to the reminder that asked for it without a side table.
  @available(iOS 26.0, *)
  struct AWAlarmMetadata: AlarmMetadata {
    let awId: Int
    let taskId: String
    let reminderId: String
    let body: String
  }
#endif

// MARK: - The action queue (app group)

/// Where a stop/snooze press is parked until Dart can be told about it.
///
/// The reason this queue exists: AlarmKit rings — and its buttons work —
/// while the app is **not running**. iOS launches the app in the background to
/// perform the intent, which happens long before (or entirely without) a Flutter
/// engine and a method-channel handler. Pushing straight down the channel would
/// drop the acknowledgement on exactly the path that matters most: the alarm
/// that woke someone at 03:00 from a cold app.
///
/// So the intent writes; the bridge drains when Dart says it is listening
/// (`drainPendingActions`) and again on every foreground.
enum AWAlarmActionQueue {
  static let appGroupId = "group.com.alliswell.alliswell"
  static let defaultsKey = "aw_alarm_pending_actions"

  /// Posted in-process after an enqueue so a live bridge forwards immediately
  /// instead of waiting for the next foreground.
  static let didEnqueue = Notification.Name("AWAlarmActionQueueDidEnqueue")

  private static let lock = NSLock()

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

  static func enqueue(actionId: String, taskId: String, reminderId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard let defaults else { return }
    var queued = defaults.array(forKey: defaultsKey) as? [[String: String]] ?? []
    queued.append([
      "actionId": actionId,
      "taskId": taskId,
      "reminderId": reminderId,
    ])
    // A queue that grows without bound would replay a year of alarms on the next
    // launch. Keep the recent tail; anything older is already stale.
    if queued.count > 32 { queued.removeFirst(queued.count - 32) }
    defaults.set(queued, forKey: defaultsKey)
    NotificationCenter.default.post(name: didEnqueue, object: nil)
  }

  /// Returns everything queued and empties the queue in one step.
  static func drain() -> [[String: String]] {
    lock.lock()
    defer { lock.unlock() }
    guard let defaults else { return [] }
    let queued = defaults.array(forKey: defaultsKey) as? [[String: String]] ?? []
    if !queued.isEmpty { defaults.removeObject(forKey: defaultsKey) }
    return queued
  }
}

// MARK: - The alert's buttons, as App Intents

#if canImport(AppIntents)
  /// "Onayla" on the AlarmKit alert. Acknowledges the reminder in our data model
  /// (and therefore on every other device, through sync).
  @available(iOS 17.0, *)
  struct AWAlarmStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Acknowledge alarm"
    static var description = IntentDescription("Acknowledges an AllisWell alarm.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task") var taskId: String
    @Parameter(title: "Reminder") var reminderId: String

    init() {}

    init(taskId: String, reminderId: String) {
      self.taskId = taskId
      self.reminderId = reminderId
    }

    func perform() async throws -> some IntentResult {
      AWAlarmActionQueue.enqueue(
        actionId: "acknowledge", taskId: taskId, reminderId: reminderId)
      return .result()
    }
  }

  /// The home-screen widget's completion circle (OPH-188).
  ///
  /// It rides the SAME rails round 9 built for the alarm buttons rather than a
  /// second mechanism: WidgetKit runs `perform()` in the background with no
  /// Flutter engine guaranteed, so the press is parked in the app-group queue
  /// and drained the moment Dart is listening. `actionId` is the app's existing
  /// `complete`, which already routes into `TaskStore.complete` — the same
  /// optimistic + outbox write the UI uses, so a completion from the widget
  /// syncs like any other and works offline.
  @available(iOS 17.0, *)
  struct AWCompleteTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var description = IntentDescription("Marks an AllisWell task done.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task") var taskId: String

    init() {}

    init(taskId: String) {
      self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
      AWAlarmActionQueue.enqueue(actionId: "complete", taskId: taskId, reminderId: "")
      return .result()
    }
  }

  /// "Ertele" on the AlarmKit alert. AlarmKit re-presents the alarm itself
  /// (`.countdown`); this only records the same snooze in our model so the task
  /// row, the other devices and the notification lane agree with what the phone
  /// just did. [preset] is one of the app's snooze preset ids.
  @available(iOS 17.0, *)
  struct AWAlarmSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze alarm"
    static var description = IntentDescription("Snoozes an AllisWell alarm.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task") var taskId: String
    @Parameter(title: "Reminder") var reminderId: String
    @Parameter(title: "Preset") var preset: String

    init() {}

    init(taskId: String, reminderId: String, preset: String) {
      self.taskId = taskId
      self.reminderId = reminderId
      self.preset = preset
    }

    func perform() async throws -> some IntentResult {
      AWAlarmActionQueue.enqueue(
        actionId: "snooze:\(preset)", taskId: taskId, reminderId: reminderId)
      return .result()
    }
  }
#endif
