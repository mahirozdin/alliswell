# NOTIFICATIONS — urgent, exactly-on-time delivery (Epic 07 design)

> Research requested in OPH-060: how AllisWell guarantees **highest-priority,
> exactly-on-time** delivery for urgent reminders on iOS and Android.
> This document is the binding plan for OPH-061…064; references at the bottom.
> Product requirements: BLUEPRINT §4.9 (reminder lifecycle), §8.2 (urgent UX:
> insistent, must be acknowledged), §8.3 (payloads carry IDs only).

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

**Ringing UX.** The urgent channel is `IMPORTANCE_HIGH`, category `ALARM`,
insistent sound + vibration; DND bypass is a per-channel user grant
(`canBypassDnd`) surfaced in our settings deep-link. A full-screen "alarm
ringing" activity (like Clock apps) needs `USE_FULL_SCREEN_INTENT`: on
Android 14+ it is special access, auto-granted only to calling/alarm apps and
policed by a Play Console declaration (enforced since 2025-01-22). Gate on
`canUseFullScreenIntent()`, request via `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`,
and degrade to a heads-up notification when denied. [5][6]

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

**Priority.** Urgent notifications set
`interruptionLevel = .timeSensitive` — delivered immediately, lights the
screen, breaks through Focus/notification summaries (user-revocable
per-app). This needs only the Time Sensitive Notifications capability, no
Apple approval. [6→iOS refs: 10][11]

**Critical alerts** (`com.apple.developer.usernotifications.critical-alerts`
— bypasses the mute switch and DND) require a per-app entitlement Apple
grants for health/safety/security use cases; productivity reminders are
usually refused. The code path ships behind a flag (`criticalAlertsEnabled`)
so the entitlement can be adopted if granted; do NOT block v1 on it. [11]

**Re-alert loop without background execution.** iOS gives no reliable
background timer, so "re-alert until acknowledged" is **pre-scheduled as a
chain**: fire at T, T+2m, T+5m, T+10m… (configurable, ≤5 slots per urgent
reminder to respect the 64 cap). Acknowledge/complete/snooze cancels the
chain locally (and via sync on every other device — reminder status changes
already replicate). Android uses the same chain model for symmetry.

## 3. Other platforms

- **macOS**: same UserNotifications framework as iOS (time-sensitive
  available); flutter_local_notifications supports it.
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
> computes task-timezone mornings for REST snoozes); the iOS time-sensitive
> capability still needs the one-time Xcode step. Exact-delivery behavior
> requires the device verification pass tracked in STATE.md.

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
