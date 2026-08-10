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
    /// iOS 26.2.
    ///
    /// CORRECTION (2026-08-10): this comment used to add "and the upstream fix
    /// (1.8+) is Swift-Package-Manager only while we build with CocoaPods".
    /// That is false. SPM-only starts at **1.9.0**; **1.8.1** still ships a
    /// podspec and its changelog reads "Fixed sharing not working on iOS 18".
    /// Measuring 1.8.1 on a device is step 0 of the remaining OPH-242 work, and
    /// it may well delete this whole file's reason for existing.
    ///
    /// The fix costs four lines instead of a dependency migration. That walk
    /// starts at `self`, so declaring the selector HERE means ours is the first
    /// — and the only working — implementation it finds. We then use the
    /// sanctioned extension API, `NSExtensionContext.open(_:)`.
    ///
    /// NOT guarded by a test, despite what this comment claimed until
    /// 2026-08-10: `native_config_test.dart` reads plists and the Android
    /// manifest, never a `.swift` file, so nothing would notice if this
    /// override vanished. A Swift group belongs in that test and is on
    /// OPH-242's list — the symptom it would prevent is silence, and silence is
    /// exactly what nobody notices in review.
    @objc func openURL(_ url: URL) -> Bool {
        extensionContext?.open(url, completionHandler: nil)
        return true
    }
}
