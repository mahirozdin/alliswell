import Flutter
import UIKit
import alliswell_docref

class SceneDelegate: FlutterSceneDelegate {

  /// A `.md` opened from Files, or "Open in ▸ AllisWell" (ADR-0030).
  ///
  /// Two entry points, and the cold one is the trap OPH-242 already
  /// documented: on a cold start the URL is not delivered to
  /// `scene(_:openURLContexts:)` at all — it arrives in the connection
  /// options, before Dart exists. Buffering it in the plugin (the
  /// ShareInboxBridge mailbox pattern) is what makes both paths look the same
  /// from Dart's side.
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    remember(connectionOptions.urlContexts)
  }

  /// The share extension's callback stops here (OPH-298, amends ADR-0029).
  ///
  /// ADR-0029 measured `ShareMedia-<bundle id>:share` as an open that can
  /// never arrive — an appex could not foreground its host app on iOS 18. On
  /// iOS 26 it DOES arrive, and nothing native claims it: the plugin only
  /// registers the pre-UIScene `application:openURL:options:` callbacks. An
  /// unclaimed URL is handed to the framework as a plain ROUTE, which is how a
  /// share that had in fact been saved ended on "Bu bağlantı … bir yere
  /// gitmiyor".
  ///
  /// Dropping it loses nothing. The payload is already in the App Group, the
  /// app is already coming forward, and `shareBinderProvider` drains the
  /// mailbox on that resume — this only stops a nudge from impersonating a
  /// destination, and keeps the drain the single transport it was decided to
  /// be (the plugin's own `handleUrl` does not clear the mailbox, so letting
  /// it read too would turn one share into two tasks).
  ///
  /// The COLD path cannot be filtered here — it arrives in the connection
  /// options above, which are read-only — so Dart guards it as well
  /// (`awIsShareCallback`, `core/deep_link.dart`).
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let forwarded = URLContexts.filter { !Self.isShareCallback($0.url) }
    if !forwarded.isEmpty {
      super.scene(scene, openURLContexts: forwarded)
    }
    remember(URLContexts)
  }

  /// `RSIShareViewController` builds the URL as
  /// `\(kSchemePrefix)-\(hostAppBundleIdentifier):share`. Compared lowercased
  /// because iOS normalizes the scheme it hands over, and derived from the
  /// bundle id so a flavor with its own identifier needs no edit here.
  private static func isShareCallback(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
      let bundleId = Bundle.main.bundleIdentifier?.lowercased()
    else { return false }
    return scheme == "sharemedia-\(bundleId)"
  }

  private func remember(_ contexts: Set<UIOpenURLContext>) {
    // `alliswell://` deep links are somebody else's business (ADR-0016); only
    // real files belong to the document handle.
    guard let url = contexts.map({ $0.url }).first(where: { $0.isFileURL }) else { return }
    AlliswellDocrefPlugin.rememberOpenedDocument(url)
  }
}
