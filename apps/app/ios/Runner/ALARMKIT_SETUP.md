# iOS 26 AlarmKit — Xcode setup (OPH-141)

The AlarmKit URGENT lane's Dart side is done and tested (`lib/src/notifications/
alarmkit.dart`, `planner.dart`, `scheduler.dart` — app 377/377). The native
bridge `AlarmKitBridge.swift` is written and sitting in this folder, and
`NSAlarmKitUsageDescription` is already in `Info.plist`. What's left **must be
done once in Xcode on an iOS 26 machine**, because AlarmKit only compiles
against the iOS 26 SDK on a real target — `flutter analyze`/`test` never touch
Swift, so this is a device step (exactly like the widget, `AllisWellWidget/
SETUP.md`).

> The committed app builds fine today: `AlarmKitBridge.swift` is NOT yet in any
> target and `AppDelegate` does NOT reference it, so nothing here affects the
> build until you wire it below.

## Steps (≈10 min, once, needs Xcode 26 / iOS 26 SDK)

1. **Open the workspace:** `open apps/app/ios/Runner.xcworkspace`

2. **Add the file to the Runner target:** drag `ios/Runner/AlarmKitBridge.swift`
   into the **Runner** group and check **Runner** in Target Membership. (It's
   iOS-only; do not add it to the widget or test targets.)

3. **Register the bridge in `AppDelegate.swift`** — add the property and the two
   lines the comment marks:
   ```swift
   private var alarmKitBridge: AlarmKitBridge?
   // ...inside didInitializeImplicitFlutterEngine, after GeneratedPluginRegistrant:
   if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlarmKitBridge") {
     alarmKitBridge = AlarmKitBridge(messenger: registrar.messenger())
   }
   ```

4. **Confirm the AlarmKit API shapes against the SDK.** The bridge uses the
   documented WWDC25 surface (`AlarmManager.shared`, `AlarmPresentation.Alert`
   with a stop + countdown button, `AlarmManager.AlarmConfiguration`,
   `AlarmMetadata`, `alarmUpdates`). If a type/initializer name differs in the
   shipping SDK, fix it in `AlarmKitBridge.swift` — the channel contract and the
   id↔UUID mapping are final; only the AlarmKit value types may need a nudge.

5. **Build & run on a real iOS 26 device** (min deployment stays iOS 16; the
   AlarmKit code is all behind `if #available(iOS 26.0, *)`).

## Verify (DoD)

6. Make an **urgent** task due in a minute, **mute the phone** and turn on a
   Focus. At the due time the AlarmKit alert should ring/vibrate through both.
7. **Onayla** acknowledges the task (check another surface — it syncs).
   **Ertele** snoozes it (AlarmKit re-presents; the reschedule flows back
   through the planner).
8. On iOS < 26 (or if you deny authorization) confirm urgent alarms still arrive
   as the time-sensitive notification chain (OPH-139) — the fallback.

## Commit

9. Commit what Xcode changed: `ios/Runner.xcodeproj/project.pbxproj` (now
   includes `AlarmKitBridge.swift`) and `AppDelegate.swift`. Record the device
   pass in `docs/STATE.md` (the alarm matrix), and check OPH-141's last box in
   `docs/TASKS.md`.
