import Foundation

#if canImport(AlarmKit) && canImport(AppIntents) && os(iOS)
  import ActivityKit
  import AlarmKit
  import AppIntents
  import SwiftUI
  import UserNotifications
#endif

/// The native "Ertele" (NOTIFICATIONS.md §2b.3 "Native snooze", #49).
///
/// AlarmKit runs the snooze button's intent with no Flutter engine — often
/// with the app force-quit — so the snooze has to happen here, completely:
/// compute the target, schedule the new alarm, silence the ringing one, leave
/// a local-notification fallback when the new alarm could not be scheduled,
/// write what failed, and park the press for Dart. `.custom` stays the button
/// behaviour (ADR-0015 §9): with `.custom` nothing stops the alert unless this
/// code does, which is exactly what #49 reported.
///
/// The core is pure over [AWAlarmOps], so every failure combination is an
/// injected XCTest (`SnoozeCoreTests`); only `AWAlarmKitOps` touches the OS.
/// It never throws: an intent that throws from an alert leaves the alarm
/// ringing and its buttons dead.

// MARK: - Ids

/// The app id <-> AlarmKit `UUID` mapping: a fixed 8-byte namespace + the id
/// big-endian, so a UUID that is not ours never decodes as an app id.
enum AWAlarmUUID {
  static let namespace: [UInt8] = [0xA1, 0x15, 0x00, 0x00, 0xA1, 0x15, 0x00, 0x00]

  static func uuid(for id: Int) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for i in 0..<8 { bytes[i] = namespace[i] }
    let value = UInt64(bitPattern: Int64(id))
    for i in 0..<8 { bytes[8 + i] = UInt8((value >> (UInt64(56 - i * 8))) & 0xff) }
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
        bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13],
        bytes[14], bytes[15]
      ))
  }

  /// The inverse, or nil when [id] was not minted by [uuid(for:)].
  static func appId(from id: UUID) -> Int? {
    let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
    guard bytes.count == 16 else { return nil }
    for i in 0..<8 where bytes[i] != namespace[i] { return nil }
    var value: UInt64 = 0
    for i in 0..<8 { value = (value << 8) | UInt64(bytes[8 + i]) }
    return Int(Int64(bitPattern: value))
  }
}

// MARK: - The snooze target

/// Where a snooze lands — Dart's `snoozeUntilWallClock`, mirrored and checked
/// against `test/fixtures/snooze_preset_cases.json` (`SnoozeTargetTests`).
enum AWSnoozeTarget {
  static let defaultPreset = "5_min"

  /// [preset] pressed at [pressedAt]: `5_min`, `30_min` and `1_hour` add to
  /// the instant (seconds kept); `tomorrow_morning` is 09:00:00 local on the
  /// calendar day after the press, also when pressed before 09:00. Nil for an
  /// unknown preset. Not floored: the caller floors to the second.
  ///
  /// The +1 minute rule for an occupied minute is applied by [compute].
  static func base(pressedAt: Date, preset: String, calendar: Calendar) -> Date? {
    switch preset {
    case "5_min": return pressedAt.addingTimeInterval(5 * 60)
    case "30_min": return pressedAt.addingTimeInterval(30 * 60)
    case "1_hour": return pressedAt.addingTimeInterval(60 * 60)
    case "tomorrow_morning":
      let today = calendar.startOfDay(for: pressedAt)
      guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
      var parts = calendar.dateComponents([.era, .year, .month, .day], from: tomorrow)
      parts.hour = 9
      parts.minute = 0
      parts.second = 0
      return calendar.date(from: parts)
    default: return nil
    }
  }

  /// How many times the +1 minute rule may move a target.
  static let maxShifts = 30

