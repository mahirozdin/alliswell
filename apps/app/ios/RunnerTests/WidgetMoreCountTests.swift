import Foundation
import XCTest

@testable import Runner

/// The "+N" line under a widget bucket's rows (#50, OPH-451; walkthrough Z-02).
///
/// One rule: N is the bucket's open rows that are not drawn — its count (open
/// rows only, Home's header rule) less the open rows drawn — and there is no
/// line when every open row is shown. Today's finished rows, drawn dimmed at
/// the bottom or trimmed, are never in it. The numbers are the walkthrough's:
/// "BUGÜN 7" with three rows drew "+5", "BUGÜN 3" with all three shown drew
/// "+5", "BUGÜN 11" drew "+13".
final class WidgetMoreCountTests: XCTestCase {

  private func row(_ id: String, done: Bool = false) -> AWTaskRow {
    AWTaskRow(
      id: id, title: id, done: done, priority: "none", time: nil, projectColor: nil,
      kind: nil, day: nil)
  }

  /// A today bucket as the app writes it: `open` open rows, then `done`
  /// finished ones sunk to the bottom, capped at `cap` rows with `more` the
  /// open rows past the cap.
  private func today(open: Int, done: Int, cap: Int = 12, more: Int? = nil) -> AWBucket {
    let all = (0..<open).map { row("o\($0)") } + (0..<done).map { row("d\($0)", done: true) }
    let items = Array(all.prefix(cap))
    let openTrimmed = max(0, open - items.filter { !$0.done }.count)
    return AWBucket(
      key: "today", label: "Bugün", count: open, items: items,
      more: more ?? (openTrimmed > 0 ? openTrimmed : nil))
  }

  /// The medium card of the walkthrough: 131 pt for rows, which fits three.
  private func medium(_ buckets: [AWBucket]) -> [AWBucket] {
    awFitBuckets(
      buckets, budget: 4, height: 131, titled: false,
      metrics: AWListMetrics.standard(compact: false))
  }

  func testMoreCountsOpenRowsNotDrawn() {
    // "BUGÜN 7", three rows drawn, one task already finished today: +4.
    let seven = medium([today(open: 7, done: 1)])
    XCTAssertEqual(seven.first?.items.count, 3)
    XCTAssertEqual(seven.first?.more, 4)

    // "BUGÜN 11" with five finished today: the app keeps 12 rows (11 open, one
    // done) and trims four finished ones. Drawn three: +8.
    let eleven = medium([today(open: 11, done: 5)])
    XCTAssertEqual(eleven.first?.items.count, 3)
    XCTAssertEqual(eleven.first?.more, 8)

    // A snapshot written before this fix counted the trimmed finished rows in
    // `more` (4 here); the line still says +8.
    let stale = medium([today(open: 11, done: 5, more: 4)])
    XCTAssertEqual(stale.first?.more, 8)

    // Past the app's cap: 20 open, 12 kept, 8 trimmed by the app. Drawn three: +17.
    XCTAssertEqual(awDistribute([today(open: 20, done: 0)], budget: 3).first?.more, 17)
  }

  func testNoMoreLineWhenEverythingIsShown() {
    // "BUGÜN 3" after four completions: three open rows drawn, five finished
    // rows below them that do not fit. No line.
    let three = medium([today(open: 3, done: 5)])
    XCTAssertEqual(three.first?.items.map(\.id), ["o0", "o1", "o2"])
    XCTAssertNil(three.first?.more)

    // Every row fits, a finished one drawn dimmed: no line either.
    XCTAssertNil(awDistribute([today(open: 1, done: 1)], budget: 4).first?.more)
    // Nothing open, finished rows trimmed: no line.
    XCTAssertNil(awDistribute([today(open: 0, done: 6)], budget: 2).first?.more)
    // Open rows all drawn, finished ones trimmed by the row budget: no line.
    XCTAssertNil(awDistribute([today(open: 2, done: 2)], budget: 2).first?.more)
  }

  /// The rule itself: count less the open rows drawn, no line at zero.
  func testMoreCountIsCountLessOpenRowsDrawn() {
    let drawn = [row("a"), row("b"), row("c", done: true)]
    XCTAssertEqual(awMoreCount(count: 7, drawn: drawn), 5)
    XCTAssertNil(awMoreCount(count: 2, drawn: drawn))
    XCTAssertNil(awMoreCount(count: 0, drawn: [row("d", done: true)]))
    // A count older than its rows never draws a negative line.
    XCTAssertNil(awMoreCount(count: 1, drawn: drawn))
  }

  /// A circle tapped in the widget (awMarkSnapshotDone): the tapped row is
  /// drawn done in place and the count drops by one, so N still names the
  /// open rows not drawn — the same four.
  func testMoreFollowsANativeCompletion() throws {
    let items = (0..<7).map { #"{"id":"o\#($0)","title":"o\#($0)","done":false,"priority":"none"}"# }
      + [#"{"id":"d0","title":"d0","done":true,"priority":"none"}"#]
    let text = """
      {"v":6,"generatedAt":"2026-11-12T08:00:00.000Z","locale":"tr",
       "date":{"weekday":"Perşembe","day":"12","month":"Kasım"},"openToday":7,
       "buckets":[{"key":"today","label":"Bugün","count":7,"items":[\(items.joined(separator: ","))]}]}
      """
    var json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    func shown() throws -> AWBucket? {
      let snap = try JSONDecoder().decode(
        AWSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
      return medium(snap.buckets).first
    }

    XCTAssertEqual(try shown()?.more, 4)

    // A drawn row: 6 open, two of them drawn — still +4.
    XCTAssertTrue(awMarkSnapshotDone(&json, taskId: "o0"))
    XCTAssertEqual(try shown()?.count, 6)
    XCTAssertEqual(try shown()?.more, 4)

    // Two more drawn rows: 4 open, none drawn — +4, the header's number.
    XCTAssertTrue(awMarkSnapshotDone(&json, taskId: "o1"))
    XCTAssertTrue(awMarkSnapshotDone(&json, taskId: "o2"))
    XCTAssertEqual(try shown()?.count, 4)
    XCTAssertEqual(try shown()?.more, 4)

    // The app rewrites the snapshot with the finished rows sunk: four open
    // rows, three drawn — +1; and once only three are open, none.
    let rewritten = medium([today(open: 4, done: 4)])
    XCTAssertEqual(rewritten.first?.more, 1)
    XCTAssertNil(medium([today(open: 3, done: 5)]).first?.more)
  }
}
