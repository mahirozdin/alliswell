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

  static let empty = AWSnapshot(
    v: 3, generatedAt: "", locale: "en",
    date: AWDate(weekday: "", day: "", month: ""), strings: nil, openToday: nil,
    clockFormat: nil, buckets: [])
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
    var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    var buckets = json["buckets"] as? [[String: Any]]
  else { return }
  var changed = false
  for bucketIndex in buckets.indices {
    guard var items = buckets[bucketIndex]["items"] as? [[String: Any]] else { continue }
    for itemIndex in items.indices where items[itemIndex]["id"] as? String == taskId {
      items[itemIndex]["done"] = true
      changed = true
    }
    buckets[bucketIndex]["items"] = items
  }
  guard changed else { return }
  json["buckets"] = buckets
  if let out = try? JSONSerialization.data(withJSONObject: json),
    let text = String(data: out, encoding: .utf8)
  {
    defaults.set(text, forKey: kSnapshotKey)
  }
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
@available(iOS 17.0, *)
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
}

struct AWProvider: TimelineProvider {
  func placeholder(in context: Context) -> AWEntry {
    AWEntry(date: Date(), snapshot: .empty, showsClock: true)
  }

  func getSnapshot(in context: Context, completion: @escaping (AWEntry) -> Void) {
    completion(AWEntry(date: Date(), snapshot: loadAWSnapshot(), showsClock: true))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AWEntry>) -> Void) {
    let snapshot = loadAWSnapshot()
    // Round 15 (OPH-232): a single entry + one midnight reload left the widget
    // frozen for DAYS when the app was not opened — after the first midnight
    // the reload re-rendered the SAME stale snapshot, still wearing
    // yesterday's date. The timeline now carries an entry for NOW plus the
    // next few midnights (the date header renders from the ENTRY's date, so
    // it stays truthful without the app), and the trailing `.after` keeps the
    // chain alive beyond the horizon. Task buckets are still the app's honest
    // snapshot — recomputing them here would move product rules into native
    // code (DESIGN §8 W1/W9), so a long-unopened app shows an aging list
    // under a correct date, not a native guess.
    let calendar = Calendar.current
    let start = Date()
    var entries = [AWEntry(date: start, snapshot: snapshot, showsClock: true)]

    // How many minutes of clock this widget can afford to draw. Bytes, not
    // entries — see kAWArchiveBudgetBytes for the measurement that forced this.
    let rows = distribute(snapshot.buckets, budget: awRowBudget(context.family))
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
        entries.append(AWEntry(date: tick, snapshot: snapshot, showsClock: true))
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
      entries.append(AWEntry(date: midnight, snapshot: snapshot, showsClock: false))
    }

    // Reload when the minute entries run out: 1440 / horizon times a day. An
    // empty widget affords the full 240 (6 a day); a ten-row one settles around
    // 115 (13 a day), still under a fifth of the 40–70 floor.
    completion(Timeline(entries: entries, policy: .after(clockHorizon)))
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
    }
  }
}

struct AWTaskRowView: View {
  let row: AWTaskRow
  var body: some View {
    HStack(spacing: 8) {
      // OPH-188: the circle is a BUTTON on iOS 17+. WidgetKit performs the
      // intent in the background — no app launch — and the press lands in the
      // app-group queue OPH-182 already built. iOS 16 keeps the deep-link floor
      // (the row opens the task), which is why this is gated rather than
      // replaced. Generous hit target: the stock Reminders widget's loudest
      // complaint is completing the wrong thing by accident (DESIGN W4).
      if #available(iOS 17.0, *), !row.done {
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
        .font(.footnote)
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
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(bucket.label.uppercased())
          .font(.caption2.weight(.bold))
          .foregroundStyle(bucket.key == "overdue" ? Color.red : Color.secondary)
        Text("\(bucket.count)")
          .font(.caption2).foregroundStyle(.secondary)
        Spacer()
      }
      ForEach(bucket.items) { AWTaskRowView(row: $0) }
      if let more = bucket.more, more > 0 {
        Text("+\(more)").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

struct AllisWellWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: AWProvider.Entry

  var body: some View {
    let snap = entry.snapshot
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
      VStack(alignment: .leading, spacing: 8) {
        if family != .systemMedium {
          // Round 15: the ENTRY's date, not the snapshot's — see awDate(for:).
          AWDateHeader(
            date: snap.generatedAt.isEmpty
              ? snap.date
              : awDate(for: entry.date, locale: snap.locale),
            clock: awClockLabel(for: entry),
            openToday: awOpenTodayLabel(snap))
        }
        if snap.buckets.isEmpty {
          Spacer()
          Text(snap.strings?["allCaughtUp"] ?? "All caught up")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
          Spacer()
        } else {
          ForEach(distribute(snap.buckets, budget: awRowBudget(family))) {
            AWBucketView(bucket: $0)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(family == .systemMedium ? 12 : 14)
      .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
    }
    .widgetURL(URL(string: "alliswell://open"))
  }
}

/// How many task rows a size draws. A free function rather than a view property
/// because `getTimeline` needs it too: the number of rows is what decides how
/// many minute entries fit in the archive (kAWArchiveBudgetBytes).
func awRowBudget(_ family: WidgetFamily) -> Int {
  switch family {
  case .systemMedium: return 4
  case .systemLarge: return 10
  default: return 18
  }
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

// MARK: - Widget (no @main — that's in AllisWellWidgetBundle.swift)

struct AllisWellWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kWidgetKind, provider: AWProvider()) { entry in
      if #available(iOS 17.0, *) {
        AllisWellWidgetEntryView(entry: entry)
          .containerBackground(for: .widget) { Color(.systemBackground) }
      } else {
        AllisWellWidgetEntryView(entry: entry)
          .padding()
          .background(Color(.systemBackground))
      }
    }
    .configurationDisplayName("AllisWell")
    .description("Your tasks at a glance — overdue, today and beyond.")
    .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
  }
}
