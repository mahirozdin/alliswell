import Foundation
import Security

// The widget's self-fetch (#50, OPH-462): WIDGETS.md §3.2 "Widget self-fetch
// contract", "The extension's turn" steps 1–5. With the app swiped away no
// Dart runs on iOS (no BGAppRefresh, no silent push — decision K-12), so the
// widget extension asks `GET /api/v1/widget/snapshot` itself, with the
// read-only widget token Dart keeps in the shared Keychain group.
//
// The policy (when to fetch, the backoff, the local-or-server choice) is the
// pure AWWidgetFetchPolicy.swift; this file does the I/O around it — the
// Keychain read, the one request, the App Group stamps — and spells the
// server's language-free view in the app's words. The session and the token
// reader are injected, so RunnerTests drives it through a URLProtocol stub.
//
// Runner and the iOS widget compile this file; the macOS widget compiles it
// with the shared set but never calls it (its self-fetch is a later candidate).
// The extension never writes, deletes or logs the token.

// MARK: - Shared identifiers (WIDGETS.md §3.2)

/// Dart's own snapshot. Swift reads it and never writes a server view over it.
let kAWLocalSnapshotKey = "aw_widget_snapshot"

/// The Keychain item Dart's `WidgetTokenStore` writes (flutter_secure_storage:
/// its default service, the key as the account, the App Group as the access
/// group with no team prefix).
let kAWWidgetTokenService = "flutter_secure_storage_service"
let kAWWidgetTokenAccount = "aw_widget_token"
let kAWWidgetTokenAccessGroup = "group.com.alliswell.alliswell"

/// The one route a widget token opens.
let kAWWidgetSnapshotPath = "/api/v1/widget/snapshot"

// MARK: - The Keychain read

/// The `SecItemCopyMatching` query for the widget token: class, service,
/// account, access group, the data, one match.
func awWidgetTokenQuery() -> [String: Any] {
  [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: kAWWidgetTokenService,
    kSecAttrAccount as String: kAWWidgetTokenAccount,
    kSecAttrAccessGroup as String: kAWWidgetTokenAccessGroup,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
  ]
}

/// The widget token, or nil: not minted (`errSecItemNotFound`), the phone not
/// unlocked once since it started (`errSecInteractionNotAllowed`), or anything
/// else the Keychain says. Every nil means the same thing — no fetch, nothing
/// written — and nothing about the item is logged.
func awReadWidgetToken() -> String? {
  var out: CFTypeRef?
  let status = SecItemCopyMatching(awWidgetTokenQuery() as CFDictionary, &out)
  guard
    status == errSecSuccess, let data = out as? Data,
    let token = String(data: data, encoding: .utf8), !token.isEmpty
  else { return nil }
  return token
}

// MARK: - The fetcher

/// What one turn's fetch did.
enum AWWidgetFetchOutcome: Equatable {
  /// No request: a precondition did not hold (step 2).
  case skipped
  /// 200: a new envelope is stored.
  case stored
  /// 304: the stored envelope still holds; its stamp moved on.
  case notModified
  /// 401: the token is refused; no fetch until the app mints a new one.
  case unauthorized
  /// Anything else, a timeout or no network: backed off.
  case failed
  /// An answer for a profile that is no longer current — "Private widget",
  /// the scope or the server changed while it was on its way: nothing is
  /// written, neither a success nor a failure, so the next turn asks again.
  case discarded
}

/// A redirect is answered as the failure it is: the token goes to the
/// `baseUrl` the app wrote and nowhere else.
private final class AWNoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// Makes "read the stamps, decide, claim the request" one step for every
/// turn in this process — WidgetKit builds the timelines of several widgets
/// at once, on several threads (#50).
private let awFetchClaimLock = NSLock()

