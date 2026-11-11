import Foundation
import XCTest

@testable import Runner

/// AlarmKit identity parity (NOTIFICATIONS.md §2b.3 "Identity", #49).
///
/// The fixture is written by the Dart test from `alarmkit_identity.dart` and
/// only read here: every case must give the same seeds, id and fp in Swift, so
/// a native snooze names exactly the alarm Dart would have planned.
final class AlarmIdentityTests: XCTestCase {

  private struct Case {
    let name: String
    let members: [String]
    let rawFireAtMs: Int64
    let fireAtMs: Int64
    let title: String
    let body: String
    let soundName: String?
    let stopLabel: String
    let snoozeLabel: String
    let snoozePreset: String
    let sortedMembers: [String]
    let idSeed: String
    let id: Int
    let fpSeed: String
    let fp: Int
  }

  /// `apps/app/test/fixtures/alarmkit_identity_cases.json`, resolved from this
  /// source file so it works from Xcode and from `xcodebuild test` alike.
  private static var fixtureURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // apps/app
      .appendingPathComponent("test/fixtures/alarmkit_identity_cases.json")
  }

  private func loadCases(file: StaticString = #filePath, line: UInt = #line) throws -> [Case] {
    let data = try Data(contentsOf: Self.fixtureURL)
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
    let raw = try XCTUnwrap(root["cases"] as? [[String: Any]], file: file, line: line)
    XCTAssertFalse(raw.isEmpty, "fixture has no cases", file: file, line: line)
    return try raw.map { c in
      func str(_ k: String) throws -> String {
        try XCTUnwrap(c[k] as? String, "\(k) missing", file: file, line: line)
      }
      func int(_ k: String) throws -> Int64 {
        try XCTUnwrap((c[k] as? NSNumber)?.int64Value, "\(k) missing", file: file, line: line)
      }
      return Case(
        name: try str("name"),
        members: try XCTUnwrap(c["members"] as? [String], file: file, line: line),
        rawFireAtMs: try int("rawFireAtMs"),
        fireAtMs: try int("fireAtMs"),
        title: try str("title"),
        body: try str("body"),
        soundName: c["soundName"] as? String,  // NSNull => nil
        stopLabel: try str("stopLabel"),
        snoozeLabel: try str("snoozeLabel"),
        snoozePreset: try str("snoozePreset"),
        sortedMembers: try XCTUnwrap(c["sortedMembers"] as? [String], file: file, line: line),
        idSeed: try str("idSeed"),
        id: Int(try int("id")),
        fpSeed: try str("fpSeed"),
        fp: Int(try int("fp"))
      )
    }
  }

  func testOccurrenceIdMatchesDartFixture() throws {
    for c in try loadCases() {
      let fireAt = AWAlarmIdentity.floorToSecond(ms: c.rawFireAtMs)
      XCTAssertEqual(fireAt, c.fireAtMs, "fireAtMs: \(c.name)")
      XCTAssertEqual(AWAlarmIdentity.members(c.members), c.sortedMembers, "members: \(c.name)")
      XCTAssertEqual(
        AWAlarmIdentity.occurrenceSeed(members: c.members, fireAtMs: fireAt), c.idSeed,
        "idSeed: \(c.name)")
      XCTAssertEqual(
        AWAlarmIdentity.occurrenceId(members: c.members, fireAtMs: fireAt), c.id, "id: \(c.name)")
      XCTAssertEqual(AWAlarmIdentity.fnv1a(c.idSeed), c.id, "fnv1a(idSeed): \(c.name)")
    }
  }

  func testFingerprintMatchesDartFixture() throws {
    for c in try loadCases() {
      XCTAssertEqual(
        AWAlarmIdentity.fingerprintSeed(
          title: c.title, body: c.body, soundName: c.soundName, stopLabel: c.stopLabel,
          snoozeLabel: c.snoozeLabel, snoozePreset: c.snoozePreset),
        c.fpSeed, "fpSeed: \(c.name)")
      XCTAssertEqual(
        AWAlarmIdentity.fingerprint(
          title: c.title, body: c.body, soundName: c.soundName, stopLabel: c.stopLabel,
          snoozeLabel: c.snoozeLabel, snoozePreset: c.snoozePreset),
        c.fp, "fp: \(c.name)")
      XCTAssertEqual(AWAlarmIdentity.fnv1a(c.fpSeed), c.fp, "fnv1a(fpSeed): \(c.name)")
    }
  }

  func testFireAtFloorsToTheSecond() throws {
    // Every fixture instant, reached through a Date the way the bridge gets one.
    for c in try loadCases() {
      let date = Date(timeIntervalSince1970: Double(c.rawFireAtMs) / 1000)
      XCTAssertEqual(AWAlarmIdentity.fireAtMs(date), c.fireAtMs, "fireAtMs(Date): \(c.name)")
    }
    // Whole seconds reached through the reference-date epoch, where the
    // 1970 conversion adds floating error, must not drop a second.
    for s: Int64 in [0, 1, 978_307_200, 1_767_225_600, 1_784_116_801, 4_102_444_799] {
      let viaReference = Date(timeIntervalSinceReferenceDate: Double(s) - 978_307_200)
      XCTAssertEqual(AWAlarmIdentity.fireAtMs(viaReference), s * 1000, "whole second \(s)")
      let justBefore = Date(timeIntervalSince1970: Double(s) - 0.001)
      XCTAssertEqual(AWAlarmIdentity.fireAtMs(justBefore), (s - 1) * 1000, "just before \(s)")
    }
    // Dart's `ms - ms % 1000` floors toward negative infinity too.
    XCTAssertEqual(AWAlarmIdentity.floorToSecond(ms: -1500), -2000)
    XCTAssertEqual(AWAlarmIdentity.floorToSecond(ms: -1000), -1000)
    XCTAssertEqual(AWAlarmIdentity.fireAtMs(Date(timeIntervalSince1970: -1.5)), -2000)
  }

  func testMembersKeyOnCodeUnitsNotCanonicalEquivalence() {
    // Swift's String == treats these as equal; Dart's toSet() and the seed do not.
    let precomposed = "\u{E9}"
    let decomposed = "e\u{301}"
    let sorted = AWAlarmIdentity.members([precomposed, decomposed, precomposed])
    XCTAssertEqual(sorted.map { Array($0.utf16) }, [[0x65, 0x301], [0xE9]])
    XCTAssertEqual(
      Array(AWAlarmIdentity.occurrenceSeed(members: [precomposed, decomposed], fireAtMs: 0).utf16),
      Array("akv2|e\u{301},\u{E9}|0".utf16))
  }

  func testFnv1aKnownValuesAndPositiveRange() {
    // FNV-1a 32 offset basis masked positive: the empty string.
    XCTAssertEqual(AWAlarmIdentity.fnv1a(""), 0x811c_9dc5 & 0x7fff_ffff)
    // An astral code point hashes as its two UTF-16 surrogates, not one scalar.
    let emoji = "\u{1F600}"
    var h: UInt32 = 0x811c_9dc5
    for unit: UInt16 in [0xD83D, 0xDE00] {
      h ^= UInt32(unit)
      h = h &* 0x0100_0193
    }
    XCTAssertEqual(AWAlarmIdentity.fnv1a(emoji), Int(h & 0x7fff_ffff))
    for s in ["a", "Görev", "akv2|T1|0", "🙂🙂"] {
      let v = AWAlarmIdentity.fnv1a(s)
      XCTAssertGreaterThanOrEqual(v, 0)
      XCTAssertLessThanOrEqual(v, 0x7fff_ffff)
    }
  }
}
