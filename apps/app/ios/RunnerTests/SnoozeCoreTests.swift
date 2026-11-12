import Foundation
import XCTest

@testable import Runner

/// The native "Ertele" (NOTIFICATIONS.md §2b.3 "Native snooze", #49).
///
/// Every OS stage is injected through a fake [AWAlarmOps], one failure at a
/// time, and every store is a throw-away `UserDefaults` suite: the ringing
/// alarm must be silenced in every combination, and a failed schedule must
/// still leave one fallback reminder at the snooze instant.
final class SnoozeCoreTests: XCTestCase {

  private final class FakeOps: AWAlarmOps {
    var scheduleError: Error?
    var stopError: Error?
    var cancelError: Error?
    var alertingError: Error?
    var fallbackError: Error?
    var alerting: [Int] = []

    var calls: [String] = []
    var scheduled: [AWAlarmSpec] = []
    var fallbacks: [AWFallbackRequest] = []

    func schedule(_ spec: AWAlarmSpec) async throws {
      calls.append("schedule:\(spec.id)")
      if let scheduleError { throw scheduleError }
      scheduled.append(spec)
    }

    func stop(id: Int) throws {
      calls.append("stop:\(id)")
      if let stopError { throw stopError }
    }

    func cancel(id: Int) throws {
      calls.append("cancel:\(id)")
      if let cancelError { throw cancelError }
    }

    func alertingIds() throws -> [Int] {
      calls.append("alerting")
      if let alertingError { throw alertingError }
      return alerting
    }

    func addFallbackNotification(_ request: AWFallbackRequest) async throws {
      calls.append("fallback:\(request.identifier)")
      if let fallbackError { throw fallbackError }
      fallbacks.append(request)
    }
  }

  private struct Boom: Error, CustomStringConvertible {
    let description: String
  }

  private var suiteName = ""
  private var defaults: UserDefaults!
  private var ledger: AWAlarmLedger!

  /// 2026-07-15 12:00:30.250 UTC — the press; ms on purpose (floored target).
  private let now = Date(timeIntervalSince1970: 1_784_116_830.25)
  private let ringingId = 4_242
  private let ringingFireAtMs: Int64 = 1_784_116_800_000

  override func setUpWithError() throws {
    suiteName = "aw.tests.snooze.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    ledger = AWAlarmLedger(defaults: defaults)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    ledger = nil
  }

  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  private func request(
    taskIds: [String]? = ["t2", "t1", "t2"], legacyTaskId: String? = nil,
    alarmId: Int?, preset: String = "5_min"
  ) -> AWSnoozeRequest {
    AWSnoozeRequest(
      taskIds: taskIds, legacyTaskId: legacyTaskId, alarmId: alarmId,
      fireAtMs: alarmId == nil ? nil : ringingFireAtMs, title: "Pay rent", body: "Today",
      soundName: "", stopLabel: "Onayla", snoozeLabel: "Ertele", preset: preset,
      reminderId: "r1")
  }

  private func run(
    _ ops: FakeOps, _ request: AWSnoozeRequest, eventId: String = "E-1"
  ) async -> AWSnoozeResult {
    await AWSnoozeCore.run(
      request, ops: ops, ledger: ledger, queue: defaults, failures: defaults, now: now,
      calendar: utc, eventId: eventId, notify: false)
  }

  private var failures: [[String: Any]] {
    defaults.array(forKey: AWAlarmFailures.key) as? [[String: Any]] ?? []
  }

  private var queued: [AWAlarmActionEvent] { AWAlarmActionQueue.pending(in: defaults, now: now) }

  /// 12:00:30.250 + 5 min, floored: 12:05:30.000.
  private let expectedUntilMs: Int64 = 1_784_117_130_000

  // MARK: - Tests