struct AWWidgetFetcher {
  /// The App Group's defaults.
  let defaults: UserDefaults
  let session: URLSession
  /// The widget token from the Keychain; nil = no fetch.
  let readToken: () -> String?
  var now: () -> Date = Date.init
  /// The IANA zone the server cuts days in — the one the timeline draws in.
  var timeZone: String = TimeZone.current.identifier

  /// Step 3: ephemeral (no cache, no cookies), 6 s for a response to start,
  /// 8 s for the whole request, and no waiting for a network that is not there
  /// — WidgetKit gives the extension seconds, not minutes.
  static func sessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 6
    configuration.timeoutIntervalForResource = 8
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    return configuration
  }

  /// The fetcher a widget turn uses: the App Group, a fresh ephemeral session
  /// and the Keychain. The caller invalidates the session after the turn.
  static func live() -> AWWidgetFetcher? {
    guard let defaults = UserDefaults(suiteName: kAWWidgetTokenAccessGroup) else { return nil }
    return AWWidgetFetcher(
      defaults: defaults, session: URLSession(configuration: sessionConfiguration()),
      readToken: awReadWidgetToken)
  }

  var profile: AWWidgetFetchProfile? {
    AWWidgetFetchProfile.decode(awStoredString(defaults, kAWFetchProfileKey))
  }

  /// One fetch, when the contract allows one (steps 2–4). Never throws: every
  /// failure leaves the App Group snapshot to be drawn.
  @discardableResult
  func refresh() async -> AWWidgetFetchOutcome {
    guard let claimed = claim() else { return .skipped }
    // Released when the turn is done with the answer, after its stamps are
    // written, so the next turn reads them and does not ask again.
    defer { release(claimed.claimMs) }
    let profile = claimed.profile
    let query = claimed.query
    let current = claimed.current
    let token = claimed.token

    guard let url = awWidgetSnapshotURL(baseUrl: profile.baseUrl, query: query) else {
      return .skipped
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let usable = current.flatMap { $0.etag.isEmpty ? nil : $0 }
    if let usable { request.setValue(usable.etag, forHTTPHeaderField: "If-None-Match") }

    let data: Data
    let response: HTTPURLResponse
    do {
      let (body, raw) = try await session.data(for: request, delegate: AWNoRedirects())
      guard let http = raw as? HTTPURLResponse else { return failed() }
      data = body
      response = http
    } catch {
      return failed()
    }

    // The app may have changed the profile while the request was out — above
    // all turned "Private widget" on and removed the server view: an answer
    // asked with the old profile is not this profile's, and writing it back
    // would put titles into the App Group again (WIDGETS.md §9).
    guard isCurrent(profile, query: query) else { return .discarded }
    // The circle was pressed while the request was out: the view drawn at the
    // press stays drawn (#50). Neither a success nor a failure, so once the
    // completion has synced and 90 s have passed the next turn asks again.
    guard !completionHoldsTheView() else { return .discarded }

    // The device's clock when the answer came: what the choice compares with
    // the app's own write (K-11), never the server's `generatedAt`.
    let receivedMs = awMs(now())
    switch response.statusCode {
    case 200:
      // A body this build cannot draw is a failure, not an envelope.
      guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      else { return failed() }
      let envelope = AWServerEnvelope(
        fetchedAtMs: receivedMs, etag: response.value(forHTTPHeaderField: "ETag") ?? "",
        query: query, body: body)
      guard
        awServerView(envelope, pendingCompletionTaskIds: [], today: nil) != nil,
        let json = envelope.json
      else { return failed() }
      guard store(json, for: profile, query: query) else { return .discarded }
      succeeded(at: receivedMs)
      return .stored
    case 304:
      if let usable, let json = AWServerEnvelope(
        fetchedAtMs: receivedMs, etag: usable.etag, query: usable.query, body: usable.body
      ).json {
        guard store(json, for: profile, query: query) else { return .discarded }
      }
      succeeded(at: receivedMs)
      return .notModified
    case 401:
      defaults.set(kAWTokenStateInvalid, forKey: kAWTokenStateKey)
      return .unauthorized
    default:
      return failed()
    }
  }

  /// What a turn that may fetch read, and the claim it holds.
  private struct Claimed {
    let profile: AWWidgetFetchProfile
    let query: String
    /// The stored envelope for this query, if any.
    let current: AWServerEnvelope?
    let token: String
    let claimMs: Int
  }

  /// Step 2 and the claim, as one step under the process's lock: reads the
  /// stamps, decides, and when the turn may fetch writes its claim before any
  /// other turn can read the stamps (#50). Nil = no request this turn.
  private func claim() -> Claimed? {
    awFetchClaimLock.lock()
    defer { awFetchClaimLock.unlock() }
    let start = now()
    let profile = self.profile
    let hasLocal = awStoredString(defaults, kAWLocalSnapshotKey) != nil
    let tokenState = awStoredString(defaults, kAWTokenStateKey)
    let lastSuccess = defaults.object(forKey: kAWFetchedAtKey) as? Int
    let backoffUntil = defaults.object(forKey: kAWBackoffUntilKey) as? Int
    let query = profile.map { awSnapshotQuery(profile: $0, timeZone: timeZone) }
    // An envelope fetched with another query is not used, not even here.
    let stored = AWServerEnvelope(json: awStoredString(defaults, kAWServerSnapshotKey))
    let current = stored.flatMap { $0.query == query ? $0 : nil }
    // Everything but the token first: the Keychain is read only for a turn
    // that would fetch.
    guard
      awShouldFetch(
        now: start, hasLocalSnapshot: hasLocal, profile: profile, tokenState: tokenState,
        tokenReadable: true, lastSuccessAtMs: lastSuccess, backoffUntilMs: backoffUntil,
        hasServerView: current != nil,
        pendingCompletion: !awQueuedCompletionTaskIds(in: defaults).isEmpty,
        completedAtMs: defaults.object(forKey: kAWCompletedAtKey) as? Int,
        fetchClaimMs: defaults.object(forKey: kAWFetchClaimKey) as? Int),
      let profile, let query, let token = readToken()
    else { return nil }
    let claimMs = awMs(start)
    defaults.set(claimMs, forKey: kAWFetchClaimKey)
    return Claimed(profile: profile, query: query, current: current, token: token, claimMs: claimMs)
  }

  /// Ends this turn's claim, unless a later turn already holds its own.
  private func release(_ claimMs: Int) {
    awFetchClaimLock.lock()
    defer { awFetchClaimLock.unlock() }
    if defaults.object(forKey: kAWFetchClaimKey) as? Int == claimMs {
      defaults.removeObject(forKey: kAWFetchClaimKey)
    }
  }

  /// Writes `json` as the server view, then looks at the profile again. The
  /// app writes its new profile before it removes the old view (WIDGETS.md
  /// §3.2), and it can land between the check above and this write — in
  /// another process, nothing makes the two one step. So a profile changed
  /// by now means the write is the old profile's: it is taken back (unless
  /// something newer already replaced it) and false is returned. Either the
  /// app's removal or this one catches every order (WIDGETS.md §9).
  ///
  /// A press of the circle can land in the same gap (#50): then the write is
  /// taken back to the view stored before it, so the rows drawn at the press
  /// stay where they were.
  private func store(_ json: String, for profile: AWWidgetFetchProfile, query: String) -> Bool {
    let previous = defaults.string(forKey: kAWServerSnapshotKey)
    defaults.set(json, forKey: kAWServerSnapshotKey)
    let current = isCurrent(profile, query: query)
    if current && !completionHoldsTheView() { return true }
    if defaults.string(forKey: kAWServerSnapshotKey) == json {
      if current, let previous {
        defaults.set(previous, forKey: kAWServerSnapshotKey)
      } else {
        defaults.removeObject(forKey: kAWServerSnapshotKey)
      }
    }
    return false
  }

  /// `awCompletionHoldsTheView` over what the App Group holds now.
  private func completionHoldsTheView() -> Bool {
    awCompletionHoldsTheView(
      now: now(), pendingCompletion: !awQueuedCompletionTaskIds(in: defaults).isEmpty,
      completedAtMs: defaults.object(forKey: kAWCompletedAtKey) as? Int)
  }

  /// Whether the stored profile still asks what `profile` asked, of the same
  /// server.
  private func isCurrent(_ profile: AWWidgetFetchProfile, query: String) -> Bool {
    guard let current = self.profile else { return false }
    return current.baseUrl == profile.baseUrl
      && awSnapshotQuery(profile: current, timeZone: timeZone) == query
  }

  private func succeeded(at ms: Int) {
    defaults.set(ms, forKey: kAWFetchedAtKey)
    defaults.set(0, forKey: kAWFetchFailuresKey)
    defaults.removeObject(forKey: kAWBackoffUntilKey)
  }

  /// Failures + 1, and no fetch for min(5 min · 2ⁿ, 2 h), n = the failures
  /// before this one.
  private func failed() -> AWWidgetFetchOutcome {
    let before = max(defaults.object(forKey: kAWFetchFailuresKey) as? Int ?? 0, 0)
    defaults.set(before + 1, forKey: kAWFetchFailuresKey)
    let until = now().addingTimeInterval(awNextBackoff(before))
    defaults.set(awMs(until), forKey: kAWBackoffUntilKey)
    return .failed
  }

  /// One turn's drawn snapshot: the fetch when `fetch` (and the contract)
  /// allow it, then the choice over the app's snapshot read AFTER it. The
  /// app may write its snapshot and its outbox count while the request is
  /// out; the choice reads the new count, so it must draw the new snapshot
  /// too, or a change still waiting to sync comes back undone.
  func drawnSnapshot(fetch: Bool, today: () -> String) async -> AWSnapshot {
    await turn(fetch: fetch, today: today).snapshot
  }

  /// `drawnSnapshot`, and whether this turn's fetch changed the stored
  /// server view — then the other widgets reload to draw it too, so two
  /// widgets on one screen never show two views (#50, PR2-09).
  func turn(fetch: Bool, today: () -> String) async -> (snapshot: AWSnapshot, changed: Bool) {
    var changed = false
    if fetch {
      let before = AWServerEnvelope(json: awStoredString(defaults, kAWServerSnapshotKey))
      let outcome = await refresh()
      let after = AWServerEnvelope(json: awStoredString(defaults, kAWServerSnapshotKey))
      changed = awFetchChangedTheView(outcome, before: before, after: after)
    }
    let day = today()
    let snapshot = snapshotToDraw(
      local: awLoadLocalSnapshot(in: defaults, today: day), today: day)
    return (snapshot, changed)
  }

  /// The choice (step 5, K-11) for `local`, the app's snapshot as the widget
  /// read it (queued completions already applied).
  func choice(local: AWSnapshot, today: String) -> AWSnapshotChoice {
    let profile = self.profile
    let hasLocal = awStoredString(defaults, kAWLocalSnapshotKey) != nil
    return awPickSnapshot(
      local: hasLocal ? local : nil, localWrittenAtMs: profile?.localWrittenAtMs,
      server: AWServerEnvelope(json: awStoredString(defaults, kAWServerSnapshotKey)),
      query: profile.map { awSnapshotQuery(profile: $0, timeZone: timeZone) },
      pendingCompletionTaskIds: awQueuedCompletionTaskIds(in: defaults),
      pendingOutbox: profile?.pendingOutbox ?? 0, today: today)
  }

  /// What the widget draws: the app's snapshot, or the server's days in the
  /// app's words when the choice says so.
  func snapshotToDraw(local: AWSnapshot, today: String) -> AWSnapshot {
    guard
      case .server(let view) = choice(local: local, today: today), let profile
    else { return local }
    return awSnapshotFromServer(
      view, local: local, profile: profile,
      timeZone: TimeZone(identifier: timeZone) ?? .current)
  }
}