  /// The native snooze target in UTC epoch ms (§2b.3 "Native snooze", steps
  /// 2–3): [base] floored to the second, then — native only, #47 — moved
  /// +60 s while [ledger] holds a record OTHER than [snoozedAlarmId] whose
  /// UTC minute (`floor(fireAtMs / 60000)`) is the target's; at most
  /// [maxShifts] times, then the last target stays (the Dart plan then
  /// groups that minute into one alarm). The whole group moves together:
  /// one press, one target, one new alarm. Seconds are kept. Nil for an
  /// unknown preset.
  ///
  /// Only the ledger is read — no `takenMinutes` table; Dart writes the
  /// result unchanged and never shifts.
  static func compute(
    pressedAt: Date, preset: String, ledger: [AWAlarmLedgerRecord], snoozedAlarmId: Int?,
    calendar: Calendar
  ) -> Int64? {
    guard let target = base(pressedAt: pressedAt, preset: preset, calendar: calendar) else {
      return nil
    }
    var ms = AWAlarmIdentity.fireAtMs(target)
    let taken = Set(ledger.lazy.filter { $0.id != snoozedAlarmId }.map { minute(of: $0.fireAtMs) })
    var shifts = 0
    while shifts < maxShifts, taken.contains(minute(of: ms)) {
      ms += 60_000
      shifts += 1
    }
    return ms
  }

  /// The UTC minute of [ms]: `floor(ms / 60000)`, also below the epoch.
  static func minute(of ms: Int64) -> Int64 {
    let q = ms / 60_000
    return (ms % 60_000 < 0) ? q - 1 : q
  }
}

// MARK: - What the core asks of the OS

/// One AlarmKit alarm as the app schedules it — from Dart (`schedule`) or
/// from a native snooze. Both build the alert from this, so a snoozed alarm
/// looks and behaves exactly like the one it replaces.
struct AWAlarmSpec: Equatable {
  let id: Int
  /// Floored to the second.
  let fireAtMs: Int64
  let members: [String]
  let title: String
  let body: String
  /// Nil = the system alarm sound.
  let soundName: String?
  let stopLabel: String
  let snoozeLabel: String
  /// Empty = no snooze button.
  let snoozePreset: String
  let reminderId: String

  var fireDate: Date { Date(timeIntervalSince1970: Double(fireAtMs) / 1000.0) }
}

/// The local-notification fallback a failed native snooze leaves behind.
///
/// It must stay reachable through the Dart notification gateway: the sign-out
/// cleanup lists pending requests and cancels each one by id, and
/// `flutter_local_notifications` (22.x) lists a request under
/// `userInfo["NotificationId"]` and cancels the identifier
/// `[NotificationId stringValue]`. So the request identifier is the decimal
/// of the notification id, not a readable name.
enum AWAlarmFallback {
  /// The plugin's notification id: FNV-1a over `aw.fallback.<eventId>`,
  /// 31-bit and positive like every Dart notification id.
  static func notificationId(eventId: String) -> Int {
    AWAlarmIdentity.fnv1a("aw.fallback.\(eventId)")
  }

  /// The `UNNotificationRequest` identifier: `String(notificationId)`.
  static func identifier(eventId: String) -> String {
    String(notificationId(eventId: eventId))
  }
}

/// The local notification a failed native snooze leaves at its target.
struct AWFallbackRequest: Equatable {
  let eventId: String
  let fireAtMs: Int64
  let title: String
  let body: String
  let soundName: String?
  let taskIds: [String]

  /// `AWAlarmFallback.notificationId(eventId:)`.
  var notificationId: Int { AWAlarmFallback.notificationId(eventId: eventId) }

  /// `AWAlarmFallback.identifier(eventId:)`: the decimal of [notificationId].
  var identifier: String { AWAlarmFallback.identifier(eventId: eventId) }

  /// The keys `flutter_local_notifications` (22.x) marks its own requests
  /// with: without them its delegate ignores the buttons, and its pending
  /// list reports `NotificationId` as the id Dart cancels by.
  var userInfo: [String: Any] {
    [
      "NotificationId": NSNumber(value: notificationId),
      "title": title,
      "presentAlert": NSNumber(value: true),
      "presentSound": NSNumber(value: true),
      "presentBadge": NSNumber(value: false),
      "presentBanner": NSNumber(value: true),
      "presentList": NSNumber(value: true),
      "payload": payloadJSON,
    ]
  }

