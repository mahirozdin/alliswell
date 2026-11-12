import Foundation
import XCTest

@testable import Runner

/// The widget timeline's day choice (#50, snapshot v6 — ADR-0010 revision
/// 2026-11-12). Every WidgetKit entry draws the `days[]` element whose date is
/// the entry's own local day; past the last one it draws the stale line, never
/// an older list under a newer date. A v5 snapshot (no `days`) keeps drawing
/// its top level, as it did before.
final class WidgetDayPickTests: XCTestCase {

  private let istanbul = TimeZone(identifier: "Europe/Istanbul")!

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = istanbul
    return calendar
  }

  private func at(_ text: String) -> Date {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = istanbul
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: text)!
  }

  private func decode(_ json: String) throws -> AWSnapshot {
    try JSONDecoder().decode(AWSnapshot.self, from: Data(json.utf8))
  }

  // MARK: - Fixtures

  /// One task row titled after its day, so a test can see which day it drew.
  private func row(_ id: String, _ title: String) -> String {
    """
    {"id":"\(id)","title":"\(title)","done":false,"priority":"none","time":"09:00"}
    """
  }

  private func bucket(_ key: String, _ rows: [String]) -> String {
    """
    {"key":"\(key)","label":"\(key)","count":\(rows.count),"items":[\(rows.joined(separator: ","))]}
    """
  }

  private func day(_ date: String, dayNumber: String, open: Int) -> String {
    """
    {"date":"\(date)",
     "header":{"weekday":"W\(dayNumber)","day":"\(dayNumber)","month":"November"},
     "openToday":\(open),"openTodayLabel":"\(open) open on \(dayNumber)",
     "next":{"id":"n\(dayNumber)","title":"next \(dayNumber)","bucket":"today","label":"Today","time":"09:00"},
     "buckets":[\(bucket("today", [row("t\(dayNumber)", "task \(dayNumber)")]))],
     "views":{"p1":{"openToday":1,"openTodayLabel":"p1 on \(dayNumber)",
       "next":{"id":"p\(dayNumber)","title":"project next \(dayNumber)","bucket":"today","label":"Today"},
       "buckets":[\(bucket("today", [row("p\(dayNumber)", "project task \(dayNumber)")]))]}}}
    """
  }

  /// A v6 snapshot written on 12 November: today + 2 days, the top level
  /// equal to day 0, plus a key this build does not know yet.
  private var v6: String {
    """
    {"v":6,"generatedAt":"2026-11-12T22:30:00.000","locale":"en",
     "date":{"weekday":"W12","day":"12","month":"November"},
     "strings":{"allCaughtUp":"All caught up","openToday":"3 open on 12",
       "stale":"List is out of date · Open to refresh"},
     "openToday":3,"clockFormat":"HH:mm",
     "buckets":[\(bucket("today", [row("t12", "task 12")]))],
     "next":{"id":"n12","title":"next 12","bucket":"today","label":"Today"},
     "lists":[{"id":"all","name":"All tasks"},{"id":"p1","name":"Work","color":"#0A5CFF"}],
     "views":{"p1":{"openToday":1,"openTodayLabel":"p1 on 12",
       "buckets":[\(bucket("today", [row("p12", "project task 12")]))]}},
     "days":[\(day("2026-11-12", dayNumber: "12", open: 3)),
             \(day("2026-11-13", dayNumber: "13", open: 5)),
             \(day("2026-11-14", dayNumber: "14", open: 7))],
     "aFieldFromTheFuture":{"x":1}}
    """
  }

  /// What the app wrote before v6: no `days`, an event row, a project view.
  private let v5 = """
    {"v":5,"generatedAt":"2026-11-12T08:00:00.000","locale":"tr",
     "date":{"weekday":"Per","day":"12","month":"Kasım"},
     "strings":{"allCaughtUp":"Her şey tamam","openToday":"Bugün 2 açık","addTask":"Görev ekle"},
     "openToday":2,"clockFormat":"HH:mm","density":"compact",
     "buckets":[{"key":"today","label":"Bugün","count":3,"more":1,"items":[
       {"id":"t1","title":"Fatura","done":false,"priority":"high","time":"10:00","projectColor":"#FF0000"},
       {"id":"e1","title":"Toplantı","done":false,"priority":"none","time":"14:00","kind":"event","day":"2026-11-12"}]}],
     "next":{"id":"t1","title":"Fatura","bucket":"today","label":"Bugün","time":"10:00"},
     "lists":[{"id":"all","name":"Tüm görevler"},{"id":"p1","name":"İş","color":"#0A5CFF"}],
     "views":{"p1":{"openToday":1,"openTodayLabel":"1 açık",
       "buckets":[{"key":"today","label":"Bugün","count":1,"items":[
         {"id":"t1","title":"Fatura","done":false,"priority":"high"}]}]}}}
    """

  // MARK: - Tests

  func testEntryPicksItsOwnDay() throws {
    let snapshot = try decode(v6)

    // Before midnight: day 0.
    guard case .day(let today) = awDayView(for: at("2026-11-12 23:59"), in: snapshot, calendar: calendar)
    else { return XCTFail("23:59 on the 12th must pick a day view") }
    XCTAssertEqual(today.date, "2026-11-12")

    // A minute entry past midnight and the 00:01 midnight entry: day 1, without Dart.
    for time in ["2026-11-13 00:00", "2026-11-13 00:01", "2026-11-13 23:59"] {
      guard case .day(let view) = awDayView(for: at(time), in: snapshot, calendar: calendar)
      else { return XCTFail("\(time) must pick a day view") }
      XCTAssertEqual(view.date, "2026-11-13", time)
    }
    guard case .day(let last) = awDayView(for: at("2026-11-14 00:01"), in: snapshot, calendar: calendar)
    else { return XCTFail("the 14th is the last day the snapshot holds") }
    XCTAssertEqual(last.date, "2026-11-14")

    // The entry's whole content comes from that day: header, count and its
    // words, next, rows — never the top level (day 0).
    let whole = awEntryContent(snapshot, listId: nil, at: at("2026-11-13 00:01"), calendar: calendar)
    XCTAssertFalse(whole.stale)
    XCTAssertTrue(whole.ownHeader)
    XCTAssertNil(whole.list)
    XCTAssertEqual(whole.snapshot.date.day, "13")
    XCTAssertEqual(whole.snapshot.openToday, 5)
    XCTAssertEqual(whole.snapshot.strings?["openToday"], "5 open on 13")
    XCTAssertEqual(whole.snapshot.strings?["stale"], "List is out of date · Open to refresh")
    XCTAssertEqual(whole.snapshot.next?.id, "n13")
    XCTAssertEqual(whole.snapshot.buckets.first?.items.map(\.title), ["task 13"])
    XCTAssertNil(whole.snapshot.days, "an entry carries its own day only")

    // A widget set to a project reads that project's view of the SAME day.
    let project = awEntryContent(snapshot, listId: "p1", at: at("2026-11-13 00:01"), calendar: calendar)
    XCTAssertEqual(project.list?.name, "Work")
    XCTAssertEqual(project.snapshot.openToday, 1)
    XCTAssertEqual(project.snapshot.strings?["openToday"], "p1 on 13")
    XCTAssertEqual(project.snapshot.next?.id, "p13")
    XCTAssertEqual(project.snapshot.buckets.first?.items.map(\.title), ["project task 13"])
    XCTAssertEqual(project.snapshot.date.day, "13")

    // The day is the entry's LOCAL day: 22:30 UTC on the 12th is already the
    // 13th in Istanbul (UTC+3).
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let lateUTC = at("2026-11-13 01:30")
    XCTAssertEqual(awDayKey(for: lateUTC, calendar: calendar), "2026-11-13")
    XCTAssertEqual(awDayKey(for: lateUTC, calendar: utc), "2026-11-12")
  }

  func testBeyondHorizonIsStale() throws {
    let snapshot = try decode(v6)

    // Three days later, the app never opened: no list under today's date.
    for time in ["2026-11-15 00:00", "2026-11-15 00:01", "2026-11-20 12:00"] {
      guard case .stale = awDayView(for: at(time), in: snapshot, calendar: calendar)
      else { return XCTFail("\(time) is past the last day and must be stale") }
    }
    // A day the snapshot does not hold on the other side too (the clock moved
    // back, or the person flew west): still never another day's list.
    guard case .stale = awDayView(for: at("2026-11-11 23:59"), in: snapshot, calendar: calendar)
    else { return XCTFail("a day before the first must be stale") }

    for listId in [nil, "p1"] as [String?] {
      let content = awEntryContent(snapshot, listId: listId, at: at("2026-11-15 00:01"), calendar: calendar)
      XCTAssertTrue(content.stale)
      XCTAssertFalse(content.ownHeader, "the header comes from the entry's date")
      XCTAssertTrue(content.snapshot.buckets.isEmpty, "the list is replaced by the stale line")
      XCTAssertNil(content.snapshot.openToday, "the counter is hidden")
      XCTAssertNil(content.snapshot.next, "the lock screen's next is hidden")
      XCTAssertNil(content.snapshot.views)
      XCTAssertEqual(content.snapshot.strings?["stale"], "List is out of date · Open to refresh")
    }
    // A widget set to a project still names it while stale.
    XCTAssertEqual(
      awEntryContent(snapshot, listId: "p1", at: at("2026-11-15 00:01"), calendar: calendar).list?.name,
      "Work")
  }

  func testV5SnapshotFallsBackToTopLevel() throws {
    let snapshot = try decode(v5)
    XCTAssertNil(snapshot.days)
    // Any date: a v5 app wrote no days, so the top level is all there is.
    for time in ["2026-11-12 10:00", "2026-11-13 00:01", "2026-11-20 00:01"] {
      guard case .topLevel = awDayView(for: at(time), in: snapshot, calendar: calendar)
      else { return XCTFail("a v5 snapshot has no days and must fall back to the top level") }
    }
    let whole = awEntryContent(snapshot, listId: nil, at: at("2026-11-13 00:01"), calendar: calendar)
    XCTAssertFalse(whole.stale)
    XCTAssertFalse(whole.ownHeader)
    XCTAssertEqual(whole.snapshot.openToday, 2)
    XCTAssertEqual(whole.snapshot.buckets.first?.items.count, 2)

    let project = awEntryContent(snapshot, listId: "p1", at: at("2026-11-13 00:01"), calendar: calendar)
    XCTAssertEqual(project.list?.name, "İş")
    XCTAssertEqual(project.snapshot.openToday, 1)
    XCTAssertEqual(project.snapshot.strings?["openToday"], "1 açık")

    // An empty `days` is treated as none, never as "everything is stale".
    guard case .topLevel = awDayView(for: at("2026-11-12 10:00"), in: try decode(
      v5.replacingOccurrences(of: "\"v\":5,", with: "\"v\":6,\"days\":[],")), calendar: calendar)
    else { return XCTFail("an empty days list falls back to the top level") }
  }

  func testV5SnapshotJsonStillDecodes() throws {
    // The model moved out of the widget file unchanged: today's v5 JSON decodes
    // field for field.
    let snapshot = try decode(v5)
    XCTAssertEqual(snapshot.v, 5)
    XCTAssertEqual(snapshot.locale, "tr")
    XCTAssertEqual(snapshot.date.month, "Kasım")
    XCTAssertEqual(snapshot.clockFormat, "HH:mm")
    XCTAssertTrue(snapshot.isCompact)
    XCTAssertEqual(snapshot.next?.time, "10:00")
    XCTAssertEqual(snapshot.lists?.map(\.id), ["all", "p1"])
    XCTAssertEqual(snapshot.views?["p1"]?.openTodayLabel, "1 açık")
    let bucket = try XCTUnwrap(snapshot.buckets.first)
    XCTAssertEqual(bucket.more, 1)
    XCTAssertEqual(bucket.items.map(\.isEvent), [false, true])
    XCTAssertEqual(bucket.items[1].dayURL?.absoluteString, "alliswell://day/2026-11-12")

    // A v1-shaped snapshot (only the required fields) still decodes, and a v6
    // one carrying a key this build does not know is not refused.
    let minimal = try decode("""
      {"v":1,"generatedAt":"","locale":"en","date":{"weekday":"","day":"","month":""},"buckets":[]}
      """)
    XCTAssertNil(minimal.days)
    XCTAssertNil(minimal.openToday)
    XCTAssertEqual(try decode(v6).days?.count, 3)

    // A day view missing its optional parts decodes too; without a header the
    // entry falls back to its own date.
    let sparse = try decode(v5.replacingOccurrences(
      of: "\"v\":5,", with: "\"v\":6,\"days\":[{\"date\":\"2026-11-12\"}],"))
    let content = awEntryContent(sparse, listId: nil, at: at("2026-11-12 10:00"), calendar: calendar)
    XCTAssertFalse(content.stale)
    XCTAssertFalse(content.ownHeader)
    XCTAssertTrue(content.snapshot.buckets.isEmpty)
    XCTAssertNil(content.snapshot.openToday)
  }

  func testDoneStampReachesEveryDay() throws {
    // The widget's complete button echoes the press in the stored JSON. With
    // v6 the entries draw from `days`, so the stamp must land there too, and
    // keys this build does not know must survive (JSONSerialization).
    var json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(v6.utf8)) as? [String: Any])
    XCTAssertTrue(awMarkSnapshotDone(&json, taskId: "p13"))
    XCTAssertFalse(awMarkSnapshotDone(&json, taskId: "nope"))
    XCTAssertNotNil(json["aFieldFromTheFuture"])

    let data = try JSONSerialization.data(withJSONObject: json)
    let snapshot = try JSONDecoder().decode(AWSnapshot.self, from: data)
    let content = awEntryContent(snapshot, listId: "p1", at: at("2026-11-13 08:00"), calendar: calendar)
    XCTAssertEqual(content.snapshot.buckets.first?.items.first?.done, true)

    var json2 = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(v6.utf8)) as? [String: Any])
    XCTAssertTrue(awMarkSnapshotDone(&json2, taskId: "t14"))
    let stamped = try JSONDecoder().decode(
      AWSnapshot.self, from: JSONSerialization.data(withJSONObject: json2))
    XCTAssertEqual(stamped.days?[2].buckets?.first?.items.first?.done, true)
    XCTAssertEqual(stamped.days?[1].buckets?.first?.items.first?.done, false)
  }
}
