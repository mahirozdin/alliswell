// AllisWell home-screen widget (Epic 12, OPH-131). Renders the JSON snapshot the
// Flutter app writes to the App Group via `home_widget` (see
// apps/app/lib/src/features/widgets/). The widget does NO i18n and NO DB access —
// it draws this pre-localized snapshot. @main lives in AllisWellWidgetBundle.swift.
//
// The snapshot schema mirrors WidgetSnapshot.toJson() in widget_snapshot.dart.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared identifiers (MUST match widget_host.dart)

private let kAppGroupId = "group.com.alliswell.alliswell"
private let kSnapshotKey = "aw_widget_snapshot"
private let kWidgetKind = "AllisWellWidget"

// MARK: - The header clock (OPH-253, DESIGN §31 C1–C5)
//
// MIRRORS widget_clock.dart. Both constants are pinned there by
// widget_clock_native_test.dart — change one, change both.

/// How old the entry being rendered may be before the clock is dropped (C3).
/// Its granularity is 60 s, so past 90 s at least one minute entry was never
/// drawn: the timeline is not being honoured and the number is no longer a time.
private let kAWClockStaleSeconds: TimeInterval = 90

/// How far ahead minute-granular entries are baked.
///
/// A widget cannot tick. `Text(date, style: .time)` prints the value from its
/// timeline entry and holds it; only `.relative`, `.offset` and `.timer` update
/// themselves, and none of those draws a wall clock — there is no live-clock API
/// on iOS, not even in 26. So a clock widget bakes an entry per minute, which is
/// cheap for a reason worth stating: **entries are free**. The ~40–70 reloads a
/// day are spent by ASKING for a new timeline, not by rendering one that already
/// exists. 240 minutes therefore costs 6 reloads a day, under 15% of the floor.
/// The real ceiling is not the budget but the ARCHIVE, and it bit us — see
/// `kAWArchiveBudgetBytes`.
private let kAWClockHorizonMinutes = 240

/// How many bytes of rendered timeline we allow ourselves.
///
/// MEASURED (iPhone 17 Pro Max simulator, iOS 26, OPH-253), and it is the whole
/// reason this file counts bytes instead of entries. A 241-entry systemLarge
/// timeline carrying a ten-row list archived to **16,665,560 bytes** and chronod
/// threw it away outright:
///
///     on local reload: failed with too large timeline archive 16665560
///     Error Domain=CHSErrorDomain Code=1050 "timelineReloadFailed"
///
/// The widget then never left its placeholder — two grey bars on the Home
/// Screen, no error anywhere the user could see. That is ~69 KB per entry, and
/// the number scales with the ROWS drawn, not with the entry count. So a fixed
/// horizon is a trap: the 240 entries that fit an empty widget blow the cap on a
/// full one, and the failure lands on exactly the users with the most tasks.
///
/// Half the observed cap, so a list that grows between two reloads still fits.
private let kAWArchiveBudgetBytes = 8_000_000

/// Archive cost of one entry, per visible task row, from the measurement above
/// (16,665,560 / 241 ≈ 69 KB for ten rows, plus the header and chrome).
private let kAWEntryBytesBase = 8_000
private let kAWEntryBytesPerRow = 6_100

// MARK: - Snapshot model (mirrors the Dart JSON)

struct AWSnapshot: Codable {
  let v: Int
  let generatedAt: String
  let locale: String
  let date: AWDate
  let strings: [String: String]?
  // OPH-187: optional ON PURPOSE. During an app update a v1 snapshot and a v2
  // widget coexist; a non-optional field would fail decoding and blank the
  // widget entirely rather than hide one badge.
  let openToday: Int?
  // OPH-253 (v3): the ICU pattern the header clock is drawn with. Optional for
  // the same reason `openToday` is — a v2 snapshot from an older app must not
  // fail decoding and blank the widget; it just gets the locale's own clock.
  let clockFormat: String?
  let buckets: [AWBucket]
  // OPH-336 (v4): the lock screen's row, the lists a widget can be set to, and
  // each project's own view. Optional like every field after v1 — a v3
  // snapshot from an older app decodes, and draws the whole list.
  let next: AWNextTask?
  let lists: [AWListInfo]?
  let views: [String: AWListView]?
  // OPH-337 (v4): "compact" draws tighter rows; absent means normal.
  let density: String?

  static let empty = AWSnapshot(
    v: 4, generatedAt: "", locale: "en",
    date: AWDate(weekday: "", day: "", month: ""), strings: nil, openToday: nil,
    clockFormat: nil, buckets: [], next: nil, lists: nil, views: nil, density: nil)

  var isCompact: Bool { density == "compact" }
}

struct AWDate: Codable {
  let weekday: String
  let day: String
  let month: String
}

struct AWBucket: Codable, Identifiable {
  let key: String
  let label: String
  let count: Int
  let items: [AWTaskRow]
  let more: Int?
  var id: String { key }
}