  /// What `flutter_local_notifications` hands Dart as the payload: the same
  /// handler as a scheduled urgent notification's buttons.
  var payloadJSON: String {
    var payload: [String: Any] = ["taskIds": taskIds, "eventId": eventId]
    if let first = taskIds.first { payload["taskId"] = first }
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else { return "{}" }
    return json
  }
}

enum AWAlarmOpsError: Error, Equatable {
  /// AlarmKit's `maximumLimitReached`, which the core records by name.
  case maximumLimitReached
  case unavailable(String)
}

/// The OS calls a native snooze makes. `AWAlarmKitOps` is the real one; tests
/// inject failures one stage at a time.
protocol AWAlarmOps {
  func schedule(_ spec: AWAlarmSpec) async throws
  func stop(id: Int) throws
  func cancel(id: Int) throws
  /// The app ids of our alarms that are ringing now (legacy intents only).
  func alertingIds() throws -> [Int]
  func addFallbackNotification(_ request: AWFallbackRequest) async throws
}

// MARK: - The core

/// A snooze press as the intent received it.
struct AWSnoozeRequest {
  /// The members, resolved from the legacy `taskId` when needed and
  /// de-duplicated in order (the event's and the fallback's `taskIds`).
  let taskIds: [String]
  /// Nil for an alarm scheduled before contract v2 (legacy intent).
  let alarmId: Int?
  /// The occurrence that rang.
  let fireAtMs: Int64?
  let title: String
  let body: String
  /// `""` or nil = the system alarm sound.
  let soundName: String?
  let stopLabel: String
  let snoozeLabel: String
  let preset: String
  let reminderId: String

  init(
    taskIds: [String]?, legacyTaskId: String? = nil, alarmId: Int?, fireAtMs: Int64?,
    title: String?, body: String?, soundName: String?, stopLabel: String?,
    snoozeLabel: String?, preset: String?, reminderId: String? = nil
  ) {
    var seen = Set<String>()
    self.taskIds = AWAlarmIntentArgs.taskIds(taskIds, legacy: legacyTaskId)
      .filter { seen.insert($0).inserted }
    self.alarmId = alarmId
    self.fireAtMs = fireAtMs
    self.title = title ?? ""
    self.body = body ?? ""
    self.soundName = (soundName?.isEmpty ?? true) ? nil : soundName
    self.stopLabel = stopLabel ?? "OK"
    self.snoozeLabel = snoozeLabel ?? "Snooze"
    self.preset = (preset?.isEmpty ?? true) ? AWSnoozeTarget.defaultPreset : preset!
    self.reminderId = reminderId ?? ""
  }

  var isLegacy: Bool { alarmId == nil }
}

/// What one snooze did; the same values ride the queued event.
struct AWSnoozeResult: Equatable {
  let eventId: String
  let untilMs: Int64
  /// Set only when the new alarm was scheduled.
  let newId: Int?
  /// `ok` · `limitReached` · `failed`.
  let scheduleOutcome: String
  /// `stopped` · `cancelled` · `failed`.
  let stopOutcome: String
  let fallbackAdded: Bool
}

/// The outcome of silencing one alarm: `stop`, then `cancel` when stop throws.
struct AWSilenceOutcome: Equatable {
  var stopped = false
  var cancelled = false
  var stopError: String?
  var cancelError: String?

  /// `stopped` · `cancelled` · `failed`.
  var name: String { stopped ? "stopped" : (cancelled ? "cancelled" : "failed") }

  var error: String? {
    switch (stopError, cancelError) {
    case (nil, _): return nil
    case (let s?, nil): return s
    case (let s?, let c?): return "stop: \(s); cancel: \(c)"
    }
  }
}

enum AWSnoozeCore {
  static let legacyMessage = "legacy-intent"
  /// How long a native record published ahead of its alarm survives a prune
  /// while the OS does not list the alarm yet (`pendingUntilMs`). A schedule
  /// takes milliseconds; a process killed mid-schedule leaves a lease that
  /// simply runs out.
  static let publishLeaseMs: Int64 = 60_000
  /// The fallback's title when a legacy intent carries no presentation.
  static let legacyTitle = "AllisWell"

