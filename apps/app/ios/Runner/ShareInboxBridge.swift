import Flutter
import Foundation

/// Drains the App Group mailbox the Share Extension writes into (OPH-242,
/// ADR-0029).
///
/// Why this exists at all: `receive_sharing_intent` only ever fills
/// `initialMedia`/`latestMedia` from `handleUrl(...)`, which is reachable only
/// from `didFinishLaunchingWithOptions[.url]`, `application:openURL:` and
/// `application:continue:`. **There is no App-Group-on-launch read anywhere in
/// the plugin.** Since ADR-0029 stopped trying to open the host app — an appex
/// cannot, on iOS 18+ — no URL ever arrives, so `getInitialMedia()` would
/// return an empty list forever and the payload would sit in `UserDefaults`
/// unread. This is that missing read.
///
/// It is also why the notification is only a nudge: the payload is here whether
/// or not the banner was shown, tapped, or ever allowed.
final class ShareInboxBridge {
  static let channelName = "alliswell/share_inbox"

  /// The plugin's own public constants, so the mailbox has exactly one schema.
  private static let payloadKey = "ShareKey"
  private static let messageKey = "ShareMessageKey"
  private static let appGroupInfoKey = "AppGroupId"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "take":
      result(take())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Read-and-clear. The clear is not tidiness: without it every resume would
  /// replay the same share, and "I shared it once and got four tasks" is a
  /// worse bug than the silence this replaced.
  private func take() -> [String: Any?]? {
    guard let defaults = UserDefaults(suiteName: Self.appGroupId()) else { return nil }
    guard let data = defaults.object(forKey: Self.payloadKey) as? Data else { return nil }
    let message = defaults.string(forKey: Self.messageKey)
    defaults.removeObject(forKey: Self.payloadKey)
    defaults.removeObject(forKey: Self.messageKey)
    return [
      "media": String(data: data, encoding: .utf8),
      "message": message,
    ]
  }

  /// Mirrors `RSIShareViewController.loadIds()`: an explicit `AppGroupId` in
  /// Info.plist wins, otherwise `group.<bundle id>`. Runner now declares the
  /// key rather than relying on the default happening to be right.
  private static func appGroupId() -> String {
    if let custom = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
      !custom.isEmpty
    {
      return custom
    }
    return "group.\(Bundle.main.bundleIdentifier ?? "")"
  }
}
