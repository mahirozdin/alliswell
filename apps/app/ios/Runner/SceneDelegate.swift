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

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    remember(URLContexts)
  }

  private func remember(_ contexts: Set<UIOpenURLContext>) {
    // `alliswell://` deep links are somebody else's business (ADR-0016); only
    // real files belong to the document handle.
    guard let url = contexts.map({ $0.url }).first(where: { $0.isFileURL }) else { return }
    AlliswellDocrefPlugin.rememberOpenedDocument(url)
  }
}
