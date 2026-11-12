import Foundation

// The widget self-fetch policy (#50, OPH-461): WIDGETS.md §3.2 "Widget
// self-fetch contract", "The extension's turn", and decision K-11 — when the
// widget extension may ask the server for its own view, how long it backs off,
// when it reloads, and which view it draws.
//
// Pure: no UserDefaults, no Keychain, no network and no clock. The caller reads
// those and passes them in, so RunnerTests can test every rule. Foundation
// only: Runner, the iOS widget and the macOS widget compile this file (the
// macOS widget never fetches; it compiles the shared set as one).
//
// The rule that matters most: a self-fetch never undoes a change made on the
// phone that has not synced yet. The server does not know an outbox entry the
// app has not sent, or a completion from the widget's circle the app has not
// pulled from the queue (AWAlarmActionQueue), so either one keeps the app's own
// snapshot on screen.

// MARK: - App Group keys (WIDGETS.md §3.2)

/// The fetch profile Dart writes; absent = never fetch.
let kAWFetchProfileKey = "aw_widget_fetch_profile"
/// `valid` · `invalid`. Swift writes `invalid` on a 401; Dart `valid` after a mint.
let kAWTokenStateKey = "aw_widget_token_state"
let kAWTokenStateInvalid = "invalid"
/// The last 200 answer, as an `AWServerEnvelope`; never written over Dart's snapshot.
let kAWServerSnapshotKey = "aw_widget_server_snapshot"
/// UTC ms of the last 200 or 304.
let kAWFetchedAtKey = "aw_widget_fetched_at_ms"
/// Failures in a row; 0 after a success.
let kAWFetchFailuresKey = "aw_widget_fetch_failures"
/// UTC ms; no fetch before it.
let kAWBackoffUntilKey = "aw_widget_backoff_until_ms"

// MARK: - Timing

/// No new fetch within this long of the last success: the N widget instances
/// WidgetKit reloads together make one request.
let kAWFetchMinInterval: TimeInterval = 120
/// The first backoff; each failure in a row doubles it, up to the cap.
let kAWBackoffBase: TimeInterval = 300
let kAWBackoffCap: TimeInterval = 7200
/// The widget asks to reload at most this long from now (plus the jitter).
let kAWReloadInterval: TimeInterval = 1800
/// 0–5 minutes, so devices do not all ask the server in the same second.
let kAWReloadJitterMax: TimeInterval = 300
/// Days the widget asks for: today and the next two (the v6 snapshot's days).
let kAWFetchDays = 3

// MARK: - The fetch profile (Dart writes, Swift reads)

/// `aw_widget_fetch_profile`, v1. It decodes only with every field a fetch
/// needs — above all `private`, so "Private widget" not read yet means no
/// profile and no fetch (fail-closed, the OPH-337 rule).
struct AWWidgetFetchProfile: Codable, Equatable {
  struct Scope: Codable, Equatable {
    let workspaceIds: [String]
    /// The user id when the scope is "mine"; absent when solo.
    let mineFor: String?
  }

  struct Patterns: Codable, Equatable {
    let time: String?
    let day: String?
    let dayYear: String?
    let relativeDays: Bool?
  }

  let v: Int
  /// No trailing `/`; `/api/v1/…` is appended.
  let baseUrl: String
  let scope: Scope
  /// "Private widget" as the app read it.
  let isPrivate: Bool
  let locale: String?
  let patterns: Patterns?
  let strings: [String: String]?
  /// Outbox entries the app has not sent to the server yet.
  let pendingOutbox: Int?
  /// When the app last wrote `aw_widget_snapshot`, UTC ms.
  let localWrittenAtMs: Int?

  enum CodingKeys: String, CodingKey {
    case v, baseUrl, scope, locale, patterns, strings, pendingOutbox, localWrittenAtMs
    case isPrivate = "private"
  }

