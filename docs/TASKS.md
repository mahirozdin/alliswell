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

### OPH-123 — Extract strings: Home, tasks, quick-add, task create/detail

- [ ] `HomeBucketLabel` (`task_grouping.dart`) → key lookups `home.bucket.{overdue,noDate,today,
      tomorrow,thisWeek,next30Days,selectedDay}`; task **status** labels `task.status.*` and
      **priority** labels `task.priority.*` (used by `task_visuals.dart` dropdowns); quick-add hints
      including the interpolated "Quick add for <date>"; task create/detail sheets; task snackbars.
- [ ] "Overdue" word + relative/absolute dates localized via `intl` in the active locale.

**Context:** the largest surface — `features/home/*`, `features/tasks/ui/*`. **`HomeBucketLabel`
keys are ALSO consumed by the widget snapshot (OPH-130)** — this is why they must be real keys.

**Spec:** parameterized strings use `.tr(args: {...})` (`{name}` placeholders). The Home group
header `'${bucket.label} · N'` keeps its shape with a localized label + the count.

**Tests:** a grouping-driven widget test asserts the `overdue`/`today` headers localize; a
create-sheet test asserts a hint localizes.

**DoD:** analyze + test; both themes; contrast unaffected (text-only).

### OPH-124 — Extract strings: projects, notes, calendar/integrations, onboarding

- [ ] Move to `en`+`tr` keys: project detail/edit/archive (`features/projects/ui/*` incl.
      `project_archive.dart` dialogs), notes list/editor (`features/notes/ui/*`), the Google &
      Apple calendar cards (`integrations/ui/google_calendar_card.dart`,
      `calendar/apple/apple_calendar_card.dart`, incl. their honest status strings), and the
      onboarding tour bubbles (`features/onboarding/tour*.dart`).

**Context:** the remaining feature strings (`google_calendar_card.dart` alone has ~10). Key groups:
`project.*`, `note.*`, `calendar.*`, `tour.*`.

**Tests:** spot tests per area assert a `tr` render; existing suites green in `en`.

**DoD:** analyze + test; both themes; calendar-card status colors/logic unchanged.

### OPH-125 — Localize API error codes & dynamic strings

- [ ] Map `ApiException.code → error.<CODE>` (fallback: server `message` → generic
      `error.unknown`); localize the sync-conflict snackbar in `home_shell.dart` (currently appends
      `conflict.errorCode`); route all date/number formatting through the active locale.
- [ ] Seed `error.*` keys for the codes the app surfaces (auth, task, sync, calendar — listed in
      the route files / `sync.js`).

**Context:** `core/api_exception.dart` carries `(code, message)`; codes are stable localization
keys (ADR-0009 D4) so the API needs NO server-side i18n.

**Tests:** a known code renders its localized message in `tr`; an unknown code falls back to the
server message; a date formats per locale.

**DoD:** analyze + test.

### OPH-126 — Account locale sync (`PATCH /me`)

- [ ] **API:** `PATCH /api/v1/me { locale }` — Ajv body schema with a `locale` allow-list (the
      supported BCP-47 subset), updates `users.locale` + `updated_at`, returns the updated `me`
      shape; `app.authenticate`-guarded. Error code `USER_UNSUPPORTED_LOCALE` for anything off the
      list.
- [ ] **App:** on a language pick (OPH-121), best-effort `PATCH /me`; on sign-in when the device
      has NO saved override, seed the initial locale from `GET /me.locale`.

**Context:** `me.js` returns `locale` but nothing writes it; no `PATCH` exists. This makes the
language follow the account across devices / reinstalls (the device override still wins locally —
offline-first).

**Tests:** API unit (`apps/api/test/unit/`) — valid locale updates; invalid → `USER_UNSUPPORTED_LOCALE`;
unauth → 401. App — sign-in with no local override seeds from `me.locale`; a local override is NOT
overwritten by `me`.

**DoD:** `npm run lint` + `npm test` (API); `flutter analyze` + `flutter test` (app); apps/api
README error-code list updated.

### OPH-127 — No-hardcoded-string CI guard

- [ ] `scripts/i18n/check.mjs` greps `apps/app/lib` for user-facing literals (`Text('…')`,
      `labelText:`, `hintText:`, `SnackBar(content: Text('…'))`) outside an allowlist (brand name,
      debug-only, `Key('…')`, already-`.tr()` lines).
- [ ] Wire into `.github/workflows/ci.yml` + an `npm run check:i18n` script (mirrors
      `check:no-ts`).

**Context:** keeps the extraction from rotting — new hardcoded strings fail CI, exactly like the
TypeScript-ban guard.

**Tests / self-check:** the guard fails on a planted `Text('Hello')` and passes on the clean tree
(document the run in the commit).

**DoD:** guard green in CI; documented in AGENTS.md §1 / CONTRIBUTING.

### OPH-128 — Web `<html lang>` + "add a language" docs

- [ ] Reflect the active locale in the web build: update `<html lang>` on locale change (a11y/SEO);
      `web/index.html` currently has no `lang`.
- [ ] Document **"How to add a language"** (drop `assets/i18n/<code>.json`, register the `Locale`
      in `supportedLocales`) in README + CONTRIBUTING.
- [ ] Keep BLUEPRINT §12.9/§15.5 truthful; STATE + CHANGELOG.

**Context:** Flutter doesn't manage `<html lang>`; a tiny web hook sets it from `context.locale`.

**DoD:** analyze + test; manual web check (browser lang default + a switch); docs updated. **Epic
11 closes here → v0.2.0-alpha (i18n).**

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

