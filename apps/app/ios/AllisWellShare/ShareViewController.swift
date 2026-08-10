//
//  ShareViewController.swift
//  AllisWellShare — the iOS Share Extension (OPH-225/OPH-242, ADR-0023/ADR-0029).
//
//  Still EMPTY of product logic. The extension does no network and no AI of its
//  own: it hands the shared text/URL to the AllisWell app through the App Group.
//  "The share sheet never talks to a model" stays a structural fact rather than
//  a promise — this process has no code that could. v1: text and URLs only.
//
//  What ADR-0029 changed is only the last step. It used to end by opening the
//  host app; it now ends by NOTIFYING, because on iOS 18+ an app extension
//  cannot bring its host app forward at all (see below). The payload is the
//  transport; the banner is a nudge.
//
import UIKit
import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    /// OPH-242 L3 — the last of three reasons "Share to AllisWell" did nothing,
    /// and the one that turned out to be unfixable rather than unfixed.
    ///
    /// `redirectToHostApp()` walks the responder chain trying to open a
    /// `ShareMedia-<bundleid>:share` URL. Both of upstream's attempts are dead
    /// ends inside an appex:
    ///
    /// * ≤1.7.0 performs the legacy `openURL:` selector. iOS 18 refuses it —
    ///   "BUG IN CLIENT OF UIKIT… Force returning false (NO)" — measured on
    ///   iOS 26.2. We tried the sanctioned `NSExtensionContext.open(_:)` here
    ///   instead; the app still did not come forward (that API is documented
    ///   for Today extensions).
    /// * 1.8.1's "Fixed sharing not working on iOS 18" replaces that walk with
    ///   `if let application = responder as? UIApplication { application.open(…) }`.
    ///   **An app extension's responder chain never contains a UIApplication**,
    ///   so on iOS 18+ the fix is a no-op — and because it takes that branch, it
    ///   also stops calling the selector, which silently disabled the shim we
    ///   had. Measured by reading 1.8.1's source; recorded in ADR-0029.
    ///
    /// So we stop trying to open the app. Returning false here shows the
    /// inherited `SLComposeServiceViewController` sheet — the shared text with
    /// Post/Cancel, Apple's own compose UI — and `didSelectPost()` below hands
    /// off to `saveAndRedirect(message:)`, which writes the App Group. The app
    /// drains that on its next launch or resume (`ShareInboxBridge` →
    /// `alliswell/share_inbox`). Silence became a delay, and the delay is
    /// visible.
    override func shouldAutoRedirect() -> Bool {
        return false
    }

    /// Order is load-bearing. `super` writes the App Group and then completes
    /// the extension request, and completing can suspend this process — so the
    /// banner is scheduled BEFORE the hand-off, and with a short time trigger
    /// rather than an immediate one so the notification daemon owns it even if
    /// we are torn down a millisecond later.
    override func didSelectPost() {
        ShareNotifier.schedulePendingBanner()
        super.didSelectPost()
    }
}