  /// The profile from its stored JSON; nil when absent or incomplete.
  static func decode(_ raw: String?) -> AWWidgetFetchProfile? {
    guard let raw, let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(AWWidgetFetchProfile.self, from: data)
  }
}

/// The query string a profile asks `GET /widget/snapshot` with, in the
/// contract's order. The envelope keeps it: a view fetched for another scope
/// or privacy setting is not this profile's view.
func awSnapshotQuery(profile: AWWidgetFetchProfile, timeZone: String) -> String {
  let ids = profile.scope.workspaceIds.map(awQueryEscape).joined(separator: ",")
  return [
    "tz=\(awQueryEscape(timeZone))",
    "workspaceIds=\(ids)",
    "mine=\(profile.scope.mineFor == nil ? 0 : 1)",
    "private=\(profile.isPrivate ? 1 : 0)",
    "days=\(kAWFetchDays)",
  ].joined(separator: "&")
}

/// RFC 3986 unreserved characters only, so `/` in a zone id is `%2F`.
private let kAWQueryUnreserved = CharacterSet(
  charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

private func awQueryEscape(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: kAWQueryUnreserved) ?? ""
}

// MARK: - The server's view (`GET /widget/snapshot` 200 body)

/// The 200 body: language-free day views. Words, the header and every label
/// come from Dart's snapshot and profile, never from the server.
struct AWServerSnapshot: Codable {
  let v: Int
  /// The server's clock; informative only (the choice compares device clocks).
  let generatedAt: String?
  let tz: String?
  /// `days[0]` is today in `tz`.
  let days: [AWServerDay]
}

struct AWServerDay: Codable {
  /// The local day, `yyyy-MM-dd`.
  let date: String
  let openToday: Int?
  let next: AWServerNext?
  let buckets: [AWServerBucket]?
  let views: [String: AWServerView]?
}

/// One project's own view of a day.
struct AWServerView: Codable {
  let openToday: Int?
  let next: AWServerNext?
  let buckets: [AWServerBucket]?
}

struct AWServerBucket: Codable {
  let key: String
  /// Open rows only.
  let count: Int
  /// Open entries past the rows; absent at 0.
  let more: Int?
  let items: [AWServerItem]
}

struct AWServerItem: Codable {
  let id: String
  /// Absent when the profile is private.
  let title: String?
  let done: Bool
  let priority: String?
  let projectColor: String?
  /// `"event"` for a calendar event, absent for a task.
  let kind: String?
  let day: String?
  let dueAt: String?
  let endAt: String?
  let allDay: Bool?
  /// How the row's time is spelled; absent = no label.
  let timeStyle: String?
}

struct AWServerNext: Codable {
  let id: String
  let title: String?
  let bucket: String
  let dueAt: String?
  let timeStyle: String?
}

/// `aw_widget_server_snapshot`: the last 200 answer with what the next request
/// and the choice need. `body` stays a JSON tree, so a field this build does
/// not know survives a rewrite (the OPH-187 stance).
struct AWServerEnvelope {
  /// When the device received it, UTC ms on the device's clock.
  let fetchedAtMs: Int
  let etag: String
  /// The exact query string it was fetched with.
  let query: String
  let body: [String: Any]

  init(fetchedAtMs: Int, etag: String, query: String, body: [String: Any]) {
    self.fetchedAtMs = fetchedAtMs
    self.etag = etag
    self.query = query
    self.body = body
  }

  /// The envelope from its stored JSON; nil when absent or malformed.
  init?(json raw: String?) {
    guard
      let raw, let data = raw.data(using: .utf8),
      let tree = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let fetchedAtMs = tree["fetchedAtMs"] as? Int,
      let etag = tree["etag"] as? String,
      let query = tree["query"] as? String,
      let body = tree["body"] as? [String: Any]
    else { return nil }
    self.init(fetchedAtMs: fetchedAtMs, etag: etag, query: query, body: body)
  }

