# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

## [Unreleased]

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
