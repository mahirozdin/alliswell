# Google Play — exact alarm permission declaration

Everything needed to submit the `USE_EXACT_ALARM` declaration, in one place.
The decision and its measurements are in [ADR-0037](../adr/0037-android-exact-alarms-are-declared-not-begged-for.md);
this file is the submission itself.

> **Status:** not yet submitted. The form, the video and the review are the
> owner's to do — they need Play Console access.

---

## 1. Where the form is

**Play Console → App content → Restricted permissions → Exact alarm permission.**

It appears once a build declaring `USE_EXACT_ALARM` has been uploaded. Without
an approved declaration the app cannot publish updates at all — this is not a
feature flag, it is a gate on the whole release.

Expect the review to take **weeks, not days**, and expect the app to sit in
"pending publication" while it runs. Submit it well before a release you care
about.

## 2. Which acceptable use case we claim

Google lists exactly two:

- the app is an **alarm or timer app**;
- the app is a **calendar app that shows event notifications**.

**AllisWell claims the first, and can support the second.** The Play listing is
*"AllisWell: Todo and Reminders"*. Its urgent reminders are alarms in the strict
sense: they ring through at a set time, they repeat on a re-alert chain, and
they must be acknowledged rather than swiped away. It also syncs Google and
Apple calendars two ways and notifies on events, which is the second case.

## 3. What to write in the form

> AllisWell is a reminders app. Its core feature is an alarm the user sets for
> an exact time — a medication dose, a meeting, a deadline — which rings at that
> time and must be acknowledged before it stops. Users mark these reminders
> "urgent", which puts them on an insistent alarm channel with a repeating
> re-alert chain, exactly like a clock app's alarm.
>
> A privacy-friendlier alternative does not work for this feature. Inexact
> alarms are batched by the system and can fire minutes to hours late; a
> reminder that arrives "around" the time it was set for is not a reminder, and
> for a medication dose it is actively harmful. Push notifications are not an
> alternative either: AllisWell schedules alarms on the device from locally
> synced data precisely because FCM makes no delivery-time guarantee, and
> because the app is offline-first — an alarm set on a plane must still ring on
> that plane.
>
> The permission is used for nothing else. AllisWell requests no location, no
> contacts, no media permissions, and no background location.

## 4. What the video must show

A missing or unclear video is one of the most common rejection reasons, so the
video is not a formality — it is the evidence. It should be **short (60–90
seconds), unedited, and show the clock**.

Record on a device or emulator running **Android 14 or newer** (the behaviour
the permission exists for only appears there), sign in first so the reviewer
never sees a login wall, and keep the system clock visible throughout.

1. **Open AllisWell and create a task** — something an alarm is obviously for.
   "Take medication" reads better to a reviewer than "test 1".
2. **Set a reminder for a time two or three minutes ahead**, on camera, so the
   reviewer sees the exact time being chosen. Say it out loud or caption it.
3. **Turn on "Urgent alarm"** and show the subtitle: *"Insistent reminder that
   must be acknowledged."* This is the sentence that makes the case — it is what
   separates an alarm from a notification.
4. **Leave the app.** Go to the home screen, or lock the device. The reviewer
   needs to see that the alarm does not depend on the app being open.
5. **Wait on camera** until the stated time. Do not cut. The whole claim is
   about exactness, so the cut is the thing that would undermine it.
6. **The alarm fires at that minute** — full-screen, sounding, with the
   acknowledge action. Show the clock in the same frame as the alarm.
7. **Acknowledge it** and show that it stops, and that snoozing offers real
   presets (5 min / 30 min / 1 hour / tomorrow).

Optional but strong, if there is room: show **Settings → Alarm log**, which
records what the device actually did with each alarm. It demonstrates that the
exactness is something the app treats as a contract, not a hope.

**Do not use a real personal account.** The video goes to Google reviewers and
is attached to a public submission; record with a throwaway demo account whose
tasks are all props.

## 5. Where the video goes

The declaration form asks for a **link**, not a file upload — an unlisted
YouTube video or a Google Drive link with link-sharing on is what reviewers
expect. Upload it there and paste the URL into the form.

A copy can live in this repository for reference, but do not submit a repository
URL as the video link: reviewers need something that plays in a browser without
a download.

## 6. If it is rejected

A refusal is recoverable and is not a strike against the account. Remove
`USE_EXACT_ALARM` from the manifest (`SCHEDULE_EXACT_ALARM` alone still works,
and the in-app `AlarmProblem.exactAlarmsOff` prompt is what carries users
through the system settings page), ship that build to unblock publishing, and
resubmit the declaration separately with a clearer video.

The usual reasons, in order: the video does not show the feature actually
working; the video shows a login screen the reviewer cannot get past; the
declaration describes the app rather than the permission's role in it.
