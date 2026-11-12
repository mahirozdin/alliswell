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

/// One press, as it waits in the App Group queue (NOTIFICATIONS.md §2b.3
/// "Action event", queue entry v2). Also the shape Dart reads through
/// `pullPendingActions`.
struct AWAlarmActionEvent: Equatable {
  let eventId: String
  /// `snooze` · `acknowledge` · `complete`.
  let action: String
  let taskIds: [String]
  var untilMs: Int64? = nil
  /// Only on an entry converted from v1 (no `untilMs`).
  var preset: String? = nil
  var occurrenceFireAtMs: Int64? = nil
  let pressedAtMs: Int64
  /// `alarmkit` · `widget`.
  let origin: String
  var alarmId: Int? = nil
  var newId: Int? = nil
  /// `ok` · `limitReached` · `failed`.
  var scheduleOutcome: String? = nil
  /// `stopped` · `cancelled` · `failed`.
  var stopOutcome: String? = nil

  init(
    eventId: String, action: String, taskIds: [String], untilMs: Int64? = nil,
    preset: String? = nil, occurrenceFireAtMs: Int64? = nil, pressedAtMs: Int64,
    origin: String, alarmId: Int? = nil, newId: Int? = nil, scheduleOutcome: String? = nil,
    stopOutcome: String? = nil
  ) {
    self.eventId = eventId
    self.action = action
    self.taskIds = taskIds
    self.untilMs = untilMs
    self.preset = preset
    self.occurrenceFireAtMs = occurrenceFireAtMs
    self.pressedAtMs = pressedAtMs
    self.origin = origin
    self.alarmId = alarmId
    self.newId = newId
    self.scheduleOutcome = scheduleOutcome
    self.stopOutcome = stopOutcome
  }

  /// A v2 entry, or nil when [d] is not one.
  init?(dictionary d: [String: Any]) {
    guard
      let eventId = d["eventId"] as? String, !eventId.isEmpty,
      let action = d["action"] as? String,
      let pressedAtMs = (d["pressedAtMs"] as? NSNumber)?.int64Value
    else { return nil }
    self.init(
      eventId: eventId, action: action, taskIds: d["taskIds"] as? [String] ?? [],
      untilMs: (d["untilMs"] as? NSNumber)?.int64Value, preset: d["preset"] as? String,
      occurrenceFireAtMs: (d["occurrenceFireAtMs"] as? NSNumber)?.int64Value,
      pressedAtMs: pressedAtMs, origin: d["origin"] as? String ?? "alarmkit",
      alarmId: (d["alarmId"] as? NSNumber)?.intValue, newId: (d["newId"] as? NSNumber)?.intValue,
      scheduleOutcome: d["scheduleOutcome"] as? String, stopOutcome: d["stopOutcome"] as? String)
  }

  /// A v1 entry `{actionId: "acknowledge"·"complete"·"snooze:<preset>", taskId,
  /// reminderId}` rewritten as v2: a new `eventId`, `pressedAtMs` = [now],
  /// `taskIds: [taskId]`, and the `preset` of a snooze (no `untilMs`: Dart
  /// computes the target from `pressedAtMs`). v1 `complete` only ever came
  /// from the widget; the other two from the AlarmKit alert.
  init?(v1 d: [String: Any], now: Date) {
    guard let actionId = d["actionId"] as? String, !actionId.isEmpty else { return nil }
    let taskId = d["taskId"] as? String ?? ""
    var action = actionId
    var preset: String?
    if actionId.hasPrefix("snooze:") {
      action = "snooze"
      preset = String(actionId.dropFirst("snooze:".count))
    }
    self.init(
      eventId: UUID().uuidString, action: action, taskIds: taskId.isEmpty ? [] : [taskId],
      preset: preset, pressedAtMs: AWAlarmActionQueue.epochMs(now),
      origin: action == "complete" ? "widget" : "alarmkit")
  }

  /// Plist values only, so it is both the App Group entry and the channel
  /// payload; an absent optional is an absent key, never `NSNull`.
  var dictionary: [String: Any] {
    var d: [String: Any] = [
      "eventId": eventId,
      "action": action,
      "taskIds": taskIds,
      "pressedAtMs": NSNumber(value: pressedAtMs),
      "origin": origin,
    ]
    if let untilMs { d["untilMs"] = NSNumber(value: untilMs) }
    if let preset { d["preset"] = preset }
    if let occurrenceFireAtMs { d["occurrenceFireAtMs"] = NSNumber(value: occurrenceFireAtMs) }
    if let alarmId { d["alarmId"] = NSNumber(value: alarmId) }
    if let newId { d["newId"] = NSNumber(value: newId) }
    if let scheduleOutcome { d["scheduleOutcome"] = scheduleOutcome }
    if let stopOutcome { d["stopOutcome"] = stopOutcome }
    return d
  }
}