  /// Silences [id]: `stop` (a one-shot `.fixed` alarm is deleted with its
  /// sound), and `cancel` only when stop throws. Shared with the bridge's
  /// `stop` channel method.
  static func silence(id: Int, ops: AWAlarmOps) -> AWSilenceOutcome {
    var outcome = AWSilenceOutcome()
    do {
      try ops.stop(id: id)
      outcome.stopped = true
    } catch {
      outcome.stopError = "\(error)"
      do {
        try ops.cancel(id: id)
        outcome.cancelled = true
      } catch {
        outcome.cancelError = "\(error)"
      }
    }
    return outcome
  }

  /// One native snooze, in the contract's order. Every stage runs whatever
  /// the one before it did; a failing stage is written to
  /// `aw.alarmkit.failures` and never thrown.
  @discardableResult
  static func run(
    _ request: AWSnoozeRequest, ops: AWAlarmOps, ledger: AWAlarmLedger?,
    queue: UserDefaults?, failures: UserDefaults?, now: Date = Date(),
    calendar: Calendar = .current, eventId: String = UUID().uuidString, notify: Bool = true
  ) async -> AWSnoozeResult {
    func fail(_ stage: String, _ code: String, _ message: String) {
      AWAlarmFailures.record(
        eventId: eventId, stage: stage, code: code, message: message, at: now, in: failures)
    }

    // (2)+(3) The target, from the press instant, floored to the second and
    // moved off any minute another alarm of the ledger holds. Read before (5)
    // forgets the ringing alarm, which never counts anyway.
    let held = ledger?.records() ?? []
    let untilMs =
      AWSnoozeTarget.compute(
        pressedAt: now, preset: request.preset, ledger: held, snoozedAlarmId: request.alarmId,
        calendar: calendar)
      ?? AWSnoozeTarget.compute(
        pressedAt: now, preset: AWSnoozeTarget.defaultPreset, ledger: held,
        snoozedAlarmId: request.alarmId, calendar: calendar)!

    // The new occurrence's identity: every member of the group, one alarm.
    let members = AWAlarmIdentity.members(request.taskIds)
    let newId = AWAlarmIdentity.occurrenceId(members: members, fireAtMs: untilMs)
    let fp = AWAlarmIdentity.fingerprint(
      title: request.title, body: request.body, soundName: request.soundName,
      stopLabel: request.stopLabel, snoozeLabel: request.snoozeLabel,
      snoozePreset: request.preset)

    // (4) Schedule the new alarm. A legacy intent carries no presentation to
    // rebuild the alert from, so it never schedules natively.
    var scheduleOutcome = "failed"
    if request.isLegacy {
      fail("schedule", "other", legacyMessage)
    } else {
      let spec = AWAlarmSpec(
        id: newId, fireAtMs: untilMs, members: members, title: request.title,
        body: request.body, soundName: request.soundName, stopLabel: request.stopLabel,
        snoozeLabel: request.snoozeLabel, snoozePreset: request.preset,
        reminderId: request.reminderId)
      // The record is published BEFORE the schedule: the daemon can list the
      // new alarm while `schedule` is still being awaited, and a Dart plan
      // reading `scheduledAlarms` then would find an OS alarm with no record
      // — a stray it cancels. The lease keeps the record through a prune
      // that runs before the OS lists the alarm; a success confirms it, a
      // failure takes it back (restoring whatever held that id before).
      let record = AWAlarmLedgerRecord(
        id: newId, fp: fp, members: members, fireAtMs: untilMs, origin: "native",
        eventId: eventId)
      let before = ledger?.record(id: newId)
      ledger?.write(
        record.pending(until: AWAlarmActionQueue.epochMs(now) + publishLeaseMs))
      do {
        try await ops.schedule(spec)
        scheduleOutcome = "ok"
        ledger?.write(record)
      } catch AWAlarmOpsError.maximumLimitReached {
        scheduleOutcome = "limitReached"
        fail("schedule", "maximumLimitReached", "maximumLimitReached")
      } catch {
        fail("schedule", "other", "\(error)")
      }
      if scheduleOutcome != "ok" {
        if let before { ledger?.write(before) } else { ledger?.remove(id: newId) }
      }
    }

    // (5) Always silence what rang, whatever (4) did.
    var stopOutcome = "failed"
    if let alarmId = request.alarmId {
      let outcome = silence(id: alarmId, ops: ops)
      record(outcome, fail: fail)
      stopOutcome = outcome.name
      if outcome.stopped || outcome.cancelled { ledger?.remove(id: alarmId) }
    } else {
      do {
        let ringing = try ops.alertingIds()
        let outcomes = ringing.map { silence(id: $0, ops: ops) }
        for outcome in outcomes { record(outcome, fail: fail) }
        for (id, outcome) in zip(ringing, outcomes) where outcome.stopped || outcome.cancelled {
          ledger?.remove(id: id)
        }
        if outcomes.contains(where: { $0.name == "failed" }) {
          stopOutcome = "failed"
        } else if outcomes.contains(where: { $0.name == "cancelled" }) {
          stopOutcome = "cancelled"
        } else {
          stopOutcome = "stopped"
        }
      } catch {
        fail("stop", "other", "alarms: \(error)")
      }
    }

    // (6) No new alarm: one time-sensitive reminder at the target instead.
    var fallbackAdded = false
    if scheduleOutcome != "ok" {
      let fallback = AWFallbackRequest(
        eventId: eventId, fireAtMs: untilMs,
        title: request.title.isEmpty ? legacyTitle : request.title, body: request.body,
        soundName: request.soundName, taskIds: request.taskIds)
      do {
        try await ops.addFallbackNotification(fallback)
        fallbackAdded = true
      } catch {
        fail("fallback", "other", "\(error)")
      }
    }

    // (8) Park the press for Dart: ONE event for every member of the group;
    // Dart writes `untilMs` unchanged.
    AWAlarmActionQueue.enqueue(
      action: "snooze", taskIds: request.taskIds, origin: "alarmkit", untilMs: untilMs,
      occurrenceFireAtMs: request.fireAtMs, alarmId: request.alarmId,
      newId: scheduleOutcome == "ok" ? newId : nil, scheduleOutcome: scheduleOutcome,
      stopOutcome: stopOutcome, pressedAt: now, eventId: eventId, in: queue, notify: notify)

    return AWSnoozeResult(
      eventId: eventId, untilMs: untilMs, newId: scheduleOutcome == "ok" ? newId : nil,
      scheduleOutcome: scheduleOutcome, stopOutcome: stopOutcome, fallbackAdded: fallbackAdded)
  }