struct AWTaskRow: Codable, Identifiable {
  let id: String
  let title: String
  let done: Bool
  let priority: String
  let time: String?
  let projectColor: String?
}

/// The lock screen's one row (OPH-336) — `WidgetNextTask` in Dart.
struct AWNextTask: Codable {
  let id: String
  let title: String
  let bucket: String
  let label: String
  let time: String?
}

/// One entry of the list picker (OPH-336) — `WidgetListChoice` in Dart.
struct AWListInfo: Codable {
  let id: String
  let name: String
  let color: String?
}

/// One project's own view (OPH-336) — `WidgetListView` in Dart.
struct AWListView: Codable {
  let openToday: Int?
  let openTodayLabel: String?
  let next: AWNextTask?
  let buckets: [AWBucket]
}

/// The id of the whole list — `kWidgetListAll` in widget_grouping.dart.
let kAWListAll = "all"

extension AWSnapshot {
  /// The snapshot as a widget set to `listId` draws it (OPH-336).
  ///
  /// The app computed every list's rows, count and next task — the filter is
  /// Dart's (W9); this only picks one. An id the snapshot does not carry (a
  /// project deleted or archived since the widget was set up, or another
  /// workspace's) draws the whole list: an empty "all caught up" for a list
  /// that no longer exists would be a lie about the person's day.
  func selecting(_ listId: String?) -> (snapshot: AWSnapshot, list: AWListInfo?) {
    guard let listId, listId != kAWListAll, let view = views?[listId] else {
      return (self, nil)
    }
    var words = strings ?? [:]
    // The top level spells the WHOLE list's count; a project speaks its own.
    words["openToday"] = view.openTodayLabel
    let picked = AWSnapshot(
      v: v, generatedAt: generatedAt, locale: locale, date: date, strings: words,
      openToday: view.openToday, clockFormat: clockFormat, buckets: view.buckets,
      next: view.next, lists: lists, views: nil, density: density)
    return (picked, lists?.first { $0.id == listId })
  }
}

/// Reads the latest snapshot from the shared App Group container.
func loadAWSnapshot() -> AWSnapshot {
  guard
    let defaults = UserDefaults(suiteName: kAppGroupId),
    let raw = defaults.string(forKey: kSnapshotKey),
    let data = raw.data(using: .utf8),
    let snapshot = try? JSONDecoder().decode(AWSnapshot.self, from: data)
  else { return .empty }
  return snapshot
}

/// Round 15 (OPH-233): flips `done` on one row INSIDE the stored snapshot so
/// the tapped circle fills on the very next timeline render — the honest
/// optimistic echo of the queued completion. Mutates via JSONSerialization,
/// not the Codable model: a decode→encode round trip would silently DROP any
/// field this widget build does not know yet (the OPH-187 versioning stance).
func markAWSnapshotDone(taskId: String) {
  guard
    let defaults = UserDefaults(suiteName: kAppGroupId),
    let raw = defaults.string(forKey: kSnapshotKey),
    let data = raw.data(using: .utf8),
    var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  else { return }
  var changed = false
  if let buckets = json["buckets"] as? [[String: Any]] {
    json["buckets"] = awMarkDone(buckets, taskId: taskId, changed: &changed)
  }
  // OPH-336: the task sits in its project's view too. Echo it there as well,
  // or a widget set to that project keeps drawing an open circle.
  if var views = json["views"] as? [String: Any] {
    for (key, value) in views {
      guard
        var view = value as? [String: Any],
        let buckets = view["buckets"] as? [[String: Any]]
      else { continue }
      view["buckets"] = awMarkDone(buckets, taskId: taskId, changed: &changed)
      views[key] = view
    }
    json["views"] = views
  }
  guard changed else { return }
  if let out = try? JSONSerialization.data(withJSONObject: json),
    let text = String(data: out, encoding: .utf8)
  {
    defaults.set(text, forKey: kSnapshotKey)
  }
}

private func awMarkDone(
  _ buckets: [[String: Any]], taskId: String, changed: inout Bool
) -> [[String: Any]] {
  var buckets = buckets
  for bucketIndex in buckets.indices {
    guard var items = buckets[bucketIndex]["items"] as? [[String: Any]] else { continue }
    for itemIndex in items.indices where items[itemIndex]["id"] as? String == taskId {
      items[itemIndex]["done"] = true
      changed = true
    }
    buckets[bucketIndex]["items"] = items
  }
  return buckets
}

// MARK: - The widget's own complete intent (round 15, OPH-233)

