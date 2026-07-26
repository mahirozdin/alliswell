# Store listing — AllisWell

Ready-to-paste copy for the **Apple App Store** and **Google Play**, for the
**0.4.0** launch. Every character-limited field shows its real count.

Everything here was written against the shipped code (`README.md`,
`docs/SELF-HOSTING.md`, `docs/PRIVACY.md`, the 0.4.0 CHANGELOG entry) — see
[§5 Claim guardrails](#5-claim-guardrails) for the lines that were deliberately
_not_ written, and why. **Read §5 before editing any of this copy.**

---

## 1. Apple App Store

### 1.1 App name (≤ 30 characters)

| #                     | Option                         | Count    |
| --------------------- | ------------------------------ | -------- |
| **A** _(recommended)_ | `AllisWell`                    | **(9)**  |
| B                     | `AllisWell: Tasks & Reminders` | **(28)** |
| C                     | `AllisWell - Tasks & Alarms`   | **(26)** |

**Why A.** The name field and the subtitle are indexed separately, and both are
indexed _in addition to_ the keywords field. Keeping the name to the bare brand
frees "tasks", "reminders" and "alarms" to be spent in the subtitle — where they
still rank — and keeps the home-screen label clean. Pick B only if you want the
category words visible in search results rather than just indexed.

### 1.2 Subtitle (≤ 30 characters)

| #                                        | Option                          | Count    |
| ---------------------------------------- | ------------------------------- | -------- |
| **A** _(recommended, pairs with name A)_ | `Tasks, notes and real alarms`  | **(28)** |
| B                                        | `Offline tasks, notes & alarms` | **(29)** |
| C                                        | `Open-source task manager`      | **(24)** |

**Recommended pairing: name A + subtitle A.** The keywords in §1.5 are built
around exactly that pairing.

### 1.3 Promotional text (≤ 170 characters)

Editable without a new build — use it for launch beats and swap it later.

```text
0.4.0 is here: a kanban Board, a Files section with folders, Turkish-aware search, and urgent alarms that re-alert until you actually acknowledge them.
```

**(151)**

<details>
<summary>Alternate promo lines</summary>

```text
Open source, offline-first, and free. Tasks, notes and files in one place, with reminders loud enough to actually move you. No ads, no tracking, no paid tier.
```

**(158)**

</details>

### 1.4 Description (≤ 4000 characters)

```text
AllisWell keeps your whole day in one place: tasks, projects, notes and files, with reminders strong enough to actually get you out of a meeting on time.

It is open source, it works offline, and there is no paid tier, no ads and no tracking.


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

• Rich-text notes with inline images and video, linked to your tasks and projects, exportable as Markdown.
• Attach files to tasks, notes and projects — up to 10 MB per file on the hosted service.
• A workspace-wide Files section with nestable folders, plus a Files tab inside every project.


OFFLINE FIRST, ALWAYS IN SYNC

Everything works with no connection: create, edit, complete, search. Your changes are queued on the device and pushed when you are back, and they land on your other devices in realtime.


CALENDARS

• Google Calendar syncs both ways — your tasks become events, and edits you make in Google come back to AllisWell. Your other Google events show up next to your tasks on Home.
• Apple Calendar is one-way in this version: the tasks you choose are written into the calendar you pick.


SEARCH THAT SPEAKS TURKISH

Search ignores case and Turkish accents, so "cay" finds "Çay" and "isi" finds "ısı". It runs over the copy of your data on the device, so it answers instantly and works offline.


ALSO IN THE BOX

• Home-screen widgets mirroring your Home buckets (iPhone, iOS 16 and later).
• English and Turkish, following your system language.
• Light and dark.


OPEN SOURCE, AND YOURS TO HOST

AllisWell is AGPL-3.0. The entire app and server are public on GitHub, and you can run the whole thing yourself with a single docker compose command — your data in your own MySQL, on your own machine, reachable at your own domain. Use our hosted service or your own server; it is the same app either way.


NO PAID TIER. NO ADS. NO TRACKING.

There is no subscription and nothing locked behind one. There is no advertising, analytics or crash-reporting SDK in the app — none. We do not sell or share your data with anyone. You can delete your account and everything in it from Settings, in the app, without asking us.


Privacy policy: https://alliswell.space/privacy
Source code: https://github.com/mahirozdin/alliswell
```

**(3151 / 4000)**

### 1.5 Keywords (≤ 100 characters total, comma-separated, no spaces after commas)

Built for **name A + subtitle A**. Apple indexes the app name and subtitle
separately, so nothing from `AllisWell` / `Tasks, notes and real alarms` is
repeated here — every character buys a _new_ term.

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,offline,sync,selfhosted
```

**(97 / 100)** — 13 terms, no spaces, no duplicates of the name or subtitle.

Notes:

- Apple auto-combines terms, so "task manager" is already covered by `manager`-free
  combinations of the subtitle's _tasks_ with `planner` / `organizer`. Do not
  waste characters on multi-word phrases.
- Do **not** add competitor names (Todoist, Things, TickTick, Notion). Apple
  rejects trademarked terms in the keyword field.
- If you switch to name B, delete `reminder` from this list and spend the freed
  ~9 characters on `notes,files` — but see the count first.

<details>
<summary>Alternate keyword sets</summary>

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,offline,sync,opensource
```

**(97)** — trades `selfhosted` for `opensource`.

```text
todo,reminder,planner,kanban,board,project,checklist,gtd,agenda,organizer,offline,sync,habit,list
```

**(97)** — drops the self-hosting angle for two broader consumer terms.

</details>

### 1.6 URLs

| Field                               | URL                               | Status               |
| ----------------------------------- | --------------------------------- | -------------------- |
| **Support URL** _(required)_        | `https://alliswell.space/support` | **Must be created.** |
| **Marketing URL** _(optional)_      | `https://alliswell.space`         | **Must be created.** |
| **Privacy Policy URL** _(required)_ | `https://alliswell.space/privacy` | **Must be created.** |

**None of these pages exist yet** — the repo has no landing site, and
`alliswell.space` currently appears only inside `docs/PRIVACY.md` and
`docs/PRIVACY.tr.md`. Before submission:

1. **`/privacy`** — publish `docs/PRIVACY.md` as a real HTML page, with the
   Turkish version (`docs/PRIVACY.tr.md`) at `/privacy/tr` or behind a language
   switch. Apple and Google both fetch this URL and both reject a 404 or a raw
   GitHub link that redirects.
2. **`/support`** — needs a working contact route. A page with the support
   mailbox, a link to GitHub Issues, and a short FAQ is enough. Apple checks that
   it loads and that it actually offers a way to reach a human.
3. **`/`** — marketing home. Optional for review, but it is where App Store and
   Play traffic lands, so ship it.
4. **Blocker:** `docs/PRIVACY.md` names **privacy@alliswell.space**, and the file's
   own header note says that mailbox **does not exist yet**. Create it (or change
   the address in both policy files) before you submit — a dead privacy contact
   is a rejection in both stores.

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
- **Third-party analytics / advertising / tracking:** **None.** The app ships no
  advertising, analytics or crash-reporting SDK, and
  `apps/app/ios/Runner/PrivacyInfo.xcprivacy` already declares
  `NSPrivacyTracking = false` with an empty tracking-domains list. Answer **No**
  to App Tracking Transparency — do not add the ATT prompt.

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

The app is open source (AGPL-3.0): https://github.com/mahirozdin/alliswell
Users may also run their own server; the "server address" field in the sign-in
screen exists for that and defaults to our hosted service.
```

### 1.9 What's New (0.4.0)

```text
This is the big one — everything since the first release.

BOARD VIEW
Home now flips between the chronological list and a kanban Board, with status columns you name, hide and reorder, and drag-to-move between them.

A REAL FILES SECTION
Attach files to tasks, notes and projects, and find every one of them in a workspace-wide Files section with nestable folders. Every project gets its own Files tab too.

ALARMS THAT MEAN IT
Urgent tasks now ring at their deadline with a real alarm sound, and keep re-alerting across the next half hour until you acknowledge them. Snooze in one tap, and turn on the privacy mode to keep task content off your lock screen.

SEARCH THAT SPEAKS TURKISH
Search now ignores case and Turkish accents everywhere — "cay" finds "Çay", "isi" finds "ısı" — and it runs on the device, so it is instant and works offline.

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

---

## 2. Google Play

### 2.1 App title (≤ 30 characters)

| #                     | Option                         | Count    |
| --------------------- | ------------------------------ | -------- |
| **A** _(recommended)_ | `AllisWell: Tasks & Reminders` | **(28)** |
| B                     | `AllisWell - Task & Note App`  | **(27)** |
| C                     | `AllisWell`                    | **(9)**  |

**Why A here but not on Apple.** Play has no separate keyword field — the title,
short description and full description _are_ the index. Spending the title on
category words is correct on Play and wasteful on Apple.

### 2.2 Short description (≤ 80 characters)

| #                     | Option                                                                             | Count    |
| --------------------- | ---------------------------------------------------------------------------------- | -------- |
| **A** _(recommended)_ | `Offline-first tasks, notes and files, with alarms that actually wake you.`        | **(73)** |
| B                     | `Tasks, notes, files and alarm-grade reminders. Open source. No ads, no tracking.` | **(80)** |
| C                     | `Open-source task manager: offline, realtime sync, alarms that keep ringing.`      | **(75)** |

This is the line under the icon on the store page and in search results. Option B
is exactly at the cap — verify it in the console before publishing, since Play
counts trailing whitespace.

### 2.3 Full description (≤ 4000 characters)

```text
AllisWell keeps your whole day in one place — tasks, projects, notes and files — with reminders strong enough to actually move you.

Open source. Works offline. No paid tier, no ads, no tracking.


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

• Rich-text notes with inline images and video, linked to tasks and projects, exportable as Markdown.
• Attach files to tasks, notes and projects — up to 10 MB per file on the hosted service.
• A workspace-wide Files section with nestable folders, and a Files tab in every project.


📶 OFFLINE FIRST, ALWAYS IN SYNC

Everything works with no connection: create, edit, complete, search. Changes queue on your device, push when you are back, and land on your other devices in realtime — phone, tablet, desktop and web, from one account.


📅 GOOGLE CALENDAR, BOTH WAYS

Connect Google Calendar and your tasks become events. Edits you make in Google come back to AllisWell, and your other Google events show up next to your tasks on Home.


🔎 SEARCH THAT SPEAKS TURKISH

Search ignores case and Turkish accents, so "cay" finds "Çay" and "isi" finds "ısı". It runs on the copy of your data on the device — instant, and it works offline.


🧩 ALSO IN THE BOX

• Home-screen widgets mirroring your Home buckets
• English and Turkish, following your system language
• Light and dark


🔓 OPEN SOURCE, AND YOURS TO HOST

AllisWell is AGPL-3.0. The whole app and server are public on GitHub, and you can run the entire stack yourself with one docker compose command — your data in your own MySQL, on your own machine, at your own domain. Use our hosted service or your own server; it is the same app either way.


🚫 NO PAID TIER. NO ADS. NO TRACKING.

There is no subscription and nothing locked behind one. There is no advertising, analytics or crash-reporting SDK in the app — none at all. We do not sell or share your data. You can delete your account and everything in it from Settings, in the app, without asking us.


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

| Data type                                                                                          | Collected               | Shared | Required? | Purpose                                                                                                                  |
| -------------------------------------------------------------------------------------------------- | ----------------------- | ------ | --------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Personal info → Email address**                                                                  | Yes                     | **No** | Required  | Account creation and sign-in                                                                                             |
| **Personal info → Name**                                                                           | Yes                     | **No** | Optional  | Display name, if the user sets one                                                                                       |
| **Personal info → User IDs**                                                                       | Yes                     | **No** | Required  | Account and device identity for sync                                                                                     |
| **App activity → Other user-generated content** (tasks, projects, notes, tags, folders, reminders) | Yes                     | **No** | Required  | App functionality; syncing across the user's own devices                                                                 |
| **Files and docs** (user uploads)                                                                  | Yes                     | **No** | Optional  | App functionality; only when the user attaches a file                                                                    |
| **Photos and videos** (inline note media)                                                          | Yes                     | **No** | Optional  | App functionality; only when the user embeds media in a note                                                             |
| **App info and performance → Diagnostics**                                                         | **No**                  | No     | —         | No crash-reporting or performance SDK is present                                                                         |
| **Device or other IDs**                                                                            | Yes                     | **No** | Required  | A per-install device id, so reminders reach the right devices                                                            |
| **Calendar**                                                                                       | **Not collected by us** | No     | Optional  | Google Calendar sync sends the task title and description to _the user's own_ Google account, only after they connect it |
| **Location / Contacts / Financial info / Health / Messages / Audio / Browsing history**            | **No**                  | No     | —         | Never collected                                                                                                          |

Also declare: **request logs include the IP address** for operating and securing
the service — map this to _App activity → Other actions_ or the console's
security-logging note, matching the "Technical logs" section of `docs/PRIVACY.md`.

**Not shared, and not for ads or tracking**

- **Data shared with third parties: none.** The only recipients are the
  infrastructure needed to run the service (server and database hosting,
  Cloudflare R2 for uploads) and — only if the user connects it — Google
  Calendar, at the user's explicit request. Under Play's definitions this is
  _processing_, not _sharing_.
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

  **This page must be created.** It must state: the in-app path
  (Settings → Delete account), the 3-day grace period and how to cancel, exactly
  what is erased, what is retained and for how long, and an off-app route
  (**privacy@alliswell.space**) for users who can no longer sign in. Apple has the
  same requirement for the in-app path — which the app already satisfies — but
  only Google requires the public URL.

---

## 3. Both stores — asset checklist

**Sizes are portrait unless noted.** All screenshots must be PNG or JPEG, RGB,
no alpha channel and no rounded corners baked in.

| #   | Store     | Asset                                      | Exact size                                                 | Count needed | Have it / To do                                                                                                                      |
| --- | --------- | ------------------------------------------ | ---------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | App Store | **iPhone 6.9"** screenshots                | 1290 × 2796                                                | 3–10 (min 3) | **To do**                                                                                                                            |
| 2   | App Store | **iPhone 6.5"** screenshots                | 1284 × 2778 _(or 1242 × 2688)_                             | 3–10         | **To do** — optional if 6.9" is supplied; Apple upscales. Ship it anyway if you support older devices.                               |
| 3   | App Store | **iPad 13"** screenshots                   | 2064 × 2752 _(portrait)_ or 2752 × 2064 _(landscape)_      | 3–10         | **To do** — **required** if the build declares iPad support. Drop iPad from the build's device family if you are not shipping these. |
| 4   | App Store | **App icon**                               | 1024 × 1024, no alpha, no transparency, no rounded corners | 1            | **Partly** — source at `docs/assets/logo.png`. Verify it is exactly 1024², sRGB and flattened; export if not.                        |
| 5   | App Store | **App preview video** (optional)           | per-device, 15–30 s                                        | 0–3          | **To do** — optional; skip for 0.4.0.                                                                                                |
| 6   | Play      | **Phone** screenshots                      | ≥ 1080 px on the short edge; 9:16 (e.g. 1080 × 1920)       | 2–8 (min 2)  | **To do**                                                                                                                            |
| 7   | Play      | **7" tablet** screenshots                  | 1200 × 1920 recommended                                    | up to 8      | **To do** — required only if the listing targets tablets; strongly recommended.                                                      |
| 8   | Play      | **10" tablet** screenshots                 | 1920 × 1200 _(landscape)_ or 1200 × 1920                   | up to 8      | **To do** — same condition as #7.                                                                                                    |
| 9   | Play      | **Feature graphic**                        | 1024 × 500, PNG/JPEG, no alpha                             | 1            | **To do** — mandatory. No text near the edges: Play crops it in several placements.                                                  |
| 10  | Play      | **App icon**                               | 512 × 512, 32-bit PNG **with** alpha                       | 1            | **Partly** — same source as #4; Play wants the alpha channel Apple forbids, so export separately.                                    |
| 11  | Play      | **Promo video** (optional)                 | YouTube URL                                                | 0–1          | **To do** — optional; skip for 0.4.0.                                                                                                |
| 12  | Both      | Localized screenshot sets (**en**, **tr**) | as above, per locale                                       | ×2           | **To do** — Turkish is the primary market; ship a Turkish set, not just English.                                                     |

### Generating the real screens

Real in-app screenshots come from the design harness:

```bash
cd apps/app
flutter test --update-goldens --dart-define=screenshots=true \
    test/design_screenshots_test.dart
# → apps/app/test/goldens/*.png
```

The harness (`apps/app/test/design_screenshots_test.dart`) renders the **real**
signed-in app — real router, real theme, real fonts, a seeded local replica — in
light and dark, at two form factors:

- **phone:** 390 × 844 logical @ 2× → **780 × 1688 px**
- **desktop:** 1280 × 800 logical @ 2× → **2560 × 1600 px**

**Neither output matches a store size.** Treat the goldens as the _source
imagery_ and composite them into store-sized frames (device bezel + a headline
band) at the exact dimensions in the table above. Do not simply upscale
780 × 1688 to 1290 × 2796 — it will look soft, and Apple's reviewers do notice.

Suggested screen order for both stores (first two carry almost all the
conversion): **Home (chronological + month calendar)** → **Board (kanban)** →
**urgent alarm / ring screen** → **note with attachments** → **Files with
folders** → **Projects** → **dark mode**.

Existing marketing screenshots (desktop-framed, from the README) live in
`docs/screenshots/` — `home-light.png`, `home-dark.png`, `board.png`,
`files.png`, `projects.png`, `mobile-home-light.png`, `mobile-home-dark.png`,
`mobile-create.png`. Useful as a reference for framing; not store-sized.

---

## 4. Turkish versions

Turkish is the primary market. These are written as Turkish marketing copy, not
as translations of §1–§2 — the emphasis and the idioms differ deliberately.

### 4.1 Apple App Store — Türkçe

**Uygulama adı (≤ 30 karakter)**

| #                  | Seçenek                         | Karakter |
| ------------------ | ------------------------------- | -------- |
| **A** _(önerilen)_ | `AllisWell`                     | **(9)**  |
| B                  | `AllisWell: Görev, Hatırlatıcı` | **(29)** |
| C                  | `AllisWell - Görev ve Alarm`    | **(26)** |

**Alt başlık (≤ 30 karakter)**

| #                  | Seçenek                          | Karakter |
| ------------------ | -------------------------------- | -------- |
| **A** _(önerilen)_ | `Görev, not ve gerçek alarm`     | **(26)** |
| B                  | `Çevrimdışı görev, gerçek alarm` | **(30)** |
| C                  | `Görev, not, dosya ve alarm`     | **(26)** |

**Tanıtım metni (≤ 170 karakter)**

```text
0.4.0 yayında: Kanban Pano, klasörlü Dosyalar bölümü, Türkçe uyumlu arama ve siz kapatana kadar tekrar tekrar çalan acil alarmlar.
```

**(130)**

**Anahtar kelimeler (≤ 100 karakter, virgülle ayrılmış, boşluksuz)**

```text
yapılacaklar,görev,hatırlatıcı,ajanda,planlayıcı,kanban,pano,proje,liste,çevrimdışı,açıkkaynak
```

**(94 / 100)** — A adı + A alt başlığı ile eşleşir; oradaki kelimeler tekrar edilmedi.

**Açıklama (≤ 4000 karakter)**

```text
AllisWell gününüzü tek yerde toplar: görevler, projeler, notlar ve dosyalar — üstüne sizi toplantıdan zamanında çıkaracak kadar ısrarcı hatırlatıcılar.

Açık kaynak. Çevrimdışı çalışır. Ücretli sürüm yok, reklam yok, takip yok.


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

• Zengin metin notları: satır içi görsel ve video, göreve ve projeye bağlama, Markdown olarak dışa aktarma.
• Göreve, nota ve projeye dosya ekleyin — barındırılan serviste dosya başına 10 MB'a kadar.
• Tüm çalışma alanını kapsayan, iç içe klasörlü bir Dosyalar bölümü; ayrıca her projenin kendi Dosyalar sekmesi.


ÖNCE ÇEVRİMDIŞI, HEP EŞİTLENMİŞ

Bağlantı olmadan da her şey çalışır: oluşturun, düzenleyin, tamamlayın, arayın. Değişiklikleriniz cihazda sıraya girer, siz döndüğünüzde gönderilir ve diğer cihazlarınıza anında düşer.


TAKVİMLER

• Google Takvim çift yönlü eşitlenir: görevleriniz etkinliğe dönüşür, Google'da yaptığınız düzenlemeler AllisWell'e geri gelir. Diğer Google etkinlikleriniz de Ana ekranda görevlerinizin yanında görünür.
• Apple Takvim bu sürümde tek yönlüdür: seçtiğiniz görevler, seçtiğiniz takvime yazılır.


TÜRKÇE BİLEN ARAMA

Arama büyük-küçük harfe ve Türkçe karakterlere takılmaz: "cay" yazınca "Çay", "isi" yazınca "ısı" gelir. Cihazınızdaki kopya üzerinde çalıştığı için anında yanıt verir ve çevrimdışı da çalışır.


AYRICA

• Ana ekran widget'ları, Ana ekrandaki gruplarınızı yansıtır (iPhone, iOS 16 ve üzeri).
• Türkçe ve İngilizce; sistem dilinizi kendisi seçer.
• Açık ve koyu tema.


AÇIK KAYNAK VE İSTERSENİZ KENDİ SUNUCUNUZDA

AllisWell, AGPL-3.0 lisanslıdır. Uygulamanın ve sunucunun tamamı GitHub'da açık; tek bir docker compose komutuyla hepsini kendiniz çalıştırabilirsiniz — veriniz kendi MySQL'inizde, kendi makinenizde, kendi alan adınızda. Bizim servisimizi de kendi sunucunuzu da kullanabilirsiniz; uygulama aynı uygulama.


ÜCRETLİ SÜRÜM YOK. REKLAM YOK. TAKİP YOK.

Abonelik yok, kilitli özellik yok. Uygulamanın içinde reklam, analitik ya da çökme raporlama kütüphanesi yok — hiçbiri. Verinizi kimseye satmıyor, kimseyle paylaşmıyoruz. Hesabınızı ve içindeki her şeyi, bize sormadan, Ayarlar'dan silebilirsiniz.


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

TÜRKÇE BİLEN ARAMA
Arama artık her yerde büyük-küçük harfe ve Türkçe karakterlere takılmıyor — "cay" yazınca "Çay", "isi" yazınca "ısı" geliyor. Üstelik cihazda çalışıyor: anında ve çevrimdışı.

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

| #                  | Seçenek                                                                     | Karakter |
| ------------------ | --------------------------------------------------------------------------- | -------- |
| **A** _(önerilen)_ | `Görev, not ve dosya; uyandıran alarmlar. Çevrimdışı çalışır, açık kaynak.` | **(73)** |
| B                  | `Görevler, notlar, dosyalar ve uyandıran alarmlar. Reklam yok, takip yok.`  | **(72)** |
| C                  | `Çevrimdışı çalışan görev yöneticisi. Gerçek alarmlar, anlık eşitleme.`     | **(69)** |

**Tam açıklama (≤ 4000 karakter)**

```text
AllisWell gününüzü tek yerde toplar — görevler, projeler, notlar ve dosyalar — üstüne sizi gerçekten harekete geçirecek hatırlatıcılar.

Açık kaynak. Çevrimdışı çalışır. Ücretli sürüm yok, reklam yok, takip yok.


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

• Zengin metin notları: satır içi görsel ve video, göreve ve projeye bağlama, Markdown olarak dışa aktarma.
• Göreve, nota ve projeye dosya ekleyin — barındırılan serviste dosya başına 10 MB'a kadar.
• İç içe klasörlü, çalışma alanının tamamını kapsayan bir Dosyalar bölümü; her projede ayrı bir Dosyalar sekmesi.


📶 ÖNCE ÇEVRİMDIŞI, HEP EŞİTLENMİŞ

Bağlantı olmadan da her şey çalışır: oluşturun, düzenleyin, tamamlayın, arayın. Değişiklikleriniz cihazda sıraya girer, siz döndüğünüzde gönderilir ve diğer cihazlarınıza anında düşer — telefon, tablet, masaüstü ve web, tek hesapla.


📅 GOOGLE TAKVİM, ÇİFT YÖNLÜ

Google Takvim'i bağlayın; görevleriniz etkinliğe dönüşsün. Google'da yaptığınız düzenlemeler AllisWell'e geri gelir, diğer Google etkinlikleriniz de Ana ekranda görevlerinizin yanında görünür.


🔎 TÜRKÇE BİLEN ARAMA

Arama büyük-küçük harfe ve Türkçe karakterlere takılmaz: "cay" yazınca "Çay", "isi" yazınca "ısı" gelir. Cihazınızdaki kopya üzerinde çalışır — anında, çevrimdışıyken bile.


🧩 AYRICA

• Ana ekrandaki gruplarınızı yansıtan widget'lar
• Türkçe ve İngilizce; sistem dilinizi kendisi seçer
• Açık ve koyu tema


🔓 AÇIK KAYNAK VE İSTERSENİZ KENDİ SUNUCUNUZDA

AllisWell, AGPL-3.0 lisanslıdır. Uygulamanın ve sunucunun tamamı GitHub'da açık; tek bir docker compose komutuyla hepsini kendiniz çalıştırabilirsiniz — veriniz kendi MySQL'inizde, kendi makinenizde, kendi alan adınızda. Bizim servisimizi de kendi sunucunuzu da kullanabilirsiniz; uygulama aynı uygulama.


🚫 ÜCRETLİ SÜRÜM YOK. REKLAM YOK. TAKİP YOK.

Abonelik yok, kilitli özellik yok. Uygulamanın içinde reklam, analitik ya da çökme raporlama kütüphanesi yok — hiçbiri. Verinizi kimseye satmıyor, kimseyle paylaşmıyoruz. Hesabınızı ve içindeki her şeyi, bize sormadan, Ayarlar'dan silebilirsiniz.


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
Türkçe arama: "cay" yazınca "Çay" gelir; cihazda çalışır, çevrimdışı da bulur.
Google Takvim tek adımda bağlanır.
Ayrıca: widget'lar, yenilenen görünüm, tek komutla kendi sunucunuz.
```

**(452 / 500)**

<details>
<summary>English "What's New" for Play (≤ 500 characters)</summary>

```text
Kanban Board: flip Home between list and board, with columns you define.
Files: attach files to tasks, notes and projects, and find them all in nestable folders.
Serious alarms: urgent tasks ring at the exact minute with a real alarm sound, and keep re-alerting until you acknowledge.
Turkish-aware search: "cay" finds "Çay" — on-device, so it works offline.
Google Calendar now connects in one step.
Plus: home-screen widgets, a refreshed look, and one-command self-hosting.
```

**(475 / 500)**

</details>

---

## 5. Claim guardrails

Things a reasonable copywriter would have written that are **not true of the
shipped build**. Do not add them back without re-checking the code.

| Claim                                                       | Why it is not in the copy                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **"Rings through the mute switch" / "AlarmKit"**            | The iOS 26 AlarmKit lane's Dart side is complete and tested, but the native bridge is **not in the build**: `AlarmKitBridge.swift` appears **zero** times in `apps/app/ios/Runner.xcodeproj/project.pbxproj`, and `apps/app/ios/Runner/AppDelegate.swift` explicitly leaves it unregistered ("Kept out of the committed build"). `apps/app/ios/Runner/ALARMKIT_SETUP.md` documents the remaining device-only step. Until that ships, urgent alarms are time-sensitive notifications with a bundled sound — **which a hardware mute switch can still silence.** The 0.4.0 CHANGELOG says as much under _Known limitations_. |
| **"Alarms that never stop until you dismiss them"**         | The re-alert chain is a **finite, pre-scheduled** set of 5 alerts at 0 / 2 / 5 / 10 / 30 minutes (`kUrgentChainOffsets`, `apps/app/lib/src/notifications/planner.dart`). "Keeps re-alerting across the next half hour" is accurate; "never stops" is not.                                                                                                                                                                                                                                                                                                                                                                  |
| **"Two-way Apple Calendar sync"**                           | Apple/EventKit is **one-way only** (task → event). The native plugin exposes no list-events method, and `apps/app/lib/src/features/calendar/apple/apple_mirror_engine.dart` states the one-way limit in its own doc comment. Only Google is two-way. Note that `README.md` currently overstates this — the store copy deliberately does not follow it.                                                                                                                                                                                                                                                                     |
| **"Tap to complete from the widget"**                       | No `AppIntent` exists in any Swift file; the iOS widget is a `StaticConfiguration` whose only interaction is `.widgetURL`, and the Android provider only opens `MainActivity`. Widgets are read-only glances.                                                                                                                                                                                                                                                                                                                                                                                                              |
| **"Widgets on iPhone, Android and Mac"**                    | There is **no macOS widget target**, so the copy claims iPhone and Android only. The iOS widget extension's deployment target was 26.2 (invisible to almost every device) and is now **16.0** — fixed 2026-07-26, so the iPhone claim needs no qualifier. |
| **"Subtasks", "recurring tasks", "natural-language dates"** | None of these exist. Grep for `subtask` / `rrule` in `apps/app/lib` returns nothing but comments about calendar events.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **"Share a project with your team" / collaboration**        | No sharing, invitation, comment or messaging surface ships. This also underpins the "No" answers in §1.8 and §2.5 — if collaboration ever ships, both questionnaires must be refiled.                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **"Unlimited file uploads" / "up to 5 GB"**                 | The code default for `STORAGE_MAX_UPLOAD_MB` is 512, but every shipped environment sets **10** (`.env.production`, `docker-compose.selfhost.yml`, `.env.selfhost.example`), and `docs/PRIVACY.md` states 10 MB for the hosted service. The copy says **10 MB on the hosted service** and notes self-hosters can change it.                                                                                                                                                                                                                                                                                                 |
| **"Instant account deletion"**                              | Deletion has a **3-day grace period** and is cancellable by signing in. The copy says you can delete from Settings without saying it is immediate; §2.6 states the grace period explicitly, as Play requires.                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Any rating, download count, award or "#1" claim**         | The app has not shipped. No social proof of any kind appears in this file.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

### Pre-submission blockers (not copy — build and infrastructure)

- [ ] **Android release signing** still uses the debug keystore
      (`apps/app/android/app/build.gradle.kts`, `signingConfig = signingConfigs.getByName("debug")`).
      Play will reject the upload.
- [ ] **Display name is inconsistent:** `Alliswell` on iOS
      (`CFBundleDisplayName`) vs `alliswell` on Android (`android:label`).
      Pick `AllisWell` and set it on both before the first submission — the
      home-screen label is much harder to change later than the store title.
- [ ] **`privacy@alliswell.space` does not exist yet** (see the header note in
      `docs/PRIVACY.md`). Create the mailbox or change the address in both
      policy files.
- [ ] **Three web pages must exist:** `/privacy`, `/support`, `/delete-account`
      (§1.6, §2.6).
- [ ] **`ITSAppUsesNonExemptEncryption = false`** in `apps/app/ios/Runner/Info.plist`,
      so every upload skips the export-compliance prompt.
- [ ] **Demo account** created on the hosted service, with credentials in both
      stores' review notes.
