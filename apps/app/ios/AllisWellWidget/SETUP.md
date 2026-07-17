# iOS home-screen widget — Xcode setup (OPH-131)

The widget's Swift, `Info.plist` and `.entitlements` are written and ready in this
folder (`ios/AllisWellWidget/`). What's left **must be done once in Xcode** —
creating an App-Extension target and its App Group is a GUI step that can't be
scripted safely (it edits `project.pbxproj` and the provisioning profile). The
Dart side (snapshot + bridge, OPH-130) is already done and shipping.

> The app currently builds fine — these files are NOT yet in any target, so they
> don't affect the build until you add them below.

## Steps (≈10 min, once)

1. **Open the workspace** (not the project):
   `open apps/app/ios/Runner.xcworkspace`

2. **Create the target:** File ▸ New ▸ Target… ▸ **Widget Extension** ▸ Next.
   - Product Name: **`AllisWellWidget`**
   - **Uncheck** "Include Configuration App Intent" and "Include Live Activity"
     (we use a `StaticConfiguration` for now; interactivity is OPH-132).
   - Finish ▸ **Activate** the scheme when prompted.

3. **Use our Swift, drop the template's:** Xcode generated `AllisWellWidget.swift`
   (+ maybe `AllisWellWidgetBundle.swift`) with its own `@main`. Delete those
   generated Swift files and **add `ios/AllisWellWidget/AllisWellWidget.swift`**
   to the new target (drag it in; check "AllisWellWidgetExtension" in Target
   Membership). Ours already has `@main`. Point the target's Info.plist at the
   provided `ios/AllisWellWidget/Info.plist` (or copy its `NSExtension` dict in).

4. **App Groups on BOTH targets** (this is what lets them share the snapshot):
   - **Runner** target ▸ Signing & Capabilities ▸ **+ Capability ▸ App Groups** ▸
     add `group.com.alliswell.alliswell`.
   - **AllisWellWidgetExtension** target ▸ + Capability ▸ App Groups ▸ add the
     **same** `group.com.alliswell.alliswell`.
   - Point the extension's Code Signing Entitlements at the provided
     `AllisWellWidget.entitlements` if Xcode made a different file, or just make
     sure the group id matches exactly.

5. **Deployment target:** set the widget extension's **Minimum Deployments** to
   **iOS 16.0** (WidgetKit needs 14; the code uses iOS 17 APIs behind
   `if #available`).

6. **Signing:** keep "Automatically manage signing" on for the extension, Team
   `QB8VR32GWN` (same as Runner) — Xcode refreshes the provisioning profile for
   the App Group.

## Verify

7. Run the app on a device or simulator (`flutter run`), **sign in and open
   Home** — that's when the app publishes the first snapshot (OPH-130's
   `WidgetBridge`). Add a task or two.
8. Long-press the Home Screen ▸ **+** ▸ search **AllisWell** ▸ add the widget in
   each size (Medium, Large; Extra-Large on iPad). It should show the date header
   and your bucketed tasks. Editing a task in the app updates the widget within a
   moment (foreground push).

## Commit

9. Commit the new files Xcode created/changed: `ios/Runner.xcodeproj/project.pbxproj`,
   `ios/Runner/Runner.entitlements` (now with the App Group), the
   `AllisWellWidgetExtension.entitlements`, and this folder. Then OPH-131 is done —
   record the device pass in `docs/STATE.md`.

## Next

- **OPH-132** (tap-to-complete / quick-add without opening the app) adds an
  `AppIntent` shared with Runner + `home_widget`'s background worker; it needs the
  `home_widget` pod linked into the extension. That's a separate task.
- **Tap-to-open** today uses `.widgetURL(alliswell://open)`; wiring the app to
  route `alliswell://…` deep links (so a tap lands on the right screen) is folded
  into OPH-132/135.
