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

  func testMinutePresetKeepsSecondsAndIsFlooredByTheCaller() {
    let now = Date(timeIntervalSince1970: 1_784_116_830.999)
    let until = AWSnoozeTarget.base(pressedAt: now, preset: "5_min", calendar: .current)
    XCTAssertEqual(until.map(AWAlarmIdentity.fireAtMs), 1_784_117_130_000)
  }
}
