# ADR-0015 — Alarm delivery: AlarmKit-first, two alarm instants, user-owned reminder profiles

- **Status:** Accepted
- **Date:** 2026-07-27
- **Related task:** OPH-175…183 (Epic 16, feedback round 9)

## Context

Feedback round 9 (Mahir, 2026-07-27) is the first report from someone who
actually **used** the product's headline feature. He armed an urgent task (due
22:45, reminder 22:42) and got:

1. 22:42 — a notification with the **default ding**, not the alarm bed.
2. 22:44 — the alarm bed played (chain slot 2).
3. **22:45 — nothing at all**, at the task's own due time.
4. 22:47 — a notification with **no sound** (chain slot 3).
5. After "5 dk ertele" — a re-ring that looked like the first alert and was
   silent again.

His requirements, in his words: every alert after the first must be loud; the
task's own due time must ring like an alarm even when a reminder exists; there
must be an indefinite "silence this without completing it"; the number and
spacing of reminders must be configurable (with a 1-minute minimum between
them); the sound must be user-choosable, including an uploaded custom ringtone;
and — the load-bearing one — **the sound must be audible with the screen locked
and the phone silent**, ideally by driving the OS's own alarm UI ("iPhone normal
alarm/sayaç sistemi direk ekran açıyor … asıl istediğim bunu entegre etmek").

What the code actually does today (verified 2026-07-27):

- `effectiveRemindAt(task) = remind_at ?? (is_urgent ? due_at : null)` — **an
  explicit reminder erases the deadline alarm** (#3 above).
- `kUrgentChainOffsets = [0, +2, +5, +10, +30]` is a compile-time constant, and
  a chain exists at all only when `requires_acknowledgement` is true.
- Every slot of an urgent chain ships **identical** iOS content (`sound:
  aw_alarm.caf`, `interruptionLevel: .timeSensitive`) — so the observed
  ding/music/silence pattern comes from the OS, not from our payloads, and we
  had **no diagnostic record** to say which OS behaviour it was.
- `AlarmFeedback` is haptics-only: the in-app ring screen has never made a
  sound, and there is no audio dependency in `pubspec.yaml`.
- **`AlarmKitBridge.swift` is in no Xcode target and `AppDelegate` never
  constructs it** (its own setup doc says so) → `isSupported()` throws
  `MissingPluginException` → the iOS 26 lane that is *designed* to break through
  the mute switch has never once run.

Platform constraints that shape any fix (sources in
[NOTIFICATIONS.md](../NOTIFICATIONS.md) §2–§2d):

- A `timeSensitive` notification sound is a **notification** sound: hardware
  silence and ringer volume win. Only Apple's critical-alerts entitlement
  (effectively refused to task managers — documented in round 6) or **AlarmKit**
  (iOS 26+, user authorization only) get past it.
- `UNNotificationSound(named:)` resolves against the app container's
  `Library/Sounds` first, then the bundle, and **silently substitutes the default
  sound** when a name does not resolve — a known intermittent failure.
- iOS keeps only the **64 soonest** pending local notifications; a longer chain
  multiplies against that budget. AlarmKit does not: one alarm = one entry,
  ring-until-answered is native.
- Android already behaves: `USAGE_ALARM` + `FLAG_INSISTENT` + `setAlarmClock`
  rings through a muted ringer and default DND — but channels are **immutable**,
  so a user-chosen sound means a channel per sound.

## Decision

1. **AlarmKit becomes the primary iOS lane for urgent alarms, for real.** The
   Dart lane already exists; OPH-182 wires the bridge into the Runner target,
   adds the required widget-extension `ActivityConfiguration(for:
   AlarmAttributes<AWAlarmMetadata>.self)` to the existing `AllisWellWidget`
   with `NSSupportsLiveActivities` in both Info.plists, passes the user's sound
   via `AlertConfiguration.AlertSound.named`, localizes the alert buttons through
   the channel, and is signed off on a real iOS 26 device with the mute switch
   ON, a Focus ON and the screen locked. The `timeSensitive` chain remains the
   iOS < 26 / declined-authorization / non-urgent lane. Nothing is ever dropped
   — it degrades, and the degradation is stated in the UI.

2. **A task has up to two alarm instants, each its own reminder row.**
   `alarmInstantsFor(task)` replaces `effectiveRemindAt` and returns `remind`
   (from `remind_at`) and `due` (from `due_at`, when the task is urgent) —
   **independently**; identical instants collapse to one. `reminders.kind`
   (`remind` | `due`) carries this, `reconcileTaskReminder` loops over kinds, and
   the app synthesizes both until the rows sync down. Rationale: a deadline the
   user marked urgent is a promise the product must keep, and a reminder is a
   *nudge before* it, not a *replacement for* it.

3. **One loudness contract.** Every slot of an urgent alarm — first, repeats and
   every post-snooze re-ring — carries alarm-grade delivery and the alarm sound.
   No "quiet first slot" exists anywhere in the design. Normal reminders carry
   the user's reminder sound. The bodies stay honest instead (`urgentFirst`,
   `urgentRepeat(n)`, `afterSnooze(round)`, `dueNow`).

