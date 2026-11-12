import Foundation
import XCTest

@testable import Runner

/// The widget self-fetch policy (#50, OPH-461; WIDGETS.md §3.2 "The extension's
/// turn", decision K-11): when the extension may fetch, how long it backs off,
/// when it reloads, and which view it draws. The rule that matters most: a
/// self-fetch never undoes a change made on the phone that has not synced yet.
final class WidgetFetchPolicyTests: XCTestCase {

  // MARK: - Fixtures

  private let now = Date(timeIntervalSince1970: 1_762_934_400)  // 2025-11-12 08:00 UTC
  private var nowMs: Int { Int(now.timeIntervalSince1970 * 1000) }

  private let query = "tz=Europe%2FIstanbul&workspaceIds=01JW1&mine=0&private=1&days=3"

  private func local() throws -> AWSnapshot {
    let json = """
      {"v":6,"generatedAt":"2025-11-12T08:00:00.000Z","locale":"tr",
       "date":{"weekday":"Çarşamba","day":"12","month":"Kasım"},
       "buckets":[{"key":"overdue","label":"Gecikmiş","count":0,
         "items":[{"id":"A","title":"title A","done":true,"priority":"none"}]}]}
      """
    return try JSONDecoder().decode(AWSnapshot.self, from: Data(json.utf8))
  }

  /// The server's view: task A overdue and open, B today; project p1 holds A.
  private func serverBody(aDone: Bool = false) -> [String: Any] {
    let a: [String: Any] = [
      "id": "A", "title": "title A", "done": aDone, "priority": "high",
      "dueAt": "2025-11-11T09:00:00.000Z", "timeStyle": "day",
    ]
    let b: [String: Any] = [
      "id": "B", "title": "title B", "done": false, "priority": "none",
      "dueAt": "2025-11-12T15:00:00.000Z", "timeStyle": "time",
    ]
    let overdue: [String: Any] = ["key": "overdue", "count": 1, "items": [a]]
    let today: [String: Any] = ["key": "today", "count": 1, "items": [b]]
    let next: [String: Any] = [
      "id": "A", "title": "title A", "bucket": "overdue",
      "dueAt": "2025-11-11T09:00:00.000Z", "timeStyle": "day",
    ]
    let project: [String: Any] = ["openToday": 1, "next": next, "buckets": [overdue]]
    let day0: [String: Any] = [
      "date": "2025-11-12", "openToday": 2, "next": next, "buckets": [overdue, today],
      "views": ["p1": project],
    ]
    let day1: [String: Any] = [
      "date": "2025-11-13", "openToday": 2, "next": next,
      "buckets": [["key": "overdue", "count": 2, "items": [a, b]]],
    ]
    return [
      "v": 1, "generatedAt": "2025-11-12T08:00:00.000Z", "tz": "Europe/Istanbul",
      "days": [day0, day1],
    ]
  }

  private func envelope(fetchedAtMs: Int, query: String? = nil, body: [String: Any]? = nil)
    -> AWServerEnvelope
  {
    AWServerEnvelope(
      fetchedAtMs: fetchedAtMs, etag: "\"e1\"", query: query ?? self.query,
      body: body ?? serverBody())
  }

  private func pick(
    local: AWSnapshot?, localWrittenAtMs: Int?, server: AWServerEnvelope?,
    pending: [String] = [], outbox: Int = 0
  ) -> AWSnapshotChoice {
    awPickSnapshot(
      local: local, localWrittenAtMs: localWrittenAtMs, server: server,
      query: query, pendingCompletionTaskIds: pending, pendingOutbox: outbox,
      today: "2025-11-12")
  }

