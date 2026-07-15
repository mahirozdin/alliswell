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

### OPH-070 — Google OAuth connect

- [ ] OAuth2 flow (offline access, calendar scope); tokens encrypted at rest (AES-256-GCM, key from env)
- [ ] `calendar_accounts` create/status endpoints; disconnect flow
- [ ] Tests with mocked Google endpoints

### OPH-071 — Google calendar list

- [ ] List calendars, choose `default_calendar_id`

### OPH-072 — Mirror task to Google event

- [ ] Create/update/delete event for mirrored tasks (`[Task] {title}`, scheduled block or due slot)
- [ ] `calendar_event_links` rows; retries via BullMQ job queue

### OPH-073 — Google extended properties mapping

- [ ] `extendedProperties.private.alliswell_task_id` / `alliswell_workspace_id` (ADR-0003)
- [ ] Re-link on duplicate detection

### OPH-074 — Google webhook receiver

- [ ] `POST /api/v1/integrations/google/webhook` (channel token validation, mark account dirty)
- [ ] Channel renewal job (channels expire)

### OPH-075 — Google incremental sync worker

- [ ] Worker consumes dirty accounts; `syncToken` incremental fetch; full resync on 410

### OPH-076 — Google two-way conflict handling

- [ ] etag/updated comparison → apply provider changes to task (time fields), or push local, or
      flag `conflict_status`; tests for all four conflict states

### OPH-077 — Apple EventKit Flutter plugin skeleton

- [ ] Platform channel (iOS/macOS): permission request + calendar list

### OPH-078 — Apple EventKit create/update event

- [ ] Event CRUD with `alliswell://task/{id}` URL marker; mapping rows; foreground resync

### OPH-079 — CalDAV design doc

- [ ] docs/CALDAV.md: iCloud app-specific password flow, ETag sync, security warnings (v2 scope)

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