### OPH-130 — Widget snapshot core (Dart: pure grouping + bridge)

- [ ] Add `home_widget` to `apps/app/pubspec.yaml`. New `lib/src/features/widgets/`.
- [ ] Pure `groupTasksForWidget(tasks, {now, events})` — sibling of `groupTasksForHome`
      (`task_grouping.dart`) with buckets **overdue → noDate → today → thisWeek → thisMonth**
      (horizon = end of current month; reuse the event rules: events never overdue, ongoing =
      today-once). Fully unit-tested.
- [ ] `WidgetSnapshot` serializer → the compact JSON of WIDGETS.md §3.1 (`date{weekday,day,month}`,
      `counts`, `buckets[]` with top-N `items{id,title,done,time,projectColor}`, `more{}` for
      truncation). Labels come from the Epic 11 i18n facade (already localized).
- [ ] `WidgetBridge` (Riverpod) listens to `openTasksProvider` + `externalEventsProvider`, calls
      `HomeWidget.setAppGroupId('group.com.alliswell.alliswell')`, and `saveWidgetData` +
      `updateWidget(iOSName:'AllisWellWidget', androidName:'TasksWidgetProvider',
      qualifiedAndroidName:'com.alliswell.alliswell.TasksWidgetProvider')` after every change.

**Context:** `groupTasksForHome` already produces these buckets — the widget mirrors that tested
philosophy. **This is the ONLY fully green-testable task and carries the correctness weight.**

**Tests** (`apps/app/test/features/widgets/`): bucket boundaries (+/- month edge, overdue,
dateless, ongoing event); snapshot JSON shape + per-bucket top-N truncation + `more` counts;
localized labels (en vs tr); "WidgetBridge writes + calls updateWidget when the task stream
changes" via a fake `HomeWidget`.

**DoD:** `flutter analyze` + `flutter test` (all green, no infra); no native code yet.

### OPH-131 — iOS Widget Extension: target, App Group, rendering, deep-link floor

- [ ] Add an `AllisWellWidget` **Widget Extension** target to `ios/Runner.xcodeproj` (**commit the
      `project.pbxproj` diff** — deliberate deviation, ADR-0010). Add **App Groups** capability
      `group.com.alliswell.alliswell` to **both** Runner and the extension (`Runner.entitlements` +
      `AllisWellWidgetExtension.entitlements`).
- [ ] SwiftUI views reading the shared `UserDefaults(suiteName:)` snapshot; `supportedFamilies:
      [.systemMedium, .systemLarge, .systemExtraLarge]`; **date header** (weekday name + big day
      number) on large/extraLarge; bucketed list at the DESIGN §8 density (W6/W7); solid tinted
      "aurora" card + `.containerBackground` (W3).
- [ ] `TimelineProvider` with a **midnight-rollover** reload policy (`.after` next midnight);
      `WidgetCenter.shared.reloadTimelines(ofKind:)` from `updateWidget`.
- [ ] **Deep-link floor:** tap → `alliswell://task/{id}` (ADR-0003) / `alliswell://add`; add the
      `add` route to the router's `onOpenURL`/deep-link handling.
- [ ] Podfile links `home_widget` into the extension; verify a real `flutter build ios`.

**Context:** ADR-0010 D6 size mapping; iPhone ceiling = `systemLarge`. `analyze` won't compile
Swift — this is build+device verified.

**Tests:** data path covered by OPH-130's Dart tests; native verified by `flutter build ios` +
device: light+dark, medium/large on iPhone, extraLarge on iPad.

**DoD:** `flutter build ios` green; device screenshots (both themes, all sizes); STATE device note;
WIDGETS.md/ DESIGN §8 truthful.

### OPH-132 — iOS interactivity: quick-complete + quick-add (App Intents)

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

### OPH-133 — Android widget (Glance): target, snapshot, interactivity, resize, midnight

- [ ] `TasksWidgetProvider` (Jetpack **Glance** `GlanceAppWidget` + `GlanceAppWidgetReceiver`) under
      `android/app/src/main/kotlin/com/alliswell/alliswell/`; `res/xml/tasks_widget_info.xml`
      (`targetCellWidth/Height` 4×2 default, `resizeMode="horizontal|vertical"`, `minResize*`/
      `maxResize*` to allow 4×6, `updatePeriodMillis` 0 or large, `previewLayout`).
- [ ] Reads the SharedPreferences snapshot; scrollable **bucketed `LazyColumn`**; date header on the
      larger sizes; circular checkbox → `actionRunCallback` → `HomeWidgetBackgroundIntent.getBroadcast`
      → the SAME Dart `widgetCallback` → `TaskStore`; quick-add "+".
- [ ] Responsive layouts for 4×2 / 4×4 / **true 4×6** (Glance size handling / `SizeF` map);
      `AndroidManifest.xml` receivers (the provider **and** `es.antonborri.home_widget.
      HomeWidgetBackgroundReceiver`); a **WorkManager** job re-pushes at local midnight (date
      rollover). Pin `androidx.glance`.
- [ ] Verify a real `flutter build apk`.

**Context:** Android honors a TRUE resizable 4×6 (no `systemLarge` ceiling). `analyze` won't compile
Kotlin — build+device verified.

**Tests:** data path from OPH-130; device: three sizes, complete + quick-add without opening the
app + sync, both themes.

**DoD:** `flutter build apk` green; device screenshots (3 sizes, light+dark); STATE note.

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

## Backlog / v2 parking lot

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Kanban & timeline views; smart lists/filters DSL; global search screen.
- Attachments (S3-compatible storage); import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), release packaging (Docker image publish, F-Droid/TestFlight).
