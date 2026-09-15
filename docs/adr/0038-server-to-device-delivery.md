# ADR-0038 — Server→device delivery: a hint everywhere, the clock only on the web

- **Status:** Accepted
- **Date:** 2026-09-15
- **Related task:** OPH-308 (Epic 30, request round 22)

## Context

Two reports from the same user, both parked out of Epic 29 with their evidence
([#15](https://github.com/mahirozdin/alliswell/issues/15),
[#16](https://github.com/mahirozdin/alliswell/issues/16)):

> "when i pre-set the 'reminder alarm' using the desktop interface, it does not
> trigger on my phone."

> "Any way to set a reminder which does not 'ring' with sound, but just pops up
> with a window on the computer screen … so it is less disturbing to colleagues
> during office hours."

Neither is a defect. [NOTIFICATIONS.md §0](../NOTIFICATIONS.md) says what the
product does and why:

> each device schedules its own OS-level notifications from local data … Push
> arrives later only as a *wake-up hint* — IDs only, never content (§8.3) — and
> as a backup for devices whose local schedule went stale.

That model is right and stays. It works offline, and it does not hand timing to
a service that makes no timing guarantees. It has exactly one assumption, and
both reports are that assumption failing: **the device is running.** A phone
that has not opened AllisWell since the change never learns about it
(`notifications/providers.dart:175` subscribes to the local replica; there is no
background sync). A browser that must alert at 14:03 is not running at 14:03.

Measured for this decision:

| Question | Finding |
| --- | --- |
| Can a browser schedule a local notification? | **No.** Notification Triggers (`showTrigger`/`TimestampTrigger`) never shipped — two Chrome origin trials, then [development stopped](https://developer.chrome.com/docs/web-platform/notification-triggers). |
| Is `silent: true` honoured everywhere? | **No.** Chromium applies it; [Firefox ignores it and plays a sound](https://developer.mozilla.org/en-US/docs/Web/API/Notification/silent). |
| May a push handler stay quiet? | **No.** `userVisibleOnly: true` is a promise; a handler that shows nothing gets Chrome's own generic card instead. |
| Is iOS silent push a schedule? | **No.** [Apple](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) caps it at two or three an hour, against a device-wide energy budget, and reserves the right to delay or drop. |
| Who already gets a given alarm? | Every member of the task's workspace — `reminder_store.dart:83-99` filters on `workspaceId` alone, and core has no assignee. |
| Does the server know when a reminder fires? | Yes. Reminder rows are server-owned (the client may only write `status`), and `idx_reminders_due (status, remind_at)` has existed, unused, since 2026-07-14. |
| Is there a push sender? | No. EE wrote the channel and left `transport` **null** (`ee/server/modules/teams/index.js:324`), and its own header records that no client has ever sent a token. |

## Decision

**1. Three triggers, in descending order of grace.** A *wake-up hint* when a
reminder changes, so the device syncs and the real local alarm fires with its
full behaviour — urgent full-screen, the user's sound, the acknowledgement
chain. A *visible, content-free push* at fire time for a device whose local
schedule is stale. A periodic refresh underneath both.

**2. Staleness is one comparison:** `notification_devices.last_seen_at` against
`reminders.updated_at`. A device that synced after the change already holds the
alarm and is **not** pushed to. The same line answers "who needs this" and
"who must not be woken twice".

**3. On the web the server is the clock.** This amends §0 for one platform, and
only because the platform has no alternative: there is no scheduled local
notification API in any browser. Everywhere else the server stays a hint and the
device stays the clock.

**4. A payload names rows; it never carries what they say.** One builder —
`apps/api/src/lib/push/payload.js` — and every transport calls
`assertPushPayload` before sending, so a body assembled anywhere else has no way
onto the wire. Keys are declared; **values are checked too**, because the quiet
leak is not a key called `title` but `taskId` holding a sentence. Ids must be
ULID-shaped, the instant must be an ISO instant, and a *visible* push carries
the **name** of a fixed message from a closed set, never the message.
`npm run check:push-payload` diffs what the code would send against
`scripts/push/allowed-payload-keys.txt` and independently rebuilds every payload
beside a task whose every field is a sentence, failing if any of it reaches the
wire.

**Amended by OPH-320 for the mobile lane.** A browser resolves the name itself:
the service worker reads the words from a cache the app wrote. A force-quit
phone has no running code to resolve anything with — APNs renders the alert
from what the push carries, or nothing appears, and "nothing appears" is the
one outcome the guaranteed half of this design exists to prevent. So an FCM
message whose payload names a *visible* alert also carries a `notification`
block holding a **fixed sentence from a closed catalogue** (`PUSH_ALERT_TEXT`),
identical for every user of every instance. The payload contract is unchanged;
the words travel beside it, and the allowlist now holds every one of them, so a
reviewer sees the exact strings this server can put in front of a push provider
and changing a letter is a diff. A task's title and contents still never make
the trip, which is the sentence `docs/PRIVACY.md` actually prints.

**5. Recipients are the task's workspace members.** Not a widening: those are
exactly the devices that already schedule the alarm locally today.

**6. FCM for mobile, Web Push (VAPID) for browsers.** FCM relays to APNs, so
there is no second provider integration; the service-account JWT is signed with
`node:crypto` rather than pulling in `firebase-admin`. Web Push needs RFC 8291
encryption, and hand-writing ECDH + HKDF + AES-128-GCM produces something that
fails *silently* when it is wrong — so `web-push` is taken as a dependency. Web
gets no Firebase, which keeps [ADR-0025](0025-firebase-optional-and-credential-hygiene.md)
§5 ("web has no implicit config") true.

**7. All of it is core, and off without credentials.** No key, no registration,
no send, and `GET /api/v1/push/public-key` is registered conditionally so it
404s on an instance that has not configured push — the same 404 answers "no key"
and "this server does not do that".

**8. iOS does not get the headless wake in this round.** The session is stored
under `kSecAttrAccessibleWhenUnlocked` (`secure_secret_store.dart:10-25` passes
no `iOptions`), so a 3 a.m. wake on a locked phone reads `null`, decides it is
signed out, and syncs nothing — **the most valuable wake is the one that
structurally cannot run.** Add the missing `aps-environment`, the absent
`UIBackgroundModes`, the delivery budget above, and an AlarmKit bridge that a
background engine never constructs (`AppDelegate.swift:22-30`). iOS is served by
the visible fallback, which needs none of that and works with the app
force-quit. Changing the Keychain accessibility is a security decision with a
re-key migration and gets its own ADR.

## Alternatives considered

- **Put the title in the payload.** Best notification, and it breaks a sentence
  `docs/PRIVACY.md` already prints. Rejected: the device has the text.
- **Let each client upload its own alert plan.** Rejected — the server already
  materialises `remind_at` and already has the index to find it; the client
  would be telling it something it knows.
- **Expand recurrence server-side in JS.** Rejected: the rule maths is Dart's,
  and `recurrence_parity.json` exists because keeping two copies honest is a
  standing cost we did not want to add to.
- **Write `delivered` onto `reminders.status` for idempotency.** Rejected: that
  is a revision per reminder per fire time, pushed to every device — a sync
  storm at exactly the busiest minute. Delivery is logged on a table nobody
  syncs.
- **Generate the payload fixture from the code.** Rejected as circular; a gate
  that reads what it does not measure is not a gate. The allowlist is policy a
  person agreed to, in the shape `scripts/android/allowed-permissions.txt`
  established.
- **Send a localisation KEY instead of the sentence** (`loc-key`,
  `body_loc_key` — both APNs and FCM resolve them against the app bundle's own
  strings). It would keep even the generic sentence off the wire, and it was
  rejected for a measured reason: those keys resolve in the DEVICE'S OS
  language, while AllisWell's language is an in-app setting. A phone running in
  English with the app set to Turkish would be told in English.
  `notification_devices.locale` exists because that difference is real
  (OPH-309), and a reminder arriving in a language the user did not choose is a
  worse failure than a public sentence that says only what the push's existence
  already says.
- **Talk to APNs directly.** Rejected: FCM already relays, and a second provider
  is a second set of credentials for the same result.
- **Take the `workmanager` package for the Android refresh.** Rejected:
  `androidx.work` is already inside the APK via home_widget, the app already has
  a background dispatcher, and a thinly-maintained Kotlin plugin on AGP 9 is a
  risk this repo has already been bitten by once.

## Consequences

- `docs/PRIVACY.md` (EN and TR) must change when the first real send lands
  (OPH-315). *"Today nothing is pushed from our servers to them"* stops being
  true. *"Your task titles and contents are not sent to Apple's, Google's, or
  anyone else's push service"* stays true, and decision 4 is what keeps it true.
- A new gate runs in CI, and a new dependency category (`web-push`) enters the
  API.
- A self-hoster without credentials sees no change at all — which is a number a
  test can assert, not a claim.
- On iOS, a reminder created elsewhere arrives as a content-free alert rather
  than the full alarm until the app has synced. Better than silence, worse than
  a local alarm, and said out loud rather than implied.
- Core will expose the transport EE's push channel has been waiting for. Wiring
  it is one line, in the EE repository, and not part of this epic.
