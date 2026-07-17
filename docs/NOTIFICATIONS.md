# NOTIFICATIONS — urgent, exactly-on-time delivery (Epic 07 design)

> Research requested in OPH-060: how AllisWell guarantees **highest-priority,
> exactly-on-time** delivery for urgent reminders on iOS and Android.
> This document is the binding plan for OPH-061…064; references at the bottom.
> Product requirements: BLUEPRINT §4.9 (reminder lifecycle), §8.2 (urgent UX:
> insistent, must be acknowledged), §8.3 (payloads carry IDs only).
>
> **Rev. 2026-07-18 (feedback round 6, OPH-138/139):** the first real device
> test (Sleep Focus on) exposed three gaps — no alarm at an urgent task's DUE
> time, no alarm sound at all, and normal reminders at `.active` buried by
> Focus. Fixed; §§1–2 now describe the shipped loudness model, the
> critical-alerts reality, and the AlarmKit path (OPH-140…143).

## 0. Delivery model (why local notifications are the primary channel)

The replica already syncs every `reminders` row to the device (Epic 06), so
**each device schedules its own OS-level notifications from local data** —
no server round-trip at fire time, works fully offline, and exactness becomes
an OS-scheduling problem (solvable, below) instead of a push-latency problem
(unsolvable: FCM/APNs make no timing guarantees). Push arrives later (Epic 07
tail / v2) only as a *wake-up hint* — IDs only, never content (§8.3) — and as
a backup for devices whose local schedule went stale. The OPH-060 device
registry is the inventory of installs that may need those wake-ups.

## 1. Android

**Exact scheduling.** Normal reminders use `AlarmManager.setExactAndAllowWhileIdle`
(fires at the requested instant even in Doze). **Urgent reminders use
`setAlarmClock`** — the strongest signal Android has: the system treats it as
a user-visible alarm clock, **never defers or batches it**, shows the alarm
status icon, and it is exempt from Doze/App Standby throttling. Through
flutter_local_notifications this maps to
`zonedSchedule(..., androidScheduleMode: AndroidScheduleMode.alarmClock)`
(urgent) and `.exactAllowWhileIdle` (normal). [1][2][3][9]

