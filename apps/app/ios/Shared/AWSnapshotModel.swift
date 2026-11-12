import Foundation

// The widget snapshot model (mirrors WidgetSnapshot.toJson() in
// apps/app/lib/src/features/widgets/widget_snapshot.dart).
//
// OPH-451 moved it here from AllisWellWidget.swift, unchanged but for the v6
// `days`, so Runner compiles it too and RunnerTests can test the pure code that
// reads it (AWWidgetDayPick.swift). Foundation only: the iOS widget extension,
// the macOS widget and Runner all compile this file.
//
// Decoding stays TOLERANT: every field added after v1 is optional, so an older
// or a newer app's snapshot decodes rather than blanking the widget.

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
  // OPH-451 (v6, #50): today and the next days, each a full view. A timeline
  // entry draws the one whose `date` is its own local day (awDayView). Absent
  // in a v5 snapshot, which then draws its top level as before.
  let days: [AWDayView]?

  static let empty = AWSnapshot(
    v: 5, generatedAt: "", locale: "en",
    date: AWDate(weekday: "", day: "", month: ""), strings: nil, openToday: nil,
    clockFormat: nil, buckets: [], next: nil, lists: nil, views: nil, density: nil,
    days: nil)

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
  // v5: a calendar event rides in the same list. Optional like every field
  // after v1 — a v4 row has neither and decodes as the task it is.
  let kind: String?
  let day: String?
  /// True for a row of the server's view that the app's own snapshot does not
  /// hold (OPH-462): a task created elsewhere while the app was swiped away.
  /// The app has no copy of it to apply a completion to, so its circle does
  /// not complete in place; the row opens the app instead. Swift sets it when
  /// it spells the server's view; the app never writes it.
  var serverOnly: Bool? = nil

  /// `kWidgetKindEvent` in widget_snapshot.dart.
  var isEvent: Bool { kind == "event" }

  /// Whether the row's circle completes the task from the widget: an open
  /// task the app holds.
  var canCompleteInPlace: Bool { !done && !isEvent && serverOnly != true }

  /// Where an event row's tap goes: Home with its day selected. Nil for a
  /// task, or for a day that is not `yyyy-MM-dd` (a URL is input).
  var dayURL: URL? {
    guard isEvent, let day = day,
      day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    else { return nil }
    return URL(string: "alliswell://day/\(day)")
  }
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

/// One day of the widget (v6, OPH-451) — `WidgetDayView` in Dart: what the top
/// level carries for today, computed by the app for that day. Every field is
/// optional so one malformed day can never fail the whole decode: a day without
/// a `date` matches no entry, one without `buckets` draws "all caught up".
struct AWDayView: Codable {
  /// The local day, `yyyy-MM-dd`.
  let date: String?
  let header: AWDate?
  let openToday: Int?
  let openTodayLabel: String?
  let next: AWNextTask?
  let buckets: [AWBucket]?
  let views: [String: AWListView]?
}

extension AWSnapshot {
  /// Every row id the snapshot draws anywhere: the top level, the project
  /// views and every day with its own project views.
  var rowIds: Set<String> {
    var ids = Set<String>()
    func add(_ buckets: [AWBucket]?) {
      for bucket in buckets ?? [] { for row in bucket.items { ids.insert(row.id) } }
    }
    add(buckets)
    for view in (views ?? [:]).values { add(view.buckets) }
    for day in days ?? [] {
      add(day.buckets)
      for view in (day.views ?? [:]).values { add(view.buckets) }
    }
    return ids
  }
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
      next: view.next, lists: lists, views: nil, density: density, days: nil)
    return (picked, lists?.first { $0.id == listId })
  }
}

// MARK: - The done stamp (round 15, OPH-233; OPH-451)

