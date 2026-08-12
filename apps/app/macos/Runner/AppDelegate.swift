import Cocoa
import FlutterMacOS
import alliswell_docref

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder double-click, and "Open With ▸ AllisWell" (ADR-0030).
  ///
  /// `Info.plist` has declared `CFBundleDocumentTypes` for markdown since
  /// before this round, but nothing consumed it — so opening a .md on a Mac
  /// reached no Dart code at all. The URL also arrives before Dart is
  /// listening, which is why the plugin buffers it (the ShareInboxBridge
  /// mailbox pattern) rather than trying to deliver it.
  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    AlliswellDocrefPlugin.rememberOpenedDocument(url)
  }
}