/// `{baseUrl}/api/v1/widget/snapshot?{query}`; nil for a base that is not an
/// http(s) URL.
func awWidgetSnapshotURL(baseUrl: String, query: String) -> URL? {
  var base = baseUrl
  while base.hasSuffix("/") { base.removeLast() }
  guard
    let url = URL(string: "\(base)\(kAWWidgetSnapshotPath)?\(query)"),
    let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
    url.host != nil
  else { return nil }
  return url
}

/// The app's snapshot as it stands in `defaults` now, with every completion
/// from the circle the app has not pulled yet applied to it (OPH-451,
/// IOS-08): the app rewrites the snapshot from its own data, which still has
/// the task open until it pulls the queue, so without this a rewrite in
/// between would put the tapped row back. `.empty` when there is none.
func awLoadLocalSnapshot(in defaults: UserDefaults, today: String) -> AWSnapshot {
  guard
    let raw = awStoredString(defaults, kAWLocalSnapshotKey),
    var data = raw.data(using: .utf8)
  else { return .empty }
  let queued = awQueuedCompletionTaskIds(in: defaults)
  if !queued.isEmpty,
    var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    awApplyPendingCompletions(&json, taskIds: queued, today: today),
    let out = try? JSONSerialization.data(withJSONObject: json)
  {
    data = out
  }
  return (try? JSONDecoder().decode(AWSnapshot.self, from: data)) ?? .empty
}