/// Records a completion from the widget's circle INSIDE the stored snapshot
/// JSON, so the very next timeline render shows it — the honest optimistic
/// echo of the queued completion. Works on the JSONSerialization tree, not the
/// Codable model: a decode→encode round trip would silently DROP any field this
/// build does not know yet (the OPH-187 versioning stance).
///
/// The row sits in the top level, in its project's view (OPH-336) and, since
/// v6, in every day view and that day's project views (OPH-451) — the entries
/// draw from the days, so every place is written. In each one, by the rules
/// the app wrote it with (widget_snapshot.dart, DESIGN §8 W9, §20 C5):
/// - the row turns done, as the app draws today's finished work; in a LATER
///   day's view it leaves, because the app keeps a finished task only on the
///   day it was finished (`keepCompletedSince`);
/// - its bucket's number drops by one (a bucket counts open rows only);
/// - the open count drops by one when the row was overdue or today, and its
///   words are re-spelled from `strings.openTodayPattern` (the app's phrase);
/// - the lock screen's `next`, when it is this task, moves on to the first
///   open task the app ordered after it.
///
/// Idempotent: a row already done changes nothing, so a completion applied
/// again (a queued one on every read, `awApplyPendingCompletions`) never counts
/// twice. `today` is the completion's local day, `yyyy-MM-dd`; nil treats
/// every day as today. Returns whether anything changed.
@discardableResult
func awMarkSnapshotDone(_ json: inout [String: Any], taskId: String, today: String? = nil) -> Bool {
  var changed = false
  var strings = json["strings"] as? [String: Any]
  let pattern = strings?["openTodayPattern"] as? String

  // The top level: its count's words live in `strings.openToday`.
  var topLabel = strings?["openToday"] as? String
  awCompleteInLevel(
    &json, taskId: taskId, leaves: false, label: &topLabel, pattern: pattern,
    changed: &changed)
  if strings != nil {
    strings?["openToday"] = topLabel
    json["strings"] = strings
  }

  if var days = json["days"] as? [[String: Any]] {
    for index in days.indices {
      let date = days[index]["date"] as? String
      let later = today != nil && date != nil && date! > today!
      awCompleteInLevelWithOwnLabel(
        &days[index], taskId: taskId, leaves: later, pattern: pattern, changed: &changed)
    }
    json["days"] = days
  }
  return changed
}

/// Applies every completion still queued for the app (`AWAlarmActionQueue`)
/// to a snapshot just read. The app rewrites the snapshot from its own data
/// whenever that changes, and until it has pulled the queue its data still
/// has the task open — so a rewrite between the tap and the pull would put the
/// row back. Reading through the queue keeps it done until the app knows.
@discardableResult
func awApplyPendingCompletions(
  _ json: inout [String: Any], taskIds: [String], today: String?
) -> Bool {
  var changed = false
  for taskId in taskIds where awMarkSnapshotDone(&json, taskId: taskId, today: today) {
    changed = true
  }
  return changed
}

/// The spoken label of a row's complete circle: the app's words with the
/// row's title (OPH-451, IOS-11) — never the symbol's name.
func awCompleteLabel(title: String, strings: [String: String]?) -> String {
  let pattern = strings?["completeTask"] ?? ""
  if pattern.contains("{title}") {
    return pattern.replacingOccurrences(of: "{title}", with: title)
  }
  // A snapshot from an app without the phrase: the title still names the row.
  return title
}

/// The open count's words for `new`, from the app's phrase; for a snapshot
/// without it, the old words with their number replaced; nil when neither
/// works (the header then shows the bare number, `awOpenTodayLabel`).
func awRespellOpenCount(_ label: String?, from old: Int, to new: Int, pattern: String?)
  -> String?
{
  if let pattern, pattern.contains("{count}") {
    return pattern.replacingOccurrences(of: "{count}", with: String(new))
  }
  guard let label, let range = label.range(of: String(old)) else { return nil }
  return label.replacingCharacters(in: range, with: String(new))
}

/// A day view or a project view: its count's words are its own
/// `openTodayLabel`.
private func awCompleteInLevelWithOwnLabel(
  _ level: inout [String: Any], taskId: String, leaves: Bool, pattern: String?,
  changed: inout Bool
) {
  var label = level["openTodayLabel"] as? String
  let before = level["openToday"] as? Int
  awCompleteInLevel(
    &level, taskId: taskId, leaves: leaves, label: &label, pattern: pattern, changed: &changed)
  if before != level["openToday"] as? Int { level["openTodayLabel"] = label }
}

