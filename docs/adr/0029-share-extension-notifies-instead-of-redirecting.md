# ADR-0029 — The share extension notifies and the app drains, instead of redirecting

- **Status:** Accepted (2026-08-10, OPH-242) — **amends
  [ADR-0023](0023-stt-and-share-intent-dependencies.md) §3** (the redirect
  clause only; §1, §2 and the no-network/no-AI guarantee stand)
- **Context:** feedback round 17 #1 · [AI.md §6](../AI.md) ·
  [TASKS Epic 24](../TASKS.md)
- **Related:** [ADR-0016](0016-deep-links.md) (URL-scheme handling),
  [ADR-0027](0027-attachment-capture-image-picker.md) (the precedent for a
  measured dependency decision)

## Context

"Share → AllisWell" listed the app, dismissed the sheet, and did nothing. No
launch, no crash, no crash report. Round 17 peeled it in three layers, all
measured on iOS 26.2:

- **L1** — the appex died in dyld at 83 ms (`Library not loaded:
  @rpath/AppAuth.framework`). An appex's dyld death produces **no crash
  report**, which is why L2 and L3 were invisible. Fixed with
  `LD_RUNPATH_SEARCH_PATHS`.
- **L2** — `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` was not in Runner's
  `CFBundleURLTypes`. Fixed.
- **L3** — the extension still could not bring the app forward. **This ADR is
  about L3.**

L3 is not a bug in our wiring. It is that **an iOS app extension cannot
foreground its host app any more**, and both of upstream's attempts prove it:

| Attempt | What it does | Why it fails here |
| --- | --- | --- |
| `receive_sharing_intent` ≤1.7.0 | performs the legacy `openURL:` selector down the responder chain | iOS 18 refuses it: *"BUG IN CLIENT OF UIKIT… Force returning false (NO)"*, measured in `log show` |
| our own shim | declares `@objc func openURL(_:)` on the subclass so ours is the first responder found, then calls `NSExtensionContext.open(_:)` | the sanctioned API, and the app still did not come forward — it is documented for Today extensions |
| `receive_sharing_intent` 1.8.1 | changelog: *"Fixed sharing not working on iOS 18"* — replaces the walk with `if let application = responder as? UIApplication { application.open(…) }` | **an appex's responder chain never contains a `UIApplication`.** The branch cannot fire. Worse, taking it means the selector is no longer performed either, which silently disabled our shim |