/// Where a stop/snooze/complete press is parked until Dart has applied it.
///
/// AlarmKit rings — and its buttons work — while the app is **not running**,
/// and the widget's circle runs in the widget process. Both write here; Dart
/// pulls (`pullPendingActions`), applies each event in one transaction keyed by
/// its `eventId`, and only then acks (`ackActions`). Nothing is removed on
/// read: a process that dies between the read and the commit gets the same
/// event again, and the receipt makes the second apply a no-op.
///
/// Foundation only: the macOS widget compiles this file for the queue.
enum AWAlarmActionQueue {
  static let appGroupId = "group.com.alliswell.alliswell"
  static let defaultsKey = "aw_alarm_pending_actions"
  static let capacity = 32

  /// Posted in-process after an enqueue so a live bridge tells Dart to pull
  /// instead of waiting for the next foreground.
  static let didEnqueue = Notification.Name("AWAlarmActionQueueDidEnqueue")

  private static let lock = NSLock()

  static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

  /// UTC epoch milliseconds of [date].
  static func epochMs(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  /// Appends a v2 event and returns its `eventId`. [taskIds] are
  /// de-duplicated in order. The oldest entry goes only when the queue holds
  /// [capacity] already (a year of presses must not replay on a launch).
  @discardableResult
  static func enqueue(
    action: String, taskIds: [String], origin: String, untilMs: Int64? = nil,
    preset: String? = nil, occurrenceFireAtMs: Int64? = nil, alarmId: Int? = nil,
    newId: Int? = nil, scheduleOutcome: String? = nil, stopOutcome: String? = nil,
    pressedAt: Date = Date(), eventId: String = UUID().uuidString,
    in defaults: UserDefaults? = sharedDefaults, notify: Bool = true
  ) -> String {
    var seen = Set<String>()
    let event = AWAlarmActionEvent(
      eventId: eventId, action: action, taskIds: taskIds.filter { seen.insert($0).inserted },
      untilMs: untilMs, preset: preset, occurrenceFireAtMs: occurrenceFireAtMs,
      pressedAtMs: epochMs(pressedAt), origin: origin, alarmId: alarmId, newId: newId,
      scheduleOutcome: scheduleOutcome, stopOutcome: stopOutcome)
    guard let defaults else { return eventId }
    lock.lock()
    var queued = defaults.array(forKey: defaultsKey) ?? []
    queued.append(event.dictionary)
    if queued.count > capacity { queued.removeFirst(queued.count - capacity) }
    defaults.set(queued, forKey: defaultsKey)
    lock.unlock()
    if notify { NotificationCenter.default.post(name: didEnqueue, object: nil) }
    return eventId
  }

  /// Everything queued, sorted by `pressedAtMs` (queue order on a tie), and
  /// **not removed**. A v1 entry is rewritten as v2 in the store on this first
  /// read, so its `eventId` stays the same on every later read. An entry that
  /// is neither v1 nor v2 is dropped.
  static func pending(
    in defaults: UserDefaults? = sharedDefaults, now: Date = Date()
  ) -> [AWAlarmActionEvent] {
    guard let defaults else { return [] }
    lock.lock()
    defer { lock.unlock() }
    let raw = defaults.array(forKey: defaultsKey) ?? []
    var events: [AWAlarmActionEvent] = []
    var rewritten = false
    for item in raw {
      guard let d = item as? [String: Any] else {
        rewritten = true
        continue
      }
      if let event = AWAlarmActionEvent(dictionary: d) {
        events.append(event)
      } else if let event = AWAlarmActionEvent(v1: d, now: now) {
        events.append(event)
        rewritten = true
      } else {
        rewritten = true
      }
    }
    if rewritten { save(events, to: defaults) }
    return events.enumerated()
      .sorted { a, b in
        a.element.pressedAtMs != b.element.pressedAtMs
          ? a.element.pressedAtMs < b.element.pressedAtMs : a.offset < b.offset
      }
      .map(\.element)
  }

  /// Removes the entries named by [eventIds]; unknown ids are ignored.
  static func ack(eventIds: [String], in defaults: UserDefaults? = sharedDefaults) {
    guard let defaults, !eventIds.isEmpty else { return }
    let acked = Set(eventIds)
    lock.lock()
    defer { lock.unlock() }
    let raw = defaults.array(forKey: defaultsKey) ?? []
    let kept = raw.filter { item in
      guard let id = (item as? [String: Any])?["eventId"] as? String else { return true }
      return !acked.contains(id)
    }
    if kept.count != raw.count {
      if kept.isEmpty {
        defaults.removeObject(forKey: defaultsKey)
      } else {
        defaults.set(kept, forKey: defaultsKey)
      }
    }
  }

  private static func save(_ events: [AWAlarmActionEvent], to defaults: UserDefaults) {
    if events.isEmpty {
      defaults.removeObject(forKey: defaultsKey)
    } else {
      defaults.set(events.map(\.dictionary), forKey: defaultsKey)
    }
  }
}

/// The local-notification fallback a failed native snooze leaves behind.
enum AWAlarmFallback {
  static func identifier(eventId: String) -> String { "aw.fallback.\(eventId)" }
}

/// The member list an alarm intent applies to: `taskIds` when the alarm was
/// scheduled under contract v2, else the legacy single `taskId` (an alarm
/// scheduled by an older build keeps ringing with its old intents).
enum AWAlarmIntentArgs {
  static func taskIds(_ taskIds: [String]?, legacy taskId: String?) -> [String] {
    if let taskIds, !taskIds.isEmpty { return taskIds }
    if let taskId, !taskId.isEmpty { return [taskId] }
    return []
  }
}

// MARK: - The alert's buttons, as App Intents

// iOS only: these are `LiveActivityIntent`s — AlarmKit's alert is a Live
// Activity, and neither exists on macOS. The macOS widget (OPH-335) compiles
// this file for the QUEUE above, which its complete intent writes into.
// iOS 26: AlarmKit is the only thing that ever runs them.
//
// Every v2 parameter is optional: an alarm scheduled by an older build carries
// only `taskId` / `reminderId` (and `preset`), and a missing non-optional
// parameter would make the system ask for a value no one is there to give.
#if canImport(AppIntents) && os(iOS)
  /// "Onayla" on the AlarmKit alert. Acknowledges every member's active urgent
  /// reminder at the instant that rang (and so on every other device, through
  /// sync). AlarmKit stops the alert itself; the ledger forgets the alarm.
  @available(iOS 26.0, *)
  struct AWAlarmStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Acknowledge alarm"
    static var description = IntentDescription("Acknowledges an AllisWell alarm.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Tasks") var taskIds: [String]?
    @Parameter(title: "Alarm") var alarmId: Int?
    @Parameter(title: "Fire at") var fireAtMs: Int?
    @Parameter(title: "Task") var taskId: String?
    @Parameter(title: "Reminder") var reminderId: String?

