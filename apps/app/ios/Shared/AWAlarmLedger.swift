import Foundation

/// The AlarmKit ledger and failure ring (NOTIFICATIONS.md §2b.3 "App Group keys", #49).
///
/// `AlarmKit.Alarm` carries no attributes, so after a relaunch the OS can tell
/// us only an alarm's id, schedule and state. The ledger is the side table that
/// says what each of our alarms IS: its members (task ids), its occurrence
/// instant, its presentation fingerprint and who scheduled it (`dart` through
/// the bridge, `native` from a snooze pressed with no Flutter engine). The OS
/// stays the truth about which alarms exist: a record the daemon no longer
/// holds is dropped the next time the ledger is read against it.
///
/// Foundation only, so the app, the widget extension and the tests compile it
/// alike; every `AlarmManager` call stays in the bridge and the intents. The
/// store is injected, so a test runs on a throw-away suite.
struct AWAlarmLedgerRecord: Equatable {
  let id: Int
  let fp: Int
  let members: [String]
  let fireAtMs: Int64
  /// `dart` or `native`.
  let origin: String
  /// The snooze event that scheduled a `native` record.
  let eventId: String?
  /// Set while the record is published AHEAD of its alarm: a native snooze
  /// writes its record before `AlarmManager.schedule` (the daemon can list
  /// the new alarm before that call returns, and an OS alarm with no record
  /// looks like a stray to the Dart plan). Until this UTC ms instant the
  /// prune keeps the record although the OS does not list the alarm yet;
  /// nil once the schedule is confirmed.
  let pendingUntilMs: Int64?

  init(
    id: Int, fp: Int, members: [String], fireAtMs: Int64, origin: String,
    eventId: String? = nil, pendingUntilMs: Int64? = nil
  ) {
    self.id = id
    self.fp = fp
    self.members = members
    self.fireAtMs = fireAtMs
    self.origin = origin
    self.eventId = eventId
    self.pendingUntilMs = pendingUntilMs
  }

  /// This record with the pending lease set to [untilMs] (nil = confirmed).
  func pending(until untilMs: Int64?) -> AWAlarmLedgerRecord {
    AWAlarmLedgerRecord(
      id: id, fp: fp, members: members, fireAtMs: fireAtMs, origin: origin, eventId: eventId,
      pendingUntilMs: untilMs)
  }

  init?(dictionary d: [String: Any]) {
    guard
      let id = (d["id"] as? NSNumber)?.intValue,
      let fireAtMs = (d["fireAtMs"] as? NSNumber)?.int64Value
    else { return nil }
    self.init(
      id: id,
      fp: (d["fp"] as? NSNumber)?.intValue ?? 0,
      members: d["members"] as? [String] ?? [],
      fireAtMs: fireAtMs,
      origin: d["origin"] as? String ?? "dart",
      eventId: d["eventId"] as? String,
      pendingUntilMs: (d["pendingUntilMs"] as? NSNumber)?.int64Value)
  }

  /// Plist values only (App Group `UserDefaults`); no `eventId` key when nil.
  var dictionary: [String: Any] {
    var d: [String: Any] = [
      "id": NSNumber(value: id),
      "fp": NSNumber(value: fp),
      "members": members,
      "fireAtMs": NSNumber(value: fireAtMs),
      "origin": origin,
    ]
    if let eventId { d["eventId"] = eventId }
    if let pendingUntilMs { d["pendingUntilMs"] = NSNumber(value: pendingUntilMs) }
    return d
  }
}

struct AWAlarmLedger {
  static let key = "aw.alarmkit.ledger"

  /// One lock per process; the app and the widget extension are separate
  /// processes, and only the app's intents and bridge write the ledger.
  private static let lock = NSLock()

  let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  /// The App Group ledger, or nil when the group container is unavailable.
  static var shared: AWAlarmLedger? {
    UserDefaults(suiteName: AWAlarmActionQueue.appGroupId).map(AWAlarmLedger.init(defaults:))
  }

  /// Every record, malformed entries skipped.
  func records() -> [AWAlarmLedgerRecord] {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return load()
  }

  func record(id: Int) -> AWAlarmLedgerRecord? {
    records().first { $0.id == id }
  }

