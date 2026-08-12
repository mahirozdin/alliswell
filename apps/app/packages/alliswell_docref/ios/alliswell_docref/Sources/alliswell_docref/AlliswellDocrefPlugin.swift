import CryptoKit
import Foundation
import UniformTypeIdentifiers

// One source file for BOTH Apple platforms. `macos/…/Sources/alliswell_docref`
// is a symlink to this directory — do not duplicate this file.
//
// The divergences are small and each is commented where it happens: the picker
// class, the `.withSecurityScope` bookmark option (macOS only), and how a
// document the OS opened reaches us.
#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import AppKit
  import FlutterMacOS
#endif

/// The Apple half of ADR-0030.
///
/// Deliberately dumb, with one stated exception: the expected-hash comparison
/// happens HERE, inside the coordinated write, because that is the only place
/// check-then-write is atomic (ADR-0030 §5).
public class AlliswellDocrefPlugin: NSObject, FlutterPlugin {
  /// A document the OS handed us before Dart was listening. The URL arrives at
  /// launch — on macOS through `application(_:open:)`, on iOS through the
  /// scene's `urlContexts` — so it is buffered rather than delivered.
  private static var pendingOpen: String?

  public static func rememberOpenedDocument(_ url: URL) {
    pendingOpen = bookmarkToken(for: url) ?? url.path
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "alliswell/docref", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(AlliswellDocrefPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pickExternal":
      pickExternal(maxBytes: args["maxBytes"] as? Int ?? 0, result: result)
    case "open":
      result(Self.openToken(args["token"] as? String, maxBytes: args["maxBytes"] as? Int ?? 0))
    case "adopt":
      result(Self.adopt(args["osToken"] as? String, maxBytes: args["maxBytes"] as? Int ?? 0))
    case "probe":
      result(Self.probe(args["token"] as? String))
    case "save":
      result(
        Self.save(
          token: args["token"] as? String,
          data: (args["bytes"] as? FlutterStandardTypedData)?.data,
          expected: args["expectedSha256"] as? String ?? "",
          force: args["force"] as? Bool ?? false))
    case "clipboardRead":
      result(Self.clipboardRead())
    case "takeOpenedDocument":
      // Take-once: a second call must not re-deliver the same document.
      let token = Self.pendingOpen
      Self.pendingOpen = nil
      result(token.map { ["osToken": $0] })
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ── Resolving a handle ─────────────────────────────────────────────────────

  /// Mints the durable token. On macOS this needs BOTH new entitlements:
  /// `files.user-selected.read-write` for the grant and
  /// `files.bookmarks.app-scope` for the bookmark itself. On iOS the option is
  /// unavailable — a document-picker bookmark is implicitly security-scoped —
  /// and passing it there fails.
  private static func bookmarkToken(for url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    #if os(macOS)
      let options: URL.BookmarkCreationOptions = [.withSecurityScope]
    #else
      let options: URL.BookmarkCreationOptions = []
    #endif
    guard let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return nil }
    return data.base64EncodedString()
  }

  /// Resolves a token back to a URL, re-minting it when the bookmark is stale.
  ///
  /// A file that moved leaves a stale bookmark that still resolves; not
  /// re-minting it means the NEXT launch cannot find it, which is the quiet
  /// way a recents list rots.
  private static func resolve(_ token: String) -> (url: URL, refreshed: String?)? {
    if let data = Data(base64Encoded: token) {
      var stale = false
      #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
      #else
        let options: URL.BookmarkResolutionOptions = []
      #endif
      if let url = try? URL(
        resolvingBookmarkData: data, options: options, relativeTo: nil,
        bookmarkDataIsStale: &stale)
      {
        return (url, stale ? bookmarkToken(for: url) : nil)
      }
      return nil
    }
    // A plain path: the sessionOnly fallback, and what a legacy caller passes.
    return (URL(fileURLWithPath: token), nil)
  }

  /// Runs `body` with the security scope held, balanced.
  private static func withScope<T>(_ url: URL, _ body: () -> T) -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return body()
  }

  // ── Reading ────────────────────────────────────────────────────────────────

  private static func openToken(_ token: String?, maxBytes: Int) -> [String: Any] {
    guard let token, let resolved = resolve(token) else {
      return ["refused": "gone"]
    }
    return read(url: resolved.url, token: resolved.refreshed ?? token, maxBytes: maxBytes)
  }

