//
//  ShareViewController.swift
//  AllisWellShare — the iOS Share Extension (OPH-225, ADR-0023).
//
//  Deliberately EMPTY of product logic. The extension does ZERO work of its
//  own: it hands the shared text/URL to the AllisWell app through the App Group
//  and redirects. Every AI/network decision stays in the app, which makes "the
//  share sheet never talks to a model" a structural fact, not a promise — this
//  process has no code that could. v1: text and URLs only.
//
import UIKit
import receive_sharing_intent

class ShareViewController: RSIShareViewController {
    // Default shouldAutoRedirect() == true → no compose UI; the app opens with
    // the payload and the user chooses what to do there.

    /// OPH-242 — the last of three reasons "Share to AllisWell" did nothing.
    ///
    /// `RSIShareViewController.redirectToHostApp()` walks the responder chain
    /// looking for anything that answers the old `openURL:` selector, and
    /// performs it. On iOS 18 and later UIKit refuses that call outright:
    ///
    ///     BUG IN CLIENT OF UIKIT: The caller of UIApplication.openURL(_:)
    ///     needs to migrate to the non-deprecated
    ///     UIApplication.open(_:options:completionHandler:).
    ///     Force returning false (NO).
    ///
    /// `UIApplication` is unavailable to app extensions by design, so the
    /// plugin's Objective-C-runtime workaround is now a dead end — measured on
    /// iOS 26.2, and the plugin line that fixes it upstream (1.8+) is
    /// Swift-Package-Manager only while this project builds with CocoaPods.
    ///
    /// The fix costs four lines instead of a dependency migration. That walk
    /// starts at `self`, so declaring the selector HERE means ours is the first
    /// — and the only working — implementation it finds. We then use the
    /// sanctioned extension API, `NSExtensionContext.open(_:)`.
    ///
    /// Guarded by `test/native_config_test.dart`, which fails if this override
    /// disappears; the symptom it prevents is silence, and silence is exactly
    /// what nobody notices in review.
    @objc func openURL(_ url: URL) -> Bool {
        extensionContext?.open(url, completionHandler: nil)
        return true
    }
}