  /// The records whose alarm the daemon still holds ([present] = the app ids
  /// of `AlarmManager.shared.alarms`); the rest are removed from the store —
  /// except a record published ahead of its alarm whose lease
  /// (`pendingUntilMs`) has not run out at [now]: it is kept in the store
  /// (its schedule is still in flight) but not returned, since the OS does
  /// not list it. Call it only with a list the OS actually returned: an empty
  /// set prunes every record that is not pending.
  func records(present: Set<Int>, now: Date = Date()) -> [AWAlarmLedgerRecord] {
    records(now: now) { present }
  }

  /// [records(present:now:)] with the OS list read by [list] UNDER the
  /// ledger lock — what the bridge's `scheduledAlarms` uses. A list read
  /// outside the lock can be older than a record written before the prune:
  /// a native snooze that confirms its record (lease cleared) after the list
  /// was read, its alarm not in that list, would lose the record, and the
  /// next plan would cancel the new alarm as a stray. Under the lock that
  /// write waits for the prune. A throwing [list] prunes nothing. [list] must
  /// not touch the ledger (the lock is not recursive).
  func records(
    now: Date = Date(), listedBy list: () throws -> Set<Int>
  ) rethrows -> [AWAlarmLedgerRecord] {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let present = try list()
    let nowMs = AWAlarmActionQueue.epochMs(now)
    let all = load()
    let stored = all.filter { r in
      present.contains(r.id) || (r.pendingUntilMs.map { nowMs < $0 } ?? false)
    }
    if stored.count != all.count { save(stored) }
    return stored.filter { present.contains($0.id) }
  }

  /// Writes [record], replacing any record with its id.
  func write(_ record: AWAlarmLedgerRecord) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var all = load().filter { $0.id != record.id }
    all.append(record)
    save(all)
  }

  func remove(id: Int) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let all = load()
    let kept = all.filter { $0.id != id }
    if kept.count != all.count { save(kept) }
  }

  private func load() -> [AWAlarmLedgerRecord] {
    let raw = defaults.array(forKey: Self.key) ?? []
    var seen = Set<Int>()
    var out: [AWAlarmLedgerRecord] = []
    for case let d as [String: Any] in raw {
      guard let r = AWAlarmLedgerRecord(dictionary: d), seen.insert(r.id).inserted else { continue }
      out.append(r)
    }
    return out
  }

  private func save(_ records: [AWAlarmLedgerRecord]) {
    if records.isEmpty {
      defaults.removeObject(forKey: Self.key)
    } else {
      defaults.set(records.map(\.dictionary), forKey: Self.key)
    }
  }
}

/// `aw.alarmkit.failures`: what a native stage (schedule, stop, cancel,
/// fallback) could not do, for Dart's alarm log (`degraded`, lane `alarmkit`).
/// A ring of the last 50; `pull` hands the rows over and removes them.
enum AWAlarmFailures {
  static let key = "aw.alarmkit.failures"
  static let capacity = 50
  private static let lock = NSLock()

  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: AWAlarmActionQueue.appGroupId)
  }

  /// [stage] `schedule`·`stop`·`cancel`·`fallback`; [code]
  /// `maximumLimitReached`·`other`.
  static func record(
    eventId: String, stage: String, code: String, message: String, at: Date = Date(),
    in defaults: UserDefaults? = sharedDefaults
  ) {
    guard let defaults else { return }
    lock.lock()
    defer { lock.unlock() }
    var rows = defaults.array(forKey: key) as? [[String: Any]] ?? []
    rows.append([
      "eventId": eventId,
      "atMs": NSNumber(value: AWAlarmActionQueue.epochMs(at)),
      "stage": stage,
      "code": code,
      "message": message,
    ])
    if rows.count > capacity { rows.removeFirst(rows.count - capacity) }
    defaults.set(rows, forKey: key)
  }

  /// Every recorded failure, oldest first; the returned rows are removed.
  static func pull(in defaults: UserDefaults? = sharedDefaults) -> [[String: Any]] {
    guard let defaults else { return [] }
    lock.lock()
    defer { lock.unlock() }
    let rows = defaults.array(forKey: key) as? [[String: Any]] ?? []
    if !rows.isEmpty { defaults.removeObject(forKey: key) }
    return rows
  }
}
