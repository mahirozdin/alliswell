# ADR-0037 — Android exact alarms are declared, not begged for

- **Status:** Accepted
- **Date:** 2026-09-14
- **Related task:** OPH-304 (Epic 29, request round 22)

## Context

A user reported that AllisWell's alarms fire on their iPhone — in airplane
mode, even — but not on a Samsung Galaxy A12. Reading the code found no defect:
the manifest declares `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `USE_FULL_SCREEN_INTENT` and the boot
receivers, and an A12 ships Android 11–12, where `SCHEDULE_EXACT_ALARM` is
granted at install.

Looking into it surfaced something larger than the reported device, and it was
**measured on an API 36 emulator rather than reasoned about**:

```
$ adb shell dumpsys package com.alliswell.alliswell | grep -i alarm
      android.permission.SCHEDULE_EXACT_ALARM          # requested
      android.permission.USE_FULL_SCREEN_INTENT: granted=true

$ adb shell dumpsys package permission android.permission.SCHEDULE_EXACT_ALARM
    prot=signature|privileged|appop
Packages:                                              # ← EMPTY. Not us.

$ adb shell dumpsys package com.alliswell.alliswell | grep targetSdk
    versionCode=38 minSdk=24 targetSdk=36
```

`SCHEDULE_EXACT_ALARM` is an **appop** permission, not an install-time one. We
target SDK 36, and from Android 14 an app targeting 33+ starts with it denied:
the user must find **Settings → Apps → AllisWell → Alarms & reminders** by hand.

That is not a thing a person does for an alarm they have not yet missed. The
failure it produces is also the worst kind — silent, and indistinguishable from
"this app's reminders just do not work". Every Android 14, 15 and 16 install is
in that state today, which is a much bigger population than one Galaxy A12.

## Decision

**Declare `USE_EXACT_ALARM` alongside `SCHEDULE_EXACT_ALARM`, and accept the
Google Play restricted-permission review that comes with it.**

Measured after the change, on the same emulator, on a fresh install:

```
$ adb shell dumpsys package com.alliswell.alliswell | grep -i EXACT_ALARM
      android.permission.USE_EXACT_ALARM
      android.permission.SCHEDULE_EXACT_ALARM
      android.permission.USE_EXACT_ALARM: granted=true      # ← no user action
```

Both permissions stay. They are not alternatives: `USE_EXACT_ALARM` exists from
API 33, and `minSdk` is 24 — the older half of the install base reaches exact
alarms through `SCHEDULE_EXACT_ALARM`, exactly as it always has.

The permission is added to `scripts/android/allowed-permissions.txt`, whose
check reads the built APK's binary manifest — the merged manifest is where the
truth lives, and an exact-set diff is what makes a permission nobody
anticipated impossible to ship quietly (OPH-244).

## Alternatives considered

**Keep `SCHEDULE_EXACT_ALARM` alone and make the in-app prompt insistent.** The
diagnostic already exists — `AlarmProblem.exactAlarmsOff` and the fix sheet
(OPH-277) name the switch and open the page that holds it. This costs no review
and no policy risk, and it was the option the round's plan leaned toward.

It lost on what it asks of the user. An alarm app whose alarms are off until
you visit a settings page you have never heard of is an alarm app that fails
the first time it matters, and the report this round came from is a user who
had already reached that state and could not explain it. The prompt remains —
it is the only thing that helps a user who declines or revokes — but it is a
safety net, not the plan.

**Lower `targetSdk` below 33.** Not available: Google Play requires recent
target API levels for updates, and pinning backwards to dodge a permission
policy is the kind of debt that comes due on somebody else's schedule.

## Consequences

**The risk is real and it is a publishing risk, not a runtime one.**
`USE_EXACT_ALARM` is a Play **restricted permission**: a declaration form under
*Play Console → App content → Restricted permissions*, a video showing the core
feature that needs it, and a manual review. Google's listed acceptable cases
are "an alarm or timer app" and "a calendar app that shows event notifications".
AllisWell is listed as *"AllisWell: Todo and Reminders"*, its urgent alarms are
insistent and must be acknowledged (DESIGN §11, NOTIFICATIONS.md §2), and it
syncs and shows calendar events — the case is arguable on both grounds. It is
**not automatic**, and a refusal blocks publishing updates, not just this
feature. A rejection is recoverable by removing the permission and resubmitting;
plan for the review to take weeks, not days.

**What the declaration must say, and what the video must show.** The form asks
why the permission is core and why a privacy-friendlier alternative does not
work. The honest answer is in `docs/NOTIFICATIONS.md` §0: each device schedules
its own OS-level alarms from local data, because push makes no timing
guarantees — an alarm that arrives "around" the time it was set for is not an
alarm. The video has to show that: a reminder set for a stated time, the alarm
firing at that time, and the acknowledgement it demands. A missing or unclear
video is one of the common rejection reasons.

**This does not fix the reported Galaxy A12.** That device is Android 11–12,
where `SCHEDULE_EXACT_ALARM` was already granted, so the cause is elsewhere —
battery optimisation, a reminder created on another device that this one never
synced (see the backlog's push wake-up item), or something the **Alarm log**
(Settings → Alarm log, OPH-176) will name. That thread stays open and needs the
reporter's data.

**Follow-ups.** The declaration and the video are the owner's to submit, and
`docs/store/` carries the wording. The `AlarmProblem.exactAlarmsOff` banner
still needs its first real run on an Android 14+ device: with this permission
granted at install it should now be silent, and a banner that fires when
nothing is wrong would be its own bug.
