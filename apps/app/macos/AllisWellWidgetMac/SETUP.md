# macOS widget — the one step that needs the account holder (OPH-335)

Everything that can be written is written and compile-checked:

| Piece | Where | State |
| --- | --- | --- |
| Widget views + timeline | `ios/AllisWellWidget/AllisWellWidget.swift` (shared with iOS) | compiles for macOS 14 (`swiftc -typecheck`) and still builds for iOS |
| The extension's `@main` | `macos/AllisWellWidgetMac/AllisWellWidgetMacBundle.swift` | the iOS bundle minus the AlarmKit Live Activity |
| Info.plist / entitlements | `macos/AllisWellWidgetMac/` | sandbox + `group.com.alliswell.alliswell` |
| App → widget data | `macos/Runner/MainFlutterWindow.swift` (`AWMacWidgetBridge`) + Dart `MacWidgetHost` | live in the app today — `home_widget` has no macOS side |
| Widget taps → app | the same bridge drains `AWAlarmActionQueue` into Dart's `onAlarmAction` | live in the app today |
| The Xcode target | `macos/scripts/add_widget_extension.rb` | **not applied** — see below |

## Why the target is not in the project yet

The extension has its own bundle id, `com.alliswell.alliswell.AllisWellWidget`.
The only Mac provisioning profile on team `WWRZ5CG3DW` ("Mac Team Provisioning
Profile: com.alliswell.alliswell") covers the app's id alone, and `flutter build
macos` does not let Xcode register a new id (it passes no
`-allowProvisioningUpdates`). With the target in the project, every macOS build
on this machine would fail on the missing profile — and the rule is that the
build is never left red. Registering an App ID is an account change, which is
the account holder's to make.

## The step (once, ~5 minutes)

```bash
cd apps/app/macos
ruby scripts/add_widget_extension.rb      # idempotent; a second run changes nothing
open Runner.xcworkspace
```

In Xcode: select the **AllisWellWidgetMac** target → *Signing & Capabilities* →
team **APPILLON (WWRZ5CG3DW)**, "Automatically manage signing" on. Xcode
registers the id and the App Group for it and downloads a profile. Then:

```bash
cd apps/app && flutter build macos --debug
find build/macos -name '*.appex'          # AllisWellWidgetMac.appex inside AllisWell.app
```

Commit the `project.pbxproj` change the script made (and nothing else Xcode
touched — read the diff; it should add one target, one group pair, one embed
phase and one dependency).

## Then, on the Mac

Add the widget from Notification Center / the desktop ("Edit Widgets" → AllisWell),
in light and dark; tap a row's circle (macOS 14+) and open the app — the task is
completed; tap "+" — the app opens on the new-task sheet.
