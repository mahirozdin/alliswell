import Foundation
import XCTest

@testable import Runner

/// A completion from the widget's circle (#50, OPH-451; walkthrough IOS-08,
/// IOS-09, IOS-10, IOS-11). The circle writes the stored snapshot so the next
/// render shows it before the app runs: every place the task is drawn — the top
/// level, every day view, every project view — by the rules the app wrote it
/// with (widget_snapshot.dart): done in today's view, gone from a later day's,
/// one fewer in its bucket and in the open count, and the lock screen's next
/// moved on.
final class WidgetCompletionTests: XCTestCase {

  // MARK: - Fixture

  private func row(_ id: String, done: Bool = false, time: String = "09:00", kind: String? = nil)
    -> String
  {
    let kindField = kind.map { #","kind":"\#($0)""# } ?? ""
    return """
      {"id":"\(id)","title":"title \(id)","done":\(done),"priority":"none","time":"\(time)"\(kindField)}
      """
  }

  private func bucket(_ key: String, _ label: String, count: Int, _ rows: [String], more: Int = 0)
    -> String
  {
    let moreField = more > 0 ? #","more":\#(more)"# : ""
    return """
      {"key":"\(key)","label":"\(label)","count":\(count),"items":[\(rows.joined(separator: ","))]\(moreField)}
      """
  }

  /// Today: task A overdue (the next task), B and an event today, C this week,
  /// D finished today. Tomorrow and the day after: A, B are overdue. Project
  /// p1 holds A and C.
  private func todayBuckets() -> String {
    [
      bucket("overdue", "Gecikmiş", count: 1, [row("A", time: "11:17")]),
      bucket(
        "today", "Bugün", count: 2,
        [row("E", time: "10:00", kind: "event"), row("B", time: "11:20"), row("D", done: true)]),
      bucket("thisWeek", "Bu hafta", count: 1, [row("C", time: "Cum")]),
    ].joined(separator: ",")
  }

  private func laterBuckets() -> String {
    [
      bucket("overdue", "Gecikmiş", count: 2, [row("A"), row("B")]),
      bucket("thisWeek", "Bu hafta", count: 1, [row("C")]),
    ].joined(separator: ",")
  }

  private func project(open: Int) -> String {
    """
    {"p1":{"openToday":\(open),"openTodayLabel":"\(open) açık",
      "next":{"id":"A","title":"title A","bucket":"overdue","label":"Gecikmiş","time":"11:17"},
      "buckets":[\(bucket("overdue", "Gecikmiş", count: 1, [row("A")])),
                 \(bucket("thisWeek", "Bu hafta", count: 1, [row("C")]))]}}
    """
  }

  private func day(_ date: String, buckets: String, open: Int) -> String {
    """
    {"date":"\(date)","header":{"weekday":"W","day":"\(date.suffix(2))","month":"Kasım"},
     "openToday":\(open),"openTodayLabel":"\(open) açık",
     "next":{"id":"A","title":"title A","bucket":"overdue","label":"Gecikmiş","time":"11:17"},
     "buckets":[\(buckets)],"views":\(project(open: 1))}
    """
  }

  private func snapshot(pattern: Bool = true) -> [String: Any] {
    let patternField = pattern ? #","openTodayPattern":"{count} açık""# : ""
    let text = """
      {"v":6,"generatedAt":"2026-11-12T08:00:00.000Z","locale":"tr",
       "date":{"weekday":"Perşembe","day":"12","month":"Kasım"},
       "strings":{"allCaughtUp":"Her şey tamam","openToday":"Bugün 3 açık",
         "completeTask":"Tamamla: {title}"\(patternField)},
       "openToday":3,
       "next":{"id":"A","title":"title A","bucket":"overdue","label":"Gecikmiş","time":"11:17"},
       "buckets":[\(todayBuckets())],"views":\(project(open: 1)),
       "days":[\(day("2026-11-12", buckets: todayBuckets(), open: 3)),
               \(day("2026-11-13", buckets: laterBuckets(), open: 2)),
               \(day("2026-11-14", buckets: laterBuckets(), open: 2))],
       "aFieldFromTheFuture":{"x":1}}
      """
    return try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
  }

  // MARK: - Reading the tree

  private func days(_ json: [String: Any]) -> [[String: Any]] {
    json["days"] as! [[String: Any]]
  }

  private func buckets(_ level: [String: Any]) -> [[String: Any]] {
    level["buckets"] as! [[String: Any]]
  }

  private func project(_ level: [String: Any]) -> [String: Any] {
    (level["views"] as! [String: Any])["p1"] as! [String: Any]
  }

  /// `done` of the row `id` wherever it is in `level`, nil when it is not drawn.
  private func done(_ id: String, in level: [String: Any]) -> Bool? {
    for b in buckets(level) {
      for item in b["items"] as! [[String: Any]] where item["id"] as? String == id {
        return item["done"] as? Bool
      }
    }
    return nil
  }

  private func count(_ key: String, in level: [String: Any]) -> Int? {
    buckets(level).first { $0["key"] as? String == key }?["count"] as? Int
  }

  private func decode(_ json: [String: Any]) throws -> AWSnapshot {
    try JSONDecoder().decode(
      AWSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
  }

  // MARK: - Tests

  func testCompletionMarksEveryDayView() throws {
    var json = snapshot()
    XCTAssertTrue(awMarkSnapshotDone(&json, taskId: "A", today: "2026-11-12"))

    // Today — the top level, day 0 and their project view: a done row, as the
    // app draws today's finished work.
    XCTAssertEqual(done("A", in: json), true)
    XCTAssertEqual(done("A", in: days(json)[0]), true)
    XCTAssertEqual(done("A", in: project(json)), true)
    XCTAssertEqual(done("A", in: project(days(json)[0])), true)

    // A later day keeps no task finished before it: the row leaves, in the day
    // and in its project view.
    for later in days(json).dropFirst() {
      XCTAssertNil(done("A", in: later))
      XCTAssertNil(done("A", in: project(later)))
      XCTAssertEqual(done("B", in: later), false, "only the tapped task moves")
    }

    // What the entries draw: today's entry and tomorrow's, decoded as the
    // widget decodes them. The unknown field survives the rewrite.
    XCTAssertNotNil(json["aFieldFromTheFuture"])
    let decoded = try decode(json)
    guard let today = decoded.days?.first, let tomorrow = decoded.days?[1] else {
      return XCTFail("the days must survive")
    }
    let todayRows = decoded.forDay(today).buckets.flatMap(\.items)
    XCTAssertEqual(todayRows.first { $0.id == "A" }?.done, true)
    let tomorrowRows = decoded.forDay(tomorrow).buckets.flatMap(\.items)
    XCTAssertFalse(tomorrowRows.contains { $0.id == "A" })

    // Again: nothing left to change.
    XCTAssertFalse(awMarkSnapshotDone(&json, taskId: "A", today: "2026-11-12"))
    // A task the snapshot does not hold changes nothing.
    var untouched = snapshot()
    XCTAssertFalse(awMarkSnapshotDone(&untouched, taskId: "nope", today: "2026-11-12"))
  }

  func testCompletionDecrementsCount() throws {
    var json = snapshot()
    awMarkSnapshotDone(&json, taskId: "A", today: "2026-11-12")

    // The open count and its words, from the app's phrase, at every level.
    XCTAssertEqual(json["openToday"] as? Int, 2)
    XCTAssertEqual((json["strings"] as? [String: Any])?["openToday"] as? String, "2 açık")
    XCTAssertEqual(days(json)[0]["openToday"] as? Int, 2)
    XCTAssertEqual(days(json)[0]["openTodayLabel"] as? String, "2 açık")
    XCTAssertEqual(days(json)[1]["openToday"] as? Int, 1)
    XCTAssertEqual(project(json)["openToday"] as? Int, 0)
    XCTAssertEqual(project(json)["openTodayLabel"] as? String, "0 açık")
    XCTAssertEqual(
      try decode(json).selecting("p1").snapshot.openToday, 0, "zero: the badge hides")

    // The bucket's number: open rows only (the medium widget's "BUGÜN 8").
    XCTAssertEqual(count("overdue", in: json), 0)
    XCTAssertEqual(count("overdue", in: days(json)[1]), 1)
    XCTAssertEqual(count("today", in: json), 2)

    // Twice is once: a queued completion is applied on every read.
    awMarkSnapshotDone(&json, taskId: "A", today: "2026-11-12")
    XCTAssertEqual(json["openToday"] as? Int, 2)
    XCTAssertEqual(count("today", in: days(json)[0]), 2)

    // Today's task counts; next week's does not — but its bucket does.
    awMarkSnapshotDone(&json, taskId: "B", today: "2026-11-12")
    XCTAssertEqual(json["openToday"] as? Int, 1)
    XCTAssertEqual(count("today", in: json), 1)
    awMarkSnapshotDone(&json, taskId: "C", today: "2026-11-12")
    XCTAssertEqual(json["openToday"] as? Int, 1)
    XCTAssertEqual(count("thisWeek", in: json), 0)
    // A later day's bucket left with no row is gone, as the app drops it.
    XCTAssertFalse(buckets(days(json)[1]).contains { $0["key"] as? String == "thisWeek" })

    // A snapshot from an app without the phrase: the old words, new number.
    var old = snapshot(pattern: false)
    awMarkSnapshotDone(&old, taskId: "A", today: "2026-11-12")
    XCTAssertEqual((old["strings"] as? [String: Any])?["openToday"] as? String, "Bugün 2 açık")
  }

  func testNextMovesOn() throws {
    var json = snapshot()
    awMarkSnapshotDone(&json, taskId: "A", today: "2026-11-12")

    // Today: the event and the finished row are never next; B is, with its
    // bucket's words and its time.
    let next = json["next"] as? [String: Any]
    XCTAssertEqual(next?["id"] as? String, "B")
    XCTAssertEqual(next?["bucket"] as? String, "today")
    XCTAssertEqual(next?["label"] as? String, "Bugün")
    XCTAssertEqual(next?["time"] as? String, "11:20")
    XCTAssertEqual((days(json)[0]["next"] as? [String: Any])?["id"] as? String, "B")
    XCTAssertEqual((days(json)[1]["next"] as? [String: Any])?["id"] as? String, "B")
    // The project's next: C, from this week.
    XCTAssertEqual((project(json)["next"] as? [String: Any])?["id"] as? String, "C")
    XCTAssertEqual(try decode(json).next?.id, "B")

    // Nothing open left: no next, so the lock screen says all caught up.
    for id in ["B", "C"] { awMarkSnapshotDone(&json, taskId: id, today: "2026-11-12") }
    XCTAssertNil(json["next"])
    XCTAssertNil(project(json)["next"])
    XCTAssertNil(try decode(json).next)

    // Completing a task that is not next leaves next alone.
    var other = snapshot()
    awMarkSnapshotDone(&other, taskId: "C", today: "2026-11-12")
    XCTAssertEqual((other["next"] as? [String: Any])?["id"] as? String, "A")
  }

  /// IOS-08: the app rewrites the snapshot from its own data, which has the
  /// task open until it pulls the queue. Reading through the queue keeps the
  /// tapped row done.
  func testQueuedCompletionSurvivesARewrite() throws {
    var rewritten = snapshot()
    XCTAssertTrue(
      awApplyPendingCompletions(&rewritten, taskIds: ["A"], today: "2026-11-12"))
    XCTAssertEqual(done("A", in: days(rewritten)[0]), true)
    XCTAssertEqual(rewritten["openToday"] as? Int, 2)

    // Once the app has written the task done itself, the queue changes nothing.
    XCTAssertFalse(
      awApplyPendingCompletions(&rewritten, taskIds: ["A"], today: "2026-11-12"))
  }

  /// IOS-11: VoiceOver read the circle as "Circle".
  func testCircleIsSpokenWithItsTitle() {
    XCTAssertEqual(
      awCompleteLabel(title: "KDV beyannamesi", strings: ["completeTask": "Tamamla: {title}"]),
      "Tamamla: KDV beyannamesi")
    XCTAssertEqual(awCompleteLabel(title: "Fatura", strings: nil), "Fatura")
  }

  /// IOS-09: the medium widget drew a fourth row half outside the card.
  func testMediumDrawsOnlyWholeRows() {
    let rows = (1...8).map {
      AWTaskRow(
        id: "t\($0)", title: "t\($0)", done: false, priority: "none", time: nil,
        projectColor: nil, kind: nil, day: nil)
    }
    let today = AWBucket(key: "today", label: "Bugün", count: 8, items: rows, more: nil)
    let metrics = AWListMetrics.standard(compact: false)

    // A 163 pt medium card less the system's 16 pt margins: 131 pt.
    let fitted = awFitBuckets([today], budget: 4, height: 131, titled: false, metrics: metrics)
    XCTAssertEqual(fitted.first?.items.count, 3)
    XCTAssertEqual(fitted.first?.more, 5, "+N names every row not drawn")
    XCTAssertLessThanOrEqual(awListHeight(fitted, titled: false, metrics: metrics), 131)
    // The fourth row would not fit whole.
    let four = awDistribute([today], budget: 4)
    XCTAssertGreaterThan(awListHeight(four, titled: false, metrics: metrics), 131)

    // Two buckets pay for two labels.
    let overdue = AWBucket(
      key: "overdue", label: "Gecikmiş", count: 1, items: [rows[0]], more: nil)
    let two = awFitBuckets([overdue, today], budget: 4, height: 131, titled: false, metrics: metrics)
    XCTAssertLessThanOrEqual(awListHeight(two, titled: false, metrics: metrics), 131)
    XCTAssertEqual(two.map(\.items.count), [1, 1])

    // Rows the app trimmed already stay in the +N.
    let trimmed = AWBucket(key: "today", label: "Bugün", count: 20, items: rows, more: 12)
    XCTAssertEqual(awDistribute([trimmed], budget: 3).first?.more, 17)
    // A finished row is not in the count, and not in +N either (Z-02): the
    // one open row is drawn, so there is no line.
    let finished = AWTaskRow(
      id: "done", title: "done", done: true, priority: "none", time: nil,
      projectColor: nil, kind: nil, day: nil)
    let withDone = AWBucket(key: "today", label: "Bugün", count: 1, items: [rows[0], finished], more: nil)
    XCTAssertNil(awDistribute([withDone], budget: 1).first?.more)

    // No height (a size with a measured budget): the budget alone.
    XCTAssertEqual(
      awFitBuckets([today], budget: 4, height: nil, titled: false, metrics: metrics)
        .first?.items.count, 4)
  }
}