/// The intent's stamp (WIDGETS.md §3.2, `aw_widget_completed_at_ms`): the
/// circle completed a task at `date`. For 90 s no turn fetches (#50, PR2-03).
func awStampWidgetCompletion(in defaults: UserDefaults?, at date: Date = Date()) {
  defaults?.set(awMs(date), forKey: kAWCompletedAtKey)
}

/// The task ids of every completion from the widget's circle still queued
/// for the app.
func awQueuedCompletionTaskIds(in defaults: UserDefaults) -> [String] {
  AWAlarmActionQueue.pending(in: defaults)
    .filter { $0.action == "complete" }
    .flatMap(\.taskIds)
}

// MARK: - The server's view in the app's words

/// The server's days as a v6 snapshot the widget already knows how to draw.
///
/// The server sends no words (WIDGETS.md §3.2): the chrome — `strings`,
/// `lists`, `clockFormat`, `density`, `locale` — is the app's snapshot's;
/// bucket labels, the private title and the relative-day words are the
/// profile's `strings`; every time label is spelled here from the row's
/// `timeStyle` with the profile's ICU `patterns` in the server's `tz`; the
/// open-count words come from `strings.openTodayPattern`.
func awSnapshotFromServer(
  _ view: AWServerSnapshot, local: AWSnapshot, profile: AWWidgetFetchProfile, timeZone: TimeZone
) -> AWSnapshot {
  let zone = view.tz.flatMap(TimeZone.init(identifier:)) ?? timeZone
  let words = AWServerWords(
    profile: profile, localStrings: local.strings ?? [:],
    locale: Locale(identifier: profile.locale ?? local.locale), timeZone: zone,
    localBuckets: local.buckets, localRowIds: local.rowIds)

  let days = view.days.map { words.day($0) }
  guard let day0 = days.first else { return local }
  var strings = local.strings ?? [:]
  strings["openToday"] = day0.openTodayLabel
  return AWSnapshot(
    v: max(local.v, 6),
    generatedAt: local.generatedAt.isEmpty ? (view.generatedAt ?? "") : local.generatedAt,
    locale: local.locale, date: day0.header ?? local.date, strings: strings,
    openToday: day0.openToday, clockFormat: local.clockFormat, buckets: day0.buckets ?? [],
    next: day0.next, lists: local.lists, views: day0.views, density: local.density, days: days)
}

