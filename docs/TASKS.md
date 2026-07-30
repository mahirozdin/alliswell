# TASKS — AllisWell backlog

> **How to use:** work strictly top-to-bottom. The first unchecked `[ ]` task in the first
> unfinished epic is the **next task**. The current pointer also lives in [STATE.md](STATE.md).
> Rules and workflow: [../AGENTS.md](../AGENTS.md). Spec: [BLUEPRINT.md](BLUEPRINT.md).
>
> When a task is completed: check every box, keep acceptance notes accurate, update STATE.md and
> CHANGELOG.md, commit with the task id in the message.

---

## Epic 01 — Repository Foundation (Phase 0)

### OPH-001 — Create monorepo skeleton ✅

- [x] Root files (.gitignore, .gitattributes, .editorconfig, .nvmrc, package.json workspaces)
- [x] `apps/api` and `apps/app` directories
- [x] `docs/` + `docs/adr/` folders
- [x] AGPL-3.0 license
- [x] `scripts/check-no-ts.sh` policy guard

Acceptance: repo boots locally; `npm install` works at root; README links all docs. ✔

### OPH-002 — Add root docs ✅

- [x] README.md (intro, features, architecture, quickstart, docs index)
- [x] docs/BLUEPRINT.md (full product vision preserved)
- [x] AGENTS.md (agent rules + "do the next task" protocol)
- [x] docs/ARCHITECTURE.md
- [x] docs/TASKS.md (this file) + docs/STATE.md
- [x] CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, CHANGELOG.md
- [x] ADRs 0001–0004

Acceptance: all docs cross-linked from README; blueprint content preserved. ✔

### OPH-003 — Docker Compose with MySQL and Redis ✅

- [x] MySQL 8.4 service with healthcheck + named volume
- [x] Redis 8 service with healthcheck + AOF persistence
- [x] `.env.example` with all variables
- [x] Optional `api` (profile `full`) and `adminer` (profile `tools`) services
- [x] `apps/api/Dockerfile`

Acceptance: `docker compose up -d mysql redis` starts infra; healthchecks go green.
(Verified locally; also exercised by CI service containers on every push.)

### OPH-004 — Backend Fastify app ✅

- [x] `@alliswell/api` workspace package (ESM, JavaScript only)
- [x] `src/config.js` env loader (+ root/local `.env` support)
- [x] `buildApp()` factory (`src/app.js`) + entrypoint with graceful shutdown (`src/server.js`)
- [x] Plugins: helmet, cors, rate-limit, sensible, request-id logging (pino)
- [x] MySQL plugin (knex) + Redis plugin (ioredis) with test overrides
- [x] ESLint (flat) + Prettier + Vitest wiring

Acceptance: `npm run dev` boots without infra (degraded mode); `npm test` green. ✔

### OPH-005 — Backend healthcheck ✅

- [x] `GET /health/live` — process liveness (200 always)
- [x] `GET /health/ready` — MySQL `SELECT 1` + Redis `PING` with timeouts; 503 when degraded
- [x] JSON-schema'd responses; component-level status in payload
- [x] Unit tests (stubbed deps) + integration test (real infra)

Acceptance: ready endpoint reports per-component status; used by compose/CI healthchecks. ✔

### OPH-006 — Flutter app shell ✅

- [x] `flutter create` for ios/android/web/macos/windows/linux (`apps/app`, org `com.alliswell`)
- [x] Riverpod + go_router wired
- [x] Adaptive shell: NavigationRail (wide) / NavigationBar (mobile)
- [x] Placeholder screens: Inbox, Today, Upcoming, Projects, Notes (+ Settings route)
- [x] Light/dark Material 3 theme (seed `#2563EB`)
- [x] Widget smoke test

Acceptance: `flutter analyze` clean; `flutter test` green; app runs on at least one device. ✔

### OPH-007 — CI pipeline ✅

- [x] GitHub Actions workflow: API job (lint, no-TS guard, unit tests, migrations against real
      MySQL, integration tests) with MySQL+Redis service containers
- [x] Flutter job (pub get, analyze, test)
- [x] Concurrency cancellation, npm cache

Acceptance: `ci.yml` runs green on push/PR to main. (Will be exercised on first push.)

---

## Epic 02 — Database (Phase 1)

### OPH-010 — Knex migration setup ✅

- [x] `knexfile.js` reusing `src/config.js`
- [x] Shared `src/db/knexconfig.js` (also used by the runtime plugin)
- [x] npm scripts: `db:migrate`, `db:rollback`, `db:migrate:make`
- [x] Migration conventions documented in AGENTS.md (append-only, ESM up/down)

Acceptance: `npm run db:migrate` runs against compose MySQL; CI runs it on every push. ✔

### OPH-011 — users / workspaces migration ✅

- [x] `users` (per BLUEPRINT §10.1)
- [x] `workspaces` + `workspace_members` (owner/admin/member)
- [x] `refresh_tokens` (rotation-family model, hashed tokens)

### OPH-012 — projects / tags / tasks migration ✅

- [x] `projects` (per §10.2, FK → workspaces)
- [x] `tags` (unique slug per workspace)
- [x] `tasks` (per §10.3 + `sort_order`, `actual_minutes`, `snoozed_until` — ADR-0004)
- [x] `task_tags`, `checklist_items`
- [x] FULLTEXT index on tasks(title, description)

### OPH-013 — notes / note_links migration ✅

- [x] `notes` (per §10.4, Delta JSON + markdown + plain_text)
- [x] `note_tags`, `note_links` (polymorphic)
- [x] FULLTEXT index on notes(title, plain_text)

### OPH-014 — sync_revisions migration ✅

- [x] `sync_revisions` (workspace-scoped monotonic revision log, per §6.2)
- [x] `client_mutations` (idempotency records: unique client_id + client_mutation_id)

### OPH-015 — calendar tables migration ✅

- [x] `calendar_accounts` (encrypted token columns, sync/webhook state)
- [x] `calendar_event_links` (provider mapping, etag, conflict_status)
- [x] `reminders` (alarm lifecycle: delivered/acknowledged/snoozed, per §4.9)

Epic 02 acceptance: all migrations apply cleanly to a fresh MySQL 8.4 (`db:migrate`) and roll
back (`db:rollback --all`); integration test asserts the migration set is applied. ✔

---

## Epic 03 — Auth (Phase 1)

### OPH-020 — Register endpoint ✅

- [x] `POST /api/v1/auth/register` (email, password ≥ 8, displayName?) with Ajv schema
- [x] argon2id password hashing
- [x] Create user + personal workspace (`{name}'s Space`, slug, owner member row) in one transaction
- [x] Return access token (JWT, 15 min) + refresh token (opaque, 30 days, stored hashed)
- [x] Error codes: `AUTH_EMAIL_TAKEN`, validation errors
- [x] Unit + integration tests (duplicate email, weak password, happy path)

Acceptance: new user can register and immediately call an authenticated endpoint.
(_Closed in OPH-023: the integration suite registers and immediately calls `GET /me`._)

### OPH-021 — Login endpoint ✅

- [x] `POST /api/v1/auth/login` — argon2 verify, timing-safe failure path
- [x] Same token pair response shape as register
- [x] Error `AUTH_INVALID_CREDENTIALS` (no user/pass distinction)
- [x] Rate limit tighter than global (`RATE_LIMIT_AUTH_MAX`, default 10/min/IP, all auth routes)
- [x] Tests: wrong password, unknown email, happy path (+ soft-deleted user, rate limit trip)

### OPH-022 — Refresh token rotation ✅

- [x] `POST /api/v1/auth/refresh` — rotate: old token retired (`rotated_at`), same family id
- [x] Reuse detection: refresh with a rotated/revoked token revokes the whole family
      (`AUTH_REFRESH_REUSED`); concurrent rotations settled by an atomic claim UPDATE
- [x] `POST /api/v1/auth/logout` — revoke current token (and `?all=true` for family); always
      204 (idempotent, no validity oracle)
- [x] Tests: rotation chain, reuse attack, expiry (+ soft-deleted user, unknown token)

### OPH-023 — Auth middleware / plugin ✅

- [x] `app.authenticate` decorator verifying JWT (issuer/audience/exp; expiry gets its own
      `AUTH_TOKEN_EXPIRED` code so clients know to refresh)
- [x] `request.user` (`{ id, email }` via formatUser) + `app.requireWorkspaceMember(request,
      workspaceId, { roles })` authorization helper (403 `AUTH_WORKSPACE_FORBIDDEN`)
- [x] `GET /api/v1/me` returning profile + workspaces (batched queries, no N+1)
- [x] Tests: missing/expired/garbage/forged token, deleted user, membership + role check

### OPH-024 — Flutter auth repository ✅

- [x] dio API client with base URL config (`--dart-define=ALLISWELL_API_URL`) + auth
      interceptor (token attach, single retry with refresh-on-401, QueuedInterceptor)
- [x] Auth repository (register/login/refresh/logout, single-flight rotation, session
      change stream) + Riverpod providers (`authControllerProvider`, `apiClientProvider`)
- [x] Login & register screens wired to shell — go_router redirect: `/splash` while
      restoring, `/login`+`/register` when signed out; Settings shows account + sign out
- [x] Widget/unit tests with mocked dio (fake HttpClientAdapter, no sockets)

### OPH-025 — Secure token storage ✅

- [x] flutter_secure_storage for tokens (Keychain/Keystore/libsecret/DPAPI). Web —
      _amended in feedback round 1 (2026-07-14):_ sessions persist in localStorage via
      shared_preferences so reloads keep you signed in (product decision; XSS trade-off
      accepted for self-hosted v1, httpOnly refresh-cookie flow stays as future hardening)
- [x] Session restore on app start (expired refresh tokens dropped eagerly); logout clears
      storage even when offline
- [x] Tests for storage wrapper (round-trip, corrupt/incompatible blob recovery, keystore
      delegation via plugin mock)

Epic 03 acceptance: register from a fresh app → authenticated `GET /me` immediately; session
survives restart (mobile/desktop); refresh rotation transparent on 401; reuse burns the family. ✔

---

## Epic 04 — Projects / Tags / Tasks (Phase 1)

### OPH-030 — Project CRUD API ✅

- [x] `GET/POST /api/v1/workspaces/:wsId/projects`, `GET/PATCH/DELETE /api/v1/projects/:id`
- [x] RGB color validation (`#RRGGBB`), status enum, favorite, sort_order (list ordered by
      sort_order, `?status=` filter)
- [x] Soft delete (owner/admin only — members create/edit); workspace authorization on
      every route
- [x] Revision bump + `sync_revisions` row on every write — `recordSyncWrite()` transaction
      helper in `src/db/sync.js` (workspace row lock serializes writers; entity row gets the
      returned revision stamped)
- [x] Tests: CRUD, authz cross-workspace denial, validation, sync-log invariants

### OPH-031 — Tag CRUD API ✅

- [x] CRUD under workspace; unique slug per workspace (slugify helper; slug follows renames;
      soft delete rewrites the slug to `…--deleted--…` so the name can be recreated)
- [x] Tests incl. duplicate slug conflict (`409 TAG_SLUG_TAKEN`, case/diacritic-insensitive)

### OPH-032 — Task CRUD API ✅

- [x] Create/list (filters: status multi, projectId, tag, due range, urgent, parentTaskId;
      ULID-cursor pagination, newest first) / get / patch / soft-delete (subtree cascade,
      one sync row per task)
- [x] Checklist items sub-resource (`/tasks/:id/checklist[/:itemId]`, task-scoped);
      parent_task_id subtasks with cycle guard (`TASK_PARENT_CYCLE`)
- [x] Tag attach/detach (`PUT /tasks/:id/tags`, replace-set diff; no-op costs no revision)
- [x] Revision + sync_revisions on writes; cross-workspace reference guards
      (`TASK_INVALID_PROJECT` / `TASK_INVALID_PARENT` / `TASK_INVALID_TAG`)
- [x] Tests: filters, pagination, subtask nesting, tag ops (unit + real-MySQL integration)

### OPH-033 — Task status & priority transitions ✅

- [x] `POST /tasks/:id/complete` (idempotent, no revision on no-op) / `reopen` (only from
      completed/cancelled → `TASK_INVALID_TRANSITION` otherwise); completed_at maintained by
      both endpoints AND status PATCHes
- [x] Status transition validation: archived tasks immutable across PATCH/tags/checklist/
      transitions (`409 TASK_ARCHIVED`) — the only allowed write is a lone unarchiving
      `PATCH { status }`; soft delete stays allowed (cleanup)
- [x] Tests

### OPH-034 — Task urgent / remind fields ✅

- [x] Validation: timezone validity enforced via Intl whenever provided (`TASK_INVALID_TIMEZONE`;
      the column default guarantees presence for remind_at); urgent implies
      requires_acknowledgement default (create AND patch, explicit opt-out respected)
- [x] Reminder row lifecycle sync with task writes, same transaction
      (`src/db/reminders.js` reconcile): remind_at set → scheduled upsert (re-arm in place);
      cleared → cancelled; task completed → completed; reopened with remind_at → re-armed;
      deleted → cancelled; urgency/timezone/repeat mirrored; no-op writes cost no revision
- [x] Tests (unit + real-MySQL integration)

### OPH-035 — Task snooze endpoint ✅

- [x] `POST /api/v1/tasks/:id/snooze` (`snoozeUntil` XOR preset
      `5_min|30_min|1_hour|tomorrow_morning`; past times → `TASK_SNOOZE_IN_PAST`;
      completed/cancelled → `TASK_INVALID_TRANSITION`)
- [x] Updates task.snoozed_until + the active reminder's snoozed_until/status in one
      transaction; unrelated task patches now PRESERVE a snooze (reconcile fix) while a
      moved remind_at still re-arms
- [x] Tests incl. preset math in user timezone (`src/lib/time.js` — DST-safe wall-clock→UTC)

### OPH-036 — Flutter project screens ✅

- [x] Projects list (color dot, favorite toggle, non-active status) + create/edit bottom
      sheet with palette + free #RRGGBB input (status dropdown in edit mode)
- [x] Project detail tabs skeleton (Overview/Tasks/Notes) + edit/delete actions;
      route `/projects/:projectId` inside the shell branch
- [x] Riverpod data layer hitting the API (`workspacesProvider` via `GET /me` picks the
      current workspace; `ProjectsController` re-fetches after mutations); widget + unit
      tests over a stateful fake API adapter

### OPH-037 — Flutter task screens ✅

- [x] Inbox/Today/Upcoming lists from the API (shared `TaskListScreen`; Today = open statuses
      due up to end-of-day incl. overdue, Upcoming = from tomorrow); quick-add bar per list
      (Inbox → status inbox, Today → due today, Upcoming → due tomorrow 09:00)
- [x] Task detail (`/tasks/:id` pushed over the shell): status/priority dropdowns, urgent
      toggle, due/remind date rows, tag FilterChips (PUT replace-set), checklist
      add/toggle/remove — every control writes to the API and re-fetches
- [x] Tests: per-section list filtering, quick-add, checkbox complete drop-off, detail edits
      (urgent/tags/checklist) over the stateful fake API; TasksApi query-building unit tests

Epic 04 acceptance: the core-domain loop works end to end — register → create projects/tags →
capture tasks in Inbox → plan Today/Upcoming → edit detail (tags, checklist, urgent) →
complete/reopen — against the real API contract (fake adapter in widget tests, real MySQL in
API integration tests). ✔

_Amended in feedback round 1 (2026-07-14): Today/Upcoming tabs were replaced by the Home
dashboard (chronological groups + Apple-style month calendar, day selection highlight/dim,
collapsible on mobile with a persisted preference) and a dedicated Calendar tab. Projects
gained a README-note Overview (`readme_note_id`), palette-only color picking (no hex for end
users) and in-tab quick adds for tasks/notes. See BLUEPRINT §12._

---

## Epic 05 — Notes (Phase 1)

### OPH-040 — Note CRUD API ✅

- [x] CRUD with content_delta (JSON, structurally validated → `NOTE_INVALID_DELTA`),
      content_markdown, plain_text extraction server-side (`src/lib/delta.js`)
- [x] Pinned/archived flags (list hides archived unless `includeArchived`); workspace authz;
      sync revisions on every write; ULID-cursor pagination; `?q=` FULLTEXT search
      (title + plain_text)
- [x] Tests (unit + real-MySQL integration incl. FULLTEXT and JSON round-trip)

### OPH-041 — Note–task link ✅

- [x] `POST /api/v1/notes/:id/links` + `DELETE /notes/:id/links/:linkId` (polymorphic,
      v1: task/project; same-workspace target validation, dup → `NOTE_LINK_EXISTS`,
      note revision bumps on link/unlink)
- [x] "Create note from task" (`POST /tasks/:id/notes`): inherits the task's project,
      defaults the title, records `created_from_task_id` and auto-links back; notes list
      `?taskId=` filter covers both link-based and created-from notes
- [x] Tests

### OPH-042 — Note–project link ✅

- [x] Project notes listing (`GET /projects/:id/notes`) — attached (project_id) ∪
      link-attached notes, archived hidden by default, cursor pagination
- [x] Tests

### OPH-043 — Flutter note list ✅

- [x] All/Pinned chips + server FULLTEXT search box; project notes on the project detail
      Notes tab (attached ∪ linked); task-linked filter available via the API (`?taskId=`)
- [x] Tests (list rendering, pinned/search filtering, project tab) over the stateful fake API

### OPH-044 — Flutter note editor ✅

- [x] flutter_quill 11 editor (headings, bold/italic/strike/code, colors, links, check/bullet/
      ordered lists, code blocks; single-row toolbar)
- [x] Delta autosave (1.5 s debounce; first save creates the note, POST → PATCH after; failed
      saves stay dirty and retry on next edit); markdown generated client-side on every save
      (`data/delta_markdown.dart`) + preview sheet action; pin toggle + delete in the app bar
- [x] Tests: converter fixtures (headers/inline/lists/code fences), editor load, title
      autosave PATCH, create-on-first-save POST

### OPH-045 — Markdown export ✅

- [x] Server-side delta→markdown converter + `GET /notes/:id/export?format=md`
- [x] Tests with fixture deltas

Acceptance: the export streams `text/markdown` (attachment, slugified filename) derived
server-side from the canonical delta — `deltaToMarkdown` in `src/lib/delta.js` mirrors the
client converter fixture-for-fixture; stored `content_markdown` is only the fallback for
delta-less notes. ✔

Epic 05 acceptance: notes work end to end — delta-canonical CRUD + FULLTEXT search,
task/project links, Flutter list + editor with delta autosave, markdown preview (client)
and export (server). ✔

---

## Epic 06 — Sync (Phase 2)

### OPH-050 — Revision generator ✅

- [x] Transaction helper: `withRevision(trx, wsId, entityType, entityId, op, changedFields)`
- [x] Per-workspace monotonic counter (row lock on workspaces.revision)
- [x] Retrofit existing write paths; tests incl. concurrency

Acceptance notes: `recordSyncWrite()` (object args, `src/db/sync.js`) has been the live
implementation since OPH-030 and every write path already used it — `withRevision` is the
blueprint-named positional form of the same function, so no retrofit was required.
Integration test: 12 concurrent transactions produce gapless, duplicate-free revisions
1..12 under the workspace row lock. ✔

### OPH-051 — Sync pull endpoint ✅

- [x] `GET /api/v1/sync/pull?workspaceId&sinceRevision` (batched, `hasMore`)
- [x] Entity snapshots for create/update; tombstones for delete
- [x] Tests

Acceptance notes: revision-ascending windows (default 200, max 500; `limit+1` probes
`hasMore`), coalesced to each entity's LATEST change — snapshots reflect current rows
(tasks embed `tagIds`, notes embed content + links), so intermediate revisions carry
nothing. Any row that is currently soft-deleted (or missing) answers as a tombstone
(`operation: 'delete', data: null`) even when its delete log row lies past the window.
Entity types: project, tag, task, note, checklist_item, reminder. ✔

### OPH-052 — Sync push endpoint ✅

- [x] `POST /api/v1/sync/push` with mutation batch (per BLUEPRINT §6.3)
- [x] Field-level LWW merge for metadata; per-mutation result statuses
- [x] Tests: apply, conflict, invalid entity

Acceptance notes (documented deviations): the body adds a required `workspaceId` beside
§6.3's `clientId`/`baseRevision`/`mutations` (authorization and the `client_mutations` rows
need it). Entity types v1: project, tag, task, note, checklist_item — reminders stay
server-managed. Per-mutation statuses: `applied` / `conflict` / `rejected` plus
`errorCode`, `discardedFields`, `replayed`. LWW: a field conflicts only when a FOREIGN
writer changed it after `baseRevision` (own pushes are attributed through recorded result
revisions and never conflict with themselves); the newer wall clock wins
(`localUpdatedAt` vs server-canonical `updated_at`), losing fields are dropped one by one,
and an all-dropped mutation answers `conflict`/`SYNC_STALE_MUTATION`. Note CONTENT never
merges — document-level lock → `NOTE_CONTENT_CONFLICT` (§6.5), metadata on notes still
LWW-merges. Domain rules ride along: urgent⇒acknowledgement default, `completed_at`
bookkeeping + reminder reconcile in the same transaction, archived immutability (lone
unarchive allowed), tag slug rules (`TAG_SLUG_TAKEN`), task subtree delete cascade, and
the owner/admin role guard on project deletes. Error codes live in `src/routes/sync.js`. ✔

### OPH-053 — Idempotency table usage ✅

- [x] Duplicate `clientMutationId` returns recorded result without re-applying
- [x] Tests: replay batch

Acceptance notes: EVERY outcome (applied and conflict/rejected alike) is recorded in
`client_mutations`; applied rows commit in the SAME transaction as the entity write, so a
crash can never apply without recording. Replays answer from the record (`replayed: true`,
original revision, no re-application); idempotency is scoped per `clientId` (two devices may
reuse a mutation id) and concurrent duplicates settle on the `uq_client_mutation` unique
key. ✔

### OPH-054 — Flutter local DB ✅

- [x] drift schema mirroring server entities + `pending_mutations` outbox table
- [x] Repository layer reads local-first
- [x] Tests

Acceptance notes: `lib/src/sync/db/database.dart` mirrors every synced entity
(projects/tags/tasks + tag joins/checklist_items/notes + links/reminders) plus
`pending_mutations` and a per-workspace `sync_states` cursor (clientId +
lastRevision); timestamps stored as ISO text so DATETIME(3) precision
round-trips. Native platforms open a background-isolate sqlite file
(app-support dir); web uses drift's wasm setup — `web/sqlite3.wasm` +
`web/drift_worker.js` are committed, pinned to the resolved package versions
(bump together with pubspec). Feature stores (`features/*/data/*_store.dart`)
expose drift watch streams; every provider the UI consumed kept its name and
value shape, so screens re-render live from the replica. Client-generated
ULIDs (`core/ulid.dart`) give offline creates their identity. Offline note
search is a substring scan over title+plainText (server FULLTEXT remains
canonical ranking). ✔

### OPH-055 — Flutter outbox ✅

- [x] Mutation enqueue on every local write; background push with retry/backoff
- [x] Tests

Acceptance notes: every store write commits the optimistic row change AND its
outbox row in ONE drift transaction (`sync/outbox.dart`; the row id doubles as
the server `clientMutationId`, so retries stay idempotent end to end).
`SyncEngine` (`sync/sync_engine.dart`) drains the outbox in order (batches of
≤100), applies per-mutation results, then pulls the workspace forward
(coalesced snapshots/tombstones applier in `sync/sync_applier.dart`).
Triggers: debounced poke after every local write, on engine start, and a
periodic fallback pull (60 s — OPH-057's socket will demote it). Failures keep
the outbox intact and retry with exponential backoff (1s→2s→…→60s cap);
`attempts`/`lastError` are recorded on the rows. Widget tests run the full
loop against the FakeApi, which now speaks `/sync/pull` + `/sync/push`. ✔

### OPH-056 — Conflict handling ✅

- [x] Server conflict statuses surfaced; note conflict-copy flow (v1 policy)
- [x] Tests

Acceptance notes: push results other than a clean `applied` (conflict,
rejected, or applied-with-`discardedFields`) emit a `SyncConflict` on the
engine's stream; the shell listens (`syncConflictsProvider`) and shows a
snackbar naming what happened — by then the replica already shows the
server-canonical state via pull. `NOTE_CONTENT_CONFLICT` runs the §6.5 v1
policy client-side: the local content becomes a NEW note titled
"… (çakışan kopya)" whose create is enqueued (nothing typed is ever lost),
while the next pull restores the server content into the original note.
Replayed mutations never re-surface a conflict. ✔

### OPH-057 — WebSocket live update ✅

- [x] Socket.IO server (auth on connect, rooms per workspace) + Redis adapter
- [x] `sync:changed {workspaceId, toRevision}` event on push/API writes → clients pull
- [x] Flutter socket client triggering pull; tests

Acceptance notes: `src/plugins/socket.js` rides the same HTTP listener; the
access token authenticates the handshake (`auth: { token }`) and the socket
joins one room per workspace membership (snapshotted at connect — clients
reconnect to pick up new workspaces; the JWT is verified at connect only,
which is safe because the event carries no data and the pull re-authenticates
over HTTP). `recordSyncWrite` announces AFTER its transaction commits via an
in-process emitter, coalesced per workspace per tick (one event with the top
revision per burst) — so REST writes and sync pushes both fan out. The Redis
adapter attaches when Redis is up (its pub/sub pair connects eagerly and
queues, unlike the fail-fast health-check client); single-node mode
otherwise. App side: `sync_socket.dart` + `syncSocketProvider` — one socket
per session (rebuilt on token rotation, `forceNew`), a matching
`sync:changed` calls `SyncEngine.syncNow()`, and the 60 s periodic pull is
now the fallback. Widget tests drive a captured fake socket (a foreign edit
appears in the UI with no local write); server tests cover auth rejection,
room isolation, burst coalescing and push fanout, plus an integration test
over real MySQL/Redis with the adapter attached. ✔

Epic 06 acceptance: the full BLUEPRINT §6 loop is live — offline edits queue
in the outbox, push idempotently with LWW conflict policy, pulls converge
every replica, and other devices hear about it within a socket round-trip. ✔

---

## Epic 07 — Notifications (Phase 3)

### OPH-060 — Notification device registry ✅ (Very important detail to know: Urgent notifications needs highest priority and exactly-on-time delivery,  so need to make research on the best way to implement this on iOS and Android atleast 5 references to research and implement this)

- [x] `notification_devices` migration + register/unregister endpoints (platform, push token?)
- [x] Research: exactly-on-time, highest-priority delivery on iOS/Android (≥5 references)
- [x] Tests

Acceptance notes: one row per install, keyed by a device-generated ULID (the
app will reuse its sync client id). `PUT /notification-devices/:id` is the
register AND heartbeat (idempotent upsert; 201 on first sight, 200 after;
untouched fields persist; a device signing into another account is taken over
by it). `GET` lists only the caller's devices (last-seen first); `DELETE`
always answers 204 (sign-out must never fail) and cannot touch foreign rows.
`push_token` is optional — v1 notifications are local; not a synced entity.
Unit + real-MySQL integration tests; migration verified
apply→rollback→re-apply.

**Research delivered in [NOTIFICATIONS.md](NOTIFICATIONS.md)** (11 references,
binding plan for OPH-061…064). Headline decisions: Android urgent →
`setAlarmClock` (never deferred, Doze-exempt) + `SCHEDULE_EXACT_ALARM`
runtime flow (denied by default on Android 14) with `USE_EXACT_ALARM` as a
Play-policy option; iOS urgent → `timeSensitive` interruption level +
scheduling window ≤40 of the 64 pending slots; re-alert-until-acknowledged is
a pre-scheduled chain on both platforms (iOS has no background timers);
critical-alerts entitlement is a flagged stretch goal. ✔

### OPH-061 — Local notification scheduling ✅

- [x] flutter_local_notifications setup (all platforms incl. timezone handling)
- [x] Schedule/cancel from task.remind_at via local DB
- [x] Tests where feasible

Acceptance notes (per the binding plan in [NOTIFICATIONS.md](NOTIFICATIONS.md)):
the logic layer is device-free — `notifications/planner.dart` (pure: replica
alarms → desired OS notifications, ≤40-slot window under iOS's 64 cap,
urgent chains) + `notifications/scheduler.dart` (diff desired-vs-pending by
content-hash ids: cancel extras, schedule missing; permission failures
degrade silently). Only `gateway_local.dart` touches the plugin: urgent →
`AndroidScheduleMode.alarmClock` + iOS `timeSensitive`, normal →
`exactAllowWhileIdle` + `.active`; reminders fire on absolute UTC instants
(no wall-clock math client-side — the server owns timezone semantics).
Platform config: manifest permissions + boot/schedule receivers, gradle
desugaring, macOS time-sensitive entitlements (iOS needs the Xcode
capability once a signed project exists — noted in NOTIFICATIONS.md).
CAVEAT: exact-delivery behavior (Doze, alarm icon, Focus breakthrough) is
device-observable only — a device pass is pending (STATE blocked notes);
planner/scheduler/actions logic is fully unit-tested. ✔

### OPH-062 — Snooze actions ✅

- [x] Notification action buttons: complete / 5m / 30m / 1h / tomorrow / custom
- [x] Actions call snooze endpoint when online; enqueue mutation when offline

Acceptance notes: actions route through the local-first stores, so the
checklist's online/offline split collapses into ONE path — `TaskStore.snooze`
moves the task and its alarm locally in a transaction and enqueues a
`snoozedUntil` patch; the sync push now accepts it (update-only field) and
mirrors REST snooze semantics server-side (reminder snoozed/re-armed in the
same transaction; finished tasks → `TASK_INVALID_TRANSITION`; past instants
accepted by design — queued offline actions may land late). Buttons: normal
[Tamamla, 30 dk, 1 saat(+Yarın on iOS)], urgent [Onayla, 5 dk, 30 dk];
"custom" is the tap itself (deep-link to the task detail). v1 actions run
through the main isolate (`showsUserInterface: true`) — the
background-isolate handler is future work (NOTIFICATIONS.md). ✔

### OPH-063 — Urgent notification UX ✅

- [x] Urgent channel: critical sound, requires acknowledgement, re-alert loop until acked
- [x] Acknowledge endpoint wiring (`reminders.acknowledged_at`)

Acceptance notes: urgent+ack alarms pre-schedule the re-alert chain
(T, +2 m, +5 m, +10 m, +30 m — iOS has no background timers, Android shares
the shape; every slot rides `alarmClock`, immune to Doze's allow-while-idle
rate limit) on the dedicated `urgent_alarms` channel (max importance, alarm
category, full-screen intent where granted, `timeSensitive` on Darwin).
Acknowledging cancels the chain everywhere: locally at once (planner drops
the rows → scheduler cancels), other devices via sync. Wiring: local-first
`ReminderStore.acknowledge` → outbox `reminder {status: acknowledged}`
mutation (narrow push entity, update-only) + REST
`POST /api/v1/reminders/:id/acknowledge` (idempotent; silenced alarms →
`REMINDER_INVALID_TRANSITION`). Critical-alert sound bypass stays a flagged
stretch goal (Apple entitlement, NOTIFICATIONS.md §2). ✔

### OPH-064 — Notification privacy mode ✅

- [x] Setting: payloads/notifications show IDs-only vs. title
- [x] Server push payloads always minimal (BLUEPRINT §8.3)

Acceptance notes: Settings gains "Private notifications" (persisted per
device) — when on, every notification renders as "AllisWell / Bir
hatırlatıcın var" with no task content; taps still deep-link by id. The
planner enforces it for the whole urgent chain (tested). Server payloads:
structurally satisfied today — no push channel exists yet, and the only
server-emitted signal (`sync:changed`) already carries IDs only; when
FCM/APNs land they inherit the same rule. ✔

---

## Epic 08 — Calendar (Phase 4)

### OPH-070 — Google OAuth connect ✅

- [x] OAuth2 flow (offline access, calendar scope); tokens encrypted at rest (AES-256-GCM, key from env)
- [x] `calendar_accounts` create/status endpoints; disconnect flow
- [x] Tests with mocked Google endpoints

Acceptance notes (design in [ADR-0006](adr/0006-google-oauth-token-crypto-and-mirror-queue.md)):
`POST /workspaces/:id/integrations/google/connect` returns the consent URL
with a 10-minute signed state (`purpose: google_oauth` — a session JWT does
NOT pass, tested); the unauthenticated callback exchanges the code, decodes
the id_token for the Google identity and upserts `calendar_accounts`
(reconnect never duplicates; `prompt=consent` re-issues refresh tokens).
Tokens at rest are AES-256-GCM ciphertext under `CALENDAR_TOKEN_KEY`
(64 hex; production refuses placeholders when Google is configured — the
integration itself is optional: `GOOGLE_NOT_CONFIGURED` without creds).
Status endpoint never leaks token material; disconnect revokes at Google
(best effort) and NULLs the ciphertext. Tests run against an in-process
fake Google (`test/helpers/fakegoogle.js`) — happy path, forged/expired
state, failed exchange, reconnect upsert, crypto tamper/wrong-key. ✔

### OPH-071 — Google calendar list ✅

- [x] List calendars, choose `default_calendar_id`

Acceptance notes: `GET /integrations/google/accounts/:id/calendars` proxies
Google's calendarList with transparent refresh — an access token expiring
within a minute is renewed and re-encrypted in place; a rejected refresh
flips the account to `error` and answers `CALENDAR_ACCOUNT_REAUTH_REQUIRED`
(502). `PATCH /integrations/google/accounts/:id {defaultCalendarId}` stores
the choice and immediately backfills: a mirror sweep enqueues every
mirror-enabled task of the workspace. Accounts are managed only by the user
who connected them. ✔

### OPH-072 — Mirror task to Google event ✅

- [x] Create/update/delete event for mirrored tasks (`[Task] {title}`, scheduled block or due slot)
- [x] `calendar_event_links` rows; retries via BullMQ job queue

Acceptance notes: tasks opt in via the new `calendarMirrorEnabled` field
(REST + sync push + snapshots). Derivation is pure (`src/lib/mirror.js`,
§7.1): scheduled block verbatim (open end → +30 min), else a 30-minute due
slot, else an urgent reminder block; completed/cancelled/archived/deleted →
event removed. Every committed task write enqueues a mirror job
(post-commit entity events); BullMQ carries them with exponential-backoff
retries when Redis is up, an inline serialized runner otherwise (dev
degraded + unit tests — `app.mirror.idle()` makes tests deterministic).
The worker converges on CURRENT state, tolerates remote deletions
(recreates; conflict policy proper is OPH-076) and keeps
`calendar_event_links` as the mapping source of truth. Proven end-to-end
over real Redis+BullMQ in integration. ✔

### OPH-073 — Google extended properties mapping ✅

- [x] `extendedProperties.private.alliswell_task_id` / `alliswell_workspace_id` (ADR-0003)
- [x] Re-link on duplicate detection

Acceptance notes: every mirrored event carries the ADR-0003 private keys
plus `alliswell_project_id`, `alliswell_source` and `alliswell_revision`
(§7.1 metadata). Before creating, the worker searches the calendar for
`privateExtendedProperty=alliswell_task_id=<id>` and ADOPTS a hit —
re-linking instead of duplicating after a lost link row (tested). ✔

### OPH-074 — Google webhook receiver ✅

- [x] `POST /api/v1/integrations/google/webhook` (channel token validation, mark account dirty)
- [x] Channel renewal job (channels expire)

Acceptance notes (design in [ADR-0007](adr/0007-google-inbound-sync-and-conflict-policy.md)):
the receiver is unauthenticated by nature — Google's notification carries no
body, only headers — so the **channel token is the gate**: we mint it, hand it
to Google once and store only `HMAC-SHA256('channel:'+token)`
(`webhook_channel_token_hash`, new append-only migration alongside
`sync_dirty_at`), compared in constant time. A forged token → `401`
`GOOGLE_WEBHOOK_INVALID_TOKEN`; an unknown/retired channel → `200` (retries
cannot make it exist, and without the account we cannot even call
`channels.stop`); `X-Goog-Resource-State: sync` is the channel-opened
handshake and marks nothing dirty. The route runs in its own content-type
scope because Fastify's JSON parser would 400 the bodyless POST Google
actually sends. Real notifications stamp `sync_dirty_at` and enqueue — the
receiver must answer fast. Renewal (`runWatchJob` + the sweep,
`CALENDAR_SYNC_SWEEP_SEC`): a fresh channel goes live BEFORE the old one is
stopped (no gap; overlap only duplicates), keyed off the `expiration` Google
answered with rather than the ttl we asked for, and disconnect stops the
channel before revoking the token. `GOOGLE_WEBHOOK_URL` is optional: Google
demands public HTTPS, so channel-less installs are polled by the same sweep
instead. ✔

### OPH-075 — Google incremental sync worker ✅

- [x] Worker consumes dirty accounts; `syncToken` incremental fetch; full resync on 410

Acceptance notes: `plugins/calendar-sync.js` mirrors the outbound queue's
shape (BullMQ with Redis, inline runner without — both now share
`queue/runner.js`). The worker paginates to the last page before trusting a
cursor (Google puts `nextSyncToken` there only), absorbs a `410` by dropping
the token and resyncing in full — no local wipe needed, since
`calendar_event_links` is keyed by event id and every event reconciles itself
on the way through — and clears `sync_dirty_at` with a compare-and-clear so a
notification landing mid-sync keeps its own pass. Errors are deliberately loud
(bubble → backoff retries → `last_error` on the status endpoint): events we
merely cannot interpret answer `time_conflict` rather than throwing, so a
throw really does mean infrastructure. ✔

### OPH-076 — Google two-way conflict handling ✅

- [x] etag/updated comparison → apply provider changes to task (time fields), or push local, or
      flag `conflict_status`; tests for all four conflict states

Acceptance notes: the whole matrix is a PURE function (`src/lib/inbound.js`,
the inbound twin of `desiredEventForTask`), so all four states are tested
without Google or a database, then again end to end. **Echo suppression is
etag-based** — every outbound write stores the etag Google answered with, so
our own change coming back is never mistaken for a user edit; this is what
stops mirror ⇄ sync from looping. A foreign move lands on
`scheduled_start_at`/`scheduled_end_at`, never `due_at` (dragging a block means
"I'll do it then"), and is compared against the §7.1 **derived** window so a
cosmetic edit cannot silently pin a due-derived task to a schedule. All-day
events map to midnight in the task's timezone (exclusive `end.date` honoured).
The four states: `local_changed_provider_changed` (both moved → §6.5
last-write-wins, loser dropped, flag recorded; a later clean write resets it to
`none` = converged), `provider_deleted_local_exists` (the user deleted our
event → keep the task, stop mirroring it, leave the flagged link as a
tombstone the mirror job skips — never resurrect, never delete the task),
`local_deleted_provider_exists` (task no longer earns an event but the entry
lives and changed → local is canonical, remove it), `time_conflict` (a
recurring series or unusable boundaries → flag, touch neither side).
Provider-driven task writes are ordinary writes: one transaction, a sync
revision, reminder reconciled, attributed to the connecting user. ✔

> **OPH-082/083 added 2026-07-16, from live use.** The product lead connected his real
> Google account and said his calendar's events never appeared. Correct and deliberate —
> `lib/inbound.js` ignores any event that isn't ours — but the line was wrong: AllisWell
> has a Calendar tab and §12 calls Home "the single chronological view where everything
> shows", and neither can answer "what does my day look like" from tasks alone. BLUEPRINT
> never specced external events at all (not even in the v2 parking lot), so this is a spec
> hole, not a code bug. Design: [ADR-0008](adr/0008-external-calendar-events.md).
> **The data is already in our hands** — the OPH-075 worker fetches the whole feed each
> pass and drops the foreign half on the floor.

### OPH-082 — External calendar events (server) ✅

- [x] `calendar_external_events` table + `calendar_accounts.external_sync_token` (append-only)
- [x] Second feed in the inbound worker: `singleEvents=true`, its own cursor, same
      webhook/dirty/sweep trigger; skip our own events (`alliswell_task_id`), apply the
      storage window, cancelled → delete
- [x] Pure derivation `lib/external-events.js` (Google event → row, or skip + reason)
- [x] `sync/pull` snapshots + tombstones for `external_event`; `sync/push` rejects it
      (falls out of the `ENTITIES` registry as `SYNC_UNSUPPORTED_ENTITY` — no new code)
- [x] Tests: pure mapper (window, all-day, ours-skipped, cancelled), worker over the fake
      Google, pull/push

Acceptance notes: the feed was already in our hands — OPH-075 pulled every event
each pass and dropped the foreign half. Now it lands in
`calendar_external_events` as a read-only sync entity. **Verified against the
product lead's real Google account: 41 events, real syncToken.** Two contract
findings drove the design: `timeMin`/`timeMax` are incompatible with
`syncToken`, so a sync cannot be windowed by time (Google syncs whole
collections) — the window is applied when STORING, and the live account proves
it (kept 2026-06-16 → 2027-07-23 from a 31-back/400-forward window, older
history dropped); and `singleEvents` cannot serve both consumers, so the task
mirror keeps its `singleEvents=false` cursor (it must see recurrence masters to
answer `time_conflict`) while the display feed gets `singleEvents=true` and its
own. An unchanged event costs no revision — a full resync replays the whole
calendar and would otherwise wake every device per meeting. Read-only needed no
code: absence from the push `ENTITIES` registry IS the enforcement. ✔

### OPH-083 — External calendar events (app) ✅

- [x] drift table + applier mapping (schema v3 + migration step) + store
- [x] Calendar tab: events on the month grid next to task dots
- [x] **Home: events in the chronological groups (§12 "everything shows")** — deferred here,
      shipped as its own task OPH-084 ✅ (checkbox was left stale; corrected 2026-07-17)
- [x] Read-only affordance — never editable; visually distinct from tasks
- [x] Tests: applier round-trip, grouping with events, Calendar rendering

Acceptance notes: `features/calendar/` — drift schema v3 (`external_events`,
migrated by `createTable`, proven by the v1→latest migration test), applier
case, and a store with **no write path at all — that absence is the read-only
guarantee**. `ExternalEventTile` is deliberately a different species from
`TaskTile`: a time rail instead of a checkbox, because you cannot complete a
meeting and the row must not suggest you can; "not busy" events (Google's
`transparent` — birthdays, holidays) recede to a muted accent. Day maths is
pure and tested: Google's exclusive end means an all-day event marks ONE day,
and multi-day events mark every day they touch. Verified live in the browser
against the real account, light and dark.

**Deferred, deliberately:** Home's chronological groups. §12 wants events there
too, but `HomeGroup` carries tasks and mixing events in changes a tested pure
function and the shape of every row — a real change that deserves its own task
rather than being smuggled into this one. The Calendar tab is where the lead
looked and where the gap was reported; Home is next (OPH-084).

### OPH-084 — External events on Home ✅

- [x] Home's chronological groups carry events beside tasks (§12: "the single
      chronological view where everything shows") — needs `HomeGroup` to hold a
      mixed, ordered list, so the pure grouping function and its tests change

Acceptance notes: `HomeGroup.tasks` became `HomeGroup.items`, a sealed
`HomeItem` (`TaskItem` | `EventItem`) with an `at` sort key — so a 10:00 meeting
renders ABOVE a 16:00 task instead of tasks and calendar living in separate
lists. That is the difference between §12's "one chronological view" and a
sidebar. The month grid now dots days that only carry a meeting.

Two product rules, both tested, both about not lying to the user:

- **Events never enter Overdue.** Overdue means "you still owe this"; a meeting
  that already happened is history, not a debt, so past events leave Home
  entirely rather than nagging beside real work.
- **An ongoing multi-day event belongs to Today, once.** A trip that started
  Sunday and runs to Thursday is happening NOW — it is not overdue (it began in
  the past) and it is not repeated into every bucket it spans. It sits at the
  first day it touches that has not passed.

A workspace with no calendar connected renders exactly as before (the events
list is simply empty — not an error, not a spinner).

### OPH-077 — Apple EventKit Flutter plugin skeleton ✅

- [x] Platform channel (iOS/macOS): permission request + calendar list

Acceptance notes: shipped as a **package** (`apps/app/packages/alliswell_eventkit`),
not Swift files dropped into `Runner`. That choice is the point: Flutter's
tooling wires the podspec for iOS *and* macOS by itself, so there is **zero
pbxproj surgery** — the thing STATE has deliberately avoided since Epic 07.
Proven by a real `flutter build ios --debug`: the Swift compiles and the pod is
picked up with nothing hand-edited.

**One Swift file serves both platforms** — `macos/…/Sources` is a symlink to the
iOS sources, and the only real difference (`import Flutter` vs `FlutterMacOS`,
`registrar.messenger()` vs `.messenger`) is conditional compilation. EventKit
itself is identical on both. ⚠️ The macOS half is **not yet compiled** — see the
macOS signing note in STATE (inherited breakage, not this task's).

The native side is deliberately dumb: it requests access and lists calendars,
nothing else. Every decision (what mirrors, when, who wins) stays in Dart where
it is pure and testable — the same seam `notifications/gateway.dart` uses.

Design points worth keeping:

- **`writeOnly` (iOS 17+) is NOT "granted".** It can create events but cannot
  read them back, which is exactly what re-linking our own events needs — so it
  is its own state rather than a flavour of yes. `requestFullAccess` therefore
  answers with a *status*, not a bool: "denied" and "write-only" are different
  problems and the UI has to say different things about them.
- **One `EKEventStore` for the plugin's lifetime** — EventKit ties a grant to
  the instance that asked, so a per-call store would re-prompt the user.
- **Read-only calendars are surfaced** (`isWritable`): mirroring into a
  subscribed/holiday calendar fails on *every* write, so the picker must rule
  them out rather than let the user pick a dead end.
- Non-Apple platforms answer `restricted` (Apple's own word for "this device
  will never allow it") instead of throwing — the feature simply does not exist
  there, and the UI already hides it.
- `NSCalendarsFullAccessUsageDescription` added to iOS **and** macOS Info.plist
  (without it the app CRASHES at the prompt, it does not merely get denied), plus
  the macOS sandbox entitlement `com.apple.security.personal-information.calendars`.

### OPH-078 — Apple EventKit create/update event ✅

- [x] Event CRUD with `alliswell://task/{id}` URL marker; mapping rows; foreground resync

Acceptance notes: the device-side twin of the Google mirror. Apple has no server
API, so — unlike Google's server-side BullMQ queue — this runs IN THE APP,
reacting to the replica (`appleMirrorProvider` watches the open-task stream and
reconciles on every emit; the home shell keeps it alive). One-way in v1: task →
event. Reading foreign Apple edits back is deferred (the analogue of OPH-076 —
it needs a conflict policy and there is no push, only foreground polling).

- **The 4th pure decision function** (`apple_mirror.dart`, as ADR-0008 predicted):
  `desiredAppleEvent(task)` mirrors the server's `desiredEventForTask`
  fixture-for-fixture — same §7.1 rules, same backwards-end guard — so a task
  lands at the same time whether it reaches a calendar through Google or
  EventKit. `decideAppleMirror` is the create/update/noop/remove matrix, tested
  in isolation. The engine only executes.
- **Signature guard**: the map row stores a content fingerprint, so reconciling
  the whole set on every replica emit costs an EventKit round-trip only when
  something a calendar shows actually changed. (The client can't use revisions —
  local edits don't bump the server revision — so it compares content.)
- **Mapping is device-local drift** (`apple_event_links`, schema **v4** +
  migration step, proven by the v1→latest migration test): Apple events live on
  the device, so this is per-install cache like `sync_states`, never synced. The
  `alliswell://task/{id}` URL is the re-link recovery key (ADR-0003) because
  EventKit's own identifier can change on an iCloud move.
- **Orphan sweep**: `reconcileAll` deletes events for tasks that vanished
  entirely (a per-task reconcile never sees a deleted task), so un-mirroring and
  deletion both clean up.
- **Reachable** (the OPH-080 lesson): an Apple calendar Settings card — request
  access, pick which calendar to mirror into, honest status (amber until a
  calendar is chosen, blocked-in-Settings for denied). Hides itself entirely off
  Apple platforms. `NSCalendarsFullAccessUsageDescription` + the sandbox
  entitlement were already added in OPH-077.
- **Fixed an OPH-077 defect found on the way**: the committed Swift plugin file
  (`e3cb3ea`) was EMPTY — the previous session's `git stash` dance corrupted it
  after the iOS build passed but before the commit, and I committed without
  re-building. So the method channel had no native handler. Restored here (with
  the CRUD methods) and re-verified by a real `flutter build ios`. The lesson:
  `flutter analyze` does not compile Swift, so a green analyze hid it.
- Tests: 27 (pure derivation + decision matrix + engine over a fake gateway and
  real in-memory replica + channel CRUD contract + v4 migration). ⚠️ The actual
  EventKit round-trip is device-only — a device pass is pending, consistent with
  OPH-061's notification device tour. iOS build compiles the Swift; macOS still
  cannot build (inherited signing gap, STATE).

### OPH-079 — CalDAV design doc ✅

- [x] docs/CALDAV.md: iCloud app-specific password flow, ETag sync, security warnings (v2 scope)

Acceptance notes: [CALDAV.md](CALDAV.md) — 9 references, design-only (nothing built).
Written now, ahead of its epic slot, because OPH-077/078 are blocked on Xcode
signing and because the decision it documents — asking users for an iCloud
app-specific password — is the most security-sensitive thing AllisWell would
ever do (AGENTS.md rule 10: risky things in writing first). Headline: an
app-specific password is **not** an OAuth token — unscoped, never expires,
un-revocable from our side, and reversible at rest by construction (we must
replay it, so it cannot be hashed like a channel token). Hence: ADR-0006 crypto,
connector **disabled by default** behind `CALDAV_ENABLED`, verify-before-store,
plain-language consent, and a disconnect that tells the user the other half of
revocation is theirs. Protocol: discovery → per-account partition host
(`p34-caldav.icloud.com`, never hardcode), RFC 6578 `sync-collection` with an
opaque token (404 = deleted; ANY token rejection → full resync — the RFC does
not prescribe a status, so don't match on one), no PATCH (whole-VEVENT PUT),
`If-Match` etag concurrency where a `412` **is** the conflict signal. The
OPH-015 schema already fits (`apple_caldav`, `provider_event_uid`, `etag`,
`sync_token`); one append-only migration adds `encrypted_app_password` +
principal/home URLs. Key finding: **ADR-0007's conflict matrix carries over
unchanged** if `lib/inbound.js` is fed a normalized event — doing that
normalization first is the difference between a connector and a second copy of
Epic 08. CalDAV has no push, so it is polling-only — already a first-class mode
because OPH-074 built it for webhook-less installs. ✔

---

> **OPH-080/081 added 2026-07-15.** Epic 08 shipped a complete Google API vertical
> (OPH-070…076) that **no user can reach**: the app has no way to connect an account,
> and `calendarMirrorEnabled` is not in the Flutter model at all — so mirroring can
> never be switched on. BLUEPRINT §12 already requires the task-detail "Calendar mirror
> toggle"; it was simply never given a task. Taken now because OPH-077/078 are blocked
> on Xcode signing (see STATE.md → Blocked).

### OPH-080 — Flutter Google Calendar connect UI ✅

- [x] Settings → Calendar section: connect (opens consent URL), account status, disconnect
- [x] Calendar picker after connect (`GET …/calendars` → `PATCH …{defaultCalendarId}`)
- [x] Honest states: not-configured (`GOOGLE_NOT_CONFIGURED`), needs-reconnect
      (`CALENDAR_ACCOUNT_REAUTH_REQUIRED`), error (`lastError`)
- [x] Tests over the fake API; design system compliance (AGENTS.md rule 11, light + dark)

Acceptance notes: `features/integrations/` — REST, deliberately outside the sync
protocol (calendar accounts are per-user server state; a cached "connected"
would be a lie), joining `/me` as the only place a screen may call the API
directly. Flow: connect → pick a calendar → done. `url_launcher` (new
dependency) opens consent in a REAL browser (`externalApplication` — Google
blocks webviews, and the app never handles an OAuth code: identity rides in the
server's signed state, ADR-0006); it sits behind `urlLauncherProvider` so tests
observe the hand-off without a platform channel. Icon colour tells the truth:
amber while a connected account still has no calendar (it mirrors nothing),
green only once it works, red on reauth. `configured: false` is stated plainly,
not as an error — the integration is optional and self-hosters are their own
admin. Disconnect says events already in the calendar stay there. Verified in
the real browser, light AND dark, plus the contrast guard (FAILURES: 0). ✔

**Found by verifying in the browser rather than trusting the tests** — see the
`awRetry` note under OPH-081.

### OPH-081 — Flutter task calendar mirror toggle ✅

- [x] `calendarMirrorEnabled` through the replica: drift column + schema migration, sync
      applier mapping, task store write (optimistic + outbox)
- [x] Task detail toggle (BLUEPRINT §12) — local-first, no REST from the screen
- [x] Tests: applier round-trip, store write/outbox, detail toggle

Acceptance notes: the server has carried `calendarMirrorEnabled` since OPH-072
(REST + sync push allowlist + pull snapshots) — the app dropped it at every
layer, so **zero server work was needed**. Now: drift column (schema v2, the
project's first replica migration — plan and proof below), `taskCompanion`
mapping, `Task` model, `TaskStore.update` branch, and the §12 toggle cloned
from the urgent switch. The subtitle tells the truth per task — "Adds a block
to your connected calendar" vs "Add a date below and it will appear" — instead
of silently doing nothing on a task §7.1 can't derive a time from; enabling it
early still works, because the mirror starts on its own once a date lands.

**Also closed a hole in OPH-076:** `scheduled_*` is where a dragged calendar
event lands, and the app modelled neither field — so the marquee two-way sync
was invisible. `Task` now carries them and the detail screen has a Scheduled
row. Clearing/moving the start clears the end (a stale end would make §7.1
derive a backwards block), and `desiredEventForTask` now guards that case
anyway: Google rejects `end <= start` with a 400 the queue could never retry
away.

**Two real bugs found by running the app instead of trusting green tests:**

1. **Riverpod 3 retries every failed provider by default** — 10×, 200 ms → 6.4 s
   (`ProviderContainer.defaultRetry`, which only declines for `Error`/
   `ProviderException`; our `ApiException` is a plain `Exception`). While it
   retries, the provider reports `AsyncLoading`, so the calendar picker sat on
   a spinner for ~38 s and asked a dead Google credential **eleven times** —
   the error state we designed was unreachable. Measured live: request gaps
   225/420/821/1628/3222/6426 ms. Policy now in `core/retry.dart` (`awRetry`,
   applied at every `ProviderScope` including the test ones): retry only what a
   retry could fix — failing to reach the server at all — everything else
   surfaces at once. After: **1 request, error shown immediately.** This
   affected every `FutureProvider` in the app, not just the new ones.
2. **Why the widget tests missed it:** they build their own `ProviderScope`
   (so they never had the app's policy) and `pumpAndSettle` burns through the
   backoff in fake time, so the error state appears "instantly" in a test and
   after 38 real seconds for a user. The regression test is therefore a unit
   test of the policy itself (`test/core/retry_test.dart`), and the test scopes
   now share the production policy.

**Migration plan (AGENTS.md rule 10 — written before implementation).** This is the
**first drift schema migration in the project's history** and it sets the precedent
for every one after it, so the plan is about the harness as much as the column.

- *Current state:* `schemaVersion => 1` with **no `MigrationStrategy` at all**. Drift's
  default `onUpgrade` throws, so a bare version bump would brick every existing
  install on open — including live web (localStorage/IndexedDB) and simulator data.
- *Change:* `Tasks.calendarMirrorEnabled` = `boolean().withDefault(const Constant(false))`
  (NOT NULL + default, mirroring the server column), `schemaVersion` 1 → 2, and the
  first `MigrationStrategy`: `onCreate: (m) => m.createAll()`, plus an
  `onUpgrade` version ladder — one narrow `if (from < n)` per version:
  `if (from < 2) await m.addColumn(tasks, tasks.calendarMirrorEnabled)`.
  (Drift's generated `stepByStep` would read better, but it is produced by the
  same `drift_dev schema` tooling that is broken here — see *Verification*.)
- *Why migrate at all, given the replica is cache?* Because it also holds the
  **outbox**: a failed open would strand writes that never reached the server.
  "Wipe and re-pull" is not a safe shortcut here.
- *Safety of the migration itself:* `ADD COLUMN` with a NOT NULL default is the
  cheapest, least reversible-risk migration SQLite has — existing rows take the
  default, nothing is rewritten, no data is read or moved.
- *Verification:* drift's sanctioned schema-test tooling (`drift_dev schema dump`)
  is **broken on this toolchain** — drift_dev 2.34.0's verifier calls
  `allSchemaEntities`, which drift 2.34.2's drift3-preview `GeneratedDatabase` does
  not define. So the migration is tested directly instead, against a real file-backed
  SQLite: create the schema, drop the new column and set `user_version = 1` to
  manufacture a genuine v1 database **with a row in it**, close, reopen the real
  `AwDatabase` over the same file, and assert `onUpgrade` ran, the row survived and
  the column reads `false`. This exercises the real migration code path, not a mock
  of it. Revisit the generated harness when the toolchain versions line up.
- *Rollback:* none needed — a v2 replica is disposable local cache. Worst case a user
  clears it and the next pull rebuilds from the server (MySQL is canonical, §6.2).

---

## Epic 09 — Open-source readiness (Phase 6)

### OPH-090 — CONTRIBUTING.md ✅

- [x] Setup, workflow, commit conventions, PR checklist

### OPH-091 — SECURITY.md ✅

- [x] Reporting channel, supported versions, handling process

### OPH-092 — Issue templates ✅

- [x] Bug report + feature request forms, config with links

### OPH-093 — PR template ✅

- [x] Checklist mirroring Definition of Done

### OPH-094 — Public roadmap ✅

- [x] ROADMAP.md generated from phases; link from README; GitHub Projects note

Acceptance notes: [ROADMAP.md](../ROADMAP.md) — phase-by-phase (0-6) from
BLUEPRINT §14, honest against real state (✅ shipped / 🟡 partial / ⏳ planned /
💤 v2), with a v0.1.0 milestone and a v2 parking lot that matches TASKS.md's.
Linked from the README docs index AND the top-of-file status line. The "GitHub
Projects note" is deliberate: the markdown files (STATE/TASKS/CHANGELOG) stay the
single source of truth — a Projects board is optional and layered on top only if
the project grows a team — because those files are what the AI-agent workflow
reads and writes. Cross-linked to STATE/TASKS/CHANGELOG so they can't silently
drift ("when they disagree, they win"). ✔

### OPH-095 — First release notes ✅

- [x] v0.1.0 tag notes; release automation (GitHub Actions release workflow)

Acceptance notes: `.github/workflows/release.yml` — triggered by a `v*.*.*` tag,
where the tag IS the version. It (1) **gates on the full CI suite** by reusing
`ci.yml` via `workflow_call` (a tag never publishes code CI has not green-lit —
no trimmed copy to drift); (2) **verifies the tag matches** `apps/api`'s and
`apps/app`'s declared versions, failing loudly on a mismatch; (3) **extracts the
release notes from CHANGELOG.md** for that version (one source of truth — the
awk stops at the "Development log" marker so the release shows the curated
Highlights + Known limitations, not the whole history, with a link to the full
log); (4) builds the **web bundle** (`alliswell-web-<v>.tar.gz`, the artifact a
self-hoster actually wants) and (5) publishes a GitHub Release, marked
prerelease below 1.0. CHANGELOG restructured with a curated `## [0.1.0]` section.
The extractor + version check + YAML were verified locally
(`awk`/`python3 -c yaml.safe_load`). **Cutting the actual v0.1.0 release is left
to the maintainer** — pushing a tag is an outward publish; the automation is
ready, the command is `git tag v0.1.0 && git push origin v0.1.0`. ✔

---

## Epic 10 — Feedback round 4: user-testing UX corrections (Phase 4.9, v0.1.1)

> **Source:** the FIRST hands-on user-testing session (2026-07-17, Mahir; iOS simulator +
> web against the full local stack). 13 numbered feedback items, captured verbatim and
> researched against the codebase the same day. The binding spec changes already landed in
> BLUEPRINT (§4.2, §4.3, §12.2–§12.7) and DESIGN §4 ("Project badge") — **when a task below
> and those sections disagree, the sections win** (they carry the reviewed wording).
>
> Every task still follows AGENTS.md §2/§3 in full: tests + docs + `flutter analyze` clean +
> both themes checked + contrast guard where palettes move. Work strictly top-to-bottom —
> the two bug fixes come first on purpose.
>
> Mapping (user's item № → task): 1→OPH-102, 2→OPH-103, 3→OPH-107, 4→OPH-111, 5→OPH-105,
> 6→OPH-101, 7→OPH-100, 8→OPH-106, 9→OPH-102, 10→OPH-104, 11→OPH-108, 12→OPH-109, 13→OPH-110.

### OPH-100 — Fix web sign-out crash (204 body is not a Map) ✅

- [x] `AuthApi._post` never casts `res.data` — type-check and fall back to `{}`
- [x] `AuthRepository.logout` clears local state no matter WHAT the client throws
- [x] Regression test: adapter returns 204 with an EMPTY STRING body (dio-web behavior)

Acceptance notes: both layers changed exactly as specced. `_post` replaced the
`res.data as Map<String, dynamic>?` cast with a type check (`data is Map ? data
: {}`) — fixes every empty/204 response, not just logout. `logout` broadened
`on AuthException` → `on Object` so the best-effort server revoke can never
block the local `_clearSession`. Tests (`auth_repository_test.dart`, +2): a
logout whose handler returns `emptyBody(204)` (the real dio-web shape — a new
`test_support` helper, NOT `jsonBody(204, {})`) completes and clears; and a
stub API that throws a non-AuthException still clears locally. 11/11 auth tests
green. ✔

**User's report (item 7):** signing out on web logged `TypeError: "": type 'String' is not a
subtype of type 'Map<String, dynamic>?'` from `auth_api.dart:54` — after the server had
already answered `204 No Content`.

**Diagnosis (verified in source):** `POST /api/v1/auth/logout` correctly returns 204 with no
body. On web, dio materializes an empty body as the empty STRING `''`, so
`res.data as Map<String, dynamic>?` in `_post` (apps/app/lib/src/features/auth/data/auth_api.dart)
throws a `TypeError`. That error is NOT an `AuthException`, and `AuthRepository.logout`
(auth_repository.dart, `on AuthException` only) lets it escape **before `_clearSession()`
runs** — so the server session is revoked but the app still holds the dead session; the UI
only recovers when the next refresh fails. Two layers must change:

1. `_post`: replace the cast with a type check — `final data = res.data; return data is
   Map<String, dynamic> ? data : const <String, dynamic>{};`. This fixes every 204/empty
   response, not just logout.
2. `logout()`: broaden the catch (`on Object`) around the API call — sign-out is a
   local-state guarantee; the server call is best-effort (the comment already says so, the
   catch just didn't match reality).

**Tests** (`apps/app/test/features/auth/`): fake `HttpClientAdapter` returning 204 with `''`
→ `logout()` completes and the session store is empty; a second test where the adapter
throws a plain `Exception` → local session STILL cleared. Existing login/refresh tests stay
green.

**DoD:** `flutter analyze` + `flutter test`; manual web verify (sign out → login screen, no
console error).

### OPH-101 — Mobile: FABs are covered by the glass bottom nav ✅

- [x] Failing-first widget test: shell at phone size, tap each section's FAB
- [x] Fix so every FAB sits fully ABOVE the glass `NavigationBar` and receives taps
- [x] Audit every bottom-anchored control on narrow layouts (FABs ×3 + list padding)

Acceptance notes: **deviation from the specced "shared wrapper" — hoisted the
FAB to the shell instead**, which is the correct fix. A `Padding` wrapper on
the FAB was tried first (`MediaQuery.paddingOf(context).bottom`) and PROVEN
wrong two ways by the failing-first test: in a nested Scaffold the section's
FAB is positioned by the INNER scaffold (padding doesn't lift it enough), and
padding inside the FAB slot overflows its transition box. The nested-Scaffold
FAB is the anti-pattern; the fix removes all three section FABs
(home/projects/notes) and renders ONE FAB from `HomeShell`'s own Scaffold via
`_sectionFab(currentIndex)` — Flutter then places it above the shell's own
`bottomNavigationBar` natively, in both the narrow (bar) and wide (rail)
branches. Test (`test/features/shell/fab_layering_test.dart`) pumps the real
shell at 390×844 and, for Home/Projects/Notes, asserts the FAB rect does not
overlap the `NavigationBar` rect AND that a `tester.tap` opens the create sheet
/ editor (it fails against the old layout — real regression proof). **Also
fixed in passing:** the Notes filter-chip `Row` overflowed at phone width (26
px) and would have broken again when OPH-109 adds the 'READMEs' chip → made it
a horizontal scroll strip. `flutter analyze` clean; full suite 161/161. ✔

**User's report (item 6):** on mobile the floating action button sits BEHIND the bottom
navigation and cannot be tapped — note/project/task creation was untestable.

**Diagnosis (verified in source):** `HomeShell` (apps/app/lib/src/screens/home_shell.dart)
uses `extendBody: true` with a `GlassSurface`-wrapped `NavigationBar` so content scrolls
under the glass (DESIGN §4 "Navigation"). The section screens are NESTED `Scaffold`s with
their own `floatingActionButton` — the nested scaffold doesn't reserve space for the OUTER
scaffold's bar, so the FAB lands under the glass. Affected FABs (grepped):
`home_screen.dart:53`, `projects_screen.dart:21`, `notes_screen.dart:67`. Lists already
compensate via `awListPadding` — FABs don't.

**Spec:** on narrow layouts every FAB clears the nav bar by `MediaQuery.paddingOf(context)
.bottom` (published by `extendBody`) — implement ONCE (e.g. a small shared wrapper in
`lib/src/widgets/`, or padding applied where the FABs are declared), not three magic
numbers. Wide layouts (rail) must not gain stray bottom padding. Pushed full-screen routes
(`/tasks/:id`, `/settings`) render OUTSIDE the shell and are unaffected — confirm, don't
"fix".

**Tests:** widget test pumping the real `HomeShell` (use `test/support/sync_overrides.dart`)
at 390×844: for Home/Projects/Notes assert the FAB's rect does not intersect the
`NavigationBar`'s rect AND `tester.tap` on it opens the create sheet (write it BEFORE the
fix — it must fail against today's layout, that's the regression proof).

**DoD:** analyze + tests; manual iOS-simulator pass (task, project and note creation all
reachable); light + dark screenshots.

### OPH-102 — Home buckets: 30-day horizon; dateless on top, never dimmed ✅

- [x] `HomeBucket.later` → `HomeBucket.next30Days` ("Next 30 days"); horizon = today+30
- [x] Items beyond the horizon (tasks AND events) do not enter Home at all
- [x] `noDate` group renders directly under Overdue, ABOVE Today
- [x] `noDate` rows are NEVER dimmed — not even when a calendar day is selected
- [x] Rewrite `test/features/home/` grouping tests to the new contract

Acceptance notes: pure `groupTasksForHome` (`task_grouping.dart`). Order is
Selected day? → Overdue → No date → Today → Tomorrow → This week → Next 30
days; `kHomeHorizonDays = 30`. `futureBucketForDay` returns null past the
horizon; tasks split past→Overdue vs future-beyond→dropped BEFORE calling it
(so a +40d task drops while an overdue one stays); events reuse their existing
"first upcoming day" anchor and drop the same way. `daysWithTasks/Events`
(month-grid dots) stay UNBOUNDED — only the LIST has the horizon. Dimming
excludes `noDate` (`dimmed: selectedDay != null && bucket != selectedDay &&
bucket != noDate`). Tests rewritten across `home_events_test.dart` +
`tasks_api_test.dart` (+2 grouping tests: +29d in / +31d out, dateless
position + never-dims); the two affected widget suites moved to a wide surface
so tasks stay visible. ✔

**User's report (items 1 + 9):** Home must show Today/Tomorrow/This Week/Next 30 Days and no
more — the unbounded "Later" bucket fills with every future instance of recurring (e.g.
monthly) calendar events and buries real work. Dateless tasks currently sit at the BOTTOM
looking disabled; they are always-active work and belong at the TOP, above Today, at full
brightness.

**Spec (pure function `groupTasksForHome`, apps/app/lib/src/features/home/task_grouping.dart):**

- Bucket order: `selectedDay?` → `overdue` → `noDate` → `today` → `tomorrow` → `thisWeek` →
  `next30Days`. (Overdue keeps the crown — it is owed debt; the user asked "above Today"
  and this satisfies it. If he later wants dateless above Overdue it is a 2-line swap.)
- Day boundaries (local days): today = `dayOf(now)`; tomorrow = +1; thisWeek = +2…+6
  (`day.isBefore(today+7)`); next30Days = +7…+30 INCLUSIVE (`!day.isAfter(today+30)`).
- **Horizon:** a dated task with due day > today+30 → dropped (no bucket). An event whose
  anchor day (existing "first day it touches that has not passed" rule — do NOT change it)
  is > today+30 → dropped. They live on the Calendar tab. Recurring Google events arrive as
  separate instances (`singleEvents=true` feed), so the horizon naturally caps them.
- `daysWithTasks` / `daysWithEvents` (month-grid dots) stay UNBOUNDED — dots are the
  calendar's job; only the LIST has a horizon. Server sync windows are untouched.
- Dimming: the `dimmed` flag stays selection-driven, but the `noDate` group is ALWAYS
  `dimmed: false` — dateless work belongs to every day, including the selected one. (This
  is the "looks disabled" half of item 9: with a day selected, dateless rows faded at 0.45.)
- `HomeBucketLabel`: 'Next 30 days'. Update the ordering comment in `home_screen.dart` and
  keep BLUEPRINT §12.2 (already revised) truthful.
- Cross-ref: `noDate` gets emptier when OPH-107 removes inbox captures from `watchOpen` —
  don't pre-implement that here.

**Tests:** task at +29d in next30Days; at +31d absent; monthly-event instances at +40/+70d
absent while the +20d instance shows; dateless: position (index 1 with an overdue present,
index 0 without) and `dimmed == false` while another day is selected; selected-day pull and
event overdue-exclusion (existing rules) still hold.

**DoD:** analyze + `flutter test`; light+dark web check of Home with a seeded month of data.

### OPH-103 — Home (mobile): the month calendar scrolls WITH the list ✅

- [x] Narrow layout: calendar becomes the first element of ONE scrollable (no sticky header)
- [x] "Hide calendar" toggle + persisted pref keep working; quick-add stays pinned above
- [x] No nested scrolling; empty state still fills the remainder

Acceptance notes: narrow Home is now `Column[quickAdd, Expanded(CustomScrollView
key: 'home-scroll')]` — the calendar card and toggle are `SliverToBoxAdapter`s
(the 50%-height cap + inner scroll are gone), the groups a `SliverList`, and
empty a `SliverFillRemaining`. Group/row building was extracted to a shared
`buildHomeGroupRows` used by BOTH the wide `_GroupedTaskList` (ListView) and the
narrow slivers — no duplicated logic. `home_scroll_test.dart`: dragging the list
up makes `MonthCalendar` un-hit-testable and dragging back restores it; Hide
persists; quick-add stays pinned and still captures. ✔

**User's report (item 2):** keep "Hide calendar", but even with the calendar visible,
scrolling the list must slide the calendar off-screen — it must NOT stay fixed at the top
eating half the screen.

**Today (home_screen.dart, narrow branch):** `Column[quickAdd, calendar(≤50% height, own
inner `SingleChildScrollView`), toggle row, Expanded(list)]` — the calendar is a permanent
header. **Target:** `Column[quickAdd, Expanded(CustomScrollView(slivers: [if (visible)
calendar card, toggle row, …grouped list…]))]` — calendar and toggle are ordinary scroll
content (`SliverToBoxAdapter`); the 50%-height cap and the inner scroll view are REMOVED
(the outer scroll owns everything). Wide layout (side panel) unchanged.

Refactor `_GroupedTaskList` so ONE builder yields the group slivers/rows used by both
layouts — do not duplicate the group-rendering logic. Empty state: `SliverFillRemaining`
hosting the existing `AwEmptyState`. Keep `awListPadding`'s bottom clearance on the LAST
sliver so rows still clear the glass bar (and the FAB fixed in OPH-101).

**Tests (widget, phone size):** with 30+ rows, `drag` the list up → `MonthCalendar` is no
longer hit-testable/visible, and dragging back down reveals it; toggle hides/shows and
persists (fake `localKv`); quick-add still appends while scrolled; day-tap on a marked day
still selects (grid tap targets unaffected by the sliver move).

**DoD:** analyze + tests; iOS simulator manual scroll check; light + dark.

### OPH-104 — Project badge on task rows ✅

- [x] `ProjectBadge` widget per DESIGN §4 (filled pill, 6-char + "…", tooltip, computed
      foreground, semantics)
- [x] `projectsByIdProvider` (Map<String, Project> from the replica) — no per-row queries
- [x] Rightmost in `TaskTile`'s trailing cluster; hidden via flag inside a project's own
      Tasks tab
- [x] Foreground-helper unit test sweeps `kProjectPalette` + color-grid extremes

Acceptance notes: `ProjectBadge` (`features/projects/ui/project_badge.dart`) —
filled pill (`AwRadius.s`, 8×2 pad, `labelSmall` w600), grapheme-safe
`shortLabel` (first 6 + "…"), `Tooltip` + `Semantics('Project: <name>')`.
**Contrast reality found during work:** the palette's violet `#8B5CF6`
(luminance ≈ 0.198) sits in a dead zone where NEITHER near-black nor white text
reaches 4.5:1 on the raw fill — so `legibleColors` picks the higher-contrast ink
AND nudges the fill's lightness a few percent (monotonic, away from the ink)
until AA passes; most colors pass untouched. `awContrastRatio` helper added to
`tokens.dart` (theme layer, no cross-feature import). `projectsByIdProvider`
(map over the existing replica stream) feeds `TaskTile`; badge is the
outermost trailing element, `showProjectBadge: false` in the project Tasks tab.
`project_badge_test.dart` (39 cases): every `kProjectPalette` swatch + all
`Colors.primaries` + neutrals + white/black/mid-grey clear 4.5:1; violet is
nudged, blue untouched; truncation + tooltip widget test. ✔

**User's report (item 10):** on Home you cannot tell which task belongs to which project.
Wanted: at the row's far right, a FILLED badge in the project's color with the project name
inside (truncate after 6 chars with "…"), full name on hover — one glance, no tap.

**Spec:** DESIGN §4 "Project badge" (added 2026-07-17) is the binding visual contract —
radius `AwRadius.s`, padding 8×2, `labelSmall` w600, min height 22, `Tooltip` (hover +
long-press) with the full name, `semanticLabel: 'Project: <full name>'`, foreground by
relative luminance (> 0.45 → ink `#101828`, else white). Put the luminance helper next to
`taskPriorityColor` in `task_visuals.dart` (or `theme/`) so future colored chips reuse it.
Truncation is data-side (`Characters` API, first 6 graphemes + '…') — NOT `TextOverflow`
(the pill must hug its short label).

**Data path:** `Task` carries only `projectId`. Add a `projectsByIdProvider` derived from
the existing replica stream (`projectsControllerProvider`) so `TaskTile` resolves name+color
with a map lookup. Rows without a project render NO badge. Trailing order: priority flag ·
status icon · urgent · **badge** (badge outermost — the user asked for the far right).
`TaskTile` gains `showProjectBadge` (default true); the project-detail Tasks tab passes
false (same-project badge is noise).

**Tests:** widget — badge shows name 'Deneme' as-is (6 chars) and 'Deneme Projesi' as
'Deneme…' with tooltip 'Deneme Projesi'; no badge when `projectId == null`; hidden in the
project tab; unit — foreground helper against every `kProjectPalette` swatch and
white/black grid extremes (assert the documented threshold behavior, both themes).

**DoD:** analyze + tests; light + dark screenshots of Home rows with 2+ project colors.

### OPH-105 — Status icons: `open` is no longer a bare circle ✅

- [x] `taskStatusIcon`: `open` → `Icons.hourglass_empty`; `waiting` → `Icons.pause_circle_outline`
- [x] Sweep tests/keys referencing the old icons; verify dropdowns + rows in both themes

Acceptance notes: single source `taskStatusIcon` (`task_visuals.dart`) — `open`
is now a pending hourglass (was `radio_button_unchecked`, which fought the row's
circular checkbox), and `waiting` took `pause_circle_outline` so every status
stays a distinct icon. `tasks_api_test` gained assertions (`open ==
hourglass_empty`, `open != radio_button_unchecked`, `waiting ==
pause_circle_outline`) plus its existing all-unique check; the row test in
`tasks_flow_test` now expects the hourglass. Grepped: no other
`radio_button_unchecked` reference remains. ✔

**User's report (item 5):** the `open` status icon must change to a "waiting/pending" style
icon — an open task is work waiting to be done — and it must NOT be a plain circle (it
collides with the circular completion checkbox at the row's left).

**Spec:** single source `taskStatusIcon` (apps/app/lib/src/features/tasks/ui/task_visuals.dart):
`'open' => Icons.hourglass_empty` (the pending metaphor the user asked for) and, to keep
statuses distinguishable (feedback round 3 rule: status→icon, one meaning each),
`'waiting' => Icons.pause_circle_outline` (on-hold hands the hourglass to `open`). All other
statuses unchanged. BLUEPRINT §12.4 already documents this mapping — keep code equal to it.
Everything downstream (row trailing icon, `StatusLabel` dropdown entries in detail + sheets)
updates through the one function; verify nothing else hardcodes `radio_button_unchecked`
(grep app + tests).

**Tests:** unit on the mapping (open ≠ waiting, open is not `radio_button_unchecked`);
adjust any widget test finding the old icons.

**DoD:** analyze + tests; light + dark spot-check of a task row and the status dropdown.

### OPH-106 — Project picker: always legible in the create sheet, added to detail ✅

- [x] Create sheet: picker visible with 0 projects, with a helper pointing to Projects
- [x] Task DETAIL screen gains a Project dropdown (`Key('detail-project')`)
- [x] Archived projects excluded from both pickers (forward-ref OPH-110)

Acceptance notes: shared `projectDropdownItems` (`features/projects/ui/
project_picker.dart`) builds the 'No project' + color-dot entries for BOTH the
create sheet and the new task-detail dropdown (`Key('detail-project')`, writes
`projectId` through the store). The create sheet keeps the field visible when
`projects.isEmpty` and adds the helper 'No projects yet — create one in the
Projects tab'. Archived projects are filtered NOW (inert until OPH-110) — with
one exception: an archived project that is the task's CURRENT value stays,
suffixed ' (archived)', so the value never silently vanishes. Tests:
`project_picker_test.dart` (No-project lead, active list, archived hidden,
archived-current kept+suffixed) + two widget tests (detail assigns a project →
one sync push; empty-state helper shows). ✔

**User's report (item 8):** opened "new task" from the FAB — no project selection visible;
detailed creation must allow choosing a project.

**Diagnosis (verified):** the sheet HAS a picker (`Key('task-sheet-project')`,
task_create_sheet.dart) — but with zero projects it renders a dropdown whose only entry is
"No project", which reads as "no picker". (At test time the user's workspace had no
projects yet — mobile project creation was blocked by OPH-101.) The DETAIL screen
(task_detail_screen.dart) has status/priority dropdowns but genuinely NO project field.

**Spec:**

1. Create sheet: when `projects` is empty, keep the field visible and add
   `helperText: 'No projects yet — create one in the Projects tab'` (disabled state is
   fine); with projects present, behavior unchanged (color dot + name entries).
2. Detail screen: add a 'Project' `DropdownButtonFormField` beside status/priority — entries
   'No project' + each project with its color dot (same visual as the sheet — extract the
   entry row into a shared widget instead of copying it); on change
   `taskStore.update(id, {'projectId': value})` (server + sync already accept `projectId`;
   verified in TASK_FIELDS and REST PATCH).
3. Both pickers exclude `status == 'archived'` projects once OPH-110 lands — write the
   filter against project status NOW (there are no archived projects yet, so it is inert);
   if the CURRENT task already points at an archived project, show that single entry
   suffixed ' (archived)' so the value stays visible/clearable.
4. Cross-ref OPH-107: once the auto-promote rule exists, assigning a project to an
   inbox-status task flips it to `open` — the detail dropdown must not fight that (it just
   patches `projectId`; the store rule does the rest).

**Tests:** sheet with 0 projects shows the helper; with 2 projects shows both entries;
detail dropdown change writes `projectId` to the replica AND enqueues one outbox mutation
(assert via the drift test db); picker hides an archived project but shows it suffixed when
already assigned.

**DoD:** analyze + tests; light + dark; manual web run: FAB → create with a project.

### OPH-107 — Inbox is a CAPTURE box: out of Home, with a triage flow ✅

- [x] `kOpenStatuses` split: planning lists (Home, project tabs) exclude `inbox`
- [x] Auto-promote in `TaskStore` (create+update): date OR project set on an inbox row →
      status `open` in the SAME write/outbox mutation (unless the patch sets status itself)
- [x] Inbox rows become `CaptureTile`: no checkbox; actions Plan / To note / Delete;
      tap = Plan
- [x] `TaskCreateSheet` gains edit/triage mode (prefilled, 'Save', updates instead of
      creating)
- [x] Copy: quick-add hint, empty state and section description say "capture now, sort
      later — these don't show on Home"
- [x] BLUEPRINT §4.3 + §12.6 stay the binding wording

Acceptance notes: `kOpenStatuses` → `kPlanningStatuses` (`['open', 'scheduled',
'in_progress', 'waiting']`, no `inbox`); `watchOpen` + `watchProjectTasks` use
it, `watchInbox` unchanged. Auto-promote lives in the store (single source):
`update` merges `status: 'open'` into the SAME optimistic write + outbox
mutation when an `inbox` row gains a non-null `dueAt`/`projectId` and the patch
carries no explicit status; `create` mirrors it. Inbox rows are a new
`_CaptureTile` (inbox icon, NO checkbox — you don't complete a thought; Plan /
Convert-to-note / Delete, tap = Plan). `TaskCreateSheet` gained a `task`
param → 'Plan task'/'Save' edit mode that updates in place (a date/project
there triggers the promote). Copy: quick-add 'Capture a thought…', empty state
'Inbox is for capturing', section description updated (feeds the OPH-111 tour).
Tests: `inbox_capture_test.dart` (8 store cases: off planning lists, promote on
date/project, NOT on unrelated patch / null-clear / explicit status, born-open,
one-mutation-carries-status) + 3 widget tests (Home excludes the capture & it
has no checkbox; Plan→date moves it to Home as 'open'; Convert→note removes it).
analyze clean; suite 223/223. ✔

**User's report (item 3):** Inbox must be where fleeting ideas are captured so they aren't
lost — written serially, evaluated/planned later — and the user must UNDERSTAND that from
the UI. If it stays a task status, inbox items must NOT appear as work on Home. (Both
halves adopted: keep the existing `inbox` status — zero schema work, sync already carries
it — and pull it out of the planning lists.)

**Verified plumbing:** captures already write `status: 'inbox'`
(`InboxTasksController.quickAdd`) and `watchInbox` filters on it; the leak is
`kOpenStatuses` (task_store.dart) including `'inbox'`, which `watchOpen` (Home) and
`watchProjectTasks` use.

**Spec:**

1. **Visibility:** introduce `kPlanningStatuses = ['open', 'scheduled', 'in_progress',
   'waiting']`; `watchOpen` + `watchProjectTasks` use it. `watchInbox` unchanged. Keep
   `kOpenStatuses` only if something still needs the "not terminal" meaning — otherwise
   delete it (grep first; update the export in providers.dart).
2. **Auto-promote (store-level, single source):** in `TaskStore.update` — if the current
   row's status is `inbox`, the patch does NOT contain `status`, and it sets a non-null
   `dueAt` OR non-null `projectId` → merge `status: 'open'` into the SAME optimistic write
   and the SAME outbox mutation (one server round-trip, no applier change — the server
   echoes status back). Mirror the rule in `create` (a capture created WITH a date/project
   isn't a capture). Server needs no change (`open` is a legal PATCH value).
3. **Inbox UI (task_list_screen.dart):** rows render as a new `CaptureTile` — leading
   `Icons.inbox_outlined` (NOT a checkbox: you don't "complete" a thought), title (wraps to
   2 lines), trailing: `event_outlined` 'Plan' → triage sheet; `description_outlined`
   'To note' → confirmation dialog ("Convert to a note? The capture moves to Notes.") →
   `noteStore.create(workspaceId, {'title': <capture title>})` then `taskStore.delete(id)`;
   `delete_outline` 'Delete' → existing delete confirm. Row tap = Plan. All three have
   tooltips + 44px targets (G4).
4. **Triage sheet:** extend `TaskCreateSheet` with an optional `task` parameter → edit mode:
   title prefilled, header 'Plan task', button 'Save', submit calls `taskStore.update`
   (auto-promote fires if a date/project was chosen; if the user saves with NEITHER, the
   capture honestly stays in Inbox — no silent promote).
5. **Copy:** quick-add hint 'Capture a thought…'; empty state title 'Inbox is for
   capturing' message 'Type above and sort later — captures never show on Home.'; section
   description (sections.dart) 'Capture thoughts fast — they stay out of Home until
   planned.' (feeds tooltips AND the OPH-111 tour).

**Tests:** store — inbox row absent from `watchOpen`/`watchProjectTasks`, present in
`watchInbox`; auto-promote on date-set, on project-set, NOT on unrelated patch, NOT when
patch carries an explicit status; create-with-date is born `open`; ONE outbox mutation per
promote. Widget — Home pumped with a seeded capture shows nothing; Plan flow sets a date →
row leaves Inbox and appears on Home; To-note flow creates the note and removes the capture;
quick-add still keeps focus (feedback round 2 contract).

**DoD:** analyze + tests; light + dark; manual: capture → plan → appears on Home.

### OPH-108 — Tab selection returns to the section root ✅

- [x] `HomeShell._goBranch`: `initialLocation: true` unconditionally
- [x] Widget test: Projects→detail→Notes→Projects lands on the LIST

Acceptance notes: one-liner in `home_shell.dart` (`goBranch(index,
initialLocation: true)`). Safety audit held: task detail + settings are pushed
on the ROOT navigator (above the shell, unaffected), and the note editor
flushes its debounced autosave in `dispose()` — so resetting a branch never
loses an edit. Widget test (`projects_flow_test.dart`) opens a project detail
(asserts its `TabBar`), switches to Inbox and back to Projects, and asserts the
LIST is shown (no `TabBar`) — fails against the old restore-last-location
behavior. ✔

**User's report (item 11):** opened the Deneme project, switched to another tab, tapped
Projects again — the project detail was still open. Returning to a tab must open that
section's main page.

**Spec:** in home_shell.dart, `_goBranch` currently passes `initialLocation: index ==
navigationShell.currentIndex` (re-tap resets, switch-back restores). Change to
`initialLocation: true` — selecting a tab ALWAYS shows the section root; tabs are sections,
not stacks (BLUEPRINT §12.3 note). This intentionally applies to every branch (consistency
beats per-tab surprises). Safety audit performed: the note editor flushes its debounced
autosave in `dispose()` (note_editor_screen.dart — verified), and task detail + settings are
pushed on the ROOT navigator, so they sit above the shell and are unaffected.

**Tests:** widget — navigate Projects → detail, switch to Notes, back to Projects → project
LIST visible (and detail disposed); same for Notes editor → Home → Notes lands on the notes
list with the note's latest text persisted (proves the dispose-flush).

**DoD:** analyze + tests; quick manual tab-dance on web + iOS sim.

### OPH-109 — README lives in its project; Notes list hides READMEs ✅

- [x] Root-level pushed route `/edit-note/:noteId` (top of the shell, like `/tasks/:taskId`)
- [x] Overview Create/Edit README uses `context.push('/edit-note/…')` — never `go('/notes/…')`
- [x] Notes list: default EXCLUDES readme notes; new 'READMEs' chip lists ONLY them
- [x] Project detail Notes tab hides the project's own README
- [x] API: `GET /workspaces/:id/notes` gains `readme` filter (default exclude / `true` = only)

Acceptance notes: new root route `/edit-note/:noteId` (sibling of
`/tasks/:taskId`); the Overview create-flow and pencil `context.push` it, so it
opens full-screen and back pops to the Overview (whose README card live-refreshes)
instead of switching to the Notes branch. The editor's delete now pops when it
can (falls back to `/notes`), so both entry points behave. Which notes are
READMEs = ids referenced by any project's `readmeNoteId`: `note_store.watchList`
combines the notes stream with a `_readmeNoteIds` stream over `projects` —
all/pinned/archived exclude READMEs, the new `NotesFilter.readmes` ('READMEs'
chip) lists only them; `watchForProject` additionally drops the project's own
README. API parity: `readme` bool on the list querystring, implemented with two
cheap queries + `whereIn`/`whereNotIn` (fakedb gained `whereNotIn`). Tests: API
unit (exclude default / only with `readme=true`) + app widget (README hidden
under All, shown under READMEs; create-README pushes the editor and pops back).
analyze + lint clean; app 225/225, API 210/210. ✔

**User's report (item 12):** creating a README from a project's Overview dumped him into the
Notes tab — it must stay on the project's Overview. README notes must not pollute the notes
list either; only an explicit filter should reveal them.

**Verified today:** `_OverviewTab._createReadme` (project_detail_screen.dart) creates the
note, sets `readmeNoteId`, then `context.go('/notes/$noteId')` — a BRANCH SWITCH; the Edit
pencil does the same. The notes list has no notion of "readme".

**Spec:**

1. **Routing:** add `GoRoute(path: '/edit-note/:noteId')` at the ROOT level (same tier as
   `/tasks/:taskId`) building `NoteEditorScreen(noteId: …)`. Overview's create flow ends
   with `context.push('/edit-note/$noteId')`; the pencil likewise. Back pops to Overview,
   whose README card live-updates (it already watches the note). Verify the editor's own
   pop/delete paths behave when pushed outside the Notes branch (it must `pop` — not
   `go('/notes')`).
2. **Which notes are READMEs:** exactly those referenced by any project's `readmeNoteId`
   (no schema change). App side: `note_store.watchList` combines the notes stream with a
   watch over `projects.readmeNoteId` (drift join or two-stream combine) exposing
   `isReadme` per row; `NotesFilter.all/pinned/archived` exclude them; new
   `NotesFilter.readmes` chip ('READMEs') lists ONLY them, rows showing the owning
   project's color dot + name. `watchProjectNotes` additionally excludes THAT project's
   own readme (it lives in Overview).
3. **API parity (apps/api/src/routes/notes.js):** `readme` boolean in the list
   querystring — absent/false ⇒ exclude readme notes, `true` ⇒ only readme notes.
   Implementation note: fetch the workspace's non-null `readme_note_id`s first and use
   `whereIn`/`whereNotIn` with the id list (two cheap queries) — keeps the unit fakedb
   viable and avoids subquery support questions. Document the param in the route schema.
4. Deleting a project or clearing `readmeNoteId` naturally returns the note to the default
   list (it is derived state — assert in a test rather than "handling" it).

**Tests:** app — create-readme keeps the router location inside `/projects/:id` (assert via
`GoRouter.of` location) and pushes the editor; notes list default hides the readme; READMEs
chip shows it with the project dot; project Notes tab hides its own readme but still shows
other project notes. API unit — `readme` filter both ways + schema validation; existing
list tests untouched.

**DoD:** analyze + `flutter test`; `npm test`; light + dark; manual: create README on web,
land back on Overview.

### OPH-110 — Project archiving with an optional cascade ✅

- [x] API: `POST /projects/:projectId/archive` + `/unarchive` with
      `{includeTasks?, includeNotes?}` — one transaction, every write revisioned
- [x] Archive cascade reuses the task status side-effect path (reminders die/revive
      correctly)
- [x] App: archive/unarchive dialogs with live counts; Projects list hides archived by
      default + 'Archived' chip; detail banner + Unarchive
- [x] Edit sheet no longer offers bare 'archived' in its status dropdown
- [x] Pickers exclude archived projects (OPH-106 wrote the filter; verify end-to-end)

Acceptance notes: server `POST /projects/:id/archive` + `/unarchive` (member-
allowed — reversible) run ONE transaction: project status via `recordSyncWrite`,
then, per the flags, the project's non-terminal tasks → `archived`/`open` EACH
through `reconcileTaskReminder` (so the reminder deactivates on archive and
re-arms on unarchive — never a bare column write) and its notes' `is_archived`
flipped; response `{project, tasksChanged, notesChanged}`, idempotent (project
write skipped if already in target). Unarchive's documented simplification:
cascade restores ALL archived tasks/notes (dialog says so). App: the controller
does a plain optimistic status flip when both boxes are off (works offline) and
hits REST + `syncNow()` for a cascade (needs a connection → inline error). UI:
Active/Archived chips on the list (archived hidden by default), a per-row menu
(Edit / Archive… / Unarchive…), a live-count dialog, and an archived-detail
banner + Unarchive. The edit sheet dropped 'archived' from its status options
(archiving only via the dedicated flow; an already-archived value is still shown
so it isn't lost). Tests: API unit (default vs cascade counts, reminder
deactivate+revive, idempotent re-archive, member role) + app widgets (archive
moves it behind the Archived chip with an Unarchive action; edit sheet has no
'archived'). **Integration test skipped deliberately:** no new schema and the
`recordSyncWrite`-in-transaction pattern is already integration-covered (subtree
delete / PATCH); the cascade logic is exhaustively unit-tested. analyze + eslint
clean; app 227/227, API 215/215. ✔

**User's report (item 13):** no way to archive a project. Archiving must ask whether to also
archive the project's tasks and notes; archived things must disappear from normal views and
only show in an archive view; unarchiving must ask the mirrored question. "This needs to be
designed well — write a detailed task."

**Verified foundation (no migration needed):** `projects.status` enum already contains
`archived` (migration 20260714000200); drift `Projects.status` exists; sync
`PROJECT_FIELDS.status` and REST PATCH both accept it. What's missing is the FLOW: cascade,
default-hidden lists, and honest dialogs. Note: `project_edit_sheet.dart` currently offers
'archived' as a plain dropdown status — REMOVE it there (`kProjectStatuses` in the sheet →
active/paused/completed); archiving goes through the dedicated flow so the cascade question
is never skipped. (Server keeps accepting the value — v1 clients/API users may set it; only
the app UI funnels.)

**Server spec (apps/api/src/routes/projects.js):**

- `POST /projects/:projectId/archive` body `{includeTasks?: bool=false, includeNotes?:
  bool=false}` (Ajv), member-allowed (reversible — parity with PATCH, not with delete).
  In ONE transaction: project → `status='archived'` via the existing revisioned write
  path; if `includeTasks`, every task of the project with status IN
  inbox/open/scheduled/in_progress/waiting → `status='archived'`, EACH going through the
  same status side-effect helper PATCH uses (tasks.js "Status side effects") so reminders
  deactivate — never a bare column update; completed/cancelled/archived tasks untouched.
  If `includeNotes`, notes of the project with `is_archived=false` → `true`, revisioned.
  Response `{project, tasksChanged, notesChanged}`. Archiving an archived project: 200,
  zero changes (idempotent).
- `POST /projects/:projectId/unarchive` mirrors: project → `active`; `includeTasks` →
  the project's `archived` tasks → `open` (side-effect path revives reminders; past
  `remind_at` reconciles like any past reminder); `includeNotes` → `is_archived=false`.
  **Documented simplification:** unarchive-with-cascade restores ALL archived
  tasks/notes of the project, including ones archived individually beforehand — tracking
  "which ones the cascade touched" needs new columns; v1 chooses the simple symmetric
  rule and the dialog copy says so.
- Every entity write = `recordSyncWrite` in the same trx (existing pattern from the
  subtree delete) so replicas converge; workspace revision bumps once per row (gapless
  guarantee already proven in OPH-050).

**App spec:**

- **Two write paths, both honest about offline:** plain archive/unarchive with BOTH
  checkboxes off = `projectStore.update(id, {'status': …})` → optimistic + outbox (works
  offline). Any cascade = the REST endpoint via the authenticated dio (multi-entity
  transactions cannot be one outbox mutation); offline → `AwInlineError`/snackbar
  "Archiving with its tasks/notes needs a connection." and nothing changes locally
  (replica converges from the pull after the call succeeds).
- **Entry points:** overflow menu on each Projects row + project detail app-bar menu:
  'Archive project…' opens a dialog — body explains the effect, two checkboxes with LIVE
  counts from the replica: 'Also archive its open tasks (N)' / 'Also archive its notes
  (M)'; confirm = error-styled `FilledButton`? No — archive is reversible: primary
  FilledButton, destructive styling reserved for delete (DESIGN §4 Dialogs). Unarchive
  mirrors with counts of archived items + the "restores ALL archived" caveat line.
- **Lists:** `project_store.watchAll` keeps returning everything; the projects screen
  filters — default view = status != archived; a ChoiceChip row (pattern: notes chips)
  All/Archived; archived rows carry an `archive_outlined` marker and their menu offers
  Unarchive. Project DETAIL of an archived project: banner 'This project is archived' +
  Unarchive button (content stays readable; edits stay possible — server allows them).
- **Ripples:** Home shows tasks of a non-cascaded archived project (their status is
  untouched — user's explicit choice); pickers exclude archived projects (OPH-106);
  project badge (OPH-104) still renders name+color for them.

**Tests:** API unit (fakedb) — archive with/without each flag (counts, statuses, notes),
reminder deactivation on cascaded tasks + revival on unarchive, idempotent re-archive,
member role allowed, response shape; integration — one full cascade + unarchive round on
real MySQL (revisions strictly increase, replica-visible rows via /sync/pull). App —
default list hides archived, chip shows them, dialog counts match seeded replica, offline
cascade shows the error and leaves state untouched, plain archive works offline through
the outbox, detail banner + unarchive flow.

**DoD:** analyze + `flutter test`; `npm test` + `npm run test:integration`; light + dark;
CHANGELOG + BLUEPRINT §4.2 kept truthful.

### OPH-111 — Onboarding: welcome + feature tour (skippable, replayable) ✅

- [x] Hand-rolled tour overlay (NO new package): welcome card → spotlight steps over the
      nav destinations (+ quick-add, FAB, Settings) with Next/dots/Skip
- [x] Auto-runs once per device after first sign-in (`alliswell_onboarding_seen_v1` via
      `localKv`); Settings gains 'App tour' to replay
- [x] Adapts to narrow (bottom bar) and wide (rail) anchors; resize mid-tour degrades
      gracefully
- [x] A11y: semantics, focus, ESC/back = skip, AwMotion.fast fades only

Acceptance notes: `features/onboarding/` — `tour.dart` (pure `kTourSteps`:
welcome → one step per nav section → farewell; a `TourController` Notifier with
`maybeAutoStart`/`next`/`skip`/`finish`) and `tour_overlay.dart` (a CustomPaint
scrim with a spotlight cut-out over the anchor + a SOLID bubble card — glass
stays chrome-only, G1 — with title, body, step dots, Next/Done, and a
persistent Skip). `HomeShell` owns stable `GlobalKey`s on the bottom bar / rail
and computes the anchor rect (a per-destination slice on phones, the whole rail
on wide — its items sit near the top so a slice would mislead); a post-frame
`maybeAutoStart` fires once. Persistence: `kOnboardingSeenKey` via `localKv`,
set on skip AND finish; Settings gains an 'App tour' tile that replays it.
**Test safety (the key risk):** the overlay would cover every full-app widget
test, so `tourAutoStartProvider` (default true) is overridden to false in
`syncTestOverrides` — the tour never auto-fires under test unless a test opts in
with `tourAutoStart: true`. A11y: a `Semantics` region announces "step i of n",
`PopScope` maps system-back/ESC to Skip, `AwMotion.fast` fades only.
**Scope notes (deliberate):** the spotlight walks the 5 nav destinations (the
"introduce the bottom menu" ask); quick-add / FAB / Settings are called out in
the step copy rather than separately anchored. A mid-tour layout-class change
degrades to a centered bubble (graceful) rather than an explicit tour-end.
Manual device run deferred — the dev systems were shut down at the user's
request; both layouts are widget-tested instead. Tests
(`test/features/onboarding/tour_test.dart`, 9): script shape, next/skip/finish
persistence, auto-start gating (disabled / already-seen), and widget flows
(auto-start + Skip, full Next-walk, phone bottom-bar anchors, no-start when
seen). `flutter analyze` clean; app suite **236/236**. ✔

**User's report (item 4):** there must be an onboarding introducing every feature — what it
is, how it's used. Even if skippable (top-right), the bottom menu must be walked item by
item with the rest dimmed and a bubble explaining each simply. Settings must let the user
re-watch the guide. "There are lots of features and nobody knows what anything is."

**Spec (BLUEPRINT §12.7 is the binding wording):**

- **Structure:** `features/onboarding/` — `tour_steps.dart` (PURE list of steps per layout:
  id, anchor key, title, body — reuses/extends `AppSection.description` copy so tooltips
  and tour never drift), `tour_controller.dart` (Riverpod Notifier: idle → step i → done;
  exposes start/next/skip), `tour_overlay.dart` (an `Overlay`/`Stack` layer inside
  `HomeShell`: veil-dimmed backdrop with a cut-out or highlight pill on the anchored
  widget, plus a SOLID bubble card — glass stays chrome-only, G1 — with icon, title, 2-line
  body, step dots, Next/Done, and a persistent 'Skip tour' in the top-right).
- **Anchors:** `HomeShell` exposes `GlobalKey`s for each destination (bar item on narrow,
  rail destination on wide) + the Home quick-add, the FAB, and the Settings gear. Steps
  whose anchor is absent (e.g. FAB while another tab is fronted) either navigate first
  (tour switches branch via `_goBranch` before highlighting — acceptable) or are skipped;
  pick ONE behavior and test it. On `MediaQuery` size flips mid-tour, re-resolve anchors;
  if the layout class changed, end the tour quietly (state stays 'seen').
- **Content (7 steps max):** Home (chronological view, 30-day horizon), Inbox (capture —
  OPH-107 copy), Calendar (your month + external events), Projects (colors, README
  overview), Notes (rich notes, pin/archive), quick-add vs FAB (serial capture vs full
  form), Settings (calendar connect, notifications, replay this tour).
- **Trigger:** after the first successful session restore/sign-in AND Home's first frame
  (post-frame callback in `HomeShell` when the flag is unset). Never during widget tests
  unless opted in — tests get the flag pre-set through the existing overrides support
  (extend `test/support/sync_overrides.dart` so EVERY current widget test keeps passing
  untouched).
- **Persistence:** `PersistedToggle('alliswell_onboarding_seen_v1', fallback: false)` —
  set true on skip AND on finish. Settings tile 'App tour' (help icon) calls
  `tourController.start()` directly (does not clear the flag).
- **A11y/quality:** every bubble is a `Semantics` region announcing "step i of n"; back
  button/ESC = skip; tap outside advances nothing (explicit buttons only); text/tokens
  meet G2 (bubble = solid surface, veil ≥ scrim contrast); animations `AwMotion.fast`
  fades only.

**Tests:** unit — steps list per layout (anchors defined, copy non-empty, ≤7); controller
transitions incl. skip-at-step-3. Widget — flag unset → welcome shows after pump; Skip →
flag persisted true and overlay gone; full Next-walk ends the tour and persists; Settings
tile relaunches with the flag already true; narrow AND wide runs (two `MediaQuery` sizes);
existing suite stays green with the flag pre-set.

**DoD:** analyze + tests; light + dark; manual run on web (wide) + iOS sim (narrow);
BLUEPRINT §12.7 stays truthful.

---

## Epic 11 — Localization (i18n) (Phase 7, v0.2.0)

> **Source:** feedback round 5 (2026-07-17, Mahir) — "tüm hardcoded string'leri çıkar, JSON dil
> mekanizması ekle; cihaz TR ise ve tr.json varsa Türkçe açılsın, fallback en.json; ayarlardan
> kalıcı dil değişimi; web'de tarayıcı diline göre." Binding spec: BLUEPRINT §12.9 + §15.5,
> [ADR-0009](adr/0009-localization-i18n-architecture.md), DESIGN §9. **When a task below and those
> disagree, the spec sections win.**
>
> **This epic ships BEFORE Epic 12 (widgets) on purpose:** the widget snapshot (OPH-130) writes
> ALREADY-LOCALIZED bucket/date labels, so i18n must exist first. (If Mahir wants widgets first,
> the two epics just swap — nothing else changes.)
>
> Every task follows AGENTS.md §2/§3: tests + docs + `flutter analyze` clean; UI tasks check both
> themes. Work strictly top-to-bottom.

### OPH-120 — i18n foundation & wiring ✅

- [x] `flutter_localizations` (SDK) added; `assets/i18n/` registered; `assets/i18n/en.json` +
      `tr.json` seeded with the `common.*` set + `app.*`.
- [x] `main.dart`: `WidgetsFlutterBinding.ensureInitialized()` + `await AwI18n.instance.boot()`
      before `runApp` (loads the persisted/device locale + fallback synchronously).
- [x] `app.dart`: `ListenableBuilder(listenable: AwI18n.instance)` wraps `MaterialApp.router`;
      `locale: AwI18n.instance.locale`, `supportedLocales: awSupportedLocales`, delegates =
      Global{Material,Widgets,Cupertino}Localizations + `FlutterQuillLocalizations`.
- [x] `lib/src/i18n/i18n.dart` — the `AwI18n` synchronous store + `String.tr()`; nothing else
      touches the engine (one seam, ADR-0009 D2).
- [x] `test/flutter_test_config.dart` bootstraps the store off disk so `.tr()` resolves under a
      plain `pumpAndSettle`.

Acceptance notes: **deviation from the specced `easy_localization` — replaced it
with an app-owned SYNCHRONOUS store (ADR-0009 revised).** easy_localization was
implemented first and reverted: its `LocalizationsDelegate` loads translations
asynchronously, and under flutter_test's fake-async clock that load never
completes during `pumpAndSettle`, so the `Localizations` widget blocked the whole
app subtree — ~40 full-app tests rendered nothing, and `.tr()` returned raw keys.
The fix (`AwI18n`, ~180 lines, unit-tested) reads the JSON into memory before
`runApp` (`boot()`), so `'key'.tr()` is a synchronous map lookup at build time.
Device/browser detection (`PlatformDispatcher.instance.locales` → first supported
→ `en`; `resolveInitialLocale` pure + tested), persisted override via `localKv`,
per-key fallback to `en`, `{name}` interpolation, and runtime switch via a
`ChangeNotifier` + `ListenableBuilder` (the `MaterialApp` is built INSIDE the
builder — a const child would not rebuild on locale change; that was a real bug
caught by a test). Tests: `test/i18n/i18n_test.dart` (11) — `resolveInitialLocale`
cases, en/tr resolution, en-fallback for a tr-missing key, unknown-key
passthrough, `{name}` args, and two widget tests proving `.tr()` renders and a
language switch rebuilds — all with plain `pumpAndSettle`, no `runAsync`. **Full
suite 247/247 (236 existing untouched + 11), `flutter analyze` clean.** ✔

**Context:** there was NO i18n; `app.dart` wired only Quill's delegates. `users.locale` exists but
nothing read it. This task stood up the engine + the one-seam indirection.

**DoD:** `flutter analyze` + `flutter test` green; app boots (device/en); no visual change yet
(strings convert in OPH-122+). ✔

### OPH-121 — Language picker in Settings + persistence ✅

- [x] Settings → **"Language"** `ListTile` (after "App tour") opens a modal bottom sheet: **System
      default** + every `awSupportedLocales` entry by its endonym (`awLanguageEndonyms`), current
      choice checkmarked. Subtitle shows the active language / "System default".
- [x] Runtime switch via `AwI18n.instance.setLocale(...)` (no restart — the app-level
      `ListenableBuilder` rebuilds); **System default** → `AwI18n.instance.useSystemLocale()`.
- [x] Persists to localKv (`alliswell_locale`); `boot()` restores it over the device locale.

Acceptance notes: language-picker UX researched (endonyms, System-default with
device detection, no flags, check on current — matches SimpleLocalize/Smashing
guidance). Endonyms are constants (`awLanguageEndonyms`, NOT translated) so a user
stuck in an unreadable language finds their own; "Language"/"System default" ARE
localized (`settings.language.*` keys — added to en+tr now, the rest of Settings
extracts in OPH-122). The sheet uses the central DESIGN bottom-sheet theme
(drag handle, solid surface). Tests (`test/features/settings/language_test.dart`,
5): setLocale switches + persists; useSystemLocale clears; boot restores a
persisted override; and two widget tests driving the real sheet — tapping
`language-tr` sets the tr override, tapping `language-system` clears it (both hit
the cached locale so they resolve under a plain `pumpAndSettle`). **Full suite
252/252, analyze clean.** Light/dark + web visual pass folded into the epic's
demo round. ✔

**Context:** `settings_screen.dart` is a plain `Card`/`ListTile` list — added the row + a
`showLanguagePicker` sheet using DESIGN components.

**DoD:** analyze + test ✔; both themes via the central sheet theme; row matches DESIGN.

### OPH-122 — Extract strings: auth, shell, settings, shared states ✅

- [x] Moved to `en`+`tr` keys: login/register (`auth.*`), nav labels + descriptions
      (`sections.dart` → `nav.*`, now localized getters), section app-bar titles, all
      `settings_screen.dart` rows (`settings.*`), FAB tooltips + Settings tooltip (`shell.*`), and
      `AwErrorState` (`state.somethingWrong` + `common.retry`).
- [x] Existing widget tests untouched (English values kept identical, so `find.text('Home')` still
      matches); every `Key('…')` preserved.

Acceptance notes: the extraction keeps each **English value byte-identical** to
the old literal, so all 236 pre-existing tests pass with ZERO changes — the
cleanest possible sweep. `AppSection.title`/`description` became localized getters
(the enum stores `nav.*` keys); this flows to both the nav bar/rail AND the
onboarding tour for free. `const` was dropped only where a `.tr()` moved into a
formerly-const widget. New test `test/i18n/extraction_test.dart` (4) proves the
labels actually flip: `AppSection.home.title` → "Home"/"Ana Sayfa",
`AwErrorState` → "Something went wrong"/"Bir şeyler ters gitti" + "Retry"/"Tekrar
dene". **Full suite 256/256, analyze clean.** (Auth error MESSAGES —
`friendlyAuthMessage` — stay for OPH-125 with the other error-code mapping.) ✔

**Context:** the chrome layer — `features/auth/ui/*`, `sections.dart`, `screens/settings_screen.dart`,
`screens/home_shell.dart`, `widgets/status_views.dart`, + the 3 section-screen app-bar titles.

**DoD:** analyze + test ✔; English parity kept; `tr` renders (extraction_test).

### OPH-123 — Extract strings: Home, tasks, quick-add, task create/detail ✅

- [x] `HomeBucketLabel` → `'home.bucket.$name'.tr()` (widget snapshot reuses these); status/
      priority → `taskStatusLabel`/`taskPriorityLabel` helpers (`task.status.*`/`task.priority.*`,
      used by the `StatusLabel`/`PriorityLabel` dropdown chips); Home empty-state + quick-add hints
      (interpolated day); task create sheet, task detail (all fields, tags, checklist, calendar
      toggle), task tile (overdue/due, semantics), and the Inbox capture screen; task snackbars.
- [x] Dates localized via `intl` (`DateFormat.MMMd(locale)`; `initializeDateFormatting()` in
      `main()` + test bootstrap) — **English renders byte-identically** to the old format.

Acceptance notes: the largest sweep — 8 UI files + `intl`. Every ENGLISH value
kept identical, so all pre-existing tests pass unchanged. `HomeBucket.label` is
now `'home.bucket.$name'.tr()` (enum-name keys) so the **widget snapshot (OPH-130)
reuses the exact same strings**. Status/priority got `taskStatusLabel`/
`taskPriorityLabel` helpers — a nice side-fix, since the dropdowns previously
showed the RAW enum value (`in_progress`) and now show proper localized names.
`intl` added as a direct dep; `DateFormat.MMMd` gives "Jul 15" (en, unchanged) /
"15 Tem" (tr). Snackbar error strings dropped the raw `$e` (cleaner UX; `catch (_)`).
New keys: `home.*`, `task.*`, `inbox.*`. Tests: `extraction_test.dart` +2 (bucket
labels + status/priority flip en↔tr). **Full suite 258/258, analyze clean.** ✔

**Context:** the largest surface — `features/home/*`, `features/tasks/ui/*` (grouping, tile,
quick-add, create sheet, detail, list/Inbox), `task_visuals.dart`.

**DoD:** analyze + test ✔; English parity kept; `tr` renders; dates locale-aware.

### OPH-124 — Extract strings: projects, notes, calendar/integrations, onboarding ✅

- [x] Moved to `en`+`tr` keys: project detail/edit/archive/picker/list, notes list/editor, Google
      & Apple calendar cards + external-event tile, and the onboarding tour.
- [x] `AppSection` (already) + `TourStep` enums store i18n keys with localized `title`/`description`
      getters; `groupTasksForHome` labels already keyed in OPH-123.

Acceptance notes: ~145 strings across ~13 files, extracted by **3 parallel
subagents** (projects 62, calendar 39, notes+onboarding ~40) reading the keys I
pre-seeded in `assets/i18n/{en,tr}.json` — each keeping the English value
IDENTICAL so the existing suite passed unchanged. I handled the 6 leftovers that
needed NEW keys (`project.deleteBody`/`color`/`archivedName`, `note.filterReadmes`/
`emptyPreview`) and converted `TourStep` to key+getter. Tests
(`test/i18n/extraction_test.dart`): tour steps localize, project/note/calendar
keys resolve in both languages, `{name}` args fill. **Suite 264/264, analyze
clean, JSON parity verified (only `common.help` is en-only, by design).** ✔

### OPH-125 — Localize API error codes & dynamic strings ✅

- [x] `friendlyAuthMessage` + `home_shell._conflictMessage` localized; `error.*` + `sync.*` keys
      seeded (auth codes, network, sync conflict).
- [x] `localizedError(Object)` helper (`core/error_messages.dart`) maps `ApiException.code →
      error.<CODE>`, falling back to the server message then `error.unknown`; the 6 `AwErrorState`
      `'$error'` sites now use it. Dates were made locale-aware in OPH-123.

Acceptance notes: added `AwI18n.maybeTranslate` (null on miss) so `localizedError`
can fall back past the raw key. Tests: a code renders its localized message
(en+tr), an untranslated code falls back to the server message, a non-ApiException
→ generic. The API stays language-neutral (codes only). ✔

### OPH-126 — Account locale sync (`PATCH /me`) ✅ (API + app push; pull deferred)

- [x] **API:** `PATCH /api/v1/me { locale }` — `app.authenticate`-guarded, updates `users.locale`
      + `updated_at`, returns the shared `loadMe` shape.
- [x] **App:** `accountLocaleSyncProvider` best-effort `PATCH`es the picked locale (fire-and-forget,
      no-op signed out) from the Settings picker.

Acceptance notes: **deviation — the body is FORMAT-validated (`^[a-z]{2}(-[A-Za-z]{2,4})?$`),
not pinned to a fixed allow-list with `USER_UNSUPPORTED_LOCALE`.** A malformed
locale is a 400; a well-formed unknown one is accepted. Rationale: a fixed
allow-list would couple the API to the app's shipped languages and break the
"add a language = drop a JSON" model (ADR-0009). **Deferred: seeding the app FROM
`users.locale` on sign-in** — the app has no `/me` fetch flow, so this is a
follow-up (the device override is the source of truth regardless). Tests: 4 API
(`auth-me.test.js`) — update+persist, region variant, malformed→400, unauth→401.
**API 219/219, app 264/264.** ✔

### OPH-127 — No-hardcoded-string CI guard ✅

- [x] `scripts/i18n/check.mjs` flags user-facing `Text('…')` / `labelText:`/`hintText:`/`tooltip:`/
      `semanticLabel:` literals outside an allowlist (`.tr(`, brand, `// i18n-ignore`).
- [x] `npm run check:i18n` + a CI step next to `check:no-ts`.

Acceptance notes: self-tested (a planted `Text('…')` fails it, the clean tree
passes). Running it **found the only 2 stragglers the extraction missed** —
`month_calendar.dart`'s "Previous/Next month" tooltips — now keyed
(`calendar.previousMonth/nextMonth`). Guard green on the whole tree. ✔

### OPH-128 — Web `<html lang>` + "add a language" docs ✅

- [x] `html_lang_stub.dart` + `html_lang_web.dart` (conditional import on `dart.library.js_interop`,
      `package:web`) set `<html lang>` from `AwI18n._apply`; `web/index.html` defaults `lang="en"`.
- [x] "Adding a language" in README + CONTRIBUTING (copy `en.json` → `<code>.json`, register the
      `Locale` + endonym); `check:i18n` command documented.

Acceptance notes: `setHtmlLang` is a no-op off-web (stub). **Epic 11 (i18n) CLOSES
here → v0.2.0-alpha.** All UI (auth, nav, Home, tasks, projects, notes, calendar
cards, onboarding, settings, errors) is EN+TR; adding a language is a JSON drop.
✔

---

## Epic 12 — Home-screen / desktop widgets (Phase 7, v0.2.0)

> **Source:** feedback round 5 (2026-07-17, Mahir) — iOS/Android/macOS widgets in **4×2 / 4×4 /
> 4×6** sizes that (A) stay in sync with tasks, (B) summarize Home's buckets (geçmiş/nodate/bugün/
> bu hafta/bu ay) in a scroll, (C) carry an Apple-Calendar-style date header at the largest size,
> and (D) allow quick-add + quick-complete like the Apple Reminders widget. Binding plan:
> [WIDGETS.md](WIDGETS.md) + [ADR-0010](adr/0010-home-screen-widgets-architecture.md); visual spec
> DESIGN §8; product spec BLUEPRINT §12.8 + §15.6. **When a task and those disagree, they win.**
>
> **User item → task:** A(sync)→OPH-130/131/133 · B(bucketed scroll)→OPH-130 · C(date header,
> largest)→OPH-131/133/134 · D(quick add/complete)→OPH-132/133.
>
> **HARD platform constraint (dokümante edilmiş revizyon):** iPhone'da **4×6 / tam-ekran widget
> YOKTUR** — WidgetKit'in iPhone için en büyük boyutu `systemLarge` (4×4). "4×6/full" tier'ı
> iPad/macOS'ta `systemExtraLarge`, Android'de gerçek 4×6 olarak verilir; iPhone'da `systemLarge`'a
> iner (WIDGETS.md §2, ADR-0010 D6). Bu kapsam kesintisi değil, platform sınırıdır.
>
> **DEPENDS ON Epic 11** (localized snapshot labels). **Native reality:** `flutter analyze` +
> `flutter test` compile NO Swift/Kotlin — every native task is proven only by a real `flutter
> build ios`/`apk`/`macos` + a device/simulator pass, recorded in STATE (the EventKit lesson).

### OPH-130 — Widget snapshot core (Dart: pure grouping + bridge) ✅

- [x] `home_widget ^0.9.0` (resolved 0.9.3); new `lib/src/features/widgets/`.
- [x] Pure `groupTasksForWidget(tasks, {now})` — buckets **overdue → noDate → today → thisWeek →
      thisMonth**, rolling 30-day horizon (`kWidgetHorizonDays`). Tasks-only (the calendar header
      covers the date). Fully unit-tested.
- [x] `WidgetSnapshot` serializer → the compact JSON of WIDGETS.md §3.1 (`v`, `generatedAt`,
      `locale`, `date{weekday,day,month}`, `buckets[]` with `label`/`count`/top-N
      `items{id,title,done,priority,time,projectColor}`/`more`). Labels via `widget.bucket.*`.tr()
      (already localized); dates via `intl` in the active locale.
- [x] `WidgetHost` seam (over `home_widget`) + `WidgetBridge.publish` (configure→save→update) +
      `widgetSyncProvider` (republishes on open-task/project change, self-disables off iOS/Android/
      macOS), watched by `HomeShell`.

Acceptance notes: the snapshot is tasks-only (deviation from the plan's "events"
mention — the widget is a task glance; the date header carries the calendar
aspect, C). The bridge is behind a `WidgetHost` abstraction so it's unit-tested
with a `FakeWidgetHost` (no platform channels) — also added to `syncTestOverrides`
so the full-app suite doesn't hit `home_widget`. Tests
(`test/features/widgets/widget_core_test.dart`, 6): bucket boundaries + the +30
drop; snapshot shape, en/tr labels + localized date header (Friday/Cuma,
July/Temmuz), top-N truncation with `more`, project color + done flag; bridge
configures-once/saves-JSON/updates, and re-updates on a second publish. **Suite
270/270, analyze + check:i18n clean.** No native code yet (OPH-131+).

**DoD:** `flutter analyze` + `flutter test` (all green, no infra). ✔

### OPH-131 — iOS Widget Extension: target, App Group, rendering, deep-link floor

- [x] **Swift written** (`ios/AllisWellWidget/AllisWellWidget.swift`): `AWSnapshot` Codable model
      mirroring the OPH-130 JSON, `AWProvider` `TimelineProvider` reading the App-Group
      `UserDefaults(suiteName:)` with a **midnight-rollover** `.after` policy, SwiftUI views —
      date header (weekday + big day number) on large/xl, bucketed rows with a circular checkbox,
      priority dot, time and project color, per-size row budget — `supportedFamilies:
      [.systemMedium, .systemLarge, .systemExtraLarge]`, `.containerBackground` behind
      `if #available(iOS 17)`, `.widgetURL(alliswell://open)`.
- [x] Extension `Info.plist` + `AllisWellWidget.entitlements` (App Group) written.
- [x] **USER (Xcode, once) — DONE 2026-07-24:** Widget Extension target created + files added + App
      Groups on Runner + extension (31 refs in `project.pbxproj`). Step-by-step:
      [ios/AllisWellWidget/SETUP.md](../apps/app/ios/AllisWellWidget/SETUP.md).
- [x] **Verified on device 2026-07-24:** the widget renders and updates. (iOS signing moved to the
      APILLON team `WWRZ5CG3DW`.)

**Context:** ADR-0010 D6 size mapping; iPhone ceiling = `systemLarge`. `analyze` won't compile
Swift — creating the Xcode target + the device pass is a GUI/hardware step that can't run here, so
the Swift is written as a ready-to-integrate package (NOT yet in `project.pbxproj`, so the app
still builds) and handed off via SETUP.md. The `alliswell://` deep-link ROUTING (so a tap lands on
the right screen) is deferred to OPH-132/135 — for now the tap opens the app.

**Tests:** data path covered by OPH-130's Dart tests; native verified by `flutter build ios` +
device: light+dark, medium/large on iPhone, extraLarge on iPad.

**DoD:** `flutter build ios` green; device screenshots (both themes, all sizes); STATE device note;
WIDGETS.md/ DESIGN §8 truthful. **Status: Swift + setup handed off; awaiting the Xcode target +
device pass.**

### OPH-132 — iOS interactivity: quick-complete + quick-add (App Intents)

> **Superseded 2026-07-28 by [OPH-188](#oph-188--widgettan-tamamlama-ios-app-intents--android-geri-çağırma-round-10-4c--cihaz)**
> (feedback round 10 #4C — the user hit exactly this gap on the device). Round 9's
> OPH-182 has since built the reusable pieces this task was missing: shared App Intents
> compiled into **both** targets (`ios/Shared/AWAlarmShared.swift`) and an App Group
> action queue that survives a cold app (`AWAlarmActionQueue` + `drainPendingActions`).
> Do the work there; this box stays for history.

- [ ] iOS 17+ `Button(intent:)` / `Toggle(isOn:intent:)` + a shared `AppIntent` that is a member of
      **BOTH** the Runner and Widget Extension targets → `HomeWidgetBackgroundWorker.run(url:
      appGroup:)` (`alliswell://complete?id=…` / `alliswell://add`).
- [ ] Dart `@pragma('vm:entry-point')` `widgetCallback(Uri?)` → `TaskStore.complete()` /
      `TaskStore.create()` (the SAME optimistic + outbox path the UI uses → syncs to server) →
      `HomeWidget.updateWidget(...)`; `HomeWidget.registerInteractivityCallback(widgetCallback)` in
      `main()`.
- [ ] Gate interactive code `@available(iOS 17, *)`; iOS 16 keeps the deep-link path (OPH-131).
      Circular checkbox completes in place and the row animates away after ~1–2 s; **generous hit
      target** (Reminders UX lesson, DESIGN W4).

**Context:** user item D; ADR-0010 D4. App-intent reloads are budget-exempt (free sync).

**Tests:** the Dart `widgetCallback` (`complete`/`add`) against a fake `TaskStore` (optimistic row +
outbox enqueued); device pass on iOS 17+ — complete + add from the widget **without opening the
app**, and confirm the change syncs (appears on another surface).

**DoD:** `flutter build ios`; device: offline complete + quick-add both work and sync; STATE note.

### OPH-133 — Android widget: rendering compile-verified 🟡 (interactivity + device pending)

- [x] `TasksWidgetProvider : HomeWidgetProvider` + `TasksWidgetService`/`TasksRemoteViewsFactory`
      under `android/app/src/main/kotlin/com/alliswell/alliswell/`; reads the `home_widget`
      SharedPreferences snapshot; **scrollable bucketed list** (RemoteViews `ListView` collection —
      bucket section headers + `○`/`●` check, project-color dot, title, time); localized empty state.
- [x] `res/xml/tasks_widget_info.xml` (`targetCellWidth/Height` 4×2 default, `resizeMode`,
      `minResize*`/`maxResize*` for a **true 4×6**), `res/layout/*`, `res/values(-night)/colors.xml`
      (light+dark, DESIGN §3.1), manifest receiver + service.
- [x] **Tap → opens the app** via `HomeWidgetLaunchIntent` (`alliswell://open`) — deep-link floor.
- [x] **Verified a real `flutter build apk`** (Kotlin + resources + manifest compile + link).
- [ ] **Interactivity** (tap-to-complete / quick-add without opening the app) — `actionRunCallback`/
      `HomeWidgetBackgroundIntent` → the Dart `widgetCallback` → `TaskStore` — **moved to
      [OPH-188](#oph-188--widgettan-tamamlama-ios-app-intents--android-geri-çağırma-round-10-4c--cihaz)**
      (round 10 #4C). Prerequisite found there: `TasksRemoteViewsFactory`'s `Row` record
      **drops the task id**, so today no per-row action or per-row deep link is even possible.
- [ ] **WorkManager** midnight re-push — DEFERRED (the app's foreground push covers the common case).
- [x] **Device visual pass — DONE 2026-07-24:** verified on a real Android device (Blocker 3). The
      remaining `[ ]` above (interactivity + WorkManager) rides OPH-132's shared background isolate.

Acceptance notes: **deviation — RemoteViews collection, not Jetpack Glance.** Glance pulls a heavy
Compose dependency and is harder to compile-verify without a device; a `ListView` +
`RemoteViewsService`/`RemoteViewsFactory` is the classic scrollable widget, compiles clean, and is
lower-risk. Reconsider Glance if we add richer interactivity. The rendering + tap-to-open path is
**build-verified** (`flutter build apk` green, only a benign KGP-deprecation warning from
home_widget/quill); the device VISUAL pass is deferred like the notification/EventKit device passes.

**DoD:** `flutter build apk` green ✔; interactivity + device screenshots pending.

### OPH-134 — macOS widget parity (gated on macOS signing)

- [ ] Widget Extension in `macos/Runner.xcodeproj`; **App Sandbox** + `com.apple.security.
      application-groups` (`group.com.alliswell.alliswell`) added to **both** `DebugProfile.
      entitlements` and `Release.entitlements` (edit the plists directly). The App-Group string is
      **byte-identical** across Dart `setAppGroupId`, Runner, and the extension; decide the
      `group.…` vs `<TeamID>.group.…` form once (macOS `home_widget` won't add the team prefix).
- [ ] Desktop / Notification Center; supports `systemExtraLarge`; deep-link + (macOS 14+)
      interactivity reusing the shared `AppIntent`.

**Context:** **explicitly gated on the inherited macOS dev-cert gap** (STATE "Blocked / notes":
`flutter build macos` fails today — no macOS development certificate). Ship the code; device-verify
when the cert lands, exactly like the EventKit macOS path. NOT a blocker for iOS/Android.

**DoD:** code compiles once the cert is present; the gate is recorded in STATE; no regression to
iOS/Android widgets.

### OPH-135 — Widget configuration, accessory tier, density & privacy

- [ ] `AppIntentConfiguration` (iOS) / Glance config so a widget instance can pick which
      project / bucket-set it shows (Things/Todoist "configurable per instance" pattern).
- [ ] Optional lock-screen `accessoryRectangular` / `accessoryCircular` "next task" / count (iOS
      16+, Structured-style).
- [ ] Todoist-style **compact/density** option; **"Private widget"** toggle in Settings (renders
      counts/placeholders instead of task titles — OPH-064 privacy ethos, WIDGETS.md §9).

**Context:** reference synthesis (WIDGETS.md §10) + privacy (§9). Fast-follow polish over the core.

**Tests:** Dart config/privacy plumbing (snapshot omits titles when Private is on); device pass for
the configurable + accessory surfaces.

**DoD:** build + device (iOS/Android); STATE note.

### OPH-136 — Widget docs, cross-platform QA matrix & release note

- [ ] Finalize WIDGETS.md against on-device reality — confirm the two research "double-check" flags
      (Glance stable version at build time; exact Apple family names/sizes on the min OS targets).
- [ ] README "Widgets" section + placeholder screenshots; the "how to" for self-hosters.
- [ ] **QA matrix in STATE:** iOS · iPad · Android · macOS × {4×2, 4×4, 4×6/xl} × {light, dark} ×
      {complete, add, sync, midnight rollover} — pass/blocked per cell.
- [ ] BLUEPRINT §12.8/§15.6 + CHANGELOG + ROADMAP v0.2.0 truthful.

**Context:** closes Epic 12.

**DoD:** docs + QA matrix recorded. **Epic 12 closes → v0.2.0 (i18n + widgets).**

---

## Epic 13 — Feedback round 6: the alarm backbone (Phase 7, v0.2.0)

> **Source:** Mahir's 2026-07-18 device test (iPhone, Sleep Focus on): an urgent task due 00:50
> plus a 00:49 reminder produced one *silent* notification — no alarm sound, no urgent
> breakthrough, and nothing at the due time at all. Alarms are the product's backbone (BLUEPRINT
> §8.2). Research is baked into [NOTIFICATIONS.md](NOTIFICATIONS.md) §§1–2b (critical-alerts
> policy, AlarmKit, Android DND mechanics).
> **Item↔task map:** (1) tab wraps + rename → OPH-137 · (2) Today looks disabled → OPH-137 ·
> (3) alarm/urgent delivery → OPH-138/139 now; OPH-140…143 device/native follow-ups.

### OPH-137 — TR "Fikirler" rename + Home dim honesty — ✅ 2026-07-18

- [x] tr.json renames (tab/status/tour/empty states): Gelen Kutusu → **Fikirler**, task status →
      "Fikir". The selected-tab bold no longer overflows (8-char label); DESIGN §9 gained **L5**
      (bottom-bar labels ≲10 chars, every locale).
- [x] `groupTasksForHome`: **Overdue/Today/No-date NEVER dim** — current debts must not look
      disabled; only future groups dim while a calendar day is selected. **Hiding the phone
      calendar clears the day selection** (an invisible filter must not keep dimming Home).
      Grouping + widget tests updated; new hide-clears-selection test.

### OPH-138 — Urgent tasks alarm at their deadline — ✅ 2026-07-18

- [x] API: `effectiveRemindAt(task)` = `remind_at ?? (is_urgent ? due_at : null)` inside
      `reconcileTaskReminder` (`src/db/reminders.js`) — one seam covers REST, sync push and the
      calendar job. Moving `due_at` moves the alarm; dropping urgency cancels it. 4 new tests.
- [x] App: `ReminderStore.watchAlarms` merges reminder rows with **synthetic task-derived
      alarms** (same rule) so the alarm is scheduled even offline/mid-sync; a task with ANY
      reminder row (even terminal) never synthesizes — acknowledged stays acknowledged. Synthetic
      acknowledge resolves to the task's active row. 9 new tests (`reminder_store_test.dart`).

### OPH-139 — Real alarm delivery: sound + interruption levels + critical path — ✅ 2026-07-18

- [x] 28 s alarm bed synthesized (dual-tone pulse train, under iOS's 30 s cap):
      `ios/Runner/Resources/aw_alarm.caf` (ima4, wired into the pbxproj, verified inside the
      built .app) + `android/.../res/raw/aw_alarm.m4a`.
- [x] iOS: urgent = `timeSensitive` + alarm sound; upgraded to `critical` + volume 1.0 **only**
      when `checkPermissions().isCriticalEnabled` (an unentitled critical payload can silence the
      notification outright). `requestPermissions(critical: true)` — safe without the
      entitlement. **Normal reminders are now `timeSensitive`** (`.active` was buried by every
      Focus mode). macOS: default sound, timeSensitive.
- [x] Android: **versioned `urgent_alarms_v2` channel** — `USAGE_ALARM` (alarm stream: rings
      through muted ringer and default DND) + `FLAG_INSISTENT` (loops until opened) + full-screen
      intent; the soundless v1 channel is deleted at startup.
- [x] Settings → **"Acil alarmlar" honest status row** (notifications / exact-alarm / critical
      states in plain language; tap re-runs the permission flow). Notification bodies, action
      labels and channel names localized (en+tr) — planner strings were TR-hardcoded.

### OPH-140 — Device verification pass: the alarm matrix

- [ ] iOS device: urgent due-time alarm rings under Sleep Focus (time-sensitive breakthrough,
      28 s sound at ringer volume, screen lights); chain re-alerts at +2/+5/+10/+30; Onayla stops
      the chain on every device (sync); normal reminder banners+sounds; mute-switch behavior
      documented (silent — expected until OPH-141/142).
- [ ] iOS sanity: Settings → AllisWell shows the "Time Sensitive Notifications" toggle; the
      PROVISIONING PROFILE carries the time-sensitive entitlement (most common silent failure —
      NOTIFICATIONS.md §2).
- [ ] Android device: v2 channel rings on the ALARM stream with the ringer muted; insistent loop
      until opened; default DND lets it through; "Alarms & reminders" special-access flow;
      full-screen intent where granted.
- [ ] Record the matrix in STATE (like the Epic 12 widget QA matrix).

**Context:** exact delivery can only be proven on devices (NOTIFICATIONS.md verification note).

**DoD:** matrix recorded in STATE; regressions become tasks.
**Status (2026-07-24):** device tour done — iOS Time-Sensitive capability added (`Runner.entitlements`
now in the provisioning profile) + widget verified, Android verified, no issues (Blocker 2/3). The
**muted-phone** urgent ring is now AlarmKit's job (OPH-141), whose Swift awaits its iOS 26 device
build; the time-sensitive lane already covers the non-muted case.

- [x] **Native bridge written** (Runner-side channel — AlarmKit's Live Activity presentation lives
      in the app target): `ios/Runner/AlarmKitBridge.swift` (`MethodChannel('alliswell/alarmkit')`:
      `isSupported`/`requestAuthorization`/`schedule`/`cancel`/`scheduledIds`, `@available(iOS 26)`,
      `AlarmManager.shared`, fixed-date schedule + `AlarmPresentation.Alert` with **Onayla (stop)** /
      **Ertele (countdown)** buttons, app-id stored in `AWAlarmMetadata` + a deterministic UUID so
      `cancel` needs no table and `scheduledIds` survives relaunch; stop → `onAlarmAction:acknowledge`
      back to Dart), registered in `AppDelegate.didInitializeImplicitFlutterEngine`,
      `NSAlarmKitUsageDescription` in Info.plist. iOS < 26 / non-urgent stay on OPH-139.
- [x] **Planner stays the single source of truth** (`lib/src/notifications/`): pure `AlarmKitHost`
      seam (`alarmkit.dart`, `MethodChannelAlarmKitHost` + `UnsupportedAlarmKitHost`), pure
      `planAlarmKitAlarms` (urgent → one AlarmKit alarm, no chain) + `routeUrgentToAlarmKit` on
      `planNotifications` (so urgent never rings twice), and a second set-diff in
      `NotificationScheduler` against the host so acknowledge/complete/snooze cancels the AlarmKit
      alarm exactly like a notification. Declined/unsupported → urgent falls back to the notification
      chain (never dropped). Onayla/Ertele route through the same `handleNotificationEvent`.
- [ ] **USER (device, iOS 26):** real build + pass — AlarmKit only compiles against the iOS 26 SDK
      on a real target (`analyze`/`test` never touch Swift). Confirm the exact AlarmKit value types
      on first build, then: urgent alarm rings on a MUTED iOS 26 device, Onayla acknowledges, Ertele
      snoozes.

**Context:** research 2026-07-18 — Apple's AlarmKit alert "breaks through silent mode and the
current Focus" with no special entitlement; critical alerts are effectively refused to task
managers (NOTIFICATIONS.md §2). This is the sanctioned way to never miss an urgent task on a
muted iPhone.

**Tests:** Dart lane logic device-free (fake AlarmKit host); Swift by real build + device pass.
Shipped: `alarmkit_test.dart` (pure lane — urgent-only/no-chain, past-skip, snooze, privacy, id
stability) + `scheduler_test.dart` AlarmKit group (urgent→AlarmKit/non-urgent→notifications,
acknowledge cancels via diff, unsupported+declined fall back). `FakeAlarmKitHost` in test support;
`syncTestOverrides` binds `UnsupportedAlarmKitHost` so full-app tests stay device-free.

**DoD:** urgent alarm rings on a MUTED iOS 26 device with the app killed; STATE matrix updated.
**Status: Dart lane DONE + tested (app 377/377, analyze+format clean); Swift bridge written and
handed off for the iOS 26 device build (same shape as OPH-131).**

### OPH-142 — Critical-alerts entitlement application (user action; code is ready)

- [ ] **Mahir (Account Holder):** submit
      <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/> —
      justification draft in NOTIFICATIONS.md §2. Expect refusal for a task manager; AlarmKit
      (OPH-141) is the primary path — this is belt-and-braces for muted phones on iOS < 26.
- [ ] If granted: add `com.apple.developer.usernotifications.critical-alerts` = true to
      `Runner.entitlements`, regenerate provisioning profiles. **No code change** — OPH-139
      already gates on the runtime grant, and the second "Critical Alerts" permission prompt +
      Settings toggle appear automatically.

### OPH-143 — Foreground ring screen + degradation banners — ✅ 2026-07-19

- [x] In-app full-screen "alarm ringing" overlay when an urgent alarm fires while the app is
      OPEN (all platforms — and desktop/web's ONLY alarm surface, NOTIFICATIONS.md §3): task
      title, Onayla + snooze presets (5/30 dk, 1 saat), Tamamla/Aç. `AlarmOverlayController`
      (`lib/src/notifications/alarm_overlay.dart`) watches `reminderStoreProvider.watchAlarms`
      + a foreground timer wheel (arms to the next urgent fire) and drives `AlarmRingScreen`,
      mounted in `HomeShell` above the tour (an urgent alarm outranks onboarding). Auto-show
      gated behind `alarmOverlayAutoShowProvider` (defaulted OFF in
      `test/support/sync_overrides.dart` — OPH-111 idiom). `PopScope(canPop:false)` so the
      alarm is answered, not dismissed. **Deviation (documented):** looping in-app AUDIO is a
      seam (`AlarmFeedback` → `HapticAlarmFeedback` haptic pulse today; `SilentAlarmFeedback`
      in tests) — a real player rides the device audio tour, since on mobile the OS
      notification already carries the 28 s bed (OPH-139) and desktop/web are best-effort
      (NOTIFICATIONS.md §3). Ring decision is a pure fn (`ringingAlarm(alarms, now)`); the
      "fake clock" is just `now`.
- [x] Honest degradation banners (§1 "never fail silently"): `AlarmDegradationBanner` at the top
      of Home warns when notifications are off (any platform) or Android exact alarms are denied
      ("alarms may arrive late — allow Alarms & reminders"); worst-problem-first cascade mirrors
      the Settings status row (OPH-139), tap re-runs the permission flow + re-probes. New
      `alarmSupportProvider` (probes the gateway; permissive fallback off-platform). New `alarm.*`
      i18n (en+tr). DESIGN §11 records the ring/banner component rules (Rule 11).

**Tests:** `ringingAlarm`/`nextUrgentFireAfter` pure (fake clock); `AlarmOverlayController` gate
ON→rings / OFF→silent (seeded urgent-due synthetic alarm); `AlarmRingScreen` renders + Acknowledge
flips the reminder row + snooze moves the task; `AlarmDegradationBanner` three permission states.
**App 322/322, analyze + check:i18n + contrast (FAILURES: 0) clean.**

**DoD:** analyze + suites green; STATE note ✔. **Epic 13 device tail rides the Epic 12 device
tour** (one physical session can clear both matrices — OPH-140).

---

## Epic 14 — Attachments & project files: Cloudflare R2 / S3 storage (Phase 8, v0.3.0)

> **Source:** Mahir's 2026-07-18 request (feedback round 7): R2 in the backend; image/video/any
> file attachments on tasks; inline images/videos in notes; a project **Files** tab as a simple
> file manager (upload/download/rename/delete). Pulled forward from the v2 parking lot
> ("Attachments — S3-compatible storage").
> **Binding docs:** [ATTACHMENTS.md](ATTACHMENTS.md) (protocol, schema, CORS, security, UX),
> [ADR-0011](adr/0011-attachments-r2-s3-storage.md); BLUEPRINT §4.10, §12.3/12.4/12.5, §16
> Risk 7; DESIGN §10.
> **Shape:** bytes go client↔bucket via presigned URLs (API never proxies); `files` metadata is
> a **pull-only** sync entity (ADR-0008 model); REST writes + `syncNow()` convergence; deletes
> cascade + queue object cleanup. Feature is optional config (`STORAGE_S3_*` unset ⇒
> `STORAGE_NOT_CONFIGURED` + honest empty states).

### OPH-150 — API: storage foundation (config, S3/R2 plugin, MinIO in compose+CI, status endpoint) — ✅ 2026-07-18

- [x] Deps: `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner` (apps/api).
- [x] `config.js` → frozen `storage` block: `STORAGE_S3_ENDPOINT/REGION('auto')/BUCKET/
      ACCESS_KEY_ID/SECRET_ACCESS_KEY/FORCE_PATH_STYLE(true)`, `STORAGE_MAX_UPLOAD_MB(512)`,
      `STORAGE_PRESIGN_TTL_SEC(3600, 60…604800)`, `STORAGE_SWEEP_SEC(3600, ≥10)`;
      `configured` = endpoint+bucket+both keys; partial config (some but not all of the four) =
      boot error naming the missing vars; TTL/size ranges validated. `.env.example` documented
      (R2 endpoint example + CORS pointer).
- [x] `src/plugins/storage.js` (fastify-plugin): decorates `app.storage` =
      `{ enabled, maxUploadBytes, presignTtlSec, presignPut(key, {contentType}),
      presignGet(key, {filename, contentType}), head(key), remove(key) }` over an S3Client
      (region `auto`, `forcePathStyle`), **injectable** via `buildApp({ storage })` exactly like
      `db`/`redis`. GET presigns set `response-content-disposition` (RFC 5987 `filename*`) +
      `response-content-type`. Disabled mode → `enabled: false`, helpers throw.
- [x] `GET /api/v1/storage` (auth): `{configured, maxUploadBytes, presignTtlSec}` — the app's
      feature probe.
- [x] docker-compose: `minio` service (console on 9001), healthcheck (`mc ready local`),
      `.env` ports. CI: **deviation** — GH service containers cannot override an image command
      and `minio/minio` needs `server /data`, so CI starts MinIO via a plain `docker run` step;
      the test bootstrap (`test/helpers/minio.js`) creates the bucket itself with retries, so
      neither compose nor CI needs init choreography (first run IS the init).
- [x] Tests — unit (17): config validation matrix (off/partial named-missing-vars/TTL range/
      bad bool), `contentDisposition` RFC 5987 (Turkish round-trip, quote escape), offline
      SigV4 presign shapes (PUT + GET response-* overrides), status endpoint auth/off/on;
      integration (4, real MinIO): presigned PUT → head byte count → presigned GET same bytes
      + pinned name/type → tampered signature 403 → idempotent remove + head null.

**DoD met 2026-07-18:** lint + format + `check:no-ts` green; unit 240/240; integration 32/32
locally (colima; MinIO on **9010** on this machine — port 9000 is a local ssh tunnel, see
STATE); MinIO wired in CI in the same change; `.env.example` + README index updated; CHANGELOG.

### OPH-151 — API: `files` migration + upload lifecycle (init → presigned PUT → complete) + sweep — ✅ 2026-07-18

- [x] Migration `create_files` (ATTACHMENTS.md §3): ULID PK, `workspace_id` FK CASCADE,
      `target_type` enum(project|task|note), `target_id` (no FK, validated at init),
      `uploaded_by`, `name` 255, `mime` 255, `size_bytes` BIGINT UNSIGNED, `storage_key` 300
      UNIQUE (`ws/{wsId}/{fileId}`), `status` enum(uploading|ready), `revision`, timestamps +
      `deleted_at`; indexes `(workspace_id, target_type, target_id)` + `(status, created_at)`.
      Rollback→re-apply verified (all 10 migrations).
- [x] `POST /api/v1/workspaces/:workspaceId/files` (member): validates storage enabled
      (`STORAGE_NOT_CONFIGURED` 503), target exists+undeleted+in-workspace
      (`FILE_INVALID_TARGET`), name sanitized to basename, 1–255, no control chars
      (`FILE_NAME_INVALID`), declared `sizeBytes` ≤ cap (413 `FILE_TOO_LARGE`). Inserts
      `status='uploading'` **without** `recordSyncWrite` (invisible to sync) → `201 {file,
      upload: {method:'PUT', url, headers:{'content-type'}, expiresAt}}`.
- [x] `POST /api/v1/files/:fileId/complete` (member): already-ready → 200 idempotent (retry
      after a network blip must not error — small deviation from the drafted `FILE_NOT_READY`);
      `head(key)` missing → 409 `FILE_UPLOAD_INCOMPLETE` (row stays, PUT can retry); size ≠
      declared → `remove(key)`, row hard-deleted, 409 `FILE_UPLOAD_MISMATCH`; match →
      transaction: `recordSyncWrite('file','create')` + `status='ready'` + revision stamp.
- [x] `DELETE /api/v1/files/:fileId` (member): `uploading` → hard delete + queued object
      remove (never synced); `ready` → `softDeleteReadyFile` (src/db/files.js) tombstone +
      post-commit enqueue. 204 both ways; idempotent on already-deleted; 403 non-members.
- [x] `plugins/storage-gc.js`: `storage-delete` job on `queue/runner.js` (`jobKey =
      storage_key`, missing object = success) + stale-upload sweep (24 h cutoff, guarded
      delete so a just-completed row survives, batch 100, timer unref'd + skipped in tests —
      `app.storageGc.sweepStaleUploads()` for suites).
- [x] `serializeFile` + `fileSchema` in the route module (no URLs/keys in payloads).
- [x] Tests — unit 15 (fake storage `test/helpers/fakestorage.js`): sanitize matrix, 503 off,
      init shape + zero sync rows, mismatch destroys object+row, incomplete retryable,
      complete idempotency, delete both branches + revision/log assertions, sweep age matrix,
      disabled no-op; integration 3 (MySQL+MinIO+BullMQ): real PUT → complete → revision row,
      mismatch deletes the real object, delete → tombstone + worker removes object (polled).

**DoD met 2026-07-18:** unit 255/255; integration 35/35; migrations rollback/re-apply green;
lint+format clean; CHANGELOG; STATE.

### OPH-152 — API: read surface, pull-only sync, cascade cleanup, rename, markdown embeds — ✅ 2026-07-18

- [x] `GET /api/v1/files/:fileId` (member): `{file, downloadUrl, downloadExpiresAt}` —
      URL null unless `ready` (and null with storage off — metadata still answers); minted
      per request, never stored.
- [x] `GET /api/v1/workspaces/:workspaceId/files` (member): `?targetType&targetId` list
      (newest first) **or** `?projectId=` aggregate — project files ∪ files of the project's
      (undeleted) tasks ∪ notes, each row + `source: {type, id, title}`; batched queries.
- [x] `PATCH /api/v1/files/:fileId` `{name}` (member, `ready` only → 409 `FILE_NOT_READY`):
      sanitize like init, update + `recordSyncWrite('file','update',['name'])`.
- [x] Sync pull: `file` joins `SNAPSHOT_LOADERS`; deleted → tombstone. Push: **deliberately
      absent** from `ENTITIES` — test proves `SYNC_UNSUPPORTED_ENTITY` (ADR-0008 model).
- [x] Cascade `cascadeDeleteFiles(trx, app, {workspaceId, targets})` (src/db/files.js):
      ready → tombstone revision each, uploading → hard delete; object deletions scheduled
      post-commit via `executionPromise` (rollback-safe). Wired into task REST delete + sync
      `customDelete` (whole subtree), note + project REST deletes and a new generic
      `afterDelete` hook in sync `applyDelete`. Archiving touches no files (test).
- [x] `GET /api/v1/workspaces/:workspaceId/files/usage`: `{totalBytes, fileCount}` over
      ready+undeleted rows (summed in JS — the in-memory test db has no aggregates;
      workspaces hold hundreds of files, not millions).
- [x] Markdown export: `deltaToMarkdown(ops, {embedLabel})` renders image embeds
      `![label](source)`, video/other sourced embeds `[label|'attachment'](source)`;
      `embedFileIds(ops)` extracts `alliswell://file/{id}` refs; the export route resolves
      labels to current file names. `deltaToPlainText` keeps skipping embeds. **Contract
      change:** the OPH-045 "embeds are dropped" fixture updated on purpose — the Dart
      converter mirrors the new fixtures in OPH-156.
- [x] Tests — unit 18 new (files-read 13: download URL, target+aggregate lists with sources,
      partial-query 400, usage, rename matrix, pull snapshot/tombstone, push refusal, cascade
      subtree/uploading/note/project/sync-push/archive; delta-embeds 5: markdown fixtures,
      resolver labels, embedFileIds, export-route names) + 1 legacy fixture updated;
      integration 1 (aggregate + real presigned download of Turkish filename + task-delete
      cascade → pull tombstone + BullMQ worker removes the object, project file survives).

**DoD met 2026-07-18:** unit 273/273; integration 36/36; lint+format+no-ts clean; CHANGELOG;
STATE. **The API vertical of Epic 14 is complete — everything the app needs exists.**

### OPH-153 — App: replica v5 `files` + pull-only FileStore + upload service + storage probe — ✅ 2026-07-18

- [x] drift `FileRows` table (mirrors `serializeFile`; read-only, no outbox path —
      ExternalEvents precedent), `@DriftDatabase` list, `schemaVersion => 5`, `onUpgrade`
      `if (from < 5) createTable(fileRows)`; `database.g.dart` regenerated; hand-rolled
      migration test extended to v5 (drift_dev dump is broken on this toolchain).
- [x] `sync_applier.dart`: `case 'file':` snapshot upsert + tombstone + `fileCompanion`.
- [x] `features/files/` — `FileStore` (read-only): `watchForTarget(type, id)` newest-first,
      `watchForProject(projectId)` — **one `customSelect` UNION** (project ∪ its tasks' ∪ its
      notes' files with `source_type/id/title`, `readsFrom` all four tables → a single live
      stream). `watchUsage` deferred to OPH-157 with the usage UI.
- [x] `FilesApi` (dio via `apiClientProvider`, GoogleIntegrationsApi template): storageStatus,
      initUpload → `UploadTicket`, complete, download (null-safe), rename, delete +
      `ApiException` mapping. `FileUrlCache` caches minted URLs until ~expiry (list thumbs
      must not re-mint per rebuild; URLs never persisted).
- [x] `UploadsNotifier` (Riverpod `Notifier`): pickAndUpload/start → init → PUT via
      `uploadTransportProvider` (a **bare** dio — an Authorization header would break the
      presigned signature) with `onSendProgress` + CancelToken → complete → `syncNow()`;
      failed(errorCode) → retry (fresh init — old URL may be expired) / dismiss; cancel →
      abort DELETE. io streams from path (video never fits memory), web uses bytes —
      conditional-import picker (`pick_files_io/web.dart`), re-openable `PickedUpload.open()`.
      `mimeForName` extension map so previews work when pickers omit MIME.
- [x] `storageStatusProvider` (REST — deployment state is not replica data); `filePickerProvider`
      seam added to `syncTestOverrides` (picks nothing by default). New dep: `file_picker` 11
      (v11 API: static `FilePicker.pickFiles`, no `.platform`).
- [x] Tests (12 new): applier round-trip/tombstone/upsert-rename, v4→v5 migration (user_version
      5 asserted), store target list + aggregate with source titles + out-of-project exclusion +
      live stream update, upload controller happy path (progress 0.5 observed, content-type
      travels), init-fail→retry, PUT-fail→dismiss, cancel→abort DELETE, mimeForName.

**DoD met 2026-07-18:** `flutter analyze` clean; app suite **290/290**; CHANGELOG; STATE.

### OPH-154 — App: task detail "Attachments" section — ✅ 2026-07-18

- [x] `_SectionCard(title: 'task.attachments')` after Checklist hosting the reusable
      `AttachmentsSection` (`features/files/ui/file_widgets.dart` — F1: ONE row anatomy shared
      with OPH-155/156): `FileRowTile` (thumb/kind icon + name + `size · date`),
      `UploadRowTile` (determinate progress + cancel; failed → error colors + retry/dismiss),
      add button → picker seam → the real `UploadsNotifier` handshake.
- [x] Tap: image → full-screen `_FileImageViewer` (InteractiveViewer, minted URL, honest
      loading/error, open+delete in the app bar); others → action sheet Open/Download
      (`urlLauncherProvider` + `FileUrlCache`) · Rename (prefilled dialog → REST + syncNow) ·
      Delete (confirm names the file, error-colored — F5). `formatBytes` KB/MB helper.
- [x] Storage not configured → one quiet explainer row, add button absent (F6); thumbnails
      fall back to kind icons whenever a URL can't be minted (F3 — also what keeps widget
      tests off the network: the fake server answers `downloadUrl: null` by default).
- [x] i18n en+tr (`task.attachments` + new `file.*` namespace, 12 keys); contrast FAILURES: 0.
- [x] Widget tests (4, full-app over FakeApi — extended with `/storage` + file endpoints,
      `seedFile`, pull integration): seeded rows render (name+size), pick→upload→synced row
      appears (mime guessed for the picker gap), delete via sheet with named confirm →
      tombstone pulled, not-configured explainer. `syncTestOverrides` grew `filePicker` +
      `uploadTransport` params (instant fake PUT default).

**DoD met 2026-07-18:** analyze clean; app suite **294/294**; check:i18n + contrast green;
CHANGELOG; STATE.

### OPH-155 — App: project "Files" tab (the file manager) — ✅ 2026-07-18

- [x] `ProjectDetailScreen`: `DefaultTabController length 4`, `Tab('project.tabFiles')` +
      `_ProjectFilesTab`: aggregated `projectFilesProvider` list (live replica UNION), source
      filter chips (All · Project · Tasks · Notes), `_SourceBadge` per row (F4 — project label
      or the task/note title), sort menu (date default · name · size). **Deviations:** upload
      is a top action row, not a FAB — the Tasks/Notes tabs set that in-project pattern
      (OPH-101 hoisted-FAB lesson); the usage footer moved to OPH-157 with its endpoint UI.
- [x] Row actions are OPH-154's shared widgets verbatim (F1); uploads targeting the project
      render progress rows; empty + not-configured `AwEmptyState`s (F6); archived-banner
      logic untouched.
- [x] i18n en+tr (12 new `file.*` keys + `project.tabFiles`); L5: `Files`/`Dosyalar` fit.
- [x] Widget tests (5): aggregate with badges + filter narrowing, sort by name, upload
      targets the PROJECT, empty state, storage-off explainer with a disabled (not dead)
      add button.

**DoD met 2026-07-18:** analyze clean; app suite **299/299**; contrast FAILURES: 0;
check:i18n green; CHANGELOG; STATE.

### OPH-156 — App: inline images/videos in notes (+ Dart markdown parity) — ✅ 2026-07-18

- [x] Editor toolbar: image + video insert buttons (`NoteMediaButtons`, custom — no
      `flutter_quill_extensions`): picker → upload targeting the note (`_ensureNote()`
      force-autosaves a brand-new note first) → on complete a standard Quill `image`/`video`
      embed with source `alliswell://file/{fileId}` lands at the caret (no phantom embeds);
      in-flight/failed uploads render as F2 rows under the toolbar (cancel/retry). Non-media
      picks still upload as note attachments with an honest "won't embed inline" snackbar.
- [x] `awNoteEmbedBuilders()` (editor + read-only README view): id → minted URL via
      **riverpod family providers** (`fileUrlProvider`/`fileByIdProvider` — futures must be
      provider-cached, minting them in build never settles; `FileUrlCache` also memoizes
      futures now, incl. brief null-caching so placeholders are stable, and never throws).
      Image inline (progress tile while fetching, tap = viewer), video/other → tile with the
      file's CURRENT name + open action; offline/gone → placeholder naming the file (F3);
      foreign http sources still render.
- [x] Dart `deltaToMarkdown` mirrors OPH-152 fixtures: `![](source)` / `[attachment](source)`,
      unknown embeds drop; the legacy "skips embeds" fixture updated like the API's;
      `plainTextFromDelta` unchanged. Parity tests replicate the server cases verbatim.
- [x] Deleting the embed leaves the file row (undo safety); the file stays in the note's
      attachments / project Files tab. **Test-double lesson:** fake ids must be REAL ULIDs —
      Crockford excludes I/L/O/U, so `FIL…` seeds never matched the embed regex (renamed).
- [x] i18n en+tr (4 new keys); 7 tests: markdown parity ×2, scheme parser, image placeholder
      names the file from the replica, video tile + open icon, insert flow (upload targets the
      note, mime guessed, embed renders), non-media honest path.

**DoD met 2026-07-18:** analyze clean; app suite **306/306**; contrast FAILURES: 0;
check:i18n green; CHANGELOG; STATE.

### OPH-157 — Hardening, docs & the attachment QA matrix — 🟡 code+docs ✅ 2026-07-18; manual matrix ⏳ device tour

- [x] Upload polish (landed across 153-156 by design): retry re-reads the original source
      (path on io / bytes on web — `PickedUpload.open()` is re-openable), duplicate names
      allowed (id-keyed) and disambiguated by the `size · date` subtitle, mismatch restarts
      from a fresh init. **Usage footer** on the Files tab: `FilesApi.usage` +
      `workspaceFilesUsageProvider` → "{count} files · {size} used" (display only — quota
      enforcement stays v2). FakeApi usage endpoint + footer test.
- [x] Docs: README "📎 Attachments & file storage" section (R2 + CORS pointer + optionality),
      ATTACHMENTS.md §0a implementation-status table (trued against reality), SECURITY.md
      "File storage" section, ROADMAP "Toward v0.3.0 / Phase 8" + parking-lot v2 line,
      BLUEPRINT §18 + parking-lot verified.
- [ ] **Web reality pass** (needs a real browser + a real bucket): CORS happy path + the
      CORS-missing error surfaced honestly, CanvasKit image fetch, `Content-Disposition`
      download.
- [ ] **Manual matrix in STATE** (rides the Epic 12/13 device tour): iPhone photo upload,
      Android video, desktop picker, web CORS ±, 100 MB file, offline placeholders, rename/
      delete propagation across two clients.

**DoD:** suites green ✔; matrix recorded in STATE ⏳; **Epic 14 closes → v0.3.0 after the
manual pass.**

---

## Epic 15 — Feedback round 8: akış hızı, arama, pano, global dosyalar (Phase 9, v0.4.0)

> Kaynak: kullanıcı testi round 8 (2026-07-20, 10 madde). Bağlayıcı dokümanlar: BLUEPRINT
> §7.2/§12.1/§12.2/§12.4/§12.10-12.12/§4.4/§4.10-4.11/§14 Phase 9/§16 Risk 8, DESIGN §10
> F7-F9/§12/§13/§14, ARCHITECTURE §6b-6c, ATTACHMENTS §14,
> [ADR-0013](adr/0013-local-first-search.md) (arama), [ADR-0014](adr/0014-folders-and-global-files.md)
> (klasörler). Sıra bağımlılık sırasıdır: bug önce, küçük kazanımlar, oluşturma akışı,
> etiketler → arama (etiket tier'ı ister), pano, dosyalar (API → app).

### OPH-160 — Google connect: otomatik primary takvim + anında ilk sync (bug, round 8 #1) ✅ 2026-07-20

Kök neden (2026-07-20 tanısı): OAuth callback yalnız token yazar, `default_calendar_id`
NULL kalır; sync/watch/sweep üçü de NULL'da erken çıkar → bağlantı "başarılı" görünür ama
hiçbir event çekilmez; kullanıcının ayrı bir "takvim seç" adımı attığı varsayılır (gizli
ikinci adım). App tarafı da takvim seçildiğinde `syncNow()` çağırmaz (60 sn'lik pull'u bekler).

- [x] API: callback başarısında `listCalendars` ile `primary` takvimi bul,
      `default_calendar_id`'ye yaz ve `enqueueSync` + `enqueueWatch` kuyruğla (PATCH
      `calendarChanged` dalının birebir aynısı; mirror sweep dahil). Primary yoksa /
      listeleme hata verirse eski davranışa düş (non-fatal — tokenlar kayıtlı, picker
      çalışır). Reconnect'te seçili takvim korunur ama feed yine tazelenir (bayat
      kanal/cursor durumu).
- [x] API: callback HTML metni — takvim hazırsa "etkinlikler arka planda senkronize
      ediliyor… istersen Ayarlar'dan farklı bir takvim seçebilirsin"; düşüşte eski metin.
- [x] App: `_pullSoon()` (`syncEngineProvider?.syncNow()`) — `chooseCalendar` sonrası VE
      onResume'da (bağlantı dönüşü) tetiklenir.
- [x] Unit test: `google-oauth.test.js` "auto-selects the primary calendar…" — seed'li
      fakegoogle meeting'i callback→idle sonrası `calendar_external_events`'te; reconnect
      takvimi değiştirmiyor ama external feed sayacı artıyor. 274/274.
- [x] App testi: takvim seçimi `GET /api/v1/sync/pull` tetikliyor (öncesinde pull yok
      assertion'ıyla atfedilebilir). 6/6.
- [x] Docs: BLUEPRINT §7.2 (docs commit'inde revize), CHANGELOG, STATE.

Acceptance: temiz bir hesapla bağlan → hiçbir ek adım atmadan Home'da etkinlikler
(socket + syncNow ile saniyeler içinde) görünür. ✔ (fakegoogle uçtan uca; gerçek Google
hesabı doğrulaması kullanıcı turunda.)

**DoD met 2026-07-20:** API unit 274/274; app google_calendar 6/6 + tam süit yeşil;
analyze temiz; CHANGELOG; STATE.

### OPH-161 — Varsayılan görev saati: 23:59 + Ayarlar tercihi (round 8 #6) ✅ 2026-07-20

- [x] `defaultTaskTimeProvider`: `PersistedChoice('alliswell_default_task_time',
      fallback: '23:59')` ("HH:mm"); `parseTaskTime` (bozuk değerde 23:59'a düşer — tercih
      çöpü görev oluşturmayı ASLA kıramaz) + `applyDefaultTaskTime(day, hhmm)` yardımcıları
      (`core/persisted_prefs.dart`).
- [x] 4 sabit 09:00 sitesi helper'a bağlandı: `task_create_sheet.dart` (`_pickDateTime`
      initialTime + saat-iptal fallback'i), `task_detail_screen.dart` `_DateRow`
      (ConsumerWidget'a çevrildi), `home_screen.dart` `_quickAdd`, `home_shell.dart` FAB
      ön-dolumu. Kod tabanında görev-saatı sabiti kalmadı (snooze'un "tomorrow morning"
      09:00'u AYRI bir kavramdır, bilinçle dokunulmadı).
- [x] Settings satırı (dil satırı idiomu, `settings-default-task-time` key'i):
      `showTimePicker` ile seçim; alt yazı yerelleştirilmiş saati gösterir.
- [x] i18n: `settings.defaultTaskTime.{title,sub}` (en+tr).
- [x] Testler: parse/apply/round-trip unit'leri (persisted_prefs_test), quick-add seçili
      günle **23:59**'a düşüyor (eski test güçlendirildi), notifier'la '07:15' yazınca
      quick-add onu kullanıyor (yeni test).

**DoD met 2026-07-20:** app süiti + analyze + check:i18n yeşil; CHANGELOG; STATE.

### OPH-162 — Takvim sekmesini kaldır; seçili gün ufku aşsın (round 8 #9) ✅ 2026-07-20

- [x] `AppSection.calendar` enum girdisi silindi; bağımlılar düzeltildi: router route
      switch'i (+import), shell FAB switch'i + yorumu, tur adımı (akış 7→6 karta indi).
- [x] `calendar_screen.dart` silindi; `selectedDayProvider` + ay ızgarası Home'da yaşıyor.
- [x] **Seçili gün ufku aşar:** `groupTasksForHome` seçili-gün kontrolünü horizon'dan ÖNCE
      yapıyormuş — davranış zaten doğruydu; bayat "Calendar tab" yorumları güncellendi ve
      davranış +68 günlük seçimle test altına alındı (task + meeting seçili-gün grubunda).
- [x] i18n: `nav.calendar/calendarDesc` + `tour.calendarTitle/Body` kaldırıldı (en+tr;
      `calendar.*` ad alanı Google/Apple kartlarının — duruyor). Tur testi 6 adıma çekildi.
- [x] Takvim-sekmesi widget testleri Home-tabanlı eşdeğere dönüştürüldü: "home shows the
      day's meetings beside its tasks (read-only)" — event satırı + Checkbox'suz sözleşme
      widget seviyesinde Home'da korunuyor (tek takvim yüzeyi artık Home).
- [x] Docs: BLUEPRINT §12.1/§12.2 (docs commit'inde revize), CHANGELOG, STATE.

**DoD met 2026-07-20:** app 326/326, analyze temiz; CHANGELOG; STATE.

### OPH-163 — Proje seçicide "+ Proje ekle" (round 8 #2) ✅ 2026-07-20

- [x] `project_picker.dart`: `kCreateProjectValue` sentinel'i + `withCreate` param'ıyla
      liste sonunda "+ Proje ekle" girdisi (primary renk + ikon); `showProjectEditSheet`
      artık `Future<String?>` — create dalı yeni projenin id'sini pop'lar
      (`ProjectStore.create` zaten id döndürüyordu, controller'a geçirildi).
- [x] Yeni paylaşılan **`ProjectPickerField`**: sentinel'i içeride çözer (`onChanged`'a
      yalnız gerçek değerler gider), `DropdownButtonFormField` uncontrolled olduğu için
      epoch-key ile kendini yeniden tohumlar — iptal edilen create'te sentinel görünen
      değer olarak ASLA takılı kalmaz; dış value değişiminde de re-seed.
- [x] İki site geçirildi: create sheet (`task-sheet-project`) + detail (`detail-project`) —
      form state'i sheet üstüne sheet açılırken korunuyor.
- [x] i18n: `project.addFromPicker` (en "Add project" / tr "Proje ekle"). Widget testi:
      FAB sheet → picker → "Add project" → adlandır+oluştur → alan yeni projeyi seçili
      gösteriyor → task o projeyle push'lanıyor (api.projects.single.id eşleşmesi).

**DoD met 2026-07-20:** app süiti + analyze yeşil; CHANGELOG; STATE.

### OPH-164 — Görev açıklaması: oluşturmada alan, detayda düzenlenebilir, linkify (round 8 #7) ✅ 2026-07-20

API hazır (`tasks.description` yazılabilir; sync `TASK_FIELDS.description` mevcut).

- [x] Create sheet: başlığın altında çok satırlı "Açıklama" alanı (1→4 satır büyür,
      `task-sheet-description`); boş = null (asla boş string alan yok); triage/edit modu da
      description'ı ön-doldurur ve günceller.
- [x] Detail: `_DescriptionField` — görüntüleme modunda linkify'lı metin (tap → düzenleme),
      düzenlemede başlığın autosave DNA'sı (1500 ms debounce + odak kaybında flush);
      boşken "Açıklama ekle" affordance'ı (`task-add-description`).
- [x] Linkify: saf `core/linkify.dart` (`linkifySegments` — kayıpsız bölme; kuyruk
      noktalama kırpma; Wikipedia parantez sezgisi; `www.` → https) + recognizer'ları
      sahiplenen/dispose eden `widgets/linkified_text.dart`. 6 unit + 2 widget testi.
- [x] OG link önizlemesi bilinçli v2 (parking lot — sunucu proxy'si ister).
- [x] i18n `task.descriptionLabel/Hint`, `task.addDescription` (en+tr). Widget testleri:
      create payload'ında description; detayda display→edit→debounce→push patch; boş
      görevde add-affordance → ilk kayıt; link tap onOpen'a launchable https URI veriyor.

**DoD met 2026-07-20:** app süiti + analyze + check:i18n yeşil; CHANGELOG; STATE.

### OPH-165 — Etiket sistemi: chip-input, #tag, otomatik oluşturma, yönetim (round 8 #4) ✅ 2026-07-20

Sunucu hazır: tags CRUD + `PUT /tasks/:id/tags` + sync push `tag` (slug'ı server türetir —
`sync.js:391-393`); eksik olan tümüyle app.

- [x] `TagStore` (`features/tags/data/tag_store.dart`): `create` (optimistic satır, geçici
      fold-tabanlı slug — server pull'da kendi slug'ıyla ezer; outbox `tag create {name}`),
      `rename`, `setColor`, `delete` (yerel `taskTagRows` da temizlenir — sarkan join satırı
      chip'i hortlatmasın), `taskCount` (silme onayının etki alanı).
- [x] `TagInputField` (DESIGN §13 T1…T4): chip'ler `#ad` + renk noktası + ×; Tab (Focus
      onKeyEvent — boşken traversal'a bırakır) / Enter / virgül commit; fold-duyarsız öneri
      satırı; tam eşleşme yoksa ilk öneri "Oluştur: #ad" (`tag-create-suggestion`); baştaki
      '#' yutulur; seri giriş odağı korur. **`core/fold.dart` burada doğdu** (ADR-0013
      fold'u — İ/I/ı→i önce, sonra lowercase + Latin-1/Ext-A açık harita; 5 test grubu).
- [x] Create sheet'e Tags alanı (`tagIds` create/update body'sinde); detail `_TagPicker`
      SİLİNDİ → aynı `TagInputField` + `setTags` replace-set + `onManage`.
- [x] "Etiketleri yönet" sheet'i: listele, yeniden adlandır + palet (proje paleti — hex
      asla görünmez), sil (onay görev sayısını söyler; error-renkli buton).
- [x] Liste satırlarında ≤2 satır-içi etiket + "+N" (tooltip kalanları sayar) — tipografik
      `_InlineTag` (satır ritmi büyümez). **Bulunan gerçek bug:** liste watch'ı `tagIds`
      hydrate ETMİYORDU (yalnız watchDetail join'liyordu) → `_watchList` artık
      `taskTagRows`'u combineLatest'le gruplayıp dolduruyor.
- [x] i18n `tag.*` (12 anahtar, en+tr); testler: Enter+virgül commit & oto-oluşturma &
      task'a binme, fold eşleşmesi duplicate yaratmıyor (cay↔Çay), detail atama + yönetim
      sheet silme (sayılı onay, push'lanmış delete), satır ≤2+N. 9/9.

**DoD met 2026-07-20:** app süiti + analyze + check:i18n yeşil; CHANGELOG; STATE.

### OPH-166 — Oluşturma sheet'inde ek seçimi (round 8 #3) ✅ 2026-07-20

- [x] Create sheet'e Ekler bölümü: `filePickerProvider` ile seç → bekleyen satırlar
      (tür ikonu + ad + boyut + kaldır ×, `pending-file-N`); upload YOK — task yok.
      Yalnız create modunda (edit/triage detaydaki tam bölümü kullanır — kopya yok).
- [x] Kaydet akışı: `TaskStore.create` id döndürür → seçimler `uploads.start(targetType:
      'task', targetId: id)` ile makineye devredilir (`unawaited` — sheet beklemez;
      F2 satırları detayda görünür).
- [x] Depo yapılandırılmamışsa AttachmentsSection'ın aynı dürüst satırı (`file.notConfigured`,
      cloud_off) — ölü buton yok.
- [x] Yeni i18n GEREKMEDİ (`file.add`, `file.notConfigured`, `common.remove` mevcuttu).
      Test: iki dosya seç → bekleyen satırlar + `api.files` boş → birini kaldır → kaydet →
      tek dosya YENİ task id'siyle yüklendi (init+PUT+complete fake sunucuda). 5/5.

**DoD met 2026-07-20:** app süiti + analyze + check:i18n yeşil; CHANGELOG; STATE.

### OPH-167 — Arama: TR fold motoru + Home/Notlar/Projeler (round 8 #5, ADR-0013) ✅ 2026-07-20

- [x] `core/fold.dart` (OPH-165'te doğdu, burada tamamlandı) + **JS aynası `src/lib/fold.js`**;
      **parite fixture'ı `apps/app/test/fixtures/fold_parity.json`** iki süitte de assert
      (flutter + vitest; idempotens dahil) — tek taraf değişirse diğer süit kırılır.
- [x] Drift v6: 9 `*_fold` gölge kolonu + **Dart backfill** (`backfillSearchFolds` —
      migration içinde; fold SQL'de koşamaz, kolonların varlık sebebi bu). Migration dersi:
      v3'ün `createTable(externalEvents)`'i tabloyu GÜNCEL tanımla (fold'lu) yaratır →
      v6 addColumn'ları `from >= 3` guard'ıyla (duplicate column tuzağı). `migration_test`
      v6 walk-back + seed'li satırın fold'lanmış backfill assert'i ('iş' → 'is').
- [x] İki yazım çatı noktası fold'u dolduruyor: `sync_applier` companion'ları (5 entity,
      `_foldValue` helper) + store'lar (task create/update, project create/update, note
      create/update [gövde=plainText], tag create/rename). Servis testleri satırları GERÇEK
      applier'dan geçirerek bunu da kanıtlıyor.
- [x] `SearchService` (tek SQL/domain): tier CASE (0 başlık/ad — TÜM kelimeler tek alanda;
      1 etiket — GROUP_CONCAT'li tag agregasyonu; 2 gövde), kelimeler AND + alanlar-arası
      bölünebilir, LIKE ESCAPE ile %/_ literal. `searchTasks(statuses)` /
      `searchEvents` / `searchProjects` + `searchSnippet` (fold-index → orijinal pencere).
- [x] UI (DESIGN §12): paylaşılan `AwSearchField` (debounce 250 ms + anında temizleme);
      Home'da arama modu (görev + Fikirler yakalamaları + takvim etkinlikleri tek sıralı
      listede; eşleşme bağlamı satırı — #etiket veya açıklama snippet'i; ≥150 ms
      `_DelayedProgress`; boş sonuç `AwEmptyState`; temizle → eski liste aynen), Notlar
      (onSubmitted → as-you-type'a terfi etti, motor fold'a taşındı + başlık>gövde sıralı),
      Projeler (fold sıralı filtre, çiplerle AND).
- [x] API paritesi: tasks `?q=` (NATURAL LANGUAGE MATCH — notes q'nun ikizi; ilk migration'dan
      beri boş bekleyen `ft_tasks_title_description` nihayet işinde). fakedb MATCH taklidi
      kolon listesini genelleştirdi. Bilinen ı/i boşluğu ADR-0013'te belgeli — app yolu
      otoritedir.
- [x] Testler: fold eş-sınıfları + parite fixture (2 stack), servis 7 senaryo (tier sırası,
      çok kelime AND, status kapsamı, event/proje tier'ları, wildcard literal, snippet),
      migration v6, 3 ekran akış testi (fold in→out, kapsam, boş durum, temizleme), API q=.

**DoD met 2026-07-20:** API unit + app süiti + analyze + check:i18n + lint/format yeşil;
CHANGELOG; STATE.

### OPH-168 — Pano: Home Kanban görünümü (round 8 #8, DESIGN §14) ✅ 2026-07-20

- [x] Home üstünde Liste|Pano `SegmentedButton` (`home-view-toggle`);
      `homeViewProvider` (PersistedChoice 'alliswell_home_view'). **Pano kendi kaynağını
      izler** — `boardTasksProvider` + `TaskStore.watchAll` (TÜM statuslar: completed/
      cancelled/archived sütunlarının verisi planlama listelerinde YOK; Home'un kaynağı
      yetmezdi). Arama Liste görünümüne aittir.
- [x] Sütunlar = statuslar; `boardColumnsProvider` ('alliswell_board_columns',
      virgüllü sıralı liste; `parseBoardColumns` çöpe dayanıklı); varsayılan open/
      in_progress/waiting/completed. "Görünümü düzenle" sheet'i: ReorderableListView +
      switch'ler; gizli status taşıma sheet'inde erişilebilir kalır.
- [x] Geniş: yatay kaydırmalı 320px sütunlar; telefon: PageView viewportFraction .90
      (komşu peek) + kenar bölgeleri (48dp, 400 ms hover → pager ilerler, %8 primary tını).
      _("2/5" konum etiketi ve dikey EdgeDraggingAutoScroller v1'den bilinçli kırpıldı —
      sütun içi listeler kısa; gerekirse cihaz turundan sonra.)_
- [x] Yol A: LongPressDraggable (200 ms) → sütun gövdesi komple DragTarget (kendi statusu
      reddeder; vurgulu kenarlık); feedback 1.04 ölçek %85 opasite; bırak → optimistic
      `store.update(status)` + **geri-al** snackbar + `SemanticsService.sendAnnouncement`.
- [x] Yol B (zorunlu, a11y sözleşmesi): karttaki AÇIK taşı ikonu (`board-move-button-*`;
      **spec'in gizli long-press-release menüsünden bilinçli sapma — görünür affordance
      keşfedilebilirlik kazanır**, DESIGN K3 karşılanır) → "Durum değiştir" sheet'i (tüm
      statuslar + mevcut işaretli). Detaydaki status alanı üçüncü yol.
- [x] Boş sütun: dashed-benzeri outline placeholder — drag'de "Buraya bırak", değilse
      "+ Görev ekle" → **`initialStatus`'lu create sheet** (sheet'e yeni param).
- [x] i18n `board.*` (10 anahtar). Testler 5/5: sütunlar+terminal statuslar dahil render,
      taşı-sheet'i + undo, long-press drag→drop, sütun gizleme + gizliye sheet'ten erişim,
      boş sütun status-preset create. Kontrast FAILURES: 0. Ders: sabit yükseklikli test
      yüzeyinde bottom-sheet kapama köşe-tap yerine explicit `Navigator.pop`.

**DoD met 2026-07-20:** app 362/362 + analyze + check:i18n + kontrast yeşil; CHANGELOG; STATE.

### OPH-169 — Klasörler + workspace dosyaları: API (round 8 #10a, ADR-0014) ✅ 2026-07-20

- [x] Migration `20260720100000_create_folders_and_workspace_files.js`: `folders` (ULID,
      parent_id self-FK, unique (ws,parent,name) — **NULL parent index'ten kaçar, kök
      seviye API-guard'lı**), `files.folder_id` (bilinçli FK'sız — kaskad transaction'ında
      tombstone sırası kilitlenmesin) + `workspace` enum üyesi (yerinde ALTER). `down`
      workspace satırlarını düşürüp tam geri alır. Migrate edildi (Batch 2).
- [x] `db/folders.js`: `depthUnder` (≤10), `wouldCycle`, `subtreeFolderIds` (BFS),
      **`deleteFolderSubtree`** (tek transaction'da alt klasörler + workspace dosyaları
      tombstone [her satır kendi revizyonu] + commit-sonrası obje GC; sayıları + kök
      revizyonu döner) — REST ve sync push AYNI implementasyonu kullanır.
- [x] `routes/folders.js`: list (düz ağaç), create, PATCH rename/move (`FOLDER_CYCLE`,
      `FOLDER_TOO_DEEP`, `FOLDER_NAME_TAKEN`), DELETE (sayılı). **Ad benzersizliği fold
      ile** (`lib/fold.js`) — collation'a değil app fold'una dayanır: fakedb'de de, ı/İ
      için de doğru (Finder semantiği ADR-0013 fold'uyla).
- [x] Files: init `workspace` hedefi (targetId == workspaceId şartı) + `folderId`
      (yalnız workspace hedefi + canlı aynı-ws klasörü; sıra: şekil kuralları hedef
      aramasından ÖNCE); list `?targetType=workspace[&folderId]` (folderId yok = kök
      seviye); `fileSchema`/serializer `folderId`.
- [x] Sync: `folder` SNAPSHOT_LOADERS + ENTITIES (FOLDER_FIELDS name/parentId; guard
      döngü/derinlik/fold-ad; `customDelete` → `deleteFolderSubtree`, **kontrat: kök
      revizyonu DÖNER** — framework mutation sonucuna yazar).
- [x] fakedb: `folders` tablosu + defaults (`files.folder_id` default'u dahil); MATCH
      taklidi zaten genel. Unit 4 senaryo ×281 toplam; **entegrasyon: gerçek MySQL+MinIO
      — klasör sil → presigned GET ölür (BullMQ worker poll kalıbı)**, 37/37.
      Crockford dersi yine tetiklendi ('FOLDER' O/L içerir → '01FDR…').

**DoD met 2026-07-20:** unit 281/281, entegrasyon 37/37, lint+format+no-ts yeşil;
CHANGELOG; STATE.

### OPH-170 — Global "Dosyalar" bölümü: app (round 8 #10b) ✅ 2026-07-20

- [x] Drift **v7** (v6 aramanındı — plan tek-v6 dedi ama 167 önce kapandı): `folders` +
      `file_rows.folder_id` (`from >= 5` guard'ı — v5 createTable dersinin aynısı);
      applier `folder` snapshot+tombstone + file folderId; migration_test v7.
      `FolderStore` (watchAll, create/rename/move — optimistic+outbox; `subtreeCounts`
      F9 onayı için; delete = yerel alt-ağaç + TEK kök outbox delete — server kaskadıyla
      bire bir). **API eki:** `PATCH /files/:id` artık `folderId` da alır (dosya taşıma —
      169'da atlanmıştı) + FakeApi paritesi.
- [x] `AppSection.files` (**en sonda** — BLUEPRINT §12.1 sırası; Takvim'in bıraktığı boşluk
      sayıca dolduruldu): FilesScreen — Klasörlerim | Kaynaklar SegmentedButton;
      Klasörlerim: breadcrumb (ActionChip'ler), klasör satırları (F8 `FolderLeadingTile` +
      "N öğe" — sayaçlar WATCH'la; autoDispose family'yi `ref.read`'lemek onu akış
      ortasında söker, UnmountedRef dersi), üst aksiyon satırı (Yeni klasör + Dosya yükle
      → aktif klasöre `targetType:'workspace'`+folderId — upload zinciri uçtan uca folderId
      taşıyor). Kaynaklar: workspace-geneli ekli dosya UNION'ı (yeni `watchWorkspaceAttached`)
      + `SourceBadge` (public) + "Kaynağa git" navigasyonu.
- [x] Eylemler: klasör oluştur/yeniden adlandır (ad diyaloğu), taşı (hedef seçici sheet —
      girintili ağaç, kendi alt ağacı hariç), sil (F9: `deleteFolderTitle/Body` sayılı onay;
      içindeysen breadcrumb dışarı adımlar), dosya taşı (aynı seçici → `FilesApi.move` +
      syncNow), aç/indir/yeniden adlandır/sil (mevcut sheet + `extraActions` seam'i;
      `onMore` verildiğinde görsel dahil HER tür sheet'ten geçer).
- [x] Depo kapalıysa Klasörlerim dürüst boş durum (`file.notConfiguredTitle`); Kaynaklar
      yine listelenir (metadata replikada). Dosyalar'da q araması parking'te.
- [x] i18n `nav.files` + `files.*` (18 anahtar) + `file.source*` + tur adımı (7 kart).
      Testler 4/4: breadcrumb seviyeli gezinme, oluştur+aktif klasöre yükleme (FakeApi
      folderId kanıtı), F9 sayılı silme (+push delete), Kaynaklar rozet+kaynağa-git.
      **Ders:** yeni nav etiketi 'Files' proje sekmesiyle çakıştı — testler Tab-scoped
      finder'a geçti.

**DoD met 2026-07-20:** app **366/366** + analyze + check:i18n + kontrast (FAILURES: 0)
yeşil; API unit 281 + entegrasyon 37 (169'la birlikte); CHANGELOG; STATE.

**Epic 15 DoD:** her task kendi test+i18n+kontrast+analyze yeşiliyle kapanır; epic sonunda
app+API tam süit, `check:no-ts`, `check:i18n`, `contrast.py FAILURES: 0`, CHANGELOG + STATE
+ README/ROADMAP dokunuşları (Dosyalar bölümü, arama, pano) → **v0.4.0**.

---

## Epic 16 — Feedback round 9: yenileme, tarih biçimi, alarm sistemi (Phase 10, v0.5.0)

_(Doğdu 2026-07-27 — Mahir'in 8 maddelik listesi; **ilk gerçek "alarmı kullandım" turu**.
Bağlayıcı metinler: [DESIGN](DESIGN.md) §15–§18 + §11 A3/A5/A6, [NOTIFICATIONS](NOTIFICATIONS.md)
rev. 2026-07-27 (§2/§2b/§2c/§2d/§5/§6), BLUEPRINT §4.9/§8.2/§8.4/§12.13/§14,
[ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md).
Sıra bağlayıcı: **171→174 UI akışı** (API'siz, cihazsız) → **175→181 alarm belkemiği**
(API+app) → **182/183 cihaz turu**.)_

**Round 9'un kök nedenleri — kodda doğrulandı (2026-07-27):**

| # | Şikâyet | Kodda kanıt |
| - | ------- | ----------- |
| 1 | Hiçbir ekranda aşağı çekip yenileme yok | `grep -r RefreshIndicator apps/app/lib` → **0 sonuç**; yenileme yalnız otomatik sync'e bağlı |
| 2 | Home'da yalnız arama + takvim kayıyor | `quickAdd` ve Liste\|Pano satırı `CustomScrollView`'in DIŞINDA, dış `Column`'da sabit — [home_screen.dart:120-165](../apps/app/lib/src/features/home/home_screen.dart#L120), [:221-224](../apps/app/lib/src/features/home/home_screen.dart#L221) |
| 3 | Proje/öncelik aynı hizada değil | `task.noProjectsHint` **`helperText`** olarak proje alanına yükseklik ekliyor, `Row` da `crossAxisAlignment: center` → kutular kayıyor — [task_create_sheet.dart:337-377](../apps/app/lib/src/features/tasks/ui/task_create_sheet.dart#L337) |
| 4 | Takvim bugünle açılıyor | `initialDate: current ?? now` — [task_create_sheet.dart:127](../apps/app/lib/src/features/tasks/ui/task_create_sheet.dart#L127); detayda aynısı [task_detail_screen.dart:432](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L432) |
| 5 | Tarih biçimi bozuk | `value.toString().split('.').first` → "2026-07-31 23:59:00" — [task_create_sheet.dart:207](../apps/app/lib/src/features/tasks/ui/task_create_sheet.dart#L207), [task_detail_screen.dart:415](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L415); uygulamada **6 ayrı el yapımı biçim** var, kullanıcı ayarı yok |
| 6.3 | 22:45'te (görev saati) hiçbir şey olmadı | `effectiveRemindAt = remind_at ?? (urgent ? due_at : null)` — [api/src/db/reminders.js:21](../apps/api/src/db/reminders.js#L21): **açık hatırlatıcı varsa görev saati hiç alarm üretmiyor** |
| 6.4/8 | 1. bildirim normal ding, 2. müzik, 3. sessiz | Kodda dört teslimatın **payload'ı aynı** (acil ⇒ 28 sn `aw_alarm.caf` + `timeSensitive`) → fark OS tarafında. Bilinen mekanizma: `UNNotificationSound(named:)` sesi çözemezse iOS **sessizce varsayılan ding'e düşer**; ayrıca `timeSensitive` özel ses **zil ses seviyesinde** çalar ve **sessiz anahtarı onu tamamen susturur** (NOTIFICATIONS §2). Teşhis kaydı olmadığı için hangisi olduğu kanıtlanamıyor → OPH-176 |
| 6.6 | Erteleme sonrası "yine 1. bildirim" | Zincir `snoozedUntil`'den **index 0'dan** yeniden kuruluyor → gövde tekrar `notif.urgentFirst` ("Acil hatırlatıcı — onay bekliyor") — [planner.dart:70-91](../apps/app/lib/src/notifications/planner.dart#L70) |
| 6.7 | Süresiz erteleme yok | Reminder statusleri yalnız scheduled\|snoozed\|delivered\|acknowledged\|completed\|cancelled — susturma durumu **yok** |
| 6/8 | Uygulama açıkken çan sesi yok | `AlarmFeedback` yalnız haptik: `HapticAlarmFeedback` — [alarm_overlay.dart:138-160](../apps/app/lib/src/notifications/alarm_overlay.dart#L138); **hiç ses çalar yok** (pubspec'te audio paketi yok) |
| 7 | Hatırlatıcı sayısı/sıklığı/sesi ayarlanamıyor | `kUrgentChainOffsets = [0, +2, +5, +10, +30]` **sabit** — [planner.dart:38](../apps/app/lib/src/notifications/planner.dart#L38); ses de sabit tek dosya |
| **8** | **Ekran kapalıyken/sessizde ses gelmiyor** | **AlarmKit hiç devreye girmedi:** `AlarmKitBridge.swift` **hiçbir Xcode hedefinde değil** ve `AppDelegate` onu kurmuyor ([ALARMKIT_SETUP.md](../apps/app/ios/Runner/ALARMKIT_SETUP.md) kendi uyarısı) → `MethodChannelAlarmKitHost.isSupported()` `MissingPluginException` → `false` → acil alarmlar `timeSensitive` bildirim hattında kalıyor; **o hat sessiz anahtarını aşamaz.** iPhone'un kendi alarm/sayaç davranışının (tam ekran, ertele/durdur, sessizi delen ses) tek meşru yolu AlarmKit'tir |

> **Sürüm kararı:** 171–174 tek başına kullanıcıya hemen değer verir (v0.4.1 ara sürümü
> olabilir); 175–181 birlikte "alarm belkemiği v2" (v0.5.0); 182/183 cihaz turuna biner.

### OPH-171 — Aşağı çekip yenileme: Home, Fikirler, Projeler, Notlar, Dosyalar (round 9 #1) ✅ 2026-07-28

- [x] **Tek paylaşılan sarmalayıcı** `apps/app/lib/src/widgets/refreshable.dart` →
      `AwRefresh({required Future<void> Function() onRefresh, required Widget child,
      double displacement, Key? indicatorKey})`: `RefreshIndicator` üstüne token'lı
      giydirme (`colorScheme.primary` çizgi, `surfaceContainerHigh` zemin, `AwRadius`
      gölge yok — DESIGN §15 R1). **Her ekran kendi listesini sarar, gövdeyi DEĞİL:**
      spinner sabit filtre satırının ALTINDA, listenin üstünde doğsun (kullanıcının
      tarifi: "üst filtrelerle arasında bir loading circle çıkar"). Home 172'den sonra
      tek kaydırma olduğu için orada app bar'ın altında doğar.
- [x] **Yenileme eylemi** `refreshSection(ref, AppSection)` (`sync/providers.dart`
      yanında yeni `sync/refresh.dart`): `syncEngineProvider?.syncNow()` + bölüm ekstraları
      (Home: `externalEventsProvider` + `alarmSupportProvider` invalidate; Dosyalar:
      `storageStatusProvider`; Fikirler/Projeler/Notlar: yok). **Minimum 450 ms**
      göster (`Future.wait([work, Future.delayed(450ms)])`) — yerel replika 20 ms'de
      döner, spinner'ın çakıp kaybolması "çalışmadı" gibi görünür (R2). Hata →
      `localizedError` snackbar, liste yerinde kalır (R4).
- [x] **Boş liste de çekilebilir:** her sarılan scrollable'a
      `physics: const AlwaysScrollableScrollPhysics()` — yoksa "Hepsi tamam" boş
      durumunda jest hiç başlamaz (klasik tuzak). Home'un `SliverFillRemaining`
      boş durumu dahil.
- [x] **Beş yüzey:** Home Liste (`home-scroll` CustomScrollView) **ve Pano** (her
      sütunun dikey `ListView`'ı aynı handler'ı alır; yatay `PageView` etkilenmez —
      200 ms long-press drag ile çekme jesti çakışmaz, testle kanıtla),
      Fikirler ([task_list_screen.dart:49](../apps/app/lib/src/features/tasks/ui/task_list_screen.dart#L49)),
      Projeler ([:99](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L99)),
      Notlar (**liste VE ızgara** — [:117](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L117), [:220](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L220)),
      Dosyalar (**Klasörlerim VE Kaynaklar** — [:452](../apps/app/lib/src/features/files/ui/files_screen.dart#L452), [:532](../apps/app/lib/src/features/files/ui/files_screen.dart#L532)).
- [x] **İşaretçi-only platformlar dürüstlük gereği:** `RefreshIndicator` fare
      tekerleğiyle tetiklenmez → geniş yerleşimde (≥800 px) app bar'a `refresh`
      IconButton'u ekle (`buildSectionAppBar`'a `onRefresh` parametresi; telefonda
      gizli, çünkü orada jest var). Web/masaüstü ile mobil aynı yeteneğe sahip olur.
- [x] i18n: `common.refresh`, `common.refreshFailed`. Testler **8/8**
      (`test/features/refresh_test.dart`) — sayaç fake engine değil **FakeApi'nin
      `/sync/pull` istekleri** (kullanıcının kanıtıyla aynı: "gidip baktı mı?"):
      Home listesi; **boş** Fikirler kutusu; Projeler + Notlar; Dosyalar'ın iki
      katmanı; Pano sütunu **+ long-press drag'in hâlâ status değiştirdiği
      regresyonu**; çevrimdışı → snackbar + veri yerinde; geniş yerleşimde buton
      çalışıyor, telefonda **yok**. Kontrast: FAILURES: 0.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **`SyncEngine.syncNow()` artık `Future<bool>` döner.** Eskiden hatayı yutup
  backoff kuruyordu — bu yüzden UI kullanıcıya "yenilenemedi" diyemezdi (R4
  imkânsızdı). Sözleşme: `true` = yakınsadı **veya yapacak iş yoktu** (durdurulmuş
  motor, zaten süren tur); `false` = başarısız, retry kurulu. Arka plan çağıranların
  hepsi dönüşü yok sayar; okuyan tek yer pull-to-refresh.
- **Boş/hata durumları drag'i yutuyordu.** `AwEmptyState`/`AwErrorState` içlerinde
  (taşma koruması için) kendi `SingleChildScrollView`'ini taşıyor; kaydırmayan bir
  iç scroll view jesti yine de kapıyor → `AwRefresh` hiç tetiklenmiyor. Çözüm: iki
  duruma `physics` parametresi + iki tarif (doğrudan `AwRefresh` altındaysa
  **Always**, zaten kayan bir ebeveynin/sliver'ın içindeyse **Never**). Home'un
  sliver içindeki boş durumu Never, geniş yerleşimdeki aynı durum Always.
- **Bilinçli v1 sınırı:** telefonda **arama modunda** Home çekilemiyor — sonuç
  listesi `SliverFillRemaining` içinde iç içe bir scrollable, bildirim `depth != 0`
  ile geliyor ve `RefreshIndicator` onu görmezden geliyor. OPH-172 Home'u tek
  sliver ağacına çevirirken düzelecek (arama sonuçları sliver olacak); Liste/Pano/
  boş durum çekilebilir olduğu için kullanıcı akışı etkilenmiyor.
- **Test dersi (yine `localKv`):** Pano testinin seçtiği `alliswell_home_view=board`
  **global singleton üzerinden sonraki teste sızıp** Home'u Pano açıyordu (bu
  yüzden `home-scroll` bulunamıyordu) → dosya başına `setUp` ile anahtar silinir.
- **FakeApi'ye `offline` anahtarı** eklendi (her isteğe 503) — çevrimdışı yolunu
  kanıtlamanın en sade hâli. Test sonunda `offline=false` + `pump(2s)`: motorun
  kurduğu **1 sn'lik backoff timer'ı** ateşlenmezse flutter_test "pending timer"
  ile düşer.

**DoD met 2026-07-28:** app **397/397** (~19 skip) + `flutter analyze` temiz +
`check:i18n` yeşil + `contrast.py FAILURES: 0`; CHANGELOG; STATE. _Cihazda
dokunma hissi (iOS lastik bantı, Android stretch) cihaz turuna kaldı — testler
gerçek jesti sürüyor ama cihaz dokusunu ölçemez._

### OPH-172 — Home tek kaydırma katmanı: yalnız başlık + ayarlar sabit (round 9 #2) ✅ 2026-07-28

- [x] **Dar yerleşimde (telefon) `CustomScrollView`'e taşınacaklar** (sırayla, hepsi
      sliver): `AlarmDegradationBanner` → Liste\|Pano satırı (+ Pano'nun `tune`
      butonu) → `QuickAddBar` → arama alanı → takvim kartı → "Takvimi gizle/göster"
      → gruplu liste. **Sabit kalan tek şey `AppBar`** ("Anasayfa" + ayarlar) —
      kullanıcının cümlesi budur. Geniş yerleşim (≥720) DEĞİŞMEZ (takvim yan panel,
      şikâyet telefona ait).
- [x] **Pano modunda istisna (DESIGN §16 H3):** yatay `PageView` kaydırılamayacağı
      için Liste\|Pano satırı Pano'da **sabit kalır** (aksi hâlde Liste'ye dönüş yolu
      kaybolur). Bilinçli sapma, gerekçesiyle DESIGN'a yazılır.
- [x] **Hızlı ekleme kaydırılınca yazdığını kaybetmesin:** `QuickAddBar`'ın
      `TextEditingController`'ı ebeveyne taşınır (state hoisting; sliver cache
      extent dışına çıkınca widget dispose olur ve metin uçar), odak kazandığında
      `Scrollable.ensureVisible` ile geri getirilir. Test: metin yaz → 600 px kaydır
      → geri kaydır → metin yerinde.
- [x] Testler **5** (4 + devralınan arama sınırı): liste modunda toggle+quick-add viewport'tan çıkıyor (kaydırma
      offset'i ile); Pano'da toggle duruyor; quick-add metni kaydırmadan sağ çıkıyor;
      geniş yerleşim regresyonsuz. Kontrast + `flutter analyze` yeşil.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Yapı LayoutBuilder-önce oldu.** Banner + Liste|Pano satırı eskiden dış
  `Column`'da, LayoutBuilder'ın DIŞINDAYDI — bu yüzden telefonda sabit kalıyorlardı.
  Artık üç dal var: geniş (≥720, H2 — hiçbir şey değişmedi), **telefon+Pano**
  (H3 — banner + toggle sabit, pager altta), **telefon+Liste** (H1 — tek
  `CustomScrollView`, yalnız app bar sabit).
- **`HomeScreen` artık `ConsumerStatefulWidget`.** Hızlı eklemenin
  `TextEditingController`'ı + `FocusNode`'u ekranda yaşıyor; `QuickAddBar` ikisini
  parametre olarak alıyor (vermeyen — Fikirler — kendi state'ini kurmaya devam eder,
  **sahibi neyi yarattıysa onu dispose eder**). Odak gelince `Scrollable.ensureVisible`
  (yalnız kaydırılabilir bir ata varsa) alanı geri getiriyor.
- **Test dişli:** metin testi, -900 kaydırmadan sonra `home-quick-add` widget'ının
  **ağaçtan silindiğini** de doğruluyor — yani metin ancak hoisted controller'da
  hayatta kalabilmiş olur. (Kaydırma öncesi/sonrası eşitlik iddiası tek başına
  cache extent'e takılıp yalancı-yeşil olabilirdi.)
- **OPH-171'in bıraktığı sınır KAPANDI:** `_HomeSearchResults` artık **sliver
  döndürüyor** (`SliverPadding`/`SliverFillRemaining`/`SliverToBoxAdapter`), yani
  arama sonuçları Home'un tek kaydırma ağacının parçası → telefonda **arama modunda
  da aşağı çekip yenileme çalışıyor** (yeni test bunu ölçüyor). Geniş yerleşimde
  aynı sliver'a kendi `CustomScrollView`'i veriliyor.
- Sağlayıcı okumaları build başına toplandı (`homeCalendarVisibleProvider` artık
  LayoutBuilder callback'i içinde değil — layout geçişi provider'a abone olmasın).
- Eski testin adı düzeltildi: "quick-add stays pinned" → **"the quick-add still
  captures"** (sözleşme değişti; iddia değişmedi).

**DoD met 2026-07-28:** app **402/402** (~19 skip) + `flutter analyze` temiz +
`check:i18n` + `contrast.py FAILURES: 0`; CHANGELOG; STATE.

### OPH-173 — Detaylı ekleme: proje/öncelik hizası + "yarın" varsayılanı (round 9 #3, #4) ✅ 2026-07-28

- [x] **"Henüz proje yok" yazısı kalkar:** `helperText` kaldırılır, `task.noProjectsHint`
      anahtarı **en.json + tr.json'dan silinir** (`npm run check:i18n` yetim anahtarı
      yakalar). Gerekçe kullanıcının: liste açılınca proje olmadığı zaten görülür ve
      picker'da "+ Proje ekle" (OPH-163) duruyor — o satır yalnız hizayı bozuyordu.
- [x] **Hiza garantisi:** `Row(crossAxisAlignment: CrossAxisAlignment.start)` + iki
      `Expanded` → ileride bir alan `errorText` gösterse bile kutular aynı üst hizada
      kalır (bugün merkezden hizalandığı için farklı yüksekliklerde kayıyorlar).
      Aynı satır deseni detay ekranında da doğrulanır.
- [x] **Varsayılan tarih = YARIN:** yeni saf yardımcı
      `DateTime awInitialPickerDate({DateTime? current, DateTime? anchor, required DateTime now})`
      → `current ?? anchor ?? now + 1 gün` (`core/date_format.dart` içinde, 174 ile
      aynı dosya). Bitiş tarihi: `anchor = null` → **yarın**. Hatırlatıcı: `anchor = _dueAt`
      → bitişin GÜNÜ (bitiş 31'indeyse hatırlatıcı da 31'inde açılır, "yarın"da değil).
      Detaydaki `_DateRow` aynı kuralı kullanır. Home FAB'ın seçili-gün prefill'i
      (`initialDue`) her zaman kazanır. `firstDate` aynı kalır (geçmiş 365 gün).
- [x] Testler **4**: bitiş tile'ına dokun → date picker'ın seçili günü yarın; bitiş
      doluyken hatırlatıcı picker'ı bitiş gününde açılıyor; seçili-gün prefill'i
      bozulmadı; proje-öncelik satırı iki alanda eşit yükseklikte (golden yerine
      `tester.getSize` karşılaştırması — piksel testi kırılgan).

**Uygulamada ortaya çıkanlar (2026-07-28):**

- Yeni saf yardımcı **`awInitialPickerDate({current, anchor, now})`**
  (`core/date_format.dart` — 174 aynı dosyayı biçimlendiricilerle dolduracak):
  `current ?? anchor ?? yarın`. Gün aritmetiği **constructor ile** yapılıyor
  (`DateTime(y, m, d + 1)`), `add(Duration(days: 1))` ile değil — DST'li bir
  bölgede 24 saat eklemek takvim gününü kaydırabilir; birim testi bunu da tutuyor.
- `anchor` üç yerde bağlandı: create sheet'te hatırlatıcı → `_dueAt`; detayda
  **hatırlatıcı ve "Planlanan"** satırları → `task.dueAt`; bitiş satırı anchor'suz
  (yarın). Home FAB'ın seçili-gün prefill'i `current` olarak geldiği için kazanmaya
  devam ediyor.
- `Row(crossAxisAlignment: start)` + `helperText`'in kalkması hizayı çözdü;
  **test bunu piksel karşılaştırmasıyla** kanıtlıyor (`getRect().top` ve `.height`
  eşit) — golden'a gerek yok, kırılgan da değil.
- **Mevcut test yeni sözleşmeye çevrildi:** "create sheet explains when there are
  no projects yet (OPH-106)" → "with no projects the picker stays, WITHOUT a hint
  line"; artık ipucunun **olmadığını** ve iki alanın aynı hizada olduğunu doğruluyor.
  (OPH-106'nın asıl niyeti — picker gizlenmesin — korunuyor.)
- Tarih testleri **davranışsal**: picker'ları dokunmadan onaylayıp **oluşan görevin
  `dueAt`/`remindAt`'ini** ölçüyor; picker'ın iç metnine bakmadıkları için
  OPH-174'ün biçim değişikliğinden etkilenmeyecekler.

**DoD met 2026-07-28:** app **409/409** (~19 skip; +3 davranış testi, +5 birim) +
`analyze` temiz + `check:i18n` yeşil (yetim anahtar yok — `task.noProjectsHint`
en+tr'den silindi) + kontrast FAILURES: 0; CHANGELOG; STATE.

### OPH-174 — Tarih/saat gösterimi: tek kaynak + kullanıcı biçimi ayarı (round 9 #5) ✅ 2026-07-28

- [x] **Tek biçimlendirici** `apps/app/lib/src/core/date_format.dart`:
      `awFormatDateTime/awFormatDate/awFormatTime/awFormatShort(value, {format, locale})`.
      Presetler (`kAwDateFormats`, hepsi aynı örnek anla önizlenir — 31.12.2026 23:59):
      `system` (locale-duyarlı `DateFormat.yMd().add_Hm()`; tr'de zaten **31.12.2026 23:59**),
      `dd.MM.yyyy HH:mm`, `dd/MM/yyyy HH:mm`, `MM/dd/yyyy h:mm a`, `yyyy-MM-dd HH:mm`,
      `d MMMM yyyy HH:mm` (31 Aralık 2026 23:59), `EEE d MMM HH:mm` (kısa satır biçimi).
      `awFormatShort` liste satırları için yılı **bu yılsa** atar (task_tile'ın bugünkü
      davranışı korunur, ama biçimi ayardan gelir).
- [x] `dateFormatProvider = NotifierProvider<PersistedChoice,String>('alliswell_date_format',
      fallback: 'system')`; bilinmeyen/bozuk değer → `system` (bozuk tercih hiçbir ekranı
      düşürmez — `parseTaskTime` dersi).
- [x] **Bütün el yapımı biçimler buraya bağlanır (hiçbiri kalmaz):**
      create sheet `_format` ([:207](../apps/app/lib/src/features/tasks/ui/task_create_sheet.dart#L207)),
      detay `_DateRow` ([:415](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L415)),
      `task_tile._formatDue` ([:19](../apps/app/lib/src/features/tasks/ui/task_tile.dart#L19)),
      `notes_screen` tarih ([:18](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L18)),
      `file_widgets` `DateFormat.yMMMd` ([:100](../apps/app/lib/src/features/files/ui/file_widgets.dart#L100)),
      `settings_screen._formatDeadline` ([:313](../apps/app/lib/src/screens/settings_screen.dart#L313)),
      Home quick-add ipucundaki ISO gün ([:114](../apps/app/lib/src/features/home/home_screen.dart#L114)),
      `external_event_tile` saat ([:19](../apps/app/lib/src/features/calendar/ui/external_event_tile.dart#L19)),
      **ve `widget_snapshot`** ([:126/:130](../apps/app/lib/src/features/widgets/widget_snapshot.dart#L126)) —
      seçilen biçim snapshot JSON'una yazılır, yoksa ana ekran widget'ı uygulamadan
      farklı tarih gösterir.
- [x] Ayarlar → **"Tarih biçimi"** satırı: radio sheet, her seçenek aynı örnek anı
      kendi biçiminde gösterir (DESIGN §17 D2 — kullanıcıya `dd.MM.yyyy` gibi teknik
      dizge ASLA gösterilmez, yalnız sonucu). i18n `settings.dateFormat.*`.
- [x] Testler **5**: her preset örnek anı beklenen dizgeye çeviriyor; bozuk tercih →
      system; tr/en locale'de `system` doğru; task_tile + create sheet ayarı izliyor;
      widget snapshot biçimi taşıyor.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Presetler ICU kalıbı değil, `id` ile saklanıyor** (`system`, `dmy_dot`,
  `dmy_slash`, `mdy_12h`, `iso`, `dmy_long`) — depolama intl kalıplarına
  bağlanmasın; `awDateFormatSpec` bilinmeyen/emekli id'yi **system**'e düşürür
  (`parseTaskTime` dersinin aynısı). Spec üç parça taşır: `date`, `time`,
  **`short`** (liste satırı, yılsız — D4).
- **Sağlayıcı mı global mi:** i18n gibi bir singleton yerine **`dateFormatProvider`**
  (PersistedChoice, `core/persisted_prefs.dart`) seçildi; biçimlendiriciler saf
  kaldı (`format` + `locale` parametre). Bunun bedeli tek yerde ödendi:
  `external_event_tile` düz `StatelessWidget`'tan `ConsumerWidget`'a çevrildi.
- **`system` gerçekten sistemi izliyor:** `DateFormat.jm(locale)` → tr 24 saat
  (`23:59`), **en 12 saat** (`11:59 PM`). Bu, İngilizce'de görev satırlarının ve
  **ana ekran widget'ının** saat biçimini bilinçli olarak değiştirdi (DESIGN §17
  D3 böyle yazılmıştı); 24 saat isteyen `dmy_dot`/`iso` seçiyor.
- **Widget snapshot'ı biçimi taşıyor:** `buildWidgetSnapshot(..., dateFormat:)` +
  `widgetSyncProvider` tercihi **watch** ediyor → biçim değişince snapshot
  yeniden yayınlanıyor. Aksi hâlde widget ile uygulama aynı ekranda çelişirdi.
- **Test dersi (CLDR):** `DateFormat.jm` AM/PM'den önce **narrow no-break space
  (U+202F)** koyuyor; `'11:30 AM'` beklentisi görünmez bir farkla düşüyordu →
  o iki testte parça bazlı (`contains`) doğrulama yapılıyor. Açık `h:mm a`
  kalıbında normal boşluk kalıyor, orada tam eşitlik tutuluyor.
- **Eski ham biçimler kalmadı:** `calendar_mirror_test`'teki son
  `toString().split('.')` beklentisi de biçimlendiriciye çevrildi (round 9'un
  şikâyet ettiği dizgenin kendisiydi).

**DoD met 2026-07-28:** app **417/417** (~19 skip; +11 birim, +2 widget) +
`analyze` temiz + `check:i18n` yeşil + kontrast FAILURES: 0; CHANGELOG; STATE.

### OPH-175 — "Görev saati de bir alarmdır": iki alarm örneği (round 9 #6.3) — API + app ✅ 2026-07-28

**Kullanıcının cümlesi:** _"velevki acil olarak işaretledim ama hatırlatıcı kurmadım —
en azından tam task saatinde bu müzikli bildirim gelmeliydi, alarm gibi."_ Bugün tam
tersi çalışıyor: hatırlatıcı KURULDUYSA görev saati sessiz geçiyor.

- [x] **Migration** `2026XXXXXXXXXX_add_reminder_kind.js` (append-only):
      `reminders.kind` ENUM('remind','due') NOT NULL DEFAULT 'remind'. **Unique index
      YOK** (terminal satırlar tarih olarak birikiyor; seçim "en yeni aktif satır"
      kalıbıyla yapılır — mevcut kod da böyle). Backfill: `remind_at` null + görev
      urgent+due ise `'due'`, değilse `'remind'`. `down` kolonu düşürür.
- [x] **`effectiveRemindAt` → `alarmInstantsFor(task)`** ([api/src/db/reminders.js](../apps/api/src/db/reminders.js)):
      `[{kind:'remind', at: task.remind_at}, {kind:'due', at: task.due_at}]` — `due`
      yalnız `is_urgent`; **iki an eşitse yalnız `remind` kalır** (tek an için iki kez
      çalmak hata olur); görev susturulmuşsa (OPH-178) **boş liste**. Tek seam kalır:
      REST + sync push + takvim job'ı hep bunu çağırır.
- [x] **`reconcileTaskReminder` tür başına döner:** her kind için upsert/terminalize,
      her satır kendi revizyonu. "remind_at kaydıysa tam yeniden kur, değilse yalnız
      görev alanlarını yansıt (erteleme korunur)" kuralı satır bazında aynen korunur —
      başlık yaması hiçbir alarmı uyandırmaz.
- [x] **Sync + REST sözleşmesi:** `reminder` varlığına `kind` (sunucu-yazar, istemci
      okur), serializer'lar (`routes/reminders.js`, `routes/sync.js`) alanı yayar.
      `POST /tasks/:taskId/snooze` **opsiyonel `reminderId`** alır: verilirse yalnız o
      alarm ertelenir (çalan alarm hangisiyse), verilmezse görevin tüm aktif alarmları
      (geriye dönük uyumlu, app'in bugünkü çağrısı bozulmaz).
- [x] **App:** drift **v8** (`reminders.kind`, `from >= 7` guard'ı — v5/v7 dersi),
      applier, `AlarmInput.kind`, `ReminderStore.watchAlarms` **her iki türü** sentezler
      (sentetik id şeması `local:remind:<taskId>` / `local:due:<taskId>`;
      `acknowledge()`'in çözücüsü türü ayrıştırıp aynı türden aktif satırı bulur —
      bugünkü `local:<taskId>` şeması tek satır varsayıyor).
- [x] **Gövde:** görev-saati alarmı yeni anahtar `notif.dueNow` ("Görev saati geldi —
      onay bekliyor"); zinciri profilden gelir (OPH-179), yüksekliği acil sözleşmesidir
      (OPH-176). Hatırlatıcı alarmı bugünkü metinlerini korur.
- [x] Testler: API unit (`alarmInstantsFor` tablosu: yalnız remind / yalnız due /
      ikisi / eşit an tekilleştirme / susturulmuş; reconcile iki satır kurar, `due_at`
      kayarsa yalnız `due` yeniden kurulur, tamamlama ikisini de terminalize eder),
      entegrasyon (REST create → 2 satır; sync pull `kind` taşıyor), app (watchAlarms
      2 alarm, planner iki farklı gövde, acknowledge doğru satırı bulur).

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **`alarmInstantsFor` tek karar noktası oldu:** "görev canlı mı" kontrolü de
  (silinmiş/tamamlanmış/iptal/arşiv **ve** ileride `alarms_muted_at`) buraya taşındı,
  böylece sunucu ile uygulamanın aynaladığı **tek** kural var. `reconcileTaskReminder`
  artık `ALARM_KINDS` üzerinde dönen ince bir sarmalayıcı + tür başına `reconcileOne`;
  "remind_at kaydıysa tam yeniden kur, yoksa yalnız alanları yansıt" kuralı satır
  bazında korundu (test: bitiş kayarken hatırlatıcı satırının **revizyonu artmıyor**).
- **`alarms_muted_at` şimdiden tolere ediliyor** (`task.alarms_muted_at != null`
  kontrolü kolon yokken `undefined` olduğu için sessizce geçer) — OPH-178 kolonu
  eklediğinde motor tarafında değişiklik gerekmeyecek.
- **Erteleme sözleşmesi düzeltildi:** eskiden yalnız "en yeni aktif satır"
  erteleniyordu; iki alarmlı bir görevde bu, kullanıcı erteledikten 3 dakika sonra
  ikinci alarmın çalması demekti. Artık `reminderId` verilmezse **hepsi**, verilirse
  **yalnız o** ertelenir (çalan alarm kendi id'sini biliyor).
- **Sentetik id şeması `local:<kind>:<taskId>`** (`syntheticReminderId` /
  `parseSyntheticReminderId`); eski `local:<taskId>` biçimi **hâlâ çözülüyor**
  (yükseltmeden sağ çıkan bir id 'remind' sayılır). `acknowledge` artık **aynı türden**
  satırı arıyor: 21:42 uyarısını onaylamak 21:45 alarmını susturmaz (test var).
- **Round 6'nın testi tersine çevrildi:** "an explicit remindAt wins over the
  deadline" → "**does NOT swallow** the deadline alarm". Bilinçli sözleşme değişikliği;
  eski niyet (bir an iki kez çalmasın) eşit-an tekilleştirmesiyle korunuyor.
- **Gerçek MySQL dersi:** `ORDER BY kind` bir ENUM'da **alfabetik değil, tanım
  sırasıyla** sıralar (`remind`, `due`) — entegrasyon testi bu yüzden JS'te sıralıyor.
  fakedb bunu gösteremezdi; entegrasyon testi tam bu yüzden var.
- **Ortam notu (dikkat):** bu repoda `npm run db:rollback` = `knex migrate:rollback
  **--all**` → 13 migration geri alınır ve **yerel dev veritabanı boşalır**. `down`u
  doğrulamak için koştum; yerel demo verisi gitti (prod'a dokunulmadı). Bir dahaki
  sefere tek migration için `npx knex migrate:down`.

**DoD met 2026-07-28:** API unit **288/288** + **entegrasyon 39/39 (gerçek MySQL —
migration uygulandı, `down` + yeniden `up` denendi)** + lint/format/no-ts yeşil;
app **425/425** + analyze + `check:i18n` + kontrast yeşil; CHANGELOG; STATE.

### OPH-176 — Tek yükseklik sözleşmesi + alarm günlüğü (round 9 #6.1, #6.4, #8 teşhisi) ✅ 2026-07-28

- [x] **Sözleşme (NOTIFICATIONS §2 rev.):** bir acil alarmın **her slotu** — ilki,
      tekrarları ve **her erteleme sonrası turu** — aynı yükseklikte çalar: Android'de
      alarm kanalı (`USAGE_ALARM` + `FLAG_INSISTENT` + alarmClock), iOS'ta alarm sesi +
      `timeSensitive` (critical grant varsa `.critical`/1.0). **Hiçbir slot "sade
      bildirim" değildir.** Normal hatırlatıcılar kullanıcının seçtiği hatırlatıcı
      sesini alır (OPH-181; varsayılan: OS sesi).
- [x] **Dürüst etiketler:** slot 1 `notif.urgentFirst`, slot n `notif.urgentRepeat(n)`,
      **erteleme sonrası** yeni anahtar `notif.afterSnooze` ("Erteleme sonrası — onay
      bekliyor ({round}. tur)"), görev saati `notif.dueNow`. Kullanıcının "yine 1.
      bildirim gibi geldi" şikâyeti buradan kalkar.
- [~] **iOS ses çözümleme bekçisi — OPH-181'e TAŞINDI (gerekçeli):** `UNNotificationSound(named:)` dosyayı çözemezse
      iOS **sessizce varsayılan ding'e düşer** (belgelenmiş davranış + yaygın hata).
      Başlatmada sesin varlığını doğrula (bundle → app container `Library/Sounds`);
      çözülemiyorsa günlüğe yaz + Ayarlar'daki alarm durum satırında söyle
      ("özel ses bulunamadı — varsayılan sesle çalacak"). Sessiz düşüş yasak.
- [x] **Alarm günlüğü** (yerel, sync DIŞI): drift tablosu `alarm_events` (halka tampon
      ~200 satır) — `scheduled | cancelled | interacted | ring_shown | action`; alan
      seti: an, lane (`notification | alarmkit | inapp`), slot index, kind, urgent,
      ses adı, interruption level, taskId/reminderId. Ayarlar → **"Alarm günlüğü"**
      (salt-okunur liste + "kopyala"). **Dürüstlük notu ekranda:** iOS, kullanıcı
      dokunmadığı bir bildirimin "teslim edildi" bilgisini vermez — günlük
      PLANLANANI, ETKİLEŞİMİ ve uygulama-içi çalmayı kaydeder, "teslim edildi"
      iddiasında bulunmaz.
- [x] Testler: planner gövde/slot tablosu (ilk/tekrar/erteleme/görev-saati),
      scheduler günlüğe yazıyor, bekçinin degraded durumu Ayarlar satırına düşüyor.
      **Bu task 6.4'ün kanıtını üretir** — sonraki cihaz turunda tahmin değil kayıt
      konuşur.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Yükseklik kararı SAF bir fonksiyona çıktı:** `awDeliveryFor({urgent,
  criticalEnabled})` → `ScheduledDelivery(sound, level)` (`gateway.dart`).
  `gateway_local` artık kararı vermiyor, **taşıyor**; `schedule()` bu tanımı
  **döndürüyor**, böylece alarm günlüğü "ne istendi"yi kararı veren katmandan
  alıyor (tahminden değil). Sözleşme testle çivilendi: bir zincirin **her** slotu
  `urgent` ve aynı `sound/level` çiftine çözülüyor — "sessiz ilk slot" diye bir şey
  yok.
- **Erteleme etiketi `status == 'snoozed'` ile geliyor** — yeni kolon gerekmedi;
  `notif.afterSnooze` ("Erteleme sonrası — hâlâ onay bekliyor"). **Tur sayacı
  (`{count}. tur`) OPH-177'ye kaldı**: `reminders.snooze_count` orada gelecek,
  o zaman metin sayılı varyanta geçer (planner'da tek satır).
- **iOS ses bekçisi neden 181'e taşındı:** bundle içeriğini Dart'tan doğrulamak
  **yeni bir native kanal** ister; `flutter analyze`/`test` Swift derlemediği için
  burada yazılıp doğrulanamayan bir köprü olurdu (AlarmKit dersi). 176'da tek
  ses **paketli** `aw_alarm` ve varlığı pbxproj'dan biliniyor; asıl risk
  **kullanıcı sesi**yle doğuyor → probe, dosya boru hattının kurulduğu OPH-181'e
  eklendi. 176 bu arada sesin **adını ve seviyesini günlüğe yazıyor**, yani
  sonraki cihaz turunda "hangi ses istendi?" sorusu kayıttan cevaplanıyor.
- **Teşhis, teşhis ettiği şeyi bozamaz:** `alarmSupportProvider` içindeki günlük
  yazımı ilk denemede probe'u yutuyordu — veritabanı olmayan bir yüzeyde
  (odaklı widget testi) probe komple `catch`'e düşüyor ve **alarmları KAPALI bir
  cihaz sağlıklı görünüyordu**. Tam olarak A6'nın engellemek için var olduğu yalan.
  Artık `unawaited` + kendi `try/catch`'i var; `AlarmLog.record` de kendi içinde
  yutuyor (test: kapalı veritabanında `record` yine `completes`).
- **Günlük halka tamponu** (`alarm_events`, drift **v9**, 200 satır) **sync DIŞI**:
  ne entity, ne outbox. Yazanlar: scheduler (kuruldu/geri alındı, iki lane),
  aksiyon yönlendiricisi (dokunuldu/düğme), ring ekranı (uygulamada çaldı),
  izin probu (kısıtlı teslimat). Ekran: Ayarlar → "Alarm günlüğü" (salt-okunur,
  **kapsam cümlesi verinin ÜSTÜNDE**, panoya kopyala). Satırın alt metni
  kasıtlı olarak **veri** (`sound=… level=… slot …`) — hata raporuna birebir gider.

**DoD met 2026-07-28:** app **437/437** (~19 skip; +12 yeni test) + `analyze` temiz +
`check:i18n` + kontrast FAILURES: 0; API dokunulmadı (288 + 39 hâlâ yeşil);
CHANGELOG; STATE.

### OPH-177 — Erteleme netliği: ne olacağını söyle, göster, aynı yükseklikte çal (round 9 #6.5, #6.6) ✅ 2026-07-28

- [x] **Ne olacağını söyle:** ring ekranındaki ve bildirimdeki erteleme seçenekleri
      sonucu yazar ("5 dk sonra tekrar çalar"); erteledikten sonra snackbar
      "22:52'de tekrar çalacak" (kullanıcının sorusu birebir: _"5 dk sonra ne olacak?"_).
- [x] **Göster:** görev satırında ve detayda `Ertelendi — 22:52` göstergesi
      (`task.snoozedUntil` bugün hiçbir yerde görünmüyor); alarm ikonu ertelenmiş
      tonda. Görev tamamlanmış gibi görünmez.
- [x] **Aynı yükseklikte çal:** erteleme sonrası tur profilin TAM zincirini kurar
      (OPH-179) ve OPH-176 sözleşmesine uyar. Tur sayacı için `reminders.snooze_count`
      (migration + REST/sync artırımı) — planner `notif.afterSnooze` içinde kullanır.
- [x] **Özel ertele** (BLUEPRINT §8.2'de yazılı, UI'da yok): tarih-saat seçici;
      `POST /tasks/:id/snooze { snoozeUntil }` zaten var.
- [x] Testler: preset alt metinleri, snackbar, satırdaki ertelendi göstergesi,
      erteleme sonrası planın slot sayısı + gövdesi, özel erteleme akışı.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Preset butonları artık iki satır:** "5 dk" + **"22:47'de çalar"** — sorunun
  ("5 dk sonra ne olacak?") cevabı butonun üstünde duruyor; ertelenince de
  snackbar **"22:52'de tekrar çalacak"** diyor. Bildirim aksiyon düğmelerinin
  metni OS'ta kısa kalmak zorunda, o yüzden bu netlik **ring ekranında** yaşıyor.
- **`reminders.snooze_count`** migration (gerçek MySQL'de uygulandı) + REST
  ertelemede **ve** sync push aynasında artırım; `reconcileTaskReminder`'ın tam
  yeniden kurma yaması **0'a çekiyor** — kayan bir an yeni alarmdır, "7. tur"
  değil. Planner `notif.afterSnooze`'u **sayılı** varyanta geçti; sayacı olmayan
  (yükseltmeden kalma) satırlar dürüstçe "1. tur" okunuyor.
- **Sync aynasındaki aynı hata düzeltildi:** `applyReminderSnooze` da yalnız "en
  yeni aktif satırı" erteliyordu → çevrimdışı erteleme iki alarmlı bir görevde
  ikinci alarmı canlı bırakıyordu (OPH-175'te REST'te düzelttiğim hatanın ikizi).
- **Erteleme artık GÖRÜNÜYOR:** görev satırında ve detayda `snooze` ikonu +
  **"Ertelendi — 22:52"**. `task.snoozedUntil` bugüne kadar hiçbir yüzeyde
  görünmüyordu; susturulmuş bir görev kurulu görünüyordu (A5'in yasakladığı yalan).
  Görev **açık** kalıyor.
- **Özel ertele** (BLUEPRINT §8.2'de yazılıydı, UI'da yoktu): ring ekranında
  "Saat seç…" → tarih+saat seçici → `snooze(until:)`; geçmiş bir an sessizce
  reddediliyor.
- **Test dersleri:** ring ekranı sonsuz nabız animasyonu taşıdığı için
  `pumpAndSettle` **asla** durmaz (DESIGN A1) — yeni testler açık `pump(süre)`
  ile sürülüyor; snackbar'ın 4 sn'lik kendi timer'ı teardown'da "pending timer"
  patlatıyor → sonda `pump(6s)`. Ayrıca ring ekranı testi artık `Scaffold`
  içinde pump ediliyor (üretimde de shell'in Scaffold'u mount'ta — snackbar
  onsuz gösterilemez).

**DoD met 2026-07-28:** app **441/441** + API **290 unit + 39 entegrasyon (gerçek
MySQL, migration uygulandı)** + analyze + lint + format + `check:i18n` + kontrast
FAILURES: 0; CHANGELOG; STATE.

### OPH-178 — Süresiz erteleme / "alarmı sustur" (round 9 #6.7) ✅ 2026-07-28

**Kullanıcının cümlesi:** _"kullanıcı isterse acil olarak ayarladığı taski tamamla
olarak işaretlemeden de tamamen susturabilmeli."_

- [x] **Migration:** `tasks.alarms_muted_at` TIMESTAMP NULL (null = alarmlar canlı).
      Sync FIELD (`alarmsMutedAt`, isoOrNull) + REST PATCH alanı (yeni endpoint YOK).
- [x] **Motor:** `alarmInstantsFor` susturulmuş görevde boş döner → `reconcileTaskReminder`
      aktif satırları `cancelled` yapar → **her cihazda zincir sync ile ölür**. Geri
      açmak reconcile'ın normal "wants reminder" yolundan satırı yeniden kurar; anı
      geçmişse app dürüstçe söyler ("saat geçti — yeni bir saat seç").
- [x] **Yüzeyler:** ring ekranında "Süresiz ertele" (birincil erteleme satırının
      yanında, DESIGN §11 A5), bildirim aksiyonu `mute` (iOS acil kategorisine 5.
      aksiyon — iOS yalnız ilk ~4'ünü gösterebilir, bu yüzden ring ekranı ve detay
      birincil yoldur), detayda "Alarmı sustur" switch'i, görev satırında
      `notifications_off` çipi + "Geri aç". **Görev açık kalır** — susturma tamamlama
      değildir (dürüstlük kuralı).
- [x] Testler: unit (susturulmuşta boş an listesi, geri açınca yeniden kurulum),
      entegrasyon (PATCH → satır cancelled), app (ring ekranından sustur → alarm
      feed'den çıkıyor, çip görünüyor, görev hâlâ açık).

**Uygulamada ortaya çıkanlar (2026-07-28):**

- **Motor tarafı gerçekten hazırdı:** `alarmInstantsFor` OPH-175'te ileriye dönük
  yazıldığı için kolon gelince sunucuda **tek satır** değişmedi — susturma
  anında iki alarm satırı da `cancelled` oluyor ve her cihaza sync ile gidiyor.
  Uygulamada aynı kontrol `taskAlarmInstants`'a düştü; **sentetik alarm sorgusu
  da** `alarmsMutedAt.isNull()` filtresi aldı (yoksa satır iptal olsa bile
  görevden sentetik alarm doğardı).
- **Yeni endpoint yok:** `alarmsMutedAt` sıradan bir task alanı (REST PATCH +
  sync FIELD + serializer). Böylece çevrimdışı susturma da bedelsiz çalışıyor:
  outbox yaması normal task update'i.
- **Dört yüzey:** ring ekranında **"Süresiz ertele"** (snackbar "Alarm
  susturuldu"), **bildirim aksiyonu `mute`** (iOS acil kategorisinin sonunda —
  iOS ilk birkaç aksiyonu gösterir, bu en ağırı; Android'de de var), detayda
  switch (alt metin ne demek olduğunu söylüyor), **görev satırında
  `notifications_off` çipi + "Alarmı geri aç"**.
- **Geri açmak dürüst:** `unmuteTaskAlarms` an geçmişse "O saat geçti — göreve
  yeni bir saat ver" diyor, sessizce hiç çalmayacak bir alarmı geri kurmuyor.
- **Görev AÇIK kalıyor** (A5): testler bunu ayrıca doğruluyor — `status == 'open'`,
  `completedAt == null`, tarihler yerinde. Susturmak tamamlamak değildir.

**DoD met 2026-07-28:** app **446/446** + API **292 unit + 39 entegrasyon (gerçek
MySQL, migration uygulandı)** + analyze + lint + format + `check:i18n` + kontrast
FAILURES: 0; CHANGELOG; STATE.

### OPH-179 — Hatırlatıcı profili: kaç tane, kaç dakikada bir (round 9 #7) — "Hatırlatıcı Sistemi Ayarları" ✅ 2026-07-28

- [x] **Saf model** `apps/app/lib/src/notifications/reminder_profile.dart`:
      `ReminderProfile(slots: [0,2,5,10,30], repeatAfterSnooze: true)`;
      `parseReminderProfile(String)` / `encode`. **Kurallar (doğrulama tablosu):**
      artan sıra, tekilleştirme, **ardışık slotlar arası ≥ 1 dk** (kullanıcının koyduğu
      çakışma kuralı — "30 sn sonra" isteği bu kurala takılır ve UI bunu söyler),
      ilk slot ≥ 0, **en çok 20 slot**, bozuk değer → fabrika profili.
- [x] **Planner profili PARAMETRE olarak alır** (saf kalır): `kUrgentChainOffsets`
      sabiti kalkar, `planNotifications(..., profile:)`. Cihaz-yerel tercih
      `alliswell_reminder_profile`; scheduler profil değişince yeniden planlar
      (privacy toggle'ın bugünkü kalıbı).
- [x] **64 slot gerçeği ekranda:** iOS bekleyen 64 bildirimi aşınca sessizce atar
      (bugünkü pencere 40). Editörde canlı hesap: "Bu profille aynı anda ~N alarm tam
      kapsanır" + 10 slotun üstünde uyarı. Sessiz kırpma yasak (NOTIFICATIONS §5).
- [x] **Ayarlar → "Hatırlatıcı Sistemi Ayarları"** yeni ekran
      (`features/settings/reminder_settings_screen.dart`, DESIGN §18): hazır profiller
      (**Sakin** 1 slot / **Standart** 5 / **Israrcı** 10), adım listesi (her adım
      dakika stepper'ı + sil, "araya adım ekle"), **canlı zaman çizelgesi önizlemesi**
      ("22:42 → 22:44 → 22:47 …" kullanıcının tarih biçimiyle), satır içi doğrulama
      mesajları, fabrika ayarına dön.
- [x] **Sürükle-bırak kararı (bilinçli sapma, gerekçeli):** sıralı bir sayı zincirinde
      "3. adımı 1. sıraya taşı" anlamsızdır — sistem hemen yeniden sıralar, jest boşa
      gider (NN/g: sonucu geri alınacak jesti sunma). Bu yüzden zincir **adım adım
      stepper** editörüdür; sürükle-bırak **anlamlı olduğu yerde** verilir: kullanıcının
      alarm ekranında gördüğü **erteleme preset'lerinin sırası** (`ReorderableListView`).
- [x] Testler: doğrulama tablosu (sıra/1 dk/kap/bozuk), planner profili uyguluyor,
      editör adım ekle-sil-değiştir + preset yeniden sıralama, kapasite uyarısı.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **`kUrgentChainOffsets` sabiti SİLİNDİ.** Zincir artık
  `planNotifications(..., profile:)` parametresi; varsayılan
  `ReminderProfile.factory` (eski `[0,2,5,10,30]`), yani yükseltmede hiçbir
  kullanıcının alarmı değişmiyor. Saklama JSON (`{"slots":[...],
  "repeatAfterSnooze":bool}`), bozuk/eksik/gelecek-sürüm değeri **fabrikaya**
  düşüyor ve **asla boş zincir** üretilmiyor (sıfır kez çalan alarm alarm değil).
- **`repeatAfterSnooze`** eklendi (spec'te yoktu, editörde bariz bir soru olarak
  çıktı): kapalıyken ertelenen alarm geri döndüğünde **bir kez** çalıyor. Planner
  bunu `status == 'snoozed'` ile birleştiriyor.
- **Presetler:** Sakin [0] · Standart [0,2,5,10,30] · **Israrcı
  [0,1,2,3,5,8,12,17,25,40]** (10 uyarı — 20 slot sınırının yarısı, kapasite
  uyarısının altında kalıyor). El yapımı zincir "Senin" segmenti olarak **gerçek
  bir durum**, boş bir seçim değil.
- **1 dk kuralı düzenlerken uygulanıyor, kaydederken değil:** stepper'ın alt/üst
  sınırı komşu adımlardan geliyor (`minSlotAfter`), yani kullanıcı kuralı ihlal
  edemiyor — `normalizeSlots` yalnız depodan gelen çöp için emniyet ağı.
- **64 slot ekranda:** "Bu zincirle aynı anda yaklaşık N alarm tam kapsanır"
  (`40 ~/ slot`) + **10 uyarının üstünde** dürüst uyarı bandı. Sessiz kırpma yok.
- **Sürükle-bırak (N4) sadece erteleme düğmelerinde:** sıralı sayı zinciri
  kendini yeniden sıralayacağı için orada jest anlamsız olurdu. Erteleme sırası
  `alliswell_snooze_presets` olarak saklanıyor ve **ring ekranı bu sırayı
  uyguluyor** (dört preset de görünüyor artık — "yarın sabah" dahil).
- **Test dersleri:** `ReorderableListView`'in varsayılan tutamakları mobil
  hedefte **gecikmeli** sürükleme kullanıyor → test uzun basıp taşımak zorunda
  (düz `drag` hiçbir şey yapmıyor); ring ekranı artık daha uzun olduğu için
  susturma düğmesi testinde `ensureVisible` gerekiyor; `onReorder` deprecate
  olmuş → `onReorderItem` (indeksi kendisi düzeltiyor).

**DoD met 2026-07-28:** app **466/466** (+20 yeni test) + API 292 (dokunulmadı) +
analyze temiz + `check:i18n` + kontrast FAILURES: 0; CHANGELOG; STATE.

### OPH-180 — Uygulama içi alarm sesi: `AlarmFeedback`'in ses yatağı (round 9 #6, #8) ✅ 2026-07-28

- [x] **Yeni bağımlılık kategorisi** (AGENTS sert kural 6 → [ADR-0015](adr/0015-alarm-delivery-and-reminder-profiles.md)):
      ses çalar (`just_audio` + `audio_session`, alternatif `audioplayers`; seçim
      ADR'de gerekçelenir). Gereksinimler: döngü, iOS `AVAudioSession` kategorisi
      **`.playback`** (uygulama ÖNDEyken sessiz anahtarını meşru şekilde aşar — bu,
      NOTIFICATIONS §2b'nin reddettiği *arka plan* audio hilesi DEĞİLDİR), Android
      `USAGE_ALARM` attributes, masaüstü + web desteği.
- [x] **Mevcut seam'in içine:** `AudioAlarmFeedback implements AlarmFeedback`
      (ses + haptik), testler `SilentAlarmFeedback`'te kalır (bekleyen timer/kanal
      yok). Seçilen alarm sesini çalar (OPH-181), her aksiyonda ve dispose'ta susar.
      **Masaüstü/web'in tek alarm yüzeyi budur** (NOTIFICATIONS §3).
- [x] **Web dürüstlüğü:** tarayıcı autoplay politikası kullanıcı jesti olmadan sesi
      engelleyebilir → engellenirse görsel + (varsa) titreşimle devam et ve ring
      ekranında "sesi başlat" düğmesi göster.
- [x] Testler: fake çalar start/stop çağrılarını doğruluyor; ring ekranı testleri
      hâlâ sessiz ve timer sızdırmıyor.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Paket seçimi: `audioplayers`** (ADR-0015 §7 buna göre güncellendi).
  `just_audio` + `audio_session` aynı iki düğme için iki paket, Windows/Linux
  için de üçüncü bir topluluk backend'i isteyecekti; `audioplayers` tek paketle
  hepsini veriyor **ve** ihtiyacım olan iki platform düğmesini açıyor: iOS
  `AVAudioSession` kategorisi **`.playback`** (uygulama ÖNDEyken sessiz
  anahtarına rağmen duyulur) + Android **`USAGE_ALARM`** (alarm akışı, alarm
  sesi seviyesi).
- **Ses yatağı artık bir Flutter varlığı:** `assets/audio/aw_alarm.m4a` (Android
  raw dosyasının kopyası — 28 sn, aac). OS hatları kendi platform kaynaklarını
  kullanmaya devam ediyor; bu varlık **masaüstü ve web'in tek alarm sesi**.
- **Seam korundu:** `AudioAlarmFeedback implements AlarmFeedback` (ses + haptik),
  `HapticAlarmFeedback` sessiz platformlar için duruyor, testler
  `SilentAlarmFeedback`'te. `syncTestOverrides`'a **`alarmFeedback` parametresi**
  eklendi (aynı provider'ı iki kez override etmek Riverpod'da hata — dosyanın
  mevcut `filePicker`/`uploadTransport` kalıbıyla aynı çözüm).
- **Dürüst düşüş seam'e girdi:** `AlarmFeedback.soundBlocked` (`ValueListenable<bool>`)
  → ring ekranı **"Sesi başlat"** düğmesini gösteriyor. Tarayıcı autoplay'i
  engellediğinde çalan gibi görünen sessiz bir alarm — bu bölümün yasakladığı tek
  sonuç — olmuyor; haptik devam ediyor ve elle başlatma çalışıyor (test var).
- **Arka plan audio hilesi hâlâ reddedildi** (NOTIFICATIONS §2b): ses yalnız
  ring ekranı ÖNDEyken çalıyor.

**DoD met 2026-07-28:** app **472/472** (+6 test) + analyze temiz + `check:i18n` +
kontrast FAILURES: 0; ADR-0015 §7 + DESIGN §11 A3 + NOTIFICATIONS §3 güncellendi;
CHANGELOG; STATE. _Cihazda gerçek ses (sessiz anahtarı açıkken duyulması) cihaz
turuna kaldı — `flutter test` audio plugin'i çalıştırmaz._

### OPH-181 — Zil sesi kütüphanesi + özel ses yükleme (round 9 #7 sesler) ✅ 2026-07-28

- [x] **Paketli sesler:** `aw_alarm` (28 sn, var) + 2 kısa hatırlatıcı tonu (yeni
      varlıklar: iOS `.caf` ≤30 sn + Android `res/raw` + Dart asset — üç yüzey aynı
      dosyayı duyar).
- [x] **Özel yükleme mevcut boru hattını kullanır** (Epic 14/15): `targetType:'workspace'`
      + ayrılmış **"Zil sesleri"** klasörü; seçim cihaz-yerel
      (`alliswell_alarm_sound` / `alliswell_reminder_sound` = `bundled:aw_alarm` |
      `file:<fileId>`) — dosya kütüphanesi çalışma alanı geneli olduğu için diğer
      cihazlar aynı sesi seçebilir, sunucu tarafında yeni ayar deposu gerekmez.
- [x] **Cihaza kurulum (kritik ayrıntı):** iOS `UNNotificationSound(named:)` sesi
      **önce app container'ın `Library/Sounds` klasöründe**, sonra bundle'da arar →
      presigned GET ile indir, `Library/Sounds/<hash>.caf` olarak yaz, adıyla referans
      ver. Android'de kanallar **değiştirilemez** → ses başına kanal
      (`urgent_alarms_v3_<hash>`), eski/kullanılmayan kanalları sil (sınırlı sayıda tut).
- [x] **iOS ses çözümleme bekçisi (OPH-176'dan taşındı):** `UNNotificationSound`
      adı çözülemezse iOS **sessizce varsayılan ding'e** düşer — özel ses boru
      hattı burada kurulduğu için probe da buraya ait. Native tarafta dosyanın
      (bundle → container `Library/Sounds`) varlığını doğrula, çözülemiyorsa
      **alarm günlüğüne `degraded` yaz** + Ayarlar'ın alarm durum satırında söyle
      ("özel ses bulunamadı — varsayılan sesle çalacak"). Sessiz düşüş yasak.
      _(176'da yazılmadı: yeni bir native kanal `flutter analyze`/`test` ile
      doğrulanamaz, AlarmKit dersi.)_
- [x] **Format dürüstlüğü:** OS bildirim sesi ≤30 sn ve aiff/wav/caf (Linear PCM,
      IMA4, µLaw, aLaw) olmak zorunda; **mp3/m4a iOS bildiriminde çalışmaz.** Yükleme
      ekranı bunu yükleme anında söyler ve alternatif sunar ("yalnız uygulama içi alarm
      sesi olarak kullan") — sessizce başarısız olmak yasak. Sunucu tarafı dönüştürme
      (ffmpeg) **bilinçli olarak park edildi** (v2 kuyruğu).
- [x] **AlarmKit aynı dosyayı kullanır:** `AlertConfiguration.AlertSound.named(...)`
      bundle/`Library/Sounds` kurallarına tabi → OPH-182'de aynı kurulu dosya beslenir;
      erken iOS 26 sürümlerinde container seslerinin çalmadığı raporları var → cihaz
      turunda doğrula, çalışmazsa paketli yatağa düş.
- [x] Ayarlar → Hatırlatıcı Sistemi Ayarları içinde "Alarm sesi" / "Hatırlatıcı sesi"
      satırları + **önizleme** (OPH-180'in çaları) + "Ses yükle".
- [x] Testler: format/süre doğrulama tablosu, seçim kalıcılığı, gateway doğru ses adını
      geçiyor, bayat kanal temizliği (fake üzerinde), desteklenmeyen format mesajı.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Paketli tonlar üretildi** (`aw_chime` 1.6 sn, `aw_ping` 0.9 sn — Python'la
  sinüs + zarf, `afconvert` ile ima4 `.caf` + aac `.m4a`). Üç yüzey üç dosya
  istiyor: **in-app** için Flutter asset (`assets/audio/*.m4a`), **Android
  kanalı** için `res/raw` (kanal yalnız raw kaynağa veya content:// URI'ye
  bakabilir), **iOS** için `.caf`.
- **pbxproj'a DOKUNULMADI (önemli bulgu):** `UNNotificationSound` adı önce app
  container'ın `Library/Sounds` klasöründe arıyor → yeni sesler **çalışma anında
  oraya kuruluyor** (`sound_store.dart`, `LocalKv`'nin io/web seam kalıbı).
  Yani Xcode'a girmeden hem paketli ton eklenebiliyor hem kullanıcının yüklediği
  ses kullanılabiliyor. `aw_alarm.caf` round 6'da pbxproj'a girdiği için bundle'dan
  geliyor.
- **Ses adı artık plan içeriğinin parçası:** `PlannedNotification.soundName` id
  seed'ine giriyor → sesi değiştirmek **yeniden planlıyor** (aksi hâlde değişiklik
  yalnız sonraki alarmda görünürdü). Android kanalı da ses başına
  (`urgent_alarms_v2_<ses>`) çünkü **kanallar değişmez**.
- **Bekçi (OPH-176'dan taşınan) burada gerçekleşti:** özel ses seçildiğinde
  indirilip kuruluyor; alarm planlanırken `installed()` ile **gerçekten var mı**
  diye bakılıyor. Yoksa `degraded` günlüğe yazılıyor ve OS sesine düşülüyor —
  iOS'un sessiz "varsayılan ding" ikamesi artık kayda geçiyor.
- **Bilinçli platform sınırı (Android):** kanal sesi `res/raw` veya `content://`
  ister; app-private bir dosya sistem UI'ı tarafından okunamaz ve onu açmak
  **FileProvider** (native yapılandırma) demek. Bu yüzden Android'de **yüklenen
  ses uygulama içi alarmda** çalıyor, bildirim paketli sesle devam ediyor —
  picker'da ve ADR'de yazılı, sessizce yutulmuyor. FileProvider yolu park kuyruğuna.
- **Format dürüstlüğü yükleme anında:** `soundUsability(ad)` → `.caf/.wav/.aiff`
  her yerde, **mp3/m4a yalnız uygulama içi** (iOS bildirimi çalamaz). Hem yükleme
  hem seçim anında söyleniyor + picker'ın altında kural metni.
- **Zil sesleri sıradan dosyalar:** ayrılmış **"Zil sesleri"** klasörüne workspace
  yüklemesi olarak gidiyorlar → Dosyalar'da görünür, senkronlanır, silinebilir;
  gizli bir depo yok. Seçim cihaz-yerel (`alliswell_alarm_sound` /
  `alliswell_reminder_sound`), bozuk değer **OS sesine** düşer (sessizliğe değil).
- **Flutter API dersi:** `RadioListTile.groupValue/onChanged` deprecate olmuş →
  liste `RadioGroup<String>` ile sarıldı, seçim tek yerde yorumlanıyor.

**DoD met 2026-07-28:** app **485/485** (+13 test) + analyze temiz + `check:i18n` +
kontrast FAILURES: 0; ADR-0015 §6 + NOTIFICATIONS §2c güncellendi; CHANGELOG;
STATE. _Gerçek cihazda "yüklenen ses bildirimde çaldı mı" doğrulaması OPH-182
cihaz turunda (iOS 26 pass'iyle aynı oturum)._

### OPH-182 — iOS 26 AlarmKit'i GERÇEKTEN devreye al (round 9 #8'in çözümü) — cihaz

**Bu task, "ekran kapalıyken/sessizde ses gelsin" isteğinin tek meşru cevabıdır ve
iPhone'un kendi alarm arayüzünü (tam ekran, ertele/durdur) bize verir.**

- [x] `AlarmKitBridge.swift`'i **Runner hedefine ekle** + `AppDelegate`'te kur
      ([ALARMKIT_SETUP.md](../apps/app/ios/Runner/ALARMKIT_SETUP.md)). Wiring
      **betiğe alındı** (`ios/scripts/wire_alarmkit.rb`, idempotent) — proje yeniden
      üretilirse Xcode'suz geri bağlanır.
- [x] **Round 9 araştırmasının yeni bulgusu — Live Activity zorunluluğu:**
      `AWAlarmLiveActivity` (widget extension'da `ActivityConfiguration(for:
      AlarmAttributes<AWAlarmMetadata>.self)`) + her iki Info.plist'te
      `NSSupportsLiveActivities`. `AWAlarmMetadata` **iki hedefte de** derleniyor
      (`ios/Shared/AWAlarmShared.swift`). **Kaynak ağacından değil, ÜRÜNDEN
      doğrulandı:** app dylib'i ve `.appex` `AlarmKit.framework`'e weak link veriyor,
      ikisinde de `Metadata.appintents` var.
- [x] **Yerelleştirme + ses + ertele:** buton metinleri artık **Dart'ta** üretiliyor
      (`planAlarmKitAlarms` → `stopLabel`/`snoozeLabel`), `sound:` OPH-181'in kurulu
      dosyasını alıyor (ses adı id tohumunda → ses değişince yeniden planlanıyor),
      erteleme **kullanıcının sıralamasındaki ilk preset**. **Bilinçli sapma:**
      `secondaryButtonBehavior` `.countdown` DEĞİL **`.custom`** — planner zaten
      ertelenen hatırlatıcıyı yeniden kuruyor, `.countdown` tek ertelemeyi İKİ alarma
      çevirirdi ve OS'un sahiplendiği erteleme görev satırına ve diğer cihazlara hiç
      ulaşmazdı (ADR-0015 karar 9, NOTIFICATIONS §2b.1).
- [x] **SDK gerçeği** (ilk derlemede çıktı, hepsi tasarımı değiştirdi): `AlarmAttributes`
      /`AlarmConfiguration` **generic**; `Alarm`'da **`attributes` YOK** → id↔UUID gidiş
      dönüşü tek kurtarma yolu; `State`'te **`.stopped` YOK** → düğmeler
      **`LiveActivityIntent`** ile geliyor; `alarms` throwing property (async değil);
      `@available(obsoleted:)` ile overload Swift'te derlenmiyor.
- [x] **Uygulama kapalıyken de çalışan düğmeler:** intent'ler App Group kuyruğuna
      yazıyor (`AWAlarmActionQueue`, 32 satır tavan), Dart handler'ı kurulur kurulmaz
      ve her öne gelişte `drainPendingActions` ile boşaltıyor — kanala doğrudan
      itmek, tam da en çok önemsenen onayı (soğuk uygulamada 03:00'te çalan alarm)
      düşürürdü.
- [x] **Pencere + limit:** lane en yakın **8** alarmla sınırlı (`kMaxAlarmKitAlarms`);
      sığmayan **bildirim zincirini koruyor** (bu yüzden planner'a bayrak değil
      **kapsanan reminder id KÜMESİ** gidiyor — bayrak olsa limit üstü acil alarm iki
      lane'in arasına düşerdi) ve hem taşma hem `limit_reached` reddi alarm günlüğüne
      yazılıyor; **reddedilen alarm `degraded`, asla `scheduled` değil.**
- [ ] **Cihaz DoD matrisi (iOS 26 gerçek cihaz):** sessiz anahtarı AÇIK + Uyku Odak
      AÇIK + ekran KİLİTLİ → alarm tam ekran çalıyor; Onayla senkronize oluyor (bir kez
      de **uygulama kapalıyken**); Ertele yeniden çalıyor; iOS < 26'da bildirim
      zincirine düşüş sağlam; günlük lane'i doğru yazıyor. Adımlar:
      [ALARMKIT_SETUP.md](../apps/app/ios/Runner/ALARMKIT_SETUP.md) "Device DoD".
      Sonuç STATE'e işlenir.

**Kodsal DoD met 2026-07-28:** app **493/493** (+8 test) + `analyze` temiz +
`check:i18n` + kontrast FAILURES: 0; `flutter build ios` **iOS 26.2 SDK'sına karşı
GEÇTİ** ve AlarmKit bağlantısı ürün ikililerinden doğrulandı. NOTIFICATIONS §2b.1
(yeni) + §2d, ADR-0015 karar 9, ALARMKIT_SETUP.md yeniden yazıldı (hand-off →
kayıt + cihaz DoD'si). Yan kazanç: `Podfile.lock` OPH-180'in `audioplayers`
bağımlılığını nihayet aldı — iOS'ta pod install hiç koşmamıştı. **Kalan: yalnız
cihaz matrisi** (yukarıdaki tek kutu) — kod tarafında yapılacak iş yok.

### OPH-183 — Apple Watch: bedava olan ne, companion gerekli mi (round 9 #6 son paragraf)

- [ ] **Bedavayı doğrula (varsayma):** iPhone bildirimleri telefon kilitliyken eşleşmiş
      saate **aynalanır** (watchOS hedefi gerekmez); ses/haptik per-app kullanıcı
      kontrolünde (Watch → Sesler ve Dokunuşlar; watchOS 26 ortama göre otomatik ses
      seviyesi; **"Belirgin" haptik** bazı uyarıları ekstra dokunuşla önceden bildirir).
      AlarmKit alarmlarının saatte de göründüğü Apple'ın kendi çerçevesinde belirtiliyor
      → gerçek saatle doğrula.
- [x] **Karar ve gerekçesini yaz:** watchOS companion hedefi yalnız (a) özel long-look
      bildirim arayüzü, (b) `WKInterfaceDevice.play(.notification)` haptikleri,
      (c) complication için gerekir — kendi imza + review yüzeyi gelir. **Karar:
      companion AÇILMIYOR**; NOTIFICATIONS §2d'de karar kuralı yazılı (önce aynalamayı
      ve AlarmKit'i gerçek saatte ölç, yetersizse ayrı epic). Ölçüm cihaz turunda.
- [x] **Hedef gelmese bile teslim edilecek:** NOTIFICATIONS §2d güncellendi +
      Hatırlatıcı Sistemi Ayarları'nda Apple Watch yardım satırı
      (`reminderSettings.watchTitle/watchSub`, en+tr) — aynalama bedava, ses/haptik
      Watch → Sesler ve Dokunuşlar'da.

**Epic 16 DoD:** her task kendi test + `check:i18n` + kontrast (FAILURES: 0) + `analyze`
yeşiliyle kapanır; epic sonunda app + API tam süit, `check:no-ts`, CHANGELOG + STATE +
README/ROADMAP dokunuşları (yenileme, tarih biçimi, hatırlatıcı sistemi), **OPH-182/183
cihaz matrisi STATE'e işlenmiş** → **v0.5.0**. 175/177/178 migration içerir → append-only
kural + `down` zorunlu; 180 yeni bağımlılık kategorisi → ADR-0015 kabul edilmiş olmalı.

---

## Epic 17 — Feedback round 10: silme, tamamlananlar, widget, geçişler (Phase 11, v0.6.0)

_(Doğdu 2026-07-28 — Mahir'in 10 maddelik listesi + istediği **kapsamlı UX taraması**.
v0.5.0 canlıya alındıktan sonraki ilk "günlük kullanım" turu. Bağlayıcı metinler:
[DESIGN](DESIGN.md) §19–§22 (yeni) + §4/§8/§17/§18 revizyonları,
[WIDGETS](WIDGETS.md) §3.1/§4, BLUEPRINT §4.2/§4.3/§12.2/§12.4/§12.8/§12.14/§14 Phase 11,
**yeni [ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md)**.
Sıra bağlayıcı: **184→186 liste UX çekirdeği** → **191→194 tekil düzeltmeler** →
**187→189 widget hattı** → **195 tarama**. 188 cihaz ister; kalan her şey cihazsız.)_

> **Turun tek cümlesi:** bu round'da bulunan hataların çoğu "yazılmamış kod" değil,
> **yazılmış ama yüzeye çıkarılmamış** yetenek. Silme motoru (store + outbox + API +
> kaskad) tamamen hazırdı ve hiçbir görev satırında düğmesi yoktu; `parentTaskId`,
> `sortOrder`, `colorRgb` aynı durumda. OPH-195 bunun sistematik taramasıdır.

**Round 10'un kök nedenleri — kodda doğrulandı (2026-07-28):**

| # | Şikâyet | Kodda kanıt |
| - | ------- | ----------- |
| 1 | Task silme yok | `TaskStore.delete` [task_store.dart:429](../apps/app/lib/src/features/tasks/data/task_store.dart#L429) + `DELETE /tasks/:id` [tasks.js:752](../apps/api/src/routes/tasks.js#L752) (alt ağaç + ek kaskadı) **hazır**; tek çağıran [task_list_screen.dart:150](../apps/app/lib/src/features/tasks/ui/task_list_screen.dart#L150) — yani **yalnız Fikirler satırında**. Task detayının app bar'ında silme **yok** ([task_detail_screen.dart:117](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L117) sadece tamamla/geri aç). `grep -r Dismissible apps/app/lib` → **0 sonuç**: uygulamada hiçbir yerde kaydırarak silme yok |
| 1b | "Başka ne unutulmuş?" | **Not silme** yalnız editörde ([note_editor_screen.dart:253](../apps/app/lib/src/features/notes/ui/note_editor_screen.dart#L253)) — liste menüsünde yalnız arşivle ([notes_screen.dart:203](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L203)). **Proje silme** yalnız detayda ([project_detail_screen.dart:115](../apps/app/lib/src/features/projects/ui/project_detail_screen.dart#L115)) — liste menüsünde düzenle+arşivle ([projects_screen.dart:188](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L188)) |
| 2 | Tamamlanan görev kayboluyor | `watchOpen` = `status.isIn(kPlanningStatuses)` [task_store.dart:28](../apps/app/lib/src/features/tasks/data/task_store.dart#L28); `kPlanningStatuses` terminal statüleri dışlar [:14](../apps/app/lib/src/features/tasks/data/task_store.dart#L14) → satır **aynı karede** listeden düşüyor. `TaskTile`'ın tamamlanmış görünümü (üstü çizili + gri) [task_tile.dart:110](../apps/app/lib/src/features/tasks/ui/task_tile.dart#L110) bu yüzden Home'da **hiç görünmüyor** — yalnız Pano'nun completed sütununda. Tamamlamanın geri alması da yok (`SnackBarAction` yalnız Pano'da) |
| 3 | Tamamlananları bir yerden görme yok | Ayarlar'da böyle bir satır yok; `completedAt` drift'te saklı ([database.dart:89](../apps/app/lib/src/sync/db/database.dart#L89)) ve pull hiçbir statüyü filtrelemiyor → **veri zaten replikada**, ekran yok |
| 4A | Widget'ta gün/ay yazısı kayık | iOS `HStack(alignment: .firstTextBaseline)` — 34 pt gün sayısının **taban çizgisi** 14 pt hafta gününün taban çizgisine hizalanıyor, ay satırı altta sarkıyor ([AllisWellWidget.swift:123](../apps/app/ios/AllisWellWidget/AllisWellWidget.swift#L123)). Android aynı başlığı `gravity="center_vertical"` ile **ortalıyor** ([tasks_widget.xml:18](../apps/app/android/app/src/main/res/layout/tasks_widget.xml#L18)) → iki platform zaten birbirinden farklı çiziyor (W1 ihlali) |
| 4B | Günün açık görev sayısı yok | Başlığın sağı `Spacer()` ([AllisWellWidget.swift:131](../apps/app/ios/AllisWellWidget/AllisWellWidget.swift#L131)); snapshot'ta **toplam sayı alanı yok** — yalnız kova başına `count` var ([widget_snapshot.dart:113](../apps/app/lib/src/features/widgets/widget_snapshot.dart#L113)) |
| 4C | Widget'tan tamamlanamıyor | iOS satırındaki daire `Image(systemName:)` — statik, `Button(intent:)` değil ([AllisWellWidget.swift:140](../apps/app/ios/AllisWellWidget/AllisWellWidget.swift#L140)). Android satırı `TextView` "○"/"●" ([TasksWidgetService.kt:52](../apps/app/android/app/src/main/kotlin/com/alliswell/alliswell/TasksWidgetService.kt#L52)) ve `Row` **görev id'sini hiç taşımıyor** [:18](../apps/app/android/app/src/main/kotlin/com/alliswell/alliswell/TasksWidgetService.kt#L18). Zaten açık: **OPH-132** + OPH-133'ün son iki kutusu |
| 4D | "No route for alliswell://open/" | Uygulama `alliswell://` şemasını **hiç kaydetmiyor**: `Info.plist`'te `CFBundleURLTypes` **yok**, `AndroidManifest.xml`'de deep-link `intent-filter` **yok**; ham URL go_router'ın konum eşleyicisine düşüyor. Hata sayfasındaki "Home" go_router'ın **varsayılan** hata ekranından geliyor (`errorBuilder` tanımlı değil) ve `/`'a gidiyor — **`/` diye bir rota yok**, bölümler `/home`, `/inbox`, … ([router.dart:63](../apps/app/lib/src/router.dart#L63), [sections.dart:16](../apps/app/lib/src/sections.dart#L16)) → ikinci hata |
| 5 | Alarm önizlemesinde durdurma çalışmıyor | Üç ayrı kusur, hepsi [sound_picker_sheet.dart:65-80](../apps/app/lib/src/features/settings/sound_picker_sheet.dart#L65): (a) çalar **metodun içinde** yaratılıyor, state'te tutulmuyor → başka kimse durduramaz; (b) `onPressed: _previewing != null ? null : …` [:224](../apps/app/lib/src/features/settings/sound_picker_sheet.dart#L224) — ikon "stop"a dönüyor ama **düğme devre dışı**, basmak hiçbir şey yapmıyor ve **diğer sesler de kilitleniyor**; (c) `dispose()` **yok** → sheet kapansa bile `Future.delayed` süresi dolana kadar ses çalmaya devam ediyor. Ayrıca **yüklenen seslerin önizlemesi hiç yok** [:250](../apps/app/lib/src/features/settings/sound_picker_sheet.dart#L250) — DESIGN §18 N6 "sesi DUYARAK seçersin" der |
| 6 | Düzenlerken saat seçimi gelmiyor | Detaydaki `_DateRow.onTap` yalnız `showDatePicker` çağırıyor, sonra **varsayılan görev saatini uyguluyor** ([task_detail_screen.dart:493-511](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L493)) → 14:30'luk bir görevin gününü değiştirmek saati **sessizce 23:59 yapıyor**. Oluşturma sheet'i ise date+time soruyor ([task_create_sheet.dart:120-152](../apps/app/lib/src/features/tasks/ui/task_create_sheet.dart#L120)). Detaydaki **üç satır da** (bitiş, planlanan, hatırlatma) aynı hatalı yolu kullanıyor |
| 7 | "Planlanan tarih" nedir? | `_DateRow(key: 'scheduled-row')` yalnız detayda var ([task_detail_screen.dart:345](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L345)); BLUEPRINT §12.4'ün alan listesinde **hiç yok**. Ama alan ölü değil: `desiredEventForTask` takvim bloğunu **önce `scheduled_start_at`'ten** türetiyor ([mirror.js:21](../apps/api/src/lib/mirror.js#L21)) ve kullanıcı Google'da etkinliği sürüklediğinde inbound **`due_at`'i değil `scheduled_*`'ı yazıyor** ([inbound.js:15](../apps/api/src/lib/inbound.js#L15)) → satırı düz silmek, kullanıcının göremediği bir alanın takvim etkinliğini kilitlemesi demek |
| 8 | Proje düzenlemede "durum" | `if (_isEdit)` dropdown'ı ([project_edit_sheet.dart:176](../apps/app/lib/src/features/projects/ui/project_edit_sheet.dart#L176)) — **yalnız düzenlemede var, eklemede yok**. Üstelik `Text(status)` ile **ham İngilizce enum** basıyor (`active`/`paused`/`completed`), aynı sızıntı iki yerde daha: [project_detail_screen.dart:197](../apps/app/lib/src/features/projects/ui/project_detail_screen.dart#L197), [projects_screen.dart:161](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L161). Arşivleme zaten ayrı bir akış (OPH-110) |
| 10 | Geçişte önceki ekranın hayaleti | **`scaffoldBackgroundColor: tokens.veil`** ([theme.dart:147](../apps/app/lib/src/theme/theme.dart#L147)) ve veil **yarı saydam**: açık `0x94F5F9FF` = **%58**, koyu `0x7A0A102A` = **%48** ([tokens.dart:153](../apps/app/lib/src/theme/tokens.dart#L153)). `AuroraBackground` ise **Navigator'ın ALTINDA**, `MaterialApp.builder`'da tek sefer boyanıyor ([app.dart:47](../apps/app/lib/src/app.dart#L47)) → push/pop sırasında iki rota da ağaçtayken **gelen ekranın saydam zemininden giden ekran görünüyor**; geçiş bitip eski rota ağaçtan silinince hayalet kayboluyor. Tam olarak tarif edilen davranış. Ayrıca `pageTransitionsTheme` tanımlı değil → platform varsayılanları (Android Zoom, iOS Cupertino kaydırma) |

> **Sürüm kararı:** 184–186 + 190–194 tek başına kullanıcıya hemen değer verir ve
> tamamen cihazsızdır (**v0.5.1 ara sürümü olabilir**); 187–189 widget hattını
> bütünler; 188 gerçek cihaz ister. Epic tamamlanınca **v0.6.0**.

### OPH-184 — Silme her yerde: kaydırarak sil + detayda sil (round 10 #1) ✅ 2026-07-28

- [x] **Karar + ADR (ilk iş):** "yarım açılır, sonra Sil'e basılır" Apple deyimini
      Flutter'da veren yol seçilir. `Dismissible` **bunu vermez** (tek jestte siler);
      seçenekler (a) `flutter_slidable` paketi, (b) elle `Stack` + sürükleme fiziği.
      **Öneri: (a)** — geri açılma fiziği, RTL, klavye/erişilebilirlik ve fling eşiği
      elle yazılınca sessizce yanlış olur ve bu ilkel **uygulamanın bütün yıkıcı
      eylemlerini** taşıyacak. Yeni bağımlılık ⇒ AGENTS sert kural 6 ⇒ **ADR-0017**
      (paket seçilirse). Görsel taraf tamamen bizim: eylem paneli `AwTokens` ile
      giydirilir, cam kuralları (G1) geçerli.
- [x] **Tek paylaşılan sarmalayıcı** `apps/app/lib/src/widgets/swipe_actions.dart` →
      `AwSwipeToDelete({required Widget child, required Future<void> Function() onDelete,
      String? confirmTitle, String? confirmBody, Key? actionKey})`: sağdan sola kaydırma
      **yarı açılır** ve `error` renkli "Sil" düğmesini gösterir; düğmeye basmak siler.
      Tap hedefi ≥ 44 px (DESIGN §5), `Semantics(button: true)` + `onLongPress` yedeği
      (jest yapamayan kullanıcı için — erişilebilirlik yolu **zorunlu**, K3 dersi).
- [x] **Geri alma modeli (bilinçli tasarım):** yıkıcı ama kaskadsız silmelerde
      (**görev, not**) dialog YOK → satır anında gizlenir + **"Geri al" snackbar'ı**;
      gerçek `store.delete()` snackbar kapanınca (≈5 sn) veya ekrandan çıkılınca
      **ertelenmiş commit** olarak koşar. Uygulama arada öldürülürse silme HİÇ olmaz —
      güvenli yön budur. Kaskadlı/kalıcı olanlar (**proje, klasör, etiket**) mevcut
      onay dialog'unu korur (kaskad sorusu atlanamaz).
- [x] **Kaydırarak silmenin ineceği yüzeyler:** `TaskTile` (Home Liste, proje Görevler
      sekmesi, arama sonuçları), Fikirler `_CaptureTile` (bugünkü üç ikon kalabalığı
      kaydırmaya devredilir), Notlar **liste VE ızgara**, Projeler listesi, Dosyalar
      satırları (bugün eylem sayfasında — kaydırma kısayol olur, sayfa kalır).
      **Bilinçli istisna: Pano kartları** — yatay `PageView` yatay jesti sahipleniyor,
      çakışırsa sütun gezinmesi ölür; Pano'da silme kartın status sheet'ine eklenir.
- [x] **Detay yüzeyleri:** `TaskDetailScreen` app bar'ına silme eylemi (not editörü ve
      proje detayındaki kalıbın aynısı — üçü de aynı görünsün). Sildikten sonra
      `context.pop()` + snackbar.
- [x] **Liste menülerindeki boşluklar:** Notlar `_NoteMenu`'ye ve Projeler
      `PopupMenuButton`'ına **Sil** girer (kaydırma jestinin menüdeki karşılığı; masaüstü/
      web'de fare ile kaydırma yoktur — OPH-171'in R5 dersi birebir geçerli).
- [x] i18n: `common.delete` var; yeni `common.deleted`, `common.undo`,
      `task.deleteTitle`, `task.deleteBody`, `note.deleteFromList`, `swipe.deleteHint`
      (en+tr).
- [x] Testler: jest ile yarı açma → düğme görünür → basınca satır gider (görev, not,
      proje, dosya); **"Geri al" satırı geri getirir ve outbox'a HİÇBİR ŞEY yazılmaz**;
      snackbar süresi dolunca outbox'ta tek `delete` mutasyonu; Pano'da long-press
      sürükleme regresyonu; detaydan silince listeye dönüş; erişilebilirlik yolu
      (long-press) aynı akışı açıyor.

**Context:** Silme motorunun tamamı hazır (store hard-delete + outbox `delete`, API alt
ağaç tombstone'u + `cascadeDeleteFiles` + reminder reconcile). Bu task **yalnız
kullanıcı arayüzü** ekler — hiçbir API/migration değişikliği yok.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Paket alındı: `flutter_slidable` 4.0.3 → [ADR-0017](adr/0017-swipe-to-delete-package.md).**
  Belirleyici olan "kolay olsun" değil, **hangi 150 satırı yazacağımız**: geri açılma
  fiziği, fling eşiği, kaydırınca kapanma, kardeş satır açılınca kapanma ve yatay
  `PageView`'la jest arenası paylaşımı — aylarca ince ince yanlış kalan şeyler bunlar.
  Paketin **sıfır transitif bağımlılığı** var (`dependencies: [flutter]`). Görünen her
  şey bizde kaldı: `AwSwipeToDelete` paneli token'larla giydiriyor.
- **Otomatik kapanma tek satırla çözüldü:** `groupTag` yalnız bir
  `SlidableAutoCloseBehavior` atası altında çalışıyor ve o bir bildirim (notification)
  atası → `app.dart`'ta router'ın üstüne **bir tane** konunca uygulamadaki bütün
  listeler kapsandı; liste başına kablolama gerekmedi.
- **Gizleme, jestin değil sarmalayıcının işi oldu.** `AwSwipeToDelete` id'si beklemedeyse
  `SizedBox.shrink()` dönüyor → "satır gitti ama hiçbir şey yazılmadı" davranışı liste
  başına muhasebe istemedi. **İki yerde yetmedi ve testler ikisini de yakaladı:**
  (1) Home grupları ham listeden hesaplandığı için `awWithoutPending` filtresi
  gruplamadan ÖNCE gerekti (yoksa "Tomorrow · 1" başlığı boşluğun üstünde kalıyordu);
  (2) **Pano kartları bilinçli olarak sarmalanmadığı için (D6) hiçbir şey onları
  gizlemiyordu** — taşıma sayfasından silinen görev pencere kapanana kadar sütunda
  duruyordu; filtre `home_board.dart`'a da girdi.
- **GERÇEK BUG, testin bulduğu:** commit closure'ı widget'ın `WidgetRef`'ini
  kapatıyordu. Commit ~5 sn sonra bir timer'dan koşuyor ve o an satır listeden
  düşmüş, element dispose olmuş oluyor → `Bad state: Using "ref" when a widget is
  about to or has been unmounted` ve **silme hiç gerçekleşmiyordu**. Çözüm: store
  hâlâ mount'luyken çözülüyor (`final store = ref.read(taskStoreProvider)`), closure
  yalnız onu taşıyor. (Repo bunu daha önce OPH-170'te görmüştü — UnmountedRef dersi.)
- **İki dereceli onay uygulandı:** görev/not → dialog yok, "Geri al" snackbar'ı;
  proje/klasör/dosya → **mevcut onay dialog'u korunuyor** (kaskad sorusu atlanamaz;
  dosya silme her cihazda objeyi öldürüyor). Kaydırma, dialog'a **kısayol**, dialog'un
  **etrafından dolaşma yolu değil** — test bunu ayrıca doğruluyor.
- **Fikirler satırı sadeleşti:** silme onay dialog'u kalktı (artık geri alınabiliyor),
  ikon **kaldı** — D2 gereği (fare kaydırmaz). Aynı gerekçeyle Notlar ve Projeler
  liste menülerine "Sil" girdi ve **not ızgarasına hiç olmayan eylem menüsü** eklendi
  (orada arşivleme bile yoktu).
- **Bonus, aynı denetimden:** proje satırı `Text(project.status)` ile ham İngilizce
  enum basıyordu ("paused") — kaldırıldı, arşivli olan kendi yerelleştirilmiş
  etiketini gösteriyor. OPH-193 kalanını temizleyecek.
- **Test dersleri:** `pumpAndSettle` kare üretimi bitene kadar ilerlediği için
  **kısa** bir geri-alma penceresi test edilemez hâle geliyor (settle penceresi
  atlıyor) → gerçek `kAwUndoWindow` kullanılıp `pump(window + 1 sn)` ile atlanıyor;
  `scrollUntilVisible` widget'ı VAR ETMEKLE yetiniyor, telefonda yüzen alt barın
  altında bırakıyor → `ensureVisible` şart (OPH-181 idiomu); grup başlığı sayı
  taşıyor ("Tomorrow · 1"), `find.text('Tomorrow')` bulmaz.

**DoD met 2026-07-28:** app **520/520** (+27 test; 9'u bu task) + `analyze` temiz +
`check:i18n` + kontrast **FAILURES: 0** (kırmızı eylem paneli iki temada ölçüldü);
DESIGN §19 + [ADR-0017](adr/0017-swipe-to-delete-package.md); CHANGELOG; STATE.

### OPH-185 — Tamamlanan görev aynı gün listede kalır, soluk olur (round 10 #2) ✅ 2026-07-28

- [x] **Kural (BLUEPRINT §12.2'ye yazılır):** bir görev tamamlandığında **o yerel gün
      boyunca kendi grubunda kalır**, sonraki yerel gece yarısında listeden düşer ve
      artık yalnız Tamamlananlar'da (OPH-186) yaşar. Grubu değişmez ("aynı gününde
      gözükmeli") ama **grubunun sonuna** sıralanır — bitmiş iş, bekleyen işin üstünde
      durmaz.
- [x] **Sorgu:** `watchOpen(workspaceId, {DateTime? completedSince})` →
      `status IN kPlanningStatuses OR (status = 'completed' AND completedAt >= completedSince)`.
      Aynı kural `watchProjectTasks` için de geçerli. `boardTasksProvider` (watchAll)
      değişmez.
- [x] **Gün sınırı canlı olmalı:** yeni `dayBoundaryProvider` — bir sonraki yerel gece
      yarısına kurulmuş timer + `AppLifecycleState.resumed`'da yeniden hesap (uyuyan
      cihaz, saat/DST değişimi, uçak modu). Sınır değişince sağlayıcı yeniden
      yayınlanır ve dünün tamamlananları **kendiliğinden** düşer. Test: sahte saatle
      23:59 → 00:01 geçişi.
- [x] **Görsel (DESIGN §20'ye yazılır):** tamamlanmış satır bir bütün olarak sakinleşir —
      kart yüzeyi `surfaceContainerLow`, başlık üstü çizili + `onSurfaceVariant`
      (bugün var), alt satır/rozet/bayrak da soluk tona iner, onay dairesi **parlak
      yeşil değil sakin (muted) success** tonuyla dolar. **`Opacity` KULLANILMAZ** —
      opaklık sarmalayıcısı kontrastı ölçülemez hâle getirir ve DESIGN §5'in
      ≥ 4.5:1 garantisini kırar; her renk açık token olur ve `contrast.py` çiftleri
      öğrenir. Seçili-gün `dimmed` görünümüyle karışmaması için tonlar ayrışır.
- [x] **Onay kutusu tamamlamanın geri alması olur:** satır durduğu için ayrı bir "geri
      al" snackbar'ına gerek kalmaz (bugün Home'da tamamlamanın hiçbir dönüşü yok).
      Tamamlama anında hafif bir hareket (`AwMotion.fast`) satırın yerinde kaldığını
      anlatır — kaybolma sanılmasın.
- [x] **Takvim noktaları ve widget:** `daysWithTasks` tamamlananları nokta saymaz
      (bitmiş gün "dolu gün" değildir); widget aynı kuralı kullanır (uygulama ile
      widget kullanıcının önünde çelişemez — §17 D1'in ruhu) → snapshot kaynağı
      OPH-187 ile birlikte gözden geçirilir.
- [x] Testler: bugün tamamlanan görev Home'da kalıyor **ve grubunun sonunda**; dün
      tamamlanan görev listede yok; gece yarısı geçişi satırı düşürüyor; proje Görevler
      sekmesinde aynısı; tamamlanmış satırın kontrastı iki temada geçiyor; onay kutusu
      geri açıyor.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Sorgu tek yerden değişti:** `watchOpen(ws, {completedSince})` +
  `watchProjectTasks(..., {completedSince})`. Sınır **null geçilince eski davranış
  aynen duruyor** (terminal statüler gizli) — Pano'nun `watchAll`'ı ve gün-kapsamlı
  olmayan çağıranlar etkilenmedi. `cancelled`/`archived` sınır ne olursa olsun
  geri gelmiyor (test var).
- **Sınır canlı: `dayBoundaryProvider`.** Gece yarısına kurulu timer **+ 1 sn pay**
  (erken ateşleyen timer "dün"ü hesaplayıp geçmiş bir sınıra yeniden kurabilirdi) ve
  `AppLifecycleState.resumed` dinleyicisi — askıya alınmış uygulamanın timer'ı
  ateşlemez, cihaz gece yarısını uyuyarak geçebilir. Saat/saat dilimi değişimi de
  aynı iki yoldan geçiyor, çünkü her tick `DateTime.now()`'dan yeniden hesaplıyor.
  Saat enjekte edilebilir (`nowProvider`) — OPH-143'ün "fake clock" idiomu.
- **Sıralama kuralı gruplamaya girdi:** tamamlanan satır kendi grubunda kalıyor ama
  **grubun sonuna** iniyor; saat olarak önde olsa bile bekleyen işin üstünde durmuyor.
  Aynı satır widget'ın snapshot'ında da uygulandı — uygulama ile widget aynı sırayı
  gösteriyor (C5, test var).
- **KONTRAST GERÇEĞİ tasarımı değiştirdi (DESIGN §20 C2 revize edildi):** onay
  dairesinin dolgusunu yüzeye doğru soldurmak ölçüldü ve tik glifini **~2.3:1**'e
  düşürüyor — §5'in 3:1 tabanının altı. Karar: **dolgu tam güçte `success` kalıyor**,
  sakinlik satırdan geliyor (kart `surfaceContainerLow`, başlık üstü çizili +
  `onSurfaceVariant`, tarih soluk). Apple Reminders de böyle okur. `Opacity`
  kullanılmadı (C3) → sekiz yeni çift `contrast.py`'a girdi ve ölçülebilir kaldı.
- **Bitmiş görevin alarm çipleri kalktı** (acil işareti, ertelendi, susturuldu):
  terminal statüde `alarmInstantsFor` zaten boş liste döndürüyor, yani o çipler
  **yanlış bir iddiaydı** — §11 A5'in yasakladığı türden. Gürültü değil, doğruluk.
- **Bedava gelen:** widget köprüsü `openTasksProvider`'ı izlediği için C5 ek kod
  istemedi; takvim noktaları (`daysWithTasks`) tamamlananları saymıyor.

**DoD met 2026-07-28:** app **520/520** (13'ü saf sorgu/gruplama testi) + `analyze` +
`check:i18n` + kontrast **FAILURES: 0** (8 yeni çift); DESIGN §20 C2/C3 revize +
BLUEPRINT §12.2/§4.3; CHANGELOG; STATE.

### OPH-186 — Tamamlananlar: Ayarlar'da sonsuz kaydırmalı zaman çizelgesi (round 10 #3) ✅ 2026-07-28

- [x] **Yer:** Ayarlar → "Tamamlananlar" satırı (dil/tarih biçimi satırlarının deyimi),
      rota `/settings/completed`. Ana gezinmeye **sekme eklenmez** — round 1'in
      "tek zengin Home, az sekme" kuralı korunur.
- [x] **Sıralama (kullanıcının kuralı, birebir):** `dueAt ?? completedAt` üzerinden
      **yeniden eskiye**. Gün başlıklarıyla bölünmüş zaman çizelgesi (bugün / dün /
      tarih), satırlar `TaskTile`'ın tamamlanmış görünümünü kullanır.
- [x] **Sayfalı yükleme:** yerel replikadan `LIMIT/OFFSET` ile 50'şer sayfa, sona
      yaklaşınca sonrakini çeker (`ScrollController` eşiği); yükleme göstergesi listenin
      **sonunda**; `AwRefresh` üstte. Sunucuya yeni uç **gerekmez** — pull hiçbir statüyü
      filtrelemiyor, tamamlananlar zaten replikada.
- [x] **drift v12: `tasks(status, completedAt)` indeksi** — sayfalı sorgu tarama
      yapmasın. Migration append-only kuralı + `from >=` guard'ı (OPH-167 dersi).
- [x] **Satır eylemleri:** dokun → görev detayı; kaydır → sil (OPH-184'ün ilkeli);
      satır içi **"Geri aç"** (görevi `open`'a döndürür ve listeden düşer — anında
      kaybolması burada DOĞRU davranıştır, çünkü ekranın sözleşmesi "tamamlananlar").
- [x] **Boş durum + kapsam cümlesi:** `AwEmptyState` ("Henüz tamamlanan bir görev yok")
      ve verinin üstünde tek satır kapsam metni (alarm günlüğünün deyimi): **yalnız
      `completed`** listelenir; `cancelled`/`archived` **v1'de yok** ve bu ekranda yazılı.
- [x] i18n: `completed.title/sub/empty/scope/reopen/todayHeader/yesterdayHeader` (en+tr).
- [x] Testler: sıralama kuralı saf fonksiyon olarak (tarihi olan/olmayan karışık küme);
      50'nin üstünde görevle ikinci sayfanın kaydırınca geldiği; "Geri aç" satırı
      düşürüyor **ve** Home'a geri koyuyor; boş durum; kaydırarak silme.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **`watchCompleted` bilinçli olarak `_watchList`'i KULLANMIYOR** ve gerekçesi
  ölçülebilir: `_watchList` etiket tablosuna join atıyor, **join'li bir ifadede
  `LIMIT` JOIN'LENMİŞ satırları sayar** → 3 etiketli bir görev sayfanın üç slotunu
  yerdi ve sayfa boyu kullanıcının etiketleme alışkanlığına bağlı olurdu. Sayfa
  görev satırları üzerinden alınıyor, o sayfanın etiketleri sonra okunuyor.
  **Bedeli saklanmadı, yazıldı:** bu akış görev değişiminde yeniden yayınlıyor, etiket
  yeniden adlandırmasında değil — arşiv için kabul edilebilir, canlı liste için yanlış.
  Test bunu doğrudan sınıyor (3 etiketli görev sayfanın TEK satırı).
- **Sıralama kullanıcının cümlesi:** `COALESCE(due_at, completed_at)` DESC + **kararlı
  eşitlik bozucu** (`id` DESC, ULID). Eşitlik bozucu olmadan sayfa sınırında satır
  tekrarlanabilir veya atlanabilirdi. Test tarihi olan ve olmayanı karıştırıp
  bitirme sırasını sıralamadan FARKLI kuruyor — tek anlı bir test iki kuralı da geçerdi.
- **Sayfalama sayfa EKLEMİYOR, pencereyi büyütüyor** (`completedTasksProvider(pages)`
  → `limit: pages * 50`): iki listeyi birleştirmek sınırlarda tekrar/atlama üretir;
  tek sorgu büyüdüğü için kullanıcının okuduğu önek asla yeniden dizilmiyor (test).
  Sona gelmeden 400 px önce büyüyor ve **son sayfa DOLU değilse büyümüyor** — yoksa
  değişmeyen bir sonuca karşı sorgu sonsuza kadar yeniden koşardı.
- **drift v12 = yalnız indeks** (`idx_tasks_completed`), kolon/veri değişikliği yok.
  `Migrator`'da `customStatement` yok → `onUpgrade` içinde veritabanının kendi
  `customStatement`'ı kullanıldı; ayrıca **`onCreate`'e de eklendi**, çünkü drift'in
  `createAll`'ı tabloları yaratır, ad-hoc indeksleri değil — yeni kullanıcılar sessizce
  tam-tarama yolunda kalırdı. Testler indeksin varlığını **sqlite'ın kendi
  kataloğundan** doğruluyor (migration "koştu" ama indeks yok senaryosu yakalanır).
- **Sekme eklenmedi:** Ayarlar → Tamamlananlar. Round 1'in "tek zengin Home, az sekme"
  kuralı korundu; kapsam cümlesi verinin ÜSTÜNDE (alarm günlüğü deyimi), v1 yalnız
  `completed`.
- **"Geri aç" satırı ekrandan düşürüyor ve bu doğru davranış** — ekranın sözleşmesi
  "tamamlananlar" ve görev artık tamamlanmış değil. Test hem düşmeyi hem Home'a
  dönmeyi doğruluyor.
- **Test altyapısında bulunan boşluk:** `FakeApi.seedTask(status: 'completed')`
  `completedAt` yazmıyordu — üretimde var olamayacak bir satır (sunucu geçişte
  damgalıyor) ve OPH-185'in gün sınırı tam da onu okuyor. `seedTask`'a `completedAt`
  parametresi eklendi, `status: 'completed'` için varsayılanı dolduruluyor.

**DoD met 2026-07-28:** app **520/520** (+5 ekran testi) + `analyze` + `check:i18n` +
kontrast FAILURES: 0; drift v12 migration testi (yükseltme + taze kurulum);
DESIGN §20 C4 + BLUEPRINT §12.14; CHANGELOG; STATE.

### OPH-187 — Widget başlığı: hizalama + günün açık görev sayısı (round 10 #4A, #4B) ✅ 2026-07-29

- [x] **Hizalama (4A):** iOS'ta `HStack(alignment: .firstTextBaseline)` bırakılır;
      gün sayısı ile hafta günü/ay bloğu **optik olarak ortalanır** (Android'in bugünkü
      `center_vertical` davranışı doğru referanstır) ve iki platform **aynı** çizer
      (WIDGETS W1). Ay satırı gün sayısının altına sarkmaz.
- [x] **Sayı (4B):** başlığın sağ ucuna, gün/ay bloğunun hizasına **bugünün açık görev
      sayısı**. Tanım (kullanıcının cümlesi): **geciken + bugün** — yani "tarihi bugün
      olanlar" değil, bugün ilgilenilmesi gereken toplam. **Kayıt altına alınan karar:
      tarihsiz görevler bu sayıya DAHİL DEĞİL** (kullanıcı "ertelenmiş / gecikmiş /
      tarihi geçmiş + bugün" dedi); tek alanlık bir karar, istenirse bir satırda döner.
      Susturulmuş/ertelenmiş görevler **sayılır** (hâlâ açık iştir).
- [x] **Snapshot sözleşmesi (WIDGETS §3.1):** `openToday` (int) alanı eklenir, saf
      `buildWidgetSnapshot` içinde hesaplanır; `kWidgetSnapshotVersion` **2** olur.
      **Native taraf eksik alana toleranslı** olmalı (eski uygulama + yeni widget ve
      tersi bir süre yan yana yaşar) — yoksa güncelleme sırasında widget boşalır.
- [x] **Yerelleştirme:** sayının etiketi de snapshot'ın `strings`'inden gelir
      (`openToday` → "3 açık" / "3 open") — native tarafta çeviri yok (W-kuralı).
      Sıfır durumunda sayı **gizlenir** (0 yazan bir rozet gürültüdür).
- [x] **Tamamlanan satırlar:** OPH-185'in kuralı widget'a da uygulanır (bugün
      tamamlanan görev gün sonuna kadar `done: true` olarak görünür) — uygulama ile
      widget aynı şeyi göstermek zorunda.
- [x] Testler: `buildWidgetSnapshot` saf testleri (geciken 2 + bugün 3 → `openToday` 5;
      tarihsiz sayılmıyor; hepsi tamamlanmışsa 0 → alan gizli); JSON şeması v2;
      `flutter build ios` + `flutter build apk`. **Cihazda görsel doğrulama** (iki tema,
      medium/large) OPH-188'in cihaz turuna biner.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-29):**

- **Sayı, widget'ın ÇİZDİĞİ gruplamadan sayılıyor** (`groupTasksForWidget`
  sonucu üzerinden), ayrı bir sorgudan değil — rozet ile satırlar matematiksel
  olarak çelişemez.
- **Alan yalnız `openToday > 0` iken yazılıyor.** Sıfırda alanın hiç olmaması
  "gizle" ile aynı anlama geliyor; Swift tarafı `Int?`, Kotlin tarafı
  `optInt(...,0)` → **eksik alan widget'ı boşaltmıyor**, eski uygulama + yeni
  widget (ve tersi) yan yana yaşayabiliyor.
- **Hizalama iki platformda da merkez:** iOS `.firstTextBaseline`'dan çıktı,
  Android zaten `center_vertical`'dı. W6, W1'in parite kuralını **yerleşime**
  uygulayacak şekilde genişletildi — iki platform bir sürüm boyunca farklı çizdi
  ve kimse yan yana koymadığı için görülmedi.
- **Ertelenmiş/susturulmuş sayılıyor** (hâlâ açık iş), **tarihsiz sayılmıyor**
  (her günün işi olduğundan her günü şişirirdi) — kullanıcının cümlesiyle
  birebir ve testte yazılı.

**DoD met 2026-07-29:** Dart testleri (5) + `analyze` + `check:i18n`; WIDGETS §3.1
(v2 sözleşmesi) + DESIGN §8 W6/W9 güncel; CHANGELOG + STATE. _Cihazda görsel
doğrulama OPH-188'in cihaz turunda._

### OPH-188 — Widget'tan tamamlama: iOS App Intents + Android geri çağırma (round 10 #4C) — kod ✅ 2026-07-29, cihaz matrisi AÇIK

**Bu task, açık duran [OPH-132](#oph-132--ios-interactivity-quick-complete--quick-add-app-intents)
ile OPH-133'ün son iki kutusunu DEVRALIR** (ikisi de burada kapanır; oradaki kutulara
"→ OPH-188" notu düşülür).

- [x] **Hazır kalıbı yeniden kullan (round 9'un kazancı):** OPH-182 zaten
      `ios/Shared/AWAlarmShared.swift`'te **iki hedefte derlenen** App Intent'ler +
      **App Group kuyruğu** (`AWAlarmActionQueue`, uygulama kapalıyken basılan düğmeleri
      biriktirip `drainPendingActions` ile boşaltır) kurdu. Widget tamamlama intent'i
      **aynı yolu** kullanır — sıfırdan bir mekanizma yazılmaz.
- [x] **iOS 17+:** satırdaki daire `Button(intent: AWCompleteTaskIntent(taskId:))` olur;
      `@available(iOS 17, *)` ile kapılır, iOS 16 bugünkü deep-link'te kalır. Dokunma
      hedefi cömert (Reminders dersi, DESIGN W4), satır tamamlanınca ~1–2 sn sonra
      yerinde soluklaşır (OPH-185'in görünümü).
- [x] **Android:** `RemoteViews.setOnClickFillInIntent` **onay dairesine ayrı** bağlanır
      (satırın kendisi görevi açar) → `HomeWidgetBackgroundIntent` → Dart
      `@pragma('vm:entry-point') widgetCallback(Uri?)`. **Önce eksik veriyi kapat:**
      `TasksRemoteViewsFactory`'nin `Row` kaydı bugün **görev id'sini taşımıyor** —
      snapshot'ta id var, factory atıyor; eklenmeden ne tamamlama ne satır bağlantısı
      mümkün.
- [x] **Dart tarafı tek yol:** `widgetCallback` → `TaskStore.complete()` (UI'nin
      kullandığı **aynı** iyimser satır + outbox yolu → sunucuya senkronlanır) →
      `HomeWidget.updateWidget(...)`. `HomeWidget.registerInteractivityCallback` `main()`'de.
      **Çevrimdışı tamamlama kaybolmaz** (outbox zaten çevrimdışı çalışıyor).
- [x] **Satır → görev detayı:** her satır `alliswell://task/{id}` taşır (OPH-189'un
      yönlendirmesi olmadan bu adım anlamsız → sıra bağlayıcı).
- [ ] **Cihaz DoD matrisi (AÇIK — kullanıcının telefonu gerekiyor):** iPhone (iOS 17+) ve Android telefonda: uygulamayı
      **açmadan** tamamla → widget yerinde güncelleniyor; uygulama açılınca satır
      tamamlanmış; başka bir cihazda/senkronda görünüyor; **uçak modunda** tamamla →
      ağ gelince senkronlanıyor; satıra dokunma doğru görevi açıyor; iOS 16 cihaz/simülatör
      deep-link'e düşüyor.

**Context:** ADR-0010 D4 + WIDGETS §4; `flutter analyze`/`test` Swift/Kotlin derlemez —
round 9'un kalıcı dersi: **native bağlantı kaynak ağacından değil üründen doğrulanır.**

**Uygulamada ortaya çıkanlar / kararlar (2026-07-29):**

- **Hiçbir yeni mekanizma yazılmadı.** iOS'ta `AWCompleteTaskIntent`
  (`LiveActivityIntent`, `openAppWhenRun: false`) OPH-182'nin **App Group
  kuyruğuna** yazıyor; `actionId: "complete"` zaten `handleNotificationEvent`
  içinde `TaskStore.complete`'e gidiyordu. Soğuk uygulamada basılan düğmenin
  kaybolmaması o kuyruğun tek varlık sebebiydi.
- **Android'de önce eksik veri kapandı:** `TasksRemoteViewsFactory`'nin `Row`
  kaydı **görev id'sini atıyordu** — ne satır bazlı tamamlama ne satır bazlı
  derin bağlantı mümkündü. Şimdi satırda **iki ayrı fill-in intent** var (satır →
  görevi aç, daire → tamamla); koleksiyon başına tek `PendingIntent` şablonu
  olduğu için ayrım intent-extra'sıyla yapılıyor.
- **Dart geri çağırması kendi izole dünyasında:** arka plan isolate'ında Riverpod
  kapsamı yok, `handleWidgetAction` kendi bağlantısını açıyor ve **yalnız kendi
  açtığını kapatıyor** — enjekte edilen handle sahibinindir. İlk hâli testte
  "can't re-open a database" verdi; kural oradan doğdu.
- **Yazma yolu tek:** `TaskStore.complete` → iyimser satır + outbox. Widget'ın
  kendi yazma yolu YOK, çevrimdışı tamamlama sıradan bir outbox mutasyonu (test).
- **`@pragma('vm:entry-point')` zorunlu:** olmadan ağaç budama fonksiyonu siler ve
  düğmeler **yalnız release'te** sessizce hiçbir şey yapmaz.
- **`alliswell://complete` bir ROTA DEĞİL** — arka plan intent'inin içinde URL
  taşıması sorun değil (imzalı intent üretiyor), ama yönlendirme tablosuna asla
  girmiyor (ADR-0016'nın güvenlik satırı, testte yazılı).
- **OPH-132 ve OPH-133'ün açık kutuları bu task'a devredildi.**

**Kodsal DoD met 2026-07-29:** app **544/544** + `analyze` + `check:i18n` temiz.
**Kalan tek şey cihaz matrisi** (yukarıdaki açık kutu) — kullanıcının telefonunu
gerektiriyor, kod tarafında iş yok.

### OPH-189 — `alliswell://` yönlendirmesi + yönlendiricinin hata çıkışı (round 10 #4D) ✅ 2026-07-29

- [x] **Şemayı OS'a kaydet:** iOS `Runner/Info.plist` → `CFBundleURLTypes` /
      `CFBundleURLSchemes: [alliswell]`; Android `AndroidManifest.xml` →
      `<intent-filter>` + `<data android:scheme="alliswell"/>` (`android:autoVerify` yok —
      özel şema, App Links değil). macOS Runner'a da aynısı.
- [x] **Saf URL çözücü:** `lib/src/core/deep_link.dart` →
      `String? awRouteForUri(Uri)` — tamamen saf, birim testli:
      `alliswell://open` → `/home` · `alliswell://task/{ulid}` → `/tasks/{ulid}` ·
      `alliswell://file/{ulid}` → `/files` (+ seçim) · bilinmeyen → `null`.
      **Bozuk/uydurma id'ler reddedilir** (ULID biçim kontrolü) — dışarıdan gelen URL
      güvenilmez veridir. `alliswell://complete?id=` **rota değildir**: onu OPH-188'in
      arka plan geri çağırması yer, yönlendiriciye hiç ulaşmaz.
- [x] **go_router'a bağla:** gelen ham URL, konum eşleyiciye girmeden önce çözülür
      (`GoRouter.onException` + `redirect` ikilisi). Kimlik doğrulama redirect'i
      **korunur**: oturum kapalıyken gelen derin bağlantı `/login`'e gider ve giriş
      sonrası **hedefe devam eder** (bekleyen hedef `pendingDeepLinkProvider`'da).
- [x] **İki ölü uç kapanır:** (a) **`/` rotası** eklenir → oturum varsa `/home`, yoksa
      `/login`'e yönlendirir; (b) `GoRouter.errorBuilder` yazılır → `AwErrorState`
      (DESIGN §4) + **gerçekten çalışan** "Ana sayfaya dön" (`AppSection.home.path`,
      asla `/`) + hatalı konumu küçük punto gösterir. Bugünkü ekran go_router'ın
      varsayılanı ve düğmesi `/`'a gidiyor — yani hata sayfasının kendisi hata veriyor.
- [x] **ADR-0016 — uygulama içi URL sözleşmesi:** `alliswell://` şeması bugüne kadar
      yalnız takvim eşlemesinin işaretiydi (ADR-0003); bu ADR onu **gerçek bir
      gezinme yüzeyine** çeviriyor: host/yol tablosu, kim üretir (widget, bildirim,
      takvim etkinliği, not gömmesi), kim tüketir, bilinmeyen URL politikası ve
      güvenlik notu (dışarıdan gelen bağlantı yalnız NAVİGASYON yapar — hiçbir zaman
      veri yazmaz; yazan tek yol imzalı App Intent kuyruğudur).
- [x] Testler: `awRouteForUri` tablo testi (geçerli/geçersiz/eksik id/fazla segment);
      router redirect testine derin bağlantı senaryoları (oturum açık/kapalı);
      `errorBuilder` bilinmeyen konumda görünüyor ve düğmesi Home'a gidiyor;
      `/` → `/home` yönlendirmesi.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-29):**

- **go_router `onException` ile `errorBuilder`'ı BİRLİKTE kabul etmiyor**
  ("Only one of…" assertion'ı). İlk hâlde ikisi de vardı ve **süitin yarısı
  düştü** — sağlayıcı hataya düşünce uygulama hiç kurulmuyor. Kalan
  `onException`, çünkü **yalnız o yönlendirebiliyor** ve bu task'ın işi tam
  olarak yönlendirmek. Çözülemeyen konumlar kendi `/not-found` rotamıza
  düşüyor: "hata sayfası" artık gerçek bir rota ve çıkışı çalışıyor.
- **`/` gerçek bir rota oldu** — go_router'ın VARSAYILAN hata sayfasının "Home"
  düğmesi oraya gidiyor ve rota olmadığı için **ikinci bir hata** üretiyordu.
  `router_redirect_test` bunu ayrıca doğruluyor.
- **Çözücü saf ve tablo testli**, ULID doğrulaması dahil: URL güvenilmez
  girdidir (başkasının istemcisinin yazdığı bir takvim etkinliğinden gelebilir),
  `../../etc` ya da kısa bir id rota olamıyor. Bilinmeyen URL hata DEĞİL —
  gönderen daha yeni bir sürüm olabilir; uygulama normal açılıyor.
- **Bekleyen derin bağlantı:** oturum kapalıyken gelen bağlantı düşmüyor,
  girişten sonra oynatılıyor. `computeAuthRedirect` **saf ve dokunulmadan**
  kaldı; durum yalnız router'ın kapatmasında.
- **Şema iki OS'a da kaydedildi** (`CFBundleURLTypes`, Android `intent-filter` +
  `BROWSABLE`). Kayıt yoksa OS uygulamayı **hiç başlatmıyor** ve hata sessiz —
  cihaz turundaki "widget'a dokun" maddesi bu yüzden var.

**DoD met 2026-07-29:** app **544/544** (+10 test, +1 router testi) + `analyze` +
`check:i18n`; ADR-0016 kabul edildi; WIDGETS §4 güncel; manifest değişiklikleri
build'de; CHANGELOG + STATE. _Gerçek cihazda widget'a dokunup doğru ekrana düşme
OPH-188'in cihaz turunda._

### OPH-190 — Ses önizlemesi: durdur gerçekten durdursun (round 10 #5) ✅ 2026-07-28

- [x] **Çalar state'e taşınır:** `_SoundPickerSheetState._player` (tek örnek, tembel
      yaratılır) ve **`dispose()` onu durdurup serbest bırakır**. Bugün çalar metodun
      içinde doğuyor, sheet kapansa bile `Future.delayed` bitene kadar ses devam ediyor.
- [x] **Durdur düğmesi çalışır:** `onPressed` asla `null` olmaz →
      `_previewing == sound.id ? _stopPreview : () => _preview(sound)`. İkon ne
      gösteriyorsa onu yapar (bugün "stop" gösterip devre dışı duruyor).
- [x] **Başka bir sese basmak anında geçer:** yeni önizleme öncekini **durdurup**
      hemen başlar; "önceki bitene kadar bekle" davranışı kalkar (bugün tüm düğmeler
      birlikte kilitleniyor).
- [x] **Sheet kapanınca / ekrandan çıkınca susar** — `dispose` + `PopScope`/route
      gözlemi; ayrıca **gerçek bir alarm çalmaya başlarsa önizleme susar** (ring ekranı
      önizlemenin üstüne binmez).
- [x] **Yüklenen seslerin önizlemesi gelir** (bugün yok — DESIGN §18 N6 "sesi DUYARAK
      seçersin" der ama kendi yüklediğin sesi seçmeden duyamıyorsun): satırda aynı
      önizleme düğmesi; ses indirilir + çalınır, indirilemezse **dürüst hata**
      (sessizce hiçbir şey olmaması yasak).
- [x] **Süre:** önizleme paketli sesin kendi uzunluğu kadar (≤ 4 sn tavanı korunur) ve
      **kendiliğinden durunca ikon geri döner** — durum tek yerden (`_previewing`)
      okunur.
- [x] Testler: sahte `AlarmSoundPlayer` ile çağrı sırası (`loop` → `stop`); durdur
      düğmesi `stop` çağırıyor; ikinci sese basmak `stop`+`loop` üretiyor; sheet
      dispose'unda `stop`+`dispose`; yüklenen ses önizlemesinin indirme hatası mesaj
      gösteriyor.

**Context:** DESIGN §18 N6 revize edilir ("önizleme durdurulabilir olmak ZORUNDADIR;
duyulabilir hiçbir ses kullanıcının kapatamayacağı bir yerde çalamaz").

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Üç şikâyet tek şekilden geliyordu:** çalar `_preview` metodunun İÇİNDE
  doğuyordu, yani ona başka hiçbir yerden erişilemiyordu. Çalar state'e taşınınca
  (`_player`) üçü de aynı anda çözüldü — durdurma düğmesi, sese geçiş ve
  `dispose()`. "Kimsenin ulaşamadığı çalar, kimsenin durduramadığı çalardır."
- **`onPressed: null` yasaklandı.** Yeni `_PreviewButton` kuralı: **düğme her
  zaman ikonunun söylediğini yapar**. Eskiden ikon "stop"a dönüyor ama düğme
  devre dışı kalıyordu — ve devre dışı olan yalnız o değildi, `_previewing != null`
  olduğu için **bütün diğer sesler de** kilitleniyordu ("bir sonrakine tıkladım,
  bitince başladı" şikâyetinin birebir kaynağı).
- **`Future.delayed` → iptal edilebilir `Timer`.** Önce token'lı bir koruma
  yazdım; testler daha iyisini dayattı: **bekleyen timer teardown'da testi
  düşürüyor.** İptal edilemeyen bir gecikme, ait olduğu önizleme bittikten sonra
  da yaşıyor ve kullanıcının başlattığı bir SONRAKİ sesi susturabilir.
  `_stopPreview` timer'ı iptal ediyor, `dispose` da.
- **Yüklenen seslere önizleme geldi** — hiç yoktu. N6 "sesi duyarak seçersin"
  diyordu ama kütüphanenin yarısı (kullanıcının kendi yüklediği dosyalar)
  seçmeden duyulamıyordu. İndirilemezse **dürüst hata** (`sound.previewFailed`).
- **Test altyapısı dersi:** sheet çalışma alanını izliyor (zil sesi klasörü için),
  bu yüzden çıplak bir `ProviderScope` auth restore'unun **4 sn'lik timer'ını**
  bekler hâlde bırakıyor ve test yanlış sebepten düşüyordu → picker testi de
  oturum açmış kapsamda pump ediliyor.
- **Seam:** `soundPreviewPlayerProvider` (`AlarmSoundPlayer Function()`) — testler
  çağrı SIRASINI doğruluyor (`stop0` → `loop1`), ki "önce durdur, sonra başlat"
  sözleşmesi tek görülebilir yer orası.

**DoD met 2026-07-28:** app **530/530** (+4 test) + `analyze` + `check:i18n` +
kontrast FAILURES: 0; DESIGN §18 N6 güncel; CHANGELOG; STATE.

### OPH-191 — Düzenlerken de saat seçilir: tek tarih-saat giriş yolu (round 10 #6) ✅ 2026-07-28

- [x] **Tek yol (DESIGN §17'ye D5 olarak yazılır):** tarih **ve saat** saklayan her
      alanın girişi tek paylaşılan yardımcıdan gelir —
      `awPickDateTime(context, ref, {DateTime? current, DateTime? anchor})`
      (`core/date_format.dart`'ın yanında): `showDatePicker` → `showTimePicker`,
      boş alanda **yarın** (OPH-173) + kullanıcının varsayılan saati (OPH-161),
      saat seçici kapatılırsa varsayılan saate düşer. Tarih **biçimi** nasıl tek
      kaynaktan geliyorsa (OPH-174), tarih **girişi** de tek kaynaktan gelir.
- [x] **Çağrı yerleri:** `task_create_sheet.dart`'ın `_pickDateTime`'ı bu yardımcıya
      devreder; `task_detail_screen.dart`'ın **üç `_DateRow`'u** (bitiş, hatırlatma ve
      OPH-192'den sonra koşullu planlanan) artık date+time sorar; `alarm_ring_screen`'in
      özel ertelemesi zaten date+time — aynı yardımcıya taşınır.
- [x] **Regresyon adıyla yazılır:** bugün 14:30'luk bir görevin **sadece gününü**
      değiştirmek saati sessizce 23:59 yapıyor; testin cümlesi budur.
- [x] Testler: mevcut saatli görevin gününü değiştir → **saat korunuyor**; boş alanda
      yarın + varsayılan saat; saat seçici iptal → varsayılan saat; üç satır için de
      aynı davranış; create ve detay aynı sonucu üretiyor (aynı görev, iki yol).

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Yeni dosya `core/date_input.dart`** — `awPickDateTime(context, ref, {current,
  anchor})`. Sözleşme keskin: **tarih adımından çıkmak `null` döndürür** ("değişiklik
  yok"), ama **yalnız SAATİ kapatmak iptal DEĞİLDİR** — gün seçilmiştir, saat
  mevcut değere, o da yoksa varsayılana düşer. Bu ayrım olmadan "tarihi seçtim,
  saat ekranını kapattım" ya hiçbir şey yapmaz ya da sessizce saati ezerdi.
- **Saat düşüş sırası `time ?? current ?? default`** — düzeltmenin can damarı bu
  satır. Eski kod doğrudan varsayılana düşüyordu, yani 14:30 → 23:59.
- **Ring ekranının özel ertelemesi bilinçli olarak DIŞARIDA kaldı.** Onun
  kısıtları farklı: `firstDate: now` (geçmişe ertelenemez), başlangıç saati
  "şimdi + 30 dk", ve kapatılırsa **şu anki** saate düşer. Üç bayrak eklemek tek
  çağıran için helper'ı şişirirdi; paylaşılan şey **kural** (saat sorulur), kod
  değil — zaten oradaki akış D5'e uyuyor.
- **Detay satırlarına test anahtarları verildi** (`due-row`, `remind-row`): eski
  tek anahtar `scheduled-row`'du ve OPH-192 onu koşullu hâle getirince
  `_DateRow`'un `key` parametresi kullanılmayan bir parametreye dönüşmüştü
  (analyzer yakaladı) — anahtarlar testin ihtiyacı olan yere taşındı.
- **Testin dişi:** `TimePickerDialog`'un varlığı ayrıca doğrulanıyor (adım hiç
  yoktu), sonra sunucudaki `dueAt`'ın **saati** kontrol ediliyor — yalnız "bir
  şey kaydedildi" demek bu hatayı yakalamazdı.

**DoD met 2026-07-28:** app **530/530** (+3 test) + `analyze` + `check:i18n`;
DESIGN §17 D5 yazılmış; CHANGELOG; STATE.

### OPH-192 — "Planlanan tarih" satırı: sabit alan olmaktan çıkar, koşullu olur (round 10 #7) ✅ 2026-07-28

> **Kullanıcıya açıklanacak (istediği gibi — "anlayamamışsam uyar, sebebini anlat"):**
> alan ölü değil. Takvim bloğu **önce `scheduled_start_at`'ten** türetiliyor
> ([mirror.js:21](../apps/api/src/lib/mirror.js#L21)) ve kullanıcı Google Takvim'de
> AllisWell etkinliğini **sürüklediğinde** sunucu `due_at`'i değil `scheduled_*`'ı
> yazıyor ([inbound.js:15](../apps/api/src/lib/inbound.js#L15)) — çünkü bloğu taşımak
> "bunu o saatte yapacağım" demektir, "son tarih değişti" değil. Satırı **düz silmek**
> şu tuzağı kurar: bir kez sürüklenmiş görevde takvim etkinliği o noktaya **çakılı
> kalır**, bitiş tarihi değişse bile yerinden oynamaz ve kullanıcının bunu görecek ya
> da temizleyecek hiçbir yolu kalmaz.

- [x] **Karar (öneri): sabit alan gider, koşullu satır gelir.** Detayın olağan alan
      listesinden `scheduled-row` **çıkarılır** (BLUEPRINT §12.4'ün alan listesinde
      zaten yoktu — OPH-076'nın eklediği bir sapmaydı). Yerine **yalnız
      `scheduledStartAt != null` iken** görünen bir bilgi satırı: "Takvimde taşındı —
      {tarih saat}", alt satırında ne anlama geldiği tek cümleyle, sağında
      **"Sıfırla"** (alanı temizler → etkinlik yeniden bitiş tarihine döner).
      Sürüklemeyen kullanıcı bu satırı **hiç görmez** — şikâyet birebir çözülür;
      sürükleyen kullanıcı sessiz bir sürprizle değil, açıklamayla karşılaşır.
- [x] **Alternatif (kullanıcı ısrar ederse):** satır tamamen kalkar ve inbound sürükleme
      `scheduled_*` yerine `due_at` yazar. Bu **sunucu davranışı + ADR-0007 değişikliği**
      demektir ve "bloğu taşımak son tarihi değiştirmez" ilkesinden vazgeçmektir;
      buraya seçenek olarak yazılır, varsayılan **değildir**.
- [x] i18n: `task.movedInCalendar`, `task.movedInCalendarSub`, `task.resetSchedule`
      (en+tr). `task.scheduledField` anahtarı kalkar.
- [x] Testler: `scheduledStartAt == null` görevde satır **yok** (widget ağaçtan silinmiş —
      OPH-172'nin "testin dişi" dersi); dolu görevde satır var ve tarihi doğru biçimde
      yazıyor; "Sıfırla" alanı null'lıyor ve outbox'a `scheduledStartAt: null` +
      `scheduledEndAt: null` gidiyor.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Önerilen yol uygulandı** (kullanıcı itiraz etmedi): sabit alan gitti, yerine
  `scheduledStartAt != null` iken görünen `_MovedInCalendarRow` geldi — "Takvimde
  taşındı — {tarih}", altında tek cümle açıklama, sağında **Sıfırla**.
  Sürüklemeyen kullanıcı bu kavramı hiç öğrenmiyor; sürükleyen kullanıcı sessiz
  bir sürpriz yerine cümle görüyor.
- **`task.scheduledField` anahtarı silindi.** "Planlanan" kelimesi hiçbir şey
  anlatmıyordu; yeni metin ne OLDUĞUNU söylüyor.
- **Sıfırla ikisini birden null'lıyor** (`scheduledStartAt` + `scheduledEndAt`):
  başlangıcı silip bitişi bırakmak §7.1'in **ters bir takvim bloğu** türetmesine
  yol açardı — eski kodun `scheduledEndAt: null` yorumu buradaki gerekçeyle aynı.
- **Round 6'nın testi ters çevrildi:** `calendar_mirror_test.dart`'ın "a scheduled
  block arriving from the calendar is visible" testi artık **"…EXPLAINS itself"**
  — "Scheduled" etiketinin YOKLUĞUNU ve açıklama metninin varlığını doğruluyor.
  Sürüklenmiş bir görevin görünürlüğü (OPH-076'nın asıl kazancı) korunuyor.
- **Sunucuda hiçbir şey değişmedi.** `scheduled_start_at` hâlâ takvim bloğunun
  birinci kaynağı, inbound hâlâ oraya yazıyor; değişen tek şey uygulamanın onu
  ne zaman ve nasıl gösterdiği.

**DoD met 2026-07-28:** app **530/530** (+2 test, +1 çevrilmiş test) + `analyze` +
`check:i18n`; BLUEPRINT §12.4 + §7.1 çapraz referansı güncel; CHANGELOG; STATE.

### OPH-193 — Proje düzenlemede "durum" seçimi kalkar (round 10 #8) ✅ 2026-07-28

- [x] **Dropdown silinir** (`project_edit_sheet.dart`'taki `if (_isEdit)` bloğu) ve
      `_status` state'i ile `kProjectStatuses` sabiti ölür. Ekleme ve düzenleme
      sheet'leri **aynı alanları** gösterir (bugünkü asimetri şikâyetin kendisi).
      Kaydetme gövdesinden `status` çıkar.
- [x] **Ürün kuralı (BLUEPRINT §4.2'ye yazılır):** kullanıcının gördüğü iki proje
      durumu vardır — **açık** ve **arşivli**. Arşiv, kaskad sorusuyla birlikte
      **kendi akışıdır** (OPH-110) ve tek giriş noktasıdır. `paused`/`completed`
      sunucu enum'unda **kalır** (migration yok, geriye uyum bozulmaz) ama arayüz
      onları üretmez; var olan satırlar "açık" gibi davranır.
- [x] **Ham enum sızıntısı kapanır (bonus, gerçek i18n hatası):** kullanıcıya ham
      İngilizce statü basan **üç yer** düzeltilir — `Text(project.status)`
      ([projects_screen.dart:161](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L161),
      [project_detail_screen.dart:197](../apps/app/lib/src/features/projects/ui/project_detail_screen.dart#L197))
      ve dropdown öğesi. Arşivli proje zaten kendi banner'ı/rozetiyle anlatılıyor →
      statü metni **tamamen kalkar**; arşivli olmayan hiçbir şey yazmaz.
      (`check:i18n` bunları yakalayamıyordu çünkü değişken basılıyor — bu, kontrolün
      bilinen kör noktası; OPH-195'e not düşülür.)
- [x] i18n: `project.status` anahtarı kalkar (kullanılmıyorsa `check:i18n` temizliği).
- [x] Testler: düzenleme sheet'inde durum alanı **yok**; kaydetme gövdesinde `status`
      **yok**; `paused` statülü mevcut bir proje listede/detayda ham metin göstermiyor
      ve normal davranıyor; arşivle/arşivden çıkar akışı regresyonsuz.

**Uygulamada ortaya çıkanlar / kararlar (2026-07-28):**

- **Üç ham enum sızıntısının üçü de kapandı:** dropdown silindi, proje listesi
  satırı (OPH-184 turunda) ve proje detayının çipi. Çip artık **projenin adını**
  taşıyor; arşivli olma zaten hemen üstündeki banner'da yazılı, yani bilgi
  kaybı yok — kaybolan tek şey İngilizce `active`/`paused` kelimeleriydi.
- **Sunucu dokunulmadı:** enum dört değerinde kaldı, migration yok, mevcut
  `paused` satırları olduğu gibi duruyor ve arayüzde "açık" gibi davranıyor.
  Test bunu açıkça doğruluyor (`paused` bir projeyi düzenle → kaydet →
  sunucudaki `status` hâlâ `paused`, `name` değişmiş).
- **Push gövdesi denetleniyor:** test yalnız "dropdown yok" demiyor, itilen
  **her** proje mutasyonunda `status` anahtarının bulunmadığını doğruluyor —
  arayüzden kaldırıp gövdede bırakmak sessiz bir gerileme olurdu.
- **OPH-110'un eski testi güçlendirildi.** "Dropdown 'archived' sunmuyor" testi
  artık "**durum değiştirmenin tek yolu arşiv akışı**" diyor: hiçbir statü
  metni ve hiçbir dropdown yok. Aynı kural, daha güçlü ifade.
- **`check:i18n`'in kör noktası kayda geçti:** kontrol `Text(değişken)`'i
  göremiyor, o yüzden bu sızıntılar bir sürüm boyunca yaşadı → OPH-195'in
  bulgu listesinde duruyor.

**DoD met 2026-07-28:** app **530/530** (+1 test, +1 güçlendirilmiş test) +
`analyze` + `check:i18n`; BLUEPRINT §4.2 güncel; CHANGELOG; STATE.

### OPH-194 — Sayfa geçişlerinde önceki ekranın hayaleti (round 10 #10) ✅ 2026-07-29

- [x] **Kök neden yazılı hâle gelir:** ekran zemini `tokens.veil` ve veil **yarı
      saydam** (açık %58, koyu %48); `AuroraBackground` ise **Navigator'ın altında**
      tek sefer boyanıyor. Push/pop sırasında iki rota da ağaçtayken gelen ekranın
      zemininden **giden ekran görünüyor**. Yani hayalet bir animasyon hatası değil,
      **tasarım sisteminin bir kuralının sonucu** — DESIGN §4 "Backgrounds" maddesi
      bu round'da değişir.
- [x] **Çözüm (öneri): zemin rota başına opak olur.** Paylaşılan `AwPageBackground`
      (aurora + veil, **opak**) rota sayfalarının altına girer; `MaterialApp.builder`
      yalnız kenar/boşluk durumları için kalır (ya da tamamen kalkar). Kabul ölçütü
      basit ve ölçülebilir: **hiçbir rota, altındaki rotayı göstermez.**
      Değerlendirilecek alternatifler ve neden reddedildikleri ADR/DESIGN'a yazılır:
      (b) veil'i aurora üzerine önceden karıştırıp opak tek renk yapmak — aurora
      gradyanını öldürür; (c) geçiş süresince araya opak katman koymak — semptomu
      örter, kökü durur.
- [x] **Geçiş dilinin kendisi tanımlanır (DESIGN §21):** bugün `pageTransitionsTheme`
      **hiç tanımlı değil** → Android'de Zoom, iOS'ta Cupertino kaydırma, masaüstünde
      başka bir şey. Tek bir geçiş ailesi seçilir (`AwMotion.base` 220 ms; öneri:
      fade-through + hafif kayma, her platformda aynı) ve tema üzerinden kurulur.
      Sekme değişimi (`StatefulShellRoute.indexedStack`) **anlık** kalır — sekmeler
      yığın değildir (OPH-108).
- [x] **Cam yüzeyler yeniden ölçülür:** `GlassSurface`'in `BackdropFilter`'ı geçiş
      sırasında ne örneklediği kontrol edilir (giden rotayı bulandırmamalı);
      gerekirse `RepaintBoundary`. Blur maliyeti geçişte en görünür yerdedir —
      profil çekilir.
- [x] **Kontrast yeniden koşar:** zemin bileşimi değişiyorsa `contrast.py`
      **FAILURES: 0** yeniden kanıtlanır (veil'in üstündeki her metin çifti).
- [x] Testler: rota geçişinin ortasında (`pump` ile yarı yolda) giden ekranın
      metninin **görünmediği** widget testi — bu, hatanın birebir testidir; sekme
      değişiminde regresyon yok; `flutter run --profile` ile telefonda gözle + kare
      süresi notu.

**Context:** DESIGN §4 "Backgrounds" ve ADR-0005/ADR-0012 bu değişiklikten etkilenir;
sapma **aynı değişiklikte** DESIGN'a yazılır (AGENTS sert kural 11).

**Uygulamada ortaya çıkanlar / kararlar (2026-07-29):**

- **Çözüm (c) seçildi ve en ucuzu çıktı:** `AwPageBackground` her rotanın altına
  giriyor (`router.dart`'ta tek `_page()` sarmalayıcısı), `MaterialApp.builder`'
  daki tek aurora kalktı. Ekran zemini (`veil`) yarı saydam KALDI — çünkü artık
  **kendi** rotasının aurorasının üstünde duruyor. Görünüm bir piksel değişmedi;
  değişen tek şey katman.
- **Builder'da opak bir taban bırakıldı** (`ColoredBox(auroraTop)`): geçişte
  Navigator'ın altı boş kalırsa siyah parlama olmasın.
- **Geçiş ailesi elle yazıldı.** Flutter'ın `FadeForwardsPageTransitionsBuilder`'ı
  en yakın eşleşme ama **450 ms** — sistemin kendi kuralını (G8: 150–320 ms)
  kırıyor. `AwPageTransitionsBuilder` aynı şekli `AwMotion.base` (220 ms) ve
  token'lı eğrilerle veriyor, **her platformda aynısı**.
- **Geçiş, saydamlığı ÖRTMÜYOR** — bilinçli. Sorun arka plan katmanında çözüldü;
  saydam sayfaları kapatmak için tasarlanmış bir geçiş, bozuk bir katmana perde
  olurdu.
- **Testin dişi:** geçişin ortasında `AwPageBackground` **iki tane** olmalı.
  Düzeltmeden önce bütün uygulamada bir taneydi (Navigator'ın altında) — bu sayı
  hatanın doğrudan ifadesi. Ayrıca her `TargetPlatform` için tek aile ve süre
  bütçesi doğrulanıyor.
- **Yan bulgu (bu değişiklikten bağımsız):** `tasks_flow_test`'in bir testi ayın
  29'unda kırmızıya döndü — "bugün + 3 gün" ay sınırını aşınca takvimde "1" yazan
  hücre Temmuz 1'di. Tarihe bağlı kırılgan bir tap'ti; hedef gün artık
  görüntülenen ayın içinde kalıyor.

**DoD met 2026-07-29:** app **544/544** (+3 test) + `analyze` + `check:i18n` +
kontrast FAILURES: 0; DESIGN §4 revize + §21 yeni; CHANGELOG + STATE.
_Cihazda/tarayıcıda gözle doğrulama kullanıcıya kaldı — testler yapıyı kanıtlar,
dokunuş hissini ölçemez._

### OPH-195 — Kapsamlı UX taraması: "eklenmiş ama silinmesi/gösterilmesi unutulmuş" ne varsa (round 10 #9) ✅ 2026-07-29

**Bu task açık uçlu bir "bir bak" değildir:** aşağıdaki bulgular bu round'un
denetiminde **zaten doğrulandı**; task bunları karara bağlar ve ardından matrisi
sistematik olarak kapatır.

- [x] **Bulgu 1 — modelde var, arayüzde yok (kolonlar yalan söylüyor):**
      `tasks.parent_task_id` (alt görevler — drift + API + **kaskadlı silme** hazır,
      **sıfır** arayüz), `tasks.color_rgb` (widget'ta kullanılıyor, seçtirilmiyor),
      `tasks.sort_order` (sıralamada kullanılıyor, **elle sıralama yok**),
      `tasks.repeat_rule` · `estimated_minutes` · `actual_minutes` · `start_at` ·
      `requires_acknowledgement`, `projects.icon` · `start_at` · `due_at`.
      BLUEPRINT §4.3 "recurring task"ı bir görev tipi olarak sayıyor — bugün yok.
      **Her biri için karar:** yüzeye çıkar (yeni task) **veya** park kuyruğuna
      gerekçesiyle yazılır. Ulaşılamayan kolon, modelde duran bir yalandır.
- [x] **Bulgu 2 — `check:i18n`'in kör noktası:** kontrol yalnız düz metin sabitlerini
      görüyor; `Text(değişken)` ile basılan ham enum'lar (OPH-193'ün üç yeri) elinden
      kaçtı. Kontrole "bilinen enum alanlarını doğrudan basma" kuralı eklenir veya
      lint kuralına dönüştürülür.
- [x] **Bulgu 3 — geri alınabilirlik:** Pano dışında hiçbir yıkıcı/dönüşü zor eylemde
      geri alma yok. OPH-184 (silme) ve OPH-185 (tamamlama) bunu kapatıyor; kalanlar
      taranır: arşivle, etiket sil, klasör sil, ses seçimi değiştir.
- [x] **Bulgu 4 — masaüstü/web paritesi:** OPH-171'in R5 dersi (fare kaydırmaz →
      düğme gerekir) yeni gelen her jest için tekrar sorulur; OPH-184'ün kaydırma
      jesti bunun ilk sınavı.
- [x] **Sistematik geçiş — matris:** {görev, proje, not, etiket, dosya, klasör,
      checklist öğesi, pano sütunu, hatırlatıcı zinciri adımı, zil sesi} ×
      {oluştur, gör, düzenle, **sil**, geri al, boş durum, hata durumu, çevrimdışı
      davranışı}. Her hücre: ✅ / ❌ / park. Matris TASKS'a yazılır, ❌'ler ya bu
      epic'te kapanır ya da gerekçeli olarak park kuyruğuna gider — **sessiz boşluk
      bırakılmaz.**
- [x] **Çıktı:** matris + kararlar TASKS'a; kapanmayanlar park kuyruğuna tek tek;
      yeni doğan işler bir sonraki epic'e OPH numaralarıyla.

**Context:** Kullanıcının cümlesi: "en basiti task ekleme düzenleme her şey var, silme
eklenmemiş — bunun gibi büyük UX hataları var her yerde". Bu task o cümleyi bir
yönteme çeviriyor.

**CRUD × varlık matrisi (2026-07-29, Epic 17 sonrası):**

| Varlık | Oluştur | Gör | Düzenle | **Sil** | Geri al | Boş durum | Hata durumu | Çevrimdışı |
| ------ | ------- | --- | ------- | ------- | ------- | --------- | ----------- | ---------- |
| Görev | ✅ | ✅ | ✅ | ✅ **184** (kaydırma + detay + Pano sheet'i) | ✅ 184 | ✅ | ✅ | ✅ outbox |
| Fikir (capture) | ✅ | ✅ | ✅ (planla) | ✅ 184 (kaydırma + ikon) | ✅ 184 | ✅ | ✅ | ✅ |
| Proje | ✅ | ✅ | ✅ | ✅ **184** (kaydırma + menü + detay; onaylı) | ⚠️ dialog | ✅ | ✅ | ⚠️ kaskad ağ ister (OPH-110) |
| Not | ✅ | ✅ | ✅ | ✅ **184** (kaydırma + menü + ızgara menüsü + editör) | ✅ 184 | ✅ | ✅ | ✅ |
| Etiket | ✅ oto | ✅ | ✅ | ✅ (yönetim sheet'i, sayılı onay) | ⚠️ dialog | ✅ | ✅ | ✅ |
| Dosya | ✅ | ✅ | ✅ ad | ✅ **184** (kaydırma + eylem sayfası; onaylı) | ❌ **park** (obje her cihazda ölüyor) | ✅ | ✅ | ⚠️ bytes ağ ister |
| Klasör | ✅ | ✅ | ✅ ad | ✅ (sayılı kaskad onayı) | ⚠️ dialog | ✅ | ✅ | ⚠️ |
| Checklist öğesi | ✅ | ✅ | ✅ | ✅ ikon | ❌ **park** (düşük bedel) | — | ✅ | ✅ |
| Pano sütunu | — | ✅ | ✅ (görünürlük + sıra) | — (statü silinmez) | — | ✅ K6 | — | ✅ cihaz-yerel |
| Hatırlatıcı adımı | ✅ | ✅ | ✅ | ✅ | ❌ **park** (fabrikaya dön var) | ✅ | ✅ | ✅ cihaz-yerel |
| Zil sesi | ✅ yükle | ✅ **+ önizleme 190** | — | ✅ (Dosyalar'dan) | ⚠️ | ✅ | ✅ 190 | ⚠️ indirme ağ ister |

**Kapanan bulgular (bu epic'te):** silme boşluğunun tamamı (184), not ızgarasında
**hiç eylem menüsü olmaması** (184), üç ham enum sızıntısı (193), `check:i18n`'in
`Text(değişken)` kör noktası (193'te kayda geçti), yüklenen seslerde önizleme
yokluğu (190), tamamlamada geri alma yokluğu (185), widget satırının **id
taşımaması** (188), `alliswell://` şemasının **iki OS'ta da kayıtlı olmaması** ve
`/` rotasının bulunmaması (189).

**Model'de var, arayüzde yok — kararlar (hepsi park, gerekçeli):**

- `tasks.parent_task_id` (**alt görevler**) — şema + API + sunucu kaskadı hazır,
  arayüz yok. **Park:** kendi epic'i; Home gruplaması, Pano ve widget satırı
  hiyerarşiyi bilmiyor, yani "bir ekran" değil bir tur iş.
- `tasks.sort_order` (**elle sıralama**) — sıralamada kullanılıyor, sürükleme yok.
  **Park:** kaydırma jesti şimdi silme; aynı satırda ikinci bir yatay/dikey
  sürükleme jesti çakışma riski (D6'nın Pano dersi) — birlikte tasarlanmalı.
- `tasks.color_rgb` (**görev rengi**) — widget'ta proje rengi yoksa yedek olarak
  kullanılıyor, kullanıcı seçemiyor. **Park:** proje rengi zaten satırda; ikinci
  bir renk kanalı G5'i (renk tek başına anlam taşımaz) zorlaştırır.
- `tasks.repeat_rule` (**tekrarlayan görev**) — BLUEPRINT §4.3 bunu bir görev tipi
  olarak sayıyor, kolon boş. **Park:** en büyük eksik özellik; alarm planlayıcısı
  ve takvim aynası tekrar üretimini bilmiyor → kendi epic'i.
- `estimated_minutes` / `actual_minutes` / `tasks.start_at` /
  `requires_acknowledgement` / `projects.icon` / `projects.start_at|due_at` —
  **park:** ürün kararı verilmemiş alanlar. Kural (DESIGN §22 R1) bundan sonra
  bunların kendiliğinden birikmesini engelliyor.

**Yöntem kararı (kalıcı):** DESIGN **§22** yazıldı — "şemada duran alan, store'daki
metot veya sunucudaki uç, bir insan ona dokunamıyorsa özellik DEĞİLDİR"; her task
artık yüzeyini adıyla yazar (R1) ve CRUD bir matris olarak denetlenir (R2).

**DoD met 2026-07-29:** matris yukarıda; her ❌/⚠️ için karar yazılı; park kuyruğu
güncel; DESIGN §22 + BLUEPRINT §12.14 bağlayıcı metin; STATE özeti.
_Bu task bilinçli olarak kod değiştirmedi — çıktısı karardır._

**Epic 17 DoD:** her task kendi testi + `check:i18n` + kontrast (FAILURES: 0) +
`analyze` yeşiliyle kapanır; epic sonunda app + API tam süit + `check:no-ts`,
CHANGELOG + STATE + README/ROADMAP dokunuşları (silme, tamamlananlar, widget sayacı,
derin bağlantılar), **OPH-188 cihaz matrisi STATE'e işlenmiş** → **v0.6.0**.
186 drift migration'ı içerir → append-only + `from >=` guard'ı zorunlu; 184 paket
seçerse ADR-0017, 189 ADR-0016 kabul edilmiş olmalı; 194 DESIGN §4'ü değiştirdiği
için ADR-0005/0012 çapraz referansları güncellenir.

---

## Epic 18 — Hızlı Erişim: kenar çubuğu bölümü + yüzen düğme (Phase 12, v0.7.0)

_(Doğdu 2026-07-29 — istek turu 11, madde #1. Mahir'in cümlesi: "Web'de sol menüye hızlı
erişim sekmesi… Notion'daki sol menü gibi; mobilde iPhone'un o beyaz noktası gibi
[AssistiveTouch] sürüklenip bırakılan, tıklayınca aynı listeyi açan bir düğme. Kısayollar,
dosyalar, dış linkler — her şey eklenebilecek, renk ve emoji verilebilecek."
Bağlayıcı metinler: BLUEPRINT **§4.12** (varlık) + **§12.15** (yüzeyler), DESIGN **§23**,
**[ADR-0018](adr/0018-quick-links-user-scoped-sync-entity.md)** (kullanıcıya özel senkron
varlık) — üçü de bu turda yazıldı. Sıra bağlayıcı: **196 araştırma/kalibrasyon** →
**197 API** → **198 replika** →
**199 geniş ekran** → **200 yüzen düğme** → **201 ekleme yolları** →
**202 kişiselleştirme** → **203 davranış + kapanış**. Hiçbir task gerçek cihaz istemez;
yüzen düğmenin dokunuş hissi cihazda gözle doğrulanır ama DoD'yi kilitlemez.)_

> **Turun tek cümlesi:** Hızlı Erişim bir "favori yıldızı" değildir — yıldız (proje/not
> pinleri) **listeyi sıralar**, Hızlı Erişim **kişisel bir gezinme rayıdır**: kullanıcının
> kendi seçtiği proje/görev/not/klasör/dosya/dış-link kısayolları, her platformda aynı
> liste, emoji + renk + elle sıra ile. İkisi karışmaz; ikon dili de ayrıdır
> (yıldız `AwTokens.warning`, Hızlı Erişim `bolt` — DESIGN §23 Q2).

**Round'un ürün kararları (kodda doğrulanmış zemin, 2026-07-29):**

| # | Karar | Zemin |
| - | ----- | ----- |
| 1 | Hızlı Erişim **kullanıcıya özeldir**, workspace'e değil | Workspace'ler çok kullanıcıya şema-hazır ([workspace_members](../apps/api/migrations/) — Epic 02); "benim kısayollarım" başka üyeye sızmamalı. Sync bugüne kadar yalnız workspace-kapsamlı varlık taşıdı → **ilk kullanıcı-kapsamlı senkron varlık, ADR-0018** |
| 2 | Geniş ekranda yüzey **NavigationRail'in devamıdır** | Kabuk zaten iki kırılımlı: ≥1160 `extended` rail, altı ikon-only ([home_shell.dart:185](../apps/app/lib/src/screens/home_shell.dart#L185)); telefonda rail yok → üçüncü kırılım **yüzen düğme** |
| 3 | Dahili linkler **rota olarak** saklanmaz, `kind + target_id` olarak saklanır | `alliswell://` çözücüsü yalnız GEZİNİR (ADR-0016); hedefi id ile saklamak yeniden adlandırmaya dayanıklıdır, rota dizesi saklamak değildir |
| 4 | Silinen hedefin kısayolu **sunucuda kaskadla ölür** | Silme motoru alt-ağaç + ek kaskadını zaten aynı transaction'da yapıyor (OPH-184 context'i) — `quick_links` aynı kalıba katılır; arşivli hedef ise **yaşar ve soluk görünür** (arşiv geri dönüşlüdür) |
| 5 | Emoji + renk **kişiselleştirmedir, anlam değildir** | DESIGN G5 (renk tek başına anlam taşımaz) → tür ikonu her zaman erişilebilir; renk yalnız vurgu noktası, proje paleti kalıbıyla ve kontrast ölçümüyle |

### OPH-196 — UX araştırma dosyası + tasarım kalibrasyonu (kod yazmaz) ✅ 2026-07-29

- [x] **Kaynaklı araştırma pası (OPH-168'in NN/g kalıbı):** (a) **yüzen düğme**
      deyimleri — iOS AssistiveTouch (kenara yapışma, boşta yarı gömülme + soluklaşma
      davranışının gerçek süre/oranları), Messenger chat heads (çoklu kenar fiziği),
      Material'ın FAB/overlay kuralları (yüzen kalıcı düğme ile sağ-alt quick-add
      FAB'ının bir arada yaşama kuralı); (b) **kenar çubuğu favorileri** — Notion
      sidebar (Favorites bölümü, hover menü, sürükleyerek sıra), Slack (özel
      bölümler), Things/Todoist (sabit akıllı listeler — bizimkinden farkı).
      Bulgular kısa karşılaştırma tablosuyla bu taskın altına işlenir (kalıcı referans).
- [x] **DESIGN §23 kalibre edilir:** planlama turunda yazılan Q1–Q8 kurallarının
      sayısal varsayılanları (56 px çap, 3 sn boşta gecikmesi, ~%55 soluklaşma,
      %35 fabrika yüksekliği, yarı gömülme miktarı) araştırmayla ya doğrulanır ya
      **§23 içinde** revize edilir — değer başka yerde değişmez (sapma DESIGN'a
      yazılır, AGENTS sert kural 11).
- [x] **ADR-0018 son okuma:** kaskad + kullanıcı-filtresi kararı implementasyon
      gözüyle yeniden okunur; değişiklik gerekirse süpersede kuralıyla yapılır
      (sessiz düzeltme yok).
- [x] **Erişilebilirlik ön kontrolü:** VoiceOver/TalkBack'te sürüklenen overlay
      düğmelerin bilinen davranışları (odak sırası, gizlenen öğenin anonsu)
      araştırılır; OPH-200'ün Semantics planı buna göre netleşir.
- [x] **Park listesi kesinleşir:** Android sistem-geneli overlay (SYSTEM_ALERT_WINDOW —
      ayrı izin, istila edici, ayrı tur), iOS'ta uygulama dışı overlay (OS izin
      vermez — yazılı sınır), kısayol klasörleri/iç içe liste, OG başlık çekme
      (unfurl proxy'ye bağlı), workspace-paylaşımlı ekip listesi, emoji-picker
      paketi — parking-lot'a gerekçeleriyle girer.

**Context:** OPH-195 kalıbında bir karar/araştırma taskıdır — kod değiştirmez. Bağlayıcı
metinler (BLUEPRINT §4.12/§12.15, DESIGN §23, ADR-0018) planlama turunda (2026-07-29)
yazıldı; bu task onları kaynaklı araştırmayla sınar ve sayıları sabitler. Sonraki altı
task o metinlere atıf yapar, yeniden karar VERMEZ.

#### OPH-196 bulguları — yüzen düğme deyimleri (kalıcı referans)

| Ürün | Ne yapıyor | Bizde karşılığı |
| ---- | ---------- | --------------- |
| **iOS AssistiveTouch** ([Apple/AbilityNet](https://mcmw.abilitynet.org.uk/how-to-control-your-device-using-assistivetouch-in-ios-26-on-your-iphone-or-ipad)) | Düğme sürüklenir, ekranın herhangi bir kenarına park eder; **"birkaç saniye" sonra %40 opaklığa soluklaşır** (Ayarlar'da **Idle Opacity** slider'ı, kullanıcı %15–%100 arası seçer). Mahir'in "o beyaz nokta" dediği tam bu. | Q4 **%55 → %40** olarak revize edildi (platformun kendi varsayılanı). 3 sn gecikme "birkaç saniye"nin içinde kalır ve ölçülebilir bir sayıdır → korundu. Kullanıcıya opaklık slider'ı **verilmiyor** (tek anahtar yeter, ayar enflasyonu yok) — istenirse park kuyruğundan gelir. |
| **Messenger chat heads** ([ishadeed teardown](https://ishadeed.com/article/facebook-messenger-chat-component/), [brutella/chatheads](https://github.com/brutella/chatheads)) | Bırakınca **en yakın sol/sağ kenara yaylanarak** yapışır; ekranın **bir kısmı dışarıda** kalır ki alanı kaplamasın; kapatma için alttaki X hedefine sürüklenir. | Kenar yapışma + yarı gömülme birebir alındı (Q4/Q4a). **X kapatma hedefi ALINMADI**: bizim düğmemiz sohbet değil kalıcı bir gezinme rayı; kapatma yolu Ayarlar anahtarıdır (Q5) — kazara sürükleyip yok etmek geri alınamaz bir kayıp hissi verirdi. Android 11'de Messenger'ın kendisi de chat head'i **Bubbles API**'sine taşıdı; sistem-geneli overlay ayrı bir dünya (park). |
| **Material 3 FAB** ([m3.material.io](https://m3.material.io/components/floating-action-button/guidelines)) | "Ekran başına **tek** FAB önerilir" — FAB ekranın **en önemli tek eylemini** temsil eder. | Hızlı erişim düğmesi bir FAB **değildir** (eylem değil gezinme) → Q4c yazıldı: sağ-alt quick-add FAB'ı yerinde kalır, bubble karşı tarafta yaşar, modal açıkken ikisi birden görünmez. |
| **Notion sidebar Favorites** ([Notion Help](https://www.notion.com/help/navigate-with-the-sidebar)) | Sayfanın üstündeki ⭐ ile eklenir/çıkarılır; bölüm başlığına tıklayınca **katlanır**; içindeki sayfalar **sürüklenerek sıralanır**; ad/emoji **sayfanın kendisinden** gelir — kısayola özel değildir. | Toggle + katlama + sürükleme aynen (Q1, OPH-199). **Ayrıldığımız yer:** bizde ad/emoji/renk **kısayola aittir** (BLUEPRINT §4.12) — hedefin adı değişince kısayol adı değişmez, satır farkı gösterir ve tek dokunuşla eşitlenir. Gerekçe: liste proje/görev/not/dosya/link karışımı; hedef adları uzun ve teknik olabiliyor. |
| **Slack özel bölümler** ([Slack Help](https://slack.com/help/articles/360043207674-Organize-your-sidebar-with-custom-sections)) | Bölümler **yalnız kullanıcıya görünür** ("won't affect what your coworkers see"), emoji verilebilir, katlanır; sayı sınırı yok ama pratik öneri 3–5. | ADR-0018'in kullanıcı-kapsamlılığını doğrular (aynı workspace, kişisel liste). Bizde tek bölüm var; **kısayol klasörleri park** — 50'lik tek liste için ikinci bir hiyerarşi seviyesi karmaşa katardı (Slack'in kendi önerisi de "az bölüm"). |
| **Things/Todoist sabit listeler** | Kenar çubuğu **ürünün tanımladığı** akıllı listelerdir (Bugün/Yaklaşan/Filtreler); kullanıcı yeniden sıralayabilir ama karışık-varlık kısayolu ekleyemez. | Bizim yüzeyimizin **farkı** budur: gezinme hedefleri zaten `AppSection` destination'ları; Hızlı Erişim onların altında, tamamen kullanıcı-derlemesi bir bölümdür ve **destination değildir** (seçili sekme state'i bozulmaz). |

#### OPH-196 bulguları — erişilebilirlik

- **Sürükleme tek yol olamaz.** Ekran okuyucu kullanıcısı sürüklemeyi nişanlayamaz; literatürün
  standart cevabı **paralel yol**: satır başına "Yukarı taşı / Aşağı taşı" eylemleri + yeni
  konumun canlı bölge ile duyurulması ([Smashing: Dragon Drop](https://www.smashingmagazine.com/2018/01/dragon-drop-accessible-list-reordering/),
  [React Spectrum: Taming the dragon](https://react-spectrum.adobe.com/blog/drag-and-drop.html)).
  → **DESIGN §23 Q9** yazıldı; OPH-199/200 her iki yolu da taşır (`quick.moveUp`/`quick.moveDown`).
- **Yüzen düğmenin etiketi.** FAB'ların %93'ünün içerik açıklaması yok (denetim bulgusu) — bizim
  düğme `Semantics(button: true, label: quick.title)` taşır; sürükleme **erişilebilir bir gereklilik
  değildir** (konum bir tercihtir, işlev panelin kendisidir), bu yüzden ekran okuyucuda düğme tek
  odak durağıdır ve tüm eylemler panelin menülerinde tekrar sunulur.
- **Odak sırası:** overlay Navigator'ın üstünde yaşadığı için varsayılan gezinme sırasında en sona
  düşer; `accessibilityTraversal*` benzeri müdahaleler "yalnız zorunluysa" öneriliyor → müdahale yok.

### OPH-197 — API: `quick_links` migration + CRUD + sync varlığı ✅ 2026-07-29

- [x] Migration `YYYYMMDDHHMMSS_create_quick_links.js` — §4.12 şeması + indeksler:
      `(workspace_id, user_id, deleted_at)` liste sorgusu, tekillik indeksleri,
      `(workspace_id, kind, target_id)` kaskad araması için.
- [x] `apps/api/src/routes/quick-links.js`: `GET /quick-links` (kendi satırları,
      `sort_order` sıralı), `POST` (limit + tekillik + kind/url tutarlılık doğrulaması;
      hedefin workspace'te VAR ve silinmemiş olduğu doğrulanır — başka workspace'in
      id'si 404), `PATCH /:id` (title/emoji/color), `DELETE /:id` (soft),
      `PUT /quick-links/order` (tam sıralı id listesi alır, tek transaction'da
      `sort_order = index*1024` yazar — kısmi liste 422). Hepsi Ajv şemalı, hepsi
      `recordSyncWrite` ile revision damgalı, hata kodları makine-okur
      (`QUICK_LINK_LIMIT`, `QUICK_LINK_DUPLICATE`, `QUICK_LINK_TARGET_NOT_FOUND`,
      `QUICK_LINK_NOT_YOURS`).
- [x] **Sync:** push `quick_link` mutasyonlarını kabul eder (create/update/delete +
      order; `clientMutationId` idempotensi aynen); pull `quick_link` satırlarını
      **yalnız istekteki kullanıcı için** döndürür (ADR-0018) — filtre tek yerde,
      pull handler'ın varlık tablosunda.
- [x] **Kaskad:** proje/görev/not/klasör/dosya silme yollarının HER BİRİNE aynı
      transaction içinde `quick_links` temizliği girer (görev alt-ağacı dahil —
      alt görevin kısayolu da ölür); temizlik `recordSyncWrite` ile duyurulur ki
      diğer cihazların paneli kendini düzeltsin. Arşiv **dokunmaz** (karar 4).
- [x] Testler — unit: şema doğrulama uçları, limit, tekillik, sahiplik (başka
      kullanıcının id'sine PATCH → 404/403), order ucunun kısmi liste reddi;
      integration: iki kullanıcılı workspace'te pull izolasyonu (A'nın kısayolu
      B'nin pull'una ASLA inmez — ADR-0018'in birebir testi), hedef silme kaskadının
      revision yayını, idempotent push tekrarı.

**OPH-197 uygulama notları (kodda karara bağlananlar):** (1) uçlar
`/workspaces/:id/quick-links` altında toplandı (kardeş koleksiyonlarla aynı —
çıplak `GET /quick-links` bir workspace adlandıramıyor); (2) **kod ailesi
400 biçim · 404 sana görünmez · 409 tekillik · 422 iş kuralı**; repodaki ilk 422'ler
`QUICK_LINK_LIMIT` ve `QUICK_LINK_ORDER_INCOMPLETE` — gövde şema olarak geçerli,
iş kuralı reddediyor; (3) Fastify'ın Ajv'si bilinmeyen gövde anahtarlarını
**reddetmiyor, SİLİYOR** → hedefi değiştirme denemesi handler'a boş patch olarak
geliyordu; sessiz 200 yerine `QUICK_LINK_EMPTY_PATCH` (400); (4) `ownershipOk`
artık **kod dizesi** dönebiliyor (`checkOwnership`) — eski `!(await …)` bir string'i
sessizce geçiriyordu ve `applyDelete` `guard`'ı hiç çağırmadığı için sahiplik
oraya konmak zorundaydı; `duplicateCode` de sabit `'tag'` kontrolünün yerini aldı;
(5) sıralama **yeni fiil değil**: `update` + virtual `orderedIds` (`col:'sort_order'`),
anchor `orderedIds.first`, N satır → N revision, `client_mutations` anchor'ı kaydeder;
(6) pull filtresi iki katmanlı (loader + `invisible` düşürmesi) ve `quick_link`
**yalnız soft** siliniyor, silerken `target_id` NULL'lanıyor (slot serbest kalsın);
(7) dosya kısayolları `softDeleteReadyFile` boğazından, klasör kısayolları
`deleteFolderSubtree`'den kaskad ediyor → REST ve push tek yoldan.

### OPH-198 — App: drift replikası + `QuickAccessStore` ✅ 2026-07-29

- [x] drift **v13**: `quick_links` tablosu (append-only migration + `from >=` guard —
      OPH-167/186 dersi; `onCreate`'e de eklenir, OPH-186'nın indeks dersi).
- [x] `features/quick_access/data/quick_access_store.dart` — Epic 06 deseninin aynısı:
      `watchMine(workspaceId)` (sort_order sıralı, deleted filtreli), `add(kind, …)`,
      `rename`, `setEmoji`, `setColor`, `reorder(orderedIds)`, `remove` — hepsi
      optimistic satır + outbox mutasyonu tek transaction, sonra engine dürtme.
      `reorder` outbox'ta TEK mutasyon taşır (id listesi) — 50 ayrı update değil.
- [x] **Hedef çözümü replikadan:** panelde her satır hedefinin canlı durumunu bilir —
      `watchMine` hedef tablolarla LEFT JOIN'lenir (proje adı/rengi, görev başlığı +
      tamamlanmışlık, not başlığı, klasör adı, dosya adı; url satırı kendi başına).
      Hedef replikada yoksa satır **"kırık"** işaretlenir (sunucu kaskadı birazdan
      düşürecektir; OPH-203 davranışı). JOIN'li izlemede `LIMIT` tuzağı yok — liste
      ≤50 ve LIMIT kullanılmıyor (OPH-186'nın dersi not düşüldü).
- [x] Testler: store CRUD + outbox gövdeleri (push'a giden mutasyon şekli), reorder'ın
      tek mutasyonu, iki workspace'te izolasyon, kırık hedef bayrağı, `sync_overrides`
      ile pump edilen widget testlerinin hazırlığı.

**OPH-198 uygulama notları:** (1) `userId` **wire'a girdi** — sunucu zaten yalnız
sahibinin satırlarını gönderiyor ama replika oturum kapanışını hayatta kalıyor, bu yüzden
`watchMine` yerelde de süzüyor (ortak cihaz); (2) `QuickAccessRow` beş LEFT JOIN'li tek
`customSelect`'ten geliyor — `readsFrom` seti eksik olsaydı hedef yeniden adlandığında
rail **sessizce donardı**, testi var; (3) `add` çift eklemede yeni satır değil MEVCUT id'yi
döndürüyor (menü toggle'ı için doğru davranış) ve 50 sınırında `null` — çevrimdışı da
dürüst; (4) `reorder` tek mutasyon: anchor `orderedIds.first`, patch `{'orderedIds': [...]}`
(sunucunun virtual alanı); (5) `forgetQuickLinksFor` **serbest fonksiyon** — görev/proje/not/
klasör store'ları kendi silme transaction'larından çağırıyor, Quick Access'e bağımlılık
almadan; **outbox mutasyonu YOK** çünkü sunucu kaskadı zaten duyuruyor ve ikinci bir delete
"kullanıcı kaldırdı" yalanı olurdu; (6) dosya silme istemcide REST + pull olduğu için yerel
kaskad gerektirmiyor (satır pull'da düşüyor).

### OPH-199 — Geniş ekran: rail'de "Hızlı erişim" bölümü (web/masaüstü) ✅ 2026-07-29

- [x] **Extended rail (≥1160):** bölüm başlığı ("Hızlı erişim" + `bolt` ikonu + "+"
      düğmesi), altında kısayol satırları — emoji (yoksa tür ikonu) + ad + renk
      noktası (varsa) + dış-link glifi (`kind=url`, G5 gereği renkten bağımsız işaret).
      Tıkla → gezin (OPH-203 tablosu). Satır sonu "⋯" menüsü: **Yeniden adlandır ·
      Emoji · Renk · Kaldır** (hover'da belirir AMA klavye odağında da görünür —
      D2 analoğu). Bölüm başlığı tıklayınca katlanır; tercih cihaz-yerel.
- [x] **Dar rail (<1160):** destinations altına `bolt` ikon düğmesi → çıpalı popover
      aynı listeyi açar (menüler dahil). Rail'in seçili-bölüm durumuna KARIŞMAZ
      (kısayol bir destination değildir — go_router sekme state'i bozulmaz).
- [x] **Sürükleyerek sıralama (fare):** `ReorderableListView` kalıbı rail bölümünde;
      bırakınca `store.reorder`. Pano'nun D6 dersi burada geçerli değil (dikey liste,
      yatay pager yok) — yine de test edilir.
- [x] **Boş durum:** tek satır ipucu ("Menülerdeki ⚡ ile proje, not veya link ekleyin"
      üslubunda, `AwEmptyState` değil — rail'de mikro boş durum, DESIGN §23 Q6).
- [x] i18n: `quick.title`, `quick.add`, `quick.addLink`, `quick.rename`, `quick.emoji`,
      `quick.color`, `quick.remove`, `quick.empty`, `quick.externalHint` (en+tr).
- [x] Testler: extended/dar kırılımda doğru yüzey; satır tıklaması doğru rotaya
      gidiyor; menü eylemleri store'a düşüyor; sıralama mutasyonu; boş durum;
      kontrast (renk noktası + soluk satır çiftleri iki temada).

**OPH-199 uygulama notları:** (1) kırılımlar `kAwWideBreakpoint`/`kAwExtendedRailBreakpoint`
token'ı oldu (dört çıplak sayı gitti); (2) bölüm `NavigationRail.trailing`'te + `scrollable: true`
+ genişliği sabitlenmiş `SizedBox` — destination olsaydı `selectedIndex` ile `AppSection.values`
eşlemesi bozulurdu, `SizedBox` olmasaydı uzun bir kısayol adı tüm rail'i genişletirdi;
(3) **popover'da iki tuzak koddan öğrenildi:** `MenuAnchor` menüsünün **intrinsic yüksekliğini
ölçüyor** → shrink-wrap viewport bunu cevaplayamıyor (sabit yükseklik verildi) ve iç liste
`PrimaryScrollController`'ı paylaşınca Scrollbar assert'i patlıyor (`primary: false`);
(4) **gezinme tablosu bu taskta yazıldı** (satır tıklaması olmadan bölüm yarım kalırdı):
`quick_access_navigation.dart` saf `quickDestinationFor` + tek "kirli" `openQuickDestination`;
klasör hedefi için **yeni rota** `/files/folder/:folderId` (+ `FilesScreen.initialFolderId`,
breadcrumb replikadan kuruluyor) ve dosya hedefi rota değil `showFileActionsSheet`.
OPH-203 bu tabloyu **devralır**: kırık/arşivli/çevrimdışı davranışlarının testleri ve
sürüm dokunuşları orada; (5) menüde **emoji/renk maddeleri görünüyor ama seçiciler
OPH-202'de** geliyor (menü tek yerde tanımlansın diye); (6) DESIGN §23 Q9 gereği her satırda
"yukarı/aşağı taşı" var — sürükleme yalnız hızlandırıcı.

### OPH-200 — Telefon: yüzen düğme (bubble) + panel ✅ 2026-07-29

- [x] **Yerleşim:** kabuğun kök `Overlay`'inde, Navigator'ın ÜSTÜNDE ama dialog/sheet
      açıkken **gizlenir** (modal rota dinleyicisi) — panel/diyalogla çakışan bir
      yüzen düğme iki kez dokunulmaz hedef üretir. Auth/onboarding rotalarında yok.
- [x] **Fizik (DESIGN §23 Q4):** parmakla serbest sürüklenir; bırakınca en yakın
      **dikey kenara** yaylanarak yapışır (`AwMotion` token'ları); konum
      (kenar + yükseklik oranı) cihaz-yerel kalıcıdır (pano tercihi kalıbı);
      3 sn boşta → kenara yarı gömülür + soluklaşır (AssistiveTouch davranışı),
      dokununca tam geri gelir. Safe area + klavye inset'ine saygı; sağ-alt FAB
      bölgesine VARSAYILAN konum verilmez (fabrika konumu: sağ kenar, %35 yükseklik).
- [x] **Görünürlük kuralı (DESIGN §23 Q5):** düğme yalnız liste doluyken VE ayar
      açıkken görünür. Ayarlar → "Yüzen hızlı erişim düğmesi" (fabrika: açık).
      Ayar kapalıyken telefonda giriş yolu **Home app bar'ındaki `bolt` ikonu**dur —
      özellik jeste/overlay'e mahkûm edilmez (D2). İlk kısayol eklendiğinde tek
      seferlik tooltip düğmeyi tanıtır.
- [x] **Panel:** dokun → bottom sheet; aynı liste, aynı satır menüleri (long-press),
      başlıkta "+" (dış link ekle) ve "Düzenle" (sıralama modu — sürükleme kulpu
      `ReorderableListView`; erişilebilirlik yolu: kulp yerine yukarı/aşağı taşı
      menü eylemleri). Satıra dokun → panel kapanır + gezinilir.
- [x] **Erişilebilirlik:** düğme `Semantics(button, label: quick.title)`; sürükleme
      TalkBack/VoiceOver'da zorunlu değil (konum bir tercihtir, işlev panelin
      kendisidir); panel tüm eylemleri menüyle sunar. Tap hedefi ≥ 44 px.
- [x] Testler: sürükle-bırak yapışma matematiği saf fonksiyon olarak (kenar seçimi +
      oran sıkıştırma); konum kalıcılığı; modal açılınca gizlenme; ayar kapalıyken
      app bar girişinin belirmesi; boş listede düğmenin yokluğu; panelden gezinme.

**OPH-200 uygulama notları:** (1) düğme `MaterialApp.builder`'da (`QuickAccessBubbleHost`),
kapılar ucuzdan pahalıya: genişlik → oturum → ayar → tur/alarm → **ancak sonra** liste akışı;
(2) **rota dinleme DENENDİ ve geri alındı** — `MaterialApp.builder` içinden router delegate'i
dinlemek router'ın kendi build'i sırasında rebuild demek (`'!_dirty': is not true`) ve
`GoRouter.state` ilk karede boş eşleşme listesiyle `Bad state: No element` atıyor; auth
ekranlarının tanımı zaten "oturum yok" olduğu için kapı **oturuma** bağlandı; (3) modal
gizlemesi `AwModalRouteObserver` (`PopupRoute` sayar, `ValueNotifier` — `didPush` build
sırasında ateşleyebilir); testte hem `showDialog` (root navigator) hem panelin kendisi
kanıtlanıyor; (4) panel `awRootNavigatorKey.currentContext` ile açılıyor (builder katmanının
`Navigator` atası yok) ve aynı sebeple tanıtım ipucu `Tooltip` DEĞİL kendi balonu;
(5) yarı gömülme `AnimatedSlide` + `AnimatedOpacity` ile **yalnız boya**, kutu 56 px
(testte `getSize` ile doğrulanıyor); (6) sürükleme testi `startGesture`+`moveBy` ister —
tek `drag()` çağrısı pan tanıyıcıyı ara karesiz bırakıyor; (7) yan etki: Ayarlar listesi bir
satır uzadı ve `completed_screen_test`in yardımcı fonksiyonu ekran dışında kalan satıra
dokunuyordu → `scrollUntilVisible` eklendi (test bakımı, davranış değişmedi).

### OPH-201 — Ekleme yolları: her varlık menüsünde "Hızlı erişime ekle" + dış link ✅ 2026-07-29

- [x] **Menü girişleri (toggle):** proje listesi menüsü + proje detay app bar menüsü;
      not listesi/ızgara menüleri + not editörü menüsü; görev detay menüsü (görev
      SATIRINA yeni jest girmez — kaydırma silmenin, D6 disiplini); Dosyalar'da klasör
      ve dosya eylem sayfaları. Ekliyse metin **"Hızlı erişimden kaldır"** olur
      (durum store'dan okunur) — ikinci kez ekleme diye bir yol yok.
- [x] **Dış link dialog'u:** panel/rail "+" → URL alanı (http/https doğrulama, şemasız
      girişe `https://` öneki), ad alanı (boşsa host adı önerilir), emoji + renk
      opsiyonel. OG başlık çekme YOK (v1 — park, unfurl proxy'ye bağlı).
- [x] **Sınır davranışı:** 50'de ekleme reddi dürüst snackbar'la ("50 kısayol sınırı —
      önce birini kaldırın" üslubu); sunucu 422'si aynı mesaja çözülür.
- [x] i18n: `quick.addTo`, `quick.removeFrom`, `quick.linkUrl`, `quick.linkTitle`,
      `quick.limitReached`, `quick.added` (en+tr).
- [x] Testler: her menüde toggle'ın iki yönü (ekle → kaldır); dış link doğrulaması
      (geçersiz şema reddi, öneki tamamlama); limit reddi; eklenen satırın panelde
      belirmesi (uçtan uca store akışı).

**OPH-201 uygulama notları:** (1) tek eylem `toggleQuickAccess` + iki kabuk
(`quickAccessMenuItem`, `quickAccessSheetTile`) — etiket ile davranış ayrı yerlerde
yaşarsa çelişir; (2) dosya sheet'ine madde **`showFileActionsSheet`in İÇİNE** kondu →
beş çağıran (Klasörlerim, Kaynaklar, proje sekmeleri, not medyası, varsayılan dokunuş)
tek düzenlemeyle kazandı; (3) not editörü/görev detayı/proje detayına mevcut ikonlar
korunarak **tek maddelik overflow** eklendi (app bar zaten telefonda sınırda; mevcut
testler kıpırdamadı); (4) **testin bulduğu üç gerçek hata:** dış link dialog'u
controller'larını `showDialog` döndükten hemen sonra dispose ediyordu — rota hâlâ
animasyonla kapanırken alanlar yeniden build ediliyor ("A TextEditingController was used
after being disposed") → dialog artık kendi controller'larının sahibi; `quickLinkUri`
şemalı girdiye `https://` ekliyordu (`mailto:a@b.c` → `https://mailto:a@b.c` kabul
ediliyordu) → şema varsa olduğu gibi değerlendirilir; ve FakeApi'nin id üretimi
`'QCK1'.padRight(26,'0')` ile `'QCK10'.padRight(26,'0')`i AYNI dizeye çeviriyordu, bu
yüzden 50 tohumlanan satırın yalnız 46'sı replikaya iniyordu (limit testi yakaladı) →
`padLeft`.

### OPH-202 — Kişiselleştirme: emoji, renk, ad ✅ 2026-07-29

- [x] **Emoji seçici (DESIGN §23 Q7):** bottom sheet — "Son kullanılanlar" (cihaz-yerel,
      ≤16) + ~48'lik kürasyonlu ızgara (iş/etiket temaları) + **serbest metin alanı**
      (sistem klavyesinin emoji sayfası asıl yol; masaüstünde de bu alan çalışır).
      Tek grafem doğrulaması (API `emoji` ≤16 bayt utf8mb4 zaten sınırlar); "Kaldır"
      seçeneği tür ikonuna döndürür. Paket YOK — tam emoji-picker bağımlılığı park
      (ADR isterdi, gerekçesiz).
- [x] **Renk:** proje renk seçicisinin aynı swatch kalıbı (aynı palet, aynı bileşen
      yeniden kullanılır — yeni palet İCAT EDİLMEZ) + "renk yok" seçeneği. Renk yalnız
      satırdaki nokta ve panel vurgusudur; metin rengine ASLA girmez (kontrast tabanı
      metinden bağımsız kalır, DESIGN §23 Q8; nokta ≥3:1 iki temada `contrast.py`
      çiftlerine girer).
- [x] **Ad:** satır menüsünden dialog, 200 karakter, boş bırakılırsa hedef adına döner
      (url'de host). Hedef yeniden adlanınca kısayol adı DEĞİŞMEZ; satır alt metni
      hedefin güncel adını gösterir (fark varsa) — kullanıcı isterse "hedef adını al"
      menü eylemiyle eşitler.
- [x] Testler: grafem doğrulaması (çok karakter reddi, ZWJ dizisi kabulü); son
      kullanılanlar sırası; renk seçiminin store'a düşüşü; ad boşaltmanın hedefe
      dönüşü; "hedef adını al" eşitlemesi.

**OPH-202 uygulama notları:** (1) `_ColorSwatchDot` → `widgets/color_swatch_dot.dart`
(`AwColorSwatchDot`); proje sheet'i artık oradan import ediyor — bir özelliğin başka bir
özelliğin SHEET dosyasından widget alması ev düzenine aykırıydı; (2) kısayol renginde
**yalnız 10'luk palet** var, `_ColorGridDialog`ın sınırsız seti bilinçle dışarıda
(DESIGN §23 Q8a: sınırsız fille halka bile kontrastı garanti edemez) — park listesinde;
(3) emoji kuralı "**tek grafem**", "emoji mi?" değil: paketsiz emoji sınıflandırması
bayrakları/ZWJ ailelerini/keycap'leri yanlışlıkla reddeder, ve ikonuna "A" yazmak isteyen
kullanıcı hata yapmıyor — testte açıkça yazıldı; (4) **OPH-199'da yazılan yeniden
adlandırma dialog'unda aynı dispose hatası bulundu** (controller `showDialog` döner dönmez
dispose ediliyordu, rota kapanma animasyonundayken alan rebuild oluyor) → dialog kendi
controller'ının sahibi; (5) hedef yeniden adlandığında satırın canlı güncellenmesi store
testinde, satırın NE YAPTIĞI (kendi adını korur + farkı gösterir + tek dokunuşla eşitler)
widget testinde — periyodik pull testlerde kapalı olduğu için ikisi ayrı yerde kanıtlanıyor.

### OPH-203 — Davranış + kapanış: gezinme, kırık/arşivli hedef, sürüm dokunuşları ✅ 2026-07-29

- [x] **Gezinme tablosu (tek yerde, test edilir saf fonksiyon):** project →
      `/projects/:id`; task → görev detayı; note → not editörü; folder → Dosyalar
      (klasör açık); file → dosya eylem sayfası; url → `url_launcher` dış tarayıcı
      (uygulama içi webview YOK — karar yazılı; OPH-164'ün linkify davranışıyla aynı).
      Panelden gezinme paneli kapatır; rail'den gezinme bölüm state'ini bozmaz.
- [x] **Kırık hedef:** hedef replikada yoksa satır soluk + "kaynak silinmiş" alt metni;
      dokununca gezinme yerine kaldırma teklifi (snackbar + Kaldır). Sunucu kaskadı
      (OPH-197) satırı zaten düşürür — bu yalnız yarış penceresinin dürüst hâlidir.
- [x] **Arşivli hedef:** satır soluk ama TIKLANIR (arşiv geri dönüşlü); proje detayı
      kendi arşiv banner'ını zaten gösterir — ekstra açıklama eklenmez.
- [x] **Çevrimdışı:** tüm CRUD outbox'la çalışır (198'in doğası); dış link açma
      çevrimdışıysa OS'nin kendi hatasına bırakılmaz — "çevrimdışı" snackbar'ı.
- [x] **Sürüm dokunuşları:** README özellik listesine bir satır + ROADMAP Phase 12
      işareti; BLUEPRINT §12.15 "uygulandı" notları; STATE + CHANGELOG.
- [x] Testler: gezinme tablosu (kind × hedef → rota) tablo-testli; kırık hedef akışı;
      arşivli hedef gezinmesi; çevrimdışı dış link mesajı; **epic kapanış süiti** —
      app + API tam süit, `check:i18n`, kontrast FAILURES: 0, `lint`/`format:check`/
      `check:no-ts`.

**OPH-203 uygulama notları:** (1) gezinme tablosu OPH-199'da yazılmıştı; burada tablo-testi
(6 kind × {canlı, arşivli, kırık}) + kırık/arşivli/çevrimdışı akış testleri geldi;
(2) **`url_launcher`'ın `bool` dönüşü uygulamada İLK KEZ kontrol ediliyor** — çevrimdışıda
`false` dönüyor ve OS hiçbir şey söylemiyordu → `quick.offlineLink`; (3) `deep_link.dart`in
"Files has no per-file route yet" yorumu artık KARARI anlatıyor (dosyanın "sayfası" bu
uygulamada eylem sheet'idir); (4) **FakeApi push'ta `quick_link`i hiç uygulamıyordu** →
silinen satır bir sonraki pull'da geri geliyordu; kırık-hedef testi yakaladı, fake artık
create/update/delete + `orderedIds` sıralamasını uyguluyor; (5) sürüm dört kaynakta
**0.7.0** (pubspec `0.7.0+8`, `kAppVersion`, iki package.json).

**Epic 18 DoD ✅ (2026-07-29):** sekiz taskın sekizi kendi testleriyle kapandı;
OPH-196'nın üç dokümanı kalibre edildi (DESIGN §23 Q4/Q4a/Q4b/Q4c/Q8a/Q9 revizyonlarıyla);
drift **v13** append-only; iki kullanıcılı pull izolasyon testi gerçek MySQL'de yeşil;
üç yüzey de gerçek (DESIGN §22 R1: rail bölümü, dar-rail popover'ı, telefon bubble+panel —
üçü de tek store'u aynı sırayla okuyor); park listesi güncel. **App 603/603, API 323 unit +
43 entegrasyon**, analyze + i18n + kontrast (FAILURES: 0) + lint/format/no-ts temiz →
**v0.7.0**. Cihaz kuyruğu bu epic'e HİÇBİR şey eklemedi (yüzen düğmenin dokunuş hissi
gerçek telefonda göze bakılır ama DoD'yi kilitlemiyordu).

---

## Epic 19 — Feedback round 12: tekrarlı görevler, takvim her zaman, akış düzeltmeleri (Phase 13, v0.8.0) ✅ KOD TAMAM (2026-07-29)

_(Doğdu 2026-07-29 — Mahir'in 6 maddelik listesi; round 11'in aynı günü. Kullanıcının
sıralamasıyla araya girdi: **bu epic Epic 18'den sonra, yapay zekadan (Epic 20) önce
koşar.** İki büyük özellik (tekrarlı görevler + takvim aynasının seçeneksizleşmesi) ve
dört düzeltme. Bağlayıcı metinler: BLUEPRINT **§12.17** (yeni — tekrar) + **§7.1
revize** (takvim) + **§12.2 revize** (geciken×tamamlanan, app bar kontrolleri),
DESIGN **§16/§20 revize** + **§25** (OPH-204 yazar); implementasyonda
**ADR-0020** (tekrar motoru + materyalizasyon) ve **ADR-0021** (takvim aynası v2 +
Google Tasks/EKReminder değerlendirmesi). Sıra bağlayıcı: **204 araştırma** →
**205→208 tekrar hattı** → **209→210 takvim hattı** → **211→213 düzeltmeler** →
**214 alarm (cihaz)**. Cihaz isteyenler: 214 (+210'un gerçek Google/Apple canlı passi).)_

> **Turun tek cümlesi:** iki büyük madde de "eksik özellik" değil **eksik yüzey +
> yanlış varsayılan**: `tasks.repeat_rule` kolonu v1'den beri şemada boş duruyor
> (OPH-195 Bulgu 1'in en büyük parkı) ve takvim aynası **opt-in bir switch'in
> arkasında** — kullanıcının beklentisi tam tersi: "eklenen HER task takvimde
> gözükmeli, bu bir seçenek bile olmamalı."

**Round 12'nin kanıtları — kodda doğrulandı (2026-07-29):**

| # | Madde | Kanıt / kök neden |
| - | ----- | ----------------- |
| 1 | Tekrarlı task yok | `tasks.repeat_rule` şemada var, **hiçbir yüzey yazmıyor/okumuyor** (OPH-195 matrisinde gerekçeli park — "en büyük eksik özellik; alarm planlayıcısı ve takvim aynası tekrar üretimini bilmiyor"); BLUEPRINT §4.3 tekrarı bir görev tipi olarak sayıyor |
| 2 | "Takvimde göster" switch'i | [task_detail_screen.dart:341](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L341) `calendar-mirror-switch` (OPH-081 opt-in) → [mirror.js:16](../apps/api/src/lib/mirror.js#L16) `if (!task.calendar_mirror_enabled) return null`; üstüne §7.1 "scheduled start/end İÇERİYORSA" şartı → bugün **sıradan tarihli görev takvime hiç gitmiyor**. Kullanıcının kuralı: switch ölür, her şey takvimde |
| 3 | Geciken'de tamamlanmış satır | OPH-185 kuralı "kendi grubunda kalır" — dün vadeli görev bugün tamamlanınca grubu **Geciken** olduğu için gün sonuna kadar "Geciken · 1"in altında üstü çizili duruyor. Kullanıcının düzeltmesi: vade geçmişse tamamlanan LİSTEDEN düşer (arşiv zaten OPH-186'da) |
| 4 | Proje düzenle sheet'i menünün altında | [projects_screen.dart:192](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L192) `onSelected` içinden **senkron** `showProjectEditSheet` — menü rotası kapanış animasyonunu bitirmeden modal sheet açılıyor (görsel: sheet menünün ALTINDA; Mahir ekran görüntüsü gönderecek — task bloklamaz) |
| 5 | Liste\|Pano + takvim düğmesi satır yiyor | [home_screen.dart:146](../apps/app/lib/src/features/home/home_screen.dart#L146) `SegmentedButton` satırı + [:363](../apps/app/lib/src/features/home/home_screen.dart#L363) gizle/göster düğmesi; Notlar zaten app bar ikon kalıbını kullanıyor ([notes_screen.dart:56](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L56)) — kullanıcının istediği kalıp repoda mevcut |
| 6 | Ekran açıkken alarm bildirimi | Gözlem (cihaz, 2026-07-29): ekran kapalıyken tam ekran ✓; ekran açıkken heads-up geliyor — X çalışıyor, **saat ikonu (erteleme) hiçbir şey yapmıyor**, bildirime dokununca uygulama açılırken **çöküyor**. Snooze aksiyon id'leri kodda var ([actions.dart:17](../apps/app/lib/src/notifications/actions.dart#L17)) — kablolama/arka plan handler ve launch-payload çökmesi 214'te kök nedenlenir |

### OPH-204 — Tekrar araştırması + kural modeli + materyalizasyon kararı + ADR-0020 (kod yazmaz)

- [x] **≥3 ürün derin incelemesi (Mahir'in şartı):** Google Calendar özel tekrar
      dialog'u (kullanıcının referansı), Todoist (doğal dil + "every!"), TickTick;
      bonus: Apple Reminders/Fantastical. Her biri için ifade gücü tablosu — üç
      senaryo sınıfı özellikle: **(A)** "her ayın 31'i" kısa ayda ne oluyor (kırpma mı
      atlama mı), **(B)** "N. haftanın Salı'sı" / "ayın 2. Salı'sı", **(C)** "ayın
      22'sinden sonraki ilk Pazartesi", "ayın ilk/son Cuma'sı". Bulgular tabloyla bu
      taskın altına işlenir (kalıcı referans; OPH-168'in kaynaklı araştırma kalıbı).
- [x] **Kural modeli kararı (ADR-0020):** RFC 5545 RRULE alt kümesi + RFC 7529
      `SKIP=BACKWARD` (kırpma) semantiği, **yapılandırılmış JSON** olarak saklanır
      (Ajv'lenebilir; ham RRULE dizesi DEĞİL): `freq (daily|weekly|monthly|yearly)`,
      `interval`, `byWeekday[]` (ordinal 1..5 + last), `byMonthDay[]` (-1 = son gün;
      kısa ayda **geriye kırp** — 31 → 30/29/28), `bySetPos`, **`afterDay` + ilk-gün**
      (senaryo C: "22'sinden sonraki ilk Pazartesi"), bitiş (`asla | until | count`).
      A/B/C senaryolarının üçü de bu modelde tek tek ifade edilip test vektörü olur.
- [x] **Materyalizasyon kararı (Mahir bana bıraktı — ADR-0020'ye yazılır):**
      occurrence'lar **gerçek görev satırlarıdır** (`task_series` tablosu +
      `tasks.series_id` + `occurrence_date`); pencere **bugünden +12 ay** (kullanıcının
      kuralı: "12 aydan fazlası eklenmemeli, biri geçince sıradaki eklenir");
      pencereyi **günlük süpürme kaydırır** (BullMQ repeatable — Redis zaten var);
      kural değişince gelecek pencere tek transaction'da yeniden kurulur, geçmişe
      dokunulmaz; **istemci hiç occurrence üretmez** — satırlar normal sync'le akar,
      yani widget/arama/takvim/alarm planlayıcı **bedavaya doğru** (yeni motor yok).
      Seri başına materyalizasyon tavanı (günlük×12 ay ≈ 366 → tavan ~400, aşan
      kural dürüst mesajla reddedilir). Alternatifler ve retleri ADR'de: sanal
      genişletme (her yüzeye — widget dahil — motor gerektirir, local-first'e ters),
      yalnız-sonraki-occurrence (Todoist modeli; "önümüzdeki 12 ay takvimde görünsün"
      isteğini karşılayamaz).
- [x] **Motor iki dilde, tek gerçek:** saf JS (sunucu — üretimin tek kaynağı) + saf
      Dart portu (dialog önizlemesi) + **ortak parite fikstürleri** (ADR-0013 fold
      kalıbı): kırpma, artık yıl, DST sınırı, yıl devri, 5. hafta yokluğu vakaları.
- [x] **DESIGN §25 yazılır:** dialog anatomisi (switch → otomatik açılış, özet satırı +
      Değiştir), kuralın **insan cümlesi** dili (TR/EN), "Sonraki 5" önizleme kuralı,
      erişilebilirlik.
- [x] `tasks.repeat_rule` kolonunun kaderi ADR'de (ölür / `task_series`'e taşınır) —
      ulaşılamayan kolon yalanı (DESIGN §22) bu epic'te biter.

**Bulgular — ifade gücü matrisi (2026-07-29, kaynaklı):**

| Ürün / spec | (A) "her ayın 31'i" kısa ayda | (B) "ayın 2. Salı'sı" | (C) "22'sinden sonraki ilk Pazartesi" | Bitiş |
| --- | --- | --- | --- | --- |
| **RFC 5545 (çıplak)** | **ATLAR** — geçersiz instance "MUST be ignored and MUST NOT be counted as part of the recurrence set" | `BYDAY=2TU`; sayısal önek **yalnız** MONTHLY/YEARLY'de | `BYDAY=MO;BYMONTHDAY=23…29` — BYDAY sınırlayıcıdır ("Limit if BYMONTHDAY is present"); spec'in kendi örneği "first Tuesday after a Monday"yi 7 günlük pencereyle kuruyor | `UNTIL` / `COUNT` |
| **RFC 7529** | `SKIP=BACKWARD` → "changed to the previous (valid) day-of-month" (31 Şub → 28/29). **Ama:** "MUST NOT be present unless RSCALE is present" | — | — | — |
| **Google Calendar** | **ATLAR** (yalnız 31 çeken aylarda); "ayın son günü" UI'da yok, özel RRULE import'u ister; Outlook'un "son gün" kuralı için *"cannot be edited in Google Calendar"* uyarısı veriyor | var ("Monthly on the second Tuesday") | **UI'da yok** | Never / tarihe kadar / N kez |
| **Outlook** | **KIRPAR** — "on the last day of every month" birinci sınıf; Google'a taşınınca yukarıdaki uyarı çıkıyor | var | UI'da yok | var |
| **Todoist** | doğal dil; `every last day` birinci sınıf; **31 davranışı dokümante edilmemiş** | `every 3rd fri`, `every last workday` var | **YOK** (yardım sayfası desteklenmeyenleri sayarken bu deseni hiç anmıyor) | `ending aug 3`, `for 3 weeks`, `starting …` |
| **TickTick** | Custom Repeat; günlükte "workday/skip" seçenekleri | var | yok (aylıkta workday/son-iş-günü hâlâ açık kullanıcı talebi) | var |
| **Apple Reminders** | Custom → "On the" ile hafta/gün deseni ("last weekday of each month") | var | yok | var |
| **→ AllisWell (karar)** | **KIRPAR** (Outlook okuması, RFC 7529 semantiği); `byMonthDay:[-1]` = "ayın son günü" birinci sınıf değer | `byWeekday:[{day:'TU',ordinal:2}]` | `byWeekday:[{day:'MO'}] + byMonthDay:[23…29]` — RFC'nin kendi kesişim deyimi, yeni alan yok | `never` / `until` / `count` |

**Turun üç belirleyici bulgusu:**

1. **"Atla" ile "kırp" arasındaki fark bir standart tercihi değil, ürün tercihi.**
   Aynı niyet Google'da Şubat'ı atlıyor, Outlook'ta ayın son gününe çekiliyor. Görev
   yöneticisinde "31'i" demek **ay sonu** demektir (kira, rapor) → kırpma seçildi.
2. **Senaryo C'nin yeni bir alana ihtiyacı yok.** RFC 5545 `BYDAY`i `BYMONTHDAY`in
   sınırlayıcısı yapıyor ve spec'in kendi örneği tam olarak bu deyimi kuruyor →
   motor üç ilkelle (gün kümesi, ordinal'li gün-adı kümesi, kesişim) yetiniyor.
3. **Kırpılmış bir kural Google'a "tekrar eden etkinlik" olarak anlatılamaz** —
   `SKIP` `RSCALE` olmadan yasak ve Google böyle kuralı düzenlemeyi reddediyor.
   Bu, materyalizasyon kararının (occurrence başına tek etkinlik) bağımsız ikinci
   gerekçesi oldu; ADR-0020 §2'de yazılı.

**Kaynaklar:** [RFC 5545 §3.3.10](https://icalendar.org/iCalendar-RFC-5545/3-3-10-recurrence-rule.html) ·
[RFC 7529](https://www.rfc-editor.org/rfc/rfc7529) ·
[Todoist — Introduction to recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV) ·
[TickTick — Set Up Recurring Tasks](https://help.ticktick.com/articles/7055782206349770752) ·
[Google Workspace — Events in Outlook Calendar (31'i/son gün farkı)](https://support.google.com/a/users/answer/156467?hl=en) ·
[Apple — Add dates or locations to reminders](https://support.apple.com/guide/reminders/add-dates-or-locations-to-reminders-remnd4b206fb/mac)

**Kararların yeri:** [ADR-0020](adr/0020-recurring-tasks-and-materialization.md)
(kural JSON'u, kırpma, kesişim, +12 ay materyalizasyon, süpürme sapması,
`repeat_rule`'ın dondurulması) + **DESIGN §25** (switch → dialog, cümle, "Sonraki 5",
kapsam sorusu, erişilebilirlik). Parite fikstürü sözleşmesi ADR-0020 §6'da; dosyanın
kendisi JS tarafında OPH-205'te, Dart tarafında OPH-207'de doğuyor.

**Context:** OPH-195'in en büyük parkı canlanıyor. Mahir: "bu sistem çok önemli,
bastırıyorum bir daha" — maksimum esneklik hedefi; karar netliği bu yüzden koddan önce.

### OPH-205 — API: `task_series` + materyalizasyon motoru + kayan 12 ay penceresi

- [x] Migration: `task_series` (`id, workspace_id, rule JSON, timezone, anchor_at,
      until_at NULL, count NULL, created/updated/deleted_at, revision`) +
      `tasks.series_id` (FK'sız ULID, index) + `tasks.occurrence_date`; seri de
      senkron varlıktır (push-pull — düzenleme dialog'u her cihazda aynı kuralı
      göstermeli).
- [x] Seri CRUD uçları (Ajv şeması OPH-204'ün JSON modeli) + **materyalizasyon tek
      transaction'da**: seri yaratılınca/değişince gelecek pencere üretilir;
      **idempotent** (aynı seri + aynı pencere ikinci kez satır üretmez —
      `(series_id, occurrence_date)` tekilliği).
- [x] **Günlük süpürme:** BullMQ repeatable job — pencereye yeni giren occurrence'ları
      ekler, `recordSyncWrite` ile duyurur; işlem hacmi log'lanır. Sunucusuz self-host
      (compose) için de aynı kuyruk zaten çalışıyor (mevcut sweep emsalleri).
- [x] Davranış kuralları: occurrence tamamlamak seriyi ve kardeşleri ETKİLEMEZ;
      occurrence silme yalnız o satırı siler (seri kapsam sorusu OPH-206'nın işi);
      seri silme = gelecekteki materyalize satırların alt-ağaç tombstone'u (geçmiş +
      tamamlanmışlar kalır — tarih dürüstlüğü).
- [x] Testler (tablo-güdümlü, OPH-204 fikstürleri): 31 → 30/29/28 kırpması; "ayın 2.
      Salı'sı"; "22 sonrası ilk Pazartesi"; "ayın son günü"; DST + yıl sınırı; pencere
      kayması (sahte saat); idempotens; kural değişiminde geçmişe dokunulmadığı;
      revision yayınları.

**Uygulamada üç sapma (2026-07-29, gerekçeleri ADR-0020'de):**

1. **Süpürme BullMQ repeatable DEĞİL** — ev kalıbı `setInterval + unref() +
   env!=='test' + app.decorate('seriesGc')` (`plugins/series-gc.js`; emsal
   account-gc/storage-gc/calendar-sync). `createJobRunner` repeatable API'si
   sunmuyor, self-host Redis'siz de koşmak zorunda, çok replikada güvenlik
   `jobKey` dedupe + idempotens'ten geliyor. Ayar: `SERIES_SWEEP_SEC` (86400).
2. **`until_at`/`count` kolonu yok** — bitiş koşulu `rule.end`in içinde. Dialog
   kuralı bir bütün olarak gidip geliyor; iki yazarı olan tek bir değer er geç
   çelişir. Filtre gerektiren bir sorgu da yok (süpürme canlı serileri yürüyor).
3. **`template` JSON kolonu eklendi** (backlog'da yoktu): occurrence'ın
   damgalandığı alanlar (başlık, proje, öncelik, etiketler, hatırlatma ofseti).
   Alternatif "tohum görevden klonla" idi — tohum silinince seri anlamını
   kaybediyordu.

**Ayrıca eklendi:** `fromTaskId` — switch'in üstünde açıldığı görev, günü
desene DÜŞÜYORSA seri tarafından **sahiplenilir** (`series_id`+`occurrence_date`
yazılır), yoksa dokunulmaz. Bu olmadan kullanıcı "tekrarla" der demez görevinin
yanında bir kopyasını görecekti.

**Doğrulama (2026-07-29):** API 374 unit (yeni: 29 motor + 15 seri + 7 sync) +
47 entegrasyon **gerçek MySQL'de** (JSON gidiş-dönüşü, DATE kolonu, tekil
indeksin kopyayı reddedişi, süpürmenin idempotensi); `db:rollback && db:migrate`
CI sırasıyla yeşil; lint + format + no-ts temiz.

### OPH-206 — Seri düzenleme semantiği: bu / bu ve gelecektekiler / tümü

- [x] **Google modeli, kullanıcının istediği otomatiklikle:** materyalize bir
      occurrence düzenlenince kapsam sorusu — "Yalnız bu" / "**Bu ve gelecektekiler**
      (varsayılan)" / "Tümü". Mahir'in cümlesi ("birinden değiştirilince
      gelecektekilerin hepsini değiştir otomatik olmalı") → varsayılan seçenek budur,
      tek dokunuşla geçer.
- [x] Kapsam mekaniği: "gelecektekiler" **seriyi böler** (eski seri `until` alır, yeni
      seri doğar — Google'ın kalıbı); "tümü" seri metadata'sını günceller, geçmiş
      occurrence'ların tamamlanmışlığına dokunmaz; "yalnız bu" occurrence'ı ayırır
      (detached — seri bağı düşer, satır sıradan görev olur; rozeti kalkar).
- [x] Alan-bazlı istisna yazılır: tek occurrence'ın tarihini sürüklemek/değiştirmek
      varsayılanı "yalnız bu"dur (bir randevuyu kaydırmak seriyi kaydırmak değildir);
      başlık/açıklama/öncelik değişimi varsayılanı "bu ve gelecektekiler"dir.
- [x] API: kapsamlı update ucu (`scope: this|future|all`) tek transaction; app: store
      + kapsam dialog'u; senkron: bölünme iki seri satırı + görev güncellemeleri
      olarak akar.
- [x] Testler: üç kapsamın her biri (satır sayıları + revision'lar); bölünme sonrası
      iki serinin bağımsız süpürülmesi; detached occurrence'ın serbestliği.

**"Yalnız bu" DETACH ETMİYOR — kod bunu düzeltti (2026-07-29):** yukarıdaki plan
occurrence'ı seriden koparıyordu (`series_id = NULL`). Uygulamada bu bir hata:
`(series_id, occurrence_date)` **slot'u** serbest kalır ve kayan pencerenin bir
sonraki süpürmesi aynı güne **ikinci bir satır** üretir — kullanıcı "yalnız bunu
değiştirdim" der, ertesi gün yanında kopyası belirir. Doğru model Google'ın
"değiştirilmiş instance"ı: **satır seride kalır**, `occurrence_date` serinin
slot'unu tutmaya devam eder, `due_at` gerçekten ne zaman olduğunu söyler. Rozet de
kalır (satır GERÇEKTEN o serinin bir occurrence'ı). ADR-0020'nin sonuçlarına
tarihli not olarak işlendi; DESIGN §25 R8 aynı cümleyi taşıyor.

**Tarih düzenlemesinin kapsamı = SAAT (yeni kural, DESIGN §25 R8):** `future`/`all`
kapsamıyla gelen bir `dueAt` günleri değiştirmez (günler kuraldan gelir) — **günün
saatini** taşır: seri anchor'ı ve etkilenen satırlar yeni saate kayar ("bundan sonra
14:00'te olsun"). `this` kapsamında yalnız o satırın `due_at`'i oynar.

**Alan-bazlı varsayılanlar UI'ye ait:** API hangi kapsam geldiyse onu uygular; "tarih
değişimi → yalnız bu, başlık/öncelik → bu ve gelecektekiler" varsayılanı dialog'da
yaşıyor (OPH-207) — sunucuya varsayılan gömmek, ikinci bir istemcinin farklı
davranmasına sessizce izin verirdi.

**Kapsam dialog'u OPH-207'ye taşındı** (app store'u orada doğuyor; store'suz dialog
yazılamaz). Bu taskın app tarafı: yok — sözleşme + motor burada bitti.

**Doğrulama (2026-07-29):** API 385 unit (yeni: 12 kapsam testi — üç kapsamın satır
etkileri, slot'un korunması, bölünmeden sonra iki serinin bağımsız süpürülmesi,
tamamlananın dokunulmazlığı, saat taşıma, sync push'la offline kapsam) + 47 entegrasyon.

### OPH-207 — App: tekrar dialog'u — switch, otomatik açılış, özet + Değiştir

- [x] **Giriş yüzeyi (kullanıcının tarifi birebir):** detaylı ekleme VE düzenleme
      sheet'lerine "Tekrarla" switch'i; switch İLK açıldığında dialog **otomatik**
      açılır; dialog iptal edilirse switch kapanır (yarım kural kalmaz). Kural
      varken satırın altında **özet cümlesi** ("Her ayın son iş günü değil — örn.
      'Her ayın 22'sinden sonraki ilk Pazartesi · bitiş yok'") + sağında **Değiştir**.
- [x] **Dialog:** hızlı preset'ler (her gün / hafta / ay / yıl / hafta içi) +
      **Gelişmiş** bölümü — üç senaryo sınıfı ayrı ayrı kurulabilir: (A) ayın günü
      (kısa ay kırpması açıklama metniyle: "kısa aylarda son güne çekilir"),
      (B) N. hafta + gün (1..5 + "son"), (C) "ayın X'inden sonraki ilk {gün}" ve
      "ayın ilk/son {gün}ü"; bitiş: asla / tarihe kadar / N kez.
- [x] **Canlı önizleme: "Sonraki 5"** — Dart motor portundan hesaplanır (OPH-204
      paritesi); kural her değişiminde güncellenir; kırpma davranışı önizlemede
      GÖRÜNÜR (31 seçiliyken Şubat satırı 28/29 gösterir — kullanıcı sistemi
      bozulmamış görür).
- [x] Kuralın insan cümlesi tek yardımcıdan (TR/EN ayrı üretim — çeviri değil kural
      bazlı cümle kurma; i18n `repeat.*`); erişilebilirlik: dialog tam klavye/okuyucu
      yolu.
- [x] Testler: switch→dialog otomatiği; iptal→switch kapanır; A/B/C kurallarının
      cümleleri (TR+EN snapshot); önizleme kırpma vakası; kural gidiş-dönüşü (dialog →
      JSON → dialog).

**Uygulama notları (2026-07-29):**

- **drift v14** geldi: `TaskSeries` tablosu + `Tasks.seriesId`/`occurrenceDate`
  (`from >= 1` guard'ıyla). `migration_test` v1→v14'ü gerçek SQLite dosyasında
  koşuyor, `user_version` 14.
- **Motor portu paritede:** `core/recurrence.dart` fikstürün 16 vakasını da
  geçiyor — JS ile gün gün aynı (ADR-0020 §6).
- **Cümle motoru** `core/recurrence_text.dart`: TR/EN ayrı kelime sırası, çoğul
  yok (her form ayrı anahtar). Senaryo C **saklanmıyor, TANINIYOR**
  (`awAfterDayOf`) — 7 günlük pencere + tek gün adı → "22. gününden sonraki ilk
  Pazartesi"; `awAfterDayRule` tersini yazıyor.
- **Kapsam dialog'u burada doğdu** (OPH-206'dan taşındı): `showSeriesScopeDialog`,
  varsayılan "bu ve gelecektekiler"; **tarih düzenlemesinde "yalnız bu"**. Detay
  ekranındaki başlık ve vade düzenlemeleri `_applyScoped`'tan geçiyor; sorudan
  vazgeçilirse HİÇBİR ŞEY yazılmıyor.
- **Dialog kök navigator'a açılıyor** (`useRootNavigator: true`) — OPH-212'nin
  dersi burada peşinen uygulandı.
- **Testin bulduğu:** detay sütunu Repeat satırıyla uzayınca `date_input_test`'in
  iki dokunuşu telefon ekranının altına düştü (tap "off-screen") → testler artık
  `ensureVisible` ile kaydırıyor. İkinci bulgu: **cümle uygulamanın diline uyar**,
  `locale` parametresi yalnız tarihi biçimlendirir (i18n cephesi global, ADR-0009)
  — test dili değiştirerek doğruluyor.
- Create sheet'in switch'i **OPH-208'e** kaldı: sheet henüz kaydedilmemiş bir
  görev üzerinde çalışıyor, seri ise `fromTaskId` istiyor — doğru sıra "kaydet →
  seri kur", o da 208'in görev listesi/rozet işiyle aynı dosyalara dokunuyor.

**Doğrulama (2026-07-29):** app **635 test** (22 motor paritesi + 10 tekrar
yüzeyi yeni), `flutter analyze` temiz, `dart format` uygulandı,
`check:i18n` temiz, kontrast **FAILURES: 0**.

### OPH-208 — App: seri görünürlüğü, yüzey etkileri + README tanıtımı

- [x] Satır ve detayda **tekrar rozeti** (↻ + kısa özet tooltip'te); Tamamlananlar'da
      occurrence sıradan satır (zaten OPH-186 sözleşmesi); Pano kartında rozet.
- [x] **Yüzeyler test edilir, varsayılmaz:** takvim noktaları, widget snapshot'ı,
      arama, alarm planlayıcı — occurrence'lar gerçek satır olduğu için çalışmalı;
      her biri için birer doğrulama testi (özellikle widget: 12 aylık pencerede
      bugünün occurrence'ı `openToday`'e sayılır).
- [x] Silme akışları: satırdan kaydırarak silme kapsam sorusuna bağlanır (OPH-184
      jesti + OPH-206 kapsamı); seri detayından "Tekrarı durdur" (gelecekler silinir,
      geçmiş kalır — dürüst metin).
- [x] **README "öve öve" bölümü (Mahir'in isteği):** tekrar sistemi örnekleriyle
      tanıtılır — "her ayın son günü", "ayın 2. Salı'sı", "22'sinden sonraki ilk
      Pazartesi" — ve **değişik senaryolu görev listesinin ekran görüntüsü** (demo
      workspace'te kurulmuş liste). ROADMAP + STORE-LISTING dokunuşları.
- [x] Kapanış: tam süit + `check:i18n` + kontrast + `analyze`.

**Uygulama notları (2026-07-29):**

- **Rozet** satırda (`task_tile.dart`, `repeat-badge-{id}`), tamamlanınca **kalkıyor**
  (§20 C2: biten bir occurrence tekrarlamaz). Pano kartı aynı `TaskTile`ı kullandığı
  için bedava geldi; detayda rozet yerine **kuralın cümlesi** duruyor (daha çok bilgi,
  aynı yer).
- **Silmede kapsam sorusu İKİ seçenekli:** "Yalnız bu" / "Bu ve gelecektekiler".
  **"Tümü" bilinçli olarak YOK** — geçmiş ve tamamlanmış occurrence'lar tarihtir
  (§20 C4 / §25 R7); onları silen bir akış, bu özelliğin asla yapmaması gereken tek
  şeydi. "Bu ve gelecektekiler" seriyi **o occurrence'ın gününden** durduruyor
  (`DELETE /task-series/:id?fromDay=…` — bugünden değil, kullanıcının kaydırdığı
  günden; Mart'tan durdurmak Şubat'ı almamalı).
- **Zaman dilimi artık sunucudan:** istemci IANA adını bilmiyor (cihaz "+03" der),
  bu yüzden `timezone` isteğe bağlı oldu ve sunucu kullanıcının profilinden dolduruyor
  (REST + sync guard). Client tahmini bir kolona yanlış değer yazmıyor.
- Create sheet'in switch'i geldi: **kaydet → seri kur** sırası (`fromTaskId` görevi
  sahiplendiriyor, kopya doğmuyor).

**Yüzey testleri (varsayılmadı, ölçüldü):** widget `openToday` occurrence'ı sayıyor,
widget kovaları occurrence'ı sıradan görev gibi bucketlıyor (+30 ufkunda düşüyor),
ay takvimi noktası düşüyor, Home grubu tarihe göre (seriye göre değil) kuruluyor,
arama fold'u aynı çalışıyor.

**Doğrulama (2026-07-29):** API **386 unit** + 47 entegrasyon, app **641 test**,
analyze + i18n + kontrast (FAILURES: 0) + format + lint temiz.

### OPH-209 — Takvim araştırması: aynanın seçeneksizleşmesi + Google Tasks / Apple Reminders değerlendirmesi + ADR-0021 (kod yazmaz)

- [x] **Mevcut davranışın yazılı dökümü (kanıt üstte):** `calendar_mirror_enabled`
      opt-in + §7.1'in "scheduled/urgent" şartı → hangi görev bugün takvime gidiyor,
      hangisi gitmiyor; switch'in tarihçesi (OPH-081) ve ölümünün etkileri.
- [x] **Senkron todo-app incelemesi (≥3):** Todoist, TickTick, Any.do — Google
      tarafına **event mi yazıyorlar, Google Tasks'a todo mu**; iki yönlü mü; silme/
      tamamlama nasıl yansıyor. Bulgular tabloyla.
- [x] **Doğrudan todo eşlemesi değerlendirmesi (Mahir'in tercihi "destekliyorsa
      birebir öyle"):** **Google Tasks API** (sınırları yazılır — ör. due'nun saat
      hassasiyeti, liste modeli, push bildirimi var mı) ve **Apple EKReminder**
      (EventKit'in Reminders yakası — ayrı izin, cihaz-yerel). Karar + faz planı:
      v1'de ne (event bloğu herkese), v-next'te ne (todo eşlemesi hangi koşulla) —
      ADR-0021'e.
- [x] **Blok kuralı netleşir (planlama varsayılanı):** tarihli görev = görev saatinde
      başlayan **30 dk blok**; blok gece yarısını taşacaksa güne kenetlenir → 23:59
      vadeli (saatsiz) görev **23:29–23:59** olur (Mahir'in verdiği aralık, varsayılan
      saatin sonucu); **tarihsiz görev ekleniş gününe** aynı kuralla girer (Mahir'in
      açık kuralı: "ekleniş tarihi baz alınır"). Tamamlanan görevin bloğunun kaderi
      (kalır+işaretlenir / silinir) araştırmada kararlaştırılıp ADR'ye yazılır.
- [x] **Hacim/kota analizi:** tüm görevlerin aynalanması = mevcut davranışın kat kat
      üstünde Google API çağrısı (backfill + günlük akış); mirror kuyruğunun rate
      limit stratejisi ve büyük workspace senaryosu ADR'de.
- [x] Gizlilik/onam: "tüm görevlerin takvime yazılması" bağlantı ekranının metnine
      girer (kullanıcı Google'a neyin akacağını bilir).

**Kararlar (2026-07-29) — [ADR-0021](adr/0021-calendar-mirror-v2.md):**

**Todo eşlemesi REDDEDİLDİ (kullanıcı kararı bana bırakmıştı), gerekçe kaynaklı:**

| Aday | Belirleyici bulgu | Sonuç |
| --- | --- | --- |
| **Google Tasks** | API referansı: `due` için *"Only date information is recorded; the time portion of the timestamp is discarded"* ve *"It isn't possible to read or write the time that a task is scheduled for using the API."* | **RET.** AllisWell'in HER görevinin bir saati var (varsayılan 23:59, alarmlar o saatte çalıyor, 30 dk blok ondan türüyor). Saati sessizce düşüren bir eşleme, §11 A4'ün yasakladığı yalanın ta kendisi. |
| **Google Tasks (değişiklik bildirimi)** | Calendar/Gmail/Drive'ın watch kanalı var, **Tasks'ın yok** — kendi rehberi yoklamayı söylüyor | Artımlı Calendar hattının yanına yalnız-yoklama ikinci bir hat: daha kayıplı bir temsil için koca bir alt sistem. |
| **Apple EKReminder** | iOS 17'den beri **ayrı izin** (`NSRemindersFullAccessUsageDescription` / `requestFullAccessToReminders`), tamamen **cihaz-yerel** | Sunucunun uzlaştıramayacağı bir yazım; ikinci izin diyaloğu cabası. |

**Yeniden değerlendirme koşulu ADR'de yazılı:** Google Tasks bir gün *saat taşıyabilir*
**ve** değişiklik sinyali verebilirse. O güne kadar event bloğu bir taviz değil, **saati
koruyan tek temsil** — saat de ürünün kendisi.

**Sabitlenen kararlar:** switch ölür (kolon **makine bastırma bayrağı** olarak kalır —
`lib/inbound.js`'in "kullanıcı Google'da sildi" dalının tek kayıt yeri); blok kuralı
`scheduled_*` → 30 dk → gece yarısı kenetlemesi (23:29–23:59) → tarihsiz ekleniş günü;
**tamamlanan görevin bloğu KALIR, başlığı `✓` alır** (iptal/arşiv/silinen hâlâ siliniyor);
backfill penceresi **-30 gün → +12 ay**; **429/Retry-After + eşzamanlılık tavanı
backfill'den ÖNCE** yazılır; onam metni "tüm görevler takvime yazılır" der.

**Kaynaklar:** [Google Tasks API — Tasks resource](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks) ·
[Google Tasks API limits](https://developers.google.com/workspace/tasks/limits) ·
[Apple — EventKit reminders access](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:))

### OPH-210 — Takvim aynası v2: her görev takvimde, hiçbir yerde seçenek yok

- [x] **Switch ölür:** [task_detail_screen.dart:341](../apps/app/lib/src/features/tasks/ui/task_detail_screen.dart#L341)
      satırı ve `task.showInCalendar*` i18n anahtarları kalkar; API
      `calendarMirrorEnabled` alanını kabul etmeye devam eder ama YAZAN yüzey kalmaz
      (kolonun kaderi ADR-0021'de; migration append-only).
- [x] **§7.1 yeni kural (BLUEPRINT'te bu turda yazıldı):** tarihli her görev →
      OPH-209'un blok kuralıyla event; tarihsiz görev → ekleniş gününe; `scheduled_*`
      önceliği (OPH-192 davranışı) korunur — kullanıcı Google'da sürüklediyse blok
      oradan gelir.
- [x] **İki ayna da geçer:** Google server-side mirror (mevcut mapping + echo
      suppression + tombstone düzeni aynen) ve Apple EventKit cihaz aynası aynı kural
      setine bağlanır — iki platform kullanıcının önünde çelişemez (§17 D1 ruhu).
- [x] **Backfill:** mevcut tüm görevler için blok üretimi kuyruklu ve rate-limit'li
      (OPH-209 stratejisi); idempotent (mapping tablosu olan atlanır); ilerleme
      log'lanır.
- [x] Testler: blok kuralı birim testleri (saatli / 23:59 / tarihsiz-ekleniş-günü /
      gece yarısı kenetlemesi); switch'siz mirror kararının tablo testi; backfill
      idempotensi; inbound echo regresyonu; **canlı pass** (gerçek Google hesabı +
      Apple cihaz) STATE cihaz kuyruğuna.

**Uygulama notları (2026-07-29):**

- **Bastırma kolonu YENİ:** planda `calendar_mirror_enabled`i bastırma bayrağına
  çevirecektik — **imkânsız**: kolon `false` varsayılanlı, yani anlamı ters çevrildiği
  an MEVCUT HER GÖREV "bastırılmış" okunurdu. Migration
  `20260729200000_add_task_calendar_suppression.js` `calendar_mirror_suppressed_at`
  ekliyor; tek yazan `lib/inbound.js` (kullanıcı event'i Google'da silince). Eski kolon
  yerinde duruyor (append-only), ölü ama dürüst.
- **Sıra ADR'deki gibi:** önce `lib/google.js`'e eşzamanlılık kapısı (6) +
  429/5xx yeniden denemesi (`Retry-After`'a **uyar**, yoksa tam-jitter üstel geri
  çekilme), sonra kural, sonra backfill.
- **Blok kuralı** `blockForTask` olarak dışa açıldı; gece yarısı kenetlemesi
  `zonedWallTimeToUtc` ile görevin KENDİ diliminde yapılıyor (gece yarısı bir yere
  aittir). Apple yakasında aynı aritmetik cihazın yerel saatinde (`appleBlockFor`).
- **İki ayna tek fikstürle bağlandı:** `apps/app/test/fixtures/calendar_block_parity.json`
  — 7 vaka, iki süit de koşuyor (§17 D1).
- **Backfill penceresi** `enqueueWorkspaceMirrorSweep(app, workspaceId, now)`:
  -30g → +12ay, `due_at`/`scheduled_start_at` ya da (ikisi de yoksa) `created_at`
  üzerinden; bastırılmışlar atlanıyor; sayı log'lanıyor.
- **Testlerin güncellenmesi bilgi taşıyor:** mirror/inbound süitlerindeki 8 beklenti
  ESKİ kuralı yazıyordu (opt-in şart, tamamlanınca event silinir). Hepsi yeni kurala
  çevrildi ve *neden* değiştiği yorumda duruyor — "tamamlanan artık bloğunu koruyor,
  iptal edilen kaybediyor".
- **Onam metni** bağlantı kartında, düğmenin ÜSTÜNDE (`google-consent`).

**Doğrulama (2026-07-29):** API **390 unit + 47 entegrasyon** (gerçek MySQL; tamamlanan
görevin `✓` bloğu ve iptalde silinmesi kuyruktan uçtan uca), app **643 test**,
analyze + i18n + kontrast + lint + format temiz. **Canlı Google/Apple passi cihaz
kuyruğunda.**

### OPH-211 — Geciken grubunda tamamlanmış satır kalmaz (round 12 #3)

- [x] **Kural revizyonu (BLUEPRINT §12.2 + DESIGN §20 C1 — bu turda yazıldı):**
      tamamlanan görev gün sonuna kadar YALNIZ vadesi bugün olan (veya tarihsiz)
      ise listede kalır; **vadesi geçmiş görev tamamlanınca planlama listelerinden
      ANINDA düşer** — doğrudan Tamamlananlar'a (OPH-186). "Geciken" başlığının
      altında üstü çizili satır bir bilgi vermiyor; kullanıcının cümlesi kuraldır.
- [x] Sorgu: `watchOpen`/`watchProjectTasks`'ın `completedSince` dalına vade sınırı
      eklenir (`completed AND (dueAt IS NULL OR dueAt >= bugünBaşlangıcı)`); grup
      sayaçları ("Geciken · N") tamamlananları saymaz; `dayBoundaryProvider` canlılığı
      aynen (OPH-185 altyapısı).
- [x] Widget aynı kuralı alır (snapshot kaynağı `openTasksProvider` — bedava ama test
      edilir); Pano'nun completed sütunu ETKİLENMEZ (o ekranın sözleşmesi farklı).
- [x] Testler: dün vadeli + bugün tamamlanan → listede YOK, Tamamlananlar'da VAR;
      bugün vadeli + tamamlanan → grubunun sonunda kalır (OPH-185 regresyonu);
      tarihsiz + tamamlanan → kalır; gece yarısı geçişi; grup sayacı.

**Uygulama notu (2026-07-29):** düzeltme **tek satır** oldu — `_completedSince`e
`AND (dueAt IS NULL OR dueAt >= günBaşlangıcı)`. `watchOpen` ve `watchProjectTasks`
aynı `_watchList`ten geçtiği için ikisi birden düzeldi; grup sayaçları ve widget
`openTasksProvider` üzerinden **bedavaya** doğru oldu (satır listeye hiç girmiyor,
sayaç da onu saymıyor). 5 yeni sorgu testi: dün vadeli+tamamlanan listede YOK ve
arşivde VAR, bugün vadeli KALIR (OPH-185 regresyonu), tarihsiz KALIR, proje listesinde
aynı kural, gece yarısında bugünkü de düşer. **App 648 test.**

### OPH-212 — Proje düzenle sheet'i menünün altında açılıyor (round 12 #4)

- [x] **Kök neden doğrulanır:** [projects_screen.dart:192](../apps/app/lib/src/features/projects/ui/projects_screen.dart#L192)
      `onSelected` içinden senkron `showProjectEditSheet` — menü rotası kapanışını
      bitirmeden modal sheet açılıyor (Mahir'in ekran görüntüsü gelince eklenir —
      task onu BEKLEMEZ, davranış koddan yeniden üretilebilir).
- [x] **Düzeltme tek kalıpla:** menü eylemi → rota kapanışı tamamlandıktan sonra aç
      (post-frame/`Future` ertelemesi veya `showMenu` sonucunu bekleyen kalıp) — ve
      **aynı hata repo genelinde taranır** (Notlar menüleri, Dosyalar eylem sayfaları,
      görev menüleri, etiket yönetimi): OPH-195 disiplini — bulunan her eş vaka ya
      burada düzelir ya gerekçeyle yazılır.
- [x] Regresyon testi: menüden "Düzenle" → sheet önde ve etkileşilebilir (tap
      hedefine gerçekten basılabildiği widget testiyle kanıtlanır); mevcut menü
      akışları regresyonsuz.

**Kök neden TASKS'takinden farklı çıktı ve KANITLANDI (2026-07-29):** suç senkron
`showProjectEditSheet` çağrısı değil — `showModalBottomSheet` **`useRootNavigator`
verilmeden** çağrılıyordu (varsayılan `false`), yani sheet `StatefulShellBranch`
navigator'ına push ediliyor ve HomeShell'in `extendBody: true` + `bottomNavigationBar`
(GlassSurface) + FAB'ı **onun üstüne** boyanıyordu. Kanıt iki taraflı: (1) aynı
fonksiyonu **root** context'ten çağıran Projeler FAB'ı hep doğru çalışıyordu;
(2) yeni regresyon testi düzeltme geri alınınca **"would not hit test on the specified
widget"** ile düşüyor — bildirilen belirtinin ta kendisi.

**Düzeltme + tarama:** `useRootNavigator: true` **17 çağrı yerinin hepsine** verildi
(sound picker, pano kolonları, görev create sheet, Apple/Google takvim kartları, proje
düzenle, etiket yönetimi, not editörü, dosya eylemleri, klasörler, hızlı erişim paneli
ve sheet'leri, ayarlar). OPH-207'nin dialog'ları zaten peşinen veriyordu.

**Testin dişi:** `findsOneWidget` bu hatayı ÜÇ tur boyunca kaçırırdı — sheet ağaçtaydı,
sadece dokunulamıyordu. Yeni test sheet'e **dokunuyor**: alana `tap` + `enterText` +
"Save changes"e basıp sunucu satırını doğruluyor.

### OPH-213 — Home görünüm kontrolleri app bar'a taşınır (round 12 #5)

- [x] **Liste|Pano `SegmentedButton` satırı ölür** → app bar'da tek ikon toggle
      (Notlar kalıbı: [notes_screen.dart:56](../apps/app/lib/src/features/notes/ui/notes_screen.dart#L56));
      ikon mevcut görünümün TERSİNİ değil KENDİNİ değil — karar: ikon **geçilecek
      görünümü** gösterir (Notlar'daki davranışın aynısı; tooltip yazar), tercih
      kalıcılığı (`homeViewProvider`) aynen.
- [x] **Takvim göster/gizle** kayan düğmesi ölür → app bar'da takvim ikonu (açık/
      kapalı durumu ikon varyantıyla, `calendar_month`/üstü çizili; tooltip);
      tercih (`homeCalendarVisibleProvider`) aynen. İki ikon da **ayarlar
      düğmesinin solunda** (kullanıcının yerleşimi).
- [x] **DESIGN §16 revizyonu bu turda yazıldı:** H1 sliver listesi iki satır kaybeder;
      H3'ün "Pano'da toggle sabit" sapması KENDİLİĞİNDEN çözülür (app bar zaten tek
      sabit — OPH-172'nin kuralı güçlenir). Geniş ekran aynı ikonları app bar'da
      taşır (kalıp tek).
- [x] i18n: `home.viewList/viewBoard/showCalendar/hideCalendar` tooltip'leri (mevcut
      anahtarlar yeniden kullanılır/taşınır); kontrast: app bar ikon durumları iki
      temada.
- [x] Testler: toggle app bar'dan çalışır (Liste↔Pano), satırların yokluğu, takvim
      ikonunun tercihi koruması, telefon+geniş ekran iki kırılımda, arama modunda
      ikonların davranışı.

**Uygulama notları (2026-07-29):** `buildSectionAppBar`a **`trailingActions`** eklendi
(ikinci bir AppBar kalıbı doğurmadan; ikonlar ayarların solunda). Liste|Pano tek ikon,
**geçilecek görünümü** gösteriyor (Notlar kalıbı); pano kolon düzenleyicisi yanında,
takvim ikonu yalnız liste görünümünde (panoda takvim zaten yok). Üç yerleşimden de
(geniş, telefon-pano, telefon-liste) eski satırlar kalktı.

**Testin öğrettiği iki şey:** (1) **ikon bir TOGGLE, segment ise idempotent'ti** —
`localKv` global önbelleği bir önceki testin tercihini taşıdığı için `openBoard()`
bazen panodan LİSTEYE geçiyordu; yardımcı artık zaten panodaysa dokunmuyor ve
`alliswell_home_view` `app()`te temizleniyor. (2) `home_scroll_test`in H1 testi artık
**tersini** doğruluyor: toggle kaydırmayla KAYBOLMUYOR, çünkü app bar'a taşındı —
quick-add hâlâ kayboluyor (DESIGN §16 H1 revizyonu birebir).

### OPH-214 — Ekran açıkken alarm: ölü erteleme ikonu + dokununca çökme (round 12 #6, cihaz taskı)

- [x] **Gözlemin yazılı hali (2026-07-29, gerçek cihaz):** ekran KAPALIYKEN tam ekran
      alarm doğru çalışıyor; ekran AÇIKKEN üstten kalıcı (heads-up) bildirim geliyor —
      X kapatıyor ✓, yanındaki **saat ikonu hiçbir şey yapmıyor** ✗, bildirimin
      gövdesine dokununca uygulama **açılırken çöküyor** ✗.
- [x] **Kök neden araştırması — iki ayrı hat:** (a) **ölü aksiyon:** saat ikonu hangi
      aksiyon (erteleme?); Android'de aksiyonun `showsUserInterface`/arka plan isolate
      handler kaydı ve [actions.dart](../apps/app/lib/src/notifications/actions.dart)
      yönlendiricisine gerçekten düşüp düşmediği; iOS'ta category eşlemesi. Alarm
      günlüğü (OPH-176) burada kanıt kaynağı — aksiyon satırı düşmüyorsa kablolama
      kopuk. (b) **dokunuş çökmesi:** launch/payload işleme — soğuk başlatmada payload
      rotası, `alliswell://` çözücüsü, auth restore yarışı; crash log toplanır
      (adb logcat / Xcode organizer). Hangi OS olduğu cihazda doğrulanır (gözlem
      Android'e işaret ediyor; iOS aynı senaryoda ayrıca denetlenir).
- [x] Düzeltme + **alarm günlüğüne** eksik `action`/`interacted` satırlarının
      düşmesi garanti edilir (bir dahaki rapor kanıtla gelir).
- [ ] **Cihaz DoD:** ekran açıkken alarm → erteleme düğmesi çalışır ve "{saat}'te
      tekrar" davranışı OPH-177 sözleşmesine uyar; bildirime dokunmak doğru ekranı
      açar, çökme yok; ekran kapalı tam ekran akışı regresyonsuz; sonuç STATE'e.

**Kod tarafı BİTTİ (2026-07-29); kalan yalnız cihaz DoD'si.** İki hipotez de koddan
kanıtlandı ve düzeltildi:

1. **Cold-start kaybı.** `getNotificationAppLaunchDetails` / `didNotificationLaunchApp`
   repoda **hiç yoktu** (`lib`, `ios`, `android` tarandı) — oysa TÜM Android aksiyonları
   `showsUserInterface: true`, yani aksiyona basmak uygulamayı BAŞLATIYOR ve yanıt
   yalnız o API'den okunabiliyor. Okunmadığı için basış hiçbir yere düşmüyordu:
   "saat ikonu hiçbir şey yapmıyor"un tam karşılığı. `initialize` artık launch
   detaylarını okuyup olayı kuyruğa koyuyor.
2. **Dinleyici yarışı.** `_events` broadcast ve **tamponsuzdu**; tek dinleyici
   `notificationSchedulerProvider`, o da HomeShell mount olup workspace çözülünce
   doğuyor. Arada gelen her yanıt **sessizce düşüyordu**. Artık dinleyicisi olmayan
   yanıtlar kuyruğa giriyor ve **ilk** dinleyiciye bir kez akıyor (ikinci dinleyici
   aksiyonu tekrar çalıştırmaz — görevi iki kez ertelemek zararsız değil).

**Çökmeye dair:** ertelenmiş teslim aynı zamanda router'ı işin dışında tutuyor —
uygulama ayağa kalkana kadar hiçbir yönlendirme denenmiyor, ki dokununca çökmenin
en olası yeri orasıydı. **Gerçek crash log'u yine de cihaz turunda toplanmalı**
(adb logcat / Xcode organizer): sebep auth restore yarışıysa ayrıca yazılacak.

**Cihaz DoD (kullanıcıda):** ekran açıkken alarm → erteleme düğmesi çalışır ve
"{saat}'te tekrar" OPH-177 sözleşmesine uyar; bildirime dokunmak doğru ekranı açar,
çökme yok; ekran kapalı tam ekran akışı regresyonsuz; **Ayarlar ▸ Alarm günlüğü'nde
`action`/`interacted` satırları görünür** (bu tur onların düşmesini garanti etti);
sonuç STATE'e.

### Round 13 — kullanıcı düzeltmeleri (2026-07-29, Epic 19'un altında; ayrı task numarası verilmedi, istek "direkt yap" idi)

- [x] **1. Takvim bağlantısını koparma yok.** Google'da vardı ama listenin en altında
      bir satırdı ve **onay sormuyordu**; Apple'da hiç yoktu. Artık ikisinde de hesabın
      **yanında kırmızı `link_off` düğmesi** var (`google-unlink`, `apple-unlink`) ve
      ikisi de onay istiyor. Apple'da "koparmak" OS iznini iptal etmek değil — uygulama
      bunu yapamaz — **seçili takvimi boşaltmak**, yani aynayı durdurmak; onay metni
      izninin Ayarlar'da durduğunu söylüyor. Google'ın eski alt satırı da aynı onaya bağlandı.
- [x] **2. Dosya/klasör silmede onay çıkmıyor.** Onay dialog'ları **zaten vardı** —
      görünmüyorlardı: OPH-212'de sheet'leri kök navigator'a aldık ama **`showDialog`
      dokunulmamıştı**, dolayısıyla dal navigator'ına açılan her dialog HomeShell'in cam
      çubuğu ve FAB'ının altında kalıyordu. **20 `showDialog` çağrısının hepsi** kök
      navigator'a alındı — dosya/klasör silme, etiket yönetimi, not silme, ayarlar dahil.
- [x] **3. Geri al çubuğu çok uzun kalıyor.** `kAwUndoWindow` 5 sn → **3 sn**
      (snackbar süresi zaten pencereden türüyor). Kaydırma animasyonu + bir bakış için
      yeterli; fazlası, kullanıcının çoktan karar verdiği bir düğmeyi listenin üstünde
      tutmak demek.
- [x] **4. Kart boşlukları eşit değil.** İki farklı kalıp vardı: görev satırı
      `Padding(vertical: 3)`, etkinlik kartı `Card(margin: bottom 8)`. Sonuç: görev→etkinlik
      **3 px** (yapışık), etkinlik→görev **11 px**. Etkinlik kartı da görev satırının
      ritmine alındı — her boşluk artık **6 px**, sıra ne olursa olsun.
- [x] **5. Arama app bar'a taşındı.** Yeni `AwSearchAction` (`widgets/search_field.dart`):
      app bar'da bir arama ikonu, tıklayınca **yerinde genişleyen** input, X ile kapanıyor.
      **Kapanış sorguyu da temizliyor** — kapalı bir ikonun arkasında duran filtre, §16'nın
      takvim seçimi için zaten reddettiği "görünmez filtre"dir. Üç ekranda uygulandı
      (Home, Notlar, Projeler); üçü de gövdesinden bir satır kazandı. Genişlik ekrana göre
      140-280 px arası kısılıyor ki başlık ve diğer ikonlar yerinden olmasın.
- [x] **6. Tekrar cümlesi tarihi değiştirince güncellenmiyor.** State bayat değildi,
      **kural gerçekten değişmiyordu**: §25 R8 "günler kuraldan gelir" diyordu, ama
      kullanıcı tarihi değiştirerek hangi günü istediğini zaten söylemişti. Artık
      **kapsamı "bu ve gelecektekiler"/"tümü" olan bir tarih düzenlemesi deseni de
      taşıyor** (`ruleFollowingDay`): tek günlü aylık kural yeni güne geçer, "ayın son
      günü" son günse öyle kalır, "2. Salı" yeni tarihin kaçıncı Salı'sıysa ona döner,
      yıllıkta ay da güncellenir. **Belirsiz kurallar** (birden çok gün, "22'sinden
      sonraki ilk Pazartesi" penceresi) desenini korur, yalnız saati alır — taşınacak
      tek bir gün yok. Aynı gün içinde saat değişimi kuralı hiç kıpırdatmıyor (yoksa
      her satırın id'si boşuna değişirdi).

**Doğrulama:** app **654 test**, API **393 unit + 47 entegrasyon**, analyze + i18n +
kontrast (FAILURES: 0) + lint + format temiz.

**Epic 19 DoD:** her task kendi testleriyle; ADR-0020 + ADR-0021 kabul edilmiş; motor
parite fikstürleri iki süitte de yeşil; README tekrar bölümü gerçeği yansıtıyor;
BLUEPRINT §7.1/§12.2/§12.17 + DESIGN §16/§20/§25 tutarlı; cihaz işleri (214 + 210'un
canlı Google/Apple passi) STATE kuyruğunda; epic sonunda app + API tam süit +
`check:i18n` + kontrast FAILURES: 0 + `lint`/`format:check`/`check:no-ts` → **v0.8.0**.

---

## Epic 20 — İstek turu 11 #2: Yapay zeka — MCP bağlayıcısı, kendi anahtarınla sohbet, sesle görev (Phase 14, v0.9.0)

_(Doğdu 2026-07-29 — istek turu 11, madde #2; Mahir'in "üstüne 10 kere bastığı" iş.
İstek: "Claude/ChatGPT/Gemini hesabını bağla — API key girmeden, kendi limitlerinden;
verilerinle sohbet et; solda ikinci bir FAB'a basılı tutup konuş, 'Ahmet projesine şu
işleri yarın hatırlat' desin, todo kendiliğinden eklensin; bubble açılınca el kalkabilsin,
kapanmasın; herhangi bir metni uygulamaya paylaşınca bubble'da açılsın; README'ye logolar."
Fikir, planlamadan önce **maksimum-efor özel araştırma ajanına** verildi (2026-07-29);
sağlayıcı programları, STT, MCP, mağaza politikaları ve prompt-injection savunması
kaynaklarıyla doğrulandı. Bağlayıcı metinler: **[AI.md](AI.md)** (bu turda yazıldı —
kanıt linkleri orada), **[ADR-0019](adr/0019-ai-provider-architecture.md)**,
BLUEPRINT **§4.13** + **§12.16**, DESIGN **§24**. Sıra bağlayıcı: **215→217 temel** →
**218 MCP** → **219→222 gömülü sohbet + çıkarım** → **223→225 ses & paylaşım (cihaz)** →
**226→227 sertleştirme + tanıtım**. Cihaz isteyenler: 223, 225 (+218/227'nin dizin
başvuruları canlı instance ister). _Numara kayması:_ feedback round 12 (2026-07-29)
araya Epic 19'u soktu — bu epic Epic 20'ye, taskları OPH-204…216'dan
**OPH-215…227'ye** kaydı; içerik değişmedi.)_

> **Turun tek cümlesi:** istenen şeyin birebiri — "abonelik OAuth'u, API key'siz" —
> 2026 ortasında üç sağlayıcıda da üçüncü partilere KAPALI (Anthropic açıkça yasakladı,
> Google ihlal sayıp hesap kapatıyor, OpenAI bekleme listesinde); Mahir'in Cloudflare/
> Notion'da gördüğü deneyim ise **ters yön** — kendi hesabına bir MCP bağlayıcısı
> eklemek. Bu yüzden epic **iki hat** taşır: **Hat A** "AllisWell'i Claude/ChatGPT'ne
> ekle" (uzak MCP sunucusu — dürüst "aboneliğinle çalışır" hikâyesi ve pazarlama kası)
> ve **Hat B** uygulama içi AI (BYOK: kendi API anahtarın + self-host için Ollama) —
> ses, bubble ve paylaşım orada yaşar. Auth dikişi, bir sağlayıcı abonelik-OAuth'u
> açtığı gün `oauth_subscription` modunun şemasız-değişiklikle oturacağı şekilde kurulur.

**Round'un doğrulanmış gerçekleri (ajan araştırması, 2026-07-29 — tam kanıt ve linkler [AI.md](AI.md) §1):**

| # | Bulgu | Sonuç |
| - | ----- | ----- |
| 1 | Anthropic: Claude Free/Pro/Max OAuth token'larının başka üründe kullanımı **yasak** (Şub 2026, yazılı politika); Google: Gemini CLI OAuth'unu proxy'lemek ToS ihlali, **25 Mart 2026'dan beri hesap kapatma** (ücretli Ultra dahil); OpenAI: "Sign in with ChatGPT" üçüncü partilere **kapalı önizleme** (ilgi formu) | Abonelik-OAuth v1'de YOK; `ai_connections.auth_mode`'da **rezerve** durur; OpenAI ilgi formuna kayıt kullanıcı aksiyonu olarak STATE'e işlenir; üç ayda bir politika kontrolü park kuralı |
| 2 | Claude/ChatGPT tarafında **uzak MCP bağlayıcıları** tüketici planlarında canlı (Claude: Free×1/Pro/Max custom connectors + dizin; ChatGPT: developer mode + uygulama dizini); Notion'ın "AI bağlantısı" da tam bu | Hat A = `/mcp` ucu; her self-host instance kendi bağlayıcı URL'i — dizine girmeden de çalışır |
| 3 | Claude API'sinde **ses girişi yok**; OpenAI (`gpt-4o-mini-transcribe` ≈$0.003/dk) ve Gemini'de var; cihaz-üstü STT (iOS SFSpeech/SpeechAnalyzer, Android SpeechRecognizer) Türkçe dahil ücretsiz + canlı partial | STT sohbet sağlayıcısından **bağımsız bir dikiş**; v1 cihaz-üstü, v1.5 sunucu-STT anahtarı |
| 4 | Üç sağlayıcıda da şema-kısıtlı yapılandırılmış çıktı + SSE akışı var; hiçbiri min/max doğrulamaz | Tek JSON şeması (`ai/schema.js`) + sunucuda Ajv + tek onarım turu; sağlayıcı-doğal kısıtlı çıktı |
| 5 | API veri politikaları: Anthropic 7 gün/eğitim yok; OpenAI 30 gün/eğitim yok; **Gemini ücretsiz katman VERİYLE EĞİTİYOR** | Onam ekranı sağlayıcı-başına dürüst cümle; Gemini ücretsizde sarı uyarı zorunlu |
| 6 | Prompt injection: not/görev başlıkları modele giren **güvenilmez girdi** (OWASP LLM01, "lethal trifecta") | v1'de modele **hiç yazma aracı verilmez** — yalnız öneri JSON'u + onay kartı; silme AI'ya **kalıcı olarak** kapalı (DESIGN §19 ile tutarlı) |
| 7 | Prod Apache reverse proxy SSE'yi tamponlayabilir (mod_deflate/flushpackets) | OPH-217'nin DoD'sinde **prod'a karşı curl** artımlı akış kanıtı + deploy kontrol listesi; Socket.IO tek-dikiş yedek transport (web'de birincil) |

**Round'da karara bağlananlar (AGENTS §8 — sor değil, karar ver ve yaz):** onay kartı
v1'de ATLANAMAZ (yüksek-güven otomatik commit v1.5 opt-in, park); sohbet geçmişi
**cihaz-yerel** (senkron `conversation` varlığı gizlilik duruşu değişikliğidir — park,
bilinçli karar ister); beş adaptör de v1 (Anthropic+OpenAI+Gemini kullanıcının açıkça
saydığı üçlü; Ollama self-host DNA'sı; OpenRouter aynı ailede ucuz); alliswell.space
**BYOK-only** açılır (instance-env anahtar self-host'lara; barındırılan ücretli
"AllisWell AI" katmanı ürün kararı olarak parkta); README rozetleri **doğruyu söyler**
("Works with Claude/ChatGPT" = MCP; Gemini = "API key" — tüketici Gemini uygulamasında
bağlayıcı yüzeyi yok; logo kullanımı marka kurallarına takılırsa metin rozetleri).

### OPH-215 — ADR-0019 + AI temeli: sağlayıcı dikişi, anahtar şifrelemesi, ayar şeması

_(✅ 2026-07-30 — dört uygulama notu: (1) `ai_action_log.source` ENUM'u dört değil
ALTI değerle doğdu (+`quick_add`,`voice` — şemanın kendisi bu iki extract yüzeyini
ayırt ediyor; ENUM genişletmek migration ister, bilinen yüzey listesi baştan tam);
(2) `key_last4` SAKLANAN kolon — serializer şifreliye hiç dokunmaz, maske için her
listede decrypt etmek düz metnin maruziyet penceresini kozmetik uğruna genişletirdi;
(3) app'in yüzey-çekme kapısı için `GET /ai/status` ucu eklendi (configured +
instance sağlayıcıları); (4) create şemasında `consentAcknowledged: const true` —
OPH-220'nin onam ekranı yürünmeden create'e ulaşılamaz, kalıcı sunucu izi baştan.)_

- [x] **[ADR-0019](adr/0019-ai-provider-architecture.md) kabul edilmiş olmalı** (bu
      turda yazıldı): SDK yok — `fetch` tabanlı ince adaptörler (ADR-0006'nın "Google
      SDK'sız" duruşunun genellemesi), BYOK-first, `auth_mode`'da rezerve
      `oauth_subscription`, LangChain-sınıfı bağımlılık YOK.
- [x] Migration'lar: `ai_connections` (`user_id, workspace_id, provider
      ENUM(anthropic|openai|gemini|openrouter|ollama), auth_mode ENUM(api_key|instance_env|
      oauth_subscription), encrypted_key TEXT NULL, base_url NULL, default_chat_model,
      default_fast_model, status, last_used_at` + soft delete), `ai_usage_events`
      (istek başına: kind chat|extract|transcribe|mcp, model, input/output token,
      süre — **içerik asla değil**), `ai_action_log` (AI-önerisi + kullanıcı onayı
      denetim izi: source bubble|share|chat|mcp, proposal JSON, accepted, varlık
      referansları — Epic 16'nın alarm günlüğü dersi: tartışma hafızadan değil kayıttan).
- [x] Anahtar şifrelemesi **ADR-0006 kalıbının aynısı**: `src/lib/crypto.js` yeniden
      kullanılır, yeni `AI_TOKEN_KEY` env (prod placeholder reddi aynen — prod +
      `AI_ENABLED=true` iken gerçek anahtar ZORUNLU, boot'ta reddedilir); anahtar hiçbir
      serializer'dan çıkmaz — arayüz yalnız `…son4` görür; testler ciphertext sızmadığını
      kanıtlar.
- [x] Yapılandırma kapısı: `AI_ENABLED=false` (instance kapatabilir — route'lar hiç
      register edilmez, tüm `/ai/*` 404) ve hiç bağlantı yokken `AI_NOT_CONFIGURED`
      dürüst boş durumu (`STORAGE_NOT_CONFIGURED` kalıbı; `app.ai.resolveConnection`
      503 atar) — AI yüzeyleri arayüzden tamamen çekilir (app tarafı OPH-220).
- [x] **Kullanıcı aksiyonu kaydı:** OpenAI "Sign in with ChatGPT" geliştirici ilgi
      formuna başvuru + üç ayda bir üç sağlayıcının politika kontrolü — STATE
      "Kullanıcıdan bekleyen"e işlenir.
- [x] Testler: bağlantı CRUD'u şifreli anahtar gidiş-dönüşüyle (integration); sahiplik
      (başkasının bağlantısı 404); `AI_ENABLED=false`'ta tüm `/ai/*` uçlarının 404'ü.

### OPH-216 — Sağlayıcı adaptörleri: Anthropic, OpenAI, Gemini, OpenRouter, Ollama

_(✅ 2026-07-30 — uygulama notları: (1) OpenAI adaptörü bir **lehçe fabrikası**
(`createOpenAiDialectAdapter`) — OpenRouter ~15 satırlık örnekleme (max_tokens +
`/v1/auth/key` verify + nezaket başlıkları); OpenAI `chat/completions` konuşur,
`/v1/responses` değil — iki sağlayıcının paylaştığı ortak dil bu. (2) Hata olayları
tel seviyesinde değil: adaptörler `AiProviderError` FIRLATIR, 'error' SSE olayına
çeviri route katmanının işi (OPH-217). (3) Ollama SSE değil **NDJSON** — ikinci
ayrıştırıcı `parseJsonLines` aynı dosyada. (4) Şema biçimlendirme adaptörün işi
DEĞİL: `extract()` çağırandan SAĞLANMIŞ (provider-dönüştürülmüş) şemayı aynen
geçirir — dönüşüm OPH-219'un `providerSchema`'sında. (5) Katalog varsayılanında
Gemini sohbet = **Flash**: ücretsiz katman Flash-only, 402 yiyen varsayılan yalan
olur. (6) fakeai'nin öğrettiği tuzak: istemci kopuşu `request.raw`'da değil
**`reply.raw`'ın 'close'unda** görünür — OPH-217'nin gerçek SSE ucu aynı
dinleyiciyi kullanmalı, yorumda yazılı.)_

- [x] `src/lib/ai/providers/*.js` — ortak sözleşme: `capabilities()`, `chatStream()`
      (sağlayıcı SSE lehçeleri **tek normalize akışa** çevrilir: `text|usage|done|error`),
      `extract()` (sağlayıcı-doğal kısıtlı çıktı: Anthropic structured outputs, OpenAI
      `json_schema` strict, Gemini `responseSchema`; OpenRouter=OpenAI lehçesi; Ollama
      `format: json` — tam şema, Ollama ≥0.5 grameri).
- [x] ~80 satırlık SSE ayrıştırıcı elle yazılır (bağımlılık yok — ADR-0019'da yazılı;
      `lib/ai/sse.js`: çok baytlı karakter chunk sınırında bölünse de TextDecoder
      stream'li çözer, testte `ş` ikiye bölünür).
- [x] **Süreç-içi sahte sağlayıcılar** (ADR-0006 §5 emsali): beş adaptör aynı Vitest
      sözleşme süitinden geçer (akış parçalama, iptal, hata gövdeleri, kısıtlı çıktı
      reddi + onarım girdisi) — TEK Fastify, beş yerel tel kodlayıcı
      (`test/helpers/fakeai.js`); tel assert'leri strict/responseSchema/format'ın
      GERÇEKTEN gittiğini, Gemini anahtarının URL'e asla girmediğini kanıtlar.
- [x] Model kataloğu ucu: `GET /ai/models` — bağlantının sağlayıcısına göre seçilebilir
      modeller + fabrika varsayılanları (sohbet: orta sınıf; çıkarım: **hızlı sınıf** —
      maliyet tavanı ADR'de); katalog statik veri (üç aylık kontrolde tazelenir),
      Ollama canlı `/api/tags`; bağlantı test ucu (`POST /ai/connections/:id/test`)
      dürüst `{ok:false, code}` döner ve auth hatasında satırı `error`'a çevirir.
- [x] Testler: sözleşme süiti ×5; `AbortSignal`'ın gerçek iptali (fake'in `aborted`
      sayacı upstream soketin kapandığını kanıtlar); usage muhasebesinin
      `ai_usage_events`'e düşüşü (+ bozuk muhasebe yanıtı asla düşürmez).

### OPH-217 — `/ai/chat`: SSE akışı + hız sınırı + iptal + prod kanıtı

_(✅ 2026-07-30 kod tarafı — prod curl kanıtı v0.9.0 deploy'unda alınacak (aşağıda,
STATE kuyruğunda). Uygulama notları: (1) istemci kopuşu `request.raw` DEĞİL
**`reply.raw`'ın 'close'** olayında görünür (OPH-216'nın fakeai dersi — checklist'in
orijinal cümlesi düzeltildi); (2) iptal hata değil: akış `done {cancelled:true}` ile
biter, sahiplik STREAM'İ TUTAN worker'da doğrulanır (iptal eden yalnız kendi isteğini
öldürebilir); (3) bucket chat+extract ORTAK (aynı sağlayıcı kotasını içerler);
Redis'siz süreç-içi fallback PM2'de worker-başına düşer — daha sıkı, daha gevşek
değil; Redis komut hatası **fail open** (limiter koruma, authz değil); (4) sunucu
tarafı socket odası `user:{userId}` — `ws:*` odaları sohbeti tüm üyelere yayınlardı;
Flutter `AiStreamClient` dikişi OPH-221'de.)_

- [x] SSE-over-POST (`text/event-stream`, 15 sn heartbeat yorumu, token demeti başına
      flush + drain backpressure); istemci kopunca (**`reply.raw` close**) upstream
      `AbortController` iptali.
- [x] Redis: kullanıcı başına token-bucket hız sınırı (paylaşılan self-host'u korur;
      atomik Lua, chat+extract ortak kova) + `ai:cancel` yayını (bubble kapatınca PM2
      worker'ları arası iptal — entegrasyon testi B instance'ına POST edilen iptalin
      A'daki akışı öldürdüğünü gerçek Redis'le kanıtlıyor); instance_env için günlük
      token tavanı (`AI_DAILY_TOKEN_CAP` → 429 `AI_DAILY_CAP`).
- [x] **Transport dikişi tek yerde:** sunucu tarafı hazır — `runChat` tek kod yolu,
      `sseSink` (iOS/Android/masaüstü) + `socketSink` (**web Socket.IO odası**
      `user:{userId}`, anında 200 ack + detached koşu). Flutter `AiStreamClient`
      OPH-221'de; UI transportu bilmez.
- [x] **Apache/PM2 deploy kontrol listesi dokümana** ([AI.md](AI.md) **§3** + SELF-HOSTING
      Apache bloğu): `text/event-stream` için `no-gzip`, `flushpackets=on`,
      `ProxyTimeout` > heartbeat. **DoD: alliswell.space'e karşı curl ile artımlı parça
      kanıtı** — tamponlanmış SSE "AI takıldı" gibi görünür, bu yüzden kanıt pazarlıksız
      (v0.9.0 deploy adımında alınır, STATE'e yapıştırılır).
- [x] Testler: enjekte akışla unit (parça sırası, heartbeat, iki iptal türü, hata
      çevirisi + status bayrağı); hız sınırı 429 + makine-okur kod + Retry-After;
      usage satırı her sonuçta; gerçek dinleyicide SSE artımlılığı + kopuş-abort +
      sahiplikli iptal + **eş üyenin soketi HİÇBİR ŞEY almaz**.

### OPH-218 — Hat A: AllisWell uzak MCP sunucusu ("Add to Claude / ChatGPT")

_(✅ 2026-07-30 — uygulama notları: (1) **elle yazılmış** Streamable HTTP (SDK yok —
ADR-0019 duruşu sunucuya genellendi); stateless, POST-only JSON-RPC, GET/DELETE 405,
Mcp-Session-Id yok; protokol 2025-06-18 (+2025-03-26). (2) **Kendi OAuth 2.1 AS'imiz**:
discovery (RFC 8414/9728, openid alias + /mcp sonekli PR biçimi), açık DCR (RFC 7591),
sunucu-render login+consent (API'de UI yok — inline HTML; form-encoded parser plugin
kapsamında ~6 satır; imzalı form token'ı = google state emsali; PKCE S256 ZORUNLU);
**opak token'lar** (JWT değil — gerçek revocation; refresh_tokens kalıbı + aile iptali;
kod tek-kullanım, replay tokenları yakar). (3) `MCP_ENABLED` + `API_PUBLIC_URL` **ayrı
kapı** (`AI_ENABLED` yalnız `/ai/*`); yapılandırılmamışsa 404, boot hatası ASLA.
(4) **`src/db/tasks.js` çıkarıldı** — createTask/completeTask/taskDetail routes'tan
alındı, REST delege ediyor, sync.js'e DOKUNULMADI; 43 mevcut task testi regresyon ağı,
yeşil. (5) Proje belirsizse create YARATMAZ, aday döner (onay-kartı seçicisinin dürüst
MCP ikizi); etiketler yalnız MEVCUT'a çözülür, eşleşmeyen raporlanır. (6) Araç Ajv hatası
protokol hatası değil `isError:true` SONUÇ (model düzeltebilir). Kırmızı-takım fikstürü
`ai_redteam.json` doğdu — OPH-226 genişletecek.)_

- [x] **ADR-0022 (ilk iş):** transport (Streamable HTTP `/mcp`), kimlik (mevcut auth
      OAuth 2.1 sağlayıcısı olarak + dynamic client registration), araç yüzeyi ve yazma
      kuralları. MCP **domain katmanının bir istemcisidir** — ham SQL asla; her yazı
      REST ile aynı Ajv + authz + revision yolundan geçer (`src/db/tasks.js`).
- [x] Araçlar v1: `search` (ADR-0013 fold'uyla — başlıklar fold-garantili, gövdeler
      ikinci geçiş), `list_tasks` (filtreli + today/overdue kullanıcı TZ'siyle),
      `get_task` / `get_note` / `get_project` (workspace dışı → varlık sızdırmayan
      NOT_FOUND), `create_task` (OPH-219'un şemasıyla — tek kaynak + idempotencyKey +
      proje/etiket çözümü), `complete_task` (idempotent); kaynaklar: bugün/geciken
      görünümleri. **Silme aracı YOK — kalıcı karar** (tablo satır 6).
- [x] Yazma araçları host onay UI'ları için annotate edilir (`destructiveHint:false`);
      `ai_action_log`'a `source='mcp'` düşer; `mcp_mutations` idempotency defteri.
- [x] Doküman: "AllisWell'i Claude'a / ChatGPT'ye ekle" sayfası ([MCP.md](MCP.md);
      self-host: kendi `https://instance/mcp` URL'in; alliswell.space için dizin
      başvuruları OPH-227'de) + SELF-HOSTING/ARCHITECTURE çaprazları.
- [x] Testler: birim — OAuth tam dansı (PKCE, kod reuse→aile iptali, rotasyon, revoke,
      form-token tamper); protokol (versiyon pazarlığı, -32700/600/601/602, 405'ler,
      Origin matrisi); araçlar (fold arama Işık≈isik, **iki kullanıcılı izolasyon bayt
      bayt**, idempotent create, belirsiz proje → satır YOK); **düşman korpusu** üç yüzey
      assert'i (veri döner, eylem DEĞİL, tablo değişmez). Entegrasyon — gerçek dans +
      **MCP yazısının /sync/pull'da cihaza aktığı** + gerçek unique index'te idempotens.
      MCP Inspector koşusu STATE cihaz/kullanıcı kuyruğunda (canlı HTTPS ister).

### OPH-219 — Çıkarım ucu + görev-önerisi sözleşmesi (tek şema)

_(✅ 2026-07-30 — **218'den ÖNCE koşuldu (bilinçli takas, STATE'te):** MCP'nin
`create_task`'ı bu şemayı tek kaynaktan tüketsin diye. Uygulama notları:
(1) `ajv-formats` YOK — `dueAt` açık ISO+offset pattern'i; `dependencies: {dueAt:
[dueAtSource]}` çözülmüş tarihi ham ifadesiz İMKÂNSIZ kılar (dürüst onay kartının
şema seviyesinde garantisi); (2) `providerSchema()` saf dönüşüm: OpenAI strict
(hepsi required + nullable + bound'lar soyulur) / Gemini (additionalProperties+
pattern yok) / Anthropic (dependencies+pattern'siz) / Ollama (aynen) —
`normalizeProposal` strict null'larını düşürür, Ajv HER ZAMAN son sözü söyler;
(3) geçmiş tarih ÇİFT katman: prompt söyler + sunucu post-check `date_unclear`'ı
EKLER (tarih kaydırılmaz — sessiz kabul yapısal imkânsız); (4) `defaultTaskTime`
İSTEMCİDEN gelir (OPH-161 app-side ayarı, sunucu göremez) — fallback '23:59'
ürünün varsayılan varsayılanı; (5) karar ucu `POST /ai/actions/:id/decision`:
AYNI karar tekrarı sessiz 200 no-op (çevrimdışı rapor kuyruğu güvenle retry eder),
FARKLI karar 409 — kanıt append-once; (6) `ajv` package.json'a açıkça yazıldı
(Fastify'ın zaten kullandığı doğrulayıcı — yeni kategori değil; hoisted v6'ya
çözülüyordu, ^8 pinlendi).)_

- [x] `src/lib/ai/schema.js` — **tek kaynak** öneri şeması: `intent
      (create_tasks|answer|none)`, `tasks[] {title, description?, projectName?
      (kullanıcının SÖYLEDİĞİ ad — id asla), dueAt (ISO+offset, kullanıcı TZ),
      dueAtSource ("yarın 15:00" ham ifadesi — onay kartında gösterilir), reminderAt?,
      priority, urgent, tags[], checklist[], confidence, ambiguities[]}`; Ajv hem API'de
      hem MCP'de aynı modülden.
- [x] Prompt'a enjekte: `now` (ISO+offset — `formatInstantWithOffset` lib/time.js'e
      eklendi), IANA TZ, haftanın günü, **workspace'in varsayılan görev saati**
      (OPH-161 ayarı — "yarın" çıplaksa yarın@varsayılan saat, sabit saat İCAT
      EDİLMEZ); geçmişte kalan due → sessiz kabul değil `date_unclear`.
- [x] **Proje eşleme LLM'e bırakılmaz:** model `projectName`'i aynen döndürür; çözüm
      bizde — ADR-0013 fold'u + prefix/contains katmanı (`Ahmet ≈ ahmet ≈ AHMET`,
      `ışık ≈ isik`); tek eşleşme → önseçili, çoklu/sıfır → onay kartında seçici +
      "+ Proje ekle" (OPH-163 affordance'ı aynen). Dart/JS **ortak test vektörleri**
      (`apps/app/test/fixtures/project_match_parity.json` — Dart yarısı OPH-222'de).
- [x] Onarım turu: Ajv hatası → hata metniyle TEK yeniden deneme → hâlâ bozuksa
      `AI_EXTRACTION_INVALID` + arayüzde "transkripti Inbox'a kaydet" teklifi (app
      OPH-224'te); onarımlı çıkarım İKİ usage satırı yazar (ikisi de gerçekleşti);
      422'de log satırı YOK (log insana ulaşan önerileri kaydeder).
- [x] Testler: tablo-güdümlü TR/EN sözler — çok görevli tek cümle ("şu şu şu işler" →
      N satır), göreli tarihler, bilinmeyen proje, geçmiş tarih, boş başlık reddi;
      onarım turunun tam akışı sahte sağlayıcıyla; parite fikstürü; karar ucu
      idempotens/409/sahiplik; entegrasyonda JSON kolon gidiş-dönüşü.

### OPH-220 — Flutter: AI ayarları + onam ekranı

_(✅ 2026-07-30 — `features/ai/` iskeleti kuruldu (data/ui/providers). aiStatusProvider localKv önbellekli (404 = disabled, çevrimdışı son-bilinen doğru); ekranlar için AiSettingsCard (AppleCalendarCard sonrası, disabled'da tamamen gizli) + /settings/ai (bağlantı listesi ••••son4, ekle akışı: sağlayıcı seç → ONAM → anahtar/baseUrl → connect, model/kullanım OPH-221'de daha da; MCP kartı instance /mcp URL + kopyala). Onam cihaz-yerel (localKv per user+provider) + create'ta consentAcknowledged:true kalıcı iz; ensureAiConsent kapısı; Gemini AMBER uyarı. GoogleCalendarCard kalıbı birebir (_guard/ApiException). FakeApi'ye _ai handler + seedAiConnection. 8 widget testi + extraction_test ai grubu (en+tr).)_

- [x] Ayarlar → "Yapay zeka": sağlayıcı bağla (BYOK — anahtar alanı, `…son4` gösterimi,
      bağlantı testi düğmesi dürüst hatayla), model seçimi (sohbet/hızlı), kullanım
      sayacı (`ai_usage_events` özetinden: bu ay istek/token), bağlantıyı kaldır.
- [x] **Onam ekranı (ilk kullanımda, sağlayıcı başına):** neyin cihazdan çıktığı
      (dahil ettiğin görev/not metni, ses TRANSKRİPTİ — ses değil), anahtarın nerede
      durduğu (şifreli, sunucuda), sağlayıcının saklama/eğitim duruşu **tek dürüst
      cümleyle** (Anthropic 7 gün/eğitim yok; OpenAI 30 gün/eğitim yok; **Gemini
      ücretsiz katman verinle eğitir — sarı uyarı**; Ollama "kendi sunucunda kalır").
      Onamsız hiçbir AI yüzeyi açılmaz (widget testi).
- [x] Apple Kas 2025 / Play Nis 2026 üçüncü-parti-AI veri paylaşımı beyanlarıyla hizalı
      metin (mağaza formu notları STORE-LISTING'e).
- [x] i18n: `ai.settings.*`, `ai.consent.*` (en+tr); tasarım DESIGN §24.
- [x] Testler: onam kapısı; anahtarın maskeli gösterimi; yapılandırılmamış durumda
      yüzeylerin yokluğu; Gemini uyarısının varlığı.

### OPH-221 — AI bubble (önce metin) + akış render'ı

_(✅ 2026-07-30 — drift **v15** (`ai_messages`, AlarmEvents emsali cihaz-yerel ring buffer `kAiMessageLimit=200`; migration_test v15 + DROP ladder + user_version 15); `showAwSheet` + `AwSheetSurface/AwSheetTile` `widgets/`e çıkarıldı (create sheet typedef ile aynı satırları paylaşır — DESIGN §24 AI5). Bubble kök-navigator opak sheet; **saf** `AiBubbleMachine` (composing/listening/reviewing/thinking/streaming/error/offline/unconfigured) + controller (impure kenarlar `_disposed` korumalı — Notifier dispose sonrası state yazımı UnmountedRefException verir, ders). `AiStreamClient` dikişi: `DioAiStreamClient` (dio ResponseType.stream + elle SSE satır ayrıştırıcı + CancelToken; kapatınca upstream kesilir + cancel POST), `syncTestOverrides`a `aiStreamClient` + `ScriptedAiStreamClient`. `ai_context_builder` **SAF** (T0/T1/T2, ≤50 satır, chars/4 bütçe, `external_share` çerçevesi; toJson yalnız tier/source/id/text). **`AiText`** sınırlı render: HTML asla widget, http linkler tıklanamaz düz metin, yalnız `alliswell://` `awRouteForUri`den geçen çip (background-action inert — exfil-tap bacağı yok). Kodun öğrettiği: bir FutureProvider tembel — `send()`te workspace `.value` null olabilir, `await workspacesProvider.future` gerekti. **App 690 test** (662+28), analyze + i18n temiz. Onay kartı OPH-222'de.)_

- [x] `features/ai/ui/ai_bubble.dart` — DESIGN §24 sözleşmesi: **opak içerik yüzeyi**
      (cam yalnız krom), alt sayfa/overlay; durumlar: boş (metin alanı + mik anahtarı),
      düşünüyor, **token akışı** (durdur düğmesi canlı), hata (`status_views.dart`
      kalıbı + yeniden dene), çevrimdışı ("AI bağlantı ister" + transkripti Inbox'a
      kaydet).
- [x] `AiStreamClient` dikişi (OPH-217) — iptal bubble kapatınca upstream'i keser;
      "bağlam çipi" her mesajda **neyin gönderildiğini** açar (T0/T1/T2 paketi —
      güven + hata ayıklama, AI.md §7).
- [x] drift: `ai_messages` cihaz-yerel tablo (bubble geçmişi, budanabilir) — **v14,
      migration adımıyla** (belgelenmiş drift tuzağı); senkron varlık DEĞİL (karar
      yazılı).
- [x] Bağlam paketleyici `ai_context_builder.dart` **saf fonksiyon**: T0 (yerel ayar,
      TZ, proje adları, sayımlar) / T1 (bugün+geciken dilimleri ≤50 satır — açıklamasız)
      / T2 (soru → ADR-0013 fold aramasıyla top-K alıntı); bütçe ~4–8K girdi tokenı,
      görünür kırpma işareti. Ek baytları, presigned URL'ler, başka kullanıcı verisi
      **asla**.
- [x] Testler: durum makinesinin golden widget testleri; paketleyicinin saf testleri
      (bütçe kırpması, dilim sınırları); iptal akışı; kontrast iki temada.

### OPH-222 — Onay kartı → local-first commit (+ quick-add "sihirli ayrıştır")

_(✅ 2026-07-30 — `ai_confirm_card.dart` create sheet satırlarını yeniden kullanır (AwSheetTile/ProjectPickerField), satır-başına aç/kapa, `dueAtSource` çözülen değerin yanında ("yarın → 30 Tem"). Proje çözümü **bizde**: `project_match.dart` (fold + exact→prefix→contains, parite fikstürünün Dart yarısı — 11 vaka JS ile birebir). Accept: etkin her satır `TaskStore.create` + `addChecklistItem` (AI REST'e DOKUNMAZ — outbox tek yol); karar raporu `ai_action_reporter` (localKv kuyruğu, anında dene, resume'da drain — idempotent uç güvenli retry). **Undo 3sn** oluşturulanları store.delete ile geri alır (create+delete outbox). **Reject HİÇBİR ŞEY yazmaz** (pushedMutations boş assert'i). Quick-add ✨ binicisi (yalnız configured'da) → aynı extract → AYNI kart. FakeApi `_ai` extract/actions. **App 704 test** (690+14), analyze + i18n temiz. Onay-kartı-atlanamaz v1 değişmezi korunuyor.)_

- [x] Öneri kartı: oluşturma sheet'inin alan satırlarının AYNISI yeniden kullanılır
      (`core/date_input.dart` tek tarih yolu — OPH-191 dersi; etiket chip-input; proje
      seçici + "+ Proje ekle"); her görev satırı ayrı aç/kapa; `dueAtSource` ham ifade
      alanın yanında ("yarın 15:00 → 30 Tem 15:00").
- [x] **Commit yolu = `TaskStore`:** kabul edilen her görev optimistic satır + outbox
      olarak yazılır (AI REST'e DOKUNMAZ — ADR-0016'nın "ikinci yazma yolu yok" ilkesi);
      hatırlatma sunucunun mevcut reconcile'ına düşer; çevrimdışı kabul çalışır, sonra
      senkron olur (test).
- [x] Reddedilen öneri outbox'a HİÇBİR ŞEY yazmaz (test); kabul `ai_action_log`'a
      düşer; kabul sonrası geri alma DESIGN §19 kalıbı.
- [x] **Bonus yüzey (ucuz binici):** quick-add alanına "✨ ayrıştır" — yapıştırılan
      uzun metni aynı çıkarım ucundan geçirir, aynı onay kartı (yeni UX icat edilmez).
- [x] i18n: `ai.confirm.*`, `ai.parse.*`; testler: çok görevli kartın kısmi kabulü;
      düzenle-sonra-kabul; çevrimdışı kabul + sonra senkron; sihirli ayrıştır ucu.

### OPH-223 — Basılı-konuş FAB + cihaz-üstü STT (cihaz taskı)

_(✅ 2026-07-30 kod tarafı; **cihaz turu STATE kuyruğunda** — gerçek mikrofon + izin diyalogları cihaz ister. ADR-0023 yazıldı; `speech_to_text ^7` + `receive_sharing_intent` (1.8 SPM-only → `<1.8` CocoaPods'a sabitlendi). **Saf `ai_ptt_machine.dart`** (idle→pressed→recording→**locked (parmak kalkınca — Mahir kuralı)** | sola ≥80px cancel; tap<250ms composing; stop/VAD finalize) — 7 test. `SttController` dikişi + `SpeechToTextController` (onDevice tercihli) + `FakeSttController`; `sttProvider` nullable, syncTestOverrides'a eklendi. **`AiFab`** (Listener + makine + haptik; bottom-LEFT); home_shell iki-FAB Row (`_fabBar` + spaceBetween/centerFloat; AI kapalıysa aynen eski tek FAB). Info.plist mikrofon+konuşma gerekçeleri, AndroidManifest RECORD_AUDIO. **Test-double kararı:** FakeApi `aiEnabled` VARSAYILAN FALSE — 6 mevcut akış (14 FAB assert'i) perturbe olmasın; AI testleri `seedAiConnection`/`aiEnabled=true` ile opt-in. **App 727 test** (704+23: machine 7, FAB 3, + i18n voice), analyze + i18n temiz.)_

- [x] **ADR-0023 (ilk iş):** `speech_to_text` + `receive_sharing_intent` (OPH-225'le
      ortak) + iOS Share Extension hedefi — yeni bağımlılık kategorisi + pbxproj sapması
      (ADR-0010 emsali).
- [x] Sol-alt **AI FAB** (mevcut sağ-alt oluşturma FAB'ı YERİNDE kalır — DESIGN §24
      yerleşim kuralı; geniş ekranda rail altı giriş, basılı-konuş mobil-öncelikli).
- [x] **Jest makinesi (DESIGN §24'te çizili):** ≥250 ms basılı tut → bubble açılır,
      dalga formu + **canlı partial transkript**; sola ≥80 px kaydır → iptal (haptik);
      **parmağı kaldır → kayıt KİLİTLİ sürer, bubble açık kalır** (Mahir'in kuralı —
      kaldır-kilitle, WhatsApp'ın yukarı-kaydır kilidinden basit); durdur/2 sn sessizlik
      (VAD) → transkript; dokunma yolu: FAB'a TEK dokunuş bubble'ı metin+mik modunda
      açar (erişilebilirlik + masaüstü — jest asla tek yol değil, D2/K3).
- [x] STT: `speech_to_text` (iOS SFSpeech/SpeechAnalyzer, Android SpeechRecognizer) —
      cihaz-üstü, ücretsiz, çevrimdışı çalışabilir; **Ayarlar gerçek `locales()`
      sonucunu ve cihaz-üstü aktifliğini gösterir** (dürüst durum); dil çipi: uygulama
      dili + söz başına TR/EN geçişi; transkript HER ZAMAN düzenlenebilir (düşük kalite
      sigortası). Sunucu-STT (OpenAI $0.003/dk) v1.5 anahtarı — park.
- [x] İzin akışları: mikrofon + konuşma tanıma (iOS ikili izni) dürüst gerekçe
      metinleriyle; reddedilirse FAB metin moduna düşer.
- [x] Testler: jest makinesi saf durum-geçiş testleri; izin reddi düşüşü; VoiceOver/
      TalkBack yolu; **gerçek iPhone + Android turu:** Türkçe söz → doğru onay kartı
      (STATE cihaz kuyruğuna).

### OPH-224 — Ses → çıkarım kablolaması + çevrimdışı düşüş

_(✅ 2026-07-30. Kontrolör STT kenarları: `startListening`/`stopListening`/`cancelListening` (nullable `sttProvider` — null = ses yok → dürüstçe metin moduna düş) + `_finalizeTranscript` → saf makine `finalizeTranscript` (transkript inputa, faz=`reviewing`, **otomatik gönderim YOK** — AI9). **FAB→bubble paylaşımlı provider:** FAB'ın `startStt`/`finalizeStt`/`cancelStt` aksiyonları artık `aiBubbleControllerProvider`'ı sürüyor (aynı örnek); bubble'ın `initState`'i canlı ses oturumunu ezmiyor. Tek nokta yönlendirme `submitReview()`: `extractUtterance` → `AiRouteTasks` (widget bubble'ı pop edip onay kartını açar) · `AiRouteAnswer` (satır-içi, saf makine `answer` iki turu da işler) · `AiRouteNone` (`ai.voice.noIntent` ipucu) · `AiRouteOffline` (transkript korunur → **`ai-save-inbox` tek dokunuş** → `captureToInbox`, `status:'inbox'`, ilk satır 140'ta kırpılır). Bubble UI: dinleme yüzü (`ai-partial` canlı) + Stop/Vazgeç, `reviewing`'de input senkronu + odak, offline/unconfigured yüzünde Inbox butonu. i18n `ai.voice.{cancel,mic,savedToInbox,noIntent}` (+`ai.bubble.{stop,saveToInbox}` yeniden kullanıldı). **App 728 test** (wiring 4 + voice-ui 4 + machine `answer` 1), analyze + i18n temiz. Gecikme _sayıları_ eklenti/model çalışma-zamanı → cihaz turunda ölçülür; affordance'lar yerinde.)_

- [x] **Niyet kapısı tek yolculukta:** transkript hızlı-sınıf modele gider; şemadaki
      `intent` alanı sınıflandırır — `create_tasks` ise aynı istekte çıkarım da biter
      (ikinci tur yok), `answer` ise bubble akışa geçer; Dart'ta sezgisel YOK (boş
      transkript hariç).
- [x] Çevrimdışı / AI yapılandırılmamış: transkript korunur + **tek dokunuşla Inbox'a
      yakalama** ("sesle yakala, sıfır AI ile bile çalışır" — ürünün kendi GTD dili;
      §12.6 semantiği).
- [x] Gecikme bütçeleri (DESIGN §24): partial <300 ms ritim; durdurma→final ≤500 ms;
      ilk token <2 sn (hızlı sınıf); kart dolu <4 sn — her durumun görünür affordance'ı
      (dinleme/düşünme/gözden-geçirme yüzleri; _sayısal_ ölçüm cihaz turunda).
- [x] Testler: sahte sağlayıcıyla uçtan uca "Ahmet projesine yarın şu iki işi ekle…" →
      2 görevli kart, yarın@varsayılan-saat, proje önseçili; çevrimdışı → Inbox yolu;
      `answer` niyeti → akış.

### OPH-225 — Paylaşım hedefi: her metni AllisWell'e paylaş (cihaz taskı)

_(✅ 2026-07-30 kod tarafı; **iOS uzantı pbxproj kablolaması + cihaz turu STATE kuyruğunda.** `ShareIntentSource` dikişi (`initialShare`/`shares`/`reset`) + `payloadFromMedia` (URL→text+url, text→text, dosya→null; v1 metin+URL) + nullable `shareIntentSourceProvider` (yalnız iOS/Android; web/desktop null → yüzey yok) + `FakeShareIntentSource`. `PendingSharePayload` (remember/take — bir kez tekrar; PendingDeepLink emsali) + `shareBinderProvider` (initial→remember + shares→remember). **HomeShell dersi:** binder'ı `ref.watch` ile canlı tutar + `pendingSharePayloadProvider`'ı `ref.listen` eder → payload gelince `take()` + `showAiBubble(shared:)`; shell yalnız oturumluyken mount olur → soğuk paylaşım auth restore'u YAPISAL atlatır (deep-link'in remember/replay'ine gerek yok). Bubble'da paylaşılan blok altında **5 çip**: Görev yap (extract `source:'share'` → onay kartı; offline→Inbox), Not al (`NoteStore.create` — SIFIR AI, extract'a dokunmaz), Özetle (`send(context:)` — paylaşım `external_share` fenced segment olarak gider, chat metnine değil), Soru sor (composer'a odak), **Inbox'a kaydet DAİMA**. Android `AndroidManifest` `ACTION_SEND` intent-filter (text/plain+text/html). iOS `ios/AllisWellShare/` (boş `RSIShareViewController` alt sınıfı = ağ/AI YAPISAL imkânsız, Info.plist text+URL aktivasyon, App Group entitlement) + idempotent `ios/scripts/wire_share_extension.rb` (app-extension target + embed + build settings) + SETUP.md — **pbxproj cihazda çalıştırılır** (ADR-0010 emsali; test edilmemiş pbxproj mutasyonu commit'lenmez). **App 738 test** (share 10: mapping, binder soğuk/sıcak, take-once, 5 çip, make-task→kart, take-note sıfır-AI, inbox, özetle+context, unconfigured), analyze + i18n temiz.)_

- [x] `receive_sharing_intent` (ADR-0023): Android `intent-filter` (`text/plain` +
      `text/html`), iOS **Share Extension** — uzantı AĞ VE AI İŞİ YAPMAZ (bellek
      tavanı + süre sınırı): payload'ı App Group'a yazar, host uygulamayı açar
      (OPH-182'nin App Group emsali).
- [x] Yönlendirme: paylaşım bubble'ı **"paylaşılan içerik" bloğu** önceden dolu açar
      (provenance `source="external_share"` — en sıkı çerçeveleme, AI.md §8) + eylem
      çipleri: **Görev yap** (çıkarım → onay kartı) · **Not al** (NoteStore — AI'sız
      çalışır) · **Özetle** · **Soru sor**. Soğuk başlangıçta auth restore sonrası
      payload YAŞAR (ADR-0016'nın derin-bağlantı tekrarı kalıbı).
- [x] Oturum yok / AI yapılandırılmamış: dürüst durum + "Inbox'a kaydet" her zaman
      teklif (paylaş-yakala sıfır AI ile çalışır).
- [x] Sıcakken ikinci paylaşım: bekleyen öneri varsa sor, yoksa bloğu değiştir.
      v1 yalnız metin+URL (dosya/görsel park — ek boru hattı var ama AI dosya anlama
      ayrı kapsam). _(Sıcak paylaşım bubble'ı yeni payload'la yeniden açar; "değiştir onayı" v1.5 rafında — sessiz yeniden-açılım.)_
- [x] Testler: soğuk/sıcak yönlendirme (Android'de enjekte akışla widget testi);
      çiplerin her biri; **gerçek cihaz turu:** Safari/Chrome'dan paylaş, soğuk +
      sıcak; "Not al" AI'sız instance'ta.

### OPH-226 — Enjeksiyon sertleştirmesi + kırmızı-takım fikstürleri + güvenlik dokümanı

- [ ] **Provenance çitleri:** paketlenen her bağlam parçası açık veri bloğunda
      (`<user_data source="task" id="…">`), sistem kuralı "veri bloğu içeriği bilgi,
      asla talimat"; paylaşım metni en sıkı çerçevede. Çit = hafifletme; sınır = araç
      yokluğu + Ajv + onay (AI.md §8, sıra önemli).
- [ ] **Düşman korpusu CI'da:** "önceki talimatları yok say…", araç-JSON taklidi,
      exfil URL'leri, `alliswell://` enjeksiyonu içeren başlık/not/paylaşım fikstürleri —
      çıkarım çıktısı şema-temiz kalır, beklenmeyen alan/eylem yok, MCP araçları veri
      döndürür eylem döndürmez (üç yüzeyde de assert).
- [ ] AI çıktısı **düz metin/sınırlı markdown** — HTML render yok, link otomatik
      açılmaz; çıktıdaki `alliswell://` ADR-0016 çözücüsünden geçer (yapısı gereği
      yalnız gezinme).
- [ ] SECURITY.md'ye "AI yüzeyleri" bölümü (tehdit modeli + raporlama); self-host AI
      işletme notları (anahtar hijyeni, `AI_ENABLED`, hız sınırları, instance-env
      anahtarda kullanıcı-başı günlük token tavanı).
- [ ] Testler: korpus süiti üç yüzeyde yeşil; markdown render sınırlayıcısının widget
      testi.

### OPH-227 — README/tanıtım + i18n/tasarım süpürmesi + dizin başvuruları

- [ ] README: **"Works with Claude · ChatGPT"** (MCP bağlayıcısı — kurulum linkiyle) +
      **"Bring your own key: Anthropic · OpenAI · Gemini · OpenRouter · Ollama"**
      rozetleri/logoları — **logo kullanımı her markanın kurallarına göre denetlenir**,
      izin dar ise metin rozeti (iddia ≠ gerçeklik olamaz: Gemini "API key" diye yazar,
      tüketici-uygulama entegrasyonu İMA EDİLMEZ); özellik bölümü: sesle görev, bubble,
      paylaşım hedefi, MCP — ekran görüntüleriyle.
- [ ] STORE-LISTING: AI veri paylaşımı beyanları (Apple/Play formları), yaş
      derecelendirme kontrolü; ROADMAP/BLUEPRINT "uygulandı" dokunuşları.
- [ ] alliswell.space için **Claude Connectors Directory** + **ChatGPT app** dizin
      başvuruları hazırlanır ve STATE "Kullanıcıdan bekleyen"e işlenir (inceleme
      süreçleri dış taraf — DoD'yi kilitlemez).
- [ ] Kapanış süpürmesi: `check:i18n` (tüm `ai.*` anahtarları en+tr), kontrast
      FAILURES: 0 (bubble/kart/onam yüzeyleri), `lint`/`format:check`/`check:no-ts`,
      app + API tam süit.

**Epic 20 DoD:** her task kendi testleriyle; ADR-0019 + (implementasyonda) ADR-0022/0023
kabul edilmiş; AI.md canlı tutulmuş; **prod SSE curl kanıtı** STATE'te; düşman korpusu
CI'da kalıcı; cihaz turu (223, 225) STATE cihaz kuyruğunda; README iddiaları birebir
gerçek → **v0.9.0**. Modele v1'de yazma aracı verilmediği ve silmenin AI'ya kalıcı
kapalı olduğu bu epic'in değişmezidir — gevşetme ancak yeni ADR'yle.

---

## Backlog / v2 parking lot

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Timeline view; smart lists/filters DSL; global single-screen search (per-screen search
  shipped in Epic 15; kanban shipped in Epic 15 — OPH-168).
- Search v2: FTS5 external-content upgrade (bm25 ranking — ADR-0013 upgrade path),
  server-side fold columns for a first-class API `?q=`, file-name search in Dosyalar.
- Task description v2: OG link previews (needs a server-side unfurl proxy), rich formatting.
- Tag management v2: merge tags, usage counts, tag colors in board/list filters.
- Files v2: desktop drag-to-move into folders (target-picker sheet is v1), bulk move/delete.
- Attachments v2: multipart >5 GB uploads, thumbnails/transcodes, quota enforcement, local
  binary cache for offline viewing, camera capture, inline video playback, public share links
  (v1 shipped in Epic 14 — ATTACHMENTS.md §11).
- **Round 9 park kuyruğu:** sunucu tarafı zil sesi dönüştürme (ffmpeg → ≤30 sn caf, mp3
  yüklemelerini iOS bildiriminde kullanılabilir kılar — OPH-181 bilinçli olarak
  doğrulama+dürüst mesajla yetiniyor); **watchOS companion hedefi** (özel long-look +
  `WKInterfaceDevice` haptikleri + complication — kararı OPH-183 veriyor); cihazlar arası
  **sunucu tarafı ayar deposu** (hatırlatıcı profili + tarih biçimi bugün cihaz-yerel,
  `notification_privacy` kalıbıyla aynı); alarm günlüğünün sunucuya raporlanması.
- **Round 10 park kuyruğu (kararı OPH-195 verir):** alt görevler (`parent_task_id` —
  şema, API ve kaskadlı silme hazır, arayüz yok), ~~**tekrarlayan görevler**~~
  (**park bitti — round 12'de Epic 19 oldu**, OPH-204…208; `repeat_rule` kolonunun
  kaderi ADR-0020'de), görev rengi
  (`tasks.color_rgb` — widget kullanıyor, kullanıcı seçemiyor), **elle sıralama**
  (`sort_order` sıralamada kullanılıyor ama sürükleme yok), süre alanları
  (`estimated_minutes`/`actual_minutes`), proje ikonu/başlangıç-bitiş tarihi;
  Tamamlananlar ekranında arama + `cancelled`/`archived` sekmesi; Pano kartlarında
  kaydırarak silme (yatay pager jest çakışması); sunucu tarafı "tamamlananlar" ucu
  (bugün tamamen yerel replikadan okunuyor).
- **Round 11 park kuyruğu — Hızlı Erişim (OPH-196'da kesinleşti, 2026-07-29):** Android
  sistem-geneli overlay düğmesi (SYSTEM_ALERT_WINDOW — ayrı izin ve istila, kendi turu;
  Messenger bile chat head'i Android 11'de Bubbles API'sine taşıdı, yani "uygulama dışı
  yüzen düğme" artık OS'un kendi kanalı üzerinden yapılan bir iştir); iOS'ta uygulama dışı
  yüzen düğme (OS üçüncü partiye izin vermez — yazılı sınır); kısayol klasörleri / iç içe
  liste (tek 50'lik liste için ikinci hiyerarşi seviyesi; Slack'in kendi önerisi de "3–5
  bölüm"); dış linklerde OG başlık çekme (unfurl proxy'ye bağlı); workspace-paylaşımlı ekip
  kısayol listesi (ADR-0018 "shared team list" alternatifi — additive, v2); emoji-picker
  paketi (tam ızgara — ADR gerektirir, gerekçesi yok); **kısayol renginde sınırsız palet**
  (`_ColorGridDialog`'un tüm `Colors.primaries` seti — DESIGN §23 Q8a: sınırsız fille
  kontrast garanti edilemiyor, kısayolda yalnız 10'luk palet sunuluyor); **yüzen düğme
  opaklık slider'ı** (AssistiveTouch'ta var; bizde tek anahtar + %40 sabiti yeterli sayıldı);
  kısayol satırından hedefi yeniden adlandırma (kısayol adı hedefin adı değildir — §4.12).
- **Round 11 park kuyruğu — AI (gerekçeler TASKS Epic 20 + [AI.md](AI.md)):**
  abonelik-OAuth entegrasyonu (üç sağlayıcıda da kapalı/bekleme listesi — üç ayda bir
  yeniden bakılır; `auth_mode='oauth_subscription'` rezerve); sohbette yazma araçları
  v1.5 (`complete_task`/`reschedule_task` onay-kapılı; **silme kalıcı olarak hariç**);
  yüksek-güvende onay kartını atlama anahtarı (v1.5 opt-in); senkron sohbet geçmişi
  (`conversation` varlığı — gizlilik duruşu değişikliği, bilinçli karar ister);
  sunucu-STT varsayılanı (OpenAI/Gemini ses — v1.5 ayarı); gerçek-zamanlı sesli sohbet
  (speech-to-speech); doğal-dil filtreleri → akıllı liste DSL'i (önce DSL); akıllı
  zamanlama (takvim boş/dolu akıl yürütmesi); otomatik etiket/öncelik önerisi;
  haftalık AI özet e-postası; barındırılan ücretli "AllisWell AI" katmanı (ürün kararı);
  paylaşımda dosya/görsel anlama; günlük/haftalık AI incelemesi + not özetleme +
  toplantı-notu→görevler (v1.5 adayları — Epic 19 çıkarım ucunu yeniden kullanır).
- Import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), release packaging (Docker image publish, F-Droid/TestFlight).