/// The old circle reused `AWCompleteTaskIntent` — a **LiveActivityIntent**,
/// which iOS runs IN THE MAIN APP: every tap cold-started a headless Flutter
/// process in the background. Nothing visible happened on the widget, the
/// half-born process crashed when the user then opened the app, and the
/// completion only surfaced after a force-kill relaunch (the owner's exact
/// device report). A plain `AppIntent` runs HERE in the widget extension:
/// stamp the shared snapshot, queue the real completion for the app's
/// existing drain (AlarmKitBridge → Dart), redraw. No app launch at all.
@available(iOS 17.0, macOS 14.0, *)
struct AWWidgetCompleteIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete task"
  static var description = IntentDescription("Marks an AllisWell task done.")
  static var isDiscoverable: Bool = false

  @Parameter(title: "Task") var taskId: String

  init() {}

  init(taskId: String) {
    self.taskId = taskId
  }

  func perform() async throws -> some IntentResult {
    AWAlarmActionQueue.enqueue(actionId: "complete", taskId: taskId, reminderId: "")
    markAWSnapshotDone(taskId: taskId)
    WidgetCenter.shared.reloadTimelines(ofKind: kWidgetKind)
    return .result()
  }
}

// MARK: - Timeline

struct AWEntry: TimelineEntry {
  let date: Date
  let snapshot: AWSnapshot

  /// Whether this entry is one of the minute-granular ones that may draw a
  /// clock (C3). The midnight entries beyond the horizon are not: by then the
  /// clock would be a stale number pretending to be live, and the header has to
  /// degrade to something TRUE — the date block alone.
  let showsClock: Bool

  /// The project this widget is set to (OPH-336); nil for the whole list.
  var list: AWListInfo? = nil
}

/// iOS 16's provider: the whole list, nothing to configure. iOS 17 and macOS
/// 14 use `AWIntentProvider`; both hand WidgetKit the same `awTimeline`.
struct AWProvider: TimelineProvider {
  func placeholder(in context: Context) -> AWEntry {
    AWEntry(date: Date(), snapshot: .empty, showsClock: true)
  }

  func getSnapshot(in context: Context, completion: @escaping (AWEntry) -> Void) {
    completion(AWEntry(date: Date(), snapshot: loadAWSnapshot(), showsClock: true))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AWEntry>) -> Void) {
    completion(awTimeline(snapshot: loadAWSnapshot(), list: nil, family: context.family))
  }
}

