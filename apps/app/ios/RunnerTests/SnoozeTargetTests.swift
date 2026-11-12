import Foundation
import XCTest

@testable import Runner

/// Snooze target parity (NOTIFICATIONS.md §2b.3 "Native snooze", step 2).
///
/// `test/fixtures/snooze_preset_cases.json` is written by the Dart test from
/// `snoozeUntilWallClock` and only read here. The cases are zone-free wall
/// clock times that cross no DST change, so each must hold in every zone.
final class SnoozeTargetTests: XCTestCase {

  private static var fixtureURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // apps/app
      .appendingPathComponent("test/fixtures/snooze_preset_cases.json")
  }

  private static let zones = [
    "UTC", "Europe/Istanbul", "America/New_York", "Asia/Kolkata", "Pacific/Auckland",
  ]

  private func formatter(_ zone: TimeZone) -> DateFormatter {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = zone
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
  }

  func testBaseTargetMatchesDartFixture() throws {
    let data = try Data(contentsOf: Self.fixtureURL)
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
    XCTAssertFalse(cases.isEmpty, "fixture has no cases")
    let presets = Set(cases.compactMap { $0["preset"] as? String })
    XCTAssertEqual(presets, ["5_min", "30_min", "1_hour", "tomorrow_morning"])

    for zoneId in Self.zones {
      let zone = try XCTUnwrap(TimeZone(identifier: zoneId))
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      let wall = formatter(zone)
      for c in cases {
        let name = try XCTUnwrap(c["name"] as? String)
        let preset = try XCTUnwrap(c["preset"] as? String)
        let nowWall = try XCTUnwrap(c["nowWall"] as? String)
        let untilWall = try XCTUnwrap(c["untilWall"] as? String)
        let now = try XCTUnwrap(wall.date(from: nowWall), "\(name): bad nowWall")
        let until = AWSnoozeTarget.base(pressedAt: now, preset: preset, calendar: calendar)
        let got = until.map { wall.string(from: $0) }
        XCTAssertEqual(got, untilWall, "\(name) in \(zoneId)")
        // Already whole seconds: flooring changes nothing.
        if let until {
          XCTAssertEqual(AWAlarmIdentity.fireAtMs(until) % 1000, 0, "\(name) in \(zoneId)")
        }
      }
    }
  }

  func testUnknownPresetHasNoTarget() {
    XCTAssertNil(
      AWSnoozeTarget.base(pressedAt: Date(), preset: "2_days", calendar: Calendar.current))
  }

  // MARK: - The +1 minute rule (native only, §2b.3 step 3)

  /// 2026-07-15 12:00:30.250 UTC; `5_min` lands on 12:05:30.000.
  private let pressedAt = Date(timeIntervalSince1970: 1_784_116_830.25)
  private let baseMs: Int64 = 1_784_117_130_000
  private let snoozedId = 4_242

  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  /// A ledger record of another alarm at [ms] (any second of its minute).
  private func other(_ id: Int, at ms: Int64, origin: String = "dart") -> AWAlarmLedgerRecord {
    AWAlarmLedgerRecord(id: id, fp: 1, members: ["x\(id)"], fireAtMs: ms, origin: origin)
  }

  private func compute(_ ledger: [AWAlarmLedgerRecord], preset: String = "5_min") -> Int64? {
    AWSnoozeTarget.compute(
      pressedAt: pressedAt, preset: preset, ledger: ledger, snoozedAlarmId: snoozedId,
      calendar: utc)
  }

  func testFreeMinuteIsKept() {
    // Records in the minutes around the target, never in it.
    let ledger = [
      other(1, at: baseMs - 60_000), other(2, at: baseMs + 60_000 - 30_000),
      other(3, at: baseMs + 2 * 60_000),
    ]
    XCTAssertEqual(compute(ledger), baseMs)
    XCTAssertEqual(compute([]), baseMs)
  }

  func testTakenMinuteShiftsOneMinute() {
    // 12:05:00 is in the target's minute (12:05:30): the target moves to
    // 12:06:30, seconds kept.
    XCTAssertEqual(compute([other(7, at: baseMs - 30_000)]), baseMs + 60_000)
    // A native record counts like a Dart one; two taken minutes move it two.
    XCTAssertEqual(
      compute([
        other(7, at: baseMs + 29_000, origin: "native"), other(8, at: baseMs + 60_000 - 30_000),
      ]),
      baseMs + 2 * 60_000)
  }

  func testThirtyTakenMinutesStopAtTheLastTry() {
    // 40 taken minutes in a row: 30 shifts, then the last target stays
    // (still taken; grouping makes it one sound).
    let ledger = (0..<40).map { other(100 + $0, at: baseMs - 30_000 + Int64($0) * 60_000) }
    XCTAssertEqual(compute(ledger), baseMs + 30 * 60_000)
    // Exactly 30 taken minutes: the 30th shift reaches a free one.
    XCTAssertEqual(compute(Array(ledger.prefix(30))), baseMs + 30 * 60_000)
    // 29 taken: one shift short of the cap.
    XCTAssertEqual(compute(Array(ledger.prefix(29))), baseMs + 29 * 60_000)
  }

  func testTheSnoozedAlarmOwnRecordDoesNotCount() {
    let own = AWAlarmLedgerRecord(
      id: snoozedId, fp: 1, members: ["t1", "t2"], fireAtMs: baseMs - 30_000, origin: "native",
      eventId: "E-0")
    XCTAssertEqual(compute([own]), baseMs)
    // Another alarm in the same minute still counts.
    XCTAssertEqual(compute([own, other(9, at: baseMs)]), baseMs + 60_000)
    // No snoozed id (a legacy intent): every record counts.
    XCTAssertEqual(
      AWSnoozeTarget.compute(
        pressedAt: pressedAt, preset: "5_min", ledger: [own], snoozedAlarmId: nil,
        calendar: utc),
      baseMs + 60_000)
  }

  func testComputeFloorsTheTargetAndRejectsAnUnknownPreset() {
    XCTAssertEqual(compute([], preset: "30_min"), 1_784_118_630_000)
    XCTAssertEqual(compute([], preset: "tomorrow_morning"), 1_784_192_400_000)
    XCTAssertNil(compute([], preset: "2_days"))
  }

  func testMinutePresetKeepsSecondsAndIsFlooredByTheCaller() {
    let now = Date(timeIntervalSince1970: 1_784_116_830.999)
    let until = AWSnoozeTarget.base(pressedAt: now, preset: "5_min", calendar: .current)
    XCTAssertEqual(until.map(AWAlarmIdentity.fireAtMs), 1_784_117_130_000)
  }
}