  /// The JSON to store; nil when the body cannot be serialised.
  var json: String? {
    let tree: [String: Any] = [
      "fetchedAtMs": fetchedAtMs, "etag": etag, "query": query, "body": body,
    ]
    guard
      JSONSerialization.isValidJSONObject(tree),
      let data = try? JSONSerialization.data(withJSONObject: tree)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// The server's view with every completion still queued for the app laid over
/// it as done, by `awMarkSnapshotDone`'s rules (done in today's view, gone from
/// a later day's, one fewer in its bucket and the open count, `next` moved on).
/// Nil when the body does not decode or carries no day.
func awServerView(
  _ envelope: AWServerEnvelope, pendingCompletionTaskIds: [String], today: String?
) -> AWServerSnapshot? {
  var body = envelope.body
  if awApplyPendingCompletions(&body, taskIds: pendingCompletionTaskIds, today: today) {
    awRestoreMovedNext(&body)
  }
  guard
    JSONSerialization.isValidJSONObject(body),
    let data = try? JSONSerialization.data(withJSONObject: body),
    let view = try? JSONDecoder().decode(AWServerSnapshot.self, from: data),
    !view.days.isEmpty
  else { return nil }
  return view
}

/// `awMarkSnapshotDone` moves `next` to the following open row in the shape
/// Dart's snapshot uses (a drawn `time`, a `title` of "" when the row had
/// none). The server's `next` carries the row's own `dueAt` and `timeStyle`,
/// and no `title` when private: copy them from the row it names.
private func awRestoreMovedNext(_ body: inout [String: Any]) {
  guard var days = body["days"] as? [[String: Any]] else { return }
  for d in days.indices {
    awRestoreNext(in: &days[d])
    if var views = days[d]["views"] as? [String: Any] {
      for (key, value) in views {
        guard var view = value as? [String: Any] else { continue }
        awRestoreNext(in: &view)
        views[key] = view
      }
      days[d]["views"] = views
    }
  }
  body["days"] = days
}

private func awRestoreNext(in view: inout [String: Any]) {
  guard var next = view["next"] as? [String: Any], let id = next["id"] as? String else { return }
  let rows = (view["buckets"] as? [[String: Any]] ?? []).flatMap {
    $0["items"] as? [[String: Any]] ?? []
  }
  guard let row = rows.first(where: { $0["id"] as? String == id }) else { return }
  for key in ["title", "dueAt", "timeStyle"] { next[key] = row[key] }
  next.removeValue(forKey: "label")
  next.removeValue(forKey: "time")
  view["next"] = next
}

// MARK: - The choice (K-11)

/// Why the app's own snapshot is drawn.
enum AWLocalReason: Equatable {
  /// The app has written no snapshot: today's behaviour.
  case noLocalSnapshot
  /// No envelope, one fetched for another query, or a body this build cannot read.
  case noServerView
  /// The outbox holds a change the server has not seen.
  case pendingOutbox
  /// A completion from the widget's circle is still queued for the app.
  case pendingCompletion
  /// The app wrote its snapshot at or after the fetch (or its time is unknown).
  case localNewer
}

enum AWSnapshotChoice {
  /// Draw `aw_widget_snapshot`, the app's own view.
  case local(AWLocalReason)
  /// Draw the server's days, queued completions laid over them.
  case server(AWServerSnapshot)

  var localReason: AWLocalReason? {
    if case .local(let reason) = self { return reason }
    return nil
  }

  var serverView: AWServerSnapshot? {
    if case .server(let view) = self { return view }
    return nil
  }
}

/// Which view the widget draws (WIDGETS.md §3.2 step 5, decision K-11).
///
/// The app's snapshot unless every one of these holds: it exists; the envelope
/// was fetched with the current profile's `query` and decodes; the outbox is
/// empty; no completion from the circle is queued; and the fetch is strictly
/// newer than the app's last write. Both stamps are the device's own clock —
/// the server's `generatedAt` is never compared. A self-fetch never undoes a
/// local change.
func awPickSnapshot(
  local: AWSnapshot?, localWrittenAtMs: Int?, server: AWServerEnvelope?, query: String?,
  pendingCompletionTaskIds: [String], pendingOutbox: Int, today: String?
) -> AWSnapshotChoice {
  guard local != nil else { return .local(.noLocalSnapshot) }
  guard
    let server, let query, server.query == query,
    let view = awServerView(
      server, pendingCompletionTaskIds: pendingCompletionTaskIds, today: today)
  else { return .local(.noServerView) }
  if pendingOutbox > 0 { return .local(.pendingOutbox) }
  if !pendingCompletionTaskIds.isEmpty { return .local(.pendingCompletion) }
  guard let localWrittenAtMs, localWrittenAtMs < server.fetchedAtMs else {
    return .local(.localNewer)
  }
  return .server(view)
}

// MARK: - When to fetch

/// UTC ms, as the App Group stamps are written.
func awMs(_ date: Date) -> Int {
  Int((date.timeIntervalSince1970 * 1000).rounded(.down))
}

/// Whether this timeline turn may make its one request (WIDGETS.md §3.2 step 2).
///
/// Never without a snapshot from the app, a profile that decoded (with its
/// `private` flag) and a workspace to ask for, a token the Keychain gave and
/// the server has not refused. Not inside the backoff, and not within two
/// minutes of the last success. A stamp later than any honest one could be —
/// the device clock was set back — is ignored rather than blocking for as long
/// as the clock was moved.
func awShouldFetch(
  now: Date, hasLocalSnapshot: Bool, profile: AWWidgetFetchProfile?, tokenState: String?,
  tokenReadable: Bool, lastSuccessAtMs: Int?, backoffUntilMs: Int?
) -> Bool {
  guard
    hasLocalSnapshot, let profile, !profile.scope.workspaceIds.isEmpty,
    tokenState != kAWTokenStateInvalid, tokenReadable
  else { return false }
  let nowMs = awMs(now)
  if let until = backoffUntilMs, until > nowMs, until <= nowMs + Int(kAWBackoffCap * 1000) {
    return false
  }
  if let last = lastSuccessAtMs, last <= nowMs, nowMs - last < Int(kAWFetchMinInterval * 1000) {
    return false
  }
  return true
}

/// The backoff after a failure: min(5 min · 2ⁿ, 2 h), n = the failures in a
/// row before this one.
func awNextBackoff(_ failuresBefore: Int) -> TimeInterval {
  // 2⁵ · 5 min is already past the cap; stop doubling there.
  let steps = min(max(failuresBefore, 0), 5)
  return min(kAWBackoffBase * Double(1 << steps), kAWBackoffCap)
}

// MARK: - When to reload

/// A reload jitter, 0–5 minutes.
func awReloadJitter() -> TimeInterval {
  TimeInterval.random(in: 0...kAWReloadJitterMax)
}

private func awClampJitter(_ jitter: TimeInterval) -> TimeInterval {
  guard jitter.isFinite else { return 0 }
  return min(max(jitter, 0), kAWReloadJitterMax)
}

/// `.after` for a home-screen timeline: when the minute entries run out, but
/// no later than 30 minutes plus the jitter from now.
func awReloadDate(now: Date, clockHorizon: Date, jitter: TimeInterval) -> Date {
  min(clockHorizon, now.addingTimeInterval(kAWReloadInterval + awClampJitter(jitter)))
}

/// The midnight reload: the next 00:01 after `date`, plus the jitter, so every
/// device does not ask the server in the same minute.
func awMidnightReloadDate(after date: Date, calendar: Calendar, jitter: TimeInterval) -> Date? {
  calendar.nextDate(
    after: date, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
  )?.addingTimeInterval(awClampJitter(jitter))
}