/// The timeline every provider builds. OPH-336 lifted it out of `AWProvider`:
/// two providers must not grow two clocks.
func awTimeline(snapshot: AWSnapshot, list: AWListInfo?, family: WidgetFamily)
  -> Timeline<AWEntry>
{
  let calendar = Calendar.current
  let start = Date()

  // OPH-336: the lock screen draws no clock and no date, so it needs none of
  // the minute entries below — one entry, and a reload a minute past midnight
  // to pick up whatever the app wrote last.
  if awIsAccessory(family) {
    let reload =
      calendar.nextDate(
        after: start, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
      ?? start.addingTimeInterval(3600)
    return Timeline(
      entries: [AWEntry(date: start, snapshot: snapshot, showsClock: false, list: list)],
      policy: .after(reload))
  }

  var entries = [AWEntry(date: start, snapshot: snapshot, showsClock: true, list: list)]

  // How many minutes of clock this widget can afford to draw. Bytes, not
  // entries — see kAWArchiveBudgetBytes for the measurement that forced this.
  let rows = distribute(
    snapshot.buckets,
    budget: awRowBudget(family, titled: list != nil, compact: snapshot.isCompact))
    .reduce(0) { $0 + $1.items.count }
  let bytesPerEntry = kAWEntryBytesBase + rows * kAWEntryBytesPerRow
  let affordable = kAWArchiveBudgetBytes / max(bytesPerEntry, 1)
  let horizon = max(15, min(kAWClockHorizonMinutes, affordable))

  // OPH-253: one entry per minute so the clock changes when the minute does.
  // Anchored to the next :00 rather than to `start` — entries built by adding
  // 60 s to "now" land 22 seconds into every minute, and a clock that flips a
  // third of a minute late is a clock that is wrong a third of the time.
  if let firstTick = calendar.nextDate(
    after: start, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
  {
    for minute in 0..<horizon {
      guard
        let tick = calendar.date(byAdding: .minute, value: minute, to: firstTick)
      else { break }
      entries.append(AWEntry(date: tick, snapshot: snapshot, showsClock: true, list: list))
    }
  }
  let clockHorizon = entries.last?.date ?? start

  // Round 15 (OPH-232): a single entry + one midnight reload left the widget
  // frozen for DAYS when the app was not opened — after the first midnight
  // the reload re-rendered the SAME stale snapshot, still wearing yesterday's
  // date. The timeline still carries the next few midnights (the date header
  // renders from the ENTRY's date, so it stays truthful without the app), and
  // the trailing `.after` keeps the chain alive beyond the horizon. Task
  // buckets are still the app's honest snapshot — recomputing them here would
  // move product rules into native code (DESIGN §8 W1/W9), so a long-unopened
  // app shows an aging list under a correct date, not a native guess.
  //
  // These entries carry NO clock: they are the fallback for when the reload
  // never comes, and that is precisely when a clock would be lying (C3).
  var cursor = start
  for _ in 0..<4 {
    guard
      let midnight = calendar.nextDate(
        after: cursor,
        matching: DateComponents(hour: 0, minute: 1),
        matchingPolicy: .nextTime)
    else { break }
    cursor = midnight
    // Skip the ones the minute entries already cover, in order and in full.
    guard midnight > clockHorizon else { continue }
    entries.append(AWEntry(date: midnight, snapshot: snapshot, showsClock: false, list: list))
  }

  // Reload when the minute entries run out: 1440 / horizon times a day. An
  // empty widget affords the full 240 (6 a day); a ten-row one settles around
  // 115 (13 a day), still under a fifth of the 40–70 floor.
  return Timeline(entries: entries, policy: .after(clockHorizon))
}

// MARK: - Per-widget list (OPH-336)

/// A list a widget can be set to: the whole list or one project. The names
/// are the app's (`lists` in the snapshot); this only carries them to the
/// system's configuration sheet.
@available(iOS 17.0, macOS 14.0, *)
struct AWListEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "List"
  static var defaultQuery = AWListQuery()

  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

/// What the configuration sheet offers: the lists the app wrote in its last
/// snapshot, in the app's order.
@available(iOS 17.0, macOS 14.0, *)
struct AWListQuery: EntityStringQuery {
  func entities(for identifiers: [AWListEntity.ID]) async throws -> [AWListEntity] {
    let lists = awListEntities()
    return identifiers.compactMap { id in lists.first { $0.id == id } }
  }

  func suggestedEntities() async throws -> [AWListEntity] {
    awListEntities()
  }

  /// The sheet's search field — a team workspace can have more projects than
  /// a sheet can show.
  func entities(matching string: String) async throws -> [AWListEntity] {
    awListEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
  }

  func defaultResult() async -> AWListEntity? {
    awListEntities().first
  }
}

/// Before the app has written a v4 snapshot there is one list to offer: the
/// whole one, under the only name native code may carry — a fallback, as
/// `allCaughtUp` has one.
@available(iOS 17.0, macOS 14.0, *)
private func awListEntities() -> [AWListEntity] {
  let lists = loadAWSnapshot().lists ?? []
  guard !lists.isEmpty else { return [AWListEntity(id: kAWListAll, name: "All tasks")] }
  return lists.map { AWListEntity(id: $0.id, name: $0.name) }
}

/// The widget's one setting (OPH-336). Nil — never chosen, or a project that
/// has since gone — is the whole list, which is what every widget showed
/// before there was a setting.
@available(iOS 17.0, macOS 14.0, *)
struct AWWidgetConfigIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "List"
  static var description = IntentDescription("Choose which list this widget shows.")

  @Parameter(title: "List") var list: AWListEntity?

  init() {}
}

@available(iOS 17.0, macOS 14.0, *)
struct AWIntentProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> AWEntry {
    AWEntry(date: Date(), snapshot: .empty, showsClock: true)
  }

  func snapshot(for configuration: AWWidgetConfigIntent, in context: Context) async -> AWEntry {
    let picked = loadAWSnapshot().selecting(configuration.list?.id)
    return AWEntry(date: Date(), snapshot: picked.snapshot, showsClock: true, list: picked.list)
  }

  func timeline(for configuration: AWWidgetConfigIntent, in context: Context) async
    -> Timeline<AWEntry>
  {
    let picked = loadAWSnapshot().selecting(configuration.list?.id)
    return awTimeline(snapshot: picked.snapshot, list: picked.list, family: context.family)
  }
}

// MARK: - Colors (mirror docs/DESIGN.md)

private func awColor(hex: String?) -> Color? {
  guard var s = hex else { return nil }
  s = s.hasPrefix("#") ? String(s.dropFirst()) : s
  guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
  return Color(
    red: Double((value >> 16) & 0xFF) / 255,
    green: Double((value >> 8) & 0xFF) / 255,
    blue: Double(value & 0xFF) / 255)
}

/// Round 15 (OPH-232): the date header derives from the ENTRY's date so every
/// midnight timeline entry shows its own day even when the snapshot is old.
/// Weekday/month localization comes from the OS via the snapshot's locale —
/// OS date names are not product strings, so W9 stays intact. An empty
/// snapshot (no locale yet) falls back to the snapshot's own strings.
func awDate(for date: Date, locale: String) -> AWDate {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: locale)
  formatter.dateFormat = "EEE"
  let weekday = formatter.string(from: date)
  formatter.dateFormat = "d"
  let day = formatter.string(from: date)
  formatter.dateFormat = "MMMM"
  let month = formatter.string(from: date)
  return AWDate(weekday: weekday, day: day, month: month)
}

