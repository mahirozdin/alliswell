# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- **Files are fully readable, synced and cleaned up** (OPH-152, Epic 14): every
  device now learns about attachments through normal sync (metadata only — the
  bytes stay in storage and download links are minted fresh on demand, with the
  file's current name, Turkish characters intact). A project can list ALL of its
  files — its own plus its tasks' and notes' — each row saying where it came
  from. Files can be renamed (the stored object never moves). And deleting a
  task (subtree included), note or project deletes its files everywhere: other
  devices drop them on the next sync and the storage objects are cleaned up in
  the background. Note exports now include embedded images/videos as markdown
  links labeled with the file's name.
- **File uploads live on the API** (OPH-151, Epic 14): the full attachment
  lifecycle — declare a file on a project/task/note, PUT the bytes straight to
  storage with a presigned URL, and a verification step that only publishes
  files whose bytes actually match what was declared (liars get deleted).
  Abandoned uploads are swept after 24 h; deleting a file queues the object
  cleanup with retries so nothing orphans in the bucket.
- **File attachments are coming — storage foundation shipped** (OPH-150, Epic 14):
  the API can now talk to Cloudflare R2 (or any S3-compatible store — MinIO ships
  in docker-compose for local dev/CI). Bytes will never pass through the API
  server: it mints short-lived presigned upload/download URLs instead. Fully
  optional — without `STORAGE_S3_*` config everything answers honestly that
  storage is off. `GET /api/v1/storage` reports availability + limits to the app.
  Full design (incl. the R2 CORS setup web browsers need):
  [docs/ATTACHMENTS.md](docs/ATTACHMENTS.md).

- **Urgent tasks now alarm at their deadline** (OPH-138, Epic 13): an urgent
  task with a due time rings AT that time even if you never set a separate
  reminder — the deadline itself is the alarm (an explicit "Remind" time still
  wins when you set one). Works offline too: the device arms the alarm straight
  from the task and hands over to the synced reminder seamlessly.
- **Urgent alarms actually sound like alarms** (OPH-139, Epic 13): a real 28-second
  alarm ring (not the default ding) that repeats at +2/+5/+10/+30 minutes until
  acknowledged. On iPhone, alarms and reminders are now **Time Sensitive** — they
  break through Sleep and Focus modes (the old level was silently buried by any
  Focus). On Android the alarm plays on the **alarm channel**: it rings at alarm
  volume even when the ringer is muted, gets through default Do Not Disturb, and
  loops until you open it. A Critical-Alerts path (rings even on a muted iPhone)
  ships ready behind Apple's special approval — and the honest plan for muted
  iPhones is the new iOS 26 AlarmKit task
  ([docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md)).
- **Settings → "Urgent alarms" status row** (OPH-139): plain-language answer to
  "can the alarm actually ring on this device?" — flags notifications being off
  or Android's exact-alarm access missing, and a tap re-runs the permission flow.

- **Home-screen widgets — taking shape** (OPH-130/131/133, Epic 12): the app
  projects your open tasks into a compact, bucketed snapshot (Overdue / No date /
  Today / This week / This month) with a localized date header and publishes it
  through the `home_widget` bridge on every change. The **Android** widget that
  renders it — a scrollable bucketed list with a date header, light/dark — is
  written and compiles; the **iOS** widget (SwiftUI) is written and ready to wire
  up in Xcode ([ios/AllisWellWidget/SETUP.md](apps/app/ios/AllisWellWidget/SETUP.md)).
  Tapping opens the app; in-widget complete/add and the on-device visual pass come
  next. (See [ADR-0010](docs/adr/0010-home-screen-widgets-architecture.md) /
  [docs/WIDGETS.md](docs/WIDGETS.md).)
- **The app is fully bilingual — English + Türkçe** (OPH-122…128, Epic 11 done):
  every screen is now translated — sign-in/sign-up, navigation, Home and the whole
  task surface (bucket headers, locale-aware dates, quick-add, create/detail
  sheets, the Inbox), projects, notes, the Google/Apple calendar cards, the
  onboarding tour, Settings, and error messages. Switch languages in **Settings →
  Language** and the entire interface flips instantly. Bonus: status/priority
  dropdowns show proper names instead of `in_progress`; the picked language is
  saved to your account too (so it can follow you), and on the web the page
  `lang` reflects the active language for screen readers. Adding a new language
  needs no code — drop a JSON file (see
  [CONTRIBUTING](CONTRIBUTING.md#translating-adding-a-language)); a CI check keeps
  the UI free of hardcoded strings.
- **Language picker in Settings** (OPH-121): Settings → **Language** lets you
  pick a language — **System default** (follow the device/browser) or any shipped
  language shown in its own name (English, Türkçe). The choice applies instantly,
  persists across restarts, and the current one is checkmarked.
- **Localization foundation** (OPH-120, Epic 11): the app now has an
  internationalization layer — a small, app-owned synchronous store that reads
  JSON locale files (`assets/i18n/en.json` + `tr.json`), auto-detects the device
  or browser language, falls back to English per key, and rebuilds the UI when
  the language changes. No third-party i18n package. Strings are still English in
  this task; the extraction and the Settings language picker follow. Adding a
  language is dropping a JSON file. (See [ADR-0009](docs/adr/0009-localization-i18n-architecture.md).)
- **First-run onboarding tour** (OPH-111): a spotlight walkthrough of the main
  navigation that starts once for a new device and can be replayed anytime from
  Settings → App tour. Skippable, keyboard/back-friendly, and adapts to the
  phone bottom bar and the desktop rail.
- **Project archiving** (OPH-110): projects can be archived (and unarchived) with
  an optional cascade that also archives their tasks and notes — reminders on
  cascaded tasks deactivate and revive correctly. Archived projects are hidden
  behind an Active/Archived filter and show a banner with an Unarchive action.

### Changed

- **The Inbox is now "Fikirler" in Turkish** (OPH-137): the tab, the task status
  and the tour all follow — and the bottom-bar label no longer wraps when
  selected.
- **Today never looks disabled** (OPH-137): picking a calendar day used to fade
  every other group — including Today and Overdue, which read as "done/inactive".
  Now only future groups dim, and collapsing the calendar clears the day
  selection so an invisible filter can't keep dimming Home.
- Notification texts, action buttons and Android channel names are localized
  (English + Türkçe) — they were Turkish-only before (OPH-139).
- **README notes stay in their project** (OPH-109): creating or editing a
  project's README opens full-screen and returns to the project's Overview
  instead of jumping to the Notes tab, and README notes no longer clutter the
  notes list — a new "READMEs" filter surfaces them on demand.
- **Inbox is now a capture box** (OPH-107): the Inbox is for jotting thoughts
  fast — captures stay OUT of Home until you triage them. Each row offers Plan
  (opens a planning sheet), Convert-to-note, or Delete instead of a completion
  checkbox; giving a capture a date or project promotes it to a real task
  automatically.
- **Clearer status icons** (OPH-105): an open task now shows a pending
  hourglass instead of a bare circle (which collided with the completion
  checkbox); "waiting" takes a pause icon.
- **Project picker everywhere** (OPH-106): the task detail screen gained a
  project dropdown, and the create sheet now explains itself when you have no
  projects yet instead of showing an empty-looking picker.
- **Home rework** (OPH-102/103/104): the task list now spans a **30-day
  horizon** (Today / Tomorrow / This week / Next 30 days) so recurring calendar
  events past a month no longer bury real work; **dateless tasks sit at the top**
  (under Overdue, above Today) and never dim; on phones the **month calendar
  scrolls away with the list** instead of staying pinned; and every task row now
  shows a **colored project badge** with the project's name (its ink is computed
  for legibility on any project color).

### Fixed

- **Feedback round 5** (user testing on web): the onboarding tour now
  spotlights the specific navigation item at each step (it was highlighting the
  whole side rail); the task-row status icon sits consistently at the far right
  with the project badge and flags to its left; the project badge renders as a
  compact pill instead of a stretched bar; and a project's README overview shows
  its title as a heading and refreshes its content after an edit.
- **Web sign-out crash** (OPH-100): signing out on the web build threw a
  `TypeError` because a `204 No Content` response body arrives as an empty
  string on dio-web; the app now type-checks the response and always clears the
  local session even if the server call fails.
- **Mobile create buttons unreachable** (OPH-101): the floating action buttons
  on Home, Projects and Notes were painted behind the glass bottom navigation
  bar and could not be tapped on phones. The FAB is now rendered by the app
  shell so it always sits above the bar. Also fixed a Notes filter-chip row
  that overflowed on narrow screens.

### Planned (docs, 2026-07-17)

- **Epic 10 — feedback round 4** (OPH-100…OPH-111), from the first hands-on user-testing
  session: web sign-out crash fix, FABs unblocked from the glass nav, Home reworked to a
  30-day horizon (Today/Tomorrow/This Week/Next 30 Days, dateless on top, calendar scrolls
  with the list, project badges on rows), clearer status icons, project picker in create +
  detail, tabs returning to their root, README notes kept inside their project (+ a
  READMEs notes filter), Inbox reworked as a true capture box, project archiving with an
  optional cascade, and a first-run onboarding tour. BLUEPRINT §4.2/§4.3/§12.2–§12.7 and
  DESIGN §4 revised to match; details in [docs/TASKS.md](docs/TASKS.md).

## [0.1.0] - 2026-07-16

First release: the MVP is complete through Phase 4 (calendar sync). AllisWell is
a self-hosted, offline-first productivity hub — tasks, projects, notes,
reminders, and two-way Google Calendar sync, across all six Flutter platforms.

### Highlights

- **Accounts & workspaces** — argon2id passwords, 15-minute JWTs with rotating
  refresh tokens and reuse detection; a personal workspace per user.
- **Tasks, projects, notes** — subtasks, checklists, tags, priorities, urgent
  flags and reminders; projects with a README-note overview; Delta-canonical
  notes with FULLTEXT search and markdown export.
- **Offline-first sync** — a local SQLite replica is the source the UI reads;
  writes queue in an outbox and push idempotently with field-level
  last-write-wins; Socket.IO fans changes out live. Works fully offline.
- **Exact reminders** — local notifications scheduled from the replica, snooze
  presets, and urgent alarms that re-alert until acknowledged; a lock-screen
  privacy mode.
- **Calendar sync** — Google (server-side): OAuth, task→event mirror, webhook +
  incremental sync, two-way conflict handling, and your own events flowing back
  into Home and the Calendar tab. Apple (device-side): an EventKit task→event
  mirror. CalDAV is designed (v2).
- **"AllisWell Glass" design system** — hand-tuned light/dark, WCAG-verified in
  both themes.

### Known limitations

- Device passes pending for exact notification delivery and the Apple EventKit
  write round-trip (logic is unit-tested; hardware observation remains).
- macOS desktop build needs a local signing certificate (iOS builds today).
- Web builds keep tokens in memory only (signed out after a reload); the
  httpOnly refresh-cookie flow is planned hardening.
- Single active workspace in the UI (multi-workspace sharing is schema-ready, v2).

### Development log

The detailed, session-by-session record of how 0.1.0 was built follows.

### Added (2026-07-16, OPH-077/078 — Apple Calendar)

- **Your tasks can now mirror into your Apple Calendar** (iOS/macOS), the device-side twin of
  the Google mirror. Turn it on in Settings → Apple Calendar (request access, pick a
  calendar); tasks with "Show in calendar" then appear as `[Task] …` events, kept in step by
  a reconcile that runs in the app itself — Apple has no server API, so the device is the
  worker. One-way in v1 (task → event); the same §7.1 derivation as Google, so a task lands
  at the same time whichever calendar it reaches. Ships as a self-contained Flutter plugin
  package (`alliswell_eventkit`) that wires iOS **and** macOS with no Xcode project surgery.
  Hides itself entirely on non-Apple platforms.

### Fixed (2026-07-16)

- **The OPH-077 Swift plugin shipped empty.** The prior session's `git stash` recovery
  corrupted `AlliswellEventkitPlugin.swift` to zero bytes after the iOS build passed but
  before the commit, so the method channel had no native handler. `flutter analyze` never
  caught it (it does not compile Swift). Restored and re-verified with a real
  `flutter build ios`.

### Added (2026-07-16, OPH-084)

- **Your meetings now sit in Home's chronological list, beside your tasks** — a 10:00 meeting
  above a 16:00 task, in one stream, which is what §12 means by "the single chronological view
  where everything shows". The month grid marks days that carry only a meeting too.
  Two rules keep it honest: a meeting that already happened never lands in **Overdue** (that
  means "you still owe this" — a past meeting is history, not a debt), and an ongoing
  multi-day event belongs to **Today**, once, rather than repeating into every bucket it spans.

### Added (your calendar, in AllisWell — 2026-07-16, OPH-082/083)

- **Google Calendar events now show up in AllisWell** (ADR-0008). Connecting an account used
  to do nothing visible unless you mirrored a task: your meetings were deliberately ignored
  ("none of our business"), which made the Calendar tab a calendar without your calendar in
  it. They now sync into the replica as a read-only entity and appear on the month grid and
  in the day list, offline like everything else. Found by the product lead connecting his
  real account and asking where his events were — the spec never mentioned external events
  at all.
- The data was already in hand: the OPH-075 worker fetched the whole event feed every pass
  and dropped the foreign half. It now keeps it — one extra request per sync, not per event.
- Events are **read-only by construction**: no write path in the store, and absence from the
  push registry is the enforcement. A meeting has no checkbox — you cannot complete a
  wedding, and the row does not pretend otherwise.
- Migrations: `calendar_external_events` + `calendar_accounts.external_sync_token` (server);
  replica schema v3 (`external_events`).

### Added (Epic 08 app side — 2026-07-15, OPH-079…081)

- **You can finally connect Google Calendar from the app.** Settings gains a Calendar card
  (`features/integrations/`): connect (consent opens in a real browser), pick which calendar
  to use, see the account, disconnect. Honest about every state — a server without an OAuth
  client says so plainly rather than erroring (the integration is optional), an account
  Google signed out of asks to be reconnected instead of decaying silently, and a connected
  account with no calendar chosen is amber, not green, because it mirrors nothing yet.
  The API for all of this shipped in OPH-070…076; nothing could reach it until now.
- **Per-task "Show in calendar" toggle** (BLUEPRINT §12) and a **Scheduled row** on the task
  detail. `calendarMirrorEnabled` and `scheduled_*` now flow through the replica (drift
  schema v2 + the project's first `MigrationStrategy`), so a calendar event you drag in
  Google is finally visible in the app — that was OPH-076's whole point.
- [docs/CALDAV.md](docs/CALDAV.md) (OPH-079): the v2 iCloud connector design, written now
  because the decision it documents — asking users for an app-specific password, which is
  unscoped, never expires and cannot be revoked from our side — deserved writing down before
  anyone starts coding. 9 references.
- New dependency: `url_launcher` (opens the OAuth consent page).

### Fixed (app — 2026-07-15)

- **Every failed request retried for ~38 seconds behind a spinner.** Riverpod 3 retries any
  failed provider by default (10×, 200 ms → 6.4 s) and reports `AsyncLoading` while it does,
  so error states were effectively unreachable — including errors no retry can fix. Found by
  driving the real app: a dead Google credential was asked eleven times and the user never
  saw the message. `core/retry.dart` now retries only what a retry could fix (not reaching
  the server); everything else surfaces immediately. Affected every `FutureProvider` in the
  app.
- `desiredEventForTask` could derive a backwards calendar block from a `scheduled_end_at`
  left behind by a moved start — Google rejects `end <= start` with a 400 the mirror queue
  could never retry away. It now falls back to the default 30-minute slot.

### Added (Epic 08 inbound — 2026-07-15, OPH-074…076)

- **Google Calendar changes now flow back into tasks** (ADR-0007, BLUEPRINT §7.2 steps 6-10).
  `POST /api/v1/integrations/google/webhook` receives Google's push notifications, gated by
  the channel token it echoes back — minted by us, stored only as an HMAC, compared in
  constant time (`401 GOOGLE_WEBHOOK_INVALID_TOKEN` for a forged one; `200` for an unknown
  channel so Google stops retrying; the `sync` handshake marks nothing dirty). Notifications
  mark the account dirty and hand off to a queue.
- **Incremental sync worker** (`src/plugins/calendar-sync.js`): `syncToken` fetch with
  pagination, full resync on `410`, compare-and-clear of the dirty marker so a notification
  arriving mid-sync keeps its own pass. Channels are renewed a day before they lapse — the
  replacement goes live before the old one is stopped, so no change slips through the gap.
- **Two-way conflict handling** (`src/lib/inbound.js`, a pure decision function): our own
  writes are recognised by etag and ignored (this is what stops mirror ⇄ sync from looping);
  a foreign move lands on the task's `scheduled_*` fields; disagreements are recorded in
  `calendar_event_links.conflict_status`. Deleting our event in Google now **stops mirroring
  that task** instead of resurrecting the event or deleting the task; a recurring series or
  unusable times are flagged `time_conflict` and neither side is touched; both-changed races
  resolve by §6.5 last-write-wins. All-day events map to midnight in the task's timezone.
- `GOOGLE_WEBHOOK_URL` (optional — Google requires public HTTPS), `CALENDAR_WATCH_TTL_SEC`,
  `CALENDAR_SYNC_SWEEP_SEC`. **Without a public webhook address inbound sync still works**:
  the sweep polls those accounts instead, so localhost/NAT self-hosters are not left out.
- Migration `20260715180000_add_calendar_webhook_state`: `webhook_channel_token_hash`,
  `sync_dirty_at`, a unique index on `webhook_channel_id` and one on `webhook_expires_at`.

### Fixed

- **Two AllisWell deployments sharing one Redis consumed each other's queue jobs.** Both
  used the default BullMQ keyspace (`bull:calendar-mirror`), so a job could be executed by
  the wrong instance — which, having its own MySQL, found no such task and dropped the job
  silently: the calendar simply never updated. The keyspace is now namespaced per
  deployment (`REDIS_KEY_PREFIX`, default `alliswell`). Surfaced as a flaky integration
  suite once a second queue-driven test file existed.

### Changed (design round 1 — 2026-07-15)

- **"AllisWell Glass" design system** (ADR-0005, spec in `docs/DESIGN.md`, binding via
  AGENTS.md hard rule 11): full visual refresh of every screen. Liquid-Glass-inspired but
  UX-first — frosted-glass navigation chrome over a static aurora wash, while all content,
  forms and sheets stay on solid, WCAG-verified surfaces (text ≥ 4.5:1, icons/borders ≥ 3:1
  in BOTH themes; guard script `scripts/design/contrast.py`).
- Hand-tuned light/dark `ColorScheme`s + `AwTokens` design tokens replace the default
  `fromSeed` theme; components (inputs, buttons, cards, sheets, dialogs, chips, nav, snackbar,
  pickers) are themed centrally. Lists became rounded card rows; checkboxes are circular;
  sheets gained drag handles and width caps on desktop.
- **Accessibility/UX fixes shipped with the restyle:** priority flags and favorite/pin stars
  now use per-theme colors with ≥ 3:1 contrast (old amber-on-white was ~2:1); inputs always
  show a visible border + 2 px focus ring; password fields gained show/hide toggles; form
  errors render as icon + text banners (never color-only); overdue dates are flagged in red
  with the word "Overdue"; empty/error states are shared widgets with a Retry path; all
  icon actions have ≥ 44 px targets and tooltips.
- App test contract updated with the redesign: `taskPriorityColor(priority, brightness)`
  (hues fixed, lightness per theme) and scroll-aware widget-test finders.

### Fixed (feedback round 3 — 2026-07-15)

- **Web task edits never saved:** the API's CORS preflight only allowed GET/HEAD/POST, so
  every browser PATCH/PUT/DELETE (e.g. setting a due date) was blocked. All verbs are now
  allowed and covered by a regression test; failed writes in the app also surface as
  snackbars instead of silent console errors.

### Changed (feedback round 3 — 2026-07-15)

- **Task titles edit in place:** the detail screen title is a text field with debounced
  autosave.
- **Standard task visuals:** statuses show icons, priorities show colors (low=green,
  medium=amber, high=orange, urgent=red) — on list rows (colored flag + status icon) and in
  every status/priority dropdown; project pickers show the project's color dot before its
  name.

### Changed (feedback round 2 — 2026-07-15)

- **Home task entry:** a rapid-entry quick-add sits above the list — Enter clears the field
  and keeps focus so entries chain (type→Enter→type→Enter); with a calendar day selected the
  task lands on that day, otherwise dateless. A bottom-right FAB opens the full creation
  sheet (due/remind date-times, priority, project, urgent), prefilled with the selected day.
  Inbox and project quick-adds gained the same keep-focus behavior.

### Changed (feedback round 1 — 2026-07-14)

- **Home replaces Today/Upcoming:** the app opens on a Home dashboard — chronological task
  groups (overdue, today, tomorrow, this week, later, no date) beside an Apple-style month
  calendar; picking a day highlights its tasks and dims the rest. On phones the calendar
  collapses behind a persisted toggle. A dedicated Calendar tab shows the month + selected day.
- **Web sessions persist:** reloading the web app no longer signs you out (localStorage-backed
  session storage; httpOnly refresh-cookie flow remains planned hardening).
- **Projects:** Overview now opens on the project's README note (GitHub style,
  `readmeNoteId`); color picking is palette-only (hex codes hidden from end users, full color
  grid dialog); Tasks/Notes tabs are live lists with in-place quick adds.
- **Notes:** list ↔ A4-card grid views (persisted), edited/created dates + linked project in
  rows, one-tap star pinning, archive actions + Archive view, and the note title now renders
  as the document's fixed H1 first block (markdown exports lead with `# title`).

### Added

- Google Calendar — outbound mirroring (OPH-070…073, ADR-0006): connect a Google account
  over OAuth (offline access; tokens AES-256-GCM-encrypted at rest under
  `CALENDAR_TOKEN_KEY`, revoked and wiped on disconnect), pick a default calendar, and
  tasks opted in via `calendarMirrorEnabled` appear as `[Task] …` events — scheduled
  blocks verbatim, otherwise a 30-minute due/urgent-reminder slot. Every committed task
  write flows through a BullMQ queue (exponential-backoff retries; a deterministic inline
  runner without Redis) and converges the event: edits patch it, completing/cancelling/
  archiving/deleting removes it, reopening recreates it. Events carry the ADR-0003
  extended properties, and the worker re-links to an existing event instead of
  duplicating after a lost mapping row. The integration is optional
  (`GOOGLE_NOT_CONFIGURED` without credentials); mocked-Google tests cover the whole
  surface, plus a real-Redis BullMQ integration pass. Inbound sync (webhooks, incremental
  pulls, two-way conflicts) is next (OPH-074…076).
- Notifications (OPH-061…064) — Epic 07's client+server core: reminders now become real
  OS notifications scheduled from the local replica, exactly on time — urgent alarms ride
  Android's alarm-clock mode (never deferred, Doze-exempt) and iOS's time-sensitive
  interruption level, with a pre-scheduled re-alert chain (T, +2 m, +5 m, +10 m, +30 m)
  that keeps ringing until acknowledged on ANY device. Notification buttons complete,
  snooze (5 m/30 m/1 h/tomorrow) and acknowledge straight from the lock screen — all
  offline-safe outbox writes; the sync push gained `task.snoozedUntil` (snoozes the alarm
  in the same transaction, REST-parity) and a narrow `reminder {status: acknowledged}`
  mutation, plus `POST /api/v1/reminders/:id/acknowledge`. A new "Private notifications"
  setting hides task titles from the lock screen entirely. Exact-delivery behavior awaits
  a device verification pass (logic is fully unit-tested; see docs/NOTIFICATIONS.md).
- Live sync fanout (OPH-057) — Epic 06 complete: a Socket.IO server rides the API's HTTP
  listener; clients authenticate with their access token, join a room per workspace, and
  receive `sync:changed {workspaceId, toRevision}` the moment any write commits (REST and
  offline push batches alike, coalesced per workspace; Redis adapter fans out across API
  instances). The app opens one socket per session and pulls immediately on a matching
  event — edits from another device now appear within a round-trip, with the 60-second
  periodic pull demoted to a fallback. The socket never carries entity data.
- Notification device registry (OPH-060): `notification_devices` table plus
  `PUT/GET/DELETE /api/v1/notification-devices[/:id]` — registration doubles as a
  heartbeat (idempotent upsert), devices follow account switches, and unregistering is
  always a 204 so sign-out can't fail. Push tokens are optional: v1 notifications are
  local. Ships with [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) — the researched,
  11-reference plan for exactly-on-time urgent delivery (Android `setAlarmClock` +
  exact-alarm permission flows; iOS time-sensitive interruption level + 64-slot
  scheduling window; pre-scheduled re-alert chains).
- App — local-first (OPH-054…056): the app now reads and writes a local drift/SQLite
  replica of the workspace (native file storage; sqlite-wasm with OPFS/IndexedDB on web)
  and syncs in the background. Every edit lands instantly, works offline, and is queued in
  a durable outbox that pushes in order with exponential backoff; pulls apply batched
  snapshots and tombstones. Server-refused or newer-wins-trimmed writes surface as
  snackbars, and a note edited on two devices at once keeps your version as a
  "(çakışan kopya)" note instead of losing anything. Feature data now streams live from
  the replica everywhere (Home, Inbox, Calendar, Projects, Notes, tags, task detail).
- Sync protocol — server core (OPH-050…053): `GET /api/v1/sync/pull` streams batched,
  per-entity-coalesced snapshots and delete tombstones since a workspace revision;
  `POST /api/v1/sync/push` applies offline mutation batches (project/tag/task/note/checklist
  item) with per-mutation statuses, field-level last-write-wins for metadata — own pushes
  never conflict with themselves (attribution via recorded result revisions) and the newer
  wall clock wins field by field — plus document-level locking for note content
  (`NOTE_CONTENT_CONFLICT`). Full idempotency: every outcome is recorded in
  `client_mutations` (applied ones atomically with the entity write) and replays return the
  original result without re-applying. `withRevision(...)` joins `recordSyncWrite` as the
  blueprint-named transaction helper, with integration proof that concurrent writers produce
  gapless, monotonic revisions.
- Markdown export (OPH-045): `GET /notes/:id/export?format=md` streams the note as
  `text/markdown` (attachment, slugified filename), converted server-side from the canonical
  Quill delta by a converter mirroring the client one fixture-for-fixture — Epic 05 (Notes)
  is complete.
- App — notes (OPH-043, OPH-044): the Notes section is live — searchable (server FULLTEXT)
  list with All/Pinned chips, project detail Notes tab, and a flutter_quill rich-text editor
  with debounced delta autosave, client-side markdown generation with a preview sheet, pin
  and delete actions. New notes are created on their first autosave.
- Project notes (OPH-042): `GET /projects/:id/notes` lists a project's notes — both directly
  attached and link-attached.
- Note links (OPH-041): polymorphic note↔task/project links with workspace validation, and
  `POST /tasks/:id/notes` to spawn a note from a task — inheriting its project and linking
  back automatically.
- Notes API (OPH-040): workspace-scoped note CRUD storing Quill delta JSON as canonical
  content with markdown alongside and server-derived plain text; pinned/archived flags,
  FULLTEXT `?q=` search, cursor pagination and sync revisions.
- App — task screens (OPH-037): Inbox, Today and Upcoming are live lists from the API with a
  context-aware quick-add bar (Inbox captures, Today dues today, Upcoming dues tomorrow);
  checkbox complete/reopen; task detail screen with status/priority, urgent toggle, due/remind
  dates, tag chips and a checklist — completing Epic 04's end-to-end core-domain loop.
- App — project screens (OPH-036): the Projects section is now real — list with colors,
  favorites and status, create/edit bottom sheet with a color palette + free #RRGGBB input,
  and a project detail screen with the Overview/Tasks/Notes tab skeleton. The app resolves
  its current workspace via `GET /me`.
- Task snooze (OPH-035): `POST /tasks/:id/snooze` with an explicit time or the BLUEPRINT
  presets (5 min / 30 min / 1 hour / tomorrow morning — computed at 09:00 on the task's own
  timezone wall clock, DST-safe); task and live reminder snooze together, and unrelated task
  edits no longer wake a snoozed alarm.
- Reminder lifecycle (OPH-034): reminders now live in lockstep with their task inside the same
  transaction — setting `remindAt` schedules (or re-arms) the alarm, clearing it cancels,
  completing the task completes it, reopening re-arms, deleting cancels. Urgent tasks default
  to requiring acknowledgement; timezones are validated (`TASK_INVALID_TIMEZONE`).
- Task transitions (OPH-033): `POST /tasks/:id/complete` (idempotent) and `/reopen` with
  `completed_at` bookkeeping shared with status PATCHes; archived tasks are immutable on every
  write surface (`409 TASK_ARCHIVED`) except a lone unarchiving status change.
- Tasks API (OPH-032): task CRUD with rich filters (status/project/tag/due-range/urgent/parent)
  and ULID-cursor pagination; subtasks with cycle protection and subtree soft delete; checklist
  sub-resource; `PUT /tasks/:id/tags` replace-set semantics. Every write logs a sync revision;
  cross-workspace references are rejected with stable error codes.
- Tags API (OPH-031): workspace-scoped tag CRUD with slugs derived from names
  (Turkish-diacritic aware), per-workspace uniqueness (`409 TAG_SLUG_TAKEN`), slug release on
  soft delete so names can be recreated, and sync-revision logging on every write.
- Projects API (OPH-030): workspace-scoped project CRUD (`/api/v1/workspaces/:id/projects`,
  `/api/v1/projects/:id`) with color/status validation, soft delete (owner/admin), and the
  first building block of the sync engine: `recordSyncWrite()` bumps the workspace revision
  and appends the `sync_revisions` log row inside the same transaction as every entity write.
- App — secure token storage (OPH-025): sessions persist in the platform keystore
  (Keychain / Android Keystore / libsecret / DPAPI) via flutter_secure_storage and restore on
  app start; expired or corrupt blobs are dropped safely; logout wipes storage even offline.
  On web, tokens deliberately stay in memory (httpOnly refresh-cookie flow is the planned
  hardening).
- App — auth layer (OPH-024): dio API client (base URL via `--dart-define=ALLISWELL_API_URL`)
  with an auth interceptor that attaches the access token and transparently refreshes it once
  on a 401; auth repository with single-flight token rotation and forced sign-out when the
  session dies; login/register screens; router now guards the shell (splash while restoring,
  login when signed out) and Settings gained account info + sign out.
- Auth — middleware & `GET /api/v1/me` (OPH-023): `app.authenticate` route guard (JWT
  issuer/audience/expiry; expired tokens answer `AUTH_TOKEN_EXPIRED` so clients refresh instead
  of re-login), `request.user`, and a workspace-membership authorization helper. `GET /api/v1/me`
  returns the profile plus workspaces with roles — closing the Epic 03 acceptance: register,
  then immediately call an authenticated endpoint.
- Auth — refresh rotation & logout (OPH-022): `POST /api/v1/auth/refresh` rotates the opaque
  refresh token inside its family; replaying a retired token answers `401 AUTH_REFRESH_REUSED`
  and revokes the entire family (theft containment), with concurrent rotations settled by an
  atomic claim. `POST /api/v1/auth/logout` revokes the presented token — or the whole family
  with `?all=true` — and always answers 204.
- Auth — login (OPH-021): `POST /api/v1/auth/login` verifies argon2id credentials with a
  timing-safe unknown-email path (dummy verify) and answers `401 AUTH_INVALID_CREDENTIALS`
  without revealing which part failed; every login starts a fresh refresh-token family.
  All `/api/v1/auth/*` routes now share a stricter per-IP rate limit
  (`RATE_LIMIT_AUTH_MAX`, default 10/min vs the global 300/min).
- Auth — registration (OPH-020): `POST /api/v1/auth/register` creates the user, their personal
  workspace and owner membership in one transaction; passwords hashed with argon2id; returns a
  15-minute JWT access token and a 30-day opaque refresh token (stored only as a keyed hash).
  Duplicate emails answer `409 AUTH_EMAIL_TAKEN`. Production now refuses to boot with missing,
  placeholder, short or identical JWT secrets.
- Monorepo skeleton: npm workspaces, `apps/api` (Node.js/Fastify) and `apps/app` (Flutter).
- Project documentation set: `README.md`, `docs/BLUEPRINT.md`, `docs/ARCHITECTURE.md`, `docs/TASKS.md`, `docs/STATE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, ADRs 0001–0004.
- Docker Compose stack: MySQL 8.4 + Redis 8 (+ optional `api` and `adminer` profiles).
- API skeleton (`@alliswell/api`): Fastify 5 (ESM JavaScript), env config loader, request-id logging,
  security plugins (helmet/cors/rate-limit), MySQL (knex) and Redis (ioredis) plugins,
  `/health/live` and `/health/ready` endpoints with JSON-schema responses.
- Knex migration baseline for the full core schema: users, workspaces, workspace_members,
  refresh_tokens, projects, tags, tasks, task_tags, checklist_items, notes, note_tags, note_links,
  sync_revisions, client_mutations, calendar_accounts, calendar_event_links, reminders.
- Flutter multi-platform shell (iOS/Android/Web/macOS/Windows/Linux) with Riverpod + go_router and
  adaptive navigation (rail on desktop, bottom bar on mobile).
- CI pipeline (GitHub Actions): API lint + unit tests + migrations + integration tests against real
  MySQL/Redis services, Flutter analyze + test, TypeScript-ban guard.
