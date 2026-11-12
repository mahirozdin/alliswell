import Foundation

/// AlarmKit occurrence identity (NOTIFICATIONS.md §2b.3 "Identity", #49).
///
/// Byte for byte the same numbers as Dart's `alarmkit_identity.dart`, so a
/// native snooze (app or widget process, no Flutter engine) names exactly the
/// alarm Dart would plan. `test/fixtures/alarmkit_identity_cases.json` is
/// written by the Dart test and compared here by `AlarmIdentityTests`.
///
/// Foundation only — no AlarmKit, no UIKit — so the widget extension compiles
/// the same file. The id <-> UUID mapping stays in `AlarmKitBridge.uuid(for:)`.
enum AWAlarmIdentity {

  /// FNV-1a 32-bit over the **UTF-16 code units** of [s] (Dart's
  /// `String.codeUnits`), masked positive — Dart `notificationIdFor`.
  static func fnv1a(_ s: String) -> Int {
    var hash: UInt32 = 0x811c_9dc5
    for unit in s.utf16 {
      hash ^= UInt32(unit)
      hash = hash &* 0x0100_0193
    }
    return Int(hash & 0x7fff_ffff)
  }

  /// Dart's `ms - ms % 1000`: floors toward negative infinity.
  static func floorToSecond(ms: Int64) -> Int64 {
    let r = ms % 1000
    return ms - (r < 0 ? r + 1000 : r)
  }

  /// [date] as UTC epoch ms floored to the whole second.
  ///
  /// `Date` is a `Double` of seconds since 2001; going to 1970 and multiplying
  /// by 1000 can land a hair under a whole second (…800.9999999 for …801) and a
  /// naive floor would drop a second, changing the id. The value is first
  /// rounded to the nearest microsecond (Dart's own resolution; a `Double` at
  /// epoch scale still resolves well below that), then floored in integers.
  static func fireAtMs(_ date: Date) -> Int64 {
    let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    let r = micros % 1_000_000
    let wholeSecondMicros = micros - (r < 0 ? r + 1_000_000 : r)
    return wholeSecondMicros / 1000
  }

  /// The members as they enter the id seed: de-duplicated and sorted by UTF-16
  /// code unit (Dart `String.compareTo`). Both steps key on the code units:
  /// Swift's `==`, `Set` and `<` use canonical equivalence, Dart does not.
  static func members<S: Sequence>(_ members: S) -> [String] where S.Element == String {
    var seen = Set<[UInt16]>()
    var unique: [String] = []
    for m in members where seen.insert(Array(m.utf16)).inserted { unique.append(m) }
    return unique.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
  }

  /// `akv2|<sorted unique members joined by ",">|<fireAtMs>`.
  static func occurrenceSeed(members: [String], fireAtMs: Int64) -> String {
    "akv2|" + Self.members(members).joined(separator: ",") + "|" + String(fireAtMs)
  }

  /// The occurrence id: which tasks ring, and when. Members are task ids,
  /// never reminder ids; [fireAtMs] is expected floored (see [fireAtMs(_:)]).
  static func occurrenceId(members: [String], fireAtMs: Int64) -> Int {
    fnv1a(occurrenceSeed(members: members, fireAtMs: fireAtMs))
  }

  /// `fp1|title|body|sound|stop|snooze|preset`; a nil sound hashes like `""`.
  static func fingerprintSeed(
    title: String, body: String, soundName: String?, stopLabel: String,
    snoozeLabel: String, snoozePreset: String
  ) -> String {
    ["fp1", title, body, soundName ?? "", stopLabel, snoozeLabel, snoozePreset]
      .joined(separator: "|")
  }

  /// The presentation fingerprint: everything the alert shows or does that is
  /// not the occurrence itself.
  static func fingerprint(
    title: String, body: String, soundName: String?, stopLabel: String,
    snoozeLabel: String, snoozePreset: String
  ) -> Int {
    fnv1a(
      fingerprintSeed(
        title: title, body: body, soundName: soundName, stopLabel: stopLabel,
        snoozeLabel: snoozeLabel, snoozePreset: snoozePreset))
  }
}
