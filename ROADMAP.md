# AllisWell Roadmap

Where AllisWell is and where it's going. Generated from the phase plan in
[BLUEPRINT §14](docs/BLUEPRINT.md) and kept honest against the real state in
[docs/STATE.md](docs/STATE.md) and the backlog in [docs/TASKS.md](docs/TASKS.md).

**Legend:** ✅ shipped · 🟡 partial (rest deferred) · ⏳ planned · 💤 v2 parking lot

> This file is a summary. The authoritative, task-by-task status is
> [docs/TASKS.md](docs/TASKS.md) (epics OPH-001…OPH-136); the live pointer to
> "what's next" is [docs/STATE.md](docs/STATE.md). When they disagree, they win.

---

## v0.1.0 — the MVP (current)

Everything through **Phase 4** is shipped and verified. That is a complete
single-workspace productivity hub: sign in, capture and plan tasks, keep
projects and notes, work fully offline with local-first sync, get exact-time
reminders, and two-way sync your tasks with Google Calendar (plus your own
calendar events flowing back in). See [release notes](#release-history).

### Phase 0 — Foundation ✅

Monorepo (npm workspaces), full docs set, public source, Docker Compose (MySQL 8.4 +
Redis 8), Fastify API skeleton, Flutter 6-platform shell, GitHub Actions CI.
_Epic 01._

### Phase 1 — Core domain ✅

Auth (argon2id, JWT + rotating refresh tokens, reuse detection), workspaces,
projects, tags, tasks (subtasks, checklists, filters, urgent/remind fields,
snooze), and notes (Delta-canonical, FULLTEXT search, markdown export). Flutter
screens for all of it. _Epics 02, 03, 04, 05._

### Phase 2 — Local-first sync ✅

The app reads and writes a local SQLite replica; every write queues in an outbox
and pushes idempotently with field-level last-write-wins conflict resolution;
pulls converge every device; a Socket.IO channel fans changes out within a
round-trip. Offline is the default, not a fallback. _Epic 06._

### Phase 3 — Reminder system ✅

Local notifications on every platform, scheduled from the replica with
content-hash diffing; snooze presets; urgent alarms that demand acknowledgement
with a re-alert chain; a privacy mode that hides task content on the lock
screen. Delivery strategy researched and documented in
[docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md). _Epic 07._

> ⏳ **Device pass pending:** exact-delivery behaviour (Doze, alarm-clock icon,
> Focus break-through) is device-observable only. The logic layer is fully
> unit-tested; a run on real Android + iOS hardware is the remaining step.

### Phase 4 — Calendar sync ✅

- **Google (server-side, always-on):** OAuth with encrypted tokens, task→event
  mirror, push-notification webhook, incremental `syncToken` sync, and a
  two-way conflict policy (etag echo-suppression, foreign edits applied to the
  task, tombstone handling). Your own calendar events flow back into Home and
  the Calendar tab as a read-only entity.
- **Apple (device-side):** an EventKit bridge — permission, calendar list, and
  a task→event mirror that runs in the app (Apple has no server API). One-way
  in v1.
- **CalDAV:** [design doc](docs/CALDAV.md) only (v2 scope).

_Epic 08. ADRs [0006](docs/adr/0006-google-oauth-token-crypto-and-mirror-queue.md),
[0007](docs/adr/0007-google-inbound-sync-and-conflict-policy.md),
[0008](docs/adr/0008-external-calendar-events.md)._

> ⏳ **Device pass pending:** the EventKit write round-trip is device-only.
> **macOS build** needs a local signing certificate (iOS builds today).

---

## v0.1.1 — first user-testing feedback ✅

The first hands-on testing round (2026-07-17, iOS simulator + web) produced
**Epic 10 (OPH-100…OPH-111)**, now shipped: two bug fixes (web sign-out crash,
FABs hidden behind the glass nav), a Home rework (30-day horizon with
Today/Tomorrow/This Week/Next 30 Days, dateless tasks on top, the month
calendar scrolling with the list, project badges on task rows), clearer
status icons, a project picker in task create/detail, tabs that return to
their root, README notes that stay inside their project, an Inbox reworked
as a true capture box, project archiving with an optional cascade, and a
first-run onboarding tour. Spec deltas live in BLUEPRINT §12.2–§12.7 and
DESIGN §4; the tasks in [docs/TASKS.md](docs/TASKS.md).

---

## Toward v0.2.0

### Phase 5 — Rich notes & documents 🟡

Shipped: the flutter_quill editor, Delta storage, client + server markdown
export, and note↔task/project links. _Deferred to v2:_ project documents (a
block editor), richer backlinks, and a global search screen.

### Phase 6 — Polish & public-release readiness 🟡 (in progress)

Shipped: the "AllisWell Glass" design system (light/dark, WCAG-verified,
[ADR-0005](docs/adr/0005-alliswell-glass-design-system.md)), accessibility pass,
CONTRIBUTING / SECURITY / issue + PR templates, **this roadmap**, and
**release automation** (a tagged GitHub Actions release pipeline). ⏳ Remaining:
import/export from other apps, a performance pass, and packaged distribution
(Docker image publish, TestFlight/F-Droid).

### Phase 7 — Localization & widgets ⏳ (planned, feedback round 5)

The second feedback round (2026-07-17) added two features, specced and broken
into tasks (docs only so far):

- **Localization (i18n) — Epic 11 (OPH-120…128).** Strip every hardcoded string
  behind JSON locales (an app-owned synchronous store, no third-party package):
  auto-detect the device/browser language, fall back to English, and let the user
  pin a language from Settings that persists. Ships `en` + `tr`; adding a language
  is dropping a JSON.
  [ADR-0009](docs/adr/0009-localization-i18n-architecture.md), BLUEPRINT §12.9/§15.5.
- **Home-screen / desktop widgets — Epic 12 (OPH-130…136).** iOS/Android/macOS
  widgets in three sizes that mirror Home's buckets in a scroll, carry an
  Apple-Calendar-style date header at the largest size, and offer quick-add +
  tap-to-complete like Apple Reminders — kept in sync via a `home_widget`
  App-Group/SharedPreferences snapshot. Note: a true **4×6 / full-screen widget
  does not exist on iPhone** (WidgetKit's ceiling is 4×4); it is delivered as
  `systemExtraLarge` on iPad/macOS and a real 4×6 on Android.
  [ADR-0010](docs/adr/0010-home-screen-widgets-architecture.md) +
  [docs/WIDGETS.md](docs/WIDGETS.md), BLUEPRINT §12.8/§15.6.

i18n ships first so the widgets are born localized. Native widget targets are
verified by real device builds (the notification/EventKit pattern).

---

## Toward v0.3.0

### Phase 8 — Attachments & project files 🟡 (feedback round 7)

Cloudflare R2 / any S3-compatible store; bytes go client↔bucket via presigned
URLs (the API never proxies them). Shipped: the whole API vertical (storage
plugin + MinIO dev/CI, presigned upload lifecycle with verification + GC
sweeps, pull-only `file` sync entity, delete cascades, rename, markdown-export
embeds) and the app surfaces (task-detail Attachments, the project **Files**
tab with source badges/filters/sort/usage footer, inline note images & videos
with honest offline placeholders). Remaining: the manual device/web QA matrix
(CORS reality pass, big files) — rides the Epic 12/13 device tour. Design:
[docs/ATTACHMENTS.md](docs/ATTACHMENTS.md), ADR-0011.

## Toward v0.4.0

### Phase 9 — Feedback round 8: flow speed, search, board, global files ✅ (code complete 2026-07-20)

Eleven tasks (OPH-160…170), all shipped the same day the round landed:
connecting Google Calendar now auto-selects the primary calendar and syncs
immediately (the hidden second step died — OPH-160); a configurable default
task time (23:59 factory); the Calendar tab retired in favor of a global
**Files** section (folders ≤10 deep with counted recursive deletes, standalone
workspace uploads, a Sources view of every attachment — ADR-0014); inline
"+ Add project" in pickers; editable task descriptions with tappable links;
a typeable tag system (`#chip` input, fold-matched suggestions, auto-create,
manage sheet); **accent-folding local search** ranked title > tag > body across
Home/Notes/Projects (one app-owned fold rather than the database's, because
collations disagree and some get letters outright wrong — parity-fixtured
across Dart and JS, ADR-0013); and a Home **Board**
(kanban) view with user-managed status columns and a mandatory non-drag move
path. Remaining for the release: a live pass with a real Google account and
the standing device-tour matrix.

## Toward v0.5.0

### Phase 10 — Feedback round 9: refresh, date format, the alarm system ⏳ (planned 2026-07-27)

Thirteen tasks (OPH-171…183) from the first round of feedback written by someone
who had actually **used** an alarm. Two halves:

**Flow (OPH-171…174, app-only).** Pull to refresh in all five sections (Home —
list and board —, Ideas, Projects, Notes, Files); on phones Home keeps exactly
one thing pinned, the app bar, so the view toggle and the quick-add field scroll
away with the search field and the calendar instead of squeezing the list; the
detailed create sheet stops misaligning project and priority and opens its date
picker on **tomorrow** (you tap for today, you plan for tomorrow); and every
date in the app comes from one formatter with a user-chosen display format
(31.12.2026 23:59 by default in Turkish) that also reaches the home-screen
widget.

**The alarm backbone v2 (OPH-175…183).** An urgent task's own due time becomes
its own alarm even when a reminder exists (a reminder is a nudge *before* the
deadline, not a replacement for it); one loudness contract — every repeat and
every post-snooze re-ring is as loud as the first, with honest labels; snooze
says what it will do and shows when it will return; a true **indefinite silence**
that never pretends the task is done; a user-owned reminder profile (how many
alerts, how far apart, minimum one minute) behind a "Reminder system settings"
screen that states the OS budget it is spending instead of trimming silently;
a ringtone library with **your own uploaded sound** (installed where each OS can
actually play it); sound in the in-app ring screen at last; a local **alarm log**
so the next report is evidence rather than memory; and the fix behind all of it —
**iOS 26 AlarmKit is finally wired into the build** (the bridge existed since
round 6 but was in no Xcode target, so the one lane designed to ring through
silent mode and Focus had never run), plus a verified answer for Apple Watch.
Design: [ADR-0015](docs/adr/0015-alarm-delivery-and-reminder-profiles.md),
[NOTIFICATIONS.md](docs/NOTIFICATIONS.md) §2b/§5/§6,
[DESIGN.md](docs/DESIGN.md) §15–§18.

## v0.6.0 — feedback round 10 ✅ (code complete 2026-07-29)

### Phase 11 — Feedback round 10: delete, completed work, the widget, transitions ✅

Twelve tasks (OPH-184…195) from the first round of feedback written after living
with the app for a while. The theme of the round is uncomfortable and worth
stating plainly: **most of it was not missing code — it was code nobody could
reach.**

**Delete, and the things like it (OPH-184, OPH-195).** A task could be created,
edited, scheduled, tagged, attached to, mirrored to a calendar and alarmed — and
not deleted. The engine was complete from day one (optimistic local delete,
outbox mutation, server-side subtree tombstone, attachment cascade); the button
was never placed on a row. Round 10 adds **swipe-to-delete** across every list —
the half-open-then-tap idiom, never a single destructive fling — plus a delete
action on task detail, delete in the notes and projects list menus, and an
**Undo** snackbar that works by not committing yet. Then a deliberate CRUD ×
entity audit, because delete is the cell no happy-path demo ever exercises, and
it was not the only one: subtasks, manual ordering and task color are all wired
below the UI and invisible above it.

**Work you finished should look finished (OPH-185, OPH-186).** Completing a task
made it vanish mid-tap. Now it stays in its own group for the rest of the day —
filled circle, struck through, calmly muted (with real tokens, not an opacity
wrapper that would void the contrast floors) — and everything older lives in
**Settings → Completed**: a reverse-chronological, day-headed timeline that pages
as you scroll, sorted by the task's own date when it has one and by its completion
time when it does not.

**The widget grows up (OPH-187, OPH-188, OPH-189).** Its date header was
misaligned on iOS and drawn differently on Android; it now shows **how many open
tasks today actually holds** (overdue + due today) and both platforms draw it the
same. Its circles become buttons that complete a task without opening the app,
riding the App Intent + App Group queue round 9 built for AlarmKit. And tapping
it stops producing `No route for alliswell://open/`: the scheme gets registered,
a tested resolver routes it, `/` becomes a real route, and the router's error
screen becomes ours with a recovery button that works. Contract:
[ADR-0016](docs/adr/0016-in-app-url-routing-and-widget-actions.md).

**Things that were quietly wrong (OPH-190…194).** A sound preview whose stop
button was disabled and which kept playing after you closed the sheet; a date
editor that silently rewrote 14:30 to 23:59 when you changed only the day; a
mysterious third date field ("planned") that exists for calendar drags and now
explains itself only when it applies; a project status dropdown that appeared
only when editing and printed raw English enum values; and the ghost of the
previous screen during navigation — which turned out not to be a performance
problem at all, but this design system's own rule that every scaffold is ~50 %
transparent over a single wash painted below the navigator. Design:
[DESIGN.md](docs/DESIGN.md) §19–§22.

**Shipped 2026-07-29.** Twelve of twelve tasks are code-complete; the one thing a
laptop cannot answer is open and named: **widget interactivity on real hardware**
(OPH-188's device matrix), alongside round 9's still-pending AlarmKit device pass.
OPH-195's audit turned the round's uncomfortable finding into a rule — DESIGN §22:
*a field in the schema, a method on the store or an endpoint on the server is not
a feature until a person can reach it* — and parked subtasks, recurring tasks,
manual ordering and task color with written reasons instead of silence.

## v0.7.0

### Phase 12 — Request round 11 #1: Quick Access ✅ (shipped 2026-07-29, v0.7.0)

Eight tasks (OPH-196…203). A Notion-style **personal** shortcut list — projects,
tasks, notes, folders, files and external links, each with an optional emoji,
color and a hand-picked order — synced to every device as the protocol's **first
user-scoped entity** ([ADR-0018](docs/adr/0018-quick-links-user-scoped-sync-entity.md)):
stored per workspace, pulled only by its owner, capped at 50, and cleaned up
server-side in the same transaction that deletes a link's target. On wide layouts
it lives as a **"Quick access" section of the navigation rail** (collapsible,
hover-and-keyboard row menus, drag to reorder); on narrow rails as a popover
behind a `bolt` icon; on phones as a **draggable floating button** in the
AssistiveTouch idiom — snaps to the nearest edge, half-recedes when idle,
position remembered, hidden behind modals, and never the only way in (a Settings
toggle plus a Home app-bar fallback keep the feature reachable without the
gesture). Internal shortcuts store `kind + target id`, never route strings —
renames survive, and the navigation-only URL rule of
[ADR-0016](docs/adr/0016-in-app-url-routing-and-widget-actions.md) stays intact.
Spec: BLUEPRINT §4.12/§12.15, [DESIGN §23](docs/DESIGN.md).

**Shipped** with two calibrations the build insisted on: the idle dim is the
platform's own 40 % (not a guessed 55 %) and the recede is paint-only so the
56 px target survives, and the colour dot carries its contrast in a 1 px ring
because half the palette cannot clear 3:1 as a bare fill.

## Toward v0.8.0

### Phase 13 — Feedback round 12: recurring tasks, calendar always, flow fixes ✅ (v0.8.0, 2026-07-29)

Eleven tasks (OPH-204…214), slotted between Quick Access and the AI epic at the
owner's request. The headline is **recurring tasks** — the column that sat empty
in the schema since v1 (`repeat_rule`, the biggest item OPH-195 parked) finally
becomes a feature, and a deliberately flexible one: a structured-JSON rule model
on an RFC 5545 subset with RFC 7529 clamping ("the 31st of every month" lands on
the 30th/29th/28th in short months instead of breaking), Nth-weekday patterns
("the 2nd Tuesday"), and after-day patterns ("the first Monday after the 22nd");
a config dialog that opens automatically the first time the Repeat switch turns
on, then lives behind a summary + Change button; a live "next 5" preview computed
by a Dart port of the same engine that materializes on the server (shared parity
fixtures, the search-fold precedent); a **rolling 12-month window** of real task
rows kept fresh by a daily sweep — clients, widgets, search and alarms never
learn what recurrence is; and Google-style edit scopes (this / this-and-future
as the default / all). Design: BLUEPRINT §12.17, ADR-0020 at implementation.
Alongside it: the **calendar mirror loses its opt-in switch** — every dated task
becomes a 30-minute block (23:29–23:59 when it has no explicit time), dateless
tasks land on their creation day, and Google Tasks / Apple Reminders are
evaluated for native todo mapping (BLUEPRINT §7.1 revised, ADR-0021); an overdue
task completed today now leaves the list immediately instead of haunting
"Geciken" (DESIGN §20 C1 revised); the project-edit sheet stops opening under
the popup menu; Home's view and calendar toggles move into the app bar (DESIGN
§16 revised); and the screen-on alarm notification gets its dead snooze button
and tap-to-crash investigated on device.

## Toward v0.9.0

### Phase 14 — Request round 11 #2: AI — MCP connector, BYOK chat, voice capture ✅ (v0.9.0, 2026-07-30)

Thirteen tasks (OPH-215…227; renumbered from OPH-204…216 when round 12 slotted
Epic 19 in between), planned on top of a dedicated max-effort research
pass whose evidence lives in [docs/AI.md](docs/AI.md). The uncomfortable finding
first: the requested "connect your Claude/ChatGPT/Gemini subscription, no API
key" is **not permitted by any provider in mid-2026** (Anthropic bans it, Google
enforces bans, OpenAI gates a preview behind an interest form) — what Cloudflare
and Notion actually ship is the reverse direction. So the epic runs **two
tracks**. Track A: an **AllisWell remote MCP server** — add AllisWell to your own
Claude or ChatGPT as a connector, where your subscription pays for the
intelligence; every self-hosted instance is its own connector URL, and the hosted
instance applies to both directories. Track B: **embedded AI with your own API
key** (Anthropic / OpenAI / Gemini / OpenRouter, plus Ollama for fully-offline
self-hosts; thin fetch adapters, no SDKs —
[ADR-0019](docs/adr/0019-ai-provider-architecture.md)) powering the in-app
surfaces: an SSE-streamed **AI bubble**, a left-side **hold-to-talk FAB**
(lift-to-lock — release your finger and the bubble stays), on-device speech
recognition with live partials (Turkish included), a single JSON-schema **task
extraction** contract ("Ahmet projesine yarın şu iki işi ekle" → a multi-task
confirm card with fold-matched projects and the workspace's default task time),
an OS **share target** that opens any shared text in the bubble, and a
**mandatory confirm card** that commits through the local-first task store —
the AI proposes, the proven write path writes, deletion stays permanently out of
AI reach. Consent screens state each provider's real data policy (including
Gemini's free-tier training, in amber); a red-team injection corpus runs in CI;
the prod deploy checklist proves SSE streams through Apache with a curl. Spec:
BLUEPRINT §4.13/§12.16, [DESIGN §24](docs/DESIGN.md), [docs/AI.md](docs/AI.md).

**Shipped in v0.9.0 (2026-07-30).** All thirteen tasks landed: both tracks are
live (remote MCP server behind our own OAuth 2.1; five BYOK adapters), the
bubble/voice/share surfaces commit through the confirm card, and the red-team
corpus runs across extract, chat and MCP. Remaining before the tag are the
device tours (real microphone, the iOS Share Extension's pbxproj wiring, a live
Claude connector run) and the prod SSE curl — queued in [docs/STATE.md](docs/STATE.md).
Directory submissions (Claude Connectors, ChatGPT apps) are drafted in
[docs/store/directories.md](docs/store/directories.md) and await the operator.

## v2 parking lot 💤

Deliberately out of scope for v1 — schema-ready or designed, not built:

- Multi-user workspace sharing & roles UI (the schema already supports members).
- Project documents (block editor); timeline view; smart-list / filter DSL;
  a single global search screen (per-screen search shipped in Phase 9);
  search v2 (FTS5/bm25, server-side fold columns); OG link previews on task
  descriptions; tag merge/usage counts; desktop drag-to-move into folders.
- Attachments v2 (multipart >5 GB, thumbnails, quotas, offline binary cache — v1 shipped in Phase 8); import from Todoist / TickTick / Apple Reminders; ICS export.
- CalDAV connector for iCloud ([design](docs/CALDAV.md)); the inbound half of the Apple mirror.
- Metrics endpoint (Prometheus), audit-log UI, admin panel.
- E2E tests (Patrol / integration_test), web httpOnly refresh-cookie hardening.

---

## Tracking

Day-to-day status lives in the repo, not a separate tool:

- **[docs/STATE.md](docs/STATE.md)** — the live "what's done / what's next" pointer.
- **[docs/TASKS.md](docs/TASKS.md)** — the full backlog, every OPH-xxx task with acceptance notes.
- **[CHANGELOG.md](CHANGELOG.md)** — what changed, per release.

A GitHub Projects board can be layered on top of these if the project grows a
team; for now the markdown files are the single source of truth (and they are
what the AI-agent workflow reads and updates — see the README).

<a id="release-history"></a>
## Release history

See [CHANGELOG.md](CHANGELOG.md). Releases are cut by pushing a `vX.Y.Z` tag,
which runs the full test suite and publishes a GitHub Release automatically.
