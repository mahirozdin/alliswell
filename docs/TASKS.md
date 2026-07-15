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

### OPH-077 — Apple EventKit Flutter plugin skeleton

- [ ] Platform channel (iOS/macOS): permission request + calendar list

### OPH-078 — Apple EventKit create/update event

- [ ] Event CRUD with `alliswell://task/{id}` URL marker; mapping rows; foreground resync

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

### OPH-094 — Public roadmap

- [ ] ROADMAP.md generated from phases; link from README; GitHub Projects note

### OPH-095 — First release notes

- [ ] v0.1.0 tag notes; release automation (GitHub Actions release workflow)

---

## Backlog / v2 parking lot

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Kanban & timeline views; smart lists/filters DSL; global search screen.
- Attachments (S3-compatible storage); import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), release packaging (Docker image publish, F-Droid/TestFlight).
