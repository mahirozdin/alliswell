import Foundation

// Which day a widget timeline entry draws (OPH-451, #50, snapshot v6).
//
// The app writes today and the next days as full views (`days`), so an entry
// past midnight draws the new day's list without Dart running. Native code only
// PICKS a day — it never re-buckets (DESIGN §8 W1/W9): the rows, the count and
// its words, the next task and every project view are the app's.
//
// Pure and Foundation-only: compiled into the widget extension, the macOS
// widget and Runner, so RunnerTests (WidgetDayPickTests) can drive it.

/// What one entry draws.
enum AWDayPick {
  /// The snapshot holds the entry's own local day.
  case day(AWDayView)
  /// It holds days, but not this one — past the last (the app has not run for
  /// days) or, after a clock or zone change, before the first. The widget says
  /// the list is out of date; it never draws another day's list under this date.
  case stale
  /// A v5 snapshot (no `days`): the top level, as before v6.
  case topLevel
}

/// The entry's local day as the app spells it (`yyyy-MM-dd`, Gregorian), in
/// `calendar`'s time zone — whatever calendar the person reads in.
func awDayKey(for date: Date, calendar: Calendar) -> String {
  var gregorian = Calendar(identifier: .gregorian)
  gregorian.timeZone = calendar.timeZone
  let parts = gregorian.dateComponents([.year, .month, .day], from: date)
  return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

/// The day view `date` draws from `snapshot`.
func awDayView(for date: Date, in snapshot: AWSnapshot, calendar: Calendar) -> AWDayPick {
  guard let days = snapshot.days, !days.isEmpty else { return .topLevel }
  let key = awDayKey(for: date, calendar: calendar)
  guard let view = days.first(where: { $0.date == key }) else { return .stale }
  return .day(view)
}

/// Everything one timeline entry renders: the snapshot it draws (one day,
/// already narrowed to the widget's list), the list it is set to, and how its
/// header is dated.
struct AWEntryContent {
  let snapshot: AWSnapshot
  let list: AWListInfo?
  /// The list is replaced by `strings.stale`; the counter and next are hidden.
  let stale: Bool
  /// The header is the day view's own (the app's words for that day). False
  /// means the header is derived from the entry's date, which is always true.
  let ownHeader: Bool
}

/// What a widget set to `listId` draws at `date`.
func awEntryContent(
  _ snapshot: AWSnapshot, listId: String?, at date: Date, calendar: Calendar
) -> AWEntryContent {
  switch awDayView(for: date, in: snapshot, calendar: calendar) {
  case .topLevel:
    let picked = snapshot.selecting(listId)
    return AWEntryContent(
      snapshot: picked.snapshot, list: picked.list, stale: false, ownHeader: false)
  case .day(let view):
    let picked = snapshot.forDay(view).selecting(listId)
    return AWEntryContent(
      snapshot: picked.snapshot, list: picked.list, stale: false,
      ownHeader: view.header != nil)
  case .stale:
    return AWEntryContent(
      snapshot: snapshot.staleDay(), list: snapshot.selecting(listId).list, stale: true,
      ownHeader: false)
  }
}

extension AWSnapshot {
  /// The snapshot with its top level replaced by `view`: the shape every view
  /// already draws, so the views and `selecting` need no v6 branch. The other
  /// days are dropped — an entry carries its own day only, which is also what
  /// the archive budget counts (kAWArchiveBudgetBytes).
  func forDay(_ view: AWDayView) -> AWSnapshot {
    var words = strings ?? [:]
    // The top level spells day 0's count; another day speaks its own.
    words["openToday"] = view.openTodayLabel
    return AWSnapshot(
      v: v, generatedAt: generatedAt, locale: locale, date: view.header ?? date,
      strings: words, openToday: view.openToday, clockFormat: clockFormat,
      buckets: view.buckets ?? [], next: view.next, lists: lists, views: view.views,
      density: density, days: nil)
  }

  /// A day past the horizon: no rows, no count, no next — nothing the app did
  /// not compute for that day.
  func staleDay() -> AWSnapshot {
    AWSnapshot(
      v: v, generatedAt: generatedAt, locale: locale, date: date, strings: strings,
      openToday: nil, clockFormat: clockFormat, buckets: [], next: nil, lists: lists,
      views: nil, density: density, days: nil)
  }
}

// MARK: - Rows that fit (OPH-451, IOS-09)

/// The "+N" under a bucket's drawn rows (Z-02): its open rows that are not
/// drawn. `count` is the bucket's open rows (Home's header rule, OPH-394), so
/// this is `count` less the open rows in `drawn`; nil — no line — when every
/// open row is shown. Today's finished rows, drawn dimmed or trimmed, are in
/// neither number. Read from `count`, not the app's `more` plus the rows
/// trimmed here: `more` once counted trimmed finished rows too (the widget
/// drew "+13" for eight hidden tasks), and a circle tapped here lowers
/// `count` and marks its drawn row done in the same write
/// (awMarkSnapshotDone), so N keeps following the rule after it. The app's
/// `more` says the same of the rows it keeps (widget_core_test.dart pins it).
func awMoreCount(count: Int, drawn: [AWTaskRow]) -> Int? {
  let hidden = count - drawn.filter { !$0.done }.count
  return hidden > 0 ? hidden : nil
}

/// Greedily trims buckets so the drawn rows fit the size's row budget; each
/// bucket's "+N" is awMoreCount of the rows it draws.
func awDistribute(_ buckets: [AWBucket], budget: Int) -> [AWBucket] {
  var remaining = budget
  var out: [AWBucket] = []
  for b in buckets {
    if remaining <= 0 { break }
    let take = min(b.items.count, remaining)
    let trimmed = Array(b.items.prefix(take))
    out.append(
      AWBucket(
        key: b.key, label: b.label, count: b.count, items: trimmed,
        more: awMoreCount(count: b.count, drawn: trimmed)))
    remaining -= take
  }
  return out
}

/// The heights the list is laid out with, in points — what
/// `AllisWellWidgetEntryView` draws: a 28 pt row (the circle's frame), a
/// bucket label or "+N" line, the gap between a bucket's lines and the gap
/// between the list's parts (the list title, each bucket).
struct AWListMetrics {
  var row: Double = 28
  var line: Double = 14
  var title: Double = 16
  var rowGap: Double = 4
  var partGap: Double = 8

  static func standard(compact: Bool) -> AWListMetrics {
    AWListMetrics(rowGap: compact ? 1 : 4, partGap: compact ? 4 : 8)
  }
}

/// How tall `buckets` draw, with the list's title line when `titled`.
func awListHeight(_ buckets: [AWBucket], titled: Bool, metrics m: AWListMetrics) -> Double {
  var parts: [Double] = titled ? [m.title] : []
  for b in buckets {
    var lines = [m.line] + Array(repeating: m.row, count: b.items.count)
    if let more = b.more, more > 0 { lines.append(m.line) }
    parts.append(lines.reduce(0, +) + m.rowGap * Double(lines.count - 1))
  }
  guard !parts.isEmpty else { return 0 }
  return parts.reduce(0, +) + m.partGap * Double(parts.count - 1)
}

/// The rows a list of `height` points draws: at most `budget`, and only as
/// many as fit WHOLE — a row cut by the widget's edge reads as a glitch, and
/// the "+N" says what was left out. Nil `height` is the budget alone.
func awFitBuckets(
  _ buckets: [AWBucket], budget: Int, height: Double?, titled: Bool, metrics: AWListMetrics
) -> [AWBucket] {
  guard let height else { return awDistribute(buckets, budget: budget) }
  var rows = max(budget, 0)
  while rows > 1 {
    let fitted = awDistribute(buckets, budget: rows)
    if awListHeight(fitted, titled: titled, metrics: metrics) <= height { return fitted }
    rows -= 1
  }
  // One row is the floor: a list that says nothing is worse than a tight one.
  return awDistribute(buckets, budget: min(rows, budget))
}
