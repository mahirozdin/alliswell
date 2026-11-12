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

  /// `kWidgetKindEvent` in widget_snapshot.dart.
  var isEvent: Bool { kind == "event" }

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

// MARK: - The done stamp (round 15, OPH-233)

/// Flips `done` on every row with `taskId` INSIDE the stored snapshot JSON, so
/// the tapped circle fills on the very next timeline render — the honest
/// optimistic echo of the queued completion. Works on the JSONSerialization
/// tree, not the Codable model: a decode→encode round trip would silently DROP
/// any field this build does not know yet (the OPH-187 versioning stance).
///
/// The row sits in the top level, in its project's view (OPH-336) and, since
/// v6, in every day view and that day's project views (OPH-451) — the entries
/// draw from the days, so a stamp on the top level alone would never show.
/// Returns whether anything changed.
@discardableResult
func awMarkSnapshotDone(_ json: inout [String: Any], taskId: String) -> Bool {
  var changed = false
  awMarkViewDone(&json, taskId: taskId, changed: &changed)
  if var days = json["days"] as? [[String: Any]] {
    for index in days.indices {
      awMarkViewDone(&days[index], taskId: taskId, changed: &changed)
    }
    json["days"] = days
  }
  return changed
}

/// One level of the snapshot (the top level or a day): its buckets and every
/// project view under it.
private func awMarkViewDone(_ view: inout [String: Any], taskId: String, changed: inout Bool) {
  if let buckets = view["buckets"] as? [[String: Any]] {
    view["buckets"] = awMarkDone(buckets, taskId: taskId, changed: &changed)
  }
  if var views = view["views"] as? [String: Any] {
    for (key, value) in views {
      guard
        var project = value as? [String: Any],
        let buckets = project["buckets"] as? [[String: Any]]
      else { continue }
      project["buckets"] = awMarkDone(buckets, taskId: taskId, changed: &changed)
      views[key] = project
    }
    view["views"] = views
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