/// The header clock's text, or nil when it must not be drawn (OPH-253, C2+C3).
///
/// Two gates, and they guard different failures. `showsClock` is the one we
/// planned for — an entry from beyond the minute horizon, where a clock was
/// never promised. The age check is the one we did not: WidgetKit can defer a
/// reload when the budget runs dry, and then it keeps re-rendering the last
/// entry it has. Without the second gate that entry's minute would sit there
/// looking authoritative for hours.
///
/// The PATTERN comes from the snapshot, not from this process. Which clock the
/// user reads — 24-hour, or 12-hour with an AM/PM marker — is a product rule
/// (W9) that the app already settled for the task rows below (OPH-174); a
/// header disagreeing with its own rows is the thing that rule exists to stop.
func awClockLabel(for entry: AWEntry, now: Date = Date()) -> String? {
  guard entry.showsClock else { return nil }
  guard now.timeIntervalSince(entry.date) <= kAWClockStaleSeconds else { return nil }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: entry.snapshot.locale)
  if let pattern = entry.snapshot.clockFormat, !pattern.isEmpty {
    formatter.dateFormat = pattern
  } else {
    // A v2 snapshot from an older app carries no pattern. Ask the locale rather
    // than hardcoding one — guessing "HH:mm" would hand a 24-hour clock to
    // someone who set 12-hour, which is C2's exact prohibition.
    formatter.dateStyle = .none
    formatter.timeStyle = .short
  }
  return formatter.string(from: entry.date)
}

/// The header badge's text, or nil when there is nothing to say. The COUNT and
/// its wording both come from the app (W9): native code carries no product rule
/// and no translations.
func awOpenTodayLabel(_ snap: AWSnapshot) -> String? {
  guard let count = snap.openToday, count > 0 else { return nil }
  if let label = snap.strings?["openToday"], !label.isEmpty { return label }
  // A v1 snapshot from an older app has the string table but not the phrase —
  // show the bare number rather than nothing.
  return "\(count)"
}

private func priorityColor(_ p: String) -> Color? {
  switch p {
  case "urgent": return Color(red: 0.86, green: 0.15, blue: 0.15)
  case "high": return Color(red: 0.76, green: 0.25, blue: 0.05)
  case "medium": return Color(red: 0.71, green: 0.33, blue: 0.04)
  case "low": return Color(red: 0.02, green: 0.47, blue: 0.34)
  default: return nil
  }
}

// MARK: - Views

struct AWDateHeader: View {
  let date: AWDate
  let clock: String?
  let openToday: String?
  /// OPH-333: the "+"'s spoken label, pre-localized by the app.
  let addLabel: String

  var body: some View {
    // OPH-187 (round 10 #4A): `.firstTextBaseline` aligned a 34 pt number's
    // baseline to a 14 pt label's, which left the month line hanging below and
    // read as a typo. Optically centred instead — and Android draws the same
    // header the same way now (DESIGN §8 W6 applies W1's parity rule to LAYOUT,
    // not just color; the two platforms disagreed for a whole release).
    HStack(alignment: .center, spacing: 8) {
      Text(date.day)
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .monospacedDigit()
      VStack(alignment: .leading, spacing: 0) {
        Text(date.weekday).font(.subheadline.weight(.semibold))
        Text(date.month).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      // OPH-253 (round 17 #4): the clock on top, the count under it, both hard
      // against the trailing edge.
      //
      // `.trailing` is load-bearing, not taste. Two lines of different widths
      // under a `Spacer()` default to leading, which leaves the shorter one
      // hanging in mid-air — the SAME complaint #4A fixed on this header once
      // already, when a baseline-aligned month line read as a typo.
      //
      // C5 needs no special case: at zero open tasks the count is nil, the
      // VStack collapses to the clock alone, and the HStack's `.center` puts it
      // on the date block's optical centre by itself.
      if clock != nil || openToday != nil {
        VStack(alignment: .trailing, spacing: 0) {
          if let clock {
            Text(clock)
              .font(.title3.weight(.bold))
              .monospacedDigit()
              .lineLimit(1)
          }
          // #4B: what is on you today — overdue + due today. Pre-localized by
          // the app; hidden at zero, because a badge reading "0" is noise (W9).
          if let openToday {
            Text(openToday)
              .font(.caption.weight(.semibold))
              .monospacedDigit()
              // Turkish says it in more words than English does; scale before
              // wrapping, because a two-line count under the clock would push
              // the whole header taller and shove the task list down.
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .foregroundStyle(.secondary)
          }
        }
      }
      // OPH-333: last in the row, so the clock and the count keep the edge
      // they are measured against (C1–C5) and the "+" sits outside them.
      AWAddLink(label: addLabel)
    }
  }
}

/// DESIGN §3.1 `primary`, mirrored natively (W1 — token parity): light
/// #0A5CFF, dark #3E9BFF — the same pair Android carries as `aw_widget_accent`.
/// Both clear the 3:1 icon floor on the widget's background (W2). One source
/// file serves iOS and macOS (OPH-335), so the dynamic color is built from
/// whichever toolkit the platform has.
#if canImport(UIKit)
  private let awPrimary = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x3E / 255.0, green: 0x9B / 255.0, blue: 0xFF / 255.0, alpha: 1)
      : UIColor(red: 0x0A / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0, alpha: 1)
  })