**A premise correction belongs in the record.** The pin comment, the extension's
own source and TASKS all said "1.8+ is Swift-Package-Manager only, and we build
with CocoaPods". That is false: SPM-only starts at **1.9.0**; 1.8.1 still ships
a podspec (`flutter pub get` still warns that the plugin "does not support Swift
Package Manager", which is the proof). The measurement above was therefore run,
not assumed, and it is the reason 1.8.1 does not rescue this.

## Decision

**The extension stops trying to open the app. It shows its own sheet, writes
the App Group, and posts a notification. The app drains the App Group.**

1. **`shouldAutoRedirect()` returns false.** `RSIShareViewController` already
   subclasses `SLComposeServiceViewController`, so this is all it takes to get
   Apple's own compose sheet — the shared text with Post/Cancel. No custom UI
   was written. `didSelectPost()` hands off to the plugin's
   `saveAndRedirect(message:)`, which writes the App Group; the redirect it
   then attempts is the no-op above, and `completeRequest` closes the sheet.
2. **A local notification, from the extension.** Generic copy from the
   extension's own `NSLocalizedString`, **never the shared text** — this lands
   on a lock screen. One stable request identifier (`aw.share.pending`) so three
   shares coalesce into one banner. The extension **never** calls
   `requestAuthorization`: an appex has no context to present the prompt in, so
   it reads `getNotificationSettings()` and stays quiet when it has no
   permission. It free-rides on the grant alarms already ask for.
3. **The app drains the App Group, and that is the transport.**
   `ios/Runner/ShareInboxBridge.swift` exposes `alliswell/share_inbox` with one
   read-and-clear `take()`; `shareBinderProvider` calls it at bind time and on
   every resume. **The notification is a nudge, not the carrier** — tapping it
   only launches the app, and a user who denied notifications still gets the
   share the next time they open AllisWell.
4. **Pin `receive_sharing_intent >=1.8.1 <1.9.0`.** Not for the iOS-18 line,
   which does nothing for us, but because 1.8.0 added shared-screenshot support
   and 1.8.1 is API-identical to 1.7.0. 1.9.0 is excluded: SPM-only, Flutter
   3.38, and its own `SceneDelegate` contract.

**Unchanged, and restated so a reader of this ADR alone does not lose it:** the
extension does **no network and no AI**. That guarantee is what makes this path
acceptable at all, and it is why ADR-0023 is amended rather than retired.

### Why this amends ADR-0023 rather than superseding it

ADR-0023 decides three things: `speech_to_text`, `receive_sharing_intent`, and
the `AllisWellShare` target's behaviour. Two of them are untouched, and the
dependency is not only kept but re-pinned. Exactly one clause moves — "…**and
opens the host app**, which does the extraction" becomes "…and posts a local
notification; the app drains the group on next launch or resume." Retiring the
whole ADR would throw away the sentence this decision leans on.

## Alternatives

- **Bump to 1.9.0.** Rejected: SPM-only (the podspec was removed), requires
  Flutter 3.38, and mandates a plugin-level `SceneDelegate` contract. We already
  run a `SceneDelegate`, so that half is free — but a whole-project Swift
  Package Manager migration is not what round 17 is funding. Its rebuilt
  `RSIComposeView` is nicer than the `SLComposeServiceViewController` sheet;
  that is a reason to revisit, not a reason to migrate now.
- **Keep the `openURL:` shim.** Rejected on the device measurement, and by 1.8.1
  making it unreachable anyway.
- **Subclass and write the App Group ourselves** (`shouldAutoRedirect() == false`
  plus our own persistence). Rejected on **access control, not taste**:
  `saveAndRedirect` and `redirectToHostApp` are `private`, and `sharedMedia`,
  `appGroupId`, `hostAppBundleIdentifier` are `internal`
  (`RSIShareViewController.swift:15-17`) — with `inherit! :search_paths` our
  extension is a different module, so a subclass can neither read what the
  plugin collected nor write it. `didSelectPost()` is `open`, which is the door
  we actually needed. Recorded because this gets re-proposed.
- **Route the payload through the notification's `userInfo`.** Rejected:
  nothing in this app installs a `UNUserNotificationCenterDelegate`, and
  `flutter_local_notifications` drops foreign notifications at
  `isAFlutterLocalNotification` regardless. The tap must stay a plain launch.
- **Post nothing and let the payload wait silently.** Rejected: indistinguishable
  from the original complaint.
- **Send the shared text to the backend from the extension** (owner's proposal).
  Rejected on four measurements: there is no `keychain-access-groups`
  entitlement, so the appex cannot read the session; the access token lives 15
  minutes and the refresh token rotates with reuse treated as theft, so a second
  process holding a copy would sign the user out at random; the server address
  is a **user setting** (self-hosting) that is not in the App Group, so a
  self-hoster's text would go to `api.alliswell.space`; and
  [PRIVACY.md](../PRIVACY.md) publishes "every task or note is created by your
  own tap, never automatically", which DESIGN §24 AI5 states again for the
  share path specifically.

## Consequences

- **Sharing costs one extra tap on iOS.** Post, then the banner, then the app.
  Silence became a delay, and the delay is visible — which was the whole ask.
- **A user with notifications off gets no banner** and finds the share waiting
  the next time they open the app. Honest, and unavoidable without a permission
  prompt we are not entitled to show.
- **Two transports now exist.** Android and iOS "Open in AllisWell" for a `.md`
  still arrive through the plugin; iOS shares arrive through the drain. The
  share log records which one fired (`detail: plugin | app_group`), because
  "which transport" is the first question the next report will need.
- **Ordering is load-bearing in two places.** The extension schedules the banner
  *before* handing off to `super`, because completing the request can suspend
  the process. The app captures a no-provider share to the Inbox *before*
  showing its dialog, because a dialog can be swallowed and text cannot be
  un-lost.

## Zorlama (how this is enforced)

Three layers, and the first one is only a string guard — say so plainly.

1. **`test/native_config_test.dart` grew a Swift group.** It reads
   `ios/AllisWellShare/*.swift` and `ios/Runner/AppDelegate.swift` as text and
   asserts: `shouldAutoRedirect` is present; `UNUserNotificationCenter` is
   present and `requestAuthorization` is **not**; no `URLSession`, no
   `NSURLConnection`, no `/ai/`; every line assigning `content.title`/
   `content.body` uses `NSLocalizedString`, so the shared text can never reach a
   lock screen; `ShareInboxBridge` is registered; Runner declares `AppGroupId`.
   Comments are stripped before matching — a guard that cannot tell a rule from
   the sentence explaining it fails on its own documentation.

2. **A grep, runnable on its own**, for the guarantee ADR-0023 §3 exists to
   make:

   ```bash
   ! grep -rnE 'URLSession|NSURLConnection|/ai/' apps/app/ios/AllisWellShare/*.swift
   ```

3. **Dart tests for the drain**, because that is where the real regression
   lives and no plist can see it: a payload waiting in the mailbox routes like
   any other, and a drained payload is **not replayed** across a
   background/foreground cycle. `FakeShareInbox` counts `take()` calls, since
   the failure mode is a count — one share becoming four tasks.

**No Dart test can verify the appex's runtime behaviour.** Whether the sheet
appears, whether the banner lands, and whether a denied user still gets the
payload are device questions, and the device round in TASKS is the only gate on
them.