/// The buckets that count toward the open count (W9) — `WidgetBucket.overdue`
/// and `.today` in Dart.
private let kAWCountedBuckets: Set<String> = ["overdue", "today"]

/// The order the app picks `next` in (`nextTaskForWidget`): dated work first,
/// the dateless last.
private let kAWNextOrder = ["overdue", "today", "thisWeek", "thisMonth", "noDate"]

/// One level of the snapshot (the top level or a day) and every project view
/// under it.
private func awCompleteInLevel(
  _ level: inout [String: Any], taskId: String, leaves: Bool, label: inout String?,
  pattern: String?, changed: inout Bool
) {
  awCompleteInView(
    &level, taskId: taskId, leaves: leaves, label: &label, pattern: pattern, changed: &changed)
  if var views = level["views"] as? [String: Any] {
    for (key, value) in views {
      guard var project = value as? [String: Any] else { continue }
      awCompleteInLevelWithOwnLabel(
        &project, taskId: taskId, leaves: leaves, pattern: pattern, changed: &changed)
      views[key] = project
    }
    level["views"] = views
  }
}

/// One list: its buckets, its open count and its `next`.
private func awCompleteInView(
  _ view: inout [String: Any], taskId: String, leaves: Bool, label: inout String?,
  pattern: String?, changed: inout Bool
) {
  var counted = false
  if var buckets = view["buckets"] as? [[String: Any]] {
    var emptied: [Int] = []
    for b in buckets.indices {
      guard var items = buckets[b]["items"] as? [[String: Any]] else { continue }
      guard
        let i = items.firstIndex(where: {
          $0["id"] as? String == taskId && $0["kind"] as? String != "event"
        }),
        items[i]["done"] as? Bool != true
      else { continue }
      if leaves {
        items.remove(at: i)
      } else {
        items[i]["done"] = true
      }
      buckets[b]["items"] = items
      if let count = buckets[b]["count"] as? Int, count > 0 { buckets[b]["count"] = count - 1 }
      if leaves, items.isEmpty, (buckets[b]["more"] as? Int ?? 0) <= 0 { emptied.append(b) }
      if let key = buckets[b]["key"] as? String, kAWCountedBuckets.contains(key) {
        counted = true
      }
      changed = true
    }
    for b in emptied.reversed() { buckets.remove(at: b) }
    view["buckets"] = buckets
  }

  if counted, let open = view["openToday"] as? Int, open > 0 {
    view["openToday"] = open - 1
    label = awRespellOpenCount(label, from: open, to: open - 1, pattern: pattern)
  }

  if let next = view["next"] as? [String: Any], next["id"] as? String == taskId {
    if let moved = awNextOpen(in: view["buckets"] as? [[String: Any]] ?? [], after: taskId) {
      view["next"] = moved
    } else {
      view.removeValue(forKey: "next")
    }
    changed = true
  }
}

/// The first open task row in the app's `next` order, skipping `taskId`, as a
/// `next` object. Exact over the drawn rows: the app sinks finished rows to
/// the bottom of their bucket and trims from the bottom, so a bucket whose
/// drawn rows hold no open task hides none either.
private func awNextOpen(in buckets: [[String: Any]], after taskId: String) -> [String: Any]? {
  let keyed = buckets.compactMap { b -> (String, [String: Any])? in
    guard let key = b["key"] as? String else { return nil }
    return (key, b)
  }
  let ordered =
    kAWNextOrder.flatMap { key in keyed.filter { $0.0 == key } }
    + keyed.filter { !kAWNextOrder.contains($0.0) }
  for (key, bucket) in ordered {
    for row in bucket["items"] as? [[String: Any]] ?? [] {
      guard
        let id = row["id"] as? String, id != taskId,
        row["kind"] as? String != "event", row["done"] as? Bool != true
      else { continue }
      var next: [String: Any] = [
        "id": id, "title": row["title"] as? String ?? "", "bucket": key,
        "label": bucket["label"] as? String ?? "",
      ]
      if let time = row["time"] as? String { next["time"] = time }
      return next
    }
  }
  return nil
}