  func testScheduleOkThenStopSilencesAndEnqueues() async {
    let ops = FakeOps()
    ledger.write(
      AWAlarmLedgerRecord(
        id: ringingId, fp: 1, members: ["t1", "t2"], fireAtMs: ringingFireAtMs, origin: "dart"))

    let result = await run(ops, request(alarmId: ringingId))

    let newId = AWAlarmIdentity.occurrenceId(members: ["t1", "t2"], fireAtMs: expectedUntilMs)
    XCTAssertEqual(ops.calls, ["schedule:\(newId)", "stop:\(ringingId)"])
    XCTAssertEqual(result.untilMs, expectedUntilMs)
    XCTAssertEqual(result.scheduleOutcome, "ok")
    XCTAssertEqual(result.stopOutcome, "stopped")
    XCTAssertEqual(result.newId, newId)
    XCTAssertFalse(result.fallbackAdded)

    // The new alarm is the old one, moved: same presentation and members.
    let spec = ops.scheduled.first
    XCTAssertEqual(spec?.fireAtMs, expectedUntilMs)
    XCTAssertEqual(spec?.members, ["t1", "t2"])
    XCTAssertEqual(spec?.title, "Pay rent")
    XCTAssertNil(spec?.soundName)
    XCTAssertEqual(spec?.snoozePreset, "5_min")
    XCTAssertEqual(spec?.snoozeLabel, "Ertele")

    // The ledger forgets what rang and knows what was scheduled natively.
    XCTAssertNil(ledger.record(id: ringingId))
    let fp = AWAlarmIdentity.fingerprint(
      title: "Pay rent", body: "Today", soundName: nil, stopLabel: "Onayla",
      snoozeLabel: "Ertele", snoozePreset: "5_min")
    XCTAssertEqual(
      ledger.record(id: newId),
      AWAlarmLedgerRecord(
        id: newId, fp: fp, members: ["t1", "t2"], fireAtMs: expectedUntilMs, origin: "native",
        eventId: "E-1"))

    XCTAssertEqual(
      queued,
      [
        AWAlarmActionEvent(
          eventId: "E-1", action: "snooze", taskIds: ["t2", "t1"], untilMs: expectedUntilMs,
          occurrenceFireAtMs: ringingFireAtMs, pressedAtMs: AWAlarmActionQueue.epochMs(now),
          origin: "alarmkit", alarmId: ringingId, newId: newId, scheduleOutcome: "ok",
          stopOutcome: "stopped")
      ])
    XCTAssertTrue(failures.isEmpty)
  }

