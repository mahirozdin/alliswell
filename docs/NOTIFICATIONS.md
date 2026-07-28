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
>
> **Rev. 2026-07-27 (feedback round 9, Epic 16 — the first real "I used the
> alarm" round):** the user armed an urgent task (due 22:45, remind 22:42) and
> got: a notification at 22:42 with the DEFAULT ding, the alarm bed at 22:44,
> **nothing at 22:45** (the task's own due time), a silent notification at
> 22:47, and a silent re-ring after a 5-minute snooze. Diagnosis and the binding
> answers: §2 (why a `timeSensitive` custom sound is not an alarm, and how it
> degrades silently), §2b (**AlarmKit was never wired into any Xcode target —
> the mute-switch-proof lane has never run on a device**), §2c (user-supplied
> sounds), §2d (Apple Watch), §5 (the user-configurable chain, the loudness
> contract, the 64-slot math), §6 (the alarm log — no more diagnosis from
> memory). Tasks: OPH-175…183.

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
critical alerts (below) or AlarmKit (§2b) get past hardware silence. [14]

**Round 9: the two silent-failure modes (2026-07-27).** The round-9 report
("first quiet, then music, then silence") is not explainable from our payloads —
every slot of an urgent chain ships the same content (`sound: aw_alarm.caf`,
`interruptionLevel: .timeSensitive`, urgent category). Two documented OS
behaviours can produce exactly that pattern, and both are now designed against:

1. **The sound name may not resolve at delivery time.** `UNNotificationSound`
   resolves a name against the app container's `Library/Sounds` folder first and
   the app bundle second; when it resolves to nothing the system **substitutes
   the default sound** (and there is a long tail of reports of this failing
   intermittently after installs/upgrades). A 28 s custom bed silently becoming
   a ding is exactly what the user described at 22:42. → OPH-176 verifies
   resolvability at initialize and says so in Settings; it never assumes.
2. **The mute switch / ringer volume silences the whole lane.** A
   `timeSensitive` notification is *delivered* through Focus, but its sound is
   still a notification sound: hardware silence wins. Nothing in the
   notification lane can fix this — this is the entire reason AlarmKit (§2b)
   is the primary iOS lane from round 9 on, not a nice-to-have.

**The loudness contract (binding, round 9).** An urgent alarm's **every** slot —
the first, each repeat, and every post-snooze re-ring — carries the alarm sound
and the alarm-grade delivery of its platform. There is no "quiet first slot":
that shape was never designed, and a user cannot be expected to model it. The
only user-visible loudness distinction is urgent (alarm) vs normal reminder
(reminder sound, §2c).

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
chain**: fire at T, T+2m, T+5m, T+10m… Acknowledge/complete/snooze cancels the
chain locally (and via sync on every other device — reminder status changes
already replicate). Android uses the same chain model for symmetry. **Round 9:
the chain's shape is no longer a constant — it is a user profile, and its cost
against the 64 cap is stated in the UI (§5).**

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

**Round 9 status check — the lane has never run (2026-07-27).** The Dart lane
(`planAlarmKitAlarms`, the host seam, the scheduler's second set-diff) and
`ios/Runner/AlarmKitBridge.swift` exist and are unit-tested, `NSAlarmKitUsageDescription`
is in `Info.plist` — but **the Swift file is in no Xcode target and `AppDelegate`
never constructs the bridge** (`ios/Runner/ALARMKIT_SETUP.md` says so itself).
So `isSupported()` throws `MissingPluginException` → `false` → every urgent alarm
has been served by the notification lane, which cannot beat hardware silence.
**This is the root cause of round 9 #8**, and OPH-182 is the fix.

**What round-9 research added to the wiring plan** (sources [16][17][18]):

- **A widget extension is effectively required.** AlarmKit renders its
  countdown/paused/alert presentations through ActivityKit: the app needs a
  widget extension exposing `ActivityConfiguration(for: AlarmAttributes<AWAlarmMetadata>.self)`
  and **`NSSupportsLiveActivities = YES` in BOTH Info.plists** (app + extension);
  without one, alarms can be dismissed unexpectedly by the system. AllisWell
  already ships `ios/AllisWellWidget` (Epic 12) — the Live Activity goes there,
  and the metadata type must compile into both targets.
- **Custom sounds are supported** — `AlertConfiguration.AlertSound.named(...)`,
  resolved from the app bundle or the container's `Library/Sounds` (§2c), so the
  same installed ringtone serves both lanes. Early iOS 26 releases had reports of
  container-hosted sounds not playing; verify on the device pass and fall back to
  the bundled bed.
- **Apple Watch and Standby are part of the deal** — Apple describes AlarmKit
  alarms as reaching the Lock Screen, Dynamic Island, Standby **and Apple Watch**
  (§2d).
- **Alarm count is limited but undocumented** — keep the AlarmKit lane windowed
  to the soonest N alarms (as the notification lane is) and log rejections (§6).

## 2c. User-supplied sounds — what is actually possible (round 9, OPH-181)

Round 9 asks for a user-selectable ringtone, uploadable through our own storage.
The constraints are hard and platform-specific:

- **iOS.** `UNNotificationSound(named:)` looks in `<app container>/Library/Sounds`
  first, then the app bundle (an app-group container also works) — so a
  **downloaded** file CAN be a notification sound: fetch it (presigned GET,
  ADR-0011 pipeline), write it to `Library/Sounds/<hash>.caf`, reference it by
  name. Format rules are unforgiving: **≤ 30 s**, aiff/wav/caf carrying Linear
  PCM, MA4/IMA4, µLaw or aLaw. **mp3/m4a will not play** — an unusable upload
  must be refused (with the reason) at upload time, or it becomes a silent alarm
  at 03:00. Server-side transcoding (ffmpeg) is parked in the backlog.
- **Android.** Notification channels are immutable after creation, so a sound
  change means a **new channel per sound** (`urgent_alarms_v3_<hash>`), with
  stale channels deleted and the count kept bounded. Sound is a `Uri` on the
  channel, and `USAGE_ALARM` must stay for the alarm-stream/DND behaviour (§1).
- **In-app bed (`AlarmFeedback`, OPH-180).** The foreground ring screen plays
  through our own player, so it accepts any format the platform can decode and
  is the honest home for an mp3 the OS lane would refuse.
- **Selection storage.** The ringtone LIBRARY is workspace-wide (files, so every
  device can pick the same file); the SELECTION is device-local, like
  `notification_privacy` and the reminder profile (§5). A server-side settings
  store is backlog.

## 2d. Apple Watch (round 9, OPH-183)

- **Mirroring is free and needs no watchOS target**: iPhone notifications are
  forwarded to a paired, unlocked watch while the phone is locked. Sound/haptic
  strength for our app is the **user's** setting (Watch app → Sounds & Haptics);
  watchOS 26 also auto-adjusts alert volume to the surroundings, and the
  "Prominent" haptic pre-announces alerts with an extra tap. So a watch owner
  already gets a wrist tap for every alarm — worth SAYING in the app (a help
  line in the reminder settings) instead of building anything.
- **AlarmKit alarms are stated to reach the watch** (§2b) — this is the main
  reason the watch story rides OPH-182's device pass rather than a separate
  build.
- **A watchOS companion target buys only three things**: a custom long-look
  notification UI, `WKInterfaceDevice.play(.notification)` haptics we control,
  and a complication. It also buys a second signing/review surface. Decision
  rule (OPH-183): measure mirroring + AlarmKit on a real watch first; open a
  companion epic only if that proves insufficient.

## 3. Other platforms

- **macOS**: same UserNotifications framework as iOS (time-sensitive
  available); flutter_local_notifications supports it. The urgent caf is not
  bundled in the macOS Runner yet — macOS stays on the default sound (a
  named-but-missing sound file would mean NO sound).
- **Windows/Linux/web**: no exact-wake guarantees to a closed app. The
  running app is its own alarm: the sync engine already ticks — an in-app
  alarm overlay + OS toast (best effort) fire from a foreground timer wheel.
  Web additionally needs Notification permission; treat as best-effort.
  **Shipped 2026-07-19 (OPH-143):** the in-app overlay is `AlarmRingScreen`,
  driven by `AlarmOverlayController` (watches the replica's alarm feed + a
  foreground timer wheel armed to the next urgent fire). It is the ONLY alarm
  surface on desktop/web, and the foreground companion to the OS notification on
  mobile. Insistence is a seam (`AlarmFeedback`): **shipped 2026-07-28
  (OPH-180)** as a looping audio bed + haptic pulse. The bed is the bundled 28 s
  asset played through `audioplayers` with the iOS `AVAudioSession` category
  `.playback` — audible with the mute switch ON **while the app is in the
  foreground**, which is legitimate exactly there and is NOT the background
  audio-session trick §2b rejects — and Android `USAGE_ALARM` attributes. When a
  platform refuses to play (a browser's autoplay policy), the ring screen SAYS
  so and offers a manual "start the sound": a silent alarm that looks like it is
  ringing is the one outcome this section forbids. An `AlarmDegradationBanner` on Home surfaces the "never fail silently"
  rule when notifications are off or Android exact alarms are denied.

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

## 5. What the user owns: instants, chain, silence (round 9 — OPH-175…179)

**(a) A task can have TWO alarm instants, and they are independent.** Until
round 9 the model was `effectiveRemindAt = remind_at ?? (urgent ? due_at : null)`
— one instant, with the reminder *replacing* the deadline. The user's rule is
different and better: _"velevki hatırlatıcı kurdum — tam görev saatinde de alarm
gibi çalmalı."_ So `alarmInstantsFor(task)` returns up to two, each its own
reminder row (`reminders.kind` ∈ `remind` | `due`):

| kind | when it exists | body |
| ---- | -------------- | ---- |
| `remind` | `remind_at` is set (any priority) | `notif.urgentFirst` / `notif.urgentRepeat` / `notif.afterSnooze` |
| `due` | `is_urgent` **and** `due_at` is set — **even when a reminder exists** | `notif.dueNow` ("Görev saati geldi") |

Identical instants collapse to one row (never ring twice for one moment). A
muted task returns none. One seam still serves REST, sync push and the calendar
job — `reconcileTaskReminder` simply loops over kinds, each row keeping its own
revision and its own "remind moved → re-arm" rule.

**(b) The chain is a device-local profile, and its OS cost is visible.**
`ReminderProfile.slots` (minutes after the instant) replaces the
`kUrgentChainOffsets` constant: sorted, deduplicated, **≥ 1 minute apart** (the
user's own anti-collision rule — sub-minute steps are refused with a reason),
first slot ≥ 0, at most **20**. Post-snooze re-rings run the same profile from
`snoozed_until` and are labelled as a snooze round, not as a first alert.

The cap arithmetic that the settings screen must show, because the OS enforces
it silently: iOS keeps the **64 soonest pending** local notifications, we window
at 40, so

> `alarms_fully_covered ≈ floor(40 / slots_per_alarm)`

— a 5-slot profile covers 8 concurrent alarms, a 20-slot profile covers 2. Beyond
that the window drops the farthest slots (they re-fill as time passes, on every
foreground/sync). AlarmKit does not multiply: one alarm = one entry, ring-until-
answered is native — another reason §2b is the better lane.

**(c) Silence is a state.** `tasks.alarms_muted_at` (null = live) makes
"süresiz ertele" a real, syncing, reversible fact: instants become empty →
`reconcileTaskReminder` cancels the rows → every device's chain dies. The task
stays **open**; muting is not completing, and the UI keeps saying the alarm is
off (DESIGN §11 A5). Un-muting re-arms through the ordinary create path, and if
the instant is already in the past the app says so instead of pretending.

## 6. Diagnostics: the alarm log (round 9 — OPH-176)

Round 9 cost a whole evening to a question we could not answer — *which* lane
fired, with *which* sound, at *which* slot. From now on the device keeps a local
ring buffer (`alarm_events`, ~200 rows, never synced): instant, lane
(`notification` | `alarmkit` | `inapp`), kind, slot index, urgent flag, sound
name, interruption level, task/reminder id, and the event
(`scheduled` | `cancelled` | `interacted` | `action` | `ring_shown` |
`degraded` — the last one written when the permission probe says delivery is
limited).

**Shipped 2026-07-28 (OPH-176).** `alarm_events` (drift v9) + `AlarmLog`, written
by the scheduler (both lanes), the notification action router, the in-app ring
screen and the permission probe; read by Settings → "Alarm günlüğü" (read-only,
scope sentence ABOVE the data, copy-to-clipboard). Two rules the implementation
enforces: the **loudness decision is one pure function** (`awDeliveryFor`) whose
result the gateway both applies and reports, so the log records what was actually
asked for; and **the log can never break what it observes** — every write is
guarded and fire-and-forget (during the work an unguarded write made the probe
fail on a surface with no database, and a device with alarms OFF briefly looked
healthy — precisely the lie this section exists to prevent).

Honest scope, stated in the UI: **iOS gives no callback for a notification the
user never touches**, so the log proves what we SCHEDULED, what the user
INTERACTED with, and what rang IN-APP — it must never claim "delivered". That is
still enough to settle every round-9 question (was the slot scheduled? which
sound name? which lane? was it cancelled early?).

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
    <https://developer.apple.com/videos/play/wwdc2025/230/>,
    <https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit>
17. AlarmKit in practice (round 9 research, 2026-07-27) — widget-extension /
    `ActivityConfiguration` + `NSSupportsLiveActivities` requirement, custom
    `AlertConfiguration.AlertSound.named`, Apple Watch/Standby reach:
    WWDC25-230 notes <https://wwdcnotes.com/documentation/wwdc25-230-wake-up-to-the-alarmkit-api/>,
    countdown-timer walkthrough <https://nilcoalescing.com/blog/CountdownTimerWithAlarmKit/>,
    custom-sound threads <https://developer.apple.com/forums/thread/788836>,
    <https://developer.apple.com/forums/thread/795417>
18. Apple — `UNNotificationSound` name resolution order (app container
    `Library/Sounds` → app group container → bundle) and the ≤30 s / aiff-wav-caf
    format rules; the silent fall-back to the default sound when a name does not
    resolve: <https://developer.apple.com/documentation/usernotifications/unnotificationsound>,
    <https://developer.apple.com/forums/thread/49512>
19. Apple — Apple Watch alert routing the user controls (Watch app → Sounds &
    Haptics, "Prominent" haptic, watchOS 26 ambient volume) and notification
    forwarding while the iPhone is locked:
    <https://support.apple.com/guide/watch/choose-alert-sounds-and-haptics-apd58cffe6a4/watchos>,
    <https://support.apple.com/en-us/108274>