4. **The chain shape is a user-owned profile, stored device-locally.**
   `ReminderProfile.slots` (minutes, sorted, unique, **≥ 1 min apart**, ≤ 20,
   first ≥ 0) is a pure value passed into the planner; the preference lives in
   `localKv` (`alliswell_reminder_profile`), exactly like `notification_privacy`,
   `alliswell_default_task_time` and the board columns. Delivery is a per-device
   concern (each device schedules its own OS notifications from the replica), so
   the profile belongs to the device; the 64-slot cost of the chosen profile is
   shown in the editor rather than trimmed in silence. A cross-device settings
   store is a backlog item, not a blocker.

5. **Silence is a synced task state, not a missing row.**
   `tasks.alarms_muted_at` (null = live) makes indefinite snooze a first-class,
   reversible fact that replicates: instants become empty → the reminder rows are
   cancelled → every device stops ringing. The task stays open, and the UI keeps
   saying the alarm is off (DESIGN §11 A5).

6. **Custom ringtones ride the existing storage pipeline; installation is
   platform-specific.** Uploads are ordinary workspace files (ADR-0011/0014) in
   a reserved "Zil sesleri" folder — so the library is workspace-wide while the
   selection stays device-local. Installation: iOS downloads to
   `<container>/Library/Sounds/<hash>.caf`; Android creates a channel per sound
   hash and prunes stale channels. Format rules (≤ 30 s, aiff/wav/caf with PCM /
   IMA4 / µLaw / aLaw) are enforced **at upload time with a stated reason**;
   anything else may still serve the in-app bed. Server-side transcoding is
   deliberately out of scope.

7. **A new dependency category: an audio player** (`just_audio` +
   `audio_session`, or `audioplayers` — chosen on the first implementation pass
   against these requirements: loop, iOS `AVAudioSession` `.playback`, Android
   `USAGE_ALARM` attributes, macOS/Windows/Linux/web support, fakeable in tests).
   It sits behind the existing `AlarmFeedback` seam, so tests stay silent and
   timer-free. It plays only while the ring screen is in the **foreground** —
   the background-audio-session trick that pre-iOS-26 alarm apps use stays
   rejected (fragile, battery-hungry, dies on force-quit, against the spirit of
   the mode).

8. **Every alarm keeps a local record.** `alarm_events` (~200-row ring buffer,
   never synced) logs scheduled / cancelled / interacted / ring_shown / action
   with lane, kind, slot, sound name and interruption level, surfaced read-only
   in Settings. Round 9 proved that a delivery bug with no evidence trail costs
   more than the feature it hides.

## Alternatives considered

- **Keep pushing on critical alerts.** Round 6 already researched this: Apple
  refuses the entitlement for task managers ("this API is not designed for the
  use you've identified"). The code path stays, gated on the probe, but it cannot
  be the plan. AlarmKit is the sanctioned answer and needs no entitlement.
- **Background audio session to beat the mute switch (the "Alarmy trick").**
  Rejected again: it requires a live background audio session, dies on
  force-quit, drains battery, and misuses `UIBackgroundModes: audio`.
- **Put the reminder profile on the server (workspace/user setting).** Cleaner
  across devices, but it needs a settings store we do not have and would make an
  offline device unable to change its own alerting. Device-local matches the
  existing pattern and ships now; the backlog keeps the option.
- **Keep one reminder row and "move" it to the due time.** That is exactly
  today's bug: one instant cannot express "warn me at 22:42 **and** hold me to
  22:45". Two rows also make per-alarm snooze/acknowledge meaningful.
- **A reminder-count "N times every M minutes" spinner instead of explicit
  slots.** Rejected: the user asked for per-step control ("ilkini 30 sn sonra,
  ikincisi şöyle"), and explicit slots are what the planner already consumes.
  Presets (Sakin/Standart/Israrcı) cover the simple case.
- **Drag-to-reorder the chain steps.** A sorted numeric chain re-sorts itself
  instantly, so the gesture would visibly do nothing (NN/g). Drag lands on the
  snooze-preset order instead, where the user's order is the actual data.
- **Server-side transcoding of uploaded ringtones (ffmpeg).** Real value (mp3
  would just work), but it adds a media-processing dependency to the API for a
  cosmetic gain; refusing an unusable file with a clear reason is honest and
  costs nothing. Backlogged.

## Consequences

- **Easier:** an alarm that behaves like an alarm on iOS 26+ (full-screen, mute-
  and Focus-proof, native snooze) and on Android (already there); one seam
  (`alarmInstantsFor`) for every alarm instant; alerting that users can tune
  without a release; the next device round argues from a log instead of memory.
- **Harder / riskier:** three migrations (`reminders.kind`, `reminders.snooze_count`,
  `tasks.alarms_muted_at`) and drift v8 on the client; two lanes to keep
  behaviourally identical (notification vs AlarmKit) — the scheduler's set-diff
  is what keeps them honest; AlarmKit compiles only against the iOS 26 SDK, so
  `flutter analyze`/`test` cannot protect it (same class of risk as the widget
  extension, Epic 12) and a real device is mandatory; the AlarmKit alarm limit is
  undocumented, so the lane stays windowed and logs rejections; a channel-per-
  sound scheme on Android must prune, or Settings fills with dead channels.
- **Follow-ups created:** the Epic 16 device matrix (OPH-182/183) including a
  real Apple Watch; the watchOS-companion decision; server-side ringtone
  transcoding and a cross-device settings store in the backlog; per-task
  reminder-profile overrides (only if the global profile proves insufficient —
  deliberately not shipped now).