  private func profileJSON(private flag: String? = "true", workspaceIds: String = #"["01JW1"]"#)
    -> String
  {
    let privateField = flag.map { #","private":\#($0)"# } ?? ""
    return """
      {"v":1,"baseUrl":"https://api.example.test",
       "scope":{"workspaceIds":\(workspaceIds)}\(privateField),
       "locale":"tr","patterns":{"time":"HH:mm","day":"d MMM","dayYear":"d MMM y",
       "relativeDays":true},"strings":{"bucket.overdue":"Gecikmiş"},
       "pendingOutbox":0,"localWrittenAtMs":1762934400000}
      """
  }

  private func profile() -> AWWidgetFetchProfile {
    AWWidgetFetchProfile.decode(profileJSON())!
  }

  private func shouldFetch(
    hasLocal: Bool = true, profile: AWWidgetFetchProfile?, tokenState: String? = "valid",
    tokenReadable: Bool = true, lastSuccessAtMs: Int? = nil, backoffUntilMs: Int? = nil
  ) -> Bool {
    awShouldFetch(
      now: now, hasLocalSnapshot: hasLocal, profile: profile, tokenState: tokenState,
      tokenReadable: tokenReadable, lastSuccessAtMs: lastSuccessAtMs,
      backoffUntilMs: backoffUntilMs)
  }

  private func row(_ id: String, in bucket: AWServerBucket?) -> AWServerItem? {
    bucket?.items.first { $0.id == id }
  }

  // MARK: - The choice (K-11)

  func testNewerLocalSnapshotWins() throws {
    let local = try local()
    let older = envelope(fetchedAtMs: nowMs - 60_000)
    XCTAssertEqual(pick(local: local, localWrittenAtMs: nowMs, server: older).localReason, .localNewer)
    // The same instant is a tie, and a tie never undoes a local change.
    let same = envelope(fetchedAtMs: nowMs)
    XCTAssertEqual(pick(local: local, localWrittenAtMs: nowMs, server: same).localReason, .localNewer)
    // A local write time the app has not recorded yet counts as newest.
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nil, server: same).localReason, .localNewer)
  }

  func testPendingWidgetCompletionKeepsTheRowDone() throws {
    // The circle completed A after the app last wrote; the server, fetched
    // later still, has A open because the app has not pulled the queue yet.
    let local = try local()
    let newer = envelope(fetchedAtMs: nowMs + 60_000)
    let choice = pick(local: local, localWrittenAtMs: nowMs, server: newer, pending: ["A"])
    XCTAssertEqual(choice.localReason, .pendingCompletion)
    XCTAssertEqual(local.buckets.first?.items.first?.done, true)

    // And wherever the server's view is drawn, the queued completion lies
    // over it as done, by awMarkSnapshotDone's rules.
    let view = try XCTUnwrap(
      awServerView(newer, pendingCompletionTaskIds: ["A"], today: "2025-11-12"))
    let today = view.days[0]
    XCTAssertEqual(row("A", in: today.buckets?.first { $0.key == "overdue" })?.done, true)
    XCTAssertEqual(today.buckets?.first { $0.key == "overdue" }?.count, 0)
    XCTAssertEqual(today.openToday, 1)
    XCTAssertEqual(today.next?.id, "B")
    XCTAssertEqual(today.next?.dueAt, "2025-11-12T15:00:00.000Z", "the moved next keeps its time")
    XCTAssertEqual(today.next?.timeStyle, "time")
    XCTAssertEqual(today.views?["p1"]?.openToday, 0)
    XCTAssertNil(today.views?["p1"]?.next)
    // A later day keeps only work finished on or after it: A leaves.
    XCTAssertNil(row("A", in: view.days[1].buckets?.first))
  }

  func testNewerServerSnapshotWinsWhenNothingIsPending() throws {
    let local = try local()
    let newer = envelope(fetchedAtMs: nowMs + 60_000)
    let server = try XCTUnwrap(pick(local: local, localWrittenAtMs: nowMs, server: newer).serverView)
    XCTAssertEqual(server.days.map(\.date), ["2025-11-12", "2025-11-13"])
    XCTAssertEqual(row("A", in: server.days[0].buckets?.first)?.done, false)
    XCTAssertEqual(server.days[0].openToday, 2)
  }