**Permissions (the hard part).**
- Android 12: `SCHEDULE_EXACT_ALARM` exists, granted by default.
- Android 13: still auto-granted for existing installs, revocable by user.
- **Android 14+: denied by default** — the app must send the user to the
  "Alarms & reminders" special-access screen (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`)
  and check `canScheduleExactAlarms()` before every schedule. [2]
- Alternative: **`USE_EXACT_ALARM`** is granted at install *without* a prompt,
  but Google Play policy restricts it to apps whose **core function is an
  alarm/calendar** — AllisWell (a reminders/tasks product with urgent alarms)
  has a defensible claim; decide at Play submission. Ship v1 with
  `SCHEDULE_EXACT_ALARM` + an in-app permission flow, keep `USE_EXACT_ALARM`
  as a build-config option. [2][3]
- **Degradation:** if exact access is denied, fall back to
  `AndroidScheduleMode.inexactAllowWhileIdle` AND show a persistent in-app
  banner on urgent tasks ("alarms may be late — grant Alarms & reminders").
  Never fail silently.

**Doze details.** `…AllowWhileIdle` alarms are rate-limited to ~1 per 9
minutes per app in deep Doze — relevant to the urgent re-alert loop (§8.2):
re-alerts scheduled via `setAlarmClock` are NOT subject to that limit, so the
re-alert chain (below) always uses alarm-clock mode. [1][4]

**Ringing UX (shipped 2026-07-18, OPH-139).** The urgent channel is
**versioned `urgent_alarms_v2`** — Android channels are immutable after
creation, so shipping a real sound required a new id (v1 is deleted at
startup; never reuse a deleted id — it resurrects its frozen settings) [12].
The v2 channel: `IMPORTANCE_MAX`, category `ALARM`, the bundled 28 s alarm
bed (`res/raw/aw_alarm.m4a`) with **`AudioAttributes.USAGE_ALARM`** and
**`FLAG_INSISTENT`** (loops until the notification is opened/dismissed).

**Why USAGE_ALARM is the load-bearing choice** (AOSP `ZenModeFiltering`):
DND classifies a notification as an *alarm* by its category/audio-usage, not
by which API scheduled it — so the urgent channel **rings through default
DND** (the "Alarms" exception ships enabled) and its sound routes to the
**alarm stream**: it rings at alarm volume even when the ringer is muted.
`canBypassDnd` (Notification Policy access) remains the heavier fallback if
the user disabled DND's Alarms exception. OEM DND implementations can
deviate — device pass in OPH-140. [13]

A full-screen "alarm ringing" activity (like Clock apps) needs
`USE_FULL_SCREEN_INTENT`: on Android 14+ it is special access, auto-granted
only to calling/alarm apps and policed by a Play Console declaration
(enforced since 2025-01-22). Gate on `canUseFullScreenIntent()`, request via
`ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`, and degrade to a heads-up
notification when denied. Android 15/16 added no new rules beyond the
Android 14 set (checked 2026-07-18); the Android 15+ "notification cooldown"
user setting dampens rapid successive notifications but not one insistent
loop. [5][6]

**Reboots.** `RECEIVE_BOOT_COMPLETED` + flutter_local_notifications'
boot receiver re-schedule everything from the replica on startup.

## 2. iOS

**Exact scheduling.** `UNCalendarNotificationTrigger` /
`UNTimeIntervalNotificationTrigger` fire on time — iOS has no Doze-style
deferral for local notifications. The real constraint is the **64 pending
local notifications cap** (oldest beyond 64 are dropped): a scheduling-window
manager keeps only the nearest ~40 reminder fire-times + re-alert slots
scheduled, and re-fills the window on every app foreground, sync apply, and
`BGAppRefresh` pass. [7][8]

**Priority (revised 2026-07-18, OPH-139).** ALL reminders now set
`interruptionLevel = .timeSensitive` — delivered immediately, lights the
screen, breaks through Focus (incl. Sleep, whose Time-Sensitive allowance
ships on by default; user-revocable per-app and per-Focus). The original
`.active` level for normal reminders was wrong in practice: any Focus mode
buried them silently, and a reminder the user gave a clock time to is
time-sensitive by definition. Requirements: the
`com.apple.developer.usernotifications.time-sensitive` entitlement (in
`Runner.entitlements`; self-service, no Apple approval) — without it iOS
silently demotes to `.active`, so **verify the provisioning profile actually
contains it** on any signing change (most common silent failure). [10][11]

**Sound (shipped 2026-07-18).** Notification sounds must be bundled, ≤30 s
(longer falls back to the default ding), Linear PCM/IMA4/µLaw/aLaw in
aiff/wav/caf. Urgent alarms ship a 28 s ima4 caf
(`ios/Runner/Resources/aw_alarm.caf`, wired into the pbxproj Resources
phase); normal reminders keep the default sound. Normal/time-sensitive
sounds play at RINGER volume and are silenced by the mute switch — only
critical alerts (below) or AlarmKit (§5) get past hardware silence. [14]

**Critical alerts** (`com.apple.developer.usernotifications.critical-alerts`
— bypasses the mute switch, DND and every Focus, at an app-chosen absolute
volume) require a per-app entitlement Apple grants for health/safety/
security use cases. **Research 2026-07-18: task managers are effectively
refused** — Apple rejected an alarm-clock feature twice with "this API is
not designed for the use you've identified"; approved categories are
medical (Dexcom-class), public safety, home security, ops paging. The code
path SHIPS anyway (OPH-139), gated the only safe way:
`requestPermissions(critical: true)` is harmless without the entitlement
(the standard prompt is unaffected; the extra critical prompt never
appears), and delivery upgrades to `.critical` + `criticalSoundVolume: 1.0`
ONLY when `checkPermissions().isCriticalEnabled` reports the
entitlement+user grant — an unentitled critical-sound payload degrades to
standard delivery and can lose the sound outright, so it is never sent
blind. Application form (Account Holder):
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>
— justification: urgent task alarms are user-armed, acknowledged-or-ring
safety notifications; expect refusal, treat AlarmKit as the real path
(OPH-141/142). [11][15]

**Re-alert loop without background execution.** iOS gives no reliable
background timer, so "re-alert until acknowledged" is **pre-scheduled as a
chain**: fire at T, T+2m, T+5m, T+10m… (configurable, ≤5 slots per urgent
reminder to respect the 64 cap). Acknowledge/complete/snooze cancels the
chain locally (and via sync on every other device — reminder status changes
already replicate). Android uses the same chain model for symmetry.

## 2b. AlarmKit — the iOS 26+ answer to the mute switch (OPH-141)

Research 2026-07-18: pre-iOS 26 alarm apps (Alarmy et al.) get loud on muted
phones via a background-audio-session trick (`UIBackgroundModes: audio` +
`.playback` ignoring the silent switch) — fragile, battery-hungry, dies on
force-quit, and against the spirit of the mode; not for us. **iOS 26's
AlarmKit** is Apple's sanctioned path: third-party alarms with Clock-grade
presentation whose alert "breaks through silent mode and the current Focus"
— full-screen alert, Lock Screen/Dynamic Island UI, snooze — **no special
entitlement**, only user authorization (`AlarmManager.requestAuthorization`,
`NSAlarmKitUsageDescription`) plus a Live Activity presentation. No Flutter
plugin support → native Swift bridge, real-device work (same constraints as
Epic 12). Binding plan lives in TASKS OPH-141: AlarmKit becomes the URGENT
lane on iOS 26+, the OPH-139 time-sensitive delivery stays as the < 26 and
non-urgent lane, and the planner remains the single source of truth (the
gateway diff must cancel AlarmKit alarms on acknowledge exactly like
notifications). [16]

## 3. Other platforms

- **macOS**: same UserNotifications framework as iOS (time-sensitive
  available); flutter_local_notifications supports it. The urgent caf is not
  bundled in the macOS Runner yet — macOS stays on the default sound (a
  named-but-missing sound file would mean NO sound).
- **Windows/Linux/web**: no exact-wake guarantees to a closed app. The
  running app is its own alarm: the sync engine already ticks — an in-app
  alarm overlay + OS toast (best effort) fire from a foreground timer wheel.
  Web additionally needs Notification permission; treat as best-effort.

## 4. Implementation plan (OPH-061…064) — SHIPPED 2026-07-15

> Status: everything below is implemented (`apps/app/lib/src/notifications/`,
> sync-push `snoozedUntil` + `reminder` acknowledge, REST acknowledge). v1
> deviations: notification actions run through the main isolate
> (`showsUserInterface: true` — a background-isolate outbox writer is future
> work); offline `tomorrow_morning` uses the device's wall clock (the server
> computes task-timezone mornings for REST snoozes). Exact-delivery behavior
> requires the device verification pass (now OPH-140).
>
> **Round-6 additions (SHIPPED 2026-07-18, OPH-138/139):**
> - **Urgent tasks alarm at their deadline**: `effectiveRemindAt(task)` =
>   `remind_at ?? (is_urgent ? due_at : null)` in the server's
>   `reconcileTaskReminder` (one seam: REST + sync push + calendar job), and
>   the app synthesizes the same alarm from the task row until the reminder
>   row syncs down (`ReminderStore.watchAlarms`; a task with ANY row never
>   synthesizes, so acknowledged alarms stay acknowledged).
> - **Loudness model**: §1 v2 channel + §2 sound/critical gating as revised
>   above; Settings gained an honest "Urgent alarms" permission-status row.
> - Notification bodies/actions/channel names are localized (en+tr).

1. **OPH-061** — `NotificationScheduler` (Dart): watches the replica's
   `reminders` stream, diffs desired vs. scheduled (plugin `pendingNotificationRequests`),
   schedules via `zonedSchedule` in the task's timezone (`timezone` package,
   DST-safe like the server's `src/lib/time.js`), windowed to ≤40 on iOS.
   Modes: urgent → `alarmClock` + `timeSensitive`; normal →
   `exactAllowWhileIdle` + `.active`. Permission flows + degradation banners.
2. **OPH-062** — notification actions (complete / snooze presets) call the
   local store (offline-safe: they are ordinary outbox writes) —
   `POST /tasks/:id/snooze` semantics already exist server-side.
3. **OPH-063** — urgent chain + acknowledge: chain scheduling above,
   `reminders.acknowledged_at` endpoint wiring, ring-screen (full-screen
   intent where granted).
4. **OPH-064** — privacy mode: a per-device setting renders titles vs.
   "1 reminder" in notification content; server push payloads (when they
   arrive) stay IDs-only regardless (§8.3).

Verification note: exact-delivery behavior (Doze, alarm-clock icon,
time-sensitive banners) can only be proven on devices/emulators — plan a
device pass; unit tests cover the scheduler diffing and window logic.

## References

1. Android — Schedule alarms (exact vs. inexact, Doze behavior, best practices):
   <https://developer.android.com/develop/background-work/services/alarms>
2. Android 14 behavior change — `SCHEDULE_EXACT_ALARM` denied by default (+
   `USE_EXACT_ALARM` policy):
   <https://developer.android.com/about/versions/14/changes/schedule-exact-alarms>
3. `AlarmManager` API reference (`setExactAndAllowWhileIdle`, `setAlarmClock`):
   <https://developer.android.com/reference/android/app/AlarmManager>
4. Optimize for Doze and App Standby (allow-while-idle ~9-minute rate limit):
   <https://developer.android.com/training/monitoring-device-state/doze-standby>
5. Full-screen intent limits on Android 14+ (AOSP) and the Play policy
   declaration: <https://source.android.com/docs/core/permissions/fsi-limits>,
   <https://support.google.com/googleplay/android-developer/answer/13392821>
6. Android 14 behavior changes overview (FSI special access,
   `canUseFullScreenIntent`):
   <https://developer.android.com/about/versions/14/behavior-changes-14>
7. Apple — Scheduling a notification locally from your app:
   <https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app>
8. Apple archive — local notification limits (64 soonest kept):
   <https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html>
9. flutter_local_notifications — `zonedSchedule`, `AndroidScheduleMode`
   (`exactAllowWhileIdle`, `alarmClock`), permission APIs:
   <https://pub.dev/packages/flutter_local_notifications>
10. Apple — `UNNotificationInterruptionLevel` (passive/active/timeSensitive/critical)
    + WWDC21 "Send communication and Time Sensitive notifications":
    <https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel>,
    <https://developer.apple.com/videos/play/wwdc2021/10091/>
11. Apple — Critical Alerts entitlement:
    <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts>
12. Android — notification channels are immutable after creation:
    <https://developer.android.com/develop/ui/views/notifications/channels>
13. AOSP — DND classifies alarms by category/audio usage
    (`ZenModeFiltering.java`):
    <https://github.com/aosp-mirror/platform_frameworks_base/blob/main/services/core/java/com/android/server/notification/ZenModeFiltering.java>
14. Apple — `UNNotificationSound` (formats, 30 s cap, critical volume):
    <https://developer.apple.com/documentation/usernotifications/unnotificationsound>
15. Critical-alerts request form (Account Holder sign-in):
    <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>;
    rejection precedent for alarm-clock use:
    <https://developer.apple.com/forums/thread/690030>
16. Apple — AlarmKit (iOS 26+, WWDC25 session 230 "Wake up to the AlarmKit
    API"): <https://developer.apple.com/documentation/alarmkit>,
    <https://developer.apple.com/videos/play/wwdc2025/230/>