    init() {}

    init(taskIds: [String], alarmId: Int, fireAtMs: Int64, reminderId: String = "") {
      self.taskIds = taskIds
      self.alarmId = alarmId
      self.fireAtMs = Int(fireAtMs)
      self.taskId = taskIds.first
      self.reminderId = reminderId
    }

    func perform() async throws -> some IntentResult {
      AWSnoozeCore.acknowledge(
        taskIds: AWAlarmIntentArgs.taskIds(taskIds, legacy: taskId), alarmId: alarmId,
        fireAtMs: fireAtMs.map(Int64.init), ledger: AWAlarmLedger.shared,
        queue: AWAlarmActionQueue.sharedDefaults)
      return .result()
    }
  }

  /// "Ertele" on the AlarmKit alert (`.custom` behaviour, ADR-0015 §9).
  /// With `.custom` the system only runs this intent — nothing silences the
  /// alert unless it does. It carries the whole presentation, so the snooze
  /// happens natively and completely, app running or not
  /// (`AWSnoozeCore.run`): the target is computed at the press, the new alarm
  /// is scheduled, the ringing one is ALWAYS stopped, a failed schedule leaves
  /// a fallback notification, and the press is parked for Dart with its
  /// `untilMs`. It never throws: a throwing intent leaves the alarm ringing.
  @available(iOS 26.0, *)
  struct AWAlarmSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze alarm"
    static var description = IntentDescription("Snoozes an AllisWell alarm.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes = .background
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Tasks") var taskIds: [String]?
    @Parameter(title: "Alarm") var alarmId: Int?
    @Parameter(title: "Fire at") var fireAtMs: Int?
    @Parameter(title: "Title") var alarmTitle: String?
    @Parameter(title: "Body") var body: String?
    @Parameter(title: "Sound") var soundName: String?
    @Parameter(title: "Stop label") var stopLabel: String?
    @Parameter(title: "Snooze label") var snoozeLabel: String?
    @Parameter(title: "Preset") var preset: String
    @Parameter(title: "Task") var taskId: String?
    @Parameter(title: "Reminder") var reminderId: String?

    init() {}

    /// [soundName] `""` = the system alarm sound.
    init(
      taskIds: [String], alarmId: Int, fireAtMs: Int64, title: String, body: String,
      soundName: String, stopLabel: String, snoozeLabel: String, preset: String,
      reminderId: String = ""
    ) {
      self.taskIds = taskIds
      self.alarmId = alarmId
      self.fireAtMs = Int(fireAtMs)
      self.alarmTitle = title
      self.body = body
      self.soundName = soundName
      self.stopLabel = stopLabel
      self.snoozeLabel = snoozeLabel
      self.preset = preset
      self.taskId = taskIds.first
      self.reminderId = reminderId
    }

    func perform() async throws -> some IntentResult {
      #if canImport(AlarmKit)
        let request = AWSnoozeRequest(
          taskIds: taskIds, legacyTaskId: taskId, alarmId: alarmId,
          fireAtMs: fireAtMs.map(Int64.init), title: alarmTitle, body: body,
          soundName: soundName, stopLabel: stopLabel, snoozeLabel: snoozeLabel, preset: preset,
          reminderId: reminderId)
        await AWSnoozeCore.run(
          request, ops: AWAlarmKitOps(), ledger: AWAlarmLedger.shared,
          queue: AWAlarmActionQueue.sharedDefaults, failures: AWAlarmFailures.sharedDefaults)
      #endif
      return .result()
    }
  }
#endif
