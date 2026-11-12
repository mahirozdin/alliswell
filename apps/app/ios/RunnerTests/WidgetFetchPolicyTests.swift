import Foundation
import Security
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
    // before the tap, has A open because the app has not pulled the queue
    // yet. The queued completion does not change which view is drawn
    // (#50, PR2-03): it lies over that view as done.
    let local = try local()
    XCTAssertEqual(local.buckets.first?.items.first?.done, true)
    let newer = envelope(fetchedAtMs: nowMs + 60_000)
    let choice = pick(local: local, localWrittenAtMs: nowMs, server: newer, pending: ["A"])
    let drawn = try XCTUnwrap(choice.serverView, "the view drawn before the tap")
    XCTAssertEqual(row("A", in: drawn.days[0].buckets?.first { $0.key == "overdue" })?.done, true)
    // The app's snapshot drawn before the tap stays drawn, A done in it.
    let older = envelope(fetchedAtMs: nowMs - 60_000)
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: older, pending: ["A"]).localReason,
      .localNewer)
    XCTAssertEqual(
      pick(local: local, localWrittenAtMs: nowMs, server: newer, pending: ["A"], outbox: 1)
        .localReason, .pendingOutbox)

    // Wherever the server's view is drawn, the queued completion lies over
    // it as done, by awMarkSnapshotDone's rules.
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

  /// #50, PR2-09: one request per refresh interval while a server view is
  /// stored — a second widget, or a reload after the app wrote, draws it.
  func testNoFetchWithinTheRefreshIntervalOfTheLastSuccess() {
    XCTAssertEqual(kAWFetchMinInterval, kAWReloadInterval)
    XCTAssertFalse(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs - 5_000))
    XCTAssertFalse(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs - 1_799_999))
    XCTAssertTrue(shouldFetch(profile: profile(), lastSuccessAtMs: nowMs - 1_800_000))
    // No view for this query yet (none stored, or the profile changed and
    // the app removed it): the turn fetches, however recent the stamp.
    XCTAssertTrue(
      awShouldFetch(
        now: now, hasLocalSnapshot: true, profile: profile(), tokenState: "valid",
        tokenReadable: true, lastSuccessAtMs: nowMs - 5_000, backoffUntilMs: nil,
        hasServerView: false))
  }

  /// #50, PR2-03/05: no request while a completion from the circle is
  /// queued, nor within 90 s of the circle's last press, so the reload after
  /// a tap answers at once and the view does not change under the finger.
  func testNoFetchWhileCompletionOrSoonAfterAnIntent() {
    func fetches(pending: Bool = false, completedAtMs: Int? = nil, view: Bool = false) -> Bool {
      awShouldFetch(
        now: now, hasLocalSnapshot: true, profile: profile(), tokenState: "valid",
        tokenReadable: true, lastSuccessAtMs: nil, backoffUntilMs: nil,
        hasServerView: view, pendingCompletion: pending, completedAtMs: completedAtMs)
    }
    XCTAssertTrue(fetches())
    XCTAssertFalse(fetches(pending: true))
    XCTAssertFalse(fetches(pending: true, completedAtMs: nowMs - 86_400_000))
    XCTAssertFalse(fetches(completedAtMs: nowMs))
    XCTAssertFalse(fetches(completedAtMs: nowMs - 89_999))
    XCTAssertTrue(fetches(completedAtMs: nowMs - 90_000))
    // A clock moved back a little still waits; a stamp a day ahead of any
    // honest one does not block.
    XCTAssertFalse(fetches(completedAtMs: nowMs + 1_000))
    XCTAssertTrue(fetches(completedAtMs: nowMs + 86_400_000))
  }

  /// #50: no request while another turn's request is out — its claim is
  /// younger than the claim's TTL — and a claim a killed turn left behind,
  /// or one from a clock set back, does not block for longer.
  func testNoFetchWhileAnotherTurnsRequestIsOut() {
    func fetches(claim: Int?) -> Bool {
      awShouldFetch(
        now: now, hasLocalSnapshot: true, profile: profile(), tokenState: "valid",
        tokenReadable: true, lastSuccessAtMs: nil, backoffUntilMs: nil,
        hasServerView: false, fetchClaimMs: claim)
    }
    XCTAssertGreaterThan(kAWFetchClaimTTL, AWWidgetFetcher.sessionConfiguration().timeoutIntervalForResource)
    XCTAssertTrue(fetches(claim: nil))
    XCTAssertFalse(fetches(claim: nowMs))
    XCTAssertFalse(fetches(claim: nowMs - 14_999))
    XCTAssertTrue(fetches(claim: nowMs - 15_000))
    XCTAssertFalse(fetches(claim: nowMs + 1_000))
    XCTAssertTrue(fetches(claim: nowMs + 86_400_000))
  }

  /// #50, PR2-09: only a 200 that stored another view reloads the other widgets.
  func testOnlyANewViewReloadsTheOtherWidgets() {
    let e1 = envelope(fetchedAtMs: nowMs)
    let e2 = AWServerEnvelope(fetchedAtMs: nowMs, etag: "\"e2\"", query: query, body: serverBody())
    let otherQuery = AWServerEnvelope(
      fetchedAtMs: nowMs, etag: "\"e1\"", query: "q2", body: serverBody())
    XCTAssertTrue(awFetchChangedTheView(.stored, before: nil, after: e1))
    XCTAssertTrue(awFetchChangedTheView(.stored, before: e1, after: e2))
    XCTAssertTrue(awFetchChangedTheView(.stored, before: e1, after: otherQuery))
    XCTAssertFalse(awFetchChangedTheView(.stored, before: e1, after: e1))
    XCTAssertFalse(awFetchChangedTheView(.stored, before: e1, after: nil))
    for outcome in [AWWidgetFetchOutcome.skipped, .notModified, .unauthorized, .failed, .discarded] {
      XCTAssertFalse(awFetchChangedTheView(outcome, before: nil, after: e2))
    }
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

/// The widget's self-fetch (#50, OPH-462; WIDGETS.md §3.2 steps 2–5): the one
/// request through an injected URLProtocol, the App Group stamps it leaves, and
/// what the widget draws after it.
final class WidgetFetcherTests: XCTestCase {

  private let start = Date(timeIntervalSince1970: 1_762_934_400)  // 2025-11-12 08:00 UTC
  private var startMs: Int { Int(start.timeIntervalSince1970 * 1000) }
  private let zone = "Europe/Istanbul"
  private var suite = ""
  private var defaults: UserDefaults!
  private var hooked: AWHookedDefaults { defaults as! AWHookedDefaults }
  private var clock = Date()
  private var token: String? = "aww_test"

  private let localJSON = """
    {"v":6,"generatedAt":"2025-11-12T07:50:00.000Z","locale":"tr",
     "date":{"weekday":"Çarşamba","day":"12","month":"Kasım"},
     "strings":{"openToday":"1 açık","openTodayPattern":"{count} açık"},
     "buckets":[{"key":"today","label":"Bugün","count":1,
       "items":[{"id":"L","title":"local row","done":false,"priority":"none"}]}]}
    """

  override func setUp() {
    super.setUp()
    suite = "aw.fetcher.tests.\(UUID().uuidString)"
    defaults = AWHookedDefaults(suiteName: suite)
    clock = start
    token = "aww_test"
    AWStubProtocol.reset()
    defaults.set(localJSON, forKey: kAWLocalSnapshotKey)
    defaults.set(profileJSON(localWrittenAtMs: startMs - 600_000), forKey: kAWFetchProfileKey)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    AWStubProtocol.reset()
    super.tearDown()
  }

  private func profileJSON(localWrittenAtMs: Int, outbox: Int = 0, isPrivate: Bool = true)
    -> String
  {
    """
    {"v":1,"baseUrl":"https://api.example.test/","scope":{"workspaceIds":["01JW1"]},
     "private":\(isPrivate),"locale":"tr",
     "patterns":{"time":"HH:mm","day":"d MMM","dayYear":"d MMM y","relativeDays":true},
     "strings":{"bucket.overdue":"Gecikmiş","bucket.today":"Bugün","privateTitle":"Gizli görev",
       "privateEvent":"Gizli etkinlik","allDay":"Tüm gün","today":"Bugün","tomorrow":"Yarın",
       "yesterday":"Dün"},
     "pendingOutbox":\(outbox),"localWrittenAtMs":\(localWrittenAtMs)}
    """
  }

  private func fetcher() -> AWWidgetFetcher {
    let configuration = AWWidgetFetcher.sessionConfiguration()
    configuration.protocolClasses = [AWStubProtocol.self]
    return AWWidgetFetcher(
      defaults: defaults, session: URLSession(configuration: configuration),
      readToken: { [unowned self] in self.token }, now: { [unowned self] in self.clock },
      timeZone: zone)
  }

  /// A private (no titles) server view: an overdue task, a timed task and a
  /// timed event today, a task due tomorrow evening.
  private func serverBody() -> [String: Any] {
    let overdue: [String: Any] = [
      "id": "A", "done": false, "priority": "high", "dueAt": "2025-11-11T09:00:00.000Z",
      "timeStyle": "day", "projectColor": "#2563EB",
    ]
    let timed: [String: Any] = [
      "id": "B", "done": false, "priority": "none", "dueAt": "2025-11-12T15:00:00.000Z",
      "timeStyle": "time",
    ]
    let event: [String: Any] = [
      "id": "E", "done": false, "priority": "none", "kind": "event", "day": "2025-11-12",
      "dueAt": "2025-11-12T11:00:00.000Z", "endAt": "2025-11-12T12:30:00.000Z", "allDay": false,
      "timeStyle": "range",
    ]
    let tomorrow: [String: Any] = [
      "id": "C", "done": false, "priority": "none", "dueAt": "2025-11-13T17:00:00.000Z",
      "timeStyle": "dayTime",
    ]
    let next: [String: Any] = [
      "id": "A", "bucket": "overdue", "dueAt": "2025-11-11T09:00:00.000Z", "timeStyle": "day",
    ]
    let day0: [String: Any] = [
      "date": "2025-11-12", "openToday": 2, "next": next,
      "buckets": [
        ["key": "overdue", "count": 1, "items": [overdue]],
        ["key": "today", "count": 2, "items": [timed, event, tomorrow]],
      ],
      "views": ["p1": ["openToday": 1, "next": next, "buckets": [["key": "overdue", "count": 1, "items": [overdue]]]]],
    ]
    let day1: [String: Any] = [
      "date": "2025-11-13", "openToday": 1, "buckets": [["key": "today", "count": 1, "items": [tomorrow]]],
    ]
    return ["v": 1, "generatedAt": "2025-11-12T08:00:00.000Z", "tz": zone, "days": [day0, day1]]
  }

  private func respond(_ status: Int, body: Data = Data(), headers: [String: String] = [:]) {
    AWStubProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      return (response, body)
    }
  }

  private func drawn() throws -> AWSnapshot {
    let local = try JSONDecoder().decode(AWSnapshot.self, from: Data(localJSON.utf8))
    return fetcher().snapshotToDraw(local: local, today: "2025-11-12")
  }

  private func int(_ key: String) -> Int? { defaults.object(forKey: key) as? Int }

  // MARK: - 200

  func testServerSnapshotIsStoredUnderItsOwnKey() async throws {
    let body = try JSONSerialization.data(withJSONObject: serverBody())
    respond(200, body: body, headers: ["ETag": "\"abc\"", "Cache-Control": "no-store"])
    clock = start.addingTimeInterval(1)

    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .stored)

    // One request, the contract's: path, query, bearer token, no If-None-Match.
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    let request = try XCTUnwrap(AWStubProtocol.requests.first)
    XCTAssertEqual(request.url?.host, "api.example.test")
    XCTAssertEqual(request.url?.path, "/api/v1/widget/snapshot")
    let sentQuery = request.url.flatMap {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery
    }
    XCTAssertEqual(sentQuery, "tz=Europe%2FIstanbul&workspaceIds=01JW1&mine=0&private=1&days=3")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer aww_test")
    XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))

    // Its own key: Dart's snapshot is untouched.
    XCTAssertEqual(defaults.string(forKey: kAWLocalSnapshotKey), localJSON)
    let envelope = try XCTUnwrap(
      AWServerEnvelope(json: defaults.string(forKey: kAWServerSnapshotKey)))
    XCTAssertEqual(envelope.fetchedAtMs, startMs + 1000)
    XCTAssertEqual(envelope.etag, "\"abc\"")
    XCTAssertEqual(envelope.query, sentQuery)
    XCTAssertEqual(int(kAWFetchedAtKey), startMs + 1000)
    XCTAssertEqual(int(kAWFetchFailuresKey), 0)
    XCTAssertNil(defaults.object(forKey: kAWBackoffUntilKey))

    // The server's days drawn in the app's words (profile strings and
    // patterns, Istanbul time), the chrome from the app's snapshot.
    let snap = try drawn()
    XCTAssertEqual(snap.days?.map(\.date), ["2025-11-12", "2025-11-13"])
    XCTAssertEqual(snap.date.weekday, "Çarşamba")
    XCTAssertEqual(snap.date.day, "12")
    XCTAssertEqual(snap.date.month, "Kasım")
    XCTAssertEqual(snap.openToday, 2)
    XCTAssertEqual(snap.strings?["openToday"], "2 açık")
    XCTAssertEqual(snap.buckets.map(\.label), ["Gecikmiş", "Bugün"])
    let overdue = try XCTUnwrap(snap.buckets.first?.items.first)
    XCTAssertEqual(overdue.title, "Gizli görev", "private: the app's word, never the server's")
    XCTAssertEqual(overdue.time, "11 Kas")
    XCTAssertEqual(overdue.projectColor, "#2563EB")
    let today = try XCTUnwrap(snap.buckets.last?.items)
    XCTAssertEqual(today.map(\.time), ["18:00", "14:00–15:30", "Yarın\u{00A0}20:00"])
    XCTAssertEqual(today[1].title, "Gizli etkinlik")
    XCTAssertTrue(today[1].isEvent)
    XCTAssertEqual(snap.next?.label, "Gecikmiş")
    XCTAssertEqual(snap.next?.title, "Gizli görev")
    XCTAssertEqual(snap.views?["p1"]?.openTodayLabel, "1 açık")
    // Tomorrow's own view: the same row is now on its own day.
    let day1 = try XCTUnwrap(snap.days?[1])
    XCTAssertEqual(day1.header?.weekday, "Perşembe")
    XCTAssertEqual(day1.buckets?.first?.items.first?.time, "20:00")

    // The N widgets WidgetKit reloads together make one request.
    clock = start.addingTimeInterval(60)
    let again = await fetcher().refresh()
    XCTAssertEqual(again, .skipped)
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
  }

  func testNotModifiedRefreshesTheStamp() async throws {
    let body = try JSONSerialization.data(withJSONObject: serverBody())
    respond(200, body: body, headers: ["ETag": "\"abc\""])
    _ = await fetcher().refresh()

    respond(304, headers: ["ETag": "\"abc\""])
    clock = start.addingTimeInterval(kAWFetchMinInterval)
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .notModified)
    XCTAssertEqual(AWStubProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
    let envelope = try XCTUnwrap(
      AWServerEnvelope(json: defaults.string(forKey: kAWServerSnapshotKey)))
    XCTAssertEqual(envelope.fetchedAtMs, startMs + 1_800_000)
    XCTAssertEqual(int(kAWFetchedAtKey), startMs + 1_800_000)
    XCTAssertNotNil(awServerView(envelope, pendingCompletionTaskIds: [], today: nil))
  }

  func testAPendingLocalChangeKeepsTheAppSnapshotAfterAFetch() async throws {
    let body = try JSONSerialization.data(withJSONObject: serverBody())
    respond(200, body: body, headers: ["ETag": "\"abc\""])
    defaults.set(profileJSON(localWrittenAtMs: startMs - 600_000, outbox: 1), forKey: kAWFetchProfileKey)
    _ = await fetcher().refresh()
    XCTAssertNotNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertEqual(try drawn().buckets.first?.items.first?.id, "L")
  }

  /// A task the phone does not hold yet (created elsewhere while the app was
  /// swiped away) is drawn from the server's view, but its circle cannot
  /// complete it in place: the app applies a queued completion to its own
  /// copy, and it has none, so the press would be lost. A task the app's
  /// snapshot holds keeps the circle; an event never had one.
  func testOnlyTasksThePhoneHoldsCanBeCompletedFromTheServerView() throws {
    let both = """
      {"v":6,"generatedAt":"2025-11-12T07:50:00.000Z","locale":"tr",
       "date":{"weekday":"Çarşamba","day":"12","month":"Kasım"},
       "strings":{"openTodayPattern":"{count} açık"},
       "buckets":[{"key":"today","label":"Bugün","count":1,
         "items":[{"id":"B","title":"local B","done":false,"priority":"none"}]}],
       "days":[{"date":"2025-11-13","buckets":[{"key":"today","label":"Bugün","count":1,
         "items":[{"id":"C","title":"local C","done":false,"priority":"none"}]}]}]}
      """
    let local = try JSONDecoder().decode(AWSnapshot.self, from: Data(both.utf8))
    let envelope = AWServerEnvelope(
      fetchedAtMs: startMs, etag: "\"abc\"", query: "q", body: serverBody())
    let view = try XCTUnwrap(
      awServerView(envelope, pendingCompletionTaskIds: [], today: nil))
    let profile = try XCTUnwrap(
      AWWidgetFetchProfile.decode(profileJSON(localWrittenAtMs: startMs - 600_000)))
    let snap = awSnapshotFromServer(
      view, local: local, profile: profile,
      timeZone: TimeZone(identifier: zone)!)

    let rows = snap.buckets.flatMap(\.items)
    let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    XCTAssertEqual(byId["A"]?.serverOnly, true, "A is only on the server")
    XCTAssertFalse(byId["A"]?.canCompleteInPlace ?? true)
    XCTAssertNotEqual(byId["B"]?.serverOnly, true, "the phone holds B")
    XCTAssertTrue(byId["B"]?.canCompleteInPlace ?? false)
    XCTAssertTrue(byId["C"]?.canCompleteInPlace ?? false, "C is in a later day of the phone's")
    XCTAssertFalse(byId["E"]?.canCompleteInPlace ?? true, "an event is never completed")
    // Every place the row is drawn says the same: a project's view, a later day.
    XCTAssertEqual(snap.views?["p1"]?.buckets.first?.items.first?.serverOnly, true)
    XCTAssertEqual(snap.days?[1].buckets?.first?.items.first?.id, "C")
    XCTAssertTrue(snap.days?[1].buckets?.first?.items.first?.canCompleteInPlace ?? false)

    // The app's own snapshot never carries the mark: every open task row of
    // it completes in place, as before.
    XCTAssertTrue(local.buckets.first?.items.first?.canCompleteInPlace ?? false)
  }

  /// The app completes L and writes its snapshot and an unsent outbox entry
  /// while the request is out: the choice keeps the app's snapshot, and the
  /// one it draws is the new one, with L done — not the one read before the
  /// request, with L open again.
  func testTheAppSnapshotIsReadAfterTheRequest() async throws {
    let body = try JSONSerialization.data(withJSONObject: serverBody())
    let completed = localJSON.replacingOccurrences(of: #""done":false"#, with: #""done":true"#)
    XCTAssertNotEqual(completed, localJSON)
    let pending = profileJSON(localWrittenAtMs: startMs + 500, outbox: 1)
    let defaults = self.defaults!
    AWStubProtocol.handler = { request in
      defaults.set(completed, forKey: kAWLocalSnapshotKey)
      defaults.set(pending, forKey: kAWFetchProfileKey)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"abc\""])!
      return (response, body)
    }
    clock = start.addingTimeInterval(1)

    let snap = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    let row = try XCTUnwrap(snap.buckets.first?.items.first)
    XCTAssertEqual(row.id, "L")
    XCTAssertTrue(row.done, "the snapshot the app wrote during the request")
  }

  // MARK: - A tap on the circle (#50, PR2-03, PR2-05, PR2-09)

  private let fetchQuery = "tz=Europe%2FIstanbul&workspaceIds=01JW1&mine=0&private=1&days=3"

  /// The app holds B, C and D today; the server's view holds A (created
  /// elsewhere, not on the phone yet), B and C.
  private let slotLocalJSON = """
    {"v":6,"generatedAt":"2025-11-12T07:50:00.000Z","locale":"tr",
     "date":{"weekday":"Çarşamba","day":"12","month":"Kasım"},
     "strings":{"openToday":"3 açık","openTodayPattern":"{count} açık"},
     "buckets":[{"key":"today","label":"Bugün","count":3,
       "items":[{"id":"B","title":"B","done":false,"priority":"none"},
                {"id":"C","title":"C","done":false,"priority":"none"},
                {"id":"D","title":"D","done":false,"priority":"none"}]}]}
    """

  private func slotServerBody() -> [String: Any] {
    func task(_ id: String, _ dueAt: String) -> [String: Any] {
      ["id": id, "done": false, "priority": "none", "dueAt": dueAt, "timeStyle": "time"]
    }
    let items = [
      task("A", "2025-11-12T10:00:00.000Z"), task("B", "2025-11-12T11:00:00.000Z"),
      task("C", "2025-11-12T12:00:00.000Z"),
    ]
    let day0: [String: Any] = [
      "date": "2025-11-12", "openToday": 3,
      "buckets": [["key": "today", "count": 3, "items": items]],
    ]
    return ["v": 1, "generatedAt": "2025-11-12T07:59:00.000Z", "tz": zone, "days": [day0]]
  }

  /// A server view fetched a minute ago, after the app last wrote: it wins.
  private func storeSlotServerView() {
    defaults.set(slotLocalJSON, forKey: kAWLocalSnapshotKey)
    let envelope = AWServerEnvelope(
      fetchedAtMs: startMs - 60_000, etag: "\"s1\"", query: fetchQuery, body: slotServerBody())
    defaults.set(envelope.json, forKey: kAWServerSnapshotKey)
    defaults.set(startMs - 60_000, forKey: kAWFetchedAtKey)
  }

  /// What the circle's intent does to the App Group (AWWidgetCompleteIntent).
  @discardableResult
  private func tap(_ taskId: String) -> String {
    let eventId = AWAlarmActionQueue.enqueue(
      action: "complete", taskIds: [taskId], origin: "widget", pressedAt: clock,
      in: defaults, notify: false)
    awStampWidgetCompletion(in: defaults, at: clock)
    return eventId
  }

  private func todayIds(_ snap: AWSnapshot) -> [String] {
    snap.buckets.first { $0.key == "today" }?.items.map(\.id) ?? []
  }

  /// A completion queued by the circle: the turn answers at once from the
  /// App Group, no request, however long it has been since the last fetch.
  func testNoFetchWhileCompletionQueued() async throws {
    respond(200, body: try JSONSerialization.data(withJSONObject: serverBody()))
    let eventId = tap("L")
    clock = start.addingTimeInterval(3600)

    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .skipped)
    XCTAssertEqual(AWStubProtocol.requests.count, 0)
    let snap = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 0)
    XCTAssertEqual(snap.buckets.first?.items.first?.done, true, "the done mark, at once")

    // The app pulled the queue: the next turn may fetch again.
    AWAlarmActionQueue.ack(eventIds: [eventId], in: defaults)
    let after = await fetcher().refresh()
    XCTAssertEqual(after, .stored)
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
  }

  /// Within 90 s of the circle's press no turn fetches, even once the app
  /// has pulled the queue.
  func testNoFetchWithin90sOfAnIntent() async throws {
    respond(200, body: try JSONSerialization.data(withJSONObject: serverBody()))
    let pressed = clock
    AWAlarmActionQueue.ack(eventIds: [tap("L")], in: defaults)
    XCTAssertEqual(int(kAWCompletedAtKey), startMs)

    clock = pressed.addingTimeInterval(89)
    let early = await fetcher().refresh()
    XCTAssertEqual(early, .skipped)
    XCTAssertEqual(AWStubProtocol.requests.count, 0)

    clock = pressed.addingTimeInterval(90)
    let later = await fetcher().refresh()
    XCTAssertEqual(later, .stored)
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
  }

  /// Two widgets on one screen (PR2-09): the first turn's fetch stores a new
  /// view and asks the others to reload; their turns, seconds or minutes
  /// later, make no request and draw the same stored view.
  func testSecondWidgetReusesEnvelope() async throws {
    respond(
      200, body: try JSONSerialization.data(withJSONObject: serverBody()),
      headers: ["ETag": "\"abc\""])
    clock = start.addingTimeInterval(1)
    let first = await fetcher().turn(fetch: true, today: { "2025-11-12" })
    XCTAssertTrue(first.changed, "a new view: the other widgets reload")
    XCTAssertEqual(AWStubProtocol.requests.count, 1)

    for seconds in [6.0, 600, 1_799] {
      clock = start.addingTimeInterval(seconds)
      let second = await fetcher().turn(fetch: true, today: { "2025-11-12" })
      XCTAssertFalse(second.changed, "a reused view reloads nothing, so no loop")
      XCTAssertEqual(AWStubProtocol.requests.count, 1, "no request at +\(seconds) s")
      XCTAssertEqual(todayIds(second.snapshot), todayIds(first.snapshot))
      XCTAssertEqual(second.snapshot.openToday, first.snapshot.openToday)
    }

    // One refresh interval on, the next turn asks again; a 304 is no new view.
    respond(304, headers: ["ETag": "\"abc\""])
    clock = start.addingTimeInterval(1 + kAWFetchMinInterval)
    let next = await fetcher().turn(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 2)
    XCTAssertFalse(next.changed)
  }

  /// Two widgets build their timelines at once with the stamp expired: the
  /// second turn finds the first one's request out and makes none, so there
  /// is one request per interval however many widgets ask, and no older
  /// answer can land after a newer one. The first turn's new view reloads it.
  func testASecondTurnWhileARequestIsOutMakesNone() async throws {
    respond(
      200, body: try JSONSerialization.data(withJSONObject: serverBody()),
      headers: ["ETag": "\"abc\""])
    AWStubProtocol.holdFirst = true
    let firstFetcher = fetcher()
    let first = Task { await firstFetcher.turn(fetch: true, today: { "2025-11-12" }) }
    for _ in 0..<500 where !AWStubProtocol.isHolding {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(AWStubProtocol.isHolding, "the first request is out")

    let second = await fetcher().turn(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 1, "no second request while one is out")
    XCTAssertFalse(second.changed)

    AWStubProtocol.releaseHeld()
    let firstTurn = await first.value
    XCTAssertTrue(firstTurn.changed, "the stored view reloads the other widget")
    XCTAssertEqual(int(kAWFetchedAtKey), startMs)
    XCTAssertNil(defaults.object(forKey: kAWFetchClaimKey), "the claim ends with the turn")

    // The other widget's reload, and a third widget's turn, draw it without asking.
    let third = await fetcher().turn(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    XCTAssertEqual(todayIds(third.snapshot), todayIds(firstTurn.snapshot))
  }

  /// The server's view was drawn ([A, B, C], A only on the server). A tap on
  /// B's circle leaves every row where it was and B done in its own slot:
  /// switching to the app's view ([B, C, D]) moved B up a row, and a second
  /// tap at the same point completed C.
  func testCompletedRowKeepsItsSlot() async throws {
    storeSlotServerView()
    let before = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(before), ["A", "B", "C"])

    tap("B")
    clock = start.addingTimeInterval(2)
    let after = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 0)
    XCTAssertEqual(todayIds(after), ["A", "B", "C"], "no row moved under the finger")
    let rows = try XCTUnwrap(after.buckets.first { $0.key == "today" }?.items)
    XCTAssertEqual(rows.map(\.done), [false, true, false])
    XCTAssertFalse(rows[1].canCompleteInPlace, "a done row has no button to press again")
    XCTAssertEqual(after.openToday, 2)

    // The app's own view drawn before the tap keeps its rows too.
    defaults.set(
      profileJSON(localWrittenAtMs: startMs), forKey: kAWFetchProfileKey)
    let local = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(local), ["B", "C", "D"])
    XCTAssertEqual(local.buckets.first?.items.map(\.done), [true, false, false])
  }

  /// The circle's intent, as the stub's handler can run it while a request is
  /// out (another thread, so no `self`).
  private static func press(_ taskId: String, in defaults: UserDefaults, at date: Date) {
    _ = AWAlarmActionQueue.enqueue(
      action: "complete", taskIds: [taskId], origin: "widget", pressedAt: date,
      in: defaults, notify: false)
    awStampWidgetCompletion(in: defaults, at: date)
  }

  /// A request already out when the circle is pressed. The app's view
  /// [B, C, D] is drawn, C is completed in the second slot while a turn's
  /// request is on its way, and the answer [A, B, C] arrives after the tap.
  /// It is not stored: drawing it would move C to the third slot and put B
  /// under the finger, and the next tap there would complete B.
  func testAnAnswerThatArrivesAfterATapIsDiscarded() async throws {
    defaults.set(slotLocalJSON, forKey: kAWLocalSnapshotKey)
    let before = await fetcher().drawnSnapshot(fetch: false, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(before), ["B", "C", "D"])

    let body = try JSONSerialization.data(withJSONObject: slotServerBody())
    let defaults = self.defaults!
    let pressedAt = start.addingTimeInterval(1)
    AWStubProtocol.handler = { request in
      Self.press("C", in: defaults, at: pressedAt)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"s2\""])!
      return (response, body)
    }
    clock = start.addingTimeInterval(2)
    let outcome = await fetcher().refresh()
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    XCTAssertEqual(outcome, .discarded)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertNil(defaults.object(forKey: kAWFetchedAtKey), "not a success")
    XCTAssertNil(defaults.object(forKey: kAWBackoffUntilKey), "not a failure")

    let after = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    XCTAssertEqual(todayIds(after), ["B", "C", "D"], "no row moved under the finger")
    XCTAssertEqual(after.buckets.first?.items.map(\.done), [false, true, false])
  }

  /// The same race on a 304: the stored view lost to the app's newer write,
  /// and a stamp moved on after the tap would make it win and swap the rows.
  func testANotModifiedThatArrivesAfterATapIsDiscarded() async throws {
    defaults.set(slotLocalJSON, forKey: kAWLocalSnapshotKey)
    let fetchedAt = startMs - 2_000_000  // before the app's write, outside the interval
    let envelope = AWServerEnvelope(
      fetchedAtMs: fetchedAt, etag: "\"s1\"", query: fetchQuery, body: slotServerBody())
    defaults.set(envelope.json, forKey: kAWServerSnapshotKey)
    defaults.set(fetchedAt, forKey: kAWFetchedAtKey)
    let before = await fetcher().drawnSnapshot(fetch: false, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(before), ["B", "C", "D"])

    let defaults = self.defaults!
    let pressedAt = start.addingTimeInterval(1)
    AWStubProtocol.handler = { request in
      Self.press("C", in: defaults, at: pressedAt)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 304, httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"s1\""])!
      return (response, Data())
    }
    clock = start.addingTimeInterval(2)
    let outcome = await fetcher().refresh()
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    XCTAssertEqual(outcome, .discarded)
    XCTAssertEqual(int(kAWFetchedAtKey), fetchedAt, "the stamp did not move")
    XCTAssertEqual(AWServerEnvelope(json: defaults.string(forKey: kAWServerSnapshotKey))?.fetchedAtMs, fetchedAt)

    let after = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(after), ["B", "C", "D"])
    XCTAssertEqual(after.buckets.first?.items.map(\.done), [false, true, false])
  }

  /// A tap that lands between the fetcher's last look and its write: the
  /// second look catches it and takes the write back, leaving the view that
  /// was there before.
  func testAnAnswerStoredJustAfterATapIsTakenBack() async throws {
    defaults.set(slotLocalJSON, forKey: kAWLocalSnapshotKey)
    respond(
      200, body: try JSONSerialization.data(withJSONObject: slotServerBody()),
      headers: ["ETag": "\"s2\""])
    let hooked = self.hooked
    let pressedAt = start.addingTimeInterval(1)
    hooked.beforeServerWrite = { Self.press("C", in: hooked, at: pressedAt) }
    clock = start.addingTimeInterval(2)

    let outcome = await fetcher().refresh()
    XCTAssertNil(hooked.beforeServerWrite, "the write went through the hook")
    XCTAssertEqual(outcome, .discarded)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertNil(defaults.object(forKey: kAWFetchedAtKey))

    let after = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })
    XCTAssertEqual(todayIds(after), ["B", "C", "D"])
    XCTAssertEqual(after.buckets.first?.items.map(\.done), [false, true, false])
  }

  /// `apps/app/test/fixtures/widget_view_swap.json`, written by the Dart test
  /// from the app's own builders: `local` is the phone's snapshot of 40 tasks
  /// due at the same minute today, `server` the `GET /widget/snapshot` body for
  /// the same rows plus one created elsewhere (the server's grouping is held to
  /// the Dart one by the shared grouping fixture). Resolved from this source
  /// file, so it works from Xcode and from `xcodebuild test` alike.
  private func loadViewSwapFixture() throws -> (local: String, server: [String: Any]) {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // apps/app
      .appendingPathComponent("test/fixtures/widget_view_swap.json")
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let local = try XCTUnwrap(root["local"] as? [String: Any])
    let server = try XCTUnwrap(root["server"] as? [String: Any])
    let localData = try JSONSerialization.data(withJSONObject: local)
    return (try XCTUnwrap(String(data: localData, encoding: .utf8)), server)
  }

  /// The rows both views hold are drawn in the same order whichever view
  /// wins, so a swap at a refresh only shows the row the phone lacks and
  /// moves nothing else (#50, PR2-03). Ties past 32 rows: an unstable sort on
  /// the phone drew them in another order than the server, and the swap put
  /// another task under the finger.
  func testRowsInBothViewsKeepTheirOrder() throws {
    let fixture = try loadViewSwapFixture()
    defaults.set(fixture.local, forKey: kAWLocalSnapshotKey)
    let envelope = AWServerEnvelope(
      fetchedAtMs: startMs - 60_000, etag: "\"swap\"", query: fetchQuery, body: fixture.server)
    defaults.set(envelope.json, forKey: kAWServerSnapshotKey)
    defaults.set(startMs - 60_000, forKey: kAWFetchedAtKey)

    let local = awLoadLocalSnapshot(in: defaults, today: "2025-11-12")
    let server = fetcher().snapshotToDraw(local: local, today: "2025-11-12")
    let localIds = todayIds(local)
    let serverIds = todayIds(server)
    XCTAssertEqual(localIds.count, 12)
    XCTAssertEqual(serverIds.count, 12)
    XCTAssertEqual(serverIds.first, "T41", "the row only the server holds, newest first")
    XCTAssertEqual(
      Array(serverIds.dropFirst()), Array(localIds.prefix(11)),
      "every row both views hold sits in the phone's order")

    // A completion laid over both views moves nothing either.
    let tapped = localIds[3]
    tap(tapped)
    let overLocal = awLoadLocalSnapshot(in: defaults, today: "2025-11-12")
    let overServer = fetcher().snapshotToDraw(local: overLocal, today: "2025-11-12")
    XCTAssertEqual(todayIds(overLocal), localIds)
    XCTAssertEqual(todayIds(overServer), serverIds)
    let done = { (snap: AWSnapshot) in
      snap.buckets.first { $0.key == "today" }?.items.filter(\.done).map(\.id) ?? []
    }
    XCTAssertEqual(done(overLocal), [tapped])
    XCTAssertEqual(done(overServer), [tapped])
  }

  /// A row only the server holds opens the app at its task (PR2-03): its
  /// Link goes to the task, not to the widget-wide `alliswell://open`.
  func testAServerOnlyRowOpensItsTask() throws {
    storeSlotServerView()
    let local = try JSONDecoder().decode(AWSnapshot.self, from: Data(slotLocalJSON.utf8))
    let rows = try XCTUnwrap(
      fetcher().snapshotToDraw(local: local, today: "2025-11-12").buckets.first?.items)
    let a = try XCTUnwrap(rows.first { $0.id == "A" })
    XCTAssertEqual(a.serverOnly, true)
    XCTAssertFalse(a.canCompleteInPlace)
    XCTAssertEqual(a.taskURL.absoluteString, "alliswell://task/A")
    XCTAssertEqual(
      AWTaskRow(
        id: "01JABC", title: "", done: false, priority: "none", time: nil, projectColor: nil,
        kind: nil, day: nil
      ).taskURL.absoluteString, "alliswell://task/01JABC")
    // An id that is not a plain token, and an event, open the app.
    XCTAssertEqual(
      AWTaskRow(
        id: "x/../y?z", title: "", done: false, priority: "none", time: nil, projectColor: nil,
        kind: nil, day: nil
      ).taskURL.absoluteString, "alliswell://open")
    XCTAssertEqual(
      AWTaskRow(
        id: "E", title: "", done: false, priority: "none", time: nil, projectColor: nil,
        kind: "event", day: "2025-11-12"
      ).taskURL.absoluteString, "alliswell://open")
  }

  // MARK: - A profile that changed during the request

  /// "Private widget" turned on while a request made without it was still
  /// out: Dart removed the server view, and the late answer must not put the
  /// titles back into the App Group (WIDGETS.md §9).
  func testAnAnswerForAProfileNoLongerCurrentIsDiscarded() async throws {
    defaults.set(
      profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: false),
      forKey: kAWFetchProfileKey)
    var titled = serverBody()
    var days = titled["days"] as! [[String: Any]]
    var buckets = days[0]["buckets"] as! [[String: Any]]
    var items = buckets[0]["items"] as! [[String: Any]]
    items[0]["title"] = "secret title"
    buckets[0]["items"] = items
    days[0]["buckets"] = buckets
    titled["days"] = days
    let body = try JSONSerialization.data(withJSONObject: titled)
    let turnedPrivate = profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: true)
    let defaults = self.defaults!
    AWStubProtocol.handler = { request in
      // What the app does while the answer is on its way.
      defaults.set(turnedPrivate, forKey: kAWFetchProfileKey)
      defaults.removeObject(forKey: kAWServerSnapshotKey)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"abc\""])!
      return (response, body)
    }

    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .discarded)
    XCTAssertEqual(
      AWStubProtocol.requests.first?.url?.query?.contains("private=0"), true,
      "the request went out under the old profile")
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    // Neither a success nor a failure: the next turn asks again at once.
    XCTAssertNil(defaults.object(forKey: kAWFetchedAtKey))
    XCTAssertNil(defaults.object(forKey: kAWFetchFailuresKey))
    XCTAssertNil(defaults.object(forKey: kAWBackoffUntilKey))
    XCTAssertEqual(try drawn().buckets.first?.items.first?.id, "L")
  }

  /// The same race on a 304: the stored view of the old profile is not
  /// written back after the app removed it.
  func testANotModifiedForAProfileNoLongerCurrentIsDiscarded() async throws {
    defaults.set(
      profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: false),
      forKey: kAWFetchProfileKey)
    let body = try JSONSerialization.data(withJSONObject: serverBody())
    respond(200, body: body, headers: ["ETag": "\"abc\""])
    _ = await fetcher().refresh()
    XCTAssertNotNil(defaults.string(forKey: kAWServerSnapshotKey))

    let turnedPrivate = profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: true)
    let defaults = self.defaults!
    AWStubProtocol.handler = { request in
      defaults.set(turnedPrivate, forKey: kAWFetchProfileKey)
      defaults.removeObject(forKey: kAWServerSnapshotKey)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 304, httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"abc\""])!
      return (response, Data())
    }
    clock = start.addingTimeInterval(kAWFetchMinInterval)
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .discarded)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
  }

  /// The app writes the new profile, then removes the server view (Dart's
  /// order). An answer that passed the check just before the profile write
  /// and is stored just after it is caught by the second look: the fetcher
  /// removes what it wrote itself, before the app's removal even comes.
  func testAnAnswerStoredJustAfterTheProfileChangedIsRemovedAgain() async throws {
    defaults.set(
      profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: false),
      forKey: kAWFetchProfileKey)
    var titled = serverBody()
    var days = titled["days"] as! [[String: Any]]
    var buckets = days[0]["buckets"] as! [[String: Any]]
    var items = buckets[0]["items"] as! [[String: Any]]
    items[0]["title"] = "secret title"
    buckets[0]["items"] = items
    days[0]["buckets"] = buckets
    titled["days"] = days
    respond(
      200, body: try JSONSerialization.data(withJSONObject: titled),
      headers: ["ETag": "\"abc\""])
    let turnedPrivate = profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: true)
    let hooked = self.hooked
    // Between the fetcher's check and its write: only the profile, the
    // app's removal has not run yet.
    hooked.beforeServerWrite = { hooked.set(turnedPrivate, forKey: kAWFetchProfileKey) }

    let outcome = await fetcher().refresh()
    XCTAssertNil(hooked.beforeServerWrite, "the write went through the hook")
    XCTAssertEqual(outcome, .discarded)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertNil(defaults.object(forKey: kAWFetchedAtKey))
    XCTAssertNil(defaults.object(forKey: kAWFetchFailuresKey))
    XCTAssertNil(defaults.object(forKey: kAWBackoffUntilKey))
  }

  /// The same on a 304: the old profile's view, written back just after the
  /// profile changed, is removed again.
  func testANotModifiedStoredJustAfterTheProfileChangedIsRemovedAgain() async throws {
    defaults.set(
      profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: false),
      forKey: kAWFetchProfileKey)
    respond(
      200, body: try JSONSerialization.data(withJSONObject: serverBody()),
      headers: ["ETag": "\"abc\""])
    _ = await fetcher().refresh()
    XCTAssertNotNil(defaults.string(forKey: kAWServerSnapshotKey))

    respond(304, headers: ["ETag": "\"abc\""])
    let turnedPrivate = profileJSON(localWrittenAtMs: startMs - 600_000, isPrivate: true)
    let hooked = self.hooked
    hooked.beforeServerWrite = {
      hooked.set(turnedPrivate, forKey: kAWFetchProfileKey)
      hooked.removeObject(forKey: kAWServerSnapshotKey)
    }
    clock = start.addingTimeInterval(kAWFetchMinInterval)
    let outcome = await fetcher().refresh()
    XCTAssertNil(hooked.beforeServerWrite, "the write went through the hook")
    XCTAssertEqual(outcome, .discarded)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
  }

  // MARK: - 401

  func testUnauthorizedMarksTheTokenInvalidAndStops() async throws {
    respond(401, body: Data(#"{"statusCode":401,"code":"AUTH_WIDGET_TOKEN_INVALID"}"#.utf8))
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .unauthorized)
    XCTAssertEqual(defaults.string(forKey: kAWTokenStateKey), kAWTokenStateInvalid)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertEqual(try drawn().buckets.first?.items.first?.id, "L")

    // Hours later, still nothing: only the app's re-mint (`valid`) resumes it.
    clock = start.addingTimeInterval(6 * 3600)
    let later = await fetcher().refresh()
    XCTAssertEqual(later, .skipped)
    XCTAssertEqual(AWStubProtocol.requests.count, 1)
    defaults.set("valid", forKey: kAWTokenStateKey)
    respond(304)
    _ = await fetcher().refresh()
    XCTAssertEqual(AWStubProtocol.requests.count, 2)
  }

  func testNoTokenMeansNoRequest() async {
    token = nil
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .skipped)
    XCTAssertTrue(AWStubProtocol.requests.isEmpty)
    XCTAssertNil(defaults.object(forKey: kAWFetchFailuresKey))
    XCTAssertNil(defaults.object(forKey: kAWBackoffUntilKey))
  }

  func testTheKeychainQueryIsTheContract() {
    let query = awWidgetTokenQuery()
    XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
    XCTAssertEqual(query[kSecAttrService as String] as? String, "flutter_secure_storage_service")
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "aw_widget_token")
    XCTAssertEqual(
      query[kSecAttrAccessGroup as String] as? String, "group.com.alliswell.alliswell")
    XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
    XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
  }

  // MARK: - Failure

  func testTimeoutFallsBackToTheAppGroupSnapshot() async throws {
    let configuration = AWWidgetFetcher.sessionConfiguration()
    XCTAssertEqual(configuration.timeoutIntervalForRequest, 6)
    XCTAssertEqual(configuration.timeoutIntervalForResource, 8)
    XCTAssertFalse(configuration.waitsForConnectivity)

    AWStubProtocol.handler = { _ in throw URLError(.timedOut) }
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .failed)
    XCTAssertEqual(int(kAWFetchFailuresKey), 1)
    XCTAssertEqual(int(kAWBackoffUntilKey), startMs + 300_000)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertEqual(defaults.string(forKey: kAWLocalSnapshotKey), localJSON)
    let snap = try drawn()
    XCTAssertEqual(snap.buckets.first?.items.first?.title, "local row")

    // Inside the backoff: no request. After it, a 5xx doubles it.
    clock = start.addingTimeInterval(299)
    let waiting = await fetcher().refresh()
    XCTAssertEqual(waiting, .skipped)
    clock = start.addingTimeInterval(300)
    respond(503)
    let second = await fetcher().refresh()
    XCTAssertEqual(second, .failed)
    XCTAssertEqual(int(kAWFetchFailuresKey), 2)
    XCTAssertEqual(int(kAWBackoffUntilKey), startMs + 300_000 + 600_000)
    XCTAssertEqual(AWStubProtocol.requests.count, 2)

    // The App Group snapshot is still what the widget draws.
    XCTAssertEqual(try drawn().buckets.first?.items.first?.id, "L")
  }

  func testAnUnreadableBodyIsAFailure() async {
    respond(200, body: Data("<html>".utf8))
    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .failed)
    XCTAssertNil(defaults.string(forKey: kAWServerSnapshotKey))
    XCTAssertEqual(int(kAWFetchFailuresKey), 1)
  }
}