  private static func adopt(_ osToken: String?, maxBytes: Int) -> [String: Any] {
    guard let osToken else { return ["refused": "gone"] }
    // An OS-handed token may be a path or a URL string; either way we mint a
    // durable bookmark from it so the file is reachable again later (W6).
    let url =
      osToken.hasPrefix("file://") ? (URL(string: osToken) ?? URL(fileURLWithPath: osToken))
      : URL(fileURLWithPath: osToken)
    let token = bookmarkToken(for: url) ?? osToken
    return read(url: url, token: token, maxBytes: maxBytes)
  }

  private static func read(url: URL, token: String, maxBytes: Int) -> [String: Any] {
    withScope(url) {
      let values = try? url.resourceValues(forKeys: [
        .fileSizeKey, .contentModificationDateKey, .isWritableKey, .volumeIsReadOnlyKey,
      ])
      guard let values, let size = values.fileSize else { return ["refused": "gone"] }
      if maxBytes > 0 && size > maxBytes { return ["refused": "tooLarge"] }

      var data: Data?
      var coordinationError: NSError?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
        readable in
        data = try? Data(contentsOf: readable)
      }
      guard let data, coordinationError == nil else { return ["refused": "denied"] }

      let writable = (values.isWritable ?? false) && !(values.volumeIsReadOnly ?? false)
      var out: [String: Any] = [
        "token": token,
        "kind": "appleBookmark",
        "name": url.lastPathComponent,
        "bytes": FlutterStandardTypedData(bytes: data),
        "writable": writable,
      ]
      if let modified = values.contentModificationDate {
        out["modifiedAtMs"] = Int(modified.timeIntervalSince1970 * 1000)
      }
      return out
    }
  }

  // ── Probing (W3) ───────────────────────────────────────────────────────────

  private static func probe(_ token: String?) -> [String: Any] {
    guard let token, let resolved = resolve(token) else {
      return ["state": "unreachable", "reason": "scopeExpired"]
    }
    let url = resolved.url
    return withScope(url) {
      guard
        let values = try? url.resourceValues(forKeys: [
          .isWritableKey, .volumeIsReadOnlyKey,
        ])
      else { return ["state": "unreachable", "reason": "fileGone"] }

      // `isWritableKey`, NOT `FileManager.isWritableFile(atPath:)`: that one
      // answers the POSIX mode and knows nothing about the sandbox grant, so a
      // file we cannot touch would report writable and the save would fail
      // with the button already on screen.
      if values.volumeIsReadOnly == true {
        return ["state": "readOnly", "reason": "volumeReadOnly"]
      }
      if values.isWritable != true {
        return ["state": "readOnly", "reason": "permissionReadOnly"]
      }
      return ["state": "writable", "reason": ""]
    }
  }

  // ── Writing (W5 + atomicity) ───────────────────────────────────────────────

  private static func save(token: String?, data: Data?, expected: String, force: Bool)
    -> [String: Any]
  {
    guard let token, let data, let resolved = resolve(token) else {
      return ["outcome": "lostAccess", "reason": "scopeExpired"]
    }
    let url = resolved.url
    return withScope(url) {
      var outcome: [String: Any] = ["outcome": "failed", "reason": "unknown"]
      var coordinationError: NSError?

      // The comparison lives INSIDE the coordinated block. Outside it, another
      // writer can land between the check and the write, which is precisely
      // the race W5 is about.
      NSFileCoordinator().coordinate(
        writingItemAt: url, options: [.forReplacing], error: &coordinationError
      ) { writable in
        if !force {
          guard let current = try? Data(contentsOf: writable) else {
            outcome = ["outcome": "lostAccess", "reason": "fileGone"]
            return
          }
          if sha256Hex(current) != expected {
            outcome = [
              "outcome": "conflict",
              "sha256": sha256Hex(current),
              "sizeBytes": current.count,
            ]
            return
          }
        }

        // `.atomic`, and NOT a hand-rolled temp file: the sandbox grant covers
        // the SELECTED FILE, not its directory, so writing a sibling temp file
        // is exactly what fails on a real signed build. `.atomic` stages
        // somewhere the sandbox blesses and commits with a rename, so a crash
        // mid-save leaves the original completely intact.
        let mode = try? FileManager.default.attributesOfItem(atPath: writable.path)[.posixPermissions]
        do {
          try data.write(to: writable, options: [.atomic])
        } catch {
          outcome = ["outcome": "failed", "reason": "\(error)"]
          return
        }
        // The atomic replace makes a new inode, so the mode bits have to be
        // put back. Extended attributes are a bounded, stated loss (ADR-0030).
        if let mode {
          try? FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: writable.path)
        }

        var out: [String: Any] = [
          "outcome": "ok", "sha256": sha256Hex(data), "sizeBytes": data.count,
        ]
        if let modified = try? writable.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        {
          out["modifiedAtMs"] = Int(modified.timeIntervalSince1970 * 1000)
        }
        outcome = out
      }
      if coordinationError != nil {
        return ["outcome": "lostAccess", "reason": "scopeExpired"]
      }
      return outcome
    }
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  // ── The clipboard half Flutter does not implement ──────────────────────────

  private static func clipboardRead() -> [String: Any] {
    var out: [String: Any] = [:]
    #if os(iOS)
      let board = UIPasteboard.general
      if let image = board.image, let png = image.pngData() {
        out["imageBytes"] = FlutterStandardTypedData(bytes: png)
        out["imageMime"] = "image/png"
      }
    #elseif os(macOS)
      let board = NSPasteboard.general
      if let html = board.string(forType: .html) { out["html"] = html }
      if let data = board.data(forType: .png) {
        out["imageBytes"] = FlutterStandardTypedData(bytes: data)
        out["imageMime"] = "image/png"
      } else if let data = board.data(forType: .tiff),
        let rep = NSBitmapImageRep(data: data),
        let png = rep.representation(using: .png, properties: [:])
      {
        // Screenshots and many apps put TIFF on the board, not PNG.
        out["imageBytes"] = FlutterStandardTypedData(bytes: png)
        out["imageMime"] = "image/png"
      }
    #endif
    return out
  }

  // ── Picking ────────────────────────────────────────────────────────────────

  /// `UniformTypeIdentifiers` is iOS 14+ / macOS 11+, and the annotation is
  /// not a formality even though the app requires iOS 15: the pod is compiled
  /// against whatever deployment target the build system hands the plugin,
  /// and this failed to build with exactly "'UTType' is only available in iOS
  /// 14.0 or newer" until it was declared.
  @available(iOS 14.0, macOS 11.0, *)
  private static var markdownTypes: [UTType] {
    var types: [UTType] = [.plainText]
    if let md = UTType("net.daringfireball.markdown") { types.insert(md, at: 0) }
    return types
  }

  private func pickExternal(maxBytes: Int, result: @escaping FlutterResult) {
    #if os(macOS)
      guard #available(macOS 11.0, *) else {
        result(["refused": "unsupported"])
        return
      }
      let panel = NSOpenPanel()
      panel.allowedContentTypes = Self.markdownTypes
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.begin { response in
        guard response == .OK, let url = panel.url else {
          result(["refused": "cancelled"])
          return
        }
        let token = Self.bookmarkToken(for: url) ?? url.path
        result(Self.read(url: url, token: token, maxBytes: maxBytes))
      }
    #elseif os(iOS)
      // `asCopy: false` is the whole point. `file_picker` hardcodes
      // `asCopy: true` (IOSFilePickerHandler.swift:249), which hands back a
      // copy in tmp — writing to it changes nothing the user can see, which is
      // why this plugin exists at all (ADR-0030 §Context).
      guard #available(iOS 14.0, *) else {
        result(["refused": "unsupported"])
        return
      }
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: Self.markdownTypes, asCopy: false)
      picker.allowsMultipleSelection = false
      let delegate = PickerDelegate { url in
        guard let url else {
          result(["refused": "cancelled"])
          return
        }
        let token = Self.bookmarkToken(for: url) ?? url.path
        result(Self.read(url: url, token: token, maxBytes: maxBytes))
      }
      Self.retainedPickerDelegate = delegate
      picker.delegate = delegate
      // `UIWindowScene.keyWindow` is iOS 15+, and the Podfile's
      // `flutter_additional_ios_build_settings` compiles every pod at
      // Flutter's minimum regardless of what this podspec asks for — so the
      // plugin has to be written against that floor, not against the app's.
      let root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController
      guard let root else {
        result(["refused": "denied"])
        return
      }
      root.present(picker, animated: true)
    #endif
  }

  #if os(iOS)
    /// UIKit does not retain a picker's delegate, and a deallocated one means
    /// the callback never fires and the Dart future never completes.
    private static var retainedPickerDelegate: PickerDelegate?

    private class PickerDelegate: NSObject, UIDocumentPickerDelegate {
      init(_ done: @escaping (URL?) -> Void) { self.done = done }
      let done: (URL?) -> Void

      func documentPicker(
        _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
      ) {
        done(urls.first)
        AlliswellDocrefPlugin.retainedPickerDelegate = nil
      }

      func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        done(nil)
        AlliswellDocrefPlugin.retainedPickerDelegate = nil
      }
    }
  #endif
}
