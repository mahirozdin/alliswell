# Store listing — AllisWell

Ready-to-paste copy for the **Apple App Store** and **Google Play**, for the
**1.1.0** launch. Every character-limited field shows its real count.

> **Paste the right one.** §1 is Apple's, §2 is Play's, and they are not
> interchangeable — Play's release of version code 16 was rejected on
> 2026-08-02 with §1.4's wording in the Play listing. Play indexes the whole
> description where Apple has a separate keyword field, so the two are written
> differently on purpose.

> **Assets are generated, not hand-made.** Everything in §3 is produced by
> `node scripts/screenshots/store.mjs` from the real device captures in
> `screenshots/` — see [SCREENSHOTS.md](SCREENSHOTS.md). Regenerate after any
> UI change rather than editing a PNG.

Everything here was written against the shipped code (`README.md`,
`docs/SELF-HOSTING.md`, `docs/PRIVACY.md`, the 0.4.0 CHANGELOG entry) — see
[§5 Claim guardrails](#5-claim-guardrails) for the lines that were deliberately
_not_ written, and why. **Read §5 before editing any of this copy.**

---

## 1. Apple App Store

### 1.1 App name (≤ 30 characters)

| #                     | Option                              | Count       |
| --------------------- | ----------------------------------- | ----------- |
| **A** _(recommended)_ | `AllisWell`                         | **(9)**     |
| B                     | `AllisWell: Tasks & Reminders`      | **(28)**    |
| C                     | `AllisWell - Tasks & Alarms`        | **(26)**    |
| D                     | `AllisWell: ToDo, Reminders, Notes` | **(33)** ❌ |
| **D′**                | `AllisWell: ToDo & Reminders`       | **(27)**    |
| D″                    | `AllisWell: Tasks, Notes & Alarms`  | **(32)** ❌ |

**On “AllisWell: ToDo & Reminders & Notes”** — the phrasing the owner asked for
is **38 characters**, eight over Apple's hard 30-character limit, and Play's
title cap is 30 too. It cannot be used verbatim on either store. The nearest
legal spellings are **D′** (27) here, and the longer **`AllisWell: ToDo,
Reminders & Notes`** (33) is _also_ over — the third noun does not fit next to
the brand on Apple. Play has no keyword field, so spend its 30 there instead
(see §2.1); Apple's subtitle is a separate indexed field, so use it for the
nouns that will not fit in the name.

**Why A.** The name field and the subtitle are indexed separately, and both are
indexed _in addition to_ the keywords field. Keeping the name to the bare brand
frees "tasks", "reminders" and "alarms" to be spent in the subtitle — where they
still rank — and keeps the home-screen label clean. Pick B only if you want the
category words visible in search results rather than just indexed.

### 1.2 Subtitle (≤ 30 characters)

| #                                        | Option                          | Count    |
| ---------------------------------------- | ------------------------------- | -------- |
| **A** _(recommended, pairs with name A)_ | `Tasks, notes and real alarms`  | **(28)** |
| B                                        | `Tasks, notes, files & alarms`  | **(28)** |
| C                                        | `source-available task manager` | **(29)** |

**Recommended pairing: name A + subtitle A.** The keywords in §1.5 are built
around exactly that pairing.

### 1.3 Promotional text (≤ 170 characters)

Editable without a new build — use it for launch beats and swap it later.

```text
Reminders that ring at the exact minute, with a real alarm sound. Repeats that never skip a month. Two-way calendar sync. Free, no ads — sign in with Google or Apple.
```

**(164)** — current, for the 1.1.0 launch.

<details>
<summary>Alternates, all counted</summary>

```text
Alarm-grade reminders that keep coming back until you acknowledge them, a kanban board, rich notes and two-way Google Calendar sync. Free, and no ads.
```

**(159)**

```text
Tasks, notes and reminders loud enough to actually move you. Ask for the 31st and February answers with the 28th. Free, no ads, no paid tier.
```

**(154)**

</details>

<details>
<summary>Alternate promo lines</summary>

```text
source-available and free. Tasks, notes and files in one place, with reminders loud enough to actually move you. No ads, no paid tier.
```

**(158)**

</details>

### 1.4 Description (≤ 4000 characters)

```text
AllisWell keeps your whole day in one place: tasks, projects, notes and files, with reminders strong enough to actually get you out of a meeting on time.

The source is public, there is no paid tier, and there are no ads.


ONE PLACE FOR THE WHOLE DAY

• Capture a task in seconds, with or without a date. An Inbox holds unplanned thoughts until you are ready to schedule them.
• Home lays the day out chronologically — overdue, today, this week, the next 30 days — next to a month calendar.
• Flip the same day into a Board: kanban columns you name, hide and reorder, with drag-to-move.
• Projects get colors, favorites, archiving, and their own Tasks, Notes and Files tabs.
• Tag inline by typing #tags, and set priority from none up to urgent.


REMINDERS THAT DO NOT WHISPER

• Reminders arrive at the exact minute you set them, not "around then".
• Urgent tasks ring with a real alarm sound instead of a notification chime.
• Ignore one and it keeps coming back, re-alerting on a chain across the next half hour until you acknowledge it.
• Snooze in one tap: 5 minutes, 30 minutes, an hour, or tomorrow morning.
• A privacy mode hides task content on the lock screen.


NOTES AND FILES

• Markdown notes with live syntax as you type and a real reading view, inline images, linked to your tasks and projects, exportable as .md or PDF.
• A full Markdown workspace: tables, checklists, code, maths and diagrams, with reading, rich and source views. Open a .md file from your device, edit it, and save it back to that file.
• Attach files to tasks, notes and projects — up to 10 MB per file on the hosted service.
• A workspace-wide Files section with nestable folders, plus a Files tab inside every project.


ONE ACCOUNT, EVERY DEVICE

Sign in once and your tasks, projects and notes follow you: a change you make on your iPhone lands on your iPad, your Mac and the web in realtime.


CALENDARS

• Google Calendar syncs both ways — your tasks become events, and edits you make in Google come back to AllisWell. Your other Google events show up next to your tasks on Home.
• Apple Calendar is one-way in this version: the tasks you choose are written into the calendar you pick.


SEARCH THAT IGNORES ACCENTS

Search ignores case and accents across the Latin alphabets, so "muller" finds "Müller" and "cafe" finds "café". It runs on the device, so it answers instantly as you type.


ALSO IN THE BOX

• Home-screen widgets mirroring your Home buckets (iPhone, iOS 16 and later).
• English and Turkish, following your system language.
• Light and dark.


YOURS TO HOST

The entire app and server are public on GitHub, and you can run the whole thing yourself with a single docker compose command — your data in your own MySQL, on your own machine, reachable at your own domain. Free for personal use. Use our hosted service or your own server; it is the same app either way.


NO PAID TIER. NO ADS.

There is no subscription and nothing locked behind one, and there is no advertising, attribution or fingerprinting SDK. We do not sell or rent your data, and we never share it for advertising.

The app does send crash reports and basic usage and performance diagnostics to Firebase, tagged with a random account id, so we can fix what breaks. The content you write — task titles, note bodies, file names — is never attached to any of it, and self-hosted builds send none of it.

You can delete your account and everything in it from Settings, in the app, without asking us.


Privacy policy: https://alliswell.space/privacy
Source code: https://github.com/mahirozdin/alliswell
```

**(3151 / 4000)**

### 1.5 Keywords (≤ 100 characters total, comma-separated, no spaces after commas)

Built for **name A + subtitle A**. Apple indexes the app name and subtitle
separately, so nothing from `AllisWell` / `Tasks, notes and real alarms` is
repeated here — every character buys a _new_ term.

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,notes,sync,selfhosted
```

**(97 / 100)** — 13 terms, no spaces, no duplicates of the name or subtitle.

Notes:

- Apple auto-combines terms, so "task manager" is already covered by `manager`-free
  combinations of the subtitle's _tasks_ with `planner` / `organizer`. Do not
  waste characters on multi-word phrases.
- Do **not** add competitor names (Todoist, Things, TickTick, Notion). Apple
  rejects trademarked terms in the keyword field.
- `opensource` was removed when the licence changed: the app is
  **source-available** (PolyForm Noncommercial), and a keyword that misdescribes
  the licence is a claim we cannot back.
- If you switch to name B, delete `reminder` from this list and spend the freed
  ~9 characters on `notes,files` — but see the count first.

<details>
<summary>Alternate keyword sets</summary>

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,files,sync,alarm,notes
```

**(97)** — trades `selfhosted` for two consumer terms.

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,notes,sync,habit,list
```

**(97)** — drops the self-hosting angle for two broader consumer terms.

</details>

### 1.6 URLs

| Field                               | URL                               | Status                                                           |
| ----------------------------------- | --------------------------------- | ---------------------------------------------------------------- |
| **Support URL** _(required)_        | `https://alliswell.space/support` | ✅ Live — generated from `docs/SUPPORT.md`                       |
| **Marketing URL** _(optional)_      | `https://alliswell.space`         | ✅ Live — `apps/landing`                                         |
| **Privacy Policy URL** _(required)_ | `https://alliswell.space/privacy` | ✅ Live — generated from `docs/PRIVACY.md` (TR at `/privacy/tr`) |
| **App URL** (for reviewers)         | `https://alliswell.space/app`     | ✅ Live — the full web app                                       |

**All three pages now exist**, deployed from `apps/landing` to the root of
alliswell.space with the app under `/app`. `/privacy` and `/support` are
generated at build time from `docs/PRIVACY.md` and `docs/SUPPORT.md`, so the
website and the repo can never state different policies. Remaining checks:

1. **`/privacy`** — publish `docs/PRIVACY.md` as a real HTML page, with the
   Turkish version (`docs/PRIVACY.tr.md`) at `/privacy/tr` or behind a language
   switch. Apple and Google both fetch this URL and both reject a 404 or a raw
   GitHub link that redirects.
2. **`/support`** — needs a working contact route. A page with the support
   mailbox, a link to GitHub Issues, and a short FAQ is enough. Apple checks that
   it loads and that it actually offers a way to reach a human.
3. **`/`** — marketing home. ✅ Shipped: `apps/landing`, a Vue 3 site built and
   deployed by the same workflow as the app. Add `/privacy` and `/support` as
   routes there rather than as separate hosting.
4. ✅ **Resolved:** the policies used to name `privacy@alliswell.space`, a mailbox
   that did not exist. Both now name **info@bubiapps.com**, which does — a dead
   privacy contact is a rejection in both stores.
5. **Data controller** in both policies is
   **BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI** (Talas / Kayseri,
   Türkiye). The App Store and Play seller name must match it.

### 1.7 Category

| Slot          | Choice           | Reasoning                                                                                                                                                                                                                                            |
| ------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Primary**   | **Productivity** | The app's core loop is capture → plan → complete across tasks, projects, notes and files; Productivity is where every direct comparison (Todoist, Things, TickTick) sits, and it is the category reviewers will expect from the screenshots.         |
| **Secondary** | **Utilities**    | The alarm-grade reminder engine, the widgets and the self-hosting story read as utility rather than lifestyle; Utilities is a far less crowded second shelf than Business and does not invite the enterprise-feature comparisons that Business does. |

_Alternate secondary:_ **Business**, if you intend to market self-hosting to
teams rather than to individuals. Pick one and keep it stable — category changes
reset some ranking signals.

### 1.8 Age rating

Target: **4+ / Ages 4 and up.** Answer every content question with **None**.

| Question                                          | Answer                                  |
| ------------------------------------------------- | --------------------------------------- |
| Cartoon or Fantasy Violence                       | None                                    |
| Realistic Violence                                | None                                    |
| Prolonged Graphic or Sadistic Realistic Violence  | None                                    |
| Profanity or Crude Humor                          | None                                    |
| Mature/Suggestive Themes                          | None                                    |
| Horror/Fear Themes                                | None                                    |
| Medical/Treatment Information                     | None                                    |
| Alcohol, Tobacco, or Drug Use or References       | None                                    |
| Simulated Gambling / Contests                     | None                                    |
| Sexual Content or Nudity / Graphic Sexual Content | None                                    |
| Unrestricted Web Access                           | **No** — the app has no in-app browser. |
| Gambling                                          | No                                      |
| Contests                                          | No                                      |

**Additional questions**

- **Does your app contain user-generated content?** **Yes** — users create
  tasks, notes, projects and file uploads.
- **Is that content shared with, or visible to, other users?** **No.** Content is
  private to the account. There is no public feed, no discovery surface, no
  comments, no messaging, and no way for one user to browse another's content.
  Because there is no user-to-user exposure, Apple's UGC moderation requirements
  (filtering, reporting, blocking) do not apply — say this in the review notes.
- **Unrestricted web access:** No.
- **Does the app use encryption?** Yes, but **exempt** — HTTPS/TLS only, using
  the OS-provided implementation, plus standard password hashing. Set
  `ITSAppUsesNonExemptEncryption` to `false` in `Info.plist` to skip the export
  compliance prompt on every upload.
- **Third-party analytics / advertising / tracking:** the app ships **no
  advertising, attribution or fingerprinting SDK**, but since 1.1.0 it does ship
  **Firebase Analytics, Crashlytics and Performance** (ADR-0025) — declare
  _Diagnostics_ and _Usage Data_, "Linked to You" via the random account id,
  **not used for tracking**. `apps/app/ios/Runner/PrivacyInfo.xcprivacy` declares
  `NSPrivacyTracking = false` with an empty tracking-domains list, which stays
  accurate: none of it follows the user across other companies' apps or sites.
  Answer **No** to App Tracking Transparency — do not add the ATT prompt.

**Review notes to paste into App Store Connect**

```text
Demo account: <create one on the hosted service and put the credentials here>

AllisWell is a personal task, notes and file manager. All content is private to
the signed-in account: there is no sharing, no public content, no messaging and
no discovery between users.

The app requests Calendar (EventKit) access only to write the tasks you choose
into a calendar you pick, and to enumerate your calendars so you can pick one.
It is skippable — the app is fully functional if you decline.

Notifications are used for task reminders. Urgent tasks use time-sensitive
delivery with a bundled alarm sound. The app does not request the critical
alerts entitlement.

The app is source-available (PolyForm Noncommercial 1.0.0): https://github.com/mahirozdin/alliswell
Users may also run their own server; the "server address" field in the sign-in
screen exists for that and defaults to our hosted service.
```

### 1.9 What's New (0.9.0)

```text
Reminders that actually get you moving — and repeats that never skip a month.

ALARMS, NOT NOTIFICATIONS
Urgent tasks now ring with a real alarm through Silent mode and Focus, and keep re-alerting until you acknowledge them. Snooze presets tell you exactly when they will ring again, you can silence one task without completing it, and there is a log you can read when your phone gets in the way.

REPEATS THAT CLAMP INSTEAD OF SKIPPING
Every day, every weekday, the last day of the month, the 2nd Tuesday. Ask for the 31st and February gives you the 28th — it does not drop the month. A live preview shows the next five dates before you commit, and editing one occurrence asks how far the change should reach.

EVERY TASK ON YOUR CALENDAR
The calendar mirror is no longer a setting you have to find. Your tasks are simply there, and your Google events show up next to them.

CHAT WITH YOUR TASKS — OR DON'T
Connect AllisWell to the Claude or ChatGPT subscription you already have, or bring your own API key. Press and hold to speak a task into being; share any text or link straight into the app. Everything it suggests waits for your tap, and none of it is required.

QUICK ACCESS
A personal shortcut list for the projects, notes and files you actually live in — with your own emoji, colour and order.

ALSO
• Completed work now has a timeline you can scroll back through
• Swipe to delete, everywhere, with an undo
• A faster, calmer Home

Found something wrong? https://github.com/mahirozdin/alliswell/issues
```

**(1489 / 4000)**

<details>
<summary>Previous — What's New (0.4.0)</summary>

```text
This is the big one — everything since the first release.

BOARD VIEW
Home now flips between the chronological list and a kanban Board, with status columns you name, hide and reorder, and drag-to-move between them.

A REAL FILES SECTION
Attach files to tasks, notes and projects, and find every one of them in a workspace-wide Files section with nestable folders. Every project gets its own Files tab too.

ALARMS THAT MEAN IT
Urgent tasks now ring at their deadline with a real alarm sound, and keep re-alerting across the next half hour until you acknowledge them. Snooze in one tap, and turn on the privacy mode to keep task content off your lock screen.

SEARCH THAT IGNORES ACCENTS
Search now ignores case and accents everywhere — "muller" finds "Müller", "cafe" finds "café" — and it runs on the device, so it is instant.

CALENDAR SYNC THAT JUST CONNECTS
Linking Google Calendar now picks your primary calendar and syncs straight away. The hidden second step is gone.

ALSO
• Home-screen widgets mirroring your Home buckets
• A refreshed look, checked for contrast in light and dark
• English and Turkish throughout
• Run the whole thing on your own server with one command — see the repo

Found something wrong? Tell us at https://github.com/mahirozdin/alliswell/issues
```

**(1294 / 4000)**

</details>

---

## 2. Google Play

### 2.1 App title (≤ 30 characters)

| #                     | Option                         | Count    |
| --------------------- | ------------------------------ | -------- |
| **A** _(recommended)_ | `AllisWell: ToDo & Reminders`  | **(27)** |
| B                     | `AllisWell: Tasks & Reminders` | **(28)** |
| C                     | `AllisWell - Task & Note App`  | **(27)** |
| D                     | `AllisWell`                    | **(9)**  |

**A over B** on Play specifically: “ToDo” is the higher-volume query on Android
and Play matches the title literally, where Apple's engine already covers
_tasks_ from the subtitle. The three-noun form the owner asked for
(`ToDo & Reminders & Notes`) is **38 characters** — over Play's 30-character cap
as well — so “Notes” moves into the **short description** (§2.2), which Play
also indexes.

**Why A here but not on Apple.** Play has no separate keyword field — the title,
short description and full description _are_ the index. Spending the title on
category words is correct on Play and wasteful on Apple.

### 2.2 Short description (≤ 80 characters)

| #                     | Option                                                                     | Count    |
| --------------------- | -------------------------------------------------------------------------- | -------- |
| **A** _(recommended)_ | `Tasks, notes and files in one place, with alarms that actually wake you.` | **(72)** |
| B                     | `Tasks, notes, files and alarm-grade reminders. Source-available, no ads.` | **(72)** |
| C                     | `source-available task manager: realtime sync, alarms that keep ringing.`  | **(71)** |

This is the line under the icon on the store page and in search results. All
three sit comfortably under the cap; Play counts trailing whitespace, so paste
without a trailing newline.

### 2.3 Full description (≤ 4000 characters)

```text
AllisWell keeps your whole day in one place — tasks, projects, notes and files — with reminders strong enough to actually move you.

source-available. No paid tier, no ads.


📥 CAPTURE, THEN PLAN

• Add a task in seconds, with or without a date. An Inbox holds unplanned thoughts until you are ready for them.
• Home lays the day out chronologically: overdue, today, this week, the next 30 days — next to a month calendar.
• Flip the same day into a Board — kanban columns you name, hide and reorder, with drag-to-move.
• Projects get colors, favorites, archiving, and their own Tasks, Notes and Files tabs.
• Type #tags inline and set priority from none up to urgent.


⏰ REMINDERS THAT DO NOT WHISPER

• Reminders fire at the exact minute you set them, not "around then".
• Urgent tasks ring with a real alarm sound, not a notification chime.
• Ignore one and it comes back — re-alerting on a chain across the next half hour until you acknowledge it.
• Snooze in one tap: 5 minutes, 30 minutes, an hour, or tomorrow morning.
• Privacy mode keeps task content off your lock screen.


📝 NOTES AND FILES

• Markdown notes with live syntax as you type and a real reading view, inline images, linked to tasks and projects, exportable as .md or PDF.
• A full Markdown workspace: tables, checklists, code, maths and diagrams, with reading, rich and source views. Open a .md file from your device, edit it, and save it back to that file.
• Attach files to tasks, notes and projects — up to 10 MB per file on the hosted service.
• A workspace-wide Files section with nestable folders, and a Files tab in every project.


🔄 ONE ACCOUNT, EVERY DEVICE

Sign in once and your tasks, projects and notes follow you: a change you make on your phone lands on your tablet, your desktop and the web in realtime.


📅 GOOGLE CALENDAR, BOTH WAYS

Connect Google Calendar and your tasks become events. Edits you make in Google come back to AllisWell, and your other Google events show up next to your tasks on Home.


🔎 SEARCH THAT IGNORES ACCENTS

Search ignores case and accents across the Latin alphabets, so "muller" finds "Müller" and "cafe" finds "café". It runs on the device, so it answers instantly as you type.


🧩 ALSO IN THE BOX

• Home-screen widgets mirroring your Home buckets
• English and Turkish, following your system language
• Light and dark


🔓 YOURS TO HOST

The whole app and server are public on GitHub, and you can run the entire stack yourself with one docker compose command — your data in your own MySQL, on your own machine, at your own domain. Free for personal use. Use our hosted service or your own server; it is the same app either way.


🚫 NO PAID TIER. NO ADS.

There is no subscription and nothing locked behind one, and there is no advertising, attribution or fingerprinting SDK. We do not sell or rent your data, and we never share it for advertising.

The app does send crash reports and basic usage and performance diagnostics to Firebase, tagged with a random account id, so we can fix what breaks. The content you write — task titles, note bodies, file names — is never attached to any of it, and self-hosted builds send none of it.

You can delete your account and everything in it from Settings, in the app, without asking us.


Source code: https://github.com/mahirozdin/alliswell
Privacy policy: https://alliswell.space/privacy
Support: https://alliswell.space/support
```

**(2980 / 4000)**

### 2.4 Category and tags

| Field                                             | Recommendation                                                                                     |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| **App category**                                  | **Productivity**                                                                                   |
| **Tags** (up to 5, chosen from Play's fixed list) | `Task Management` · `Notes & Lists` · `Calendar` · `Documents & Storage` · `Personal Organization` |

Play's tag list is fixed and closed — pick the nearest available label if any of
the above is not offered in the console. Tags feed the "similar apps" graph, not
keyword search, so choose by _what the app is like_, not by what you want to rank
for. Ranking comes from §2.1–2.3.

**Do not** tag as _Business_ or _Team Collaboration_: there is no multi-user
sharing surface in the app, and the mismatch hurts both conversion and the
recommendation graph.

**Store settings**

- **Contains ads:** No
- **In-app purchases:** No
- **App access:** _All functionality requires a login_ → supply demo credentials
  for review, and note that the sign-in screen has a server-address field for
  self-hosted instances.

### 2.5 Content rating questionnaire (short form)

Category: **Utility, Productivity, Communication, or Other**. Expected outcome:
**Everyone / PEGI 3 / USK 0 / ESRB Everyone.**

| Question                                                                       | Answer                                                                                         |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Violence (any kind)                                                            | No                                                                                             |
| Sexuality / nudity                                                             | No                                                                                             |
| Profanity or crude humour                                                      | No                                                                                             |
| Controlled substances (drugs, alcohol, tobacco)                                | No                                                                                             |
| Gambling — real or simulated                                                   | No                                                                                             |
| Horror / frightening content                                                   | No                                                                                             |
| Does the app share the user's current location?                                | **No**                                                                                         |
| Does the app allow users to interact or exchange content with each other?      | **No** — content is private to the account; there is no messaging, sharing, feed or discovery. |
| Does the app allow users to purchase digital goods?                            | No                                                                                             |
| Does the app contain user-generated content shared publicly?                   | **No**                                                                                         |
| Does the app allow users to communicate with each other?                       | No                                                                                             |
| Is the app a social/dating app?                                                | No                                                                                             |
| Miscellaneous: does the app enable buying/selling, or display third-party ads? | No                                                                                             |

Answering **No** to the user-interaction question is what keeps this out of Play's
social-app requirements (moderation tooling, reporting flows, an in-app block
function). It is accurate here — verify it stays accurate the moment any sharing
feature ships, and refile the questionnaire if it changes.

### 2.6 Data safety

Play's Data safety form is a _declaration_, and it must match the app's real
behaviour and `docs/PRIVACY.md`. Fill it as follows.

**Overview answers**

| Question                                                              | Answer                                                                                                                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Does your app collect or share any of the required user data types?   | **Yes** (collects)                                                                                                                                                        |
| Is all of the user data collected by your app encrypted in transit?   | **Yes** — all API and sync traffic is HTTPS/TLS; the realtime channel is a WebSocket over TLS; file transfers use time-limited presigned HTTPS links to a private bucket. |
| Do you provide a way for users to request that their data be deleted? | **Yes**                                                                                                                                                                   |

**Data collected (none of it shared with third parties)**

| Data type                                                                                          | Collected               | Shared   | Required? | Purpose                                                                                                                                                                                          |
| -------------------------------------------------------------------------------------------------- | ----------------------- | -------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Personal info → Email address**                                                                  | Yes                     | **No**   | Required  | Account creation and sign-in                                                                                                                                                                     |
| **Personal info → Name**                                                                           | Yes                     | **No**   | Optional  | Display name, if the user sets one                                                                                                                                                               |
| **Personal info → User IDs**                                                                       | Yes                     | **No**   | Required  | Account and device identity for sync                                                                                                                                                             |
| **App activity → Other user-generated content** (tasks, projects, notes, tags, folders, reminders) | Yes                     | **No**   | Required  | App functionality; syncing across the user's own devices                                                                                                                                         |
| **Files and docs** (user uploads)                                                                  | Yes                     | **No**   | Optional  | App functionality; only when the user attaches a file                                                                                                                                            |
| **Photos and videos** (inline note media)                                                          | Yes                     | **No**   | Optional  | App functionality; only when the user embeds media in a note                                                                                                                                     |
| **App info and performance → Diagnostics**                                                         | **No**                  | No       | —         | No crash-reporting or performance SDK is present                                                                                                                                                 |
| **Device or other IDs**                                                                            | Yes                     | **No**   | Required  | A per-install device id, so reminders reach the right devices                                                                                                                                    |
| **Calendar**                                                                                       | **Not collected by us** | No       | Optional  | Google Calendar sync sends the task title and description to _the user's own_ Google account, only after they connect it                                                                         |
| **AI features** (task/note text, shared text, a voice _transcript_)                                | **Not collected by us** | See note | Optional  | Sent to the AI provider _the user chooses_ (Anthropic/OpenAI/Google Gemini/OpenRouter, or a local Ollama), only on a user-initiated action. Voice is transcribed on-device — audio is never sent |
| **Location / Contacts / Financial info / Health / Messages / Audio / Browsing history**            | **No**                  | No       | —         | Never collected                                                                                                                                                                                  |

Also declare: **request logs include the IP address** for operating and securing
the service — map this to _App activity → Other actions_ or the console's
security-logging note, matching the "Technical logs" section of `docs/PRIVACY.md`.

**Not shared, and not for ads or tracking**

- **Data shared with third parties: none by default.** The only recipients are
  the infrastructure needed to run the service (server and database hosting,
  Cloudflare R2 for uploads) and — only if the user connects them — Google
  Calendar and the **AI provider the user chooses**, each at the user's explicit
  request and on a per-action basis. Under Play's definitions these are
  _user-initiated transfers_ to a destination the user selected, not _sharing_
  for our purposes. AI is off until the user adds a provider; a local Ollama
  keeps the text on the user's own network.
- **No data is used for advertising, marketing, tracking or analytics.** There is
  no ad network, attribution SDK, analytics SDK or crash reporter in the build.
- **No data is sold.**

**Data deletion**

- **In-app path:** **Settings → Delete account**. Deletion is scheduled with a
  **3-day grace period**; signing in during those 3 days cancels it. After that,
  the account, all its content and its uploaded files are permanently erased.
- **Account-deletion URL — required by Play.** Google requires a _publicly
  reachable web page_, linked from the Data safety form, that explains how to
  delete the account **and** the associated data, and that is reachable **without
  installing or signing into the app**. Use:

  ```text
  https://alliswell.space/delete-account
  ```

  ✅ **Live** at <https://alliswell.space/delete-account>. It states: the in-app path
  (Settings → Delete account), the 3-day grace period and how to cancel, exactly
  what is erased, what is retained and for how long, and an off-app route
  (**info@bubiapps.com**) for users who can no longer sign in. Apple has the
  same requirement for the in-app path — which the app already satisfies — but
  only Google requires the public URL.

---

## 3. Both stores — asset checklist

**Sizes are portrait unless noted.** All screenshots must be PNG or JPEG, RGB,
no alpha channel and no rounded corners baked in.

| #   | Store     | Asset                                      | Exact size                                                  | Count        | Status                                                                                                                                                                                                                                   |
| --- | --------- | ------------------------------------------ | ----------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | App Store | **iPhone 6.9"** screenshots                | 1320 × 2868 _(1290 × 2796 also accepted)_                   | 3–10 (min 3) | ✅ `store/ios/iphone-6.9/01–08.png`                                                                                                                                                                                                      |
| 2   | App Store | **iPhone 6.5"** screenshots                | 1242 × 2688 _(or 1284 × 2778)_                              | 3–10         | ✅ `store/ios/iphone-6.5/01–08.png`                                                                                                                                                                                                      |
| 3   | App Store | **iPad 13"** screenshots                   | 2064 × 2752 _(portrait)_                                    | 1–10         | ✅ `store/ios/ipad-13/01–06.png` — **required**, because the build declares iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). Rendered from the real widget tree at 1032 × 1376 @2×, not upscaled — see [SCREENSHOTS.md](SCREENSHOTS.md) §4.      |
| 4   | App Store | **App icon**                               | 1024 × 1024, no alpha, no rounded corners                   | 1            | ✅ `store/icons/app-store-1024.png`                                                                                                                                                                                                      |
| 5   | App Store | **App preview video** (optional)           | per-device, 15–30 s                                         | 0–3          | ⏭ Skipped for 0.9.0                                                                                                                                                                                                                      |
| 6   | Play      | **Phone** screenshots                      | ≥ 1080 px short edge, 9:16                                  | 2–8 (min 2)  | ✅ `store/android/phone/01–08.png` (1344 × 2992)                                                                                                                                                                                         |
| 7   | Play      | **7" tablet** screenshots                  | 1200 × 1920 recommended                                     | up to 8      | ⛔ **To do** — only if the listing targets tablets                                                                                                                                                                                       |
| 8   | Play      | **10" tablet** screenshots                 | 1920 × 1200 or 1200 × 1920                                  | up to 8      | ⛔ **To do** — same condition as #7                                                                                                                                                                                                      |
| 9   | Play      | **Feature graphic**                        | exactly 1024 × 500, no alpha                                | 1            | ✅ `store/android/feature-graphic.png`                                                                                                                                                                                                   |
| 10  | Play      | **App icon**                               | exactly 512 × 512, 32-bit PNG **with** alpha                | 1            | ✅ `store/icons/play-512.png`                                                                                                                                                                                                            |
| 11  | Play      | **Promo video** (optional)                 | YouTube URL                                                 | 0–1          | ⏭ Skipped for 0.9.0                                                                                                                                                                                                                      |
| 12  | Both      | Localized screenshot sets (**en**, **tr**) | as above, per locale                                        | ×2           | ⛔ **English only.** A Turkish set converts better on a localised page — re-run the pipeline with the simulator/emulator in `tr` and the seeder's content translated.                                                                    |
| 13  | Site      | Social cover (Open Graph)                  | 1200 × 630                                                  | 1            | ✅ `apps/landing/public/og-cover.png`                                                                                                                                                                                                    |
| 14  | App Store | **macOS** screenshots                      | 2880 × 1800 _(1280×800, 1440×900, 2560×1600 also accepted)_ | 3–10         | ✅ `store/macos/01–06.png` — composed from the desktop web captures, which are the same Flutter layout the macOS binary renders, in a drawn Mac window. Recapture from a real `flutter build macos` if the desktop layouts ever diverge. |

### How they are generated

```bash
# 1. a running API with the demo workspace
npm run dev &&  node scripts/seed-demo.mjs

# 2. real device captures (see docs/SCREENSHOTS.md for the per-platform steps)
npm run shots:web                       # → screenshots/web/
#   iOS simulator + Android emulator     → screenshots/ios/, screenshots/android/

# 2b. iPad 13" — rendered at exact size, no device needed (SCREENSHOTS.md §4)
cd apps/app && flutter test --update-goldens --dart-define=screenshots=true \
  test/store_screenshots_test.dart      # → screenshots/ipad/ after the copy step

# 3. compose them into store canvases, plus icons and the feature graphic
npm run shots:store                     # → store/
```

`scripts/screenshots/store.mjs` composites in **headless Chrome**: the caption
band is CSS, so it can be re-rendered per language without touching a pixel
editor, and every output is written at its exact store size rather than being
upscaled from a golden. The captions live in the `SLIDES` array at the top of
that file; Android slides can override them (`androidTitle`/`androidSub`) where
the Android capture shows a different screen from its iOS counterpart.

**Why device captures, and where goldens are used instead.** Prefer the device:
`xcrun simctl io … screenshot` on an iPhone 17 Pro Max is already 1320 × 2868,
which _is_ a valid 6.9" submission, so the phone pipeline starts there. The
design harness (`apps/app/test/design_screenshots_test.dart`) renders at
780 × 1688 / 2560 × 1600 — **no store size** — and upscaling to 1320 × 2868 looks
soft in a way reviewers notice.

The **iPad 13" set is the exception**, and it is not an upscale.
`apps/app/test/store_screenshots_test.dart` pins the surface to 1032 × 1376
logical at `devicePixelRatio: 2`, which is exactly 2064 × 2752 native — the
required size, rendered 1:1 from the same widget tree, router and theme an iPad
runs. No iPad hardware or simulator capture exists here; a phone screenshot
stretched onto an iPad canvas would be both softer and, under guideline 2.3.3,
a misrepresentation of the iPad experience.

Screen order (the first two carry almost all the conversion): **Home** →
**Board** → **the alarm / a repeating task** → **Projects** → **Notes** →
**Files** → **dark mode**.

---

## 4. Turkish versions

A localised listing, written as Turkish marketing copy rather than a
translation of §1–§2 — the emphasis and the idioms differ deliberately. Ship it
because a localised store page converts better in that market, not because the
product is Turkish: nothing in §1–§2 presents the language as a feature, and this
section should not either.

### 4.1 Apple App Store — Türkçe

**Uygulama adı (≤ 30 karakter)**

| #                  | Seçenek                         | Karakter |
| ------------------ | ------------------------------- | -------- |
| **A** _(önerilen)_ | `AllisWell`                     | **(9)**  |
| B                  | `AllisWell: Görev, Hatırlatıcı` | **(29)** |
| C                  | `AllisWell - Görev ve Alarm`    | **(26)** |

**Alt başlık (≤ 30 karakter)**

| #                  | Seçenek                      | Karakter |
| ------------------ | ---------------------------- | -------- |
| **A** _(önerilen)_ | `Görev, not ve gerçek alarm` | **(26)** |
| B                  | `Görev, not, dosya ve alarm` | **(26)** |
| C                  | `Görev, not, dosya ve alarm` | **(26)** |

**Tanıtım metni (≤ 170 karakter)**

```text
Tam dakikasında, gerçek alarm sesiyle çalan hatırlatıcılar. Şubat'ı atlamayan tekrarlar. Çift yönlü takvim eşitlemesi. Ücretsiz, reklamsız.
```

**(142)** — 1.1.0 için güncel.

**(130)**

**Anahtar kelimeler (≤ 100 karakter, virgülle ayrılmış, boşluksuz)**

```text
yapılacaklar,görev,hatırlatıcı,ajanda,planlayıcı,kanban,pano,proje,liste,not,dosya,açıkkaynak
```

**(94 / 100)** — A adı + A alt başlığı ile eşleşir; oradaki kelimeler tekrar edilmedi.

**Açıklama (≤ 4000 karakter)**

```text
AllisWell gününüzü tek yerde toplar: görevler, projeler, notlar ve dosyalar — üstüne sizi toplantıdan zamanında çıkaracak kadar ısrarcı hatırlatıcılar.

Kaynağı açık. Ücretli sürüm yok, reklam yok.


GÜNÜNÜZ TEK EKRANDA

• Görevi saniyeler içinde yazın; tarih vermek zorunda değilsiniz. Planlamadıklarınız, siz hazır olana kadar Gelen Kutusu'nda bekler.
• Ana ekran günü sırayla önünüze koyar: gecikenler, bugün, bu hafta, önümüzdeki 30 gün — yanında aylık takvim.
• Aynı günü Pano'ya çevirin: adını kendiniz koyduğunuz, gizleyip sıralayabildiğiniz Kanban sütunları ve sürükle-bırak.
• Projelerin rengi, favorisi, arşivi ve kendi Görevler / Notlar / Dosyalar sekmeleri var.
• Satır içinde #etiket yazın, önceliği "yok"tan "acil"e kadar ayarlayın.


FISILDAMAYAN HATIRLATICILAR

• Hatırlatıcı "civarında" değil, kurduğunuz dakikada gelir.
• Acil görevler bildirim sesiyle değil, gerçek bir alarm sesiyle çalar.
• Kapatmazsanız peşinizi bırakmaz: yarım saat boyunca zincirleme yeniden çalar.
• Tek dokunuşla erteleyin: 5 dakika, 30 dakika, 1 saat ya da yarın sabah.
• Gizlilik modu, görev içeriğini kilit ekranında göstermez.


NOTLAR VE DOSYALAR

• Markdown notları: yazarken canlı sözdizimi, gerçek bir okuma görünümü, satır içi görsel, göreve ve projeye bağlama, .md veya PDF olarak dışa aktarma.
• Tam bir Markdown çalışma tezgâhı: tablolar, kontrol listeleri, kod, matematik ve diyagramlar; okuma, zengin ve kaynak görünümleriyle. Cihazındaki bir .md dosyasını aç, düzenle ve o dosyaya geri kaydet.
• Göreve, nota ve projeye dosya ekleyin — barındırılan serviste dosya başına 10 MB'a kadar.
• Tüm çalışma alanını kapsayan, iç içe klasörlü bir Dosyalar bölümü; ayrıca her projenin kendi Dosyalar sekmesi.


TEK HESAP, TÜM CİHAZLAR

Bir kez giriş yapın; görevleriniz, projeleriniz ve notlarınız sizinle gelsin. iPhone'unuzda yaptığınız bir değişiklik iPad'inize, Mac'inize ve web'e anında düşer.


TAKVİMLER

• Google Takvim çift yönlü eşitlenir: görevleriniz etkinliğe dönüşür, Google'da yaptığınız düzenlemeler AllisWell'e geri gelir. Diğer Google etkinlikleriniz de Ana ekranda görevlerinizin yanında görünür.
• Apple Takvim bu sürümde tek yönlüdür: seçtiğiniz görevler, seçtiğiniz takvime yazılır.


AKSANA TAKILMAYAN ARAMA

Arama büyük-küçük harfe ve aksanlara takılmaz: "cay" yazınca "Çay", "isi" yazınca "ısı", "muller" yazınca "Müller" gelir. Cihazınızda çalıştığı için siz yazarken anında yanıt verir.


AYRICA

• Ana ekran widget'ları, Ana ekrandaki gruplarınızı yansıtır (iPhone, iOS 16 ve üzeri).
• Türkçe ve İngilizce; sistem dilinizi kendisi seçer.
• Açık ve koyu tema.


AÇIK KAYNAK VE İSTERSENİZ KENDİ SUNUCUNUZDA

Uygulamanın ve sunucunun tamamı GitHub'da açık; tek bir docker compose komutuyla hepsini kendiniz çalıştırabilirsiniz — veriniz kendi MySQL'inizde, kendi makinenizde, kendi alan adınızda. Kişisel kullanım için ücretsiz. Bizim servisimizi de kendi sunucunuzu da kullanabilirsiniz; uygulama aynı uygulama.


ÜCRETLİ SÜRÜM YOK. REKLAM YOK.

Abonelik yok, kilitli özellik yok; uygulamada reklam, ilişkilendirme veya parmak izi kütüphanesi yok. Verinizi satmıyor, kiralamıyor ve reklam için kimseyle paylaşmıyoruz.

Uygulama, bozulanı düzeltebilmemiz için çökme raporlarını ve temel kullanım/performans ölçümlerini Firebase'e gönderir; bunlar rastgele bir hesap kimliğiyle etiketlenir. Yazdığınız içerik — görev başlıkları, not gövdeleri, dosya adları — hiçbirine eklenmez ve kendi sunucunuzda çalıştırdığınız sürümler bunların hiçbirini göndermez.

Hesabınızı ve içindeki her şeyi, bize sormadan, Ayarlar'dan silebilirsiniz.


Gizlilik politikası: https://alliswell.space/privacy
Kaynak kodu: https://github.com/mahirozdin/alliswell
```

**(3155 / 4000)**

**Yenilikler (0.4.0)**

```text
Bu sürüm büyük olanı — ilk sürümden bu yana ne yaptıysak burada.

PANO GÖRÜNÜMÜ
Ana ekran artık kronolojik liste ile Kanban Pano arasında geçiş yapıyor. Sütunların adını siz koyuyor, istemediğinizi gizliyor, sırasını değiştiriyor ve görevleri sürükleyerek taşıyorsunuz.

GERÇEK BİR DOSYALAR BÖLÜMÜ
Göreve, nota ve projeye dosya ekleyin; hepsini tek bir yerde, iç içe klasörlü Dosyalar bölümünde bulun. Her projenin de kendi Dosyalar sekmesi var.

CİDDİ ALARMLAR
Acil görevler artık tam zamanında, gerçek bir alarm sesiyle çalıyor ve siz kapatana kadar yarım saat boyunca tekrar tekrar hatırlatıyor. Tek dokunuşla erteleyin; gizlilik modunu açarsanız görev içeriği kilit ekranında görünmez.

AKSANA TAKILMAYAN ARAMA
Arama artık her yerde büyük-küçük harfe ve aksanlara takılmıyor — "cay" yazınca "Çay", "isi" yazınca "ısı" geliyor. Üstelik cihazda çalışıyor: anında.

BAĞLANAN TAKVİM
Google Takvim'i bağladığınızda ana takviminiz otomatik seçiliyor ve eşitleme hemen başlıyor. O gizli ikinci adım tarihe karıştı.

AYRICA
• Ana ekrandaki gruplarınızı yansıtan widget'lar
• Açık ve koyu temada kontrastı denetlenmiş yeni bir görünüm
• Baştan sona Türkçe
• Tek komutla kendi sunucunuzda çalıştırın — deposuna bakın

Bir aksaklık mı gördünüz? https://github.com/mahirozdin/alliswell/issues
```

**(1303 / 4000)**

### 4.2 Google Play — Türkçe

**Uygulama başlığı (≤ 30 karakter)**

| #                  | Seçenek                        | Karakter |
| ------------------ | ------------------------------ | -------- |
| **A** _(önerilen)_ | `AllisWell: Görev ve Alarm`    | **(25)** |
| B                  | `AllisWell: Görev, Not, Alarm` | **(28)** |
| C                  | `AllisWell`                    | **(9)**  |

**Kısa açıklama (≤ 80 karakter)**

| #                  | Seçenek                                                                      | Karakter |
| ------------------ | ---------------------------------------------------------------------------- | -------- |
| **A** _(önerilen)_ | `Görev, not ve dosya; uyandıran alarmlar. Kaynağı açık, reklamsız.`          | **(65)** |
| B                  | `Görevler, notlar, dosyalar ve uyandıran alarmlar. Reklamsız, kaynağı açık.` | **(74)** |
| C                  | `Kaynağı açık görev yöneticisi. Gerçek alarmlar, anlık eşitleme.`            | **(63)** |

**Tam açıklama (≤ 4000 karakter)**

```text
AllisWell gününüzü tek yerde toplar — görevler, projeler, notlar ve dosyalar — üstüne sizi gerçekten harekete geçirecek hatırlatıcılar.

Kaynağı açık. Ücretli sürüm yok, reklam yok.


📥 ÖNCE YAKALAYIN, SONRA PLANLAYIN

• Görevi saniyeler içinde yazın; tarih vermek zorunda değilsiniz. Planlamadıklarınız Gelen Kutusu'nda bekler.
• Ana ekran günü sırayla önünüze koyar: gecikenler, bugün, bu hafta, önümüzdeki 30 gün — yanında aylık takvim.
• Aynı günü Pano'ya çevirin: adını kendiniz koyduğunuz, gizleyip sıralayabildiğiniz Kanban sütunları ve sürükle-bırak.
• Projelerin rengi, favorisi, arşivi ve kendi Görevler / Notlar / Dosyalar sekmeleri var.
• Satır içinde #etiket yazın, önceliği "yok"tan "acil"e kadar ayarlayın.


⏰ FISILDAMAYAN HATIRLATICILAR

• Hatırlatıcı "civarında" değil, kurduğunuz dakikada gelir.
• Acil görevler bildirim sesiyle değil, gerçek bir alarm sesiyle çalar.
• Kapatmazsanız peşinizi bırakmaz: yarım saat boyunca zincirleme yeniden çalar.
• Tek dokunuşla erteleyin: 5 dakika, 30 dakika, 1 saat ya da yarın sabah.
• Gizlilik modu, görev içeriğini kilit ekranında göstermez.


📝 NOTLAR VE DOSYALAR

• Markdown notları: yazarken canlı sözdizimi, gerçek bir okuma görünümü, satır içi görsel, göreve ve projeye bağlama, .md veya PDF olarak dışa aktarma.
• Tam bir Markdown çalışma tezgâhı: tablolar, kontrol listeleri, kod, matematik ve diyagramlar; okuma, zengin ve kaynak görünümleriyle. Cihazındaki bir .md dosyasını aç, düzenle ve o dosyaya geri kaydet.
• Göreve, nota ve projeye dosya ekleyin — barındırılan serviste dosya başına 10 MB'a kadar.
• İç içe klasörlü, çalışma alanının tamamını kapsayan bir Dosyalar bölümü; her projede ayrı bir Dosyalar sekmesi.


🔄 TEK HESAP, TÜM CİHAZLAR

Bir kez giriş yapın; görevleriniz, projeleriniz ve notlarınız sizinle gelsin. Telefonunuzda yaptığınız bir değişiklik tabletinize, masaüstünüze ve web'e anında düşer.


📅 GOOGLE TAKVİM, ÇİFT YÖNLÜ

Google Takvim'i bağlayın; görevleriniz etkinliğe dönüşsün. Google'da yaptığınız düzenlemeler AllisWell'e geri gelir, diğer Google etkinlikleriniz de Ana ekranda görevlerinizin yanında görünür.


🔎 AKSANA TAKILMAYAN ARAMA

Arama büyük-küçük harfe ve aksanlara takılmaz: "cay" yazınca "Çay", "isi" yazınca "ısı" gelir. Cihazınızda çalışır — siz yazarken anında.


🧩 AYRICA

• Ana ekrandaki gruplarınızı yansıtan widget'lar
• Türkçe ve İngilizce; sistem dilinizi kendisi seçer
• Açık ve koyu tema


🔓 AÇIK KAYNAK VE İSTERSENİZ KENDİ SUNUCUNUZDA

Uygulamanın ve sunucunun tamamı GitHub'da açık; tek bir docker compose komutuyla hepsini kendiniz çalıştırabilirsiniz — veriniz kendi MySQL'inizde, kendi makinenizde, kendi alan adınızda. Kişisel kullanım için ücretsiz. Bizim servisimizi de kendi sunucunuzu da kullanabilirsiniz; uygulama aynı uygulama.


🚫 ÜCRETLİ SÜRÜM YOK. REKLAM YOK.

Abonelik yok, kilitli özellik yok; uygulamada reklam, ilişkilendirme veya parmak izi kütüphanesi yok. Verinizi satmıyor, kiralamıyor ve reklam için kimseyle paylaşmıyoruz.

Uygulama, bozulanı düzeltebilmemiz için çökme raporlarını ve temel kullanım/performans ölçümlerini Firebase'e gönderir; bunlar rastgele bir hesap kimliğiyle etiketlenir. Yazdığınız içerik — görev başlıkları, not gövdeleri, dosya adları — hiçbirine eklenmez ve kendi sunucunuzda çalıştırdığınız sürümler bunların hiçbirini göndermez.

Hesabınızı ve içindeki her şeyi, bize sormadan, Ayarlar'dan silebilirsiniz.


Kaynak kodu: https://github.com/mahirozdin/alliswell
Gizlilik politikası: https://alliswell.space/privacy
Destek: https://alliswell.space/support
```

**(3089 / 4000)**

**Yenilikler (0.4.0)** — Play'in "Yenilikler" alanı **≤ 500 karakter**; App
Store'un 4000 karakterlik metnini buraya olduğu gibi yapıştırmayın.

```text
Kanban Pano: Ana ekranı liste ile pano arasında çevirin, sütunları kendiniz kurun.
Dosyalar: göreve, nota ve projeye dosya ekleyin; hepsini iç içe klasörlerde bulun.
Ciddi alarmlar: acil görevler tam zamanında, gerçek alarm sesiyle çalar ve siz kapatana kadar tekrarlar.
Aksana takılmayan arama: "cay" yazınca "Çay" gelir; cihazda çalışır, anında bulur.
Google Takvim tek adımda bağlanır.
Ayrıca: widget'lar, yenilenen görünüm, tek komutla kendi sunucunuz.
```

**(452 / 500)**

### English "What's new" — 1.1.0, the first Play release (≤ 500 characters)

Play's release-notes field is **≤ 500 characters** per language; never paste the
App Store's 4000-character text here.

**This is the first build ever uploaded to Play** — the release keystore was the
blocker until 2026-08-02, so nothing before versionCode 16 exists on the store.
Release notes that recite an internal 0.4.0 → 1.1.0 changelog would be describing
changes no Play user has ever seen. Introduce the app instead.

```text
Your whole day in one place: tasks, projects, notes and files, with reminders strong enough to actually move you.

• Home lays the day out chronologically — or flips into a kanban board
• Urgent tasks ring with a real alarm sound and keep re-alerting until you acknowledge
• Repeats that clamp: ask for the 31st, February answers with the 28th
• Two-way Google Calendar sync
• Syncs to your tablet, desktop and the web in realtime

Sign in with Google, Apple or e-mail. No ads, no subscriptions.
```

**(486 / 500)**

**Note the closing line.** It says _no ads, no subscriptions_ — **not** "no
tracking" and **not** "no analytics". Since 1.1.0 the build carries Firebase
Analytics, Crashlytics and Performance (ADR-0025), so that older claim is false
and would contradict the Data safety form filed beside it. Both descriptions
were corrected on 2026-08-02; see §5 for why neither sentence comes back.

<details>
<summary>Update-style alternate — use it for the first release <em>after</em> this one</summary>

```text
NEW — Sign in with Google or Sign in with Apple. One tap, and the account is still yours in AllisWell, not rented from a provider.

FIXED — A custom snooze in the half hour before midnight silently did nothing. It now snoozes, and says exactly when it will ring again.

ALSO — Search ignores accents everywhere: "muller" finds "Müller", "cafe" finds "café". It runs on your device, so it is instant.
```

**(402 / 500)**

</details>

<details>
<summary>Previous — English "What's New" for Play, 0.4.0 (never published)</summary>

```text
Kanban Board: flip Home between list and board, with columns you define.
Files: attach files to tasks, notes and projects, and find them all in nestable folders.
Serious alarms: urgent tasks ring at the exact minute with a real alarm sound, and keep re-alerting until you acknowledge.
Accent-insensitive search: "muller" finds "Müller" — on-device, so it is instant.
Google Calendar now connects in one step.
Plus: home-screen widgets, a refreshed look, and one-command self-hosting.
```

**(475 / 500)**

</details>

---

## 5. Claim guardrails

> Re-audited 2026-08-12 (OPH-252). Two claims that were **live in the copy and
> forbidden here** were removed at the source rather than re-flagged: the
> widget "tick one off without opening the app" line (README + landing) and
> "Home-screen widgets ● iOS/Android/**macOS**" (COMPARISON). The round-13
> lesson — a guardrail can go stale in the *permissive* direction — has its
> mirror: one can go stale in the *violated* direction too, when copy drifts
> after the rule was written.

Things a reasonable copywriter would have written that are **not true of the
shipped build**. Do not add them back without re-checking the code.

| Claim                                                     | Why it is not in the copy                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **"Rings through the mute switch" / "AlarmKit"**          | The iOS 26 AlarmKit lane's Dart side is complete and tested, but the native bridge is **not in the build**: `AlarmKitBridge.swift` appears **zero** times in `apps/app/ios/Runner.xcodeproj/project.pbxproj`, and `apps/app/ios/Runner/AppDelegate.swift` explicitly leaves it unregistered ("Kept out of the committed build"). `apps/app/ios/Runner/ALARMKIT_SETUP.md` documents the remaining device-only step. Until that ships, urgent alarms are time-sensitive notifications with a bundled sound — **which a hardware mute switch can still silence.** The 0.4.0 CHANGELOG says as much under _Known limitations_.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **"Alarms that never stop until you dismiss them"**       | The re-alert chain is a **finite, pre-scheduled** set of 5 alerts at 0 / 2 / 5 / 10 / 30 minutes (`kUrgentChainOffsets`, `apps/app/lib/src/notifications/planner.dart`). "Keeps re-alerting across the next half hour" is accurate; "never stops" is not.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **"Two-way Apple Calendar sync"**                         | Apple/EventKit is **one-way only** (task → event). The native plugin exposes no list-events method, and `apps/app/lib/src/features/calendar/apple/apple_mirror_engine.dart` states the one-way limit in its own doc comment. Only Google is two-way. Note that `README.md` currently overstates this — the store copy deliberately does not follow it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **"Tap to complete from the widget"**                     | No `AppIntent` exists in any Swift file; the iOS widget is a `StaticConfiguration` whose only interaction is `.widgetURL`, and the Android provider only opens `MainActivity`. Widgets are read-only glances.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **"Widgets on iPhone, Android and Mac"**                  | There is **no macOS widget target**, so the copy claims iPhone and Android only. The iOS widget extension's deployment target was 26.2 (invisible to almost every device) and is now **16.0** — fixed 2026-07-26, so the iPhone claim needs no qualifier.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **"Subtasks" / "natural-language dates" as built-ins**    | The app ships **no subtask UI** and **no built-in NLP date parser** in quick-add. (AI extraction can resolve "tomorrow 3pm" into a date, but only with a provider connected and always behind the confirm card — never sell it as an always-on built-in.) **Note:** "recurring tasks" **now ship** as of v0.8.0 (Epic 19) — that claim is no longer off-limits and appears in the copy.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **"Built-in / free AI" / "ChatGPT or Claude included"**   | AI is **bring-your-own-key** (Anthropic/OpenAI/Gemini/OpenRouter/Ollama) or **connect-your-own-subscription** (the MCP connector links the user's _own_ Claude or ChatGPT). The app ships no bundled or free model. Never imply AllisWell provides the AI, that it is free, or that a consumer Claude/ChatGPT account is integrated for the user. Gemini is always described as needing an **API key**, not the free consumer app.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| **"Share a project with your team" / collaboration**      | No sharing, invitation, comment or messaging surface ships. This also underpins the "No" answers in §1.8 and §2.5 — if collaboration ever ships, both questionnaires must be refiled.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **"Unlimited file uploads" / "up to 5 GB"**               | The code default for `STORAGE_MAX_UPLOAD_MB` is 512, but every shipped environment sets **10** (`.env.production`, `docker-compose.selfhost.yml`, `.env.selfhost.example`), and `docs/PRIVACY.md` states 10 MB for the hosted service. The copy says **10 MB on the hosted service** and notes self-hosters can change it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **"Instant account deletion"**                            | Deletion has a **3-day grace period** and is cancellable by signing in. The copy says you can delete from Settings without saying it is immediate; §2.6 states the grace period explicitly, as Play requires.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Any offline claim, in any wording**                     | **Google Play rejected version code 16 for this sentence on 2026-08-02** — Misleading Claims, "app description lists features not present in the app". Tasks, projects and notes are genuinely local-first (drift replica + outbox), and search runs on the device. But **signing in the first time needs the network**, and so does **every file**: content is fetched through a presigned URL (`fileUrlProvider` → `GET /files/:id/url`), so an attachment or note image cannot be opened offline, let alone uploaded. Calendar sync and the AI surfaces need it too. The first fix was to caveat it ("a connection is needed to sign in the first time…"). The owner overruled that on 2026-08-03 and removed the claim outright, on the grounds that a reviewer meets the sign-in wall before any offline behaviour exists to test — so the caveat argues with the reviewer's own experience instead of matching it. **No store copy may say offline, offline-first, "works with no connection" or çevrimdışı** — not in the description, subtitle, short description, keywords, promo text or release notes. The capability is real for a signed-in user and stays in README, ARCHITECTURE and the landing site, where nothing is being sold. It may only return to the store if first-run stops needing the network. |
| **"No tracking" / "no analytics" / "no crash reporting"** | True until 1.1.0, false the moment Firebase Analytics, Crashlytics and Performance landed (ADR-0025). It is also self-refuting on Play, where the Data safety form declaring exactly that data sits on the same page as the description. What is still true, and what the copy now says: no advertising, attribution or fingerprinting SDK; nothing sold or rented; the content you write is never attached; self-hosted builds send none of it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| **Any rating, download count, award or "#1" claim**       | The app has not shipped. No social proof of any kind appears in this file.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

### Pre-submission blockers (not copy — build and infrastructure)

Re-verified 2026-07-31 against the live site and the working tree — this list is
the current state, not the original one.

**New since Firebase landed (Epic 21) — both stores ask, and both answers changed:**

- [ ] **Play ▸ Data safety** must now declare Firebase: crash logs, diagnostics
      and app interactions, collected and shared with Google, tied to a user id,
      not used for advertising. §2.6's answers were written before Crashlytics
      and Analytics existed and are now incomplete.
- [ ] **Apple ▸ App privacy** needs the matching nutrition labels: _Diagnostics_
      and _Usage Data_, "Linked to You" via the account id, "Not used for
      tracking".
- [ ] **Sign in with Apple** must be enabled as a capability on the App ID, and
      `SIGN_IN_*` set on the production API — otherwise the buttons ship and the
      server answers 503. See docs/FIREBASE.md and ADR-0026.
- [ ] **Account deletion via a provider account** — Apple requires deletion to be
      reachable for accounts created with Sign in with Apple, which this now
      creates. The in-app path already covers it; confirm it on a
      provider-only account before submitting.

**Still open — these stop a submission:**

- [ ] **The release keystore is missing.** `apps/app/android/key.properties`
      points at `key0.jks`, and that file is not in the tree (correctly — it is
      gitignored). Without it the release build silently falls back to the debug
      key and **Play rejects the upload**. Restore the keystore from wherever it
      is kept, or generate one and keep it somewhere you cannot lose it: losing
      the upload key means never updating the listing again.
- [ ] **No demo account on the hosted service.** `demo@alliswell.space` answers
      401 on `api.alliswell.space`. Apple **rejects** any app behind a sign-in
      without working review credentials. Create it and seed it:
      `node scripts/seed-demo.mjs --api https://api.alliswell.space`.
- [x] **iPad screenshots** (asset checklist #3) — shipped 2026-08-02 as
      `store/ios/ipad-13/01–06.png`, 2064 × 2752, RGB, no alpha.

**Resolved:**

- [x] **Display name** is `AllisWell` on both platforms (`CFBundleDisplayName`,
      `android:label`).
- [x] **`ITSAppUsesNonExemptEncryption = false`** is set in `Info.plist`, so
      uploads skip the export-compliance prompt.
- [x] **The three web pages are live:** `/privacy`, `/support`,
      `/delete-account` — all 200, all readable without JavaScript.
- [x] **The contact mailbox exists.** The policies name `info@bubiapps.com`, a
      real address, instead of the `privacy@alliswell.space` box that was never
      created.
