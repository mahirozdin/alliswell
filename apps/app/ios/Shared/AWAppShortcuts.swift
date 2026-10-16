import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif
#if canImport(AppIntents)
  import AppIntents
#endif

/// Voice capture (OPH-376, ADR-0057): "Hey Siri, add a task in AllisWell".
///
/// Compiled into the iOS Runner and the macOS Runner ONLY — never a widget
/// extension: an `AppShortcutsProvider` belongs to the app, and these intents
/// must run in the app process. Wired by `ios/scripts/wire_app_shortcuts.rb`.
///
/// Why the intents bring the app forward (`openAppWhenRun = true`) instead of
/// adding the task in the background: the parser, the local store + outbox,
/// tags, series and — above all — the alarm a deadline arms all live in Dart.
/// A task added behind the app's back would not ring until the app next ran,
/// and starting Flutter headless from an intent has crashed before (LESSONS
/// ios-native, `LiveActivityIntent`). So `perform()` only parks the words in
/// a small mailbox and the app, now in front, drains it through the Inbox
/// quick-add rule (`capture_inbox.dart`). The write is local-first, so it works
/// in airplane mode. The text never travels in a URL (ADR-0016).

// MARK: - The mailbox

/// Requests waiting for Dart. Standard defaults, not the App Group: the intent
/// runs in the app process, and what somebody dictated has no business in a
/// container the widgets can read (the private-widget rule).
enum AWCaptureQueue {
  static let key = "aw_capture_pending"
  static let didEnqueue = Notification.Name("AWCaptureQueueDidEnqueue")
  /// The Dart decoder keeps the same caps (`kAwCaptureMax`, `kAwCaptureTextMax`).
  static let maxEntries = 32
  static let maxTextLength = 500

  private static let lock = NSLock()

  static func enqueue(kind: String, text: String? = nil) {
    lock.lock()
    var queue = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
    var entry: [String: String] = [
      "id": UUID().uuidString,
      "kind": kind,
      "at": ISO8601DateFormatter().string(from: Date()),
    ]
    if let text { entry["text"] = String(text.prefix(maxTextLength)) }
    queue.append(entry)
    if queue.count > maxEntries { queue.removeFirst(queue.count - maxEntries) }
    UserDefaults.standard.set(queue, forKey: key)
    lock.unlock()
    NotificationCenter.default.post(name: didEnqueue, object: nil)
  }

  /// Read-and-clear: a resume must never replay a request.
  static func drain() -> [[String: String]] {
    lock.lock()
    defer { lock.unlock() }
    let queue = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
    UserDefaults.standard.removeObject(forKey: key)
    return queue
  }
}

// MARK: - The channel Dart drains

/// `alliswell/capture`: `take` hands the mailbox over; `changed` tells an app
/// that is already in front to drain now (a warm Siri request has no resume).
/// Deliberately not availability-gated, so the iOS 15 Runner still compiles it.
final class AWCaptureBridge {
  static let channelName = "alliswell/capture"

  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "take":
        result(AWCaptureQueue.drain())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observer = NotificationCenter.default.addObserver(
      forName: AWCaptureQueue.didEnqueue, object: nil, queue: .main
    ) { [weak self] _ in
      self?.channel.invokeMethod("changed", arguments: nil)
    }
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}

// MARK: - The intents

#if canImport(AppIntents)
  /// "Add task" — Siri, the Shortcuts app and Spotlight. The text is parsed in
  /// Dart by the offline quick-add parser (OPH-373), so "yarın 9'da kira #ev"
  /// gets its date and tag.
  @available(iOS 16.0, macOS 13.0, *)
  struct AWAddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add task"
    static var description = IntentDescription(
      "Adds a task to AllisWell. Dates and times in the text are understood.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task", requestValueDialog: IntentDialog("What's the task?"))
    var text: String

    static var parameterSummary: some ParameterSummary {
      Summary("Add \(\.$text) to AllisWell")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        throw $text.needsValueError(IntentDialog("What's the task?"))
      }
      AWCaptureQueue.enqueue(kind: "add", text: trimmed)
      return .result()
    }
  }

  /// "Show today" — Home with today selected (the widget event row's place).
  @available(iOS 16.0, macOS 13.0, *)
  struct AWShowTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show today"
    static var description = IntentDescription("Opens AllisWell on today.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
      AWCaptureQueue.enqueue(kind: "today")
      return .result()
    }
  }

  /// The phrases. A String parameter cannot appear in an App Shortcut phrase,
  /// so Siri asks "What's the task?" after the phrase. Every phrase must name
  /// the app; translations live in `<lang>.lproj/AppShortcuts.strings`.
  @available(iOS 16.0, macOS 13.0, *)
  struct AWAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
      AppShortcut(
        intent: AWAddTaskIntent(),
        phrases: [
          "Add a task in \(.applicationName)",
          "Add a task to \(.applicationName)",
          "New task in \(.applicationName)",
          "Add to \(.applicationName)",
        ],
        shortTitle: "Add task",
        systemImageName: "plus.circle"
      )
      AppShortcut(
        intent: AWShowTodayIntent(),
        phrases: [
          "Show today in \(.applicationName)",
          "What's on today in \(.applicationName)",
        ],
        shortTitle: "Today",
        systemImageName: "calendar"
      )
    }
  }
#endif