/// Answers every request of a session configured with it from `handler`.
final class AWStubProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  static var requests: [URLRequest] = []
  /// When set, the first request is held unanswered until `releaseHeld()`,
  /// so a test can run another turn while it is out. Later ones are answered.
  static var holdFirst = false
  private static let lock = NSLock()
  private static var held: (() -> Void)?

  static var isHolding: Bool {
    lock.lock()
    defer { lock.unlock() }
    return held != nil
  }

  static func reset() {
    handler = nil
    requests = []
    holdFirst = false
    lock.lock()
    held = nil
    lock.unlock()
  }

  /// Answers the held request.
  static func releaseHeld() {
    lock.lock()
    let answer = held
    held = nil
    lock.unlock()
    answer?()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.requests.append(request)
    let hold = Self.holdFirst && Self.requests.count == 1
    if hold { Self.held = { [self] in self.answer() } }
    Self.lock.unlock()
    if !hold { answer() }
  }

  private func answer() {
    do {
      guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

/// App Group defaults that run `beforeServerWrite` once, just before the next
/// write of the server view — where another process's write can land between
/// the fetcher's check and its own write.
final class AWHookedDefaults: UserDefaults {
  var beforeServerWrite: (() -> Void)?

  override func set(_ value: Any?, forKey defaultName: String) {
    if defaultName == kAWServerSnapshotKey, let hook = beforeServerWrite {
      beforeServerWrite = nil
      hook()
    }
    super.set(value, forKey: defaultName)
  }
}
