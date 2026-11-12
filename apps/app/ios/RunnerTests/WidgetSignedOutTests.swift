import Foundation
import XCTest

@testable import Runner

/// #50, PR2-02 (WIDGETS.md §3.2): after a sign-out the widget kept drawing the
/// account's tasks. The app now removes the fetch keys — by writing the empty
/// string, since a null aborted it (PR2-01) — and writes an empty snapshot.
/// The extension must then draw that signed-out snapshot and send nothing:
/// an absent or empty profile is no profile, an empty envelope no envelope,
/// even with a titled answer from before the sign-out still stored.
final class WidgetSignedOutTests: XCTestCase {

  private let start = Date(timeIntervalSince1970: 1_762_934_400)  // 2025-11-12 08:00 UTC
  private var suite = ""
  private var defaults: UserDefaults!

  /// What Dart writes at sign-out: the day and the app's words, no row.
  private let signedOutJSON = """
    {"v":6,"generatedAt":"2025-11-12T08:00:00.000Z","locale":"en",
     "date":{"weekday":"Wednesday","day":"12","month":"November"},
     "strings":{"allCaughtUp":"All caught up","addTask":"Add task"},
     "buckets":[],"lists":[{"id":"all","name":"All tasks"}],
     "days":[{"date":"2025-11-12","header":{"weekday":"Wednesday","day":"12","month":"November"},
       "buckets":[]}]}
    """

  /// An answer stored before the sign-out, with a title in it.
  private let titledEnvelope = """
    {"fetchedAtMs":1762934500000,"etag":"\\"e\\"",
     "query":"tz=Europe%2FIstanbul&workspaceIds=01JW1&mine=0&private=0&days=3",
     "body":{"v":1,"tz":"Europe/Istanbul","days":[{"date":"2025-11-12","openToday":1,
       "buckets":[{"key":"today","count":1,"items":[{"id":"S","title":"SECRET server row",
         "done":false,"priority":"none"}]}]}]}}
    """

  override func setUp() {
    super.setUp()
    suite = "aw.signedout.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
    AWStubProtocol.reset()
    AWStubProtocol.handler = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
      return (response, Data("{}".utf8))
    }
    defaults.set(signedOutJSON, forKey: kAWLocalSnapshotKey)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    AWStubProtocol.reset()
    super.tearDown()
  }

  private func fetcher() -> AWWidgetFetcher {
    let configuration = AWWidgetFetcher.sessionConfiguration()
    configuration.protocolClasses = [AWStubProtocol.self]
    return AWWidgetFetcher(
      defaults: defaults, session: URLSession(configuration: configuration),
      readToken: { "aww_test" }, now: { [unowned self] in self.start },
      timeZone: "Europe/Istanbul")
  }

  private func assertSignedOut(
    _ snapshot: AWSnapshot, file: StaticString = #filePath, line: UInt = #line
  ) {
    // The app's signed-out snapshot, not a decode failure's `.empty`.
    XCTAssertEqual(snapshot.date.weekday, "Wednesday", file: file, line: line)
    XCTAssertTrue(snapshot.buckets.isEmpty, "no row is drawn", file: file, line: line)
    XCTAssertNil(snapshot.next, file: file, line: line)
    XCTAssertTrue(
      AWStubProtocol.requests.isEmpty, "a signed-out widget sends nothing", file: file,
      line: line)
  }

  func testAbsentProfileDrawsSignedOutAndDoesNotFetch() async throws {
    // No profile at all, and an answer from before the sign-out left behind.
    defaults.set(titledEnvelope, forKey: kAWServerSnapshotKey)

    let outcome = await fetcher().refresh()
    XCTAssertEqual(outcome, .skipped)
    let drawn = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })

    assertSignedOut(drawn)
    XCTAssertNil(fetcher().profile)
  }

  func testEmptyProfileAndEnvelopeDrawSignedOutAndDoNotFetch() async throws {
    // What the app's removal leaves: every key the empty string.
    for key in [
      kAWFetchProfileKey, kAWTokenStateKey, kAWServerSnapshotKey, kAWFetchedAtKey,
      kAWFetchFailuresKey, kAWBackoffUntilKey,
    ] {
      defaults.set("", forKey: key)
    }

    XCTAssertNil(fetcher().profile)
    XCTAssertNil(awStoredString(defaults, kAWServerSnapshotKey))
    let drawn = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })

    assertSignedOut(drawn)
    // Nothing was counted as a failure either: there was no turn to fail.
    XCTAssertEqual(defaults.string(forKey: kAWFetchFailuresKey), "")
  }

  func testEmptyProfileWithATitledEnvelopeDrawsTheEmptySnapshot() async throws {
    // A sign-out that removed the profile but met the extension's answer
    // landing afterwards: the answer is not this (absent) profile's.
    defaults.set("", forKey: kAWFetchProfileKey)
    defaults.set(titledEnvelope, forKey: kAWServerSnapshotKey)

    let drawn = await fetcher().drawnSnapshot(fetch: true, today: { "2025-11-12" })

    assertSignedOut(drawn)
  }
}
