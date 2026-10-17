# AllisWell vs. the field

A working document, not marketing copy. It exists so that every claim on the
README, the landing page and the store listings can be traced to something the
code actually does — and so the places where a competitor is genuinely better
are written down instead of quietly avoided.

Researched and written against **v1.4.0** (2026-08-12) — that is provenance, not
our current version; the live figure is in the table at §5. <!-- docs-check-ignore -->
Competitor behaviour in §2–§6 is stated as of mid-2026; re-check before a release cycle,
because half of it changes yearly. §7 compares the **self-hosted** field (Vikunja,
Super Productivity, Tasks.org, Nextcloud Tasks) and was checked on 2026-10-16.

**Contents:** [1. What we built](#1-what-we-built-the-full-inventory) ·
[2. The field](#2-the-field) · [3. Feature matrix](#3-feature-matrix) ·
[4. The seven real differences](#4-the-seven-real-differences) ·
[5. Where they beat us](#5-where-they-beat-us-honestly) ·
[6. Positioning](#6-positioning) ·
[7. Self-hosted alternatives](#7-self-hosted-alternatives-checked-2026-10)

---

## 1. What we built (the full inventory)

Grouped by surface, each line tagged with the epic that shipped it. This is the
list every screenshot, the landing page and the store copy draw from.

### Capture & planning

| Feature                                                                                                   | Shipped     |
| --------------------------------------------------------------------------------------------------------- | ----------- |
| One-tap quick add; dated or dateless                                                                      | Epic 04     |
| **Inbox ("capture box")** — unplanned thoughts stay out of the day until promoted                          | Epic 10     |
| Detailed create sheet: project, priority, tags, description, attachments, date **and time** in one pass    | 15/16       |
| **Natural-language quick add, offline, TR + EN** — "yarın 9'da kira #ev" becomes a dated, tagged task; chips show what was read | OPH-373     |
| Optional ✨ AI parse in quick-add on top — several tasks out of one sentence                               | OPH-222     |
| **Share target** — share any text or link from any app straight into the capture bubble                    | OPH-225     |
| **Press-and-hold to talk** — on-device speech, becomes a proposed task                                     | OPH-223/224 |
| Default task time (23:59) as a preference, not a hard-coded assumption                                    | OPH-161     |

### The day

| Feature                                                                                                        | Shipped |
| ---------------------------------------------------------------------------------------------------------------- | ------- |
| **Home**: one chronological surface — overdue · today · this week · next 30 days, dateless pinned on top       | Epic 10 |
| Apple-style month calendar in the same scroll; a selected day escapes the 30-day horizon                       | OPH-162 |
| **Board (kanban)** on the same data: hideable, reorderable status columns, drag-to-move + a visible status button | OPH-168 |
| View controls (List/Board, filters) live in the app bar                                                        | OPH-213 |
| Completed tasks stay on today's list, struck through, until the next midnight                                  | OPH-185 |
| **Settings ▸ Completed** — an infinite, day-headed timeline of everything finished                             | OPH-186 |
| Pull-to-refresh on every list surface                                                                          | OPH-171 |

### Structure

| Feature                                                                                       | Shipped     |
| --------------------------------------------------------------------------------------------- | ----------- |
| Projects with colour, favourite, archive, and a Notion-style **README note** as the overview  | Epic 04/10  |
| Per-project **Tasks / Notes / Files** tabs                                                    | Epic 14     |
| Inline `#tags` — auto-create, colours, fold-matched suggestions, a management sheet           | OPH-165     |
| Priorities `none → urgent`; per-task colour                                                   | Epic 04     |
| Subtasks as real parent/child rows, with cascade — in the API, MCP and sync; **the app has no subtask screen** | Epic 04     |
| Checklists inside a task                                                                      | Epic 04     |
| **Quick access** — a personal shortcut rail for projects, tasks, notes, folders, files and URLs, with your own emoji, colour and order | Epic 18 |

### Reminders & alarms

| Feature                                                                                                | Shipped |
| -------------------------------------------------------------------------------------------------------- | ------- |
| Exact-minute local delivery, per device                                                                | Epic 07 |
| **Urgent alarms that ring through Silent mode and Focus** (iOS 26 AlarmKit; Android `USAGE_ALARM` insistent channel) | 13/16 |
| A re-alert chain that keeps coming back until acknowledged; the profile (how many, how far apart) is a setting | OPH-179 |
| Snooze presets 5 m / 30 m / 1 h / tomorrow / custom — each says what will happen                        | OPH-177 |
| **Mute one task's alarms** without completing it                                                       | OPH-178 |
| Ringtone library + your own uploaded sound                                                             | OPH-181 |
| Full-screen ring screen; degradation banners when the OS is throttling us                              | OPH-143 |
| **An alarm log** — a diagnosis record, because "it didn't ring" is unanswerable without one            | OPH-176 |
| A privacy mode that hides task content on the lock screen                                              | Epic 07 |

### Recurrence

| Feature                                                                                                    | Shipped |
| ------------------------------------------------------------------------------------------------------------ | ------- |
| Daily / weekly / monthly / yearly, with intervals                                                          | Epic 19 |
| Weekdays, "the last day of the month", "the 2nd Tuesday", "the first Monday after the 22nd"                | OPH-205 |
| **Impossible days clamp instead of skipping** — the 31st becomes 28 February, it does not vanish (ADR-0020) | OPH-204 |
| A live **"next 5" preview** in the dialog: the days you are about to get, before you commit                | OPH-207 |
| Occurrences are **real rows** for 12 rolling months — visible in the calendar, in search and in the widget  | OPH-205 |
| Editing one occurrence asks how far it reaches: **this / this and future / all**                           | OPH-206 |
| **Repeat N days / weeks / months after completion** — late or early, it counts from when you did it          | OPH-375 |

### Notes & files

| Feature                                                                             | Shipped |
| ------------------------------------------------------------------------------------- | ------- |
| Markdown notes (GFM), Apple-Notes-style in-document H1 title                         | Epic 05 |
| Pin, archive, card grid or list, Markdown export                                     | Epic 05 |
| Inline images and video inside notes (`alliswell://file/{id}` embeds)                | OPH-156 |
| Attachments on tasks, notes and projects                                             | Epic 14 |
| A workspace-wide **Files** section with nestable folders (≤ 10 deep)                 | OPH-169/170 |
| Storage is **Cloudflare R2 / any S3 via presigned URLs** — bytes go direct, with one capped relay for pages that cannot run scripts (ADR-0011 amendment) | Epic 14 |
| **Markdown workspace** — GFM rendering (tables, callouts, footnotes, maths, Mermaid), three modes, outline/folding/find, command palette | OPH-246…250 |
| **Open a `.md` from your computer, edit it and save it BACK to that file** — marked, never autosaved, conflict-aware | OPH-251 (ADR-0030) |

### Calendar

| Feature                                                                                       | Shipped |
| ----------------------------------------------------------------------------------------------- | ------- |
| **Two-way Google Calendar sync** — OAuth, encrypted tokens, push webhooks, incremental sync, etag conflict resolution | Epic 08 |
| Your own Google events flow **back into Home**, next to your tasks                             | OPH-083 |
| Apple Calendar via an on-device **EventKit** bridge — one-way for now (tasks → events)        | Epic 08 |
| **Every task is on the calendar — and it is not a setting.** The mirror stopped being a toggle | OPH-210 |
| iCloud or any CalDAV calendar (Nextcloud, Radicale…) from the server — events two-way, off until the admin enables it; tasks are not served as CalDAV/VTODO | OPH-380 |

### Search

| Feature                                                                                                   | Shipped |
| ----------------------------------------------------------------------------------------------------------- | ------- |
| Case- **and accent-insensitive** across the Latin alphabets: "muller" finds _Müller_                       | OPH-167 |
| Ranked title → tag → body                                                                                 | OPH-167 |
| Runs **on the device replica** — instant, and it works offline                                            | ADR-0013 |
| The fold is app-owned on purpose: **neither SQLite nor MySQL folds ı→i** (DUCET gives them separate weights) | ADR-0013 |

### AI (all optional, all off by default)

| Feature                                                                                    | Shipped |
| -------------------------------------------------------------------------------------------- | ------- |
| **Remote MCP server** — add AllisWell to the Claude or ChatGPT subscription you already pay for | OPH-218 |
| MCP tools are read-first; **there is no delete tool, ever**; OAuth 2.1 + PKCE + DCR         | OPH-218 |
| In-app chat bubble over your own data, SSE-streamed                                        | OPH-217/221 |
| **Bring your own key**: Anthropic · OpenAI · Gemini · OpenRouter · local **Ollama**         | OPH-216 |
| Every proposed task waits for **your one-tap confirmation**; the model gets **no tools**    | OPH-222 |
| A consent screen that states each provider's real data policy (including Gemini's free tier training on your data) | OPH-220 |
| Red-team corpus against prompt injection in the test suite                                 | OPH-226 |

### Platform & foundation

| Feature                                                                                          | Shipped |
| -------------------------------------------------------------------------------------------------- | ------- |
| **Six platforms from one Flutter codebase** — iOS, Android, Web, macOS, Windows, Linux            | Epic 01 |
| **Local-first**: SQLite replica, mutation outbox, revision log, idempotent push, field-level LWW  | Epic 06 |
| Realtime fan-out over Socket.IO                                                                   | Epic 06 |
| Home-screen widgets: iOS and Android — with today's open count and tick-off without opening the app | Epic 12 |
| English + Turkish, auto-detected; a new language is one JSON file                                 | Epic 11 |
| Light + dark, contrast-verified by a script on every UI change (DESIGN §5)                        | Rule 11 |
| **Self-hosted**: your MySQL/MariaDB, one `docker compose up`, free for personal use                | Epic 09 |
| **A documented REST API** — personal API keys, 78 key-reachable endpoints, bulk import/export, a generated reference and a Postman collection | Epic 25 |

---

## 2. The field

### Google Calendar

The default calendar for most of the planet, and genuinely excellent at being a
calendar: invitations, free/busy, rooms, appointment schedules, working hours,
shared calendars, and an ecosystem every other tool integrates with.

It is not a task manager. Google Tasks appears in its sidebar, but tasks have no
priorities, no tags and no attachments. Notifications are chimes; nothing in
Google Calendar rings like an alarm. And its recurrence follows RFC 5545
literally: **a monthly event on the 31st simply does not occur in February.**

### Google Tasks

Deliberately minimal: lists, tasks, one level of subtasks, a due date and time,
a repeat, a "details" field, and a star. It is everywhere Google is — Gmail's
side panel, Calendar, the mobile apps.

That is the whole product. No priorities, no labels, no attachments, no notes,
no board, no search worth the name, no sharing. It is a shopping list that
follows you around, and it is very good at that.

### Apple Reminders

The most underrated app on this page. Lists and groups, smart lists, sections,
subtasks, tags, flags, three priorities, **location-based** and
**messaging-based** reminders, early reminders, custom repeats, image/URL
attachments, list templates, shared lists with assignments, a column view, and
since iOS 18 it shows up inside Apple Calendar.

The catch is the obvious one: it exists only where Apple exists. There is no
Android app, no Windows app, no Linux app, and the web version is a thin
iCloud.com panel. Your data is in iCloud, not anywhere you can point at.

### Apple Calendar

Events, natural-language entry, travel time, multiple alerts, shared calendars,
and — importantly for us — **CalDAV**, which is the only reason a non-Apple tool
can talk to it at all. Merged Reminders into its month view in iOS 18.

### Things 3

The design benchmark. Inbox → Today → Upcoming → Anytime → Someday is still the
clearest planning model anyone has shipped; Areas, Projects and Headings give
structure without ceremony; checklists live inside a to-do; deadlines and "when"
dates are correctly separated; Quick Entry with autofill is a joy.

It is Apple-only, single-user, paid once per platform (~$80 for Mac + iPad +
iPhone), has no web app, no attachments beyond links, no collaboration, no
kanban, reads your calendar **one way**, and is closed source with sync you
cannot host.

### Todoist / TickTick / Notion (context)

**Todoist** owns cross-platform discipline: natural-language dates, labels,
filters, karma, collaboration, everywhere. Free tier caps you at five personal
projects; the rest is a subscription. **TickTick** is the "everything" app —
tasks, calendar, habits, pomodoro, kanban, notes — behind a subscription.
**Notion** is a documents-and-databases tool that people bend into a task
manager; it has no real reminders and needs a network.

None of the three can be self-hosted.

---

## 3. Feature matrix

Legend: ● full · ◐ partial / with caveats · ○ none. ¹ API and MCP only — no subtask screen in the app.

| | **AllisWell** | Google Calendar | Google Tasks | Apple Reminders | Apple Calendar | Things 3 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Source available** | ● PolyForm NC | ○ | ○ | ○ | ○ | ○ |
| **Self-hosted (your database)** | ● MySQL/MariaDB | ○ | ○ | ○ | ○ | ○ |
| **Price** | free | free | free | free | free | ~$80 one-off |
| iOS · Android | ● ● | ● ● | ● ● | ● ○ | ● ○ | ● ○ |
| macOS · Windows · Linux | ● ● ● | ◐ web | ◐ web | ● ○ ○ | ● ○ ○ | ● ○ ○ |
| Web app | ● | ● | ◐ in Gmail | ◐ iCloud | ◐ iCloud | ○ |
| **Works fully offline** | ● local-first | ◐ | ◐ | ● | ● | ● |
| Realtime multi-device sync | ● | ● | ● | ● | ● | ● |
| Tasks with dates **and** times | ● | ◐ events | ● | ● | ◐ | ● |
| Inbox / capture separation | ● | ○ | ○ | ◐ | ● | ● |
| Kanban board | ● custom columns | ○ | ○ | ◐ column view | ○ | ○ |
| Projects / areas | ● | ○ | ◐ lists | ◐ lists+groups | ○ | ● |
| Subtasks · checklists | ◐¹ ● | ○ ○ | ◐ 1 level ○ | ● ○ | ○ ○ | ● ● |
| Tags · priorities | ● ● | ○ ○ | ○ ○ | ● ● | ○ ○ | ● ◐ |
| Rich notes / documents | ● | ○ | ○ | ○ separate app | ○ | ◐ |
| Markdown files edited in place | ● | ○ | ○ | ○ | ○ | ○ |
| File attachments | ● any file, R2/S3 | ◐ Drive | ○ | ◐ images/URLs | ◐ | ○ links |
| **Alarms that break Silent + Focus** | ● | ○ | ○ | ◐ time-sensitive | ◐ | ○ |
| Re-alert until acknowledged | ● | ○ | ○ | ○ | ○ | ○ |
| Snooze presets | ● | ◐ | ○ | ◐ | ◐ | ○ |
| Custom alarm sounds | ● | ○ | ○ | ● | ● | ○ |
| **Recurrence clamps (31st → 28 Feb)** | ● | ○ skips | ○ | ● | ○ skips | ● |
| "This / this and future / all" edits | ● | ● | ○ | ◐ | ● | ◐ |
| **Two-way Google Calendar sync** | ● | native | native | ○ | ◐ subscribe | ○ read-only |
| Apple Calendar | ◐ one-way (EventKit) | ◐ | ○ | native | native | ◐ read-only |
| Accent-insensitive search | ● | ○ | ○ | ○ | ○ | ○ |
| Home-screen widgets | ● iOS/Android | ● | ● | ● | ● | ● |
| **MCP connector for Claude / ChatGPT** | ● | ○ | ○ | ○ | ○ | ○ |
| In-app AI with **your own key** | ● 5 providers | ○ | ○ | ○ | ○ | ○ |
| Voice capture | ● on-device | ◐ Assistant | ◐ Assistant | ● Siri | ● Siri | ◐ Siri |
| Localisation | EN + TR | many | many | many | many | many |
| Collaboration / sharing | ◐ workspaces | ● | ○ | ● | ● | ○ |

---

## 4. The seven real differences

Everything above is context. These seven are the reasons to switch — and each
one is a thing a competitor **cannot** do, not merely hasn't yet. "Competitor"
here means the hosted products in §2; against the self-hosted field some of these
are shared, and §7 says which.

1. **It's yours.** The source is public, one `docker compose up`, your own MySQL on your own
   machine at your own domain. None of the hosted products above offer that at any price; the
   self-hosted ones in §7 do, and §7 says where they beat us.
2. **Alarms, not notifications.** A reminder that rings through Silent mode and
   Focus, keeps re-alerting until you acknowledge it, and writes a log entry
   explaining itself when it doesn't. Reminders can be "time sensitive"; only an
   alarm gets you out of a meeting.
3. **Recurrence that doesn't lie.** "The 31st" means month end. Google Calendar
   drops February; we clamp to the 28th, show you the next five days before you
   commit, and materialise 12 months of real rows so the calendar, the search and
   the widget all agree.
4. **Real two-way Google Calendar sync — and your tasks in Apple Calendar too.**
   Not an ICS subscription, not read-only import: your tasks become events, edits
   in Google come back, and your Google events appear on Home. On iPhone and Mac
   the same tasks are mirrored into Apple Calendar (one-way for now). Things 3
   reads your calendar; it never writes to it.
5. **One codebase, six platforms, offline-first.** A local SQLite replica, a
   mutation outbox and a revision log — everything works with the network off,
   and lands everywhere else within a round-trip when it returns. Apple's tools
   are Apple-only; Google's need the network more than they admit.
6. **AI on your terms.** Connect AllisWell to the Claude or ChatGPT subscription
   you already pay for (MCP), or bring your own API key — including a local
   Ollama, where nothing leaves the machine. The model gets **no write tools**;
   every proposal waits for your tap; deletion is closed to AI permanently.
7. **Search that does not care how you type it.** Accents and case are folded
   across the Latin alphabets — ß, ñ, å, ø, ł, č, é — so "muller" finds _Müller_
   and "cafe" finds _café_. The fold is the app's own rather than the database's,
   because collations disagree with each other and some of them get letters
   outright wrong; owning it means a search returns the same rows whether you run
   MySQL, MariaDB or the on-device SQLite replica. Every competitor on this page
   makes you type the diacritic.

---

## 5. Where they beat us (honestly)

Writing these down is what makes §4 trustworthy.

| They have | Who | Where we are |
| --- | --- | --- |
| **Location-based reminders** ("when I get home") | Apple Reminders | Not built. Real gap; geofencing is a v2 candidate. |
| **Reminders when messaging a person** | Apple Reminders | Not built, and iOS-only by nature. |
| **Invitations, RSVPs, free/busy, rooms** | Google & Apple Calendar | Out of scope — we mirror to your calendar and let it do this. |
| **Natural-language date entry, everywhere** | Todoist, Things 3 | Built in, Turkish and English, offline, in every quick-add bar (OPH-373); the AI parse is an optional extra. The grammar is younger than Todoist's: no durations or repeat ends in the text yet, and no parsing in the detailed create sheet. |
| **Real collaboration** — assignees, comments, shared lists | Todoist, Apple Reminders, Google | Workspaces exist in the model; the sharing UI is not built. Single-user today. |
| **Maturity** — a decade of edge cases, App Store trust, an ecosystem | all of them | We are at 1.18.0. This is a young product. |
| **Ecosystem reach** — Siri, Gmail side panel, Watch complications | Apple, Google | Widgets ship; Siri/Watch integration is designed (OPH-183), not delivered. |
| **Design polish over years** | Things 3 | We took their model and our own design system is strict — but they have had ten years to sand the corners. |
| **Localisation breadth** | all of them | Two languages. Adding one is a JSON file, which is the point, but the file has to be written. |
| **Sharing, tasks over CalDAV, a public demo, importers beyond Todoist/TickTick** | Vikunja, Nextcloud Tasks, Tasks.org | Not built — see §7. Calendar events go to any CalDAV calendar (OPH-380); we import Todoist and TickTick exports (OPH-371). |

Two more, said plainly: **self-hosting is work.** A managed app has no
`docker compose`, no TLS certificate, no backups to think about. And
**alarm-grade delivery depends on the OS** — AlarmKit needs iOS 26, and Android
OEM battery managers can still throttle us, which is exactly why the alarm log
exists.

---

## 6. Positioning

> **AllisWell is what you get when Things 3's planning model, Apple Reminders'
> alarms and Google Calendar's two-way sync are built as one source-available app you
> can host yourself — and then handed an MCP connector.**

Ordered by what actually moves someone:

1. **"Your data, your server."** Self-hostable like Vikunja or Nextcloud — but with
   native store apps on iOS and Android, alarm-grade reminders and two-way Google
   Calendar (§7).
2. **"Reminders that actually wake you up."** The single most concrete daily
   benefit, and the hardest to copy.
3. **"Add it to Claude or ChatGPT."** None of the hosted apps in §2 has it. The
   self-hosted field is arriving: Vikunja ships an MCP server since 2.7.0, Tasks.org one
   in its desktop app (§7). Ours is a remote OAuth connector with no delete tool.
4. **"One app on all six platforms."** The answer to "I'm on Android and my
   partner is on iPhone."
5. **"Free, forever, for you."** Not a trial, not a freemium cap — free for
   personal use and self-hosting, with commercial licensing for businesses.

**What we do not claim:** that we are more mature than Things 3, that we
collaborate like Todoist, or that we replace Google Calendar's meeting
machinery. Those lines are in §5 for a reason — see also
[docs/STORE-LISTING.md §5 Claim guardrails](STORE-LISTING.md#5-claim-guardrails).

---

## 7. Self-hosted alternatives (checked 2026-10)

Everything above compares us with hosted products, and against those "you can run it
yourself" wins on its own. Someone who already runs a homelab has a different list:
**Vikunja, Super Productivity, Tasks.org and Nextcloud Tasks** — older than us, with
far bigger communities, and in several places better. This section is for them.

Checked **2026-10-16** against each project's own repository, documentation and
pricing page; stars and versions are as of that day. A cell we could not confirm from
an official source says **—** (not checked) rather than a guess. Re-check before a
release cycle — two of the four shipped a release in the fortnight before this was
written.

### The four

**[Vikunja](https://vikunja.io)** ([go-vikunja/vikunja](https://github.com/go-vikunja/vikunja),
AGPL-3.0, since 2018, v2.7.0 of 2026-10-02) is the closest match and the one most people
mean by "self-hosted Todoist alternative". A Go server on MySQL, PostgreSQL or SQLite;
list, Gantt, table and Kanban views; projects shared with users, teams or by a link that
needs no account ([features](https://vikunja.io/features)); [CalDAV](https://vikunja.io/docs/caldav);
importers for Todoist, Trello, Microsoft To Do, Planka, TickTick, WeKan and CSV
([migration](https://vikunja.io/docs/migration-from-third-party-services)); a public demo
at [try.vikunja.io](https://try.vikunja.io); and, since 2.7.0, a built-in MCP server with
token access, read-only tokens included ([release notes](https://vikunja.io/changelog/vikunja-2.7.0-was-released/)).
Reminders go out by e-mail once a mail server is configured. Its own install guide says
the mobile app "only supports the very basic features"
([installing](https://vikunja.io/docs/installing)); the desktop app is the web frontend
packaged.
**It wins on** sharing, views, CalDAV, importers and maturity. **We win on** phones
(native store apps with alarm-grade reminders), two-way Google Calendar, a local-first
replica that works offline, and recurrence that clamps the 31st.

**[Super Productivity](https://super-productivity.com)**
([super-productivity/super-productivity](https://github.com/super-productivity/super-productivity),
MIT, since 2017, v19.2.0 of 2026-10-11) is a personal planner for focused work, and needs
no server and no account at all. Linux, macOS, Windows, Android and iOS, plus a web
version with limitations; Kanban and Eisenhower boards; time tracking, timesheets,
timeboxing and a focus mode with Pomodoro; issue-tracker integrations (Jira, GitHub,
GitLab, Gitea, OpenProject, Linear, ClickUp, Redmine, Trello, Nextcloud Deck, Azure DevOps);
basic CalDAV; sync over its own end-to-end-encrypted SuperSync (which you can host
yourself), WebDAV or Dropbox. An MCP endpoint was merged on 2026-10-12, after v19.2.0,
so it is not in a release yet.
**It wins on** time tracking, developer integrations, no account, a far larger community.
**We win on** a server that owns your data and does the work (two-way Google Calendar
runs there, not on a device), alarms that ring through Silent mode, and the markdown
workspace.

**[Tasks.org](https://tasks.org)** ([tasks/tasks](https://github.com/tasks/tasks),
GPL-3.0, since 2013) is an Android app first. Free, with no account: unlimited tasks,
reminders, recurring tasks, **location-based reminders**, and connections to Google Tasks
and Microsoft To Do. Self-hosted sync (CalDAV, DAVx⁵, EteSync) and its desktop app for
Windows, macOS and Linux are in a name-your-price tier from $0.99/year; Tasks.org Cloud
($29.99/year) adds Friends & Family list sharing, e-mail-to-task and Apple Reminders on
iOS ([pricing](https://tasks.org/pricing)). Its desktop app gained an MCP server in 15.12
(2026-09-11). There is no web app and no iOS app of its own.
**It wins on** location reminders, CalDAV interoperability and thirteen years of Android
polish. **We win on** iPhone and the web, a server of your own rather than a sync
target, and two-way Google Calendar (Tasks.org connects to Google *Tasks*, not Calendar).

**[Nextcloud Tasks](https://github.com/nextcloud/tasks)** (AGPL-3.0, since 2016, v0.18.1
of 2026-06-29) is a web app inside Nextcloud, storing tasks as CalDAV. If you already run
Nextcloud it costs nothing to add. Reminders arrived in
[0.17.0](https://github.com/nextcloud/tasks/releases/tag/v0.17.0) (2025-10) and repeating
tasks in [0.18.0](https://github.com/nextcloud/tasks/releases/tag/v0.18.0) (2026-06), with
recurrence bugs still open ([#3227](https://github.com/nextcloud/tasks/issues/3227),
[#3265](https://github.com/nextcloud/tasks/issues/3265)). It has no mobile app of its own
and points to CalDAV clients such as DAVx⁵, OpenTasks, Tasks.org and 2Do; sharing goes
through [Nextcloud's calendar sharing](https://docs.nextcloud.com/server/latest/user_manual/en/groupware/calendar.html)
— users, groups, federated servers.
**It wins on** fitting into a Nextcloud you already run, and on CalDAV and sharing for
free. **We win on** phone apps of our own, reminders that ring, and recurrence that
clamps the 31st and previews the next five dates.

### Side by side

Legend: ● yes · ◐ partly (the cell says how) · ○ no · — not checked.

| | **AllisWell** | Vikunja | Super Productivity | Tasks.org | Nextcloud Tasks |
| --- | :---: | :---: | :---: | :---: | :---: |
| Licence | PolyForm NC (source-available) | AGPL-3.0 | MIT | GPL-3.0 | AGPL-3.0 |
| GitHub stars (2026-10-16) | 21 | 5,769 | 22,872 | 5,660 | 707 |
| Project since | 2026 | 2018 | 2017 | 2013 | 2016 |
| What you run | API + MySQL/MariaDB + Redis (+ S3 for files) | Go server + MySQL/Postgres/SQLite | nothing; optional SuperSync server or WebDAV | nothing; a CalDAV/EteSync server of your choice | a Nextcloud server |
| Native iOS · Android apps | ● store · ● store | ◐ "very basic features" | ● · ● | ○ · ● | ○ · ○ (any CalDAV client) |
| Web app | ● | ● | ◐ with limitations | ○ | ● inside Nextcloud |
| Desktop | ◐ Windows/Linux download, macOS from source | ● packaged web frontend | ● | ◐ name-your-price tier | ○ browser |
| Account needed | ● | ● | ○ | ○ | ● Nextcloud |
| Views | list · board · month calendar | list · Kanban · Gantt · table | list · Kanban · Eisenhower · schedule | lists + filters | — |
| Reminders | ● alarm through Silent mode, re-alert until acknowledged | ◐ e-mail, needs a mail server | ● | ● incl. location | ◐ since 0.17 (2025-10) |
| Repeating tasks | ● | ● | ● | ● | ◐ since 0.18 (2026-06), open bugs |
| Monthly on the 31st clamps to month end | ● | — | — | — | — |
| Two-way Google Calendar | ● | ○ | — | ○ (Google Tasks, not Calendar) | ○ |
| CalDAV | ◐ calendar events over CalDAV (iCloud, Nextcloud…); tasks are not served as CalDAV/VTODO | ● | ◐ basic | ◐ name-your-price tier | ● native |
| Sharing | ○ no sharing UI | ● users · teams · link shares | ○ | ◐ Cloud tier, Friends & Family | ● via Nextcloud calendar sharing |
| Import from other apps | ◐ Todoist · TickTick (wizard) + API bulk import | ● Todoist · Trello · MS To Do · TickTick · Planka · WeKan · CSV | — | ◐ connects to Google Tasks / MS To Do | — |
| Public demo | ○ | ● try.vikunja.io | ● web app, no account | ○ | ○ |
| Time tracking · focus mode | ○ | — | ● | — | ○ |
| Issue-tracker integrations | ○ | — | ● Jira · GitHub · GitLab · … | ○ | ○ |
| MCP for AI assistants | ● remote, OAuth, no delete tool | ● since 2.7.0, token | ◐ merged, not released | ◐ desktop app, since 15.12 | ○ |

### Where they beat us

- **Sharing.** Vikunja shares projects with users, teams and links; Nextcloud shares
  through its calendars; Tasks.org Cloud has family lists. We have no sharing UI — the
  workspace model exists, the screens do not.
- **CalDAV.** Three of the four serve tasks over it, so any CalDAV client works with them.
  Ours writes calendar events to an iCloud or CalDAV calendar ([CALDAV.md](CALDAV.md)), but a
  CalDAV task client (DAVx⁵, Thunderbird) cannot read AllisWell's tasks yet.
- **Trying before installing.** Vikunja has a public demo and Super Productivity runs in
  the browser without an account. We have neither.
- **Importers.** Vikunja imports from seven sources. We read two (Todoist and TickTick, a
  wizard in Settings › Data plus the same call in the API) and a bulk JSON import.
- **Time tracking and issue trackers** — Super Productivity's whole reason to exist.
- **Location reminders and no account** — Tasks.org.
- **Maturity and community.** 700 to 23,000 stars and eight to thirteen years each,
  against our 21 stars and three months. They have met edge cases we have not.

### Where we win

- **Alarms, not notifications** — ring through Silent mode (iOS 26 AlarmKit, Android's
  alarm channel), re-alert until acknowledged, and log why when they could not (§4.2).
- **Two-way Google Calendar**, done by the server, so it works with every device off.
- **Native store apps on iPhone and Android** from the same codebase as the web and
  desktop, on a **local-first** replica that works offline.
- **Recurrence that clamps** the 31st to month end and previews the next five dates.
- **An MCP connector that signs in with OAuth** and has **no delete tool**, by design
  (ADR-0022).
- **Accent-insensitive search** and a **markdown workspace** that edits `.md` files in
  place.

### Licence, honestly

All four are open source under OSI licences (AGPL, MIT, GPL). AllisWell is
**source-available** under PolyForm Noncommercial: free for personal use and
self-hosting, not for a company running it — see the
[README](../README.md#-licence--commercial-use) and
[ADR-0024](adr/0024-license-polyform-noncommercial.md). If an OSI licence is a
requirement for you, the four above are the honest answer.
