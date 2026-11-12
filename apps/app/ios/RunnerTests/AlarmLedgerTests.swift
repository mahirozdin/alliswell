import Foundation
import XCTest

@testable import Runner

/// The AlarmKit ledger, the v2 action queue and the failure ring
/// (NOTIFICATIONS.md §2b.3 "App Group keys", #49).
///
/// Every test runs against a throw-away `UserDefaults` suite, never the App
/// Group, so a test run cannot eat a real queued press on the simulator.
final class AlarmLedgerTests: XCTestCase {

  private var suiteName = ""
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    suiteName = "aw.tests.ledger.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  private func record(
    id: Int, fp: Int = 7, members: [String] = ["t1"], fireAtMs: Int64 = 1_784_116_800_000,
    origin: String = "dart", eventId: String? = nil
  ) -> AWAlarmLedgerRecord {
    AWAlarmLedgerRecord(
      id: id, fp: fp, members: members, fireAtMs: fireAtMs, origin: origin, eventId: eventId)
  }

  // MARK: - Ledger

  func testWriteReadRemoveRoundTrip() {
    let ledger = AWAlarmLedger(defaults: defaults)
    XCTAssertEqual(ledger.records(), [])

    let a = record(id: 11, fp: 1, members: ["t1", "t2"])
    let b = record(id: 22, fp: 2, origin: "native", eventId: "E-1")
    ledger.write(a)
    ledger.write(b)
    XCTAssertEqual(ledger.records(), [a, b])

    // One record per id: a second write replaces, it does not append.
    let a2 = record(id: 11, fp: 3, members: ["t1", "t2"])
    ledger.write(a2)
    XCTAssertEqual(ledger.records().count, 2)
    XCTAssertEqual(ledger.record(id: 11), a2)

    // A fresh instance over the same store reads the same thing back (it is
    // the store, not the instance, that holds the ledger).
    let reread = AWAlarmLedger(defaults: defaults).record(id: 22)
    XCTAssertEqual(reread, b)
    XCTAssertEqual(reread?.eventId, "E-1")
    XCTAssertNil(AWAlarmLedger(defaults: defaults).record(id: 11)?.eventId)

    ledger.remove(id: 11)
    XCTAssertEqual(ledger.records(), [b])
    ledger.remove(id: 999)  // unknown: ignored
    XCTAssertEqual(ledger.records(), [b])
    ledger.remove(id: 22)
    XCTAssertEqual(ledger.records(), [])

    // The App Group shape the contract names: plain plist values.
    ledger.write(b)
    let raw = defaults.array(forKey: AWAlarmLedger.key) as? [[String: Any]]
    XCTAssertEqual(raw?.count, 1)
    XCTAssertEqual(raw?.first?["origin"] as? String, "native")
    XCTAssertEqual((raw?.first?["fireAtMs"] as? NSNumber)?.int64Value, 1_784_116_800_000)
  }

  func testPruneDropsRecordsTheDaemonNoLongerHas() {
    let ledger = AWAlarmLedger(defaults: defaults)
    ledger.write(record(id: 1))
    ledger.write(record(id: 2))
    ledger.write(record(id: 3, origin: "native", eventId: "E-3"))

    let kept = ledger.records(present: [1, 3, 42])
    XCTAssertEqual(kept.map(\.id), [1, 3])
    // Dropped from the store, not only from the answer.
    XCTAssertEqual(ledger.records().map(\.id), [1, 3])

    // An empty daemon empties the ledger.
    XCTAssertEqual(ledger.records(present: []), [])
    XCTAssertEqual(ledger.records(), [])

    // A malformed entry is dropped on read instead of breaking the rest.
    defaults.set(
      [["id": 5, "fp": 1, "members": ["t"], "fireAtMs": 1000, "origin": "dart"], ["junk": true]],
      forKey: AWAlarmLedger.key)
    XCTAssertEqual(ledger.records().map(\.id), [5])
  }

  /// A native record published ahead of its alarm (`pendingUntilMs`)
  /// survives a prune while its lease runs and the OS does not list it yet;
  /// a lease that ran out (a process killed mid-schedule) is pruned.
  func testPruneKeepsARecordPublishedAheadOfItsAlarmUntilItsLeaseRunsOut() {
    let ledger = AWAlarmLedger(defaults: defaults)
    let now = Date(timeIntervalSince1970: 1_784_116_800)
    let nowMs: Int64 = 1_784_116_800_000
    let pending = AWAlarmLedgerRecord(
      id: 9, fp: 1, members: ["t1"], fireAtMs: nowMs + 300_000, origin: "native",
      eventId: "E-9", pendingUntilMs: nowMs + 60_000)
    ledger.write(pending)
    ledger.write(record(id: 1))

    // The OS lists neither: the dart record goes, the pending one stays in
    // the store but is not answered (the OS does not hold it yet).
    XCTAssertEqual(ledger.records(present: [], now: now), [])
    XCTAssertEqual(ledger.records(), [pending])
    // The OS lists it: answered, lease and all.
    XCTAssertEqual(ledger.records(present: [9], now: now), [pending])
    // Round trip through the store keeps the lease.
    let raw = defaults.array(forKey: AWAlarmLedger.key) as? [[String: Any]]
    XCTAssertEqual((raw?.first?["pendingUntilMs"] as? NSNumber)?.int64Value, nowMs + 60_000)

    // The lease ran out and the OS never listed it: pruned.
    XCTAssertEqual(ledger.records(present: [], now: now.addingTimeInterval(60)), [])
    XCTAssertEqual(ledger.records(), [])
  }

  /// The bridge's `scheduledAlarms` reads the OS list and prunes against it.
  /// A native snooze that confirms its record (lease cleared) after that list
  /// was read — the list does not hold the new alarm yet — must not lose the
  /// record to the prune: the next plan would then find the new alarm with
  /// no record (`origin: dart`, no members) and cancel it as a stray, and no
  /// fallback stands in for a snooze that scheduled fine. So the OS list is
  /// read under the ledger lock, and the confirmation waits for the prune.
  func testPruneReadsTheOSListUnderTheLedgerLockSoALaterConfirmationSurvives() {
    let ledger = AWAlarmLedger(defaults: defaults)
    let now = Date(timeIntervalSince1970: 1_784_116_800)
    let confirmed = record(id: 9, origin: "native", eventId: "E-9")
    let written = expectation(description: "the snooze confirmed its record")

    let answered = ledger.records(now: now) { () -> Set<Int> in
      // The OS list as read before the snooze's schedule returned: no 9.
      // Meanwhile the snooze's schedule returns and it confirms its record.
      DispatchQueue.global().async {
        ledger.write(confirmed)
        written.fulfill()
      }
      Thread.sleep(forTimeInterval: 0.3)
      return []
    }
    wait(for: [written], timeout: 5)

    XCTAssertEqual(answered, [], "the list read did not hold 9, so 9 is not answered")
    XCTAssertEqual(ledger.records(), [confirmed], "the confirmed record survives the prune")
    // The next read, with the alarm listed, answers it.
    XCTAssertEqual(ledger.records(present: [9], now: now), [confirmed])
  }

  /// A list read that throws prunes nothing and rethrows.
  func testAListReadThatThrowsPrunesNothing() {
    let ledger = AWAlarmLedger(defaults: defaults)
    ledger.write(record(id: 1))
    struct Boom: Error {}
    XCTAssertThrowsError(try ledger.records { () throws -> Set<Int> in throw Boom() })
    XCTAssertEqual(ledger.records().map(\.id), [1])
  }

  // MARK: - Action queue v2

  func testQueueKeepsEntriesUntilAcked() {
    let now = Date(timeIntervalSince1970: 1_784_116_800)
    let first = AWAlarmActionQueue.enqueue(
      action: "acknowledge", taskIds: ["t1", "t2", "t1"], origin: "alarmkit",
      occurrenceFireAtMs: 1_784_116_800_000, alarmId: 11, pressedAt: now,
      in: defaults, notify: false)
    let second = AWAlarmActionQueue.enqueue(
      action: "complete", taskIds: ["t3"], origin: "widget",
      pressedAt: now.addingTimeInterval(5), in: defaults, notify: false)

    // Reading is not consuming: two reads, same two entries, in press order.
    let read1 = AWAlarmActionQueue.pending(in: defaults)
    let read2 = AWAlarmActionQueue.pending(in: defaults)
    XCTAssertEqual(read1.map(\.eventId), [first, second])
    XCTAssertEqual(read2.map(\.eventId), [first, second])

    let ack = read1[0]
    XCTAssertEqual(ack.action, "acknowledge")
    XCTAssertEqual(ack.taskIds, ["t1", "t2"])  // de-duplicated, order kept
    XCTAssertEqual(ack.origin, "alarmkit")
    XCTAssertEqual(ack.occurrenceFireAtMs, 1_784_116_800_000)
    XCTAssertEqual(ack.alarmId, 11)
    XCTAssertEqual(ack.pressedAtMs, 1_784_116_800_000)
    XCTAssertNil(ack.untilMs)
    XCTAssertNil(ack.preset)

    // The channel shape: absent optionals are absent, not NSNull.
    let wire = read1[1].dictionary
    XCTAssertEqual(wire["eventId"] as? String, second)
    XCTAssertEqual(wire["action"] as? String, "complete")
    XCTAssertEqual(wire["taskIds"] as? [String], ["t3"])
    XCTAssertEqual(wire["origin"] as? String, "widget")
    XCTAssertNil(wire["untilMs"])
    XCTAssertNil(wire["alarmId"])
    XCTAssertNil(wire[AWAlarmActionQueue.queuedAtKey], "store-only, never on the channel")

    // Ack removes exactly what it names; unknown ids are ignored.
    AWAlarmActionQueue.ack(eventIds: [first, "nope"], in: defaults)
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults).map(\.eventId), [second])
    AWAlarmActionQueue.ack(eventIds: [], in: defaults)
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults).map(\.eventId), [second])
    AWAlarmActionQueue.ack(eventIds: [second], in: defaults)
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults), [])

    // Cap 32: the oldest go only when the queue is full.
    var ids: [String] = []
    for i in 0..<40 {
      ids.append(
        AWAlarmActionQueue.enqueue(
          action: "complete", taskIds: ["t\(i)"], origin: "widget",
          pressedAt: now.addingTimeInterval(Double(i)), in: defaults, notify: false))
    }
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults).map(\.eventId), Array(ids.suffix(32)))
  }

  /// `UserDefaults` that lets "another process" write between this
  /// process's first touch of the store and the rest of its operation: the
  /// app and the widget extension each have their own lock, so nothing
  /// in-process orders them.
  private final class RacingDefaults: UserDefaults {
    var race: (() -> Void)?

    private func runRace() {
      guard let race else { return }
      self.race = nil
      race()
    }

    override func object(forKey defaultName: String) -> Any? {
      let value = super.object(forKey: defaultName)
      runRace()
      return value
    }

    override func dictionaryRepresentation() -> [String: Any] {
      let value = super.dictionaryRepresentation()
      runRace()
      return value
    }

    override func set(_ value: Any?, forKey defaultName: String) {
      runRace()
      super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
      runRace()
      super.removeObject(forKey: defaultName)
    }
  }

  /// The widget extension's complete press, written from its own process
  /// (its own store handle; no lock of this process is held around it).
  private func widgetEnqueue(_ taskId: String, at: Date) -> String {
    AWAlarmActionQueue.enqueue(
      action: "complete", taskIds: [taskId], origin: "widget", pressedAt: at, in: defaults,
      notify: false)
  }

  /// OPH-430: retained until acked. With [A] queued, the app's ack(A) and
  /// the widget's enqueue(B) interleave; B must survive the ack.
  func testAckNeverDropsAnEntryAnotherProcessQueuedMeanwhile() throws {
    let now = Date(timeIntervalSince1970: 1_784_116_800)
    let a = AWAlarmActionQueue.enqueue(
      action: "acknowledge", taskIds: ["t1"], origin: "alarmkit", pressedAt: now,
      in: defaults, notify: false)
    let app = try XCTUnwrap(RacingDefaults(suiteName: suiteName))
    var b = ""
    app.race = { b = self.widgetEnqueue("t9", at: now.addingTimeInterval(1)) }

    AWAlarmActionQueue.ack(eventIds: [a], in: app)

    XCTAssertFalse(b.isEmpty, "the widget wrote during the ack")
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults).map(\.eventId), [b])
  }

  /// Two presses at once, one per process: both are queued.
  func testEnqueueNeverDropsAnEntryAnotherProcessQueuedMeanwhile() throws {
    let now = Date(timeIntervalSince1970: 1_784_116_800)
    let app = try XCTUnwrap(RacingDefaults(suiteName: suiteName))
    var b = ""
    app.race = { b = self.widgetEnqueue("t9", at: now.addingTimeInterval(1)) }

    let a = AWAlarmActionQueue.enqueue(
      action: "acknowledge", taskIds: ["t1"], origin: "alarmkit", pressedAt: now, in: app,
      notify: false)

    XCTAssertFalse(b.isEmpty, "the widget wrote during the enqueue")
    XCTAssertEqual(AWAlarmActionQueue.pending(in: defaults).map(\.eventId), [a, b])
  }

  func testV1QueueEntriesAreConvertedOnRead() {
    defaults.set(
      [
        ["actionId": "acknowledge", "taskId": "t1", "reminderId": "r1"],
        ["actionId": "complete", "taskId": "t2", "reminderId": ""],
      ],
      forKey: AWAlarmActionQueue.defaultsKey)
    let readAt = Date(timeIntervalSince1970: 1_784_116_900)

    let first = AWAlarmActionQueue.pending(in: defaults, now: readAt)
    XCTAssertEqual(first.count, 2)
    XCTAssertEqual(first.map(\.action), ["acknowledge", "complete"])
    XCTAssertEqual(first.map(\.taskIds), [["t1"], ["t2"]])
    XCTAssertEqual(first.map(\.origin), ["alarmkit", "widget"])
    XCTAssertEqual(first.map(\.pressedAtMs), [1_784_116_900_000, 1_784_116_900_000])
    XCTAssertTrue(first.allSatisfy { !$0.eventId.isEmpty && $0.untilMs == nil })
    XCTAssertNotEqual(first[0].eventId, first[1].eventId)

    // Rewritten in place on that first read, so the eventId is stable: a
    // later read (any time later) names the same events.
    let later = AWAlarmActionQueue.pending(in: defaults, now: readAt.addingTimeInterval(3600))
    XCTAssertEqual(later.map(\.eventId), first.map(\.eventId))
    XCTAssertEqual(later.map(\.pressedAtMs), first.map(\.pressedAtMs))
    // Moved to one key per event, as v2; the old list is gone.
    XCTAssertNil(defaults.object(forKey: AWAlarmActionQueue.defaultsKey))
    for event in first {
      let stored = defaults.dictionary(
        forKey: AWAlarmActionQueue.entryKey(eventId: event.eventId))
      XCTAssertEqual(stored?["eventId"] as? String, event.eventId)
      XCTAssertNil(stored?["actionId"])
    }

    // A mixed queue keeps its order: v1 first (queued earlier), then a v2 press.
    let v2 = AWAlarmActionQueue.enqueue(
      action: "complete", taskIds: ["t9"], origin: "widget",
      pressedAt: readAt.addingTimeInterval(10), in: defaults, notify: false)
    XCTAssertEqual(
      AWAlarmActionQueue.pending(in: defaults).map(\.eventId), first.map(\.eventId) + [v2])
  }

  func testV1SnoozeKeepsPreset() {
    defaults.set(
      [["actionId": "snooze:30_min", "taskId": "t1", "reminderId": "r1"]],
      forKey: AWAlarmActionQueue.defaultsKey)
    let events = AWAlarmActionQueue.pending(
      in: defaults, now: Date(timeIntervalSince1970: 1_784_116_800))
    XCTAssertEqual(events.count, 1)
    let snooze = events[0]
    XCTAssertEqual(snooze.action, "snooze")
    XCTAssertEqual(snooze.preset, "30_min")
    XCTAssertNil(snooze.untilMs)  // Dart computes the target from pressedAtMs
    XCTAssertEqual(snooze.taskIds, ["t1"])
    XCTAssertEqual(snooze.origin, "alarmkit")
    XCTAssertEqual(snooze.pressedAtMs, 1_784_116_800_000)
    XCTAssertEqual(snooze.dictionary["preset"] as? String, "30_min")
    XCTAssertNil(snooze.dictionary["untilMs"])
  }

  // MARK: - Failures

  func testFailuresAreARingOfFiftyAndPullEmptiesIt() {
    for i in 0..<55 {
      AWAlarmFailures.record(
        eventId: "E-\(i)", stage: "schedule", code: "other", message: "m\(i)",
        at: Date(timeIntervalSince1970: Double(i)), in: defaults)
    }
    let pulled = AWAlarmFailures.pull(in: defaults)
    XCTAssertEqual(pulled.count, 50)
    XCTAssertEqual(pulled.first?["eventId"] as? String, "E-5")
    XCTAssertEqual((pulled.last?["atMs"] as? NSNumber)?.int64Value, 54_000)
    XCTAssertEqual(AWAlarmFailures.pull(in: defaults).count, 0)
  }

  func testLegacyIntentFallsBackToItsSingleTaskId() {
    XCTAssertEqual(AWAlarmIntentArgs.taskIds(["a", "b"], legacy: "x"), ["a", "b"])
    XCTAssertEqual(AWAlarmIntentArgs.taskIds(nil, legacy: "x"), ["x"])
    XCTAssertEqual(AWAlarmIntentArgs.taskIds([], legacy: "x"), ["x"])
    XCTAssertEqual(AWAlarmIntentArgs.taskIds(nil, legacy: nil), [])
  }

  func testFallbackIdentifier() {
    // The plugin cancels `String(NotificationId)`, so the request identifier
    // is that decimal: fnv1a over "aw.fallback.<eventId>".
    XCTAssertEqual(AWAlarmFallback.notificationId(eventId: "E-1"), 1_019_953_648)
    XCTAssertEqual(AWAlarmFallback.identifier(eventId: "E-1"), "1019953648")
  }
}