  /// "Onayla": park an `acknowledge` for the occurrence that rang and forget
  /// its ledger record. AlarmKit stops the alert itself on the stop button.
  @discardableResult
  static func acknowledge(
    taskIds: [String], alarmId: Int?, fireAtMs: Int64?, ledger: AWAlarmLedger?,
    queue: UserDefaults?, now: Date = Date(), eventId: String = UUID().uuidString,
    notify: Bool = true
  ) -> String {
    let id = AWAlarmActionQueue.enqueue(
      action: "acknowledge", taskIds: taskIds, origin: "alarmkit",
      occurrenceFireAtMs: fireAtMs, alarmId: alarmId, pressedAt: now, eventId: eventId,
      in: queue, notify: notify)
    if let alarmId { ledger?.remove(id: alarmId) }
    return id
  }

  private static func record(
    _ outcome: AWSilenceOutcome, fail: (String, String, String) -> Void
  ) {
    if let stopError = outcome.stopError { fail("stop", "other", stopError) }
    if let cancelError = outcome.cancelError { fail("cancel", "other", cancelError) }
  }
}

// MARK: - The real OS calls

#if canImport(AlarmKit) && canImport(AppIntents) && os(iOS)
  /// [AWAlarmOps] over `AlarmManager` and `UNUserNotificationCenter`. The
  /// bridge's `schedule` builds its alarms here too, so a Dart-scheduled and a
  /// natively snoozed alarm have the same alert and the same intents.
  @available(iOS 26.0, *)
  struct AWAlarmKitOps: AWAlarmOps {
    static let urgentCategoryId = "aw_urgent"

    func schedule(_ spec: AWAlarmSpec) async throws {
      let attributes = AlarmAttributes<AWAlarmMetadata>(
        presentation: AlarmPresentation(alert: Self.alert(for: spec)),
        metadata: AWAlarmMetadata(
          awId: spec.id, taskId: spec.members.first ?? "", reminderId: spec.reminderId,
          body: spec.body),
        tintColor: .accentColor)
      let stopIntent = AWAlarmStopIntent(
        taskIds: spec.members, alarmId: spec.id, fireAtMs: spec.fireAtMs,
        reminderId: spec.reminderId)
      let secondaryIntent: AWAlarmSnoozeIntent? =
        spec.snoozePreset.isEmpty
        ? nil
        : AWAlarmSnoozeIntent(
          taskIds: spec.members, alarmId: spec.id, fireAtMs: spec.fireAtMs, title: spec.title,
          body: spec.body, soundName: spec.soundName ?? "", stopLabel: spec.stopLabel,
          snoozeLabel: spec.snoozeLabel, preset: spec.snoozePreset, reminderId: spec.reminderId)
      let configuration = AlarmManager.AlarmConfiguration(
        schedule: .fixed(spec.fireDate),
        attributes: attributes,
        stopIntent: stopIntent,
        secondaryIntent: secondaryIntent,
        sound: spec.soundName.map { AlertConfiguration.AlertSound.named($0) } ?? .default)
      do {
        _ = try await AlarmManager.shared.schedule(
          id: AWAlarmUUID.uuid(for: spec.id), configuration: configuration)
      } catch AlarmManager.AlarmError.maximumLimitReached {
        throw AWAlarmOpsError.maximumLimitReached
      }
    }

    func stop(id: Int) throws {
      try AlarmManager.shared.stop(id: AWAlarmUUID.uuid(for: id))
    }

    func cancel(id: Int) throws {
      try AlarmManager.shared.cancel(id: AWAlarmUUID.uuid(for: id))
    }

    func alertingIds() throws -> [Int] {
      try AlarmManager.shared.alarms
        .filter { $0.state == .alerting }
        .compactMap { AWAlarmUUID.appId(from: $0.id) }
    }

    func addFallbackNotification(_ request: AWFallbackRequest) async throws {
      let content = UNMutableNotificationContent()
      content.title = request.title
      content.body = request.body
      content.categoryIdentifier = Self.urgentCategoryId
      content.interruptionLevel = .timeSensitive
      content.sound =
        request.soundName.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        ?? .default
      content.userInfo = request.userInfo
      let fireAt = Date(timeIntervalSince1970: Double(request.fireAtMs) / 1000.0)
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: max(1, fireAt.timeIntervalSinceNow), repeats: false)
      try await UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    /// iOS 26.1 retired `stopButton` (the system draws its own); 26.0 still
    /// requires it. Both initializers exist in the SDK — pick by OS so a 26.0
    /// device is not left without an alert.
    static func alert(for spec: AWAlarmSpec) -> AlarmPresentation.Alert {
      let snoozeButton = AlarmButton(
        text: LocalizedStringResource(stringLiteral: spec.snoozeLabel),
        textColor: .white,
        systemImageName: "clock")
      if #available(iOS 26.1, *) {
        return AlarmPresentation.Alert(
          title: LocalizedStringResource(stringLiteral: spec.title),
          secondaryButton: snoozeButton,
          // `.custom` — not `.countdown` — on purpose (ADR-0015 §9): the Dart
          // planner owns WHEN an alarm exists, and a countdown cannot express
          // `tomorrow_morning`. With `.custom` the snooze intent itself
          // silences the alert (`AWSnoozeCore`).
          secondaryButtonBehavior: .custom)
      }
      return AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: spec.title),
        stopButton: AlarmButton(
          text: LocalizedStringResource(stringLiteral: spec.stopLabel),
          textColor: .white,
          systemImageName: "checkmark"),
        secondaryButton: snoozeButton,
        secondaryButtonBehavior: .custom)
    }
  }
#endif