  func testMaximumLimitReachedStillStopsAndAddsFallbackNotification() async {
    let ops = FakeOps()
    ops.scheduleError = AWAlarmOpsError.maximumLimitReached

    let result = await run(ops, request(alarmId: ringingId))

    XCTAssertTrue(ops.calls.contains("stop:\(ringingId)"))
    XCTAssertEqual(result.scheduleOutcome, "limitReached")
    XCTAssertEqual(result.stopOutcome, "stopped")
    XCTAssertNil(result.newId)
    XCTAssertTrue(result.fallbackAdded)
    XCTAssertEqual(
      ops.fallbacks,
      [
        AWFallbackRequest(
          identifier: "aw.fallback.E-1", fireAtMs: expectedUntilMs, title: "Pay rent",
          body: "Today", soundName: nil, taskIds: ["t2", "t1"], eventId: "E-1")
      ])
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures.first?["stage"] as? String, "schedule")
    XCTAssertEqual(failures.first?["code"] as? String, "maximumLimitReached")
    XCTAssertEqual(failures.first?["eventId"] as? String, "E-1")
    // No native record: nothing was scheduled.
    XCTAssertTrue(ledger.records().isEmpty)
    XCTAssertEqual(queued.first?.scheduleOutcome, "limitReached")
    XCTAssertNil(queued.first?.newId)
    XCTAssertEqual(queued.first?.untilMs, expectedUntilMs)
  }

  func testOtherScheduleErrorStillStopsAndAddsFallbackNotification() async {
    let ops = FakeOps()
    ops.scheduleError = Boom(description: "daemon gone")

    let result = await run(ops, request(alarmId: ringingId))

    XCTAssertTrue(ops.calls.contains("stop:\(ringingId)"))
    XCTAssertEqual(result.scheduleOutcome, "failed")
    XCTAssertEqual(result.stopOutcome, "stopped")
    XCTAssertEqual(ops.fallbacks.map(\.identifier), ["aw.fallback.E-1"])
    XCTAssertEqual(ops.fallbacks.first?.fireAtMs, expectedUntilMs)
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures.first?["code"] as? String, "other")
    XCTAssertEqual(failures.first?["message"] as? String, "daemon gone")
    XCTAssertEqual(queued.first?.scheduleOutcome, "failed")

    // The fallback carries what the urgent notification handler reads.
    let payload =
      try? JSONSerialization.jsonObject(
        with: Data((ops.fallbacks.first?.payloadJSON ?? "").utf8)) as? [String: Any]
    XCTAssertEqual(payload?["taskId"] as? String, "t2")
    XCTAssertEqual(payload?["taskIds"] as? [String], ["t2", "t1"])
    XCTAssertEqual(payload?["eventId"] as? String, "E-1")
  }

  func testStopFailureFallsBackToCancelAndIsRecorded() async {
    let ops = FakeOps()
    ops.stopError = Boom(description: "not alerting")
    ledger.write(
      AWAlarmLedgerRecord(
        id: ringingId, fp: 1, members: ["t1"], fireAtMs: ringingFireAtMs, origin: "dart"))

    let result = await run(ops, request(alarmId: ringingId))

    XCTAssertEqual(Array(ops.calls.suffix(2)), ["stop:\(ringingId)", "cancel:\(ringingId)"])
    XCTAssertEqual(result.scheduleOutcome, "ok")
    XCTAssertEqual(result.stopOutcome, "cancelled")
    XCTAssertNil(ledger.record(id: ringingId))
    XCTAssertEqual(failures.map { $0["stage"] as? String }, ["stop"])
    XCTAssertEqual(failures.first?["message"] as? String, "not alerting")
    XCTAssertEqual(queued.first?.stopOutcome, "cancelled")
    XCTAssertTrue(ops.fallbacks.isEmpty)
  }

  func testStopAndCancelBothFailIsRecordedAndNeverThrows() async {
    let ops = FakeOps()
    ops.scheduleError = Boom(description: "schedule")
    ops.stopError = Boom(description: "stop")
    ops.cancelError = Boom(description: "cancel")
    ops.fallbackError = Boom(description: "denied")

    // `run` is not `throws`: reaching the next line at all is the proof.
    let result = await run(ops, request(alarmId: ringingId))

    XCTAssertEqual(result.scheduleOutcome, "failed")
    XCTAssertEqual(result.stopOutcome, "failed")
    XCTAssertFalse(result.fallbackAdded)
    XCTAssertEqual(
      failures.map { $0["stage"] as? String }, ["schedule", "stop", "cancel", "fallback"])
    // The press still reaches Dart, which re-plans from `untilMs`.
    XCTAssertEqual(queued.count, 1)
    XCTAssertEqual(queued.first?.stopOutcome, "failed")
    XCTAssertEqual(queued.first?.untilMs, expectedUntilMs)
  }

  func testFailureRingBufferKeepsLast50() async {
    let ops = FakeOps()
    ops.scheduleError = Boom(description: "schedule")
    ops.stopError = Boom(description: "stop")
    ops.cancelError = Boom(description: "cancel")
    ops.fallbackError = Boom(description: "fallback")

    // 13 presses x 4 failing stages = 52 rows; the ring keeps the last 50.
    for i in 1...13 {
      _ = await run(ops, request(alarmId: ringingId), eventId: String(format: "E-%02d", i))
    }

    let rows = failures
    XCTAssertEqual(rows.count, AWAlarmFailures.capacity)
    XCTAssertEqual(rows.first?["eventId"] as? String, "E-01")
    XCTAssertEqual(rows.first?["stage"] as? String, "cancel")
    XCTAssertEqual(rows.last?["eventId"] as? String, "E-13")
    XCTAssertEqual(rows.last?["stage"] as? String, "fallback")
  }

  func testLegacyIntentWithoutAlarmIdStopsAlertingAlarms() async {
    let ops = FakeOps()
    ops.alerting = [11, 22]

    // An alarm scheduled by v1.19.2: only `taskId`, `reminderId`, `preset`.
    let legacy = AWSnoozeRequest(
      taskIds: nil, legacyTaskId: "t-legacy", alarmId: nil, fireAtMs: nil, title: nil,
      body: nil, soundName: nil, stopLabel: nil, snoozeLabel: nil, preset: "30_min",
      reminderId: "r-legacy")
    let result = await run(ops, legacy)

    XCTAssertFalse(ops.calls.contains { $0.hasPrefix("schedule:") })
    XCTAssertEqual(
      ops.calls, ["alerting", "stop:11", "stop:22", "fallback:aw.fallback.E-1"])
    XCTAssertEqual(result.scheduleOutcome, "failed")
    XCTAssertEqual(result.stopOutcome, "stopped")
    XCTAssertTrue(result.fallbackAdded)

    let until = AWAlarmIdentity.fireAtMs(now.addingTimeInterval(30 * 60))
    XCTAssertEqual(ops.fallbacks.first?.fireAtMs, until)
    XCTAssertEqual(ops.fallbacks.first?.taskIds, ["t-legacy"])
    XCTAssertEqual(ops.fallbacks.first?.title, AWSnoozeCore.legacyTitle)
    XCTAssertEqual(failures.count, 1)
    XCTAssertEqual(failures.first?["message"] as? String, AWSnoozeCore.legacyMessage)
    XCTAssertEqual(queued.first?.taskIds, ["t-legacy"])
    XCTAssertEqual(queued.first?.untilMs, until)
    XCTAssertNil(queued.first?.alarmId)
  }

  func testStopIntentEnqueuesAcknowledgeAndForgetsTheLedgerRecord() {
    ledger.write(
      AWAlarmLedgerRecord(
        id: ringingId, fp: 1, members: ["t1"], fireAtMs: ringingFireAtMs, origin: "dart"))

    AWSnoozeCore.acknowledge(
      taskIds: ["t1", "t2"], alarmId: ringingId, fireAtMs: ringingFireAtMs, ledger: ledger,
      queue: defaults, now: now, eventId: "A-1", notify: false)

    XCTAssertNil(ledger.record(id: ringingId))
    XCTAssertEqual(
      queued,
      [
        AWAlarmActionEvent(
          eventId: "A-1", action: "acknowledge", taskIds: ["t1", "t2"],
          occurrenceFireAtMs: ringingFireAtMs, pressedAtMs: AWAlarmActionQueue.epochMs(now),
          origin: "alarmkit", alarmId: ringingId)
      ])
  }

  /// #47 D6 variant: three urgent alarms ring as one group alarm at 12:00 and
  /// another task's alarm is already at 12:05. The native Ertele (5 dk) is one
  /// press for the whole group: one new alarm for every member, one minute
  /// later than the taken 12:05, with the group title kept, and one event.
  func testGroupSnoozeEnqueuesOneEventWithEveryTaskId() async {
    let ops = FakeOps()
    let group = ["t3", "t1", "t2"]
    ledger.write(
      AWAlarmLedgerRecord(
        id: ringingId, fp: 1, members: ["t1", "t2", "t3"], fireAtMs: ringingFireAtMs,
        origin: "dart"))
    let otherId = 777
    let otherFireAtMs: Int64 = 1_784_117_100_000  // 12:05:00, another task
    ledger.write(
      AWAlarmLedgerRecord(
        id: otherId, fp: 2, members: ["other"], fireAtMs: otherFireAtMs, origin: "dart"))

    let groupRequest = AWSnoozeRequest(
      taskIds: group, alarmId: ringingId, fireAtMs: ringingFireAtMs, title: "3 acil alarm",
      body: "", soundName: "", stopLabel: "Onayla", snoozeLabel: "Ertele", preset: "5_min")
    let result = await run(ops, groupRequest, eventId: "G-1")

    // 12:05:30 is taken by the other task: the whole group moves to 12:06:30.
    let untilMs = expectedUntilMs + 60_000
    let newId = AWAlarmIdentity.occurrenceId(members: ["t1", "t2", "t3"], fireAtMs: untilMs)
    XCTAssertEqual(result.untilMs, untilMs)
    XCTAssertEqual(result.newId, newId)
    XCTAssertEqual(ops.calls, ["schedule:\(newId)", "stop:\(ringingId)"])
    XCTAssertEqual(ops.scheduled.count, 1)
    XCTAssertEqual(ops.scheduled.first?.members, ["t1", "t2", "t3"])
    XCTAssertEqual(ops.scheduled.first?.title, "3 acil alarm")
    XCTAssertEqual(ops.scheduled.first?.fireAtMs, untilMs)

    // One event for every member, in the order the alert carried them.
    XCTAssertEqual(
      queued,
      [
        AWAlarmActionEvent(
          eventId: "G-1", action: "snooze", taskIds: group, untilMs: untilMs,
          occurrenceFireAtMs: ringingFireAtMs, pressedAtMs: AWAlarmActionQueue.epochMs(now),
          origin: "alarmkit", alarmId: ringingId, newId: newId, scheduleOutcome: "ok",
          stopOutcome: "stopped")
      ])

    // The other task's alarm is untouched; the group's old record is gone.
    XCTAssertNotNil(ledger.record(id: otherId))
    XCTAssertNil(ledger.record(id: ringingId))
    XCTAssertEqual(ledger.record(id: newId)?.members, ["t1", "t2", "t3"])
    XCTAssertTrue(failures.isEmpty)
  }

  func testGroupStopEnqueuesOneAcknowledgeForTheWholeOccurrence() {
    AWSnoozeCore.acknowledge(
      taskIds: ["t3", "t1", "t2", "t1"], alarmId: ringingId, fireAtMs: ringingFireAtMs,
      ledger: ledger, queue: defaults, now: now, eventId: "GA-1", notify: false)

    XCTAssertEqual(queued.count, 1)
    XCTAssertEqual(queued.first?.taskIds, ["t3", "t1", "t2"])
    XCTAssertEqual(queued.first?.occurrenceFireAtMs, ringingFireAtMs)
    XCTAssertEqual(queued.first?.action, "acknowledge")
  }

  func testAlarmUUIDRoundTripsAndRejectsForeignIds() {
    for id in [0, 1, 4_242, Int(Int32.max)] {
      XCTAssertEqual(AWAlarmUUID.appId(from: AWAlarmUUID.uuid(for: id)), id)
    }
    XCTAssertNil(AWAlarmUUID.appId(from: UUID()))
  }
}
