# AllisWell vs. the field

A working document, not marketing copy. It exists so that every claim on the
README, the landing page and the store listings can be traced to something the
code actually does — and so the places where a competitor is genuinely better
are written down instead of quietly avoided.

Researched and written against **v1.4.0** (2026-08-12) — that is provenance, not
our current version; the live figure is in the table at §5. <!-- docs-check-ignore -->
Competitor behaviour is stated as of mid-2026; re-check before a release cycle,
because half of it changes yearly.

**Contents:** [1. What we built](#1-what-we-built-the-full-inventory) ·
[2. The field](#2-the-field) · [3. Feature matrix](#3-feature-matrix) ·
[4. The seven real differences](#4-the-seven-real-differences) ·
[5. Where they beat us](#5-where-they-beat-us-honestly) ·
[6. Positioning](#6-positioning)

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
| **"Magic parse"** in quick-add — plain text becomes a dated, tagged, projected task                        | OPH-222     |
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
| Subtasks (real parent/child rows, with cascade)                                               | Epic 04     |
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

### Notes & files

| Feature                                                                             | Shipped |
| ------------------------------------------------------------------------------------- | ------- |
| Markdown notes (GFM), Apple-Notes-style in-document H1 title                         | Epic 05 |
| Pin, archive, card grid or list, Markdown export                                     | Epic 05 |
| Inline images and video inside notes (`alliswell://file/{id}` embeds)                | OPH-156 |
| Attachments on tasks, notes and projects                                             | Epic 14 |
| A workspace-wide **Files** section with nestable folders (≤ 10 deep)                 | OPH-169/170 |
| Storage is **Cloudflare R2 / any S3 via presigned URLs** — bytes never touch the API | Epic 14 |
| **Markdown workspace** — GFM rendering (tables, callouts, footnotes, maths, Mermaid), three modes, outline/folding/find, command palette | OPH-246…250 |
| **Open a `.md` from your computer, edit it and save it BACK to that file** — marked, never autosaved, conflict-aware | OPH-251 (ADR-0030) |

### Calendar

| Feature                                                                                       | Shipped |
| ----------------------------------------------------------------------------------------------- | ------- |
| **Two-way Google Calendar sync** — OAuth, encrypted tokens, push webhooks, incremental sync, etag conflict resolution | Epic 08 |
| Your own Google events flow **back into Home**, next to your tasks                             | OPH-083 |
| Apple Calendar via an **EventKit** bridge                                                     | Epic 08 |
| **Every task is on the calendar — and it is not a setting.** The mirror stopped being a toggle | OPH-210 |
| CalDAV — designed, parked for v2                                                              | CALDAV.md |

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

Legend: ● full · ◐ partial / with caveats · ○ none.

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
| Subtasks · checklists | ● ● | ○ ○ | ◐ 1 level ○ | ● ○ | ○ ○ | ● ● |
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
| Apple Calendar | ● EventKit | ◐ | ○ | native | native | ◐ read-only |
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
one is a thing a competitor **cannot** do, not merely hasn't yet.

1. **It's yours.** The source is public, one `docker compose up`, your own MySQL on your own
   machine at your own domain. Nobody on this page offers that at any price.
2. **Alarms, not notifications.** A reminder that rings through Silent mode and
   Focus, keeps re-alerting until you acknowledge it, and writes a log entry
   explaining itself when it doesn't. Reminders can be "time sensitive"; only an
   alarm gets you out of a meeting.
3. **Recurrence that doesn't lie.** "The 31st" means month end. Google Calendar
   drops February; we clamp to the 28th, show you the next five days before you
   commit, and materialise 12 months of real rows so the calendar, the search and
   the widget all agree.
4. **True two-way calendar sync — in both directions, to two ecosystems.** Not
   an ICS subscription, not read-only import: your tasks become events, edits in
   Google come back, and your Google events appear on Home. Things 3 reads your
   calendar; it never writes to it.
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
| **Natural-language date entry, everywhere** | Todoist, Things 3 | Partial: magic-parse exists in quick-add, and it currently leans on AI. |
| **Real collaboration** — assignees, comments, shared lists | Todoist, Apple Reminders, Google | Workspaces exist in the model; the sharing UI is not built. Single-user today. |
| **Maturity** — a decade of edge cases, App Store trust, an ecosystem | all of them | We are at 1.9.0. This is a young product. |
| **Ecosystem reach** — Siri, Gmail side panel, Watch complications | Apple, Google | Widgets ship; Siri/Watch integration is designed (OPH-183), not delivered. |
| **Design polish over years** | Things 3 | We took their model and our own design system is strict — but they have had ten years to sand the corners. |
| **Localisation breadth** | all of them | Two languages. Adding one is a JSON file, which is the point, but the file has to be written. |

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

1. **"Your data, your server."** The only self-hostable product in this
   comparison.
2. **"Reminders that actually wake you up."** The single most concrete daily
   benefit, and the hardest to copy.
3. **"Add it to Claude or ChatGPT."** Nobody else in this category has it.
4. **"One app on all six platforms."** The answer to "I'm on Android and my
   partner is on iPhone."
5. **"Free, forever, for you."** Not a trial, not a freemium cap — free for
   personal use and self-hosting, with commercial licensing for businesses.

**What we do not claim:** that we are more mature than Things 3, that we
collaborate like Todoist, or that we replace Google Calendar's meeting
machinery. Those lines are in §5 for a reason — see also
[docs/STORE-LISTING.md §5 Claim guardrails](STORE-LISTING.md#5-claim-guardrails).