#else
  private let awPrimary = Color(NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(red: 0x3E / 255.0, green: 0x9B / 255.0, blue: 0xFF / 255.0, alpha: 1)
      : NSColor(red: 0x0A / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0, alpha: 1)
  })
#endif

/// The card behind the rows: the system's own background on each platform, so
/// the OS themes it (DESIGN W3 — no fake glass).
#if canImport(UIKit)
  private let awWidgetBackground = Color(.systemBackground)
#else
  private let awWidgetBackground = Color(nsColor: .windowBackgroundColor)
#endif

/// OPH-333: the widget's "+" — a deep link into the app's create sheet, not an
/// App Intent. Adding needs a title and a widget cannot take text, so the only
/// honest thing a button here can do is bring the app forward ready to type.
/// 44 pt hit target (DESIGN W4 / rule 11). On large/extraLarge it closes the
/// date header; systemMedium draws no header, so there it gets a narrow column
/// of its own rather than costing a row (WIDGETS §5: one "+" at 4×2 too).
struct AWAddLink: View {
  let label: String
  var body: some View {
    Link(destination: URL(string: "alliswell://add")!) {
      Image(systemName: "plus.circle.fill")
        .font(.title2)
        .foregroundStyle(awPrimary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(label)
  }
}

struct AWTaskRowView: View {
  let row: AWTaskRow
  /// OPH-337: a smaller type size. The circle's frame does NOT shrink with it —
  /// its hit target is W4's, and density is not a reason to miss it.
  var compact = false
  var body: some View {
    HStack(spacing: 8) {
      // OPH-188: the circle is a BUTTON on iOS 17+. WidgetKit performs the
      // intent in the background — no app launch — and the press lands in the
      // app-group queue OPH-182 already built. iOS 16 keeps the deep-link floor
      // (the row opens the task), which is why this is gated rather than
      // replaced. Generous hit target: the stock Reminders widget's loudest
      // complaint is completing the wrong thing by accident (DESIGN W4).
      if #available(iOS 17.0, macOS 14.0, *), !row.done {
        Button(intent: AWWidgetCompleteIntent(taskId: row.id)) {
          Image(systemName: "circle")
            .foregroundStyle(Color.secondary)
            .imageScale(.medium)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        Image(systemName: row.done ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(row.done ? Color.green : Color.secondary)
          .imageScale(.medium)
      }
      if let flag = priorityColor(row.priority) {
        Circle().fill(flag).frame(width: 6, height: 6)
      }
      Text(row.title)
        .font(compact ? .caption : .footnote)
        .lineLimit(1)
        .strikethrough(row.done)
      Spacer(minLength: 4)
      if let time = row.time {
        Text(time).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
      }
      if let color = awColor(hex: row.projectColor) {
        Circle().fill(color).frame(width: 8, height: 8)
      }
    }
    // OPH-188/189: the row opens ITS task, not just the app. Needs the routing
    // OPH-189 added — before that this URL produced "No route for …".
    .widgetURL(URL(string: "alliswell://task/\(row.id)"))
  }
}

struct AWBucketView: View {
  let bucket: AWBucket
  var compact = false
  var body: some View {
    // OPH-337: compact takes its rows from the gap between them.
    VStack(alignment: .leading, spacing: compact ? 1 : 4) {
      HStack {
        Text(bucket.label.uppercased())
          .font(.caption2.weight(.bold))
          .foregroundStyle(bucket.key == "overdue" ? Color.red : Color.secondary)
        Text("\(bucket.count)")
          .font(.caption2).foregroundStyle(.secondary)
        Spacer()
      }
      ForEach(bucket.items) { AWTaskRowView(row: $0, compact: compact) }
      if let more = bucket.more, more > 0 {
        Text("+\(more)").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

struct AllisWellWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: AWEntry

  var body: some View {
    let snap = entry.snapshot
    let addLabel = snap.strings?["addTask"] ?? "Add task"
    // OPH-253, measured on device: a full list is TALLER than a systemLarge
    // card, and an oversized child centres itself — so the widget was losing
    // pixels at BOTH ends, and the top end is where the header lives. The day
    // number came out sliced in half and the new clock was cut off the card
    // entirely: shipped, rendered, and invisible.
    //
    // `.frame(maxHeight: .infinity, alignment: .top)` does NOT fix this — a max
    // frame only ever GROWS to the proposal; when the child is bigger the frame
    // reports the child's size and there is nothing left for the alignment to
    // do. Clamping to the geometry's exact height is what makes `.top` bite,
    // and it decides WHICH end loses when something has to. It must be the
    // bottom: the list already has a vocabulary for being cut short ("+N"), and
    // the header does not.
    GeometryReader { geo in
      // OPH-333: the medium size has no date header to carry the "+", so it
      // gets a narrow trailing column — 44 pt of width instead of a row.
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: snap.isCompact ? 4 : 8) {
          if family != .systemMedium {
            // Round 15: the ENTRY's date, not the snapshot's — see awDate(for:).
            AWDateHeader(
              date: snap.generatedAt.isEmpty
                ? snap.date
                : awDate(for: entry.date, locale: snap.locale),
              clock: awClockLabel(for: entry),
              openToday: awOpenTodayLabel(snap),
              addLabel: addLabel)
          }
          // OPH-336: a widget set to one project names it — two widgets set
          // to two projects have to be told apart at a glance. The whole
          // list draws no title, exactly as before there was a choice.
          if let list = entry.list {
            AWListTitle(list: list)
          }
          if snap.buckets.isEmpty {
            Spacer()
            Text(snap.strings?["allCaughtUp"] ?? "All caught up")
              .font(.subheadline).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
          } else {
            ForEach(
              distribute(
                snap.buckets,
                budget: awRowBudget(
                  family, titled: entry.list != nil, compact: snap.isCompact))
            ) {
              AWBucketView(bucket: $0, compact: snap.isCompact)
            }
          }
          Spacer(minLength: 0)
        }
        if family == .systemMedium {
          AWAddLink(label: addLabel)
        }
      }
      .padding(family == .systemMedium ? 12 : 14)
      .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
    }
    .widgetURL(URL(string: "alliswell://open"))
  }
}

/// How many task rows a size draws. A free function rather than a view property
/// because `awTimeline` needs it too: the number of rows is what decides how
/// many minute entries fit in the archive (kAWArchiveBudgetBytes).
///
/// OPH-336: a widget set to one project pays for its title line with a row —
/// otherwise the geometry clamp above cuts the last row in half.
///
/// OPH-337: compact rows are 29 pt apart instead of 32 (the 28 pt circle stays,
/// the 4 pt gap becomes 1), so the SAME height holds `normal × 32 / 29` rows,
/// rounded down: 4 → 4, 10 → 11, 18 → 19. Derived from the measured normal
/// budgets rather than guessed — a row too many is cut in half at the bottom.
func awRowBudget(_ family: WidgetFamily, titled: Bool = false, compact: Bool = false) -> Int {
  let rows: Int
  switch family {
  case .systemMedium: rows = 4
  case .systemLarge: rows = compact ? 11 : 10
  default: rows = compact ? 19 : 18
  }
  return titled ? rows - 1 : rows
}

/// The lock screen's families (OPH-336). They exist on iOS only — macOS marks
/// them unavailable, so every mention sits behind `os(iOS)`.
func awIsAccessory(_ family: WidgetFamily) -> Bool {
  #if os(iOS)
    switch family {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
    default: return false
    }
  #else
    return false
  #endif
}

/// Greedily trims buckets so the visible rows fit the size's budget.
private func distribute(_ buckets: [AWBucket], budget: Int) -> [AWBucket] {
  var remaining = budget
  var out: [AWBucket] = []
  for b in buckets {
    if remaining <= 0 { break }
    let take = min(b.items.count, remaining)
    let trimmed = Array(b.items.prefix(take))
    let extra = b.count - trimmed.count
    out.append(
      AWBucket(
        key: b.key, label: b.label, count: b.count, items: trimmed,
        more: extra > 0 ? extra : nil))
    remaining -= take
  }
  return out
}

/// OPH-336: the name of the project a widget is set to, above its rows, in
/// the project's own color.
struct AWListTitle: View {
  let list: AWListInfo
  var body: some View {
    HStack(spacing: 6) {
      if let color = awColor(hex: list.color) {
        Circle().fill(color).frame(width: 8, height: 8)
      }
      Text(list.name)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
  }
}

// MARK: - Lock screen (OPH-336, iOS 16+)

#if os(iOS)
  /// The rectangle: the next task, in the app's words. The heading is the
  /// list's name when the widget is set to one, "Up next" otherwise; under the
  /// title, its bucket and time ("Overdue · 10 Jul", "Today · 14:30") — on a
  /// lock screen drawn in one tint, the WORD is what says it is late.
  struct AWAccessoryRectangularView: View {
    let entry: AWEntry

    var body: some View {
      let snap = entry.snapshot
      VStack(alignment: .leading, spacing: 0) {
        Text(entry.list?.name ?? snap.strings?["upNext"] ?? "Up next")
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .widgetAccentable()
        if let next = snap.next {
          Text(next.title)
            .font(.headline)
            .lineLimit(1)
          Text([next.label, next.time].compactMap { $0 }.joined(separator: " · "))
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
        } else {
          Text(snap.strings?["allCaughtUp"] ?? "All caught up")
            .font(.headline)
            .lineLimit(2)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // The rectangle IS the next task: tapping it opens that task.
      .widgetURL(URL(string: snap.next.map { "alliswell://task/\($0.id)" } ?? "alliswell://open"))
    }
  }

  /// The circle: how much is on the person today — the header badge's number
  /// (overdue + due today, open only), counted by the app. A tick at zero: a
  /// circle reading "0" is noise, the badge's own rule (W9).
  struct AWAccessoryCircularView: View {
    let entry: AWEntry

    var body: some View {
      let count = entry.snapshot.openToday ?? 0
      ZStack {
        AccessoryWidgetBackground()
        if count > 0 {
          VStack(spacing: 0) {
            Image(systemName: "checklist").font(.caption)
            Text("\(count)")
              .font(.title3.weight(.semibold))
              .monospacedDigit()
              .minimumScaleFactor(0.5)
              .lineLimit(1)
          }
        } else {
          Image(systemName: "checkmark").font(.title3.weight(.semibold))
        }
      }
      .widgetAccentable()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        awOpenTodayLabel(entry.snapshot) ?? entry.snapshot.strings?["allCaughtUp"] ?? "")
      .widgetURL(URL(string: "alliswell://open"))
    }
  }
#endif

/// One root for every family and both providers (OPH-336): the lock screen's
/// views on iOS, the list everywhere else, and the system background only
/// where a card belongs.
struct AWWidgetRootView: View {
  @Environment(\.widgetFamily) private var family
  let entry: AWEntry

  var body: some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      content.containerBackground(for: .widget) {
        awIsAccessory(family) ? Color.clear : awWidgetBackground
      }
    } else if awIsAccessory(family) {
      // iOS 16's lock screen: no card behind a glyph the system tints.
      content
    } else {
      content
        .padding()
        .background(awWidgetBackground)
    }
  }

  @ViewBuilder private var content: some View {
    #if os(iOS)
      switch family {
      case .accessoryCircular: AWAccessoryCircularView(entry: entry)
      case .accessoryRectangular: AWAccessoryRectangularView(entry: entry)
      default: AllisWellWidgetEntryView(entry: entry)
      }
    #else
      AllisWellWidgetEntryView(entry: entry)
    #endif
  }
}

// MARK: - Widgets (no @main — that's in AllisWellWidgetBundle.swift)

/// The families the widget offers. OPH-336 adds the lock screen's two, which
/// are iOS-only.
private var awFamilies: [WidgetFamily] {
  #if os(iOS)
    return [
      .systemMedium, .systemLarge, .systemExtraLarge,
      .accessoryRectangular, .accessoryCircular,
    ]
  #else
    return [.systemMedium, .systemLarge, .systemExtraLarge]
  #endif
}

/// iOS 16's widget: the whole list, nothing to configure —
/// AppIntentConfiguration begins at iOS 17.
///
/// On iOS 17 and later it has to STEP ASIDE, and at runtime, because the
/// bundle cannot drop it there. MEASURED (OPH-336, iOS 26.2 SDK): a
/// WidgetBundle takes `if #available` and nothing else — WidgetBundleBuilder
/// has no `buildEither`, so `else` is a compile error, and `if #unavailable`
/// crashes the compiler outright. So this struct is in every bundle, and on
/// iOS 17+ it gives its kind away — to `AllisWellConfigurableWidget`, which
/// takes it over, so a widget placed under iOS 16 wakes up on 17 as the
/// configurable one, set to the whole list — and it offers no family, so the
/// gallery shows one AllisWell, not two.
struct AllisWellWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: awStaticKind, provider: AWProvider()) { entry in
      AWWidgetRootView(entry: entry)
    }
    .configurationDisplayName("AllisWell")
    .description("Your tasks at a glance — overdue, today and beyond.")
    .supportedFamilies(awStaticFamilies)
  }
}

private var awStaticKind: String {
  if #available(iOS 17.0, macOS 14.0, *) { return kWidgetKind + ".ios16" }
  return kWidgetKind
}

private var awStaticFamilies: [WidgetFamily] {
  if #available(iOS 17.0, macOS 14.0, *) { return [] }
  return awFamilies
}

/// The widget on iOS 17+ and macOS 14+ (OPH-336): the same views, plus one
/// setting per placed widget — the whole list (the default, and what every
/// widget showed before) or one project. The kind is the one the widget has
/// always had, so placed widgets keep their place.
@available(iOS 17.0, macOS 14.0, *)
struct AllisWellConfigurableWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kWidgetKind, intent: AWWidgetConfigIntent.self, provider: AWIntentProvider()
    ) { entry in
      AWWidgetRootView(entry: entry)
    }
    .configurationDisplayName("AllisWell")
    .description("Your tasks at a glance — overdue, today and beyond.")
    .supportedFamilies(awFamilies)
  }
}
