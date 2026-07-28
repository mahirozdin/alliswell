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
  let buckets: [AWBucket]

  static let empty = AWSnapshot(
    v: 2, generatedAt: "", locale: "en",
    date: AWDate(weekday: "", day: "", month: ""), strings: nil, openToday: nil,
    buckets: [])
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

// MARK: - Timeline

struct AWEntry: TimelineEntry {
  let date: Date
  let snapshot: AWSnapshot
}

struct AWProvider: TimelineProvider {
  func placeholder(in context: Context) -> AWEntry {
    AWEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (AWEntry) -> Void) {
    completion(AWEntry(date: Date(), snapshot: loadAWSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<AWEntry>) -> Void) {
    let entry = AWEntry(date: Date(), snapshot: loadAWSnapshot())
    // Roll Today/Overdue over at the next local midnight; foreground app pushes
    // (home_widget updateWidget) keep it current the rest of the time.
    let nextMidnight =
      Calendar.current.nextDate(
        after: Date(),
        matching: DateComponents(hour: 0, minute: 1),
        matchingPolicy: .nextTime) ?? Date().addingTimeInterval(6 * 3600)
    completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
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
      // #4B: what is on you today — overdue + due today. Pre-localized by the
      // app; hidden at zero, because a badge reading "0" is noise (W9).
      if let openToday {
        Text(openToday)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
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
        Button(intent: AWCompleteTaskIntent(taskId: row.id)) {
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

  private var rowBudget: Int {
    switch family {
    case .systemMedium: return 4
    case .systemLarge: return 10
    default: return 18
    }
  }

  var body: some View {
    let snap = entry.snapshot
    VStack(alignment: .leading, spacing: 8) {
      if family != .systemMedium {
        AWDateHeader(date: snap.date, openToday: awOpenTodayLabel(snap))
      }
      if snap.buckets.isEmpty {
        Spacer()
        Text(snap.strings?["allCaughtUp"] ?? "All caught up")
          .font(.subheadline).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      } else {
        ForEach(distribute(snap.buckets, budget: rowBudget)) { AWBucketView(bucket: $0) }
      }
      Spacer(minLength: 0)
    }
    .padding(family == .systemMedium ? 12 : 14)
    .widgetURL(URL(string: "alliswell://open"))
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