  func testOutboxNotYetSentKeepsTheLocalSnapshot() throws {
    let newer = envelope(fetchedAtMs: nowMs + 60_000)
    let choice = pick(local: try local(), localWrittenAtMs: nowMs, server: newer, outbox: 1)
    XCTAssertEqual(choice.localReason, .pendingOutbox)
  }

  func testAnUnusableServerSnapshotKeepsTheLocalOne() throws {
    let local = try local()
    let later = nowMs + 60_000
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: nil).localReason, .noServerView)
    // Fetched for another scope or privacy setting: not this profile's view.
    let other = envelope(
      fetchedAtMs: later, query: query.replacingOccurrences(of: "private=1", with: "private=0"))
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: other).localReason, .noServerView)
    // A profile that builds no query has no view of its own on the server.
    let noQuery = awPickSnapshot(
      local: local, localWrittenAtMs: nowMs, server: envelope(fetchedAtMs: later), query: nil,
      pendingCompletionTaskIds: [], pendingOutbox: 0, today: "2025-11-12")
    XCTAssertEqual(noQuery.localReason, .noServerView)
    // A body this build cannot read, or one without days.
    let broken = envelope(fetchedAtMs: later, body: ["v": 1, "days": [["openToday": 1]]])
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: broken).localReason, .noServerView)
    let empty = envelope(fetchedAtMs: later, body: ["v": 1, "days": [Any]()])
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: empty).localReason, .noServerView)
    // No local snapshot at all: the widget keeps today's behaviour.
    XCTAssertEqual(
      pick(local: nil, localWrittenAtMs: nil, server: envelope(fetchedAtMs: later)).localReason,
      .noLocalSnapshot)
  }

  func testTheEnvelopeRoundTripsThroughItsJSON() throws {
    let stored = try XCTUnwrap(envelope(fetchedAtMs: 1234).json)
    let back = try XCTUnwrap(AWServerEnvelope(json: stored))
    XCTAssertEqual(back.fetchedAtMs, 1234)
    XCTAssertEqual(back.etag, "\"e1\"")
    XCTAssertEqual(back.query, query)
    XCTAssertNotNil(awServerView(back, pendingCompletionTaskIds: [], today: nil))
    XCTAssertNil(AWServerEnvelope(json: nil))
    XCTAssertNil(AWServerEnvelope(json: #"{"etag":"x","query":"q","body":{}}"#))
  }

  // MARK: - When to fetch

  func testNoProfileMeansNoFetch() {
    XCTAssertTrue(shouldFetch(profile: profile()))
    XCTAssertFalse(shouldFetch(profile: nil))
    // "Private widget" not read yet: the profile does not decode (fail-closed).
    XCTAssertNil(AWWidgetFetchProfile.decode(profileJSON(private: nil)))
    XCTAssertNil(AWWidgetFetchProfile.decode(profileJSON(private: #""yes""#)))
    XCTAssertNil(AWWidgetFetchProfile.decode(nil))
    XCTAssertNil(AWWidgetFetchProfile.decode("not json"))
    // A scope with no workspace has nothing to ask for.
    let noScope = AWWidgetFetchProfile.decode(profileJSON(workspaceIds: "[]"))
    XCTAssertFalse(shouldFetch(profile: noScope))
    // No token, or one the server refused: no fetch until the app re-mints.
    XCTAssertFalse(shouldFetch(profile: profile(), tokenReadable: false))
    XCTAssertFalse(shouldFetch(profile: profile(), tokenState: "invalid"))
    XCTAssertTrue(shouldFetch(profile: profile(), tokenState: nil))
    // No snapshot from the app: today's behaviour, no fetch.
    XCTAssertFalse(shouldFetch(hasLocal: false, profile: profile()))
  }

  func testNoFetchWithinTwoMinutesOfTheLastSuccess() {
    XCTAssertFalse(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs - 119_999))
    XCTAssertTrue(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs - 120_000))
  }

  func testNoFetchInsideTheBackoff() {
    XCTAssertFalse(shouldFetch(profile: profile(), backoffUntilMs: nowMs + 1))
    XCTAssertTrue(shouldFetch(profile: profile(), backoffUntilMs: nowMs))
  }

  func testAStampFromAClockSetBackDoesNotBlockFetching() {
    // The device clock moved back a day: the stamps written under the old
    // clock are later than any honest stamp could be.
    XCTAssertTrue(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs + 86_400_000))
    XCTAssertTrue(shouldFetch(profile: profile(), backoffUntilMs: nowMs + 86_400_000))
    // A backoff inside its own 2 h ceiling still holds.
    XCTAssertFalse(shouldFetch(profile: profile(), backoffUntilMs: nowMs + 7_200_000))
  }

  func testBackoffDoublesAndCapsAtTwoHours() {
    XCTAssertEqual(awNextBackoff(0), 300)
    XCTAssertEqual(awNextBackoff(1), 600)
    XCTAssertEqual(awNextBackoff(2), 1200)
    XCTAssertEqual(awNextBackoff(3), 2400)
    XCTAssertEqual(awNextBackoff(4), 4800)
    XCTAssertEqual(awNextBackoff(5), 7200)
    XCTAssertEqual(awNextBackoff(64), 7200)
    XCTAssertEqual(awNextBackoff(Int.max), 7200)
    XCTAssertEqual(awNextBackoff(-1), 300)
  }

  // MARK: - When to reload

  func testReloadDateIsCappedAtThirtyMinutesPlusJitter() {
    let far = now.addingTimeInterval(4 * 3600)
    XCTAssertEqual(awReloadDate(now: now, clockHorizon: far, jitter: 0), now.addingTimeInterval(1800))
    XCTAssertEqual(
      awReloadDate(now: now, clockHorizon: far, jitter: 120), now.addingTimeInterval(1920))
    // The jitter is 0–5 minutes, whatever the caller passes.
    XCTAssertEqual(
      awReloadDate(now: now, clockHorizon: far, jitter: 900), now.addingTimeInterval(2100))
    XCTAssertEqual(
      awReloadDate(now: now, clockHorizon: far, jitter: -60), now.addingTimeInterval(1800))
    // A clock horizon sooner than that is kept: the minute entries run out first.
    let near = now.addingTimeInterval(15 * 60)
    XCTAssertEqual(awReloadDate(now: now, clockHorizon: near, jitter: 300), near)
    for _ in 0..<50 {
      XCTAssertTrue((0...300).contains(awReloadJitter()))
    }
  }

  func testMidnightReloadIsOneMinutePastMidnightPlusJitter() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    // 2025-11-12 11:00 in Istanbul → 2025-11-13 00:01 Istanbul = 2025-11-12 21:01 UTC.
    let oneOOne = Date(timeIntervalSince1970: 1_762_981_260)
    XCTAssertEqual(awMidnightReloadDate(after: now, calendar: calendar, jitter: 0), oneOOne)
    XCTAssertEqual(
      awMidnightReloadDate(after: now, calendar: calendar, jitter: 200),
      oneOOne.addingTimeInterval(200))
    XCTAssertEqual(
      awMidnightReloadDate(after: now, calendar: calendar, jitter: 1000),
      oneOOne.addingTimeInterval(300))
  }

  // MARK: - The query

  func testTheQueryFollowsTheProfile() throws {
    XCTAssertEqual(awSnapshotQuery(profile: profile(), timeZone: "Europe/Istanbul"), query)
    let mine = try XCTUnwrap(
      AWWidgetFetchProfile.decode(
        profileJSON(private: "false", workspaceIds: #"["01JW1","01JW2"],"mineFor":"01HU""#)))
    XCTAssertEqual(
      awSnapshotQuery(profile: mine, timeZone: "America/Argentina/Buenos_Aires"),
      "tz=America%2FArgentina%2FBuenos_Aires&workspaceIds=01JW1,01JW2&mine=1&private=0&days=3")
  }
}
