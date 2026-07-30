# AllisWellShare — iOS Share Extension (OPH-225, ADR-0023)

"Share to AllisWell" from any app. The extension does **zero** work of its own:
it hands the shared text/URL to the app through the App Group and redirects.
Every AI/network decision stays in the app — structurally, this process has no
code that could reach a model. v1 activates on **text and a single web URL**
only (`Info.plist` → `NSExtensionActivationRule`).

This is the project's second pbxproj deviation after the widget (ADR-0010), so
the Xcode wiring lives in a reviewable, idempotent script rather than a
hand-edited `project.pbxproj`. It is a **device-tour step** — run it on a Mac,
then build once to verify — because a share extension can only be exercised on
a real device / simulator.

## Files (already in the repo)

- `ShareViewController.swift` — empty `RSIShareViewController` subclass.
- `Info.plist` — activation rule (text + URL), `AppGroupId`, principal class.
- `AllisWellShare.entitlements` — App Group `group.com.alliswell.alliswell`.

## Wire it (once, on a Mac)

1. Add the extension target, embed it into Runner, set build settings:

   ```bash
   ruby ios/scripts/wire_share_extension.rb
   ```

2. Add the extension's pod target to `ios/Podfile` (the plugin's iOS code must
   compile into the extension), just after the `Runner` target block:

   ```ruby
   target 'AllisWellShare' do
     use_frameworks!
     pod 'receive_sharing_intent', :path => '.symlinks/plugins/receive_sharing_intent/ios'
   end
   ```

3. Install pods and build:

   ```bash
   cd ios && pod install && cd ..
   flutter build ios --debug --no-codesign
   ```

4. In Xcode, confirm both **Runner** and **AllisWellShare** have the App Group
   capability `group.com.alliswell.alliswell` and the same signing team.

## Verify (device tour)

- Share a paragraph of text and a URL from Safari / Notes → "AllisWell" appears
  in the share sheet → tapping it opens the app with the bubble's four chips
  (Görev yap · Not al · Özetle · Soru sor) and the honest "Inbox'a kaydet".
- Cold start (app not running) and warm (app already open) both land the
  payload — the binder in `HomeShell` only mounts signed in, so the payload
  waits for the session with no extra plumbing.
- With no AI provider configured, "Not al" and "Inbox'a kaydet" still work.