/// The formatters and words one conversion uses.
private struct AWServerWords {
  let strings: [String: String]
  let patterns: AWWidgetFetchProfile.Patterns?
  let calendar: Calendar
  let instant = ISO8601DateFormatter()
  let instantFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  let dayKey: DateFormatter
  let timeFormatter: DateFormatter
  let dayFormatter: DateFormatter
  let dayYearFormatter: DateFormatter
  let weekday: DateFormatter
  let dayNumber: DateFormatter
  let month: DateFormatter
  let openTodayPattern: String?
  /// The app's own label for a bucket key, for a profile without the word.
  let localLabels: [String: String]
  /// Every row the app's snapshot holds; a task outside it is `serverOnly`.
  let localRowIds: Set<String>

  init(
    profile: AWWidgetFetchProfile, localStrings: [String: String], locale: Locale,
    timeZone: TimeZone, localBuckets: [AWBucket], localRowIds: Set<String>
  ) {
    self.localRowIds = localRowIds
    strings = profile.strings ?? [:]
    patterns = profile.patterns
    openTodayPattern = localStrings["openTodayPattern"]
    var labels: [String: String] = [:]
    for bucket in localBuckets where labels[bucket.key] == nil { labels[bucket.key] = bucket.label }
    localLabels = labels
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    calendar = gregorian

    func formatter(_ pattern: String?, template: String) -> DateFormatter {
      let f = DateFormatter()
      f.locale = locale
      f.timeZone = timeZone
      f.calendar = gregorian
      if let pattern, !pattern.isEmpty {
        f.dateFormat = pattern
      } else {
        f.setLocalizedDateFormatFromTemplate(template)
      }
      return f
    }
    let key = DateFormatter()
    key.locale = Locale(identifier: "en_US_POSIX")
    key.timeZone = timeZone
    key.calendar = gregorian
    key.dateFormat = "yyyy-MM-dd"
    dayKey = key
    timeFormatter = {
      if let pattern = profile.patterns?.time, !pattern.isEmpty {
        return formatter(pattern, template: "")
      }
      // No pattern: the locale's own short time, never a guessed 24-hour one.
      let f = DateFormatter()
      f.locale = locale
      f.timeZone = timeZone
      f.dateStyle = .none
      f.timeStyle = .short
      return f
    }()
    dayFormatter = formatter(profile.patterns?.day, template: "dMMM")
    dayYearFormatter = formatter(
      profile.patterns?.dayYear ?? profile.patterns?.day, template: "dMMMy")
    weekday = formatter("EEEE", template: "")
    dayNumber = formatter("d", template: "")
    month = formatter("MMMM", template: "")
  }

