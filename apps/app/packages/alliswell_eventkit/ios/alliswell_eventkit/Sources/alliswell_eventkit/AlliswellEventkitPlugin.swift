import EventKit

// One source file for BOTH platforms: EventKit is identical on iOS and macOS,
// only Flutter's module name and messenger accessor differ. `macos/…/Sources`
// is a symlink to this directory — do not duplicate this file.
#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// The Apple half of BLUEPRINT §7.3 (OPH-077 permission+list, OPH-078 CRUD).
/// Apple publishes no server-side calendar API, so unlike Google — which syncs
/// on our server — this bridge is per-device by nature: it runs where the
/// calendar lives.
///
/// Deliberately dumb. It requests access, lists calendars, and writes exactly
/// the event Dart tells it to. Every DECISION (what mirrors, when, which
/// calendar, conflict handling) stays in Dart, where it is pure and testable.
/// Native code we cannot easily unit-test holds no policy.
public class AlliswellEventkitPlugin: NSObject, FlutterPlugin {
  /// One store for the plugin's lifetime: EventKit ties an access grant to the
  /// instance that asked, so a fresh store per call would re-prompt the user.
  private let store = EKEventStore()

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "alliswell/eventkit", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(AlliswellEventkitPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "authorizationStatus":
      result(Self.statusName(EKEventStore.authorizationStatus(for: .event)))
    case "requestFullAccess":
      requestFullAccess(result: result)
    case "calendars":
      result(calendars())
    case "saveEvent":
      saveEvent(call.arguments as? [String: Any] ?? [:], result: result)
    case "deleteEvent":
      deleteEvent(call.arguments as? [String: Any] ?? [:], result: result)
    case "findEventByUrl":
      result(findEventByUrl(call.arguments as? [String: Any] ?? [:]))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ── Access (OPH-077) ───────────────────────────────────────────────────────

  private func requestFullAccess(result: @escaping FlutterResult) {
    let finish = {
      // Answer with the resulting STATUS, not a bool: "denied" and "write only"
      // are different problems and the UI has to say different things about
      // them. A bool would flatten that away.
      DispatchQueue.main.async {
        result(Self.statusName(EKEventStore.authorizationStatus(for: .event)))
      }
    }
    if #available(iOS 17.0, macOS 14.0, *) {
      // Full access, not write-only: we must READ the calendar to re-link our
      // own events and to see what is already there.
      store.requestFullAccessToEvents { _, _ in finish() }
    } else {
      store.requestAccess(to: .event) { _, _ in finish() }
    }
  }

  private func calendars() -> [[String: Any?]] {
    let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
    return store.calendars(for: .event).map { calendar in
      [
        "id": calendar.calendarIdentifier,
        "title": calendar.title,
        // Subscribed/holiday calendars are read-only — mirroring into one would
        // fail on every write, so the picker has to be able to rule them out.
        "isWritable": calendar.allowsContentModifications,
        "isDefault": calendar.calendarIdentifier == defaultId,
        "colorArgb": Self.argb(calendar.cgColor),
        "accountName": calendar.source?.title,
      ]
    }
  }

  // ── Event CRUD (OPH-078) ───────────────────────────────────────────────────

  /// Create or update. `id` present → update that event; absent → create in the
  /// given calendar. Returns the resulting event identifier so Dart can map it.
  /// EventKit's identifier is NOT perfectly stable (it can change on an iCloud
  /// move), which is exactly why the caller also stores the `alliswell://` url
  /// as a recovery key (ADR-0003).
  private func saveEvent(_ args: [String: Any], result: @escaping FlutterResult) {
    let event: EKEvent
    if let id = args["id"] as? String, let existing = store.event(withIdentifier: id) {
      event = existing
    } else {
      event = EKEvent(eventStore: store)
      guard let calendar = calendarForSaving(args["calendarId"] as? String) else {
        result(FlutterError(code: "no-calendar", message: "No writable calendar", details: nil))
        return
      }
      event.calendar = calendar
    }

    event.title = args["title"] as? String ?? ""
    event.notes = args["notes"] as? String
    if let urlString = args["url"] as? String { event.url = URL(string: urlString) }
    event.isAllDay = args["isAllDay"] as? Bool ?? false
    if let startMs = args["startMs"] as? NSNumber {
      event.startDate = Date(timeIntervalSince1970: startMs.doubleValue / 1000)
    }
    if let endMs = args["endMs"] as? NSNumber {
      event.endDate = Date(timeIntervalSince1970: endMs.doubleValue / 1000)
    }

    do {
      try store.save(event, span: .thisEvent, commit: true)
      result(["id": event.eventIdentifier])
    } catch {
      result(FlutterError(code: "save-failed", message: error.localizedDescription, details: nil))
    }
  }

  private func deleteEvent(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let id = args["id"] as? String else {
      result(FlutterError(code: "bad-args", message: "id required", details: nil))
      return
    }
    // Already gone is success, not an error — the caller's intent (no event) is
    // satisfied, and reconciling should be idempotent.
    guard let event = store.event(withIdentifier: id) else {
      result(true)
      return
    }
    do {
      try store.remove(event, span: .thisEvent, commit: true)
      result(true)
    } catch {
      result(FlutterError(code: "delete-failed", message: error.localizedDescription, details: nil))
    }
  }

  /// Re-link recovery (ADR-0003): find an event we previously created that still
  /// carries our task url, when the stored identifier has gone stale. EventKit
  /// has no query-by-url, so scan the calendar's window and match the url.
  private func findEventByUrl(_ args: [String: Any]) -> String? {
    guard let urlString = args["url"] as? String,
      let calendarId = args["calendarId"] as? String,
      let calendar = store.calendar(withIdentifier: calendarId),
      let fromMs = args["fromMs"] as? NSNumber,
      let toMs = args["toMs"] as? NSNumber
    else { return nil }
    let start = Date(timeIntervalSince1970: fromMs.doubleValue / 1000)
    let end = Date(timeIntervalSince1970: toMs.doubleValue / 1000)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
    return store.events(matching: predicate)
      .first { $0.url?.absoluteString == urlString }?.eventIdentifier
  }

  private func calendarForSaving(_ id: String?) -> EKCalendar? {
    if let id = id, let calendar = store.calendar(withIdentifier: id),
      calendar.allowsContentModifications {
      return calendar
    }
    return store.defaultCalendarForNewEvents
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// EKAuthorizationStatus → a name Dart can switch on. `writeOnly` (iOS 17+)
  /// is a real state we must not report as "granted": it can create events but
  /// cannot read them back, which is exactly what re-linking needs.
  private static func statusName(_ status: EKAuthorizationStatus) -> String {
    if #available(iOS 17.0, macOS 14.0, *) {
      switch status {
      case .fullAccess: return "fullAccess"
      case .writeOnly: return "writeOnly"
      default: break
      }
    }
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "fullAccess"  // pre-iOS 17 spelling
    @unknown default: return "notDetermined"
    }
  }

  /// A calendar's colour as 0xAARRGGBB, so Dart can tint rows without knowing
  /// anything about CoreGraphics. Nil when the colour space surprises us —
  /// callers fall back to the theme rather than guess.
  private static func argb(_ color: CGColor?) -> Int? {
    guard let converted = color, let components = converted.components, components.count >= 3
    else { return nil }
    let channel = { (value: CGFloat) in Int((max(0, min(1, value)) * 255).rounded()) }
    let alpha = components.count >= 4 ? channel(components[3]) : 255
    return (alpha << 24) | (channel(components[0]) << 16) | (channel(components[1]) << 8)
      | channel(components[2])
  }
}
