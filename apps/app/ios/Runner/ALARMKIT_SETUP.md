# iOS 26 AlarmKit — wiring (OPH-141 wrote it, OPH-182 connected it)

**Status: connected and compiled (2026-07-28).** This file used to be a hand-off
("do these steps once in Xcode"). It is now a record of what is wired and a
checklist for the one part that still needs hardware.

Round 6 wrote `AlarmKitBridge.swift` and left it in no target. `flutter analyze`
and `flutter test` never touch Swift, so nothing failed — the app built green for
five weeks while the only lane that can outrun the iOS mute switch had never run
once. That is round 9 #8, and the lesson is worth keeping: **a `.swift` file in
the repo is not a compiled file.**

## What is wired

| Piece | Where | Target(s) |
| --- | --- | --- |
| Method-channel bridge | `ios/Runner/AlarmKitBridge.swift` | Runner |
| Bridge registration | `ios/Runner/AppDelegate.swift` | Runner |
| Alarm metadata + the alert's App Intents | `ios/Shared/AWAlarmShared.swift` | Runner **and** AllisWellWidgetExtension |
| Live Activity (`ActivityConfiguration`) | `ios/AllisWellWidget/AWAlarmLiveActivity.swift` | AllisWellWidgetExtension |
| `NSSupportsLiveActivities` | `ios/Runner/Info.plist`, `ios/AllisWellWidget/Info.plist` | both |
| `NSAlarmKitUsageDescription` | `ios/Runner/Info.plist` | Runner |

`ios/AllisWellWidget/` is a **folder-synchronized group** (Xcode 16+), so a new
file dropped there joins the extension target automatically. `ios/Runner/` and
`ios/Shared/` are not — files there need explicit membership. The wiring is
scripted and idempotent, so a regenerated project can be re-wired without Xcode:

```bash
ruby apps/app/ios/scripts/wire_alarmkit.rb
```

## Verify it is still connected (no device needed)

The point is to check the BUILD PRODUCTS, not the source tree:

```bash
cd apps/app && flutter build ios --debug --no-codesign
```

```bash
otool -L apps/app/build/ios/iphoneos/Runner.app/Runner.debug.dylib | grep -i alarmkit
```

Both the app dylib and `PlugIns/AllisWellWidgetExtension.appex/*.debug.dylib`
must weak-link `AlarmKit.framework`, and both bundles must contain a
`Metadata.appintents` directory. If AlarmKit is missing from that list, the lane
is dead again no matter what the Swift says.

## Device DoD (iOS 26 hardware — the remaining part)

Arm an **urgent** task due in a minute, then:

1. **Silent switch ON + Sleep Focus ON + screen LOCKED** → the alarm takes over
   the full screen and rings. (This single scenario is the whole reason the lane
   exists.)
2. **Onayla** acknowledges the reminder — check another device or another surface;
   it syncs. Do this once with the app **force-quit** as well: the press is
   parked in the app group and replayed on the next launch.
3. **Ertele** snoozes by the first preset in the user's snooze order, the task row
   shows "Ertelendi — HH:mm", and the alarm comes back at that time.
4. **iOS < 26** (or authorization denied) → urgent alarms still arrive as the
   time-sensitive notification chain (OPH-139).
5. **Settings ▸ Alarm log** shows `lane=alarmkit` rows: `scheduled` with the
   sound name, and an `action` row for each button press. An empty alarmkit lane
   means the alarm never left the notification path.
6. If more than 8 urgent alarms are pending, the far ones are logged
   `degraded … over-limit` and keep their notification chain — expected, not a
   bug.

Record the result in `docs/STATE.md` (the alarm matrix) and tick OPH-182's last
box in `docs/TASKS.md`.