  func parseInstant(_ text: String?) -> Date? {
    guard let text else { return nil }
    return instantFraction.date(from: text) ?? instant.date(from: text)
  }

  /// A `yyyy-MM-dd` day's first minute in the zone.
  func parseDay(_ text: String?) -> Date? {
    guard let text else { return nil }
    return dayKey.date(from: text)
  }

  func time(_ date: Date) -> String { timeFormatter.string(from: date) }

  /// day(): `dayYear` for another year than the view's.
  func day(_ date: Date, viewDate: Date?) -> String {
    let year = calendar.component(.year, from: date)
    let viewYear = viewDate.map { calendar.component(.year, from: $0) } ?? year
    return (year == viewYear ? dayFormatter : dayYearFormatter).string(from: date)
  }

  /// A row's time label from its `timeStyle` (WIDGETS.md §3.2); nil = none.
  func label(
    style: String?, dueAt: String?, endAt: String?, eventDay: String?, allDay: Bool,
    viewDate: Date?
  ) -> String? {
    let due = parseInstant(dueAt)
    let end = parseInstant(endAt)
    switch style {
    case "time", "start":
      return due.map(time)
    case "day":
      if allDay, let date = parseDay(eventDay) { return day(date, viewDate: viewDate) }
      return due.map { day($0, viewDate: viewDate) }
    case "allDay":
      return strings["allDay"]
    case "range":
      guard let due, let end else { return due.map(time) }
      return "\(time(due))–\(time(end))"
    case "end":
      return end.map { "–\(time($0))" }
    case "dayTime":
      guard let due else { return nil }
      let full = "\(day(due, viewDate: viewDate)), \(time(due))"
      guard patterns?.relativeDays == true, let viewDate else { return full }
      let offset = calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: viewDate), to: calendar.startOfDay(for: due)
      ).day ?? Int.min
      let word: String?
      switch offset {
      case 0: return time(due)
      case 1: word = strings["tomorrow"]
      case -1: word = strings["yesterday"]
      default: word = nil
      }
      guard let word, !word.isEmpty else { return full }
      return "\(word)\u{00A0}\(time(due))"
    default:
      return nil
    }
  }

  func bucketLabel(_ key: String) -> String {
    if let word = strings["bucket.\(key)"], !word.isEmpty { return word }
    return localLabels[key] ?? ""
  }

  func openLabel(_ count: Int?) -> String? {
    guard let count, let pattern = openTodayPattern, pattern.contains("{count}") else {
      return nil
    }
    return pattern.replacingOccurrences(of: "{count}", with: String(count))
  }

  func title(_ title: String?, event: Bool) -> String {
    if let title { return title }
    return strings[event ? "privateEvent" : "privateTitle"] ?? ""
  }

  func row(_ item: AWServerItem, viewDate: Date?) -> AWTaskRow {
    let event = item.kind == "event"
    return AWTaskRow(
      id: item.id, title: title(item.title, event: event), done: item.done,
      priority: item.priority ?? "none",
      time: label(
        style: item.timeStyle, dueAt: item.dueAt, endAt: item.endAt, eventDay: item.day,
        allDay: item.allDay == true, viewDate: viewDate),
      projectColor: item.projectColor, kind: item.kind, day: item.day,
      serverOnly: event || localRowIds.contains(item.id) ? nil : true)
  }

  func bucket(_ bucket: AWServerBucket, viewDate: Date?) -> AWBucket {
    AWBucket(
      key: bucket.key, label: bucketLabel(bucket.key), count: bucket.count,
      items: bucket.items.map { row($0, viewDate: viewDate) }, more: bucket.more)
  }

  func next(_ next: AWServerNext?, viewDate: Date?) -> AWNextTask? {
    guard let next else { return nil }
    return AWNextTask(
      id: next.id, title: title(next.title, event: false), bucket: next.bucket,
      label: bucketLabel(next.bucket),
      time: label(
        style: next.timeStyle, dueAt: next.dueAt, endAt: nil, eventDay: nil, allDay: false,
        viewDate: viewDate))
  }

  func listView(_ view: AWServerView, viewDate: Date?) -> AWListView {
    AWListView(
      openToday: view.openToday, openTodayLabel: openLabel(view.openToday),
      next: next(view.next, viewDate: viewDate),
      buckets: (view.buckets ?? []).map { bucket($0, viewDate: viewDate) })
  }

  func day(_ day: AWServerDay) -> AWDayView {
    let date = parseDay(day.date)
    let header = date.map {
      AWDate(
        weekday: weekday.string(from: $0), day: dayNumber.string(from: $0),
        month: month.string(from: $0))
    }
    return AWDayView(
      date: day.date, header: header, openToday: day.openToday,
      openTodayLabel: openLabel(day.openToday), next: next(day.next, viewDate: date),
      buckets: (day.buckets ?? []).map { bucket($0, viewDate: date) },
      views: day.views?.mapValues { listView($0, viewDate: date) })
  }
}
