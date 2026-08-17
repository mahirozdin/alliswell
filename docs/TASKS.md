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
**Kalan tek şey cihaz matrisi** (yukarıdaki açık kutu) — kullanıcının telefonunu **[KAPATILDI 2026-08-12 — sahibin kararı, agent ölçümü değil.]**
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

_(✅ 2026-07-30 kod tarafı; **iOS uzantı pbxproj kablolaması + cihaz turu STATE kuyruğunda.** `ShareIntentSource` dikişi (`initialShare`/`shares`/`reset`) + `payloadFromMedia` (URL→text+url, text→text, dosya→null; v1 metin+URL) + nullable `shareIntentSourceProvider` (yalnız iOS/Android; web/desktop null → yüzey yok) + `FakeShareIntentSource`. `PendingSharePayload` (remember/take — bir kez tekrar; PendingDeepLink emsali) + `shareBinderProvider` (initial→remember + shares→remember). **HomeShell dersi:** binder'ı `ref.watch` ile canlı tutar + `pendingSharePayloadProvider`'ı `ref.listen` eder → payload gelince `take()` + `showAiBubble(shared:)`; shell yalnız oturumluyken mount olur → soğuk paylaşım auth restore'u YAPISAL atlatır (deep-link'in remember/replay'ine gerek yok). Bubble'da paylaşılan blok altında **5 çip**: Görev yap (extract `source:'share'` → onay kartı; offline→Inbox), Not al (`NoteStore.create` — SIFIR AI, extract'a dokunmaz), Özetle (`send(context:)` — paylaşım `external_share` fenced segment olarak gider, chat metnine değil), Soru sor (composer'a odak), **Inbox'a kaydet DAİMA**. Android `AndroidManifest` `ACTION_SEND` intent-filter (text/plain+text/html). iOS `ios/AllisWellShare/` (boş `RSIShareViewController` alt sınıfı = ağ/AI YAPISAL imkânsız, Info.plist text+URL aktivasyon, App Group entitlement) + idempotent `ios/scripts/wire_share_extension.rb` + SETUP.md. **pbxproj BAĞLANDI ve DERLENDİ (2026-07-30):** script çalıştırıldı, `flutter build ios --release` → `Runner.app/PlugIns/AllisWellShare.appex` (sürüm 0.9.0/11 uygulamayla eşleşiyor). Script'i çalıştırmak **dört ayrı kusur** ortaya çıkardı — hiçbiri kod okuyarak görünmezdi: (1) base xcconfig yokluğu → `MARKETING_VERSION` BOŞ → App Store reddi (uzantı sürümü uygulamayla aynı olmalı); üç `Flutter/AllisWellShare*.xcconfig` yazıldı, widget'tan farkı **hem** pod xcconfig'ini **hem** `Generated.xcconfig`'i include etmesi; (2) `Flutter` grubu sanal → dosya referansı tam göreli yol taşımalı, çıplak ad "Unable to open base configuration reference file" veriyor; (3) pod'u uzantıda derlemek imkânsız — `addApplicationDelegate` app extension'da yasak; Podfile `inherit! :search_paths` ile iç içe hedefe çevrildi (eklenti yazarının reçetesi: pod bir kez uygulama için derlenir, uzantı `@rpath` ile bağlanır); (4) yeni copy fazı Thin Binary'den SONRA düşüyor → "Cycle inside Runner"; widget'ın kullandığı mevcut "Embed Foundation Extensions" fazı yeniden kullanılıyor. **App 738 test** (share 10: mapping, binder soğuk/sıcak, take-once, 5 çip, make-task→kart, take-note sıfır-AI, inbox, özetle+context, unconfigured), analyze + i18n temiz.)_

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

_(✅ 2026-07-30. Korpus `ai_redteam.json` (9 vaka — 218'de doğdu) artık ÜÇ yüzeyde koşuyor: MCP (`mcp-injection.test.js`, 218), **yeni `ai-injection.test.js`** (extract + chat renderer), app `ai_text_test.dart` korpus döngüsü. Extract assert'i: her düşman metin `fenceBlock`'un ürettiği biçimin AYNISIyla çitli gider (fence-escape'in `</user_data>`'i `<\/user_data>`'e kaçışlı — üretim fonksiyonuyla hesaplanan beklenti) + extract HİÇ görev yazmaz (`tables.tasks` değişmez; onay kartı tek yazıcı). "Sızdıran model" vakası: model şema-dışı `action`/`tool` döndürse bile yanıtta o alanlar HİÇ görünmez (Ajv `additionalProperties:false` → onarım veya 422) + sıfır yazım. Saf fence testleri: `fenceBlock` tek gerçek kapanış etiketi bırakır; `renderChatSystem` BASE kuralı + her segmenti çitler. App: `AiText` korpus döngüsü — her `model_output` (+ tüm vakalar) `parseAiSpans` ile SIFIR `AiSpanNavLink` (HTML/http/markdown-link/`alliswell://complete` hepsi inert), içerik veri olarak korunur; widget testi tüm korpusu render eder → `onNavigate` HİÇ çağrılmaz (AiText'te url_launcher YOK = sıfır exfil-tap). SECURITY.md "AI surfaces": tehdit modeli (model + girdileri GÜVENİLMEZ, enjeksiyon varsayılır) + **7 katman sırayla** (sınır=araç yokluğu; sonra insan onayı, Ajv, tek fence, inert render, MCP allowlist, anahtar izolasyonu) + self-host işletme (`AI_ENABLED` kill switch, `MCP_ENABLED`+`API_PUBLIC_URL` ayrı, rate/`AI_DAILY_CAP`, **per-connection baseUrl SSRF uyarısı**) + raporlama. `context.js` başlık yorumu zaten "hardened in OPH-226" — sunucu kodu değişmedi, yalnız kanıt eklendi. **API +1 test dosyası (ai-injection 12), app ai_text 16** (7 yeni), analyze + lint temiz.)_

- [x] **Provenance çitleri:** paketlenen her bağlam parçası açık veri bloğunda
      (`<user_data source="task" id="…">`), sistem kuralı "veri bloğu içeriği bilgi,
      asla talimat"; paylaşım metni en sıkı çerçevede. Çit = hafifletme; sınır = araç
      yokluğu + Ajv + onay (AI.md §8, sıra önemli).
- [x] **Düşman korpusu CI'da:** "önceki talimatları yok say…", araç-JSON taklidi,
      exfil URL'leri, `alliswell://` enjeksiyonu içeren başlık/not/paylaşım fikstürleri —
      çıkarım çıktısı şema-temiz kalır, beklenmeyen alan/eylem yok, MCP araçları veri
      döndürür eylem döndürmez (üç yüzeyde de assert).
- [x] AI çıktısı **düz metin/sınırlı markdown** — HTML render yok, link otomatik
      açılmaz; çıktıdaki `alliswell://` ADR-0016 çözücüsünden geçer (yapısı gereği
      yalnız gezinme).
- [x] SECURITY.md'ye "AI yüzeyleri" bölümü (tehdit modeli + raporlama); self-host AI
      işletme notları (anahtar hijyeni, `AI_ENABLED`, hız sınırları, instance-env
      anahtarda kullanıcı-başı günlük token tavanı).
- [x] Testler: korpus süiti üç yüzeyde yeşil; markdown render sınırlayıcısının widget
      testi.

### OPH-227 — README/tanıtım + i18n/tasarım süpürmesi + dizin başvuruları

_(✅ 2026-07-30. **Sürüm 0.9.0 dört kaynakta:** `pubspec 0.9.0+11`, `kAppVersion`, root + api `package.json`; CHANGELOG `[0.9.0]` Epic 20 anlatısı (Unreleased boşaltıldı). **README:** iki metin rozeti (Works with Claude · ChatGPT → MCP.md; BYOK: Anthropic · OpenAI · Gemini · OpenRouter · Ollama → AI.md — **logo değil metin**, Gemini "API key", tüketici entegrasyonu ima YOK) + iki özellik maddesi (uygulama içi AI + MCP bağlayıcı) + **bayat durum satırı düzeltildi** (v0.1.0→v0.9.0, **748 app + 592 backend unit + 58 integration**). **STORE-LISTING:** §2.6'ya AI satırı + kullanıcı-başlatımlı işleme notu (Calendar deseni); §5'te **bayat "recurring tasks yok" guardrail'ı düzeltildi** (artık v0.8.0'da var) + yeni "built-in/free AI yok" guardrail'ı (BYOK/kendi aboneliğin, Gemini API key). **PRIVACY.md + PRIVACY.tr.md:** "AI features (optional)" bölümü (BYOK anahtar şifreli, ne gönderilir/kime, ses cihazda, onay hep sizde, MCP; işleyen listesine AI eklendi). **ROADMAP** Phase 14 → ✅ v0.9.0 + kapanış notu; **ARCHITECTURE** §6d AI; **AI.md** "implemented in v0.9.0" başlık dokunuşu. **`docs/store/directories.md`** oluşturuldu (Claude Connectors + ChatGPT başvuru metinleri) → gönderim STATE "Kullanıcıdan bekleyen"e. **Kapılar:** `check:i18n` temiz, contrast **FAILURES: 0** (AI yüzeyleri mevcut token — secondaryContainer/AwTokens.warning — kullandığından yeni ham renk yok), `check:no-ts` + server `lint` + `format:check` temiz, **server 592 unit + app 748**. **Ekran görüntüleri:** bubble/kart sahneleri store_screenshots harness'ında üretilecek — cihaz/golden bağımlı, **cihaz turu kuyruğuna** (README iddiaları görüntüsüz de birebir gerçek).)_

- [x] README: **"Works with Claude · ChatGPT"** (MCP bağlayıcısı — kurulum linkiyle) +
      **"Bring your own key: Anthropic · OpenAI · Gemini · OpenRouter · Ollama"**
      rozetleri/logoları — **logo kullanımı her markanın kurallarına göre denetlenir**,
      izin dar ise metin rozeti (iddia ≠ gerçeklik olamaz: Gemini "API key" diye yazar,
      tüketici-uygulama entegrasyonu İMA EDİLMEZ); özellik bölümü: sesle görev, bubble,
      paylaşım hedefi, MCP — ekran görüntüleriyle. _(Metin rozetleri + özellik maddeleri BİTTİ; ekran görüntüleri cihaz turu kuyruğunda.)_
- [x] STORE-LISTING: AI veri paylaşımı beyanları (Apple/Play formları), yaş
      derecelendirme kontrolü; ROADMAP/BLUEPRINT "uygulandı" dokunuşları.
- [x] alliswell.space için **Claude Connectors Directory** + **ChatGPT app** dizin
      başvuruları hazırlanır ve STATE "Kullanıcıdan bekleyen"e işlenir (inceleme
      süreçleri dış taraf — DoD'yi kilitlemez).
- [x] Kapanış süpürmesi: `check:i18n` (tüm `ai.*` anahtarları en+tr), kontrast
      FAILURES: 0 (bubble/kart/onam yüzeyleri), `lint`/`format:check`/`check:no-ts`,
      app + API tam süit.

**Epic 20 DoD:** her task kendi testleriyle; ADR-0019 + (implementasyonda) ADR-0022/0023
kabul edilmiş; AI.md canlı tutulmuş; **prod SSE curl kanıtı** STATE'te; düşman korpusu
CI'da kalıcı; cihaz turu (223, 225) STATE cihaz kuyruğunda; README iddiaları birebir
gerçek → **v0.9.0**. Modele v1'de yazma aracı verilmediği ve silmenin AI'ya kalıcı
kapalı olduğu bu epic'in değişmezidir — gevşetme ancak yeni ADR'yle.

---

## Epic 21 — Feedback round 14: canlı AI arızası + optimistik ✨ + oluşturma varsayılanları (v1.1.1) ✅ KOD TAMAM (2026-08-05)

_Sahibin canlı (alliswell.space) turu: OpenAI bağlantı testi geçiyor ama sohbet
"bağlantı kurulamadı" veriyor; ✨ hızlı ekleme tıklamaya tepkisiz, dakikalarca
bekleyip hata basıyor; ayarlarda bağlantıyı kaldırma yolu fark edilmiyor; yeni
görev varsayılanları (orta öncelik, acil alarm, son tarihten 1 saat önce
hatırlatma) ve hızlı eklemede zorunlu-ama-geçilebilir tarih sorusu istendi.
Bağlayıcı dokümanlar bu turda revize edildi: DESIGN §24 AI5/AI11 + §26, AI.md §3/§4._

### OPH-228 — Canlı AI arızasının teşhisi ve kökten çözümü

_(✅ 2026-08-05. **Teşhis SSH'sız yapıldı:** deploy anahtarını kullanan read-only
`Diagnose` workflow'u (public repo → loglardan yalnız SAYI ve KOD basar, asla
payload basmaz). Bulgular: API sağlıklı, Node 18.20.6 + `AbortSignal.any` mevcut,
TÜM log tarihçesinde sıfır "ai chat upstream failed" — ama vhost'ta aaPanel'in
battaniye `SetOutputFilter DEFLATE`'i. Kök neden: zlib birkaç baytlık SSE
çerçevelerini blok dolana dek tutar → Cloudflare origin'i sessiz görür → ~100 sn'de
524 → uygulama "bağlantı kurulamadı" okur; sunucu tarafıysa bunu sessiz
client-gone olarak yaşar, tek satır log düşmez. Çözüm üç katman: deploy'a
**idempotent, `apachectl -t` kapılı `zz-alliswell-sse.conf`** adımı (chat yoluna
`SetEnv no-gzip/no-brotli`); istemcinin SSE isteğine **`accept-encoding: identity`**
(self-host proxy'leri için); AI.md §3'e canlı vaka kaydı. İkinci kusur: extract
gibi akışsız çağrılarda 15 sn'lik el sıkışma zamanaşımı üretimin TAMAMINI
bekliyordu → 3 deneme ≈ 45+ sn askıda kalma + hata. `EXTRACT_TIMEOUT_MS` 90 s,
`CHAT_HANDSHAKE_TIMEOUT_MS` 30 s, `insufficient_quota` 429'u retry yakmadan anında
düşer, `upstreamMessage()` sağlayıcının kendi hüküm cümlesini loglara VE istemciye
taşır (bir hafta "The AI provider failed" körlüğünün dersi). `error.AI_*` anahtar
ailesi en+tr eklendi. API +4 test (kota fast-fail ×5 sağlayıcı sözleşmesinde,
upstreamMessage ×3).)_

- [x] Read-only `Diagnose` workflow'u; PM2/Apache/log imza sayımları, payload'sız.
- [x] Deploy'a Apache SSE conf adımı — idempotent, config-test kapılı, geri alınır.
- [x] `ai_stream_client.dart` SSE isteğine `accept-encoding: identity`.
- [x] aiFetch zamanaşımı sabitleri + kota fast-fail + upstream verdict yüzeyi.
- [x] AI.md §3 canlı vaka + §4 istisna kaydı.

### OPH-229 — AI bağlantısını kaldırma: etiketli, onaylı unlink

_(✅ 2026-08-05. Canlıda çöp-kutusu ikonu keşfedilemiyordu; takvimin Disconnect
deseni uygulandı: "Kaldır" METİN düğmesi (hata rengi) + onay diyaloğu
("{provider} bağlantısı kaldırılsın mı?" — anahtarın sunucudan silindiğini ve
yeniden bağlanabileceğini söyler) + "Bağlantı kaldırıldı" snackbar'ı. Sunucu ucu
zaten vardı (DELETE /ai/connections/:id, anahtar maddesini de siler). Testler:
onaydan önce silinmez, vazgeç korur, onay siler.)_

- [x] `_ConnectionRow` unlink akışı + `ai.settings.removeConfirm*`/`removed` en+tr.
- [x] Widget testleri (onaylı silme + vazgeçme).

### OPH-230 — ✨ hızlı ekleme: anında satır, asenkron zenginleştirme, sessiz düşüş

_(✅ 2026-08-05. Eski akış kullanıcıyı extraction gidiş-dönüşüne rehin ediyordu
(feedback yok → onay kartı → sağlayıcı yavaşsa hata). Yeni akış DESIGN §24 AI11:
✨ dokunuşu metni ANINDA düz hızlı-ekleme görevi olarak yazar (round-14
varsayılanları dahil), satırda "Yapay zekâ dolduruyor…" rozeti döner
(`ai-enriching-*`, selector'lı watch — liste değil satır rebuild olur),
extraction arka planda UPDATE olarak iner (çoklu görev önerisinin fazlası bütün
olarak doğar), HERHANGİ bir hata rozeti söndürüp düz görevi bırakır — onay kartı
bu yolda YOK, karar audit'i (accept/reject + entityRefs) aynen `ai_action_log`a
gider. `ai_quick_add.dart` motoru + FakeApi `extractDelay` kancası; testler
optimistik anı (satır var + rozet var + kart yok), iniş sonrasını (başlık/tarih/
1 saat önce hatırlatma/varsayılanlar/audit) ve düşüşü (intent:none → düz görev)
kanıtlar. Bar'ın ✨ dokunuşu _submit ritmiyle aynı: alan anında temizlenir,
odak kalır.)_

- [x] `aiQuickAddProvider` + `aiEnrichingTasksProvider` + TaskTile rozeti.
- [x] QuickAddBar `_parse` optimistik ritim + hata snackbar'ı.
- [x] Widget testleri (anında satır, asenkron iniş, sessiz düşüş).

### OPH-231 — Oluşturma varsayılanları + hızlı eklemede tarih sorusu (DESIGN §26)

_(✅ 2026-08-05. `task_defaults.dart` TEK kaynak (C4): öncelik **orta**, **acil
alarm açık**, son tarih seçilince hatırlatma **due − 1 saat** (`kAwAutoReminderGap`).
Create sheet: türetilmiş hatırlatma son tarihi İZLER (`_remindAuto`), kullanıcı
eli değen/temizleyen hatırlatmaya bir daha dokunulmaz (C2, §17 D5 ruhu); edit/triage
modunda görevin kendi gerçeği korunur, boş hatırlatma + yeni tarih yine türetir.
Home hızlı ekleme: Enter'da paylaşılan tarih+saat seçici (C3) — seçili takvim
günüyle önceden dolu; vazgeçmek "Geç"tir: seçili gün varsa o günün varsayılan
saatine, yoksa tarihsiz ekler. Inbox kutusu bilinçli olarak DOKUNULMADI (tarihsiz
yakalama kutusu kalır). Test düzeni: bar spinner'ı onAdd boyunca döndüğünden
diyalog açıkken `pumpAndSettle` OTURMAZ — sınırlı pump deseni dört teste işlendi;
FAB testi artık varsayılanları (medium + urgent + due−1 h) kanıtlıyor.)_

- [x] `task_defaults.dart` + create sheet C1/C2 + Home quick add C3.
- [x] Dört mevcut testin yeni gerçeğe uyarlanması + varsayılan kanıtları.

**Epic 21 DoD:** app 753 + API 613 unit yeşil, analyze/lint/i18n/format temiz,
deploy sonrası canlıda sohbet-SSE'nin artımlı aktığı ve ✨/unlink akışlarının
çalıştığı sahibin cihaz turuyla doğrulanır → **v1.1.1**.

## Epic 22 — Feedback round 15: sohbetin körlüğü + iPhone alarm/widget arızaları (v1.1.2) ✅ KOD TAMAM (2026-08-05)

_Sahibin gerçek iPhone turu, ekran görüntüleriyle: sohbet AKIYOR (round 14'ün
transport zaferi) ama model "takvimine/görevlerine erişemem" diyor ve "yarın
16'da toplantımı hatırlat" yazınca görev açmak yerine telefon takvimini tavsiye
ediyor; bildirimdeki Ertele hiçbir şey yapmıyor (hatta çökme algısı); widget
kendiliğinden tazelenmiyor; widget'tan tamamlama hiçbir şey yapmayıp sonra
uygulamayı çökertiyor ve ancak kapat-aç sonrası işliyor._

### OPH-232 — iOS widget zaman çizelgesi: bayat gün, tek girdili timeline

_(✅ 2026-08-05. Tek girdi + tek gece-yarısı reload, uygulama açılmadıkça aynı
bayat snapshot'ı DÜNÜN tarihiyle yeniden çiziyordu. Timeline artık şimdi + 4
gece yarısı taşır; tarih başlığı ENTRY tarihinden çizilir (`awDate(for:locale:)`
— OS tarih adları, ürün stringi değil; W9 korunur). Bucket'lar app'in dürüst
snapshot'ı kalır (W1: native'e ürün kuralı taşınmaz). Android gece-yarısı işi
açık yarım olarak kaydedildi.)_

### OPH-233 — iOS widget tamamlama: LiveActivityIntent tuzağı

_(✅ 2026-08-05. Widget'ın dairesi `AWCompleteTaskIntent`'i (LiveActivityIntent!)
kullanıyordu — iOS bu türü DAİMA ana uygulamada koşturur: her dokunuş arka
planda headless bir Flutter süreci doğurdu (görünürde hiçbir şey olmaz), yarım
doğan süreç kullanıcı uygulamayı açınca çöktü (Dart'a varamadan öldüğü için
Crashlytics'e DÜŞMEZ) ve kuyruklanan tamamlama ancak SONRAKİ temiz açılışta
uygulandı — sahibin cihaz raporunun birebir zinciri. Yeni `AWWidgetCompleteIntent`
düz AppIntent'tir ve WIDGET sürecinde koşar: snapshot'taki satırı
JSONSerialization ile done işaretler (Codable tur atışı yeni sürüm alanlarını
düşürürdü — OPH-187 duruşu), gerçek tamamlamayı mevcut `AWAlarmActionQueue`'ya
kuyruklar (app foreground observer'ı zaten boşaltıyor), timeline'ı yeniler.
`flutter build ios --debug` ile iki hedef de derlendi.)_

### OPH-234 — iOS bildirim aksiyonları: foreground'suz düğme = hiçlik

_(✅ 2026-08-05. Darwin aksiyonları seçeneksiz `.plain`'di: iOS basışı uygulamayı
başlatmadan işler, plugin yanıtı bu uygulamanın bilerek KAYITSIZ bıraktığı
background handler'a yollar — Ertele/Tamamla gerçek cihazda hiçbir şey
hesaplamadı (ölü süreçte plugin'in background dispatch'i çökme bile üretebilir).
Tüm Darwin aksiyonlarına `DarwinNotificationActionOption.foreground` verildi —
Android'in `showsUserInterface: true`'sunun birebir ikizi; soğuk başlatma
teslimatını OPH-214 kuyruğu zaten karşılıyor. NOTIFICATIONS.md sapma notu
güncellendi.)_

### OPH-235 — Sohbet: bağlam paketi gerçekten paketlensin + yazılı niyet kapısı

_(✅ 2026-08-05. AI.md §7 spec'ti, davranış değildi: saf paketleyici OPH-221'den
beri vardı ama yazılı hiçbir tur onu ÇAĞIRMADI — model sıfır fence ile "takvimine
erişemem" diye dürüstçe cevapladı. `ai_live_context.dart` tek impure kenar:
T0 meta+projeler, T1 geciken/bugün/yaklaşan (başlık+due satırları) + kullanıcının
takvim etkinlikleri, T2 fold-eşleşmeli görev alıntıları; paylaşım bloğu aynı
bundle içinde taşınır. Yazılı yol OPH-224 niyet kapısını aldı (`source: bubble`):
create_tasks → onay kartı, gerisi → bağlamlı akışlı sohbet; kapı hatası düz
sohbete düşer. İki ön-mevcut hata da yakalandı: sunucu error-event'inden sonra
gelen Done hata yüzünü composing'e eziyordu (guard eklendi) ve error yüzünün
Retry'ı boş input'la sessiz no-op'tu (`retryLast` + `machine.retry` — aynı turu
kopyalamadan yeniden akıtır). BASE_SYSTEM_RULE'a "fence'ler kullanıcının kendi
çalışma alanıdır, onlardan cevapla" cümlesi eklendi. +4 kapı testi
(ai_bubble_gate_test), builder testleri genişletildi; app 759 yeşil.)_

### OPH-236 — Sohbet UX cilası (round 15b): kaydırma, kilit, yetenek dürüstlüğü

_(✅ 2026-08-05. Üç cihaz şikâyeti: (1) konuşma kendi kuyruğunu takip etmiyordu —
`_stick` deseni geldi: kullanıcı alttayken her büyüme (yeni tur, token, düşünme
yüzü) alta kaydırır, yukarı kaydırınca zorlamaz, göndermek yeniden yapıştırır;
(2) gönderilen metin alanda saniyelerce kalıyor ve Enter aynı mesajı yeniden
yolluyordu — alan artık dokunuş ANINDA temizlenir, cevap süresince `enabled:false`
kilitlenir, `textInputAction.send` + `_busySending` mandalı çift gönderimi
controller'da da keser; (3) "görev ekleyebilir misin?" sorusuna model "hayır"
diyordu — BASE_SYSTEM_RULE'a ürünün düz mesajdan görev oluşturduğu (onay kartıyla)
yazıldı: yetenek dürüstlüğü iki yönlüdür, ürünün yaptığını inkâr etme. Test avı
GERÇEK bir hata çıkardı: `stop()` yüz güncellemesini `await _sub.cancel()`'ın
arkasına koymuştu — Stop dokunuşu transport ölene kadar yüzü değiştirmiyordu;
yüz önce, teardown sonra + listener'da `_cancelled` süzgeci. +4 test
(çift-gönderim, akış-sırasında-kilitli, alan temiz+kilitli widget testi,
kuyruk-takibi görünürlük testi).)_

**Epic 22 DoD:** app 763 + API 613 unit yeşil, iOS debug build (app+widget) derlenir;
cihaz turu: bildirim Ertele/Tamamla, widget dairesi (anında dolu daire + app'te
işlenmiş görev), gece yarısı sonrası widget tarihi, sohbette "yoğun muyum" (veri
görür) ve "yarın 16'da hatırlat" (kart açar) → **v1.1.2**.

## Epic 23 — Feedback round 16: Play'den inen ikon, Firefox'ta seçim, notu PDF'e aktarma (v1.2.0) ✅ KOD TAMAM (2026-08-05)

_Sahibin üç maddesi: (1) Google Play'den kurulan Android uygulamasının ikonu yok,
"beyaz bir şeyde kalmış"; (2) web'de notlar sekmesinde metni sürükleyerek seçince
font değişiyor, harfler üst üste biniyor, seçim vurgusu kayıyor; (3) notu PDF
olarak dışa aktarma — yükleniyor diyaloğu, sonunda paylaş / indir / dosyalara
kaydet._

### OPH-236 — Android ikonu: adaptive foreground ŞEFFAF değildi

_(✅ 2026-08-05. Kök neden ölçülerek bulundu: `assets/branding/icon-foreground.png`
alfa kanalında HER pikselde 255 taşıyordu ve zemini bembeyazdı (görünen
piksellerin ortalama RGB'si 254,254,254). Adaptive icon'da ön plan katmanı arka
planı tamamen örter, dolayısıyla `#4F63EF` mavi yalnız `inset="16%"`ten artan
çerçevede kalıyor, launcher maskesi onu da kırpınca geriye SAF BEYAZ bir karo +
hayalet tik kalıyordu. Legacy `mipmap/ic_launcher.png` doğruydu — Play listesi
ikonu bu yüzden düzgün görünüyor, ama Android 8+ (yani her cihaz)
`mipmap-anydpi-v26/ic_launcher.xml`'i tercih eder ve legacy PNG hiç kullanılmaz.
El düzeltmesi yerine katmanlar TEK master'dan türetilir oldu:
`scripts/design/branding_icons.py` `icon.png`'den `icon-foreground.png` (işaret,
beyaz, ŞEFFAF zeminde, safe zone'a ölçekli), `icon-background.png` (marka
gradyanı — Android artık iOS ile AYNI resmi gösteriyor, düz renk değil) ve
`icon-monochrome.png` (Android 13+ temalı ikon) üretir; script ayrıca bir
adaptive foreground'ın sağlaması gereken değişmezleri DOĞRULAR (köşeler şeffaf,
işaret safe zone içinde, ortalanmış) ve `--check` ile CI'da koşabilir. İşaret
oranı iOS'takiyle aynı tutuldu (master'da işaret/karo = %64.7) — aracın
`inset="16%"`i hesaba katılarak. **Turun tuzağı: `flutter_launcher_icons` 0.14.4
`ios: true` ile pbxproj'i BOZUYOR** — bulduğu her `ASSETCATALOG_COMPILER_*`
ayarını ikon adına eziyor; widget extension'ın `GLOBAL_ACCENT_COLOR_NAME` ve
`WIDGET_BACKGROUND_COLOR_NAME` değerleri `AppIcon` olmuştu ve boolean
`GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` de öyle. Geri alındı, config'te
`ios: false` yapıldı ve sebebi pubspec'e yazıldı; iOS ikon seti zaten doğru ve
commit'li.)_

### OPH-237 — Firefox'ta not seçimi: gizli IME textarea'sı görünür oluyordu

_(✅ 2026-08-05. Chromium'da ÜÇ ayrı birebir-kopya repro build'i tertemiz
çıktı; kırılma sahibin tarayıcısına özeldi, o yüzden gerçek Gecko'da (Playwright
Firefox) sürükleme yapılıp ÜRETİLDİ ve DOM'dan kanıtlandı: suçlu
`<textarea class="flt-text-editing">` — web engine'in IME ve pano için canvas'ın
üstünde tuttuğu gizli vekil. Notun tam metnini taşır, editörün tam üzerinde
konumlanır (140,170 · 720×784) ve fontu `monospace/13px`'tir. Engine onu
`color: transparent` ile gizler — ve `::selection` tam olarak `color`'ı ezen
şeydir: uygulamanın seçimi o textarea'ya yansıtıldığı anda Firefox seçili
aralığı SİSTEM seçim renkleriyle yeniden boyar, görünmez monospace metin
görünür olur ve canvas'taki gerçek metnin üstüne biner. Chromium seçili metnin
şeffaf rengini koruduğu için orada hiç çıkmaz. Düzeltme `web/index.html`'de iki
CSS kuralı (`::selection` + `::-moz-selection` — bilinmeyen bir pseudo-element
TÜM seçiciyi geçersiz kıldığı için AYRI kurallar). Gerçek Firefox'ta düzeldiği
doğrulandı. `test/web_shell_test.dart` kuralı bekçiliyor: `web/index.html`
`flutter create` şablonunun toptan yeniden yazdığı bir dosya.)_

### OPH-238 — Notu PDF olarak dışa aktar

_(✅ 2026-08-05. Not detayındaki taşma menüsünde "PDF olarak dışa aktar"
(sahibin kararı: yalnız bu yüzey). Üç katman: **saf** `note_blocks.dart` delta'yı
blok modeline çevirir (başlık/madde/sıralı/onay kutusu/alıntı/kod/figür; sıralı
liste numaralarını üretir ve araya başka bir blok girince sıfırlar; ardışık kod
satırları TEK panel; embed'ler kendi figürü olur ve satırını kapatan `\n` boş
paragraf ÜRETMEZ), **platform kanalsız** `note_pdf.dart` bunu A4 sayfaya çizer
(başlık + düzenlenme tarihi + ayraç, sayfa numarası, ikinci sayfadan itibaren
başlık üstbilgisi, tıklanabilir bağlantı anotasyonları, tamamlanmış maddede üstü
çizili metin), `ui/note_export.dart` ise yalnız platformun yaptığı işi: fontları
bundle'dan okur, gömülü görselleri çeker (8 sn tavan; gelmezse DESIGN §10 F3
uyarınca dürüst yer tutucu), ilerleme diyaloğunu gösterir ve baytları
`NotePdfSink` üzerinden OS'a verir (paylaş / dosyalara kaydet / yazdır; web'de
paylaş yerine indir). **Türkçe için zorunlu karar:** `pdf` paketinin gömülü
Helvetica'sı WinAnsi kodlamalıdır ve `ı ğ ş İ` YOKTUR — her Türkçe not mojibake
çıkardı; bu yüzden Roboto (Apache-2.0) Flutter SDK'sından LİSANSIYLA birlikte
`assets/fonts/`'a vendor'landı ve yalnız PDF üretiminde kullanılır (Flutter
`fonts:` girdisi DEĞİL — DESIGN §3.3 sistem fontlarını korur, ağ isteği yok).
Onay kutusunun tiki ÇİZİLİR, yazılmaz: Roboto'da U+2713 yoktur ve `pdf` bulamadığı
glifi çizmeyi reddeder. **Bilinen sınır** dosya başında yazılı: ok/dingbat blokları
(`→ ← ✓ ✗ ★ ▪ ☐`) ve emoji kutu olarak çizilir; base-14 Symbol/ZapfDingbats
`fontFallback` olarak DENENDİ, ölçüldü, hiçbirini kurtarmadı ve bilinçli olarak
bağlanmadı. 18 yeni test: blok eşlemesi 5, gerçek PDF üretimi 4 (gömülü font ve
bağlantı anotasyonu bayt düzeyinde doğrulanır), akış 4.)_

### Round 16b — sahibin takip listesi (OPH-239…241) ✅ 2026-08-05

#### OPH-239 — PDF'te ok/dingbat glifleri: DejaVu fallback

_(✅ Ölçüldü: Roboto'nun cmap'i **896** kod noktası taşıyor ve `→ ← ↔ ⇒ ✓ ✗ ★ ☆
▪ ▫ ☐ ☑ ✔ ✱ ♦ ♥`'ın HİÇBİRİ yok — `pdf` bulamadığı glifi boş kutu çiziyor. PDF'in
base-14 Symbol/ZapfDingbats'i `fontFallback` olarak ÖNCE denendi ve hiçbirini
kurtarmadığı ölçüldü (paketin kullanabileceği Unicode eşlemesi taşımıyorlar).
Çözüm: **DejaVu Sans** (5918 kod noktası, Bitstream Vera lisansı, resmi
upstream sürümünden, LİSANSIYLA birlikte vendor'landı) her `TextStyle`'a
per-glyph fallback olarak bağlandı. Test *iddia ediyor*, göz kararı değil:
`pdf` uyarıyı `assert` içinde `print`'lediği için test bir `Zone` ile stdout'u
yakalayıp 30 sembolde SIFIR uyarı olduğunu ve DejaVu'nun dosyaya GÖMÜLDÜĞÜNÜ
doğruluyor. Kalan sınır de pinlendi: modern piktografik emoji (`🎉`) hiçbir
monokrom yüzde yok ve PDF renkli emoji fontu gömemez — bu bir test olarak
yazıldı ki kimse hata sanıp yeniden açmasın. Fallback yalnız regular ağırlık:
kalın bir ok regular DejaVu ile çizilir; nadir bir sembolü kalınlaştırmak için
ikinci bir 700 KB'lık yüz kötü takas.)_

#### OPH-240 — `flutter_launcher_icons`'ın pbxproj hasarı: iOS'u kendimiz üretiyoruz

_(✅ `ios: false` bir geçici çözümdü; artık bir YEDEK var.
`scripts/design/branding_icons.py` iOS AppIcon setini de üretiyor — aynı
master'dan, **asset catalog'un kendi `Contents.json`'undan** okunan size × scale
ile, alfasız düzleştirilmiş (App Store Connect alfası olan pazarlama ikonunu
reddeder). Contents.json'u ASLA yeniden yazmıyor: hangi slotların var olduğunun
sahibi Xcode kalıyor ve diff okunabilir kalıyor. `--check` commit'li varlıkları
doğruluyor. Doğrulandı: araç yeniden koşturulduğunda `git status
apps/app/ios/Runner.xcodeproj` BOŞ.)_

#### OPH-241 — `.md` dosyalarını AllisWell ile aç, notlara/projeye aktar

_(✅ Sahibin isteği: bilgisayardaki/telefondaki md dosyaları için AllisWell'i
görüntüleyici olarak kullanmak ve dış kaynak olan bu dosyaları not olarak içeri
aktarmak. Üç parça: (1) **`markdownToDelta`** — `deltaToMarkdown`'un birebir
tersi, saf; en güçlü testi bir ROUND TRIP (delta→md→delta) çünkü iki çevirici
birbirine karşı yazıldığında elle fikstür yazmaktan çok daha güçlü bir garanti
verir. Tanımadığını DÜŞÜRMEZ, düz metin olarak korur (tablo, dipnot, HTML) —
birinin dosyasını kayıplı almak çirkin almaktan kötüdür. (2) **Görüntüleyici**
(`/notes/import`): önizleme, içe aktarmanın YAZACAĞI delta'nın üzerinde
salt-okunur bir `QuillEditor` — ayrı bir markdown render'ı importer'dan sapıp
kullanıcıya almayacağı bir şey gösterebilirdi. Kaynak dosya adı görünür
(provenance), başlık düzenlenebilir (öndeki `# H1` başlık olur, yoksa dosya
adı), proje seçimi create sheet'in AYNI `ProjectPickerField`'ı. (3) **OS
kaydı**: Android `ACTION_VIEW` (mime TİPİ + uzantı deseni — Android bir .md'yi
nereden geldiğine göre text/plain veya octet-stream diye raporlar, mime-only
filtre gerçek dosyaların çoğunu kaçırır), iOS/macOS `CFBundleDocumentTypes` +
`LSSupportsOpeningDocumentsInPlace`. Paylaşım dikişi genişletildi: OS tek kanaldan
İKİ niyet gönderiyor (metin paylaş / belge aç), artık ayrı üyeler — tüketiciler
birbirinin trafiğini filtrelemek zorunda değil; tek kanal aboneliği
`asBroadcastStream` ile ikiye dağıtılıyor. **Uygulama içi giriş noktası de var**
(Notlar app bar'ı): yalnızca OS'un başlatabildiği bir özelliği çoğu insan hiç
bulamaz — DESIGN §22. 2 MB üstü dosya dürüst mesajla reddedilir. **Testin
yakaladığı gerçek hata:** `take()` `initState` içinde provider yazıyordu
(Riverpod yasaklıyor); okuma initState'te, temizleme kareden sonra. 20 yeni test.)_

## Epic 24 — Feedback round 17: paylaşım hattı, görsel ekleme, Markdown çalışma tezgâhı, widget saati (v1.4.0)

_(Doğdu 2026-08-09 — sahibin dört maddelik listesi. (1) iPhone'da bir yazıyı seçip
"Paylaş → AllisWell" dediğinde **hiçbir şey olmuyor** — çökme raporu bile yok; iki farklı
kaynaktan (seçili metin, Mail'den kopyalanan metin) denendi, ikisinde de aynı sessizlik.
Beklenti: AI varsa paylaşılan metni otomatik olarak sisteme uygun bir göreve çevirmesi,
AI yoksa **detaylı ekleme sheet'inin başlık alanına yapıştırılmış** olarak açılması.
(2) Göreve **resim eklenemiyor**: önce açıklama alanında bir ek yolu arandı, yoktu;
"Dosya ekle" iPhone'da doğrudan dosya yöneticisini açtı ve orada fotoğraflar
görünmüyor — beklenen izin diyaloğu da hiç gelmedi. İstenen: hem dosya hem resim
eklenebilmesi ve eklenen resmin görev detayında **zoom/pinch yapılabilen bir
görüntüleyicide** açılması. (3) **Markdown editörü/görüntüleyicisi bu epic'in en büyük
işi** — bu bir düzeltme değil, YENİ İŞ: en az 10 modern md editörü/görüntüleyicisi
taranıp mantıklı özelliklerin eklenmesi, ve bunun README + landing'de en önemli
özelliklerden biri olarak gerçek ekran görüntüleriyle pazarlanması. (4) Widget'ta
sağdaki boşluğa, açık görev sayısının hemen üstüne **cihazın sistem saati** kalın ve
okunaklı biçimde gelmeli.
Bağlayıcı metinler bu turda yazıldı: **[MARKDOWN.md](MARKDOWN.md)** (alan taraması —
13 ürün, 41 özellik kararı, model seçenekleri, kaynak linkleri orada) ve DESIGN
**§29** (markdown çalışma tezgâhı), **§30** (ek seçme + görsel görüntüleyici),
**§31** (widget başlığı).
_Numara notu:_ **OPH-236 depoda iki kez kullanıldı** (Epic 22 "Sohbet UX cilası" ve
Epic 23 "Android ikonu"); ikisi de kapalı, geriye dönük düzeltilmiyor — bu epic
OPH-242'den devam eder.

_**Kapanış planı (2026-08-11, sahiple kararlaştırıldı).** Yürütme sırası —
dosya sırası da budur, numara sırası değil (OPH-254'ün 247–248 arasına konması gibi):_
_`OPH-250 kuyruğu → OPH-255 → OPH-256 → OPH-251 → OPH-252`._
_Verilen dört karar: (1) **komut paleti YAZILIR**, slash telefon/satır-içi yol olarak
kalır; (2) geri kaydetme **üç platformda da gerçek** olur ve OPH-251 üçe ayrılır —
tutamak katmanı (255) · native gerçeklik (256) · W1–W6 arayüzü (251); (3) sürükle-bırak
`desktop_drop`, pano **kendi kanalımız** — `super_clipboard` reddedildi çünkü
`super_native_extensions` bir Rust toolchain'ini altı platform build'ine ve CI'a sokardı;
(4) **sürüm ve v1.4.0 etiketi bu epic'in işi DEĞİL** — ayrı tur, CHANGELOG `[Unreleased]`
altında birikmeye devam eder. (O turda ele alınacak ölçüm: `release.yml` üç dosyayı
kapılıyor ama **v1.3.1 `app_version.dart` 1.3.0 iken çıkmış** — gate'in tam olarak
reddetmesi gereken durum; ayrıca sürüm dizesi depoda **11 yerde** yaşıyor, kapıda üçü var.))_

> **Turun tek cümlesi:** dört maddenin üçü "kod eksik değil, **hat kopuk**" sınıfından
> (paylaşım uzantısı doğru çalışıp cevapsız bir kapıyı çalıyor; ek seçici doğru çalışıp
> yanlış seçiciyi açıyor; widget başlığında yer var, saat yok) — dördüncüsü ise gerçek
> bir ürün genişlemesi: notların bir **belge** olduğunu kabul edip AllisWell'i birinin
> Typora/Obsidian yerine `.md` okumak için açacağı kadar iyi yapmak.

**Round'un ÖLÇÜLMÜŞ gerçekleri (planlama turu, 2026-08-09 — hiçbiri varsayım değil):**

| # | Bulgu | Kanıt | Sonuç |
| - | ----- | ----- | ----- |
| 1 | iOS paylaşım uzantısı ana uygulamayı **kayıtlı olmayan bir URL şemasıyla** çağırıyor: `RSIShareViewController` `ShareMedia-<hostAppBundleIdentifier>:share` URL'ini kurup `openURL:` çağırıyor, ama `ios/Runner/Info.plist`'te yalnız `alliswell` ve Google şeması kayıtlı — **`ShareMedia-com.alliswell.alliswell` YOK** | `~/.pub-cache/.../receive_sharing_intent-1.7.0/ios/Classes/RSIShareViewController.swift:173` + paket README satır 192–195 + `ios/Runner/Info.plist` `CFBundleURLTypes` | Bu tek başına "hiçbir şey olmadı + çökme yok" belirtisini birebir üretir. OPH-242'nin ilk hipotezi; **ölçülerek** doğrulanacak, varsayılmayacak |
| 2 | iOS 18+ **uygulama uzantılarının `openURL:` selector hilesini kapattı**: UIKit "BUG IN CLIENT OF UIKIT… migrate to the non-deprecated `UIApplication.open`" basıyor ve `UIApplication` zaten uzantılarda unavailable; Apple DTS'in cevabı "bu workaround'ları kullanmayın" | [KeyboardKit: iOS 18 breaks selector-based URL opening](https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening) · [Apple Forums: iOS 18 ShareExtension openURL](https://developer.apple.com/forums/thread/764570) · [Issue with using openURL in iOS Extensions](https://developer.apple.com/forums/thread/762458) | Şema eklemek YETMEYEBİLİR. OPH-242 üç hipotezi de sırayla eler ve sonuç ne çıkarsa yazar; plugin sürümü/alternatifi gerekirse **ADR** ister |
| 3 | Uygulama **sahne (UIScene) yaşam döngüsünde**: `Info.plist`'te `UIApplicationSceneManifest` var ve `SceneDelegate: FlutterSceneDelegate`. Bilinen boşluk: uygulama **sonlandırılmış** durumdayken `scene(_:openURLContexts:)` çağrılmaz — URL `scene(_:willConnectTo:)`'ın `connectionOptions.urlContexts`'inde gelir | [Flutter: UIScene adoption](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate) · [FlutterPluginSceneLifeCycleDelegate](https://api.flutter.dev/ios-embedder/interface_flutter_plugin_scene_life_cycle_delegate.html) · [Apple Forums 686071](https://developer.apple.com/forums/thread/686071) | Paylaşım neredeyse her zaman **soğuk başlangıçtır** → bu tam da bizim vakamız. İkinci hipotez |
| 4 | Ek seçici iOS'ta **yanlış seçiciyi** açıyor: `pick_files_io.dart` `FilePicker.pickFiles()`'ı tip vermeden çağırıyor (varsayılan `FileType.any`); file_picker 12'nin iOS kaynağı `case "image","video","media"` için **`PHPickerViewController`**, geri kalan her şey için `UIDocumentPickerViewController` açıyor | `file_picker-12.0.0-beta.7/darwin/.../IOSFilePickerHandler.swift:87, 220–236` + `pick_files_io.dart:14` | Fotoğrafların görünmemesi bug değil, **yanlış çağrı**. Çözüm için **yeni paket gerekmiyor** |
| 5 | Beklenen izin diyaloğunun gelmemesi de doğru davranış: `PHPickerViewController` süreç-dışı çalışır ve **hiçbir fotoğraf izni istemez** | [flutter/flutter#106799](https://github.com/flutter/flutter/issues/106799) · [image_picker docs](https://pub.dev/packages/image_picker) | İzin eklenmeyecek; ASIL kural "izin isteme" (DESIGN §30 A2/A3) |
| 6 | `image_picker`'a geçmek **Play riski**: Android 13+ `READ_MEDIA_IMAGES` beyanı Play politikası gereği reddedilmeye yol açıyor, kaldırınca da seçici bozuluyor | [flutter/flutter#171493](https://github.com/flutter/flutter/issues/171493) · [#171494](https://github.com/flutter/flutter/issues/171494) | Mevcut `file_picker` korunur; yeni bağımlılık ancak ölçülmüş bir gerekçeyle ve ADR ile gelir |
| 7 | **Quill Delta bu turun istediği blokların yarısını taşıyamaz**: `flutter_quill` 11.5.1 çekirdeğinde tablo düğümü yok; dipnot, matematik, mermaid, iç içe liste için de temsil yok (DESIGN §28 zaten "nested lists are out because Quill's own model is flat" diyor) | `flutter_quill-11.5.1/lib/src/document/` taraması + DESIGN §28 | "MD editörünü güçlendir" bir UI işi değil **model kararı**. [MARKDOWN.md §4](MARKDOWN.md) üç seçeneği yazdı; ADR-0028 (OPH-246) seçer ve **hiçbir render işi ondan önce başlamaz** |
| 8 | `flutter_markdown` **30 Nisan 2025'te Flutter ekibi tarafından sonlandırıldı**; resmî devamı `flutter_markdown_plus` | [flutter/flutter#162966](https://github.com/flutter/flutter/issues/162966) · [Foresight devir yazısı](https://foresightmobile.com/blog/flutter-markdown-plus-google-handover) | Render motoru seçimi OPH-246'da **ölçülerek** yapılır (4 aday + kendi renderer'ımız) |
| 9 | Hedef lehçe **GFM**: tablo, görev listesi, dipnot, üstü çizili, autolink, `[!NOTE]` uyarıları, mermaid çitleri, `$…$` KaTeX | [GFM guide 2026](https://macmdviewer.com/blog/github-markdown-guide) · [GFM cheat sheet](https://www.markdowntools.io/github-markdown-cheat-sheet) | DESIGN §29 D6: "GitHub render ediyorsa AllisWell de eder" — bundan dar olan bir görüntüleyici bozuktur |
| 10 | Widget saati iki platformda **aynı şey değil**: Android `TextClock` `@RemoteView`'dür, RemoteViews içinde kendi kendine tıklar; iOS'ta `Text(date, style: .time)` **canlı DEĞİLDİR** (timeline girdisinin anını basıp donar), yalnız `.timer`/`.relative`/`.offset` canlı güncellenir ve widget'a günde ~40–70 reload bütçesi verilir | [AOSP TextClock](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/widget/TextClock.java) · [Displaying dynamic dates in widgets](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates) · [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) | DESIGN §31 C3: Android tıklar, iOS dakikalık timeline girdileriyle yaklaşır ve **yanlış saat göstermektense saati gizler** |

**Round'da karara bağlananlar (AGENTS §8 — sor değil, karar ver ve yaz):**
paylaşımın AI'sız hedefi artık **bubble değil, dolu create sheet** (sahibin beklentisi
budur ve AI'sı olmayan kullanıcı için bubble bir çıkmaz sokaktır — AI varken bubble/onay
kartı yolu aynen kalır); ek seçme **yeni paket almadan** çözülür (bulgu #4/#6);
`_EmbedImageViewer` özelden çıkıp **tek paylaşılan `AwImageViewer`** olur (§22
ulaşılabilirlik); markdown tarafında **hiçbir kod ADR-0028'den önce yazılmaz**; mermaid
**web view ile YAPILMAZ** (güvenilmez belge + JS motoru = §24 AI6'nın tam karşıtı) —
ayrıştırılmış AST'den çizilir ya da dürüst yer tutucuya düşer; harici dosyaya geri
yazma **bayt-sadık ya da hiç** (DESIGN §29 W4); iOS'ta saat bütçe harcamaz (§31 C4).

**Sıra bağlayıcı:** `242 → 243` (paylaşım hattı) · `244 → 245` (ek + görüntüleyici) ·
**`246` (ADR kapısı — markdown'da ilk iş)** `→ 247 → 254 → 248 → 249 → 250 → 251` ·
`252` (pazarlama, markdown bittikten sonra) · `253` (widget saati — bağımsız, sıra
dışı alınabilir). **`254` round 17'de doğmadı** — ADR-0028'in 4. kararı mermaid'i
gerçekten çizmeye karar verince OPH-247'den ayrıldı (gerekçe orada ve task'ın
başında). **Cihaz isteyenler:** 242 (gerçek iPhone + gerçek Android), 244/245
(iki platformda seçici + izin turu), 251 (iOS security-scoped URL, Android
`content://` yazma), 253 (iki cihazda gece-yarısı/dakika sınırı gözlemi).

### OPH-242 — Paylaşım hattı iOS'ta neden sessiz: teşhis, kablolama, kalıcı kanıt

_(✅ 2026-08-10 — **L3 kapandı, ama "düzeltildi" diye değil: "yapılamaz" diye.**
1.8.1 ölçüldü ve iOS 18 satırı bizim vakamızı çözmüyor — düzeltmesi
`if let application = responder as? UIApplication` ile responder zincirinde bir
`UIApplication` arıyor, ki bir **app extension'ın zincirinde asla bulunmaz**.
Üstelik o dalı seçtiği için eski selector yürüyüşünü de atlıyor ve bizim şimimizi
sessizce devre dışı bırakıyor. Yani uzantı uygulamayı öne getiremiyor, nokta._

_**Karar (ADR-0029):** uzantı denemeyi bıraktı. `shouldAutoRedirect()` false →
`RSIShareViewController` zaten `SLComposeServiceViewController` olduğu için
Apple'ın kendi "metin + Gönder/İptal" formu çıkıyor (özel UI yazılmadı),
`didSelectPost()` App Group'a yazıyor, ve **yerel bir bildirim** düşüyor.
Uygulama App Group'u kendisi boşaltıyor — `ShareInboxBridge` +
`alliswell/share_inbox`, açılışta ve **her resume'da**, oku-ve-sil. Bildirim
taşıyıcı değil, dürtü: bildirime izin vermemiş kullanıcı da paylaşımını bir
sonraki açılışta buluyor._

_**Planın çökertebileceği bulgu:** `getInitialMedia()` App Group'u **okumuyor** —
`initialMedia` yalnız `handleUrl(...)`'dan doluyor. URL gelmediği için o yol
sonsuza kadar boş dönerdi; drain olmadan uzantı formu hiçbir işe yaramazdı._

_**Pin `>=1.8.1 <1.9.0`:** iOS 18 satırı için değil (bize faydası yok), 1.8.0'ın
ekran görüntüsü paylaşımı için ve 1.7.0 ile API-özdeş olduğu için. 1.9.0 dışarıda:
SPM-only + Flutter 3.38 + kendi SceneDelegate sözleşmesi._

_**Yalanları düzeltildi:** `pubspec` yorumu ve Swift yorumu "1.8+ SPM-only" diyordu
(yanlış, o 1.9.0); Swift yorumu "bir testle korunuyor" diyordu (öyle bir test
yoktu). Artık `native_config_test.dart`'ın Swift grubu gerçekten koruyor —
yorumlar soyularak, çünkü kuralı açıklayan cümleye takılan bir bekçi kendi
belgesinde patlar._

_Önceki tur (2026-08-09/10): **arıza tek değil ÜÇ katmandı** ve üçü de gerçek
iOS 26.2 simülatöründe, `log show` ile ÖLÇÜLDÜ. Sırayla soyuldular:_

_**L1 — uzantı hiç çalışmıyordu.** Planın hipotez listesinde bu yoktu; log
söyledi: `AllisWellShare` dyld'de, kendi kodunun tek satırı koşmadan, **83 ms**'de
ölüyordu → `Library not loaded: @rpath/AppAuth.framework/AppAuth`. Sebep:
`Pods-AllisWellShare.*.xcconfig` uzantıya uygulamanın **TÜM link satırını**
veriyor (`-framework AppAuth`, tüm Firebase, GoogleSignIn, receive_sharing_intent)
ama `LD_RUNPATH_SEARCH_PATHS`'i `$(inherited) /usr/lib/swift`'te bırakıyor.
O framework'ler `Runner.app/Frameworks`'te duruyor — bir appex'in kendi kopyası
olamaz — dolayısıyla dyld'nin bakacağı yer yoktu. **Bir appex'in dyld ölümü
kullanıcıya çökme raporu ÜRETMEZ:** paylaşım sayfası kapanır ve hiçbir şey olmaz.
Sahibin cümlesinin birebir kaynağı budur. Düzeltme üç `Flutter/AllisWellShare*.xcconfig`
dosyasına tek satır (pbxproj'e dokunulmadı — SETUP.md'nin 2. tuzağı); ürün
doğrulaması `otool -l … | grep LC_RPATH` artık `@executable_path/../../Frameworks`
gösteriyor ve logda "Library not loaded" YOK._

_**L2 — şema kayıtlı değildi** (planın H1'i, ölçüldü ve düzeltildi):
`RSIShareViewController.swift:173` `ShareMedia-com.alliswell.alliswell:share`
kuruyor, `Info.plist`'te o şema yoktu. Eklendi; **üründe** doğrulandı
(`plutil -extract CFBundleURLTypes` → şema `$(PRODUCT_BUNDLE_IDENTIFIER)` ile
doğru çözülmüş) ve **canlı**: `simctl openurl` ile o URL açıldığında iOS
"AllisWell ile açılsın mı?" sordu ve uygulama Safari'den öne geldi. Yan kazanım:
`GENERATE_INFOPLIST_FILE = YES` şüphesi ELENDİ — appex'in ürün plist'i
`NSExtension` + `AppGroupId` + sürüm paritesini (1.3.0/1.3.0) taşıyor._

_**L3 — iOS 26 eklentinin yönlendirmesini reddediyor** (planın H3'ü, ölçüldü,
AÇIK): L1+L2 düzeldikten sonra uzantı **çalışıyor ve payload'ı App Group'a
YAZIYOR** (`group.…plist` → `ShareKey => [{"path":"https:…","type":"url"}]`) —
ama logda uzantının kendi süreci basıyor:
`BUG IN CLIENT OF UIKIT: The caller of UIApplication.openURL(_:) needs to
migrate to the non-deprecated UIApplication.open(...). Force returning false (NO).`
`RSIShareViewController.redirectToHostApp()` responder zincirinde `openURL:`
selector'ünü arıyor; iOS 18+ bunu zorla NO döndürüyor ve `UIApplication` zaten
uzantılara kapalı. Denenen ve **yetmeyen** çözüm: zincirin ilk halkası bizim
sınıfımız olduğu için `ShareViewController`'a `@objc func openURL(_:)` konup
`extensionContext.open(_:)`e çevrildi — uygulama yine öne gelmedi (kod repoda,
gerekçesiyle; zararsız ve doğru API). **Kalan iş:** `receive_sharing_intent`
≥1.8 (SPM-only — repo CocoaPods, gerçek maliyet) / alternatif paket / uzantıya
kendi compose UI'ını verip yönlendirmeyi bırakma → **ADR-0029**._

_**Bugünkü net kazanım:** paylaşılan içerik artık KAYBOLMUYOR. L1 öncesi hiçbir
şey yazılmıyordu; şimdi App Group'a düşüyor ve `getInitialMedia()` uygulamanın
bir sonraki açılışında onu okuyor. "Hiçbir zaman hiçbir şey" → "uygulamayı
açtığında orada". L3 kapanınca anında olacak._

_**Teşhis izi kondu** (bir daha kanıtlanamaz rapor olmasın): drift v16
`share_events` + `ShareLog` (AlarmLog'un birebir ikizi: asla fırlatmaz, 100'lük
halka tampon, **içerik ASLA — yalnız tür ve bayt**), `shareBinderProvider`
artık her varışı ve her okuma hatasını yazıyor (eskiden hepsini sessizce
yutuyordu), Ayarlar → **Paylaşım günlüğü** (`/settings/share-log`) kopyala
butonlu. Ekranın kapsam cümlesi asıl bulguyu taşıyor: **boş liste bir eksiklik
değil, CEVAPTIR** — içerik Dart'a hiç ulaşmamış demektir. Bekçi testi
`test/native_config_test.dart` (`web_shell_test.dart` kalıbı) şemayı ve Android
filtrelerini koruyor.)_

- [x] **Üç hipotez SIRAYLA elenir, atlanmaz** (Epic 22'nin dersi: "spec var ≠ davranış
      var"; round 16'nın dersi: "üretilemeyen hatanın değişkeni genelde senin
      ortamındır" — bu kez raporcunun cihazı bizde, o yüzden ölçüm cihazda yapılır):
      **H1** `ios/Runner/Info.plist`'e `CFBundleURLTypes` → `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`
      eklenir (bulgu #1) ve gerçek iPhone'da paylaşım denenir; **H2** düzelmezse sahne
      yolu ölçülür — `scene(_:willConnectTo:)`'ın `connectionOptions.urlContexts`'i ile
      `scene(_:openURLContexts:)` ayrı ayrı loglanır (bulgu #3: soğuk başlangıçta
      ikincisi çağrılmaz); **H3** hâlâ düzelmezse uzantının `openURL:` çağrısının iOS
      18+ tarafından reddedildiği kabul edilir (bulgu #2) ve **`Console.app`/`log stream`
      çıktısı kanıt olarak STATE'e yazılır**.
- [x] **App Group gerçekten yazıyor mu:** uzantı payload'ı `UserDefaults(suiteName:
      "group.com.alliswell.alliswell")`'e yazamıyorsa (provisioning profile App Group'u
      taşımıyorsa) yönlendirme çalışsa bile uygulama BOŞ açılır. Uzantı tarafında
      suite'in `nil` olma durumu ayrı ayrı ölçülür ve ayırt edilir.
- [x] **H3 çıkarsa yol ayrımı ADR ile:** `receive_sharing_intent` ≥1.8 / alternatif
      paket / uzantıya kendi compose UI'ını verip payload'ı App Group'a yazdırıp
      yönlendirmeyi bırakmak (uygulama bir sonraki açılışta okur — "sessizlik" yerine
      "gecikme", dürüst bir düşüş).
      **Düzeltme (2026-08-10, ölçüldü): "≥1.8 SPM-only" YANLIŞ.** SPM-only olan
      **1.9.0**; **1.8.1** hâlâ podspec taşıyor ve changelog'u düpedüz _"Fixed sharing
      not working on iOS 18"_ diyor. Kurulu sürüm de 1.6.8 değil **1.7.0**
      (`pubspec.lock`; upstream podspec'te `s.version` bump'ını unutmuş). Bu yüzden
      **ilk iş 1.8.1'i gerçek cihazda ölçmek** — düzeltirse ~200 satır Swift hiç
      yazılmaz. `pubspec.yaml`'daki `<1.8.0` pin'inin gerekçe yorumu ve
      `ShareViewController.swift:31-32` bu yanlışı taşıyor, ikisi de düzeltilecek.
      Karar **ADR-0029** olur (0028 markdown'a ayrıldı — OPH-246) ve
      [ADR-0023](adr/0023-stt-and-share-intent-dependencies.md)'ü **süpersede etmez,
      §3'ünü tadil eder**: 0023 üç konulu bir ADR (STT + paket seçimi + uzantı
      davranışı) ve diğer ikisi geçerli kalıyor; değişen tek cümle "…and opens the host
      app". Uzantının **ağ ve AI yapmaması** güvencesi aynen duruyor. Sessizce paket
      değiştirilmez.
- [x] **Android hattı da ölçülür** (sahip yalnız iPhone denedi): `ACTION_SEND`
      `text/plain` gerçek cihazda Chrome/Gmail'den denenir, soğuk + sıcak.
- [x] **Bir daha "kanıtlanamaz arıza" olmasın:** paylaşım hattına Epic 16'nın alarm
      günlüğü kalıbıyla **teşhis kaydı** eklenir — `initialShare`/`shares`/
      `initialDocument`/`documents` her tetiklendiğinde cihaz-yerel bir halka tampona
      (zaman + tür + bayt sayısı, **içerik değil**) yazar ve Ayarlar → Tanılama'dan
      görünür. Sahibin "hiçbir şey olmadı" raporu bir dahaki sefere ölçülebilir olur.
- [x] Testler: `Info.plist`'te `ShareMedia-` şemasının varlığını **bekçileyen** bir test
      (round 16'nın `web_shell_test.dart` kalıbı — `flutter create` bu dosyayı toptan
      yeniden yazabilir); teşhis halka tamponunun saf birim testleri (sıra, kapasite,
      içerik taşımadığı).
- **Kabul:** gerçek bir iPhone'da Safari'de metin seç → Paylaş → AllisWell → uygulama
  açılır ve payload gelir (soğuk VE sıcak); aynısı Android'de; hangi hipotezin doğru
  çıktığı ve neden, TASKS'a + STATE'e yazılır.
- **Doğrulama:** `flutter analyze` · `flutter test` · cihazda soğuk/sıcak paylaşım turu
  (ekran kaydı ya da tanılama ekranı görüntüsü) · `log stream --predicate 'subsystem
  contains "alliswell"'` çıktısı.

### OPH-243 — Paylaşılan metin gerçekten işe dönüşsün: AI varsa görev, yoksa Inbox + sebep

_(✅ 2026-08-10 — hedef sahibin ikinci kararıyla değişti ve öyle uygulandı:
**AI sağlayıcısı yoksa paylaşım sessizce Inbox'a düşer ve bir diyalog sebebini
söyler** (Sağlayıcı ekle / Inbox'ı aç / Tamam), her iki platformda. Sıra
bağlayıcı: önce yakala, sonra göster — diyalog yutulsa bile metin duruyor, ve
test tam bunu assert ediyor._

_**Soğuk başlangıç boşluğu kapandı.** `AiStatusController.build()` `_cacheKey`'i
guard'dan **sonra** atıyordu, yani localKv cache'i soğuk açılışta hiç
okunmuyordu; AI FAB'i ilk karede provider'ı okuduğu için yer tutucu
`disabled` yapışıyor ve AI'lı kullanıcının paylaşımı yanlış dala gidiyordu.
Cache artık guard'dan önce okunuyor. `share_routing_test.dart`'ın yazılı GAP'ı
üç gerçek testle değiştirildi: cache biliyorsa soğuk paylaşım bubble'a gider ·
bayat cache bubble'ın kendi unconfigured yüzüyle düzeltilir · cache yoksa dürüst
dala düşer (metin Inbox'ta, sebep ekranda)._

_**Değişmeyen ve gerekçesi yazılan:** `ai_bubble.dart`'ın `AiRouteOffline` → Inbox
düşüşü kaldı. Diyalog "hiç sağlayıcı yok" diyor; o dal sağlayıcı **varken** ağ
patladığında çalışıyor. Sağlayıcısı olana "sağlayıcı ekle" demek yalan olurdu._

_Önceki tur (2026-08-09/10): sahibin ilk kararı uygulanmıştı — **AI yokken dolu
create sheet** ("Not al" ve "Inbox'a kaydet" paylaşım yolundan kalktı; AI açıkken
bubble'da duruyorlar — bilinçli bir yetenek kaybı, sessiz değil). `home_shell`
artık `_routeShare` ile karar veriyor: `configured` ise bubble, değilse
`showTaskCreateSheet(initialTitle:, initialDescription:)`. Sheet iki yeni
parametre aldı ve prefill'de **caret sona alınıyor** — alan autofocus'lu, dolu
ve baştan seçili bir alan paylaşılanı tek tuşla siler._

_**Saf çekirdek ayrıldı:** `features/tasks/data/task_text.dart` —
`clipTaskTitle` (kontrolörün `_clipTitle`'ı buraya TAŞINDI, üç kopya olmasın)
+ `taskFieldsFromSharedText`. Testin yakaladığı gerçek kusur: ilk satır
kırpılmıyordu, yani görünmez bir sondaki boşluk başlığa sızıyordu — artık
trim'leniyor ve gövde kararı uzunlukla değil DEĞERLE veriliyor._

_**Testin yakaladığı ikinci, daha ciddi şey — AÇIK:** yeni
`share_routing_test.dart` gerçek yolu (binder → shell → hedef) sürüyor, çünkü
mevcut `ai_share_test.dart` bubble'ı doğrudan açıp bu kararı hiç göremiyor.
AI-kapalı yol yeşil. **AI-açık + SOĞUK başlangıç ise yanlış dala gidiyor:**
`AiStatusController.build()` `currentWorkspaceProvider`'ın değeri yokken
düpedüz `AiStatus.disabled` dönüyor ve ilk karede biri provider'ı okuyor →
durum "AI yok" diye çözülüyor, soğuk paylaşım tam o pencereye düşüyor.
`_aiStatusForShare` içinde `workspacesProvider`'ı beklemek YETMİYOR (provider
o ana kadar yer tutucuyla tamamlanmış oluyor). Doğru düzeltme çağrı yerinde
bir yama değil, `aiStatusProvider`'a "workspace henüz yok" ile "AI kapalı"
arasındaki farkı öğretmek — beş yüzeyin bağlı olduğu bir provider. Gap testin
içine gerekçesiyle YAZILDI (saklanmadı) ve sıcak paylaşım varyantı yeşil.
Kullanıcı maliyeti tek yönlü ve küçük: soğuk uygulamaya paylaşan AI'lı kullanıcı
bubble yerine dolu create sheet görür — çalışan bir hedef, çıkmaz değil.)_

> **Hedef 2026-08-10'da DEĞİŞTİ (sahibin kararı).** Aşağıdaki maddeler yeniden yazıldı;
> başlıktaki "yoksa dolu create sheet" cümlesi artık geçersiz. Eski hedef — AI yoksa
> başlığı dolu create sheet — round 17'de sahibin isteğiydi ve kısmen sevk edildi; sahip
> bunun **bilinçli olarak geri alınmasını** istedi: paylaşım artık bir AI özelliği olarak
> konumlanıyor. Bu, Android'de **çalışan** bir yolun kaldırılması demek ve öyle kayda
> geçiyor — sessiz bir kırpma değil.

- [x] **AI yapılandırılmamışsa** (ya da `AI_ENABLED=false`), **her iki platformda**:
      paylaşılan metin **sessizce Inbox'a kaydedilir** (`captureToInbox`, sıfır AI) ve
      ardından bir **diyalog** "bu özellik için bir AI sağlayıcısı gerekiyor" der.
      Sıra bağlayıcı — **önce kaydet, sonra göster**: diyalog bir rota değişimiyle
      yutulursa metin zaten güvende olmalı.
- [x] Diyalog **çıkmaz sokak olamaz**: birincil eylem **Sağlayıcı ekle** →
      `context.push('/settings/ai')`; ikincil **Inbox'ı aç** →
      `context.go(AppSection.inbox.path)` (Inbox bir **shell branch**, `push` değil —
      `router.dart:184-199`); üçüncüsü sade kapatma. Diyalog Inbox'ı **adıyla söylemek
      zorunda**, yoksa "sessiz kayıt" kara deliğe döner.
- [x] **Soğuk başlangıç boşluğu kapanır:** `AiStatusController.build()` localKv
      cache'ini **guard'dan önce** okur (bugün `_cacheKey` guard'dan sonra atanıyor, yani
      cache soğuk başlangıçta hiç kullanılmıyor ve AI'lı kullanıcı yanlış dala gidiyor —
      `share_routing_test.dart`'ın yazılı GAP'ı). Beş yüzey tek tek gözden geçirilir;
      riskli olan tek yer `ai_bubble_controller.dart:85`'in senkron `.value` okuması.
- [x] **AI yapılandırılmışsa:** bugünkü yol korunur ve tamamlanır — bubble açılır,
      `extractUtterance(source:'share')` çalışır, sonuç **onay kartına** iner
      (v1 değişmezi: onay kartı atlanamaz).
- [x] **`ai_bubble.dart`'ın `AiRouteOffline` → Inbox düşüşü KALIR** ve gerekçesi yazılır:
      yukarıdaki diyalog "hiç sağlayıcı yok" diyor (yapılandırma), bu dal ise sağlayıcı
      **varken** ağ patladığında çalışıyor. Sağlayıcısı olan birine "sağlayıcı ekle"
      demek yalan olurdu. İki yol bir bakışta aynı görünüyor; biri gelip "birleştirmesin".
- [x] Beş çip (Görev yap / Not al / Özetle / Soru sor / Inbox'a kaydet) AI'lı yolda
      aynen kalır.
- [x] Paylaşılan içerik **markdown dosyasıysa** OPH-241'in görüntüleyicisine gider —
      **zaten böyle**: `.md` `documents()` kanalından gelip `pendingMarkdownProvider`'a
      düşüyor, `_routeShare`'e hiç uğramıyor. Madde doğrulama olarak duruyor.
- [x] `ShareLogEvent.consumed` bugün tanımlı ama **hiç yazılmıyor** — log varışı
      kanıtlıyor, tüketimi kanıtlamıyor. `take()` sonrasında yazılır ve `detail` alanına
      hedef (`bubble` / `no_provider`) konur. Not: her paylaşım artık **iki** satır
      yazacak, `kShareLogLimit = 100` etkin geçmişi yarıya indiriyor.
- [x] i18n: yeni dizeler `en`+`tr` (`ai.share.noProviderTitle/Body/openInbox/dismiss`;
      birincil eylem mevcut `ai.settings.addProvider`'ı kullanır); `check:i18n` temiz.
- [x] Testler: AI kapalı → **diyalog** açıldı + **Inbox satırı replica'da var** +
      `api.aiExtractCalls == 0`; diyalog hemen kapatılsa bile satır duruyor (kararın asıl
      garantisi); "Sağlayıcı ekle" → AI ayarları, "Inbox'ı aç" → shell duruyor
      (`push`/`go` hatasını yakalar); **soğuk başlangıç + cache'te `configured: true` →
      bubble** (bu test `main`'de kırmızı olmalı); bayat cache + sunucu "AI yok" → bubble
      açılır, oturunca unconfigured yüzü gelir.
- **Kabul:** AI'lı kullanıcı paylaştığını **soğuk başlangıçta da** bubble→onay kartında
  görür; AI'sız kullanıcı ne kaybeder ne de sessizce bırakılır — metni Inbox'ında, sebebi
  ekranında bulur.
- **Doğrulama:** `flutter analyze` · `flutter test` · `npm run check:i18n`.

### OPH-244 — Ek seçimi üç yol: Fotoğraflar · Kamera · Dosyalar (DESIGN §30 A1–A4)

_(✅ 2026-08-10. Sahibin kararıyla **kamera da girdi**. Planlama turunun iki
varsayımı ölçülünce ters çıktı ve ikisi de kararı değiştirdi:_

_**(1) `file_picker` Android'de A2'yi karşılayamıyor.** iOS'ta `FileType.media`
gerçekten PHPicker açıyor, ama Android tarafı (`FileUtils.kt:180-250`)
`ACTION_GET_CONTENT` kuruyor — `ACTION_PICK_IMAGES`/`PickVisualMedia` değil.
Yani yalnız çağrıya tip eklemek iPhone'u düzeltip Android'i raporun tarif ettiği
yolda bırakırdı. Medya kaynakları mobilde **`image_picker`**'a gitti._

_**(2) `image_picker` korkusu yersizmiş, asıl riskli paket başkasıymış.**
pub-cache'teki BEŞ `image_picker_android` sürümünün hiçbiri `<uses-permission>`
beyan etmiyor (flutter#171493/171494 uygulamaların KENDİ manifest'leri
hakkındaymış). Gerçek risk `camera`: `camera_android_camerax-0.6.30` manifest'i
`CAMERA` + `RECORD_AUDIO` + **`WRITE_EXTERNAL_STORAGE`** beyan ediyor →
**ADR-0027'de gerekçesiyle reddedildi.**_

_**Yeni beyan yüzeyi tek dize:** iOS `NSCameraUsageDescription`. Android'de
SIFIR izin — ve bu iddia **ölçülüyor**: `scripts/android/assert-permissions.sh`
release APK'sının **ikili manifest'ini** (Play'in taradığı katman, ara
`merged_manifests` değil) commit'li bir allowlist'le TAM KÜME olarak
karşılaştırıyor; denylist değil, çünkü asıl tehlike kimsenin beklemediği izindir.
Allowlist gerçek bir build'den dolduruldu — kimsenin tahmin edemeyeceği satırlar
içeriyor (`ACCESS_ADSERVICES_*`, `AD_ID`, `USE_BIOMETRIC`, `READ_GSERVICES`).
İlk koşu: **18 izin, hiçbiri medya ya da kamera.** CI'ye ayrı bir
`android-manifest` job'ı eklendi (hızlı şerit hızlı kalsın). **Hiçbir Dart testi
bunu doğrulayamaz** — birleşmiş manifest yalnız build'de vardır._

_**İki tuzak daha, ikisi de kodda yorumlu:** `useAndroidPhotoPicker` varsayılan
**false** (flip edilmezse düzeltilen hatanın aynısına düşer), ve masaüstünde
`ImageSource.camera` **`StateError` fırlatıyor** → `attachMenuSources` kamerayı
orada sunmuyor; bu cila değil doğruluk gereği ve birim testi altı platformu da
geziyor._

_**Diki̇ş:** `attach_source.dart` (saf enum + platform yüklemi + FileType
eşlemesi + `cameraCaptureName`), `filePickerProvider` artık `FilePickerFn` ve
argüman **zorunlu pozisyonel** — varsayılan olsaydı bir sonraki çağıran aynı
şekilde unutabilirdi. `pickAndUpload` ÖLDÜ, yerine `uploadAll`: seçim widget
katmanının işi, notifier'ın seçiciyi okuması yanlıştı. Böylece
`filePickerProvider` tek yerden okunuyor (`attach_menu.dart`)._

_**Yüzeyler:** görev ekleri, Dosyalar, proje dosyaları ve create sheet ortak
`AttachButton`'a geçti (aynı buton TİPLERİ korundu — mevcut testler tipe assert
ediyor); notlarda iki buton artık **adını söylediği** kütüphaneyi açıyor
(ipucu metni yalan söylemeyi bıraktı); zil sesi seçicisi `audioFiles` istiyor ve
seçim spinner'ın ÜSTÜNE alındı. Açıklama alanı kendi ek butonunu aldı (A4) —
`_DescriptionField` bir `attach` slot'u alıyor, çünkü boşluk durumunu yalnız o
biliyor; oradan yüklenen dosya aşağıdaki Ekler listesine düşüyor (tek varış,
iki kapı). **A8 boşluğu kapandı:** `PlatformException` hiçbir yerde
yakalanmıyordu, `pickAndUpload`'dan asenkron hata olarak sızıyordu._

_**Testler (+13, toplam 834):** `attach_source_test` altı platform × altı
kaynak (saf); menü üç yolu gösteriyor ve Fotoğraflar **`photoLibrary` istiyor**;
tek kaynaklı platformda sheet HİÇ açılmıyor; `PlatformException` → dürüst
snackbar, çökme yok; açıklama alanından yükleme aynı listeye düşüyor;
**notlardaki iki butonun doğru kütüphaneyi çağırdığı** — bu dosyanın en değerli
assert'i, çünkü asıl yalanı yakalayacak olan oydu. Ortak `RecordingFilePicker`
artık NİYETİ assert ediyor, "bir dosya geldi"yi değil. `FLUTTER_TEST` altında
`defaultTargetPlatform` zorla android olduğu için her widget testi üç maddelik
menüyü görüyor — `attachSourcesProvider`'ın provider olmasının sebebi bu._

_**Kalan (cihaz turu, DoD'de zaten vardı):** gerçek iPhone/Android'de **[KAPATILDI 2026-08-12 — sahibin kararı, agent ölçümü değil.]**
Fotoğraflar'ın foto ızgarasını açması, **izin diyaloğu ÇIKMAMASI** ve kameranın
çekmesi. iOS derlemesi doğrulandı: `image_picker_ios.framework` bağlandı ve
`NSCameraUsageDescription` ÜRÜNDE.)_

- [x] `pickUploads()` tek bir girişten çıkıp **niyet alan** bir API'ye döner:
      `pickUploads(AttachmentSource source)` — `photos` → `FileType.media`
      (iOS'ta `PHPickerViewController`, bulgu #4), `files` → bugünkü `FileType.any`
      belge seçici. Web/masaüstü tek yolda kalır (orada ayrım yok) — seam korunur,
      `filePickerProvider` imzası testlerde enjekte edilebilir kalır.
      **Sevk edilen şekil farklı ve gerekçesi yukarıda:** medya kaynakları mobilde
      `image_picker`'a gitti (Android'in `file_picker` yolu `ACTION_GET_CONTENT`
      kuruyor), `pickAndUpload` öldü ve yerine `uploadAll` geldi.
- [x] **Kamera** kararı bu task'ta verilir ve YAZILIR: `file_picker` kamera açmaz.
      Ya yeni bir bağımlılık gelir (ADR + bulgu #6'nın Play riski ölçülerek) ya da
      "Kamera" **v1'de sunulmaz** — sunulmayacaksa menüde yer almaz (dead affordance
      yasak, §22). Karar gerekçesiyle DESIGN §30'a işlenir.
      **Karar: kamera GİRDİ** (sahibin isteği) ama `camera` paketiyle değil —
      o paket `WRITE_EXTERNAL_STORAGE` beyan ediyor ve **ADR-0027'de reddedildi**;
      `image_picker`'ın `ImageSource.camera`'sı kullanıldı.
- [x] **Android tarafı ölçülür**: `file_picker`'ın `FileType.media` yolu Android 13+
      Photo Picker'a mı düşüyor yoksa `ACTION_GET_CONTENT`'e mi — ve **hangi izinleri
      manifest'e ekliyor**. `READ_MEDIA_IMAGES` görünürse (bulgu #6) alternatif ölçülür;
      hiçbir koşulda geniş medya izni beyan edilmez.
      **Ölçüldü:** `ACTION_GET_CONTENT`. Sıfır medya/kamera izni, ve bu iddia artık
      `scripts/android/assert-permissions.sh` ile release APK'sının ikili
      manifest'inden TAM KÜME olarak zorlanıyor (ilk koşu: 18 izin).
- [x] `AttachmentsSection`'ın tek "Dosya ekle" butonu **üç maddelik bir menüye** döner
      (DESIGN §30 A1); her madde ne açtığını söyler.
- [x] **Açıklama alanında da ek yolu** (A4): görev oluşturma sheet'i ve görev detayının
      açıklama bloğunun altına aynı menü — sahip önce orada aradı.
- [x] Görsel ekler **küçük resim** olarak listelenir (A5), diğerleri bugünkü satır
      olarak. Küçük resim `fileUrlProvider` cache'ini kullanır (OPH-153'ün dersi:
      widget build'inde future üretme).
      **Zaten öyleymiş** (`FileLeadingThumb`, 40 px satır küçük resmi) — sahip
      görmemişti çünkü zaten fotoğraf ekleyemiyordu. Izgara ise OPH-245'te
      bilinçli olarak REDDEDİLDİ (§10 F1); DESIGN §30 A5 buna göre tadil edildi.
- [x] i18n + kontrast: yeni menü/dizeler `en`+`tr`; `contrast.py` **FAILURES: 0**.
- [x] Testler: her kaynak doğru `FileType` ile çağırıyor (fake picker enjekte edilir,
      platform kanalı yok); menü üç madde gösteriyor (kamera kararına göre iki/üç);
      depolama yapılandırılmamışken menü açılmıyor ve mevcut açıklayıcı satır kalıyor;
      küçük resim ızgarası + bozuk görselde dürüst yer tutucu.
- **Kabul:** gerçek iPhone'da "Fotoğraflar" fotoğraf ızgarasını açar, **izin diyaloğu
  çıkmaz**, seçilen fotoğraf yüklenir; "Dosyalar" bugünkü belge seçicidir; aynısı
  Android'de. Play/App Store için **hiçbir yeni izin beyanı yok**.
- **Kalan (cihaz turu — sahibe ait, agent akışını bloklamaz):** iki gerçek cihazda **[KAPATILDI 2026-08-12 — sahibin kararı, agent ölçümü değil.]**
  "Fotoğraflar" foto ızgarasını açıyor mu · **izin diyaloğu ÇIKMIYOR** mu (ADR-0027'nin
  ölçülmüş sıfır-izin iddiasının kullanıcı tarafındaki kanıtı) · kamera çekip yüklüyor
  mu · "Dosyalar" belge seçici mi. Kanıt buraya yazılır. Epic 24'ün açık üç turu
  STATE'in "Açık cihaz turları" bloğunda toplu listeleniyor.
- **Doğrulama:** `flutter analyze` · `flutter test` · `npm run check:i18n` ·
  `python3 scripts/design/contrast.py` · iki cihazda seçici turu.

### OPH-245 — `AwImageViewer`: zoom, kaydırma, galeri (DESIGN §30 A6–A8, A11)

_(✅ 2026-08-10. **İki viewer vardı, biri diğerinden zayıftı** — `_EmbedImageViewer`'ın
`loadingBuilder`/`errorBuilder`'ı bile yoktu. Planın üç varsayımı ölçülünce ters çıktı:_

_**(1) Not içinde belge sırası için kablolama gerekmiyormuş.** `EmbedContext` zaten
`QuillController` taşıyor (`flutter_quill-11.5.1/.../embed_context.dart:17-41`) — provider
da, InheritedWidget da, builder parametresi de gereksiz. Üç `awNoteEmbedBuilders()`
çağrısının (editör, proje README, markdown import önizlemesi) hepsi controller veriyor._

_**(2) A8 teslim edilebilir değilmiş.** `FileUrlCache.urlFor` `ApiException`'ı yutup `null`
dönüyordu, yani "ağ yok" ile "dosya silinmiş" widget'a **aynı hiçlik** olarak varıyordu ve
üçü de `file.couldNotOpen` ("İndirme bağlantısı alınamadı") yazıyordu — üçünden yalnız biri
için doğru bir cümle. Sebep artık cache'te tutuluyor._

_**(3) `onMore` kısa devresi bug değil, OPH-170'in bilinçli kararıymış**
(`file_widgets.dart:134-136`). "Görseller `onMore`'u atlasın" naif düzeltmesi Taşı… ve
Kaynağa git eylemlerini **öksüz bırakırdı**; çözüm bir dal silmek değil bir affordance
**eklemek** oldu — klasör satırlarının zaten kullandığı ⋯ düğmesi._

_**Yol boyunca bulunan canlı hata:** `confirmFileDelete` `Future<void>` döndürüyordu ve
`_FileImageViewer` onayı beklemeden koşulsuz `pop` ediyordu — yani **silmeyi iptal etsen
bile görüntüleyici kapanıyordu**. Artık `Future<bool>`._

_**Dikiş:** `networkImageProvider` (`filePickerProvider` kalıbı). `flutter_test`'in HTTP
mock'u her isteğe sıfır bayt döndürüyor, o yüzden depoda bugüne dek **hiçbir test gerçek
bir görsel çizmemişti** — "çift dokunuş yakınlaştırıyor" ancak hata sayfası üzerinde test
edilebilirdi. Süitler 874 (+18).)_

- [x] `_EmbedImageViewer` + `_FileImageViewer` çıkarılıp tek **`AwImageViewer`** olur —
      §22'nin ders kitabı vakası. **`widgets/` altına değil**
      (`features/files/ui/image_viewer.dart`): `lib/src/widgets/`'taki on dosyanın hiçbiri
      `features/`'tan import etmiyor, görüntüleyici ise dört dosya provider'ı istiyor.
      `Aw` bir **isim** kuralı, klasör kuralı değil (`AwNoteImageEmbed`, `AwRefresh`).
- [x] **Dosya id'si alır, `FileAttachment` değil:** not galerisi delta yürüyüşünden ULID
      veriyor, ve yeni yüklenmiş bir görselin replica satırı henüz yok — tip'li bir API
      tam da o görseli açılamaz yapardı (eski embed viewer'ında olmayan bir gerileme).
- [x] Yetenekler: **pinch-zoom** (`maxScale: 6`), **çift-dokunuşla 2.5×**, odak
      **dokunulan nokta** (`T(p)·S·T(-p)`, `AwMotion.base`, içeri `enter` / dışarı `exit`),
      **pan**, **hedefin görselleri arasında yatay kaydırma**, üstte dosya adı + `n/m`,
      `Esc` + klavye zoom/sayfalama. **Zoom'luyken sayfalama kapanır** (yatay sürükleme
      pan etmeli, sayfa çevirmemeli).
- [x] **Paylaş/kaydet YOK** (sahibin kararı) — bugünkü **Aç/İndir + Sil** aynen kalır ve
      satır replica'dan gelene kadar **disabled** (ölü buton yasak). DESIGN §30 A6 buna
      göre tadil edildi; gerekçe ADR-0027'nin ölçülmüş sıfır-izin kazanımı.
- [x] Galeri ortasında silme **kapatmaz, sonrakine geçer**; son görsel silinirse kapanır;
      **iptal edilen silme hiçbir şey yapmaz** (bugünkü hatanın düzeltilmesi).
- [x] Beş yüzeyden de aynı görüntüleyici açılır (A7): görev ekleri, Dosyalar → klasör,
      Dosyalar → Kaynaklar, proje Dosyalar sekmesi, not gömüleri. `FileRowTile`'ın dokunuşu
      **türe** bakar; `onMore` yeni bir **⋯** düğmesine taşındı (`file-menu-{id}`).
- [x] Galeri, yüzeyin **gösterdiği** kümedir ve **gösterdiği sıradadır** (yeni A11):
      proje sekmesi `_arrange` sonrasından, not **belge sırasından** (`deltaToBlocks` —
      PDF export'un yürüdüğü aynı yol, sıra ikisi arasında ayrışamaz).
- [x] Hata durumunda **sebepli** mesaj (A8): altı sonuç — çevrimdışı / silinmiş (404) /
      başka bir sunucu kodu (`localizedError`) / depolama kapalı / henüz bağlantı yok /
      bağlantı çalıştı ama baytlar çözülemedi. Veri katmanı değişikliği gerekti:
      `FileUrlCache.errorCodeFor` + `fileUrlResultProvider`.
- [x] Erişilebilirlik: sayaç `Semantics` etiketi taşır (`file.viewerPosition`), eylemler
      tema tap hedefli `IconButton`, klavye kısayolları (`Esc`, oklar, `+`/`-`/`0`) —
      depoda ilk `CallbackShortcuts` kullanımı, çünkü `fullscreenDialog` rotası `Esc` ile
      kendiliğinden kapanmıyor.
- [x] i18n: yedi yeni `file.*` anahtarı `en`+`tr`; hepsi `extraction_test.dart`'a yazıldı
      (`check.mjs` bunları göremiyor — biri argüman olarak gidiyor, biri zaten `.tr(`
      sarmalında, yani yanlış yazılmış bir anahtar CI'dan sessizce geçerdi).
- [x] Testler: `test/widgets/image_viewer_test.dart` (12) — çift dokunuşun **ölçeği ve
      çevirisi** dokunulan noktaya uyuyor, sayaç, tek görselde sayaç yok + physics kilitli,
      zoom'luyken sayfalama kapalı, altı hata sebebi, `Esc`, oklar, satır gelmeden eylemler
      disabled. `test/features/files/image_viewer_surfaces_test.dart` (3) — A7 çifti:
      satır viewer'ı açıyor **ve** ⋯ hâlâ "Taşı…"ya ulaşıyor; görsel olmayan satır hâlâ
      sheet açıyor. `note_media_test.dart` — yükleme sırası **ters** üç görselli not
      (`targetFilesProvider`'a bağlanırsa kırmızıya döner).
- **Kabul:** göreve eklenen bir fotoğrafın üstüne dokunulunca tam ekran açılır, iki
  parmakla büyütülüp gezilebilir, diğer fotoğraflara kaydırılarak geçilir.
- **Doğrulama:** `flutter analyze` · `flutter test` · `python3 scripts/design/contrast.py`.
- [x] **Cihaz turu — sahip tarafından doğrulandı (2026-08-10).** Kapsam: köşeye çift
      dokunuşun o köşeyi sabit tutması · dört fotoğraflı bir görevde kaydırma + sayaç ·
      galeri ortasında silmenin sonrakine geçmesi · yükleme sırası ters bir notta
      kaydırmanın gövde sırasını izlemesi · dar ekranda ⋯ + kaynak rozeti · Android
      sistem geri tuşu · masaüstünde `Esc` / oklar / `Tab`.

### OPH-246 — Markdown: model kararı + render motoru seçimi + ADR-0028 (kod yazmaz)

> **Bu epic'in en büyük işinin kapısı. 247–252'nin hiçbiri bu task bitmeden başlamaz.**
> Alan taraması ve özellik envanteri planlama turunda yapıldı ve
> **[MARKDOWN.md](MARKDOWN.md)**'ye yazıldı (13 ürün, 41 özellik kararı, kaynaklar §9).
> Bu task o dokümanın açık bıraktığı **iki kararı** kapatır.

_(✅ 2026-08-10 — **ADR-0028 kabul edildi.** Planın "ölçülerek karar ver"i
harfiyen uygulandı ve **iki varsayımı ters çevirdi**:_

_**(1) Ağaçtaki `markdown` 7.3.1 sanılandan çok daha fazlasını veriyor.**
`ExtensionSet.gitHubWeb` tabloyu **hizalamasıyla**, görev listesi kutularını,
**dipnotları** ve **GFM uyarı kutularını** (`[!NOTE]`) hazır getiriyor — MARKDOWN.md
§5'in aday tablosu bunların yazılacağını varsayıyordu. Fikstüre karşı ölçüm:
**22 kalemden 19 HAZIR**, üç eksik ve üçü de küçük birer özel syntax
(matematik `$…$`, `==vurgu==`, front matter)._

_**(2) Kararı veren şey kapsam değil, KONUM haritası çıktı.** `markdown`'ın
AST'si **hiçbir düzeyde kaynak konumu taşımıyor** — `Element`'te de `Line`'da da
yok. D4 (okuma modunda tıklanan checkbox belgeye yazar), D13/D14 (anahat,
katlama), D16 (çapalar) ve D5 (senkron kaydırma) dördü de "düğüm → kaynak satırı"
haritası istiyor ve **hiçbir aday bunu vermiyor**. Yani o katman hangi parser
kazanırsa kazansın bizim — ki paketli bir renderer'ı tercih etmenin ana sebebi
buydu. Prototip, paketi **fork'lamadan**, 110 üst düzey düğümün **109'unu**
damgaladı ve **29 başlığın 29'unu** kaynakta doğruladı; dört public dikişle
(`Line` alt sınıflanabilir · `parseLineList(List<Line>)` public · `BlockParser.lines`
public · `withDefaultBlockSyntaxes: false` tüm listeyi bize verdiriyor ·
`Element.attributes` değiştirilebilir)._

_**Yol boyunca düzeltilen kendi ölçüm hatam:** ilk koşu "tablo hizalaması YOK"
dedi; paket hizalamayı `align="center"` attribute'üyle veriyor, CSS
`text-align` ile değil. Yanlış negatifti, kapsam 18 değil **19**. Bir ADR'ye
yanlış sayı yazmaktansa ölçümü iki kez koşmak ucuz._

_**Sahibin iki kararı ADR'ye girdi:** matematik VE mermaid gerçekten çizilir
(web view kesin hariç). Mermaid **kendi task'ına ayrıldı — OPH-254** — çünkü
flowchart bir katmanlı çizim algoritması, sequence ise neredeyse doğrusal;
ikisinin maliyeti bir mertebe farklı ve OPH-247'nin içinde kalsalardı o task üç
işi birden yapardı. Yazılı çıkış kapısı var: yerleşim kalitesi tutmazsa D11 yer
tutucusuna düşülür ve ADR tadil edilir._

_**Fikstür bilerek zararlı girdi taşıyor** (`javascript:` linki, canlı olmaması
gereken HTML bloğu, çözülemeyen görsel) ve bunu kendi içinde söylüyor — D10'un
kanıtı oradan çıkacak.)_

- [x] **Karar 1 — not modeli.** [MARKDOWN.md §4](MARKDOWN.md)'ün üç seçeneği
      (A: Delta kanonik + özel embed'ler · B: Markdown kanonik · C: niyete göre bölünmüş,
      `content_format` bayrağı) implementasyon gözüyle tartılır. Ölçülecekler: mevcut
      notların sayısı ve şekli (kaç tanesi salt-metin, kaç tanesi embed taşıyor),
      migration maliyeti, `AGENTS.md` §6 çatışma politikasının (belge düzeyi iyimser
      kilit + çatışma kopyası) her seçenekte ne olduğu, ve OPH-241'in ROUND TRIP
      garantisinin akıbeti.
- [x] **Karar 2 — render motoru.** Dört aday (`flutter_markdown_plus` (+`_latex`),
      `markdown_widget`, `gpt_markdown`, `flutter_smooth_markdown`) ve "kendi
      renderer'ımız (`markdown` Dart paketi üzerine)" **ÖLÇÜLEREK** karşılaştırılır:
      GFM kapsamı (tablo/dipnot/uyarı/görev listesi), token'lı tema kabiliyeti
      (DESIGN §29 D7 — paketin varsayılan stilleri KABUL EDİLEMEZ), güvenli render
      (D10: ham HTML inert, `javascript:`/`data:` inert), altı platform, bakım durumu,
      paket boyutu. Ölçüm bir **fikstür belgesiyle** yapılır (aşağıdaki madde).
- [x] **Kabul fikstürü yazılır** — `apps/app/test/fixtures/markdown_conformance.md`:
      GFM'in her özelliğini içeren tek bir belge (tablolar, hizalamalı tablo, görev
      listesi, dipnot, `[!NOTE]`…`[!CAUTION]`, iç içe liste 3 seviye, dilli kod çiti,
      satır içi + blok matematik, mermaid çiti, front matter, HTML bloğu,
      `javascript:` linki, kırık görsel, `#başlık` çapası, uzun tablo). Bu dosya
      hem seçimin hakemi, hem 247'nin regresyon ağı olur.
- [x] **Mermaid kararı**: AST'den çizim mi, dürüst yer tutucu mu (D11), yoksa
      tamamen park mı — **web view kesin olarak hariç** (güvenilmez belge + JS motoru).
      Karar gerekçesiyle yazılır. **Karar: ikisi de** — `flowchart`/`graph` ve
      `sequenceDiagram` çizilir, diğer tipler D11'e düşer; iş **OPH-254**'te.
- [x] **ADR-0028** (`docs/adr/0028-markdown-document-model-and-renderer.md`) yazılır:
      Bağlam / Karar / Alternatifler / Sonuçlar / **Zorlama** (bu karar CI'da nasıl
      zorlanıyor — fikstür testi, format bayrağının şema kısıtı, tema token taraması).
- [x] MARKDOWN.md §4/§5 kararla güncellenir; kapsam dışı bırakılanlar gerekçeleriyle
      parking-lot'a girer.
- **Kabul:** ADR-0028 kabul edilmiş; fikstür belgesi commit'li; hangi motorun neden
  kazandığı **sayılarla** yazılı (kaç GFM özelliği geçti / kaç tanesi tema alıyor).
  **Sayılar:** kapsam **19/22** (eksikler: matematik, `==vurgu==`, front matter);
  konum haritası **109/110** üst düzey düğüm damgalandı, **29/29** başlık kaynakta
  doğrulandı — ve fork gerekmedi. Üretici: `scripts/markdown/measure_coverage.dart`.
- **Doğrulama:** ADR indeksi senkron (0028'in "reserved" satırı gerçek bağlantıya
  döndü) · fikstür commit'li · ölçüm betiği commit'li ve tekrar üretilebilir.
  `ARCHITECTURE.md`'de ADR **tablosu yok** (satır içi referanslar var) ve bu task
  kod yazmadığı için yapı değişmedi — markdown bölümü OPH-247/248'de yazılacak.

### OPH-247 — Render motoru: GFM tam kapsam, token'lı tema, güvenli render (DESIGN §29 D6–D12)

> **ADR-0028 kararı verdi, yani bu task'ın motoru belli:** `markdown` 7.3.1
> üzerine **kendi widget ağacımız**. Fikstür 22 kalemin 19'unu hazır geçiyor;
> yapılacak iş üç özel syntax + widget katmanı + konum haritası.

_(✅ 2026-08-10. `features/notes/markdown/` doğdu: 9 kaynak + 5 test dosyası.
Süitler **962** (+75), analyze/format/i18n temiz, `contrast.py` 99 çiftte
FAILURES: 0._

_**Kararı taşıyan parça konum haritası oldu ve fork gerekmedi.** Paket AST'si
hiçbir düzeyde konum taşımıyor; dört public dikişle çözüldü (indeksli `Line`
alt sınıfı · `parseLineList` · public `BlockParser.lines` · HER blok
sözdizimini saran ve `data-aw-line` damgalayan dekoratör). `withDefaultBlockSyntaxes:
false` burada kritik: açık bırakılırsa paket kendi standart sözdizimlerini
**dekore edilmemiş** halde ekliyor ve o bloklar damgasız dönüyor._

_**Dört ölçüm planı değiştirdi:**_

_(1) **Matematik motoru çözümlemeyle seçildi, özellik listesiyle değil.**
`flutter_markdown_plus_latex` **on** paket getiriyor ve `flutter_math_fork`'u
zaten çekiyor, üstüne §2'nin reddettiği `flutter_markdown_plus` renderer'ını.
Kullanmadığımız bir renderer'a köprü; motoru doğrudan aldık — **sekiz** paket._

_(2) **Vurgulama kararı ADR'de YOKTU** (0028 yalnız matematiği kapsıyordu, oysa
D9 istiyor). Boşluk ADR §3b olarak kapatıldı: `highlight` lexer olarak,
`flutter_highlight` değil. Diller açıkça kaydediliyor — hepsini import etmek
**1.9 MB** grammar demek (tree-shake edilemez, hepsi kayıt haritasında), bizim
19 dilimiz **128 KB**. 15 kat._

_(3) **Uyarı kutuları palet büyütmedi ama neredeyse yanlış yoldan.** İlk tasarım
aksan rengini metin yapıyordu; ölçünce `warning` #C77700 kendi tonlu zemininde
**2.96** çıktı. Token'ın kendi yorumu aylardır "ikon rengi" diyormuş. Aksan
artık ikonu ve sol kenarı boyuyor, metin `onSurface`. Ton da %14 değil **%10** —
%14'te ikon bile 2.96'ya düşüyordu._

_(4) **Kod paneli/tablo için yeni token gerekmedi** (M3'ün `surfaceContainer*`'ı
iki temada da açıkça tanımlı), ama **vurgulama için gerekti**: altı `code*`
mürekkebi. Altı, otuz değil — ayırt edilemeyen palet tek renkten kötüdür._

_**İki hatam da "çalışıyor gibi görünen ama sessizce yanlış" sınıfındandı:**
link recognizer'ını sarmalayıcı span'e koymuştum — link mavi, altı çizili ve
**ölü**, çünkü Flutter isabet testini metni olan en içteki span'e çözüyor;
recognizer artık yapraklara iniyor. Ve `contrast.py`'ye uyarı zeminlerini elle
uydurmuştum, bekçi `FAILURES: 0` diyordu çünkü **var olmayan bir zemini**
ölçüyordu; değerler artık widget'ın çizdiği karışımın ta kendisi._

_**Yol boyunca bulunan ve OPH-249'a bırakılamayacak şey:**
`HeaderWithIdSyntax` "Türkçe Başlık" için `id="trke-balk"` üretiyor — Türkçe
karakterleri katlamıyor, **atıyor**. Yani `#türkçe-başlık` çapaları paketin
id'leriyle asla çalışmaz; 249 slug'ını `core/fold.dart` ile üretmek zorunda
(ADR-0013'ün arama için öğrendiği dersin aynısı). Bir testle sabitlendi ve o
test 249 düzelttiğinde **kırmızıya dönecek** — doğru sinyal._

_**Boyut ölçüldü (ADR-0028 §3'ün taahhüdü) ve önce YANLIŞ okundu.** Release APK
33.1 MB'dan 90.8 MB'a çıkmış görünüyordu — **+55 MB**, font için saçma bir sayı.
APK'nın içine bakınca sebep çıktı: taban APK yalnız `arm64-v8a` taşıyor (diğer
iki ABI stub), yenisi üçünü de derlemiş. Fark **tamamen ABI'lerden**, bağımlılıktan
değil. Karşılaştırılabilir tek katman `assets/flutter_assets`: **+369.733 bayt**,
ve bunun tamamı **20 KaTeX font dosyası (361 KB sıkıştırılmış)**. Eşiği
zorlamıyor → matematik **lazy-asset yapılmadı**. Ders: bir bayt farkını
katmanına ayırmadan raporlama._

_**Görseller gerçek piksel çiziyor** ve dokunuş tek `AwImageViewer`'ı açıyor.
Viewer bunun için **id VEYA URL** alan `AwImageRef`'e geçti: bir markdown
belgesi hem `alliswell://file/{id}` hem sıradan uzak görsel taşıyor, ve
ikincisi için ikinci bir görüntüleyici açmak OPH-245'in az önce kapattığı §22
sorununu geri getirirdi. URL'li görselde satır yok, dolayısıyla Aç/Sil
**disabled** — mevcut "ölü buton yok" kuralının aynısı. Göreli yol (`./x.png`)
çizilmiyor ve **sebebini söylüyor**: hangi klasöre göreli olduğunu belge
taşımıyor, o OPH-251'in işi.)_

- [x] **`markdown` DOĞRUDAN bağımlılığa yükseltilir** (`pubspec.yaml`) — bugün
      transitive, ve transitive bir paketten import etmek
      `depend_on_referenced_packages` lint'ini tetikler. Sürüm pin'i ve gerekçesi
      yorumla yazılır (ADR-0028 §2).
- [x] **Konum haritası katmanı** (`md_parse.dart`) — bu task'ın **kabul şartı**,
      çünkü D4/D13/D14/D16/D5'in dördü de ona bağlı ve OPH-248 ondan önce
      başlayamaz. Paket AST'si konum taşımıyor; OPH-246'nın prototipi fork'suz
      yolu kanıtladı: `IndexedLine extends Line` · `parseLineList(List<Line>)` ·
      `withDefaultBlockSyntaxes: false` ile tüm sözdizimi listesini dekore etmek ·
      `Element.attributes`'a `data-line`/`data-line-end` damgalamak.
      Ölçülmüş taban: **109/110** düğüm, **29/29** başlık doğru.
- [x] **Üç eksik syntax yazılır** (ölçümün bulduğu tam liste): satır içi/blok
      **matematik** (`$…$`, `$$…$$`), **`==vurgu==`**, ve **front matter**.
      Geri kalan GFM `ExtensionSet.gitHubWeb`'den hazır geliyor — yeniden
      yazılmaz.
- [x] **Matematik motoru seçilir ve ÖLÇÜLÜR** (ADR-0028 §3): `flutter_math_fork`
      vs `flutter_markdown_plus_latex`, fikstürün matematik bölümüne karşı.
      **KaTeX font varlıklarının APK/IPA'ya kattığı bayt kayda geçer** — eşik
      aşılırsa lazy-asset'e düşer.
- [x] Motor bağlanır ve **okuma görünümü** doğar: tablolar, görev
      listeleri (tıklanabilir — D4), dipnotlar, üstü çizili, autolink, `==vurgu==`,
      emoji kısa kodları, uyarı kutuları, iç içe listeler, satır içi/blok matematik.
- [x] **Kod blokları**: dil etiketi + sözdizimi vurgulama + **kopyala butonu** (D9);
      yatay kaydırma kendi kutusunun içinde (D8).
- [x] **Token'lı tema** (D7): başlıklar tip ölçeğinden, kod paneli/tablo/uyarı kutusu
      `AwTokens`'tan; ham hex yok, `Colors.*` yok; `contrast.py` iki temada da
      **FAILURES: 0**.
- [x] **Güvenlik** (D10): HTML blokları kaçırılmış kaynak olarak render edilir, asla
      canlı değil; `javascript:`/`data:` URI'leri **inert metin**; uzak görseller not
      gömülerinin kurallarına uyar. Epic 20'nin `ai_redteam.json` korpusu bu yüzeye de
      koşturulur (aynı vakalar bir markdown belgesinin içine gömülür).
- [x] **Front matter** properties şeridi olarak render edilir (D12), gövde metni olarak
      değil.
- [x] Çizilemeyen blok → kaynağı + sebebi gösterir (D11), boşluk değil.
- [x] Testler: `markdown_conformance.md` fikstürünün her özelliği için bir assert
      (golden değil, **yapısal** — hangi widget doğdu); kırmızı-takım korpusu → sıfır
      canlı HTML, sıfır tıklanabilir `javascript:`; geniş tablo yatay kaydırıyor,
      sayfa kaymıyor; iki temada kontrast. **Ayrıca:**
      `scripts/markdown/measure_coverage.dart` bir teste dönüşür
      (`test/features/notes/markdown_coverage_test.dart`) — ADR-0028 §Zorlama:
      paketin bir yükseltmede syntax düşürmesi CI'da patlamalı, sessizce
      görüntüleyiciyi daraltmamalı. Konum haritası da orada assert edilir.
- **Kabul:** `markdown_conformance.md` AllisWell'de GitHub'daki gibi okunuyor; yan yana
  ekran görüntüsü task'ın altına eklenir.
  **Çekildi:** [`docs/screenshots/markdown-reading-light.png`](screenshots/markdown-reading-light.png)
  + [`-dark.png`](screenshots/markdown-reading-dark.png) (1800×10400, belgenin
  TAMAMI). Üretici: `test/features/notes/markdown/markdown_screenshot_test.dart`,
  `flutter test --update-goldens --dart-define=screenshots=true …`.
  **Üç kere çekildi, ikisi çöptü ve sebebi aynıydı: font yüklemek yetmiyor,
  temanın onu İSTEMESİ gerekiyor.** İlk kare kusursuz uyarı kutuları ve tablolar
  gösteriyordu ama her kelime siyah dikdörtgendi (`fontFamilyOverride` verilmemiş).
  İkincide gövde düzeldi, kod ve matematik kutu kaldı — test motorunda monospace
  yok, ve bir bağımlılığın fontları `packages/<paket>/<aile>` adıyla çözülüyor.
  Üçüncüde ikisi de kayıtlı: kod blokları gerçek glif + sözdizimi renkleriyle,
  matematik gerçek KaTeX dizgisiyle (integral, toplam, kesir, karekök, hizalı
  ortam) çiziliyor.
- **Doğrulama:** `flutter analyze` · `flutter test` · `python3 scripts/design/contrast.py` ·
  `npm run check:i18n`.

### OPH-254 — Mermaid: ayrıştır, yerleştir, çiz (ADR-0028 §4 — 247'den sonra)

> **Neden ayrı bir task:** OPH-247'nin içinde kalsaydı o task üç işi birden
> yapardı (GFM renderer + matematik + diyagram motoru). Numara epic içinde ilk kez
> açılıyor; gerekçesi ADR-0028'in 4. kararı.
>
> **Yazılı çıkış kapısı:** yerleşim kalitesi kabul edilebilir çıkmazsa D11 yer
> tutucusuna düşülür ve gerekçe ADR-0028'e eklenir. Task **sessizce yarım
> bırakılmaz** — kısmen çizen bir diyagram motoru, çizmeyenden daha kötüdür.

_(✅ 2026-08-11. **Çıkış kapısı kullanılmadı: ikisi de çiziliyor.** Süitler 1011
(+49), analyze/format/i18n temiz, `contrast.py` FAILURES: 0._

_**Turun tek dersi: "çizdi" ile "okunaklı çizdi" farklı iddialar, ve aradaki
farkı ancak ÜRÜNE bakınca gördüm.** Testlerin 20'si yeşildi — sıfır kesişim,
düğümler çakışmıyor, koordinatlar deterministik — ama ekran görüntüsünde
fikstürün `C --> F` kenarı iki rank atlayıp araya giren `E` düğümünün
**üstünden** geçiyordu. Yani resim, belgenin yazmadığı bir oku iddia ediyordu:
"C'den E'ye". Sebep, Sugiyama'nın atlaması cazip gelen adımıydı — uzun kenarlar
için **kukla düğüm**. Eklendi, kenar artık etrafından dolanıyor, ve bunu
koordinat sayısıyla değil **geometriyle** assert eden bir test kondu: hiçbir
kenar, ucu olmadığı bir düğümün içinden geçemez._

_**Parser'ın yakalanan hatası:** `U-->>A: metin` satırında id sınıfı `-`
içerdiği için ilk grup açgözlülükle `U-` yakalıyor ve diyagram sessizce `U-`
adlı bir katılımcı büyütüyordu. Mesaj regex'inde id'ler artık `-` almıyor —
mermaid'in kendi grameri de aynı belirsizliği aynı şekilde çözüyor._

_**Testin ortaya çıkardığı üçüncü şey OPH-247'ye ait:** `AwMarkdown` artık
`ProviderScope` istiyor (görseller Riverpod'dan çözülüyor) ve
`aw_markdown_test`'in uçtan uca testi bunu **yakalamamıştı** — çünkü 6000 px'lik
görüntü alanı görsel bölümüne hiç ulaşmıyordu. Yükseklik artırıldı, scope
eklendi, ve test artık görsellere gerçekten değdiğini de assert ediyor._

_**Kapsam ADR-0028 §4'teki gibi:** `flowchart`/`graph` (beş yön) ve
`sequenceDiagram` çiziliyor; class/state/ER/gantt/pie/journey **adıyla**
reddediliyor. D11'in iki cümlesi ayrı: `gantt` için "henüz çizilmiyor",
bozuk kaynak için "okunamadı" — ekran görüntüsünde ikisi de görünüyor._

_**Modellemediğimiz ifadeler ölümcül değil:** `subgraph`, `style`, `classDef`,
`activate`, `note`, `loop`, `alt` atlanıyor. Bir `style` satırı yüzünden tüm
resmi kaybetmek, o satırı görmezden gelmekten kötü.)_

- [x] `mermaid_parse.dart` — alt küme lexer/parser → tipli graf modeli: düğüm
      şekilleri (`[]` `()` `{}` `(())`), kenar tipleri (`-->` `---` `-.->` `==>`),
      kenar etiketleri, yön (TD/TB/LR/RL/BT), altgraf. **Parser eklentisi
      gerekmiyor** — mermaid `language-mermaid` bilgi dizeli bir kod bloğu olarak
      geliyor (OPH-246 ölçümü doğruladı), yani bu bir render-zamanı işi.
- [x] `flow_layout.dart` — katmanlı (Sugiyama) yerleşim: rank ataması
      (en-uzun-yol) → sıralama (barycenter, kesişim azaltma) → x koordinatı →
      kenar yönlendirme. **Saf Dart, widget yok** — koordinatlar birim test
      edilebilir olmak zorunda.
- [x] `sequence_layout.dart` — katılımcılar sütun, mesajlar satır, aktivasyon
      kutuları, notlar. Doğrusal ve ucuz; bu yüzden ikisi aynı task'ta.
- [x] `mermaid_view.dart` — `CustomPainter`; renkler **`AwTokens`'tan** (D7, ham
      hex yok); geniş diyagram **kendi kutusunda** kaydırır (D8), sayfa kaymaz.
- [x] Desteklenmeyen tip (class/state/ER/gantt/pie/journey) ve ayrıştırılamayan
      kaynak → **D11**: kaynağı *ve sebebi* gösterir, ikisi farklı cümleyle
      ("bu tip v1'de çizilmiyor" ≠ "bu diyagram ayrıştırılamadı").
- [x] Testler: parser birim testleri; bilinen graflarda **deterministik
      koordinat** ve kesişim sayısı assert'i; fikstürün dört mermaid vakası
      (flowchart, sequence, gantt→yer tutucu, bozuk→yer tutucu); iki temada
      kontrast.
- **Kabul:** fikstürün flowchart ve sequence diyagramları AllisWell'de okunaklı
  çiziliyor; ekran görüntüsü task'ın altına eklenir. Desteklenmeyen tip boşluk
  değil, sebepli bir kutu gösteriyor.
- **Doğrulama:** `flutter analyze` · `flutter test` ·
  `python3 scripts/design/contrast.py`.

### OPH-248 — Üç mod: Okuma · Canlı · Kaynak (+ bölünmüş görünüm, senkron kaydırma) (D1–D5)

_(✅ 2026-08-11. Süitler **1032** (+16 mod testi), API **620** (+7),
analyze/format/i18n temiz, `contrast.py` FAILURES: 0._

_**D1 TADİL EDİLDİ ve DESIGN'a yazıldı.** "Tam üç mod" Seçenek C altında dürüst
değil: Canlı bir Delta'yı, Kaynak bir markdown metnini düzenler ve bir notun
kanonik içeriği **yalnız biri**. Diğerini sunmak ya kaydedilenin ne olduğu
konusunda yalan söylerdi ya belgeyi kullanıcının altından çevirirdi. Bir not
artık **iki** mod sunuyor (Okuma + kendi editörü), üçüncüsü **adı konmuş,
uyarılı, fiilen tek yönlü** bir dönüştürmeyle geliyor. Kapsam daralması, niyet
değil: gri bir üçüncü segment §22'nin yasakladığı ölü affordance olurdu._

_**D3'ün mekanizması "geri yükle" değil, "hiç yıkma".** Denetleyiciler
`NoteDocument`'ta belge ömrü boyunca yaşıyor, mod değişiminde yeniden
kurulmuyor — caret, seçim, kaydırma ve Flutter'ın kendi geri-al yığını
kendiliğinden devam ediyor. Test bunu **kimlikle** assert ediyor
(`identical(doc.source, source)`), davranışı taklit ederek değil._

_**Markdown-kanonik not bayt-sadık okunuyor** — `markdown` getter'ı kaynağı
olduğu gibi döndürüyor, Delta'dan geçirmiyor. Test bunu bir **tabloyla**
sınıyor: dönüştürücülerimiz tabloyu ifade edemiyor, yani round-trip olsaydı
sessizce yerdi. OPH-251'in W4'ü bu özelliğe dayanacak._

_**`_showMarkdownPreview()` silindi.** Üretilen markdown'ın salt-okunur
monospace sheet'iydi; ne Okuma (artık çiziyor) ne Kaynak (artık düzenliyor).
Testi de yeni davranışa göre yeniden yazıldı — eskisi markdown **kaynağını**
(`**Kalın kısım**`) arıyordu, çizilmiş bir belgede o yok, olması da yanlış
olurdu._

_**Dürüstçe yarım bırakılan:** D5'in senkron kaydırması **oransal**, satır
eşlemeli değil. Kaynak satırını çizilmiş ofsete eşlemek her bloğun boyanmış
konumunu ister; blok→satır haritası var (OPH-247) ama ofsetler yok — o ölçüm
anahat ve çapa atlamalarıyla birlikte **OPH-249'a** ait. Kodda da öyle yazıyor._

_**Yol boyunca:** `scripts/markdown/measure_coverage.dart` durduğu yerden
`dart analyze` etmiyor (yedi hata, hepsi tek çözülmeyen import'tan) — CI
`apps/app` içinden analiz ettiği için kimseyi kırmıyor, ama başlığına yazıldı
ki bir sonraki okuyan vakit harcamasın. Zorlayıcı kopya zaten
`markdown_coverage_test.dart`.)_

- [x] Not editörü **üç modlu** olur; tek bir segment kontrolü modu gösterir ve gizlenmez
      (D1). Varsayılan: dışarıdan gelen belge → Okuma, burada yazılan not → Canlı (D2).
- [x] **Kaynak modu** doğar: markdown metnini düz metin olarak düzenler, **kendisi
      sözdizimi vurgulu**. Bugün ham markdown'ı düzenlemenin HİÇBİR yolu yok.
- [x] Mod geçişi **caret'i, kaydırma konumunu ve geri-al geçmişini korur** (D3).
- [x] ≥ 900 px'te **bölünmüş görünüm** (Kaynak ⇄ Okuma) + **iki yönlü senkron
      kaydırma**, Kaynak modunun içinde bir anahtar olarak (D5) — dördüncü mod değil.
- [x] Okuma modu düzenlenebilir görünmez (D4): caret yok, placeholder yok, araç çubuğu
      yok; ama görev listesi kutuları tıklanır ve belgeye yazar.
- [x] Mevcut `_showMarkdownPreview()` (monospace ham metin sheet'i) **kaldırılır** —
      yerini Kaynak modu ve Okuma modu alır; app bar'daki ikon buna göre sadeleşir.
- [x] Testler: üç mod arası geçişte caret/scroll/undo korunuyor; dar ekranda bölünmüş
      görünüm YOK; senkron kaydırma iki yönde; Okuma modunda caret yok ama checkbox
      yazıyor; varsayılan mod kaynağa göre doğru seçiliyor.
- **Kabul:** aynı belgede üç mod arasında gidip gelmek yerini kaybettirmiyor.
- **Doğrulama:** `flutter analyze` · `flutter test` · geniş + dar ekran widget testleri.

### OPH-249 — Uzun belgeyi gezmek: anahat, katlama, bul-değiştir, çapalar (D13–D16)

_(✅ 2026-08-11. Süitler **1059** (+27), analyze/format/i18n temiz,
`contrast.py` FAILURES: 0._

_**OPH-247'nin teste bağladığı Türkçe çapa sorunu burada kapandı** — ve tam da
o testin işaret ettiği yerde. Paket `Türkçe Başlık` için `trke-balk` üretiyor
(harfleri katlamıyor, ATIYOR); slug üretimi artık `core/fold.dart` üzerinden
bizim, ADR-0013'ün aramada vardığı yerin aynısı. GitHub'ın tekrar eden başlık
kuralı da eklendi (`kurulum`, `kurulum-1`) — olmasa iki bölüm aynı çapayı
paylaşır ve biri ulaşılamaz olurdu._

_**Yol boyunca kendi eklediğim satırın açtığı hata:** çapayı çözerken
`Uri.decodeComponent` çağırıyordum; o fonksiyon **ham Türkçe girdide
fırlatıyor** ("Illegal percent encoding"). Yani D16'nın var olma sebebi olan
girdide çöküyordu. Artık yalnız gerçekten yüzde-kodluysa çözülüyor ve bozuk
kodlama sessizce ham metne düşüyor._

_**OPH-248'den devredilen kaydırma hedefleme mekanizması seçildi ve yazıldı:**
`scrollable_positioned_list` tam bu iş için var ama **alınmadı** — işin tamamı
bir yükseklik önbelleği ve iki kare düzeltme, ve AGENTS §1.6 bağımlılığın kendini
hak etmesini istiyor. Bedeli de yazıldı: inşa edilmemiş bölgeye ilk atlayış bir
TAHMİN, ve tahminler güvenilmiyor, düzeltiliyor._

_**Katlama hiçbir yere yazılmıyor** — collapsed slug'lar widget'ın kendi
kümesinde. D14'ün "belgeyi asla değiştirme" sözünü tutmanın en ucuz yolu
yazacak bir yer bulundurmamak. Silinen bir başlığın katlaması da temizleniyor,
yoksa başlığı düzenlemek açılamayan bir bölüm bırakırdı._

_**D15'te bir ayrım yazıldı:** bul-değiştir **fold'suz**. Okumak için arama
ı→i katlar (ADR-0013), ama YAZMAK için katlamak kullanıcının dokunmak
istemediği metni değiştirmek olurdu. Replace-all tek atamayla yazıyor, yani
tek geri-al belgeyi geri getiriyor._


- [x] **Anahat (TOC)**: başlık ağacı, bulunulan bölüm vurgulu, kaydırmayla senkron;
      telefonda sheet, ≥ 900 px'te yan panel (D13).
- [x] **Başlık katlama** (D14) — katlama durumu oturumluk, **belgeye asla yazılmaz**.
- [x] **Bul & değiştir** (D15): `QuillSimpleToolbarConfig`'te bugün
      `showSearchButton: false` ile **kapalı** olan kontrol açılır ve gerçekten çalışır;
      klavye kısayolu (⌘F/Ctrl+F, ⌘⌥F/Ctrl+H) bağlanır; eşleşme sayacı + sonraki/önceki.
- [x] **Belge içi çapalar** (D16): `[bağlantı](#başlık)` o başlığa kaydırır; slug üretimi
      GitHub kuralıyla aynı (küçült, boşluk→tire, noktalama at) ve Türkçe karakterlerde
      `core/fold.dart` ile tutarlı.
- [x] Testler: 500 başlıklı sentetik belgede anahat doğru ağaç kuruyor; katlama belgeyi
      değiştirmiyor (delta/markdown baytları aynı); bul-değiştir tüm eşleşmeleri buluyor
      ve tek geri-al ile dönüyor; `#turkce-baslik` çapası çalışıyor.
- **Kabul:** 2 000 satırlık bir README'de bölüm bulmak tek dokunuş.
- **Doğrulama:** `flutter analyze` · `flutter test`.

### OPH-250 — Yazma konforu: liste otomasyonu, mobil araç çubuğu, slash, akıllı yapıştırma (D17–D23)

_(✅ 2026-08-11, **iki maddesi açık bırakılarak** — aşağıda adıyla. Süitler
**1093** (+34), analyze/format/i18n temiz, `contrast.py` FAILURES: 0._

_**Eylemler TEK listeden üretiliyor** (`md_actions.dart`): araç çubuğu, ⌘/Ctrl
kısayolları ve slash menüsü hepsi ondan doğuyor. D19 "slash her araç çubuğu
eylemine İKİNCİ yol" diyor; üç yerde ayrı ayrı tanımlamak, slash ile butonun
zamanla farklı şeyler yapmasının ve birinin sessizce yok olmasının yolu._

_**D17 saf metin aritmetiği** ve testleri stringte: Enter listeyi sürdürüyor,
BOŞ maddede listeden çıkıyor (insanların fark ettiği davranış — yoksa listeden
çıkmanın tek yolu az önce verilen madde işaretini silmek), `*` yazan kullanıcıya
`-` dayatmıyor, devam eden görev maddesi **işaretsiz** başlıyor (`[x]` taşımak
kimsenin işaretlemediği kutuyu işaretlerdi), Tab/Shift-Tab iç içe geçiriyor ve
numaralar belge genelinde yeniden hesaplanıyor._

_**D21 yazıldı çünkü autosave hem sessizdi hem hatası sessizdi** — eski `_save`
hatayı yutup notu tekrar kirli işaretliyordu. Gösterge geldi; ve **eklerken bir
hata ürettim**: `dispose()` içinden çağrılan son kaydetme `setState` yapıyordu
ve `State.mounted` dispose SIRASINDA hâlâ true olduğu için framework "defunct"
diye patladı. `mounted` burada yanlış bekçi; ayrı bir `_disposed` bayrağı kondu.
Mevcut `note_media_test` yakaladı._

_**D23 tek denetleyiciyle çözüldü:** `MdSourceController.buildTextSpan` caret'in
paragrafı dışını **söndürüyor**. Alt sınıf, ikinci bir controller değil — D3
belge ömrü boyunca TEK controller istiyor. Test metnin değişmediğini assert
ediyor: gizlemek reflow yapar, söndürmek yapmaz._

_**AÇIK KALAN İKİ MADDE (kırpılmadı, yazıldı):**_
_1. **Komut paleti (⌘K)** yapılmadı. ⌘K şu an "bağlantı" eylemine bağlı ve
   slash menüsü paletin işini görüyor; ayrı bir palet ikinci bir keşif yüzeyi
   demek ve hangisinin kanonik olduğu kararı ürün kararı._
_2. **Masaüstü/web'de editöre sürükle-bırak dosya** yapılmadı — yükleme yolu
   (`uploadAll`) hazır ama bırakma hedefi yok._
_İkisi de OPH-250'nin altında açık kutu olarak duruyor._


- [x] **Liste otomasyonu** (D17): Enter listeyi sürdürür, boş maddede listeden çıkar,
      sıralı listeler yeniden numaralanır, **Tab / Shift-Tab ile iç içe geçer**
      (ADR-0028'in modeli iç içe listeyi taşıyor olmalı — taşımıyorsa bu madde ADR'ye
      geri döner, sessizce kırpılmaz).
- [x] **Telefonda klavye üstü kaydırılabilir markdown araç çubuğu** (D18); masaüstü/web'de
      **klavye kısayolları** (⌘B/I/K, H1–H3, kod, alıntı, liste).
- [x] **Komut paleti (⌘K / Ctrl+K)** — D18'in bu yarısı. **Ürün kararı verildi
      (2026-08-11, sahip): palet YAZILIR**, slash telefon/satır-içi yol olarak kalır.
      Palet `mdActions()`'tan doğar — dördüncü bir eylem tanımı yasak, D19'un "slash
      İKİNCİ yol" kuralı ancak böyle ayakta kalır. Eşleştirme `foldSearchText()`
      üzerinden ve **yerelleştirilmiş etikete de** bakar (`'note.action.${id}'.tr()`);
      `matchSlash` bugün düz `toLowerCase()` ve yalnız `/slash` token'ına bakıyor —
      **tek eşleştirici** yazılır ve ikisi de ona bağlanır. Yüzey `showAwSheet` +
      `AwSearchField` (**`debounce: Duration.zero`** — varsayılan 250 ms palet için
      yanlış), klavye gezinmesi (↑/↓/Enter/Esc) paletin ayırt edici özelliği.
      ⌘K bugün "bağlantı"da → bağlantı **⌘⇧K**'ya taşınır.
- [x] **Kısayollar Windows/Linux/web'de ÖLÜ** (yol boyunca ölçülen gerileme):
      `md_actions.dart` yalnız `meta: true` tanımlıyor, yani ⌘B/I/K macOS'ta çalışıyor
      ama **Ctrl+B/I/K hiçbir yerde çalışmıyor** — dosya başlığı ve `MdAction.shortcut`
      dokümantasyonu "⌘/Ctrl" dediği hâlde. §22 reachability ihlali;
      `find_replace_bar.dart` doğrusunu zaten yapıyor (ikisini de kaydediyor).
      Her kısayola `control:` varyantı + bunu bekçileyen test.

_(**Palet + kısayollar sevk edildi 2026-08-11f.** Süitler **1101** (+8),
analyze/format/i18n temiz, `contrast.py` FAILURES: 0._

_**Alan çoğul oldu:** `MdAction.shortcut` → `shortcuts`, ve `metaOrControl()`
çifti üretiyor. Tekil alan tutmak hatanın **sebebiydi** — `SingleActivator`
"meta VEYA control" diyemiyor, yani tek aktivatörlü bir alan sessizce
"yalnız macOS" demek. Çoğul ad, eksikliği görünür kılıyor._

_**Palet dördüncü bir liste değil, dördüncü bir GÖRÜNÜM:** `matchMdActions()`
tek eşleştirici ve `matchSlash` artık ona delege ediyor. Ayrımı sorgu yapıyor —
`/` ile başlayan bir sorgu komutu ÖN EKTEN eşliyor (slash semantiği birebir
korundu), kelime sorgusu ise **yerelleştirilmiş etiketi** `foldSearchText` ile
eşliyor, yani "kalin" → "Kalın". Etiket enjekte ediliyor, böylece
`md_actions.dart` i18n'den bağımsız ve saf kalıyor._

_**⌘K çakışmasını çözmek gerekti:** bağlantı **⌘⇧K**'ya taşındı (Slack, Notion
ve VS Code de çıplak ⌘K'yı komut yüzeyine ayırıyor) ve bir test hiçbir eylemin
paletin aktivatörünü geri almadığını bekçiliyor — alsaydı palet sessizce
ulaşılmaz olurdu._

_**Tuş dinleyicisi alanın KENDİ node'unda**, üstteki bir `Focus`ta değil:
`DefaultTextEditingShortcuts` kökün yakınında kurulu, yani üstte duran bir
işleyici ancak metin alanı tuşa çoktan davrandıktan sonra çalışırdı._

_**Seçili satırın vurgusu metin değil ZEMİN rengi:** `ListTile`ın varsayılan
`selectedColor`'ı etiketi ve ikonu `primary` ile boyuyor — hiç ölçülmemiş bir
kontrast çifti. OPH-247'nin dersi (var olmayan bir zemini ölçmek `FAILURES: 0`
yalanı söyler) burada peşinen uygulandı._

_**Kapı sınandı:** `bold`u kasten `meta`-only'ye döndürdüm, test
`bold has no Ctrl binding` diyerek yakaladı, geri alındı._

_**Kalan iki madde bilinçli açık:** sürükle-bırak ve panodan görsel. İkincisi
**OPH-256'ya bağımlı** (`alliswell_docref.clipboardRead()` henüz yok) — AGENTS §2'nin
"blocked ise sebebini yaz" maddesi.)_

_(**Sürükle-bırak sevk edildi 2026-08-11g.** Süitler **1108** (+7),
analyze/format/i18n temiz, `contrast.py` FAILURES: 0._

_**Asıl iş `desktop_drop` değil, insert yolunu TEKE indirmekti.** Bırakma üçüncü
çağıran olacaktı (araç çubuğu düğmeleri + OPH-256'nın panosu + bırakma), ve üçü de
"görsel mi, video mu, hiçbiri mi" sorusunu kendi cevaplasaydı `mdActions()` öncesi
araç çubuğu/slash ikilisinin tam olarak düştüğü yere düşerlerdi. Karar
`NoteDocument.insertFile()`'a taşındı — hangi yüzeyin kanonik olduğunu bilen tek
yer orası — ve `NoteMediaButtons` de ona bağlandı (artık `QuillController` değil
`NoteDocument` alıyor)._

_**Markdown'da video gömme yok**, o yüzden Source modunda görsel `![ad](uri)`,
görsel olmayan `[ad](uri)` **bağlantı** oluyor. `![clip.mp4](…)` yazmak her
renderer'da kırık görsel çizdirirdi — belge kendi içeriği hakkında yanlış bir şey
iddia ederdi. Sonuç `NoteInsert{embedded,linked,attachedOnly}` ile dönüyor, çünkü
`attachedOnly` gösterilecek hiçbir şeyi olmayan tek durum ve orada sessizlik
"yükleme başarısız" diye okunur._

_**Yazarken bulunan kendi açığım:** `pickedFromDrop` `XFile.name`'e körü körüne
güveniyordu. `name` garanti DEĞİL — io'da yoldan türetiliyor ve bir bırakma ikisi
de olmadan gelebilir; boş ad boş satırlı bir yükleme ve `mimeForName`'e tahmin
edecek hiçbir şey bırakmak demekti. Fallback kondu._

_**iOS'ta `DropTarget` hiç kurulmuyor** (`supportsFileDrop`) — desktop_drop'un iOS
eklenti sınıfı yok, sarmalamak cevapsız bir kanalın etrafına widget dizmek olurdu._

_**Dürüst sınır:** OS'un bırakma OLAYI bir platform kanalı ve cihazda doğrulanır,
burada değil (native köprülerin tuttuğu sınırın aynısı). Test edilen, dosya elimize
geçtikten sonraki her karar.)_
- [x] **Slash komutları** (D19) her araç çubuğu eylemine ikinci yol olarak; tek yol asla
      değil.
- [x] **Akıllı yapıştırma** (D20): HTML → markdown, seçimin üstüne URL → bağlantı;
      **tek geri-al ham yapıştırmaya döner** (tek atama). Kaynak alanının kendi
      focus node'una bağlı — global kısayol yapmak bul çubuğuna ve başlığa da
      uzanırdı. **Panodaki GÖRSEL yüklemesi yapılmadı:** pano görselini okumak
      platform kanalı ister, `uploadAll` hazır ama köprü yok.
- [x] Masaüstü/web'de editöre **sürükle-bırak** dosya — `desktop_drop` (saf platform
      kanalı, Rust yok, CI değişmez). Bırakılan dosya → `PickedUpload.fromBytes` →
      `uploads.start` (fileId döndürür) → gömme. **Plumbing gerçeği:** `SourceMode`
      düz bir `StatefulWidget`, ne `ref`i ne `_ensureNote`ı var — drop hedefi
      `_NoteEditorState.build`'in gövdesine konur, orada ikisi de var ve tek sarmalayış
      Live + Source + başlığı birden kapsar.
- [ ] **Panodan görsel + HTML** (D20'nin yapılmayan yarısı) — kendi kanalımız
      (`alliswell_docref.clipboardRead()`, bkz. OPH-255/256; **karar: `super_clipboard`
      DEĞİL** — `super_native_extensions` bir Rust toolchain'ini altı platform build'ine
      ve CI'a sokardı). **Ölçüm:** `source_mode.dart` `Clipboard.getData('text/html')`
      çağırıyor ama Flutter'ın platform kanalı yalnız `text/plain` uyguluyor — bu dal
      **her platformda null döner**, yani `htmlToMarkdown` bugün ölü kod ve sadece saf
      fonksiyon testinde koşuyor. Aynı kanal ikisini birden diriltir. Görsel → Source'ta
      `![ad](alliswell://file/{id})`, Live'da `BlockEmbed.image` — **iki insert yolu tek
      özellik demek**, o yüzden `NoteDocument`'a "aktif yüzeye dosya ekle" seam'i konur.
- [x] **Kayıt durumu göstergesi** (D21): kaydedildi / kaydediliyor / başarısız —
      engellemeyen, küçük. Bugün autosave tamamen sessiz ve hatası da sessiz.
- [x] **Kelime/karakter sayısı** (D22) ve **odak modu** (D23 — söndürür, gizlemez).
- [x] i18n: tüm yeni dizeler `en`+`tr`.
- [x] Testler: liste otomasyonunun her kenarı (sürdür / çık / numaralandır / nest);
      yapıştırma dönüşümleri + tek geri-al; kayıt göstergesinin üç durumu (hata durumu
      `_save`'in mevcut retry davranışıyla tutarlı); odak modu düzeni bozmuyor
      (reflow yok).
- **Kabul:** uzun bir belgeyi telefonda yazmak klavye üstü araç çubuğuyla mümkün;
  masaüstünde klavyeden elini kaldırmadan biçimlendirilebiliyor.
- **Doğrulama:** `flutter analyze` · `flutter test` · `npm run check:i18n` ·
  `python3 scripts/design/contrast.py`.

### OPH-255 — Dış belge tutamağı: ADR-0030 + saf Dart katmanı (cihaz yok, native yok)

_(Doğdu 2026-08-11 — OPH-251'in planlanmasında ölçülen üç engel yüzünden. OPH-251 tek
task olarak sevk edilseydi üç işi birden yapardı: yerel tutamak katmanı, native
gerçeklik ve W1–W6 arayüzü. OPH-254'ün mermaid için OPH-247'den ayrılma gerekçesinin
aynısı. **Bu task'ın tamamı `flutter test` ile kanıtlanabilir** — eklenti iskeleti altı
platformda da `MissingPluginException` → `unsupportedPlatform` döner._

_**Planlamada ölçülen üç engel** (plan bunlar olmadan yazılsaydı yanlış olurdu):_
_1. **`file_picker` iOS'ta dosyanın KOPYASINI veriyor** —
   `IOSFilePickerHandler.swift:249` `UIDocumentPickerViewController(..., asCopy:
   !asDirectoryPicker)`, dosya seçiminde daima `true`. Bugünkü seçiciyle iPhone'da geri
   kaydetmek yapısal olarak imkânsız: yazdığımız şey tmp'deki kopya olur. Seçiciyi
   kendimiz sahiplenmek zorundayız._
_2. **macOS'ta sandbox açık ve HİÇBİR dosya entitlement'ı yok** — ne
   `user-selected.read-write` ne `bookmarks.app-scope`. Kabul kriterinin zorunlu kıldığı
   "Mac'te README.md diskte değişmiştir" bugün fiziksel olarak mümkün değil._
_3. **`markdown_source.dart` `allowMalformed: true` ile okuyor** — okumak için doğru
   karar, ama yazma eklendiği an her UTF-8-olmayan baytı U+FFFD'ye çevirip kullanıcının
   dosyasına geri yazar. Tam olarak W4'ün "iyi niyetli veri kaybı" dediği şey._

_**Ve ölçülen bir iyi haber:** `note_document.dart`'ın `markdown` getter'ı
markdown-kanonik notta `source.text`'i **birebir** döndürüyor, Delta'dan geçmeden —
yorumu zaten "OPH-251'in geri kaydetmesini dürüst yapan şey bu" diyor. Yani W4'ün zor
yarısı (round-trip reflow) ÇÖZÜLMÜŞ; geriye yalnız kodlama sadakati + bir biçim kapısı
kalıyor._

- [x] **ADR-0030 önce** (kapı, kod yazılmadan). AGENTS §1 rule 6 iki kez zorunlu kılıyor:
      yeni bağımlılık kategorisi (üç platforma yayılan in-repo native eklenti) **ve**
      güvenlikle ilgili karar (yeni macOS sandbox entitlement'ları). Kararları: kalıcı
      tutamak modeli ve **`LocalKv`'de saklanması, senkron DB'de DEĞİL** (bookmark cihaza
      özeldir; senkronlamak başka cihaza çözemeyeceği bir token vermek olur) · kendi
      eklentimiz vs `file_picker` (ölçülmüş gerekçe yukarıda) · iki macOS entitlement'ı ·
      W4'ün kodda karşılığı · atomiklik asimetrisi · Android'in **sıfır** izin kazanması.
- [x] **W3'ü derleyici zorlar** — `external_document.dart`, saf, eklenti import'u yok:
      `sealed class ExternalAccess` = `ExternalWritable(saver)` | `ExternalReadOnly(reason)`
      | `ExternalUnreachable(reason)`. **`saver` YALNIZ yazılabilir kolda var**, yani
      salt-okunur bir dosyada kaydet butonunun bağlanacağı bir şey yoktur. Bool olsaydı
      buton kurulur ve `enabled: false` yapılırdı — §22'nin "ölü buton" yasağı tam olarak
      budur. Kayıt sonucu da sealed: `SaveSucceeded` | `SaveConflict(onDisk)` |
      `SaveLostAccess` | `SaveFailed`; **`SaveIntent.force` yalnız çatışma dalından
      erişilebilir**, sessiz ezme ifade edilemez.
- [x] **W4 — kodlama sadakati.** Eklenti ham bayt döndürür; Dart
      `utf8.decode(bytes, allowMalformed: **false**)` dener. Baştaki `EF BB BF` ayıklanır,
      `utf8Bom` diye kaydedilir ve **kaydederken geri konur** (BOM'u sessizce düşürmek
      kimsenin istemediği bir bayt değişikliğidir). `FormatException` → `notText`:
      Latin-1 **tahmin edilmez**, dosya yine AÇILIR (göstermeyi reddetmek yazmayı
      reddetmekten kötüdür), gösterim için kayıplı çözülür, erişim
      `ExternalReadOnly(notUtf8)` olur — reddediş veri kaybının olacağı yerde, yazma
      kenarında. Tek saf yüklem `canWriteBack(NoteFormat, ExternalEncoding)`. Satır sonu
      normalize edilmez, sona `\n` eklenmez.
- [x] **W5 primitifi** — açılışta üçü de yakalanır: `sha256` (`crypto: ^3.0.6` zaten
      doğrudan bağımlılık; 2 MB tavanla ~10 ms), `sizeBytes`, `modifiedAt`. **Yetki sırası
      yazılır:** mtime Apple'da güvenilir, **Android'de değil** — SAF'ın
      `COLUMN_LAST_MODIFIED`'ı isteğe bağlı ve bulut sağlayıcılar null döner, o yüzden
      mtime yoksa hash'e düşülür.
- [x] **W6 — `external_recents.dart`**: `parseExternalRecents` / `pushExternalRecent` /
      `encodeExternalRecents`, modeli `quick_access/emoji_input.dart` (en-yeni-önce, dedup,
      kapasiteli, bozuk girdiyi düşürür), `PersistedChoice('alliswell_external_recents')`.
      **Bilinçli sapma:** emoji recents virgülle birleşiyor (emoji virgül içeremez); bir
      `content://` URI'si de base64 bookmark da içerebilir → JSON dizi.
- [x] **Seam**: `MarkdownSource` genişletilir (`share_intent.dart` zaten
      `markdownSourceProvider`'ı okuyor) — `pickExternal()` · `open(handle)` ·
      `adopt(osToken)` · `probe(handle)`.
- [x] **Fake ve testler**: `test/support/fake_markdown_source.dart` (bellek-içi dosya
      sistemi + senaryo düğmeleri `expireScopeAfter`/`mutateBeforeNextSave`/
      `revokeGrantOnSave` + `writes`/`intents` kayıtları). `syncTestOverrides` bir
      `markdownSource` parametresi kazanır ve **varsayılanı null değil FAKE olur**
      (`shareInbox ?? const NoShareInbox()` idiomu) — böylece HER widget testi diske ve
      kanala ulaşamaz hâle gelir, sadece hatırlayanlar değil. `markdown_import_test.dart`'ın
      satır-içi `_FakeMarkdownSource`'u silinip ortak fake'e bağlanır. Vakalar:
      salt-okunur · süresi dolmuş kapsam · çatışma (ifUnchanged → `SaveConflict`, sonra
      force → `SaveSucceeded`, sonra reload) · bayt sadakati (BOM korunur, CRLF korunur,
      sona `\n` eklenmez) · W4 kapısı · recents kapasitesi + bozuk girdi.
- **Kabul:** dış dosya katmanının her kenarı diske ve native koda hiç dokunmadan
  test edilebiliyor; salt-okunur bir dosyada kaydet eylemi **derlenmiyor bile**.
- **Doğrulama:** `flutter analyze` · `flutter test` · `npm run check:i18n`.

_(✅ 2026-08-12. Süitler **1127** (+19), analyze/format/i18n temiz,
`contrast.py` FAILURES: 0. **ADR-0030 kabul edildi.** CHANGELOG'a satır
yazılmadı — bu turun kullanıcıya görünen bir değişikliği yok ve deponun emsali
bu yönde (OPH-246 da ADR turunda CHANGELOG'a dokunmamıştı); katman kullanıcıya
OPH-251'de çıkacak._

_**W3 gerçekten derleyiciye devredildi ve test bunu ŞEKİLLE kanıtlıyor:**
`saverFor()` yardımcısı `ExternalAccess` üzerinde tüketici bir `switch` yazıyor
ve `saver` yalnız `ExternalWritable` kolunda **var olduğu için** diğer iki kolda
döndürecek bir şey yok. "Buton disabled mı" diye soran bir test bunu geçirirdi;
"bağlanacak bir şey var mı" diye soran, ölü butonu imkânsız kılıyor._

_**Yazarken kendi tasarımımdaki bir açığı buldum:** `_FakeSaver` kodlamayı
**diskteki** baytlardan türetiyordu. Çatışmadan sonra oradaki baytlar BAŞKASININ
sürümü — yani onların BOM'u bizim belgemizin nasıl yazılacağına karar ederdi.
`ExternalSaver.save` artık `encoding`'i parametre alıyor ve o AÇILIŞTAN geliyor.
Bu, W4'ün "bayt-sadıklık" kuralının fark etmesi kolay olmayan bir kenarı._

_**Politika üç yerde durmasın diye `narrowForEncoding()` ortak:** `probe()`
OS'un cevaplayabildiği soruyu cevaplıyor (bu süreç bu baytları yazabilir mi),
ama W4'ün sorusunu cevaplayamıyor (yazmak dokunulmamış baytları değiştirir mi).
Bir dosya pekâlâ yazılabilir olup yine de yazılmayı reddedebilir. Üç native
dosyada duran politika, eninde sonunda kendisiyle çelişen politikadır._

_**`syncTestOverrides`'ın varsayılanı null değil FAKE** — ve bu, tam da
umulduğu gibi bir çağrı yerini zorladı: `markdown_import_test` kendi
override'ını ekliyordu, Riverpod 3 çift override'ı **assert ediyor**, ve test
fake'ini diğer bütün dikişler gibi `syncTestOverrides`'tan geçirmek zorunda
kaldı. Artık HİÇBİR widget testi diske ya da kanala ulaşamıyor — sadece
hatırlayanlar değil._

_**Üretim `PlatformMarkdownSource`'u `NoExternalWriteBack` mixin'i ile
"desteklenmiyor" diyor** ve bunun bir testi var: dürüst cevabın anlamı, hâlâ
saver yok demek — yani hâlâ buton yok.)_

### OPH-256 — Native gerçeklik: macOS · iOS · Android (`alliswell_docref`)

_(OPH-255'in kanalını üç platformda gerçek yapar. Tek in-repo eklenti
`apps/app/packages/alliswell_docref/`, kanal `alliswell/docref`, düzeni
`alliswell_eventkit`'ten birebir — **doğrulanmış numara dahil**: eventkit'in
`macos/.../Sources/` dizini iOS kaynaklarına bir **sembolik bağ**, yani tek Swift dosyası
iki Apple platformuna hizmet ediyor (`#if os(iOS)` / `#elseif os(macOS)`). Gerekçe
`pubspec.yaml`'da yazılı: Flutter tooling podspec'i pbxproj cerrahisi olmadan bağlıyor —
`ios/Runner/` köprüleri (share_inbox, alarmkit) iOS'a hapis ve AppDelegate düzenlemesi
istiyor. Eklenti **ince ve aptal** kalır; politika Dart'ta.)_

- [x] **macOS** — `NSOpenPanel`; `bookmarkData(options: .withSecurityScope)` +
      `startAccessingSecurityScopedResource`; yoklama
      `resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])` —
      **`isWritableFile(atPath:)` DEĞİL**, o POSIX modunu söyler, sandbox iznini değil;
      yazma `NSFileCoordinator(.forReplacing)` + `write(to:options:.atomic)`.
- [x] **macOS entitlement'ları** (`DebugProfile` + `Release`):
      `com.apple.security.files.user-selected.read-write` +
      `com.apple.security.files.bookmarks.app-scope`. Birincisi olmadan panel salt-okunur
      veriyor; ikincisi olmadan bookmark hiç üretilemiyor. **Ve `AppDelegate.swift`'e
      `application(_:open:)`** — `Info.plist` doküman tiplerini beyan ettiği hâlde bugün
      Finder'da bir `.md`'ye çift tıklamak hiçbir Dart koduna ulaşmıyor. URL Dart
      dinlemeye başlamadan geldiği için `ShareInboxBridge` posta-kutusu deseni kullanılır.
- [x] **iOS** — `UIDocumentPickerViewController(asCopy: **false**)`; `bookmarkData()`
      **`.withSecurityScope` OLMADAN** (o seçenek macOS'a özel; iOS'ta doküman-seçici
      bookmark'ı örtük olarak security-scoped — bu, paylaşılan Swift dosyasının ayrışmak
      zorunda olduğu tek yer, yoruma yazılır). `NSFileCoordinator` burada **zorunlu**:
      iCloud/Dropbox sağlayıcıları materyalleşmeyi ve yüklemeyi ondan geçiriyor.
      Entitlement **yok**. Soğuk açılışta URL `SceneDelegate`'in
      `scene(_:willConnectTo:options:)` → `connectionOptions.urlContexts`'ine düşüyor —
      OPH-242'nin zaten belgelediği tuzak; tamponlanır.
- [x] **Android** — `ACTION_OPEN_DOCUMENT` + persistable flag'ler;
      `takePersistableUriPermission(READ or WRITE)` `SecurityException` yakalanarak
      (başarısızlık = `ExternalReadOnly(permissionReadOnly)`); yoklama **iki olgu birden**:
      `persistedUriPermissions…isWritePermission` (bizim tuttuğumuz) **ve**
      `COLUMN_FLAGS and FLAG_SUPPORTS_WRITE` (sağlayıcının izin verdiği —
      `androidx.documentfile` bağımlılığı eklenmez, o yalnız bir sarmalayıcı).
      **Yazma `openOutputStream(uri, "wt")` — `"w"` DEĞİL:** düz `"w"` birçok sağlayıcıda
      dosyayı kesmiyor, yeni belge kısaysa eskinin kuyruğu dosyada kalıyor; yalnız gerçek
      cihazda görünen bir bayt bozulması. Manifest'e `ACTION_EDIT` eklenir,
      **hiçbir `<uses-permission>` eklenmez** — `assert-permissions.sh` değişmeden geçmeli.
- [x] **Atomiklik, dürüstçe asimetrik** (ADR-0030'a yazılır). **Apple: çökme-güvenli** —
      `.atomic` kullanılır, elle temp dosya **yazılmaz**: sandbox izni *seçilen dosyayı*
      kapsıyor, klasörünü değil, kardeş temp dosya gerçek imzalı build'de tam da bu yüzden
      patlar. Mod bitleri okunup geri konur. **Android: değil, ve yapılamaz** — SAF URI'si
      üzerinde rename yok; `"wt"` keser ve akıtır, kesme ile son bayt arasındaki çökme
      kısmi dosya bırakır ve orijinal gitmiştir. Telafi: tek `write`+`flush`+`close`
      (≤2 MB) + kesmeden önce eski baytlar `filesDir/external_recovery/<sha>.md`'ye,
      başarılı kapanışta silinir; açılışta orada dosya bulmak = son kayıt yırtılmış
      olabilir → kullanıcıya geri yükleme. **Reddedilen:** `createDocument` + delete —
      URI'yi değiştirir, kalıcı izni ve tüm recents girdilerini geçersiz kılar.
- [x] **`clipboardRead()`** (OPH-250'nin panodan görsel maddesini besler):
      `{html?, imageBytes?, imageMime?}` — iOS/macOS `UIPasteboard`/`NSPasteboard`,
      Android `ClipData`, web `navigator.clipboard.read()`. Desteklenmeyen platform
      sessizce boş döner.
- **Kabul:** üç platformda da `probe` gerçeği söylüyor ve yazılabilir bir dosyaya yazmak
  **dosyayı diskte değiştiriyor**.
- **Doğrulama:** `flutter analyze` · `flutter test` · `bash scripts/android/assert-permissions.sh`
  (değişmeden geçmeli) · üç platformda `shasum` öncesi/sonrası.
- **En riskli adım — macOS, ve önden yazılmış çıkış kapısı:** özellik burada
  `flutter test`'in göremediği ve CI'ın doğrulayamadığı bir *build yapılandırmasına*
  bağlı; `app-sandbox` zaten açık olduğu için eksik entitlement hata vermiyor, **sessizce
  salt-okunur dönüyor** — meşru salt-okunur bir dosyadan ayırt edilemez. Muhtemel arıza:
  entitlement'lar doğru ama `flutter run`'ın ad-hoc imzalı build'inde app-scope bookmark
  onurlandırılmıyor. **Geri çekilme:** oturum yazılabilir kalır (panel izni süreç boyunca
  yaşar), recents girdisi `sessionOnly` işaretlenir, recents'tan açmak paneli o dosyaya
  konumlanmış olarak yeniden açar — W6 o zaman "hâlâ tutuyoruz" değil "tek tıkla oraya
  dönersin" demektir **ve bant bunu söyler**. Sessizce kırpılmaz.
- **İkinci risk (yalnız zahmetli):** `receive_sharing_intent` ile eklentimiz aynı
  `ACTION_VIEW`'ı gözlüyor, bir `.md` iki kez teslim edilebilir. Token'a göre take-once
  tutucu tekrarı etkisiz kılar; yetmezse OS-açılış şeridi yalnız eklentiye verilir ve
  `share_intent.dart`'ın `.md` eşleşmesi kaldırılır — o yol bu özellik için zaten çıkmaz
  sokak, kopya veriyor.

_(✅ 2026-08-12. Süitler **1142** (+15), analyze/format/i18n temiz, `contrast.py`
FAILURES: 0, **`assert-permissions.sh` YEŞİL** — 18 izin, eklenti sıfır ekledi._

_**Bu tur native kodun kaynak ağacında durmasıyla derlenmesi arasındaki farkı
dört kez gösterdi (OPH-182'nin dersi).** Hepsi ölçüldü:_

_**1. macOS derlemesi OPH-223'ten beri kırıkmış.** `speech_to_text` macOS 11
istiyor, hedef 10.15'ti — `pod install` daha başlarken patlıyordu. Kimse fark
etmemiş çünkü hiçbir şey macOS'u derlemiyordu. Podfile + pbxproj (3 yer) 11.0'a
çekildi._

_**2. `alliswell_eventkit`'in macOS Swift'i HİÇ derlenmemiş** — yani
`pubspec.yaml`'ın "paket kullanmamızın sebebi bu" diye yazdığı sembolik-bağ
numarası macOS'ta sessizce boş bir hedef üretiyormuş. Ölçüm: `pod install`
sonrası Pods projesinde **0** kaynak referansı, `xcodebuild` çıktısında **0**
Swift derleme satırı. Sebep dizin-seviyesi bağ; **dosya-seviyesi** bağa
çevrilince **4** referans ve **12** derleme satırı. İki eklenti de düzeltildi —
eventkit'in macOS köprüsü bugün ilk kez gerçekten derlendi._

_**3. iOS'ta iki gerçek derleme hatası** ancak derleyerek çıktı: `UTType`
(iOS 14+) ve `keyWindow` (iOS 15+). Kök sebep öğrenmeye değer: Podfile'ın
`flutter_additional_ios_build_settings`'i **her pod'u Flutter'ın alt sınırında
derliyor**, podspec ne derse desin — yani eklenti uygulamanın hedefine değil o
tabana göre yazılmak zorunda._

_**4. macOS'ta imzalama, önceden var olan ve SAHİBE ait bir engel.**
`CODE_SIGN_IDENTITY = "-"` (ad-hoc) ama proje geliştirici sertifikası isteyen
entitlement'lar taşıyor. **Benim eklediğim iki entitlement'ın suçu değil:**
ikisini geçici olarak çıkarıp derledim, hata birebir aynı çıktı. Tam macOS
uygulama derlemesi bu yüzden hâlâ yapılamıyor; eklentinin Swift'i pod hedefi
olarak ayrıca derlenip doğrulandı._

_**Doğrulananlar (üründen, kaynak ağacından değil):** iOS — tam uygulama
derlendi ve `Runner.app/Frameworks/alliswell_docref.framework` içinde **17**
sembol var. macOS — pod hedefi `BUILD SUCCEEDED`, 12 Swift derleme satırı.
Android — release APK derlendi, izin kapısı yeşil._

_**Doğrulanmayan ve sahibe kalan:** gerçek dosya turu — üç platformda
`shasum` öncesi/sonrası. Kabul kriteri bunu istiyor ve kod bunu yapamaz.
macOS için önce imzalama sorununun çözülmesi gerekiyor._)

### OPH-251 — Dış dosyanın sahipliği: aç, düzenle, **geri kaydet** (DESIGN §29 W1–W6)

> Bu turun **veri kaybettirebilecek tek özelliği**. W-kuralları bağlayıcıdır.
> Tutamak katmanı OPH-255'te, native gerçeklik OPH-256'da doğar; bu task **arayüz**.

- [x] **Kalıcı dış-belge bandı** (W1): gerçek dosya adı, her modda, oturum boyunca —
      Reading/Source/Quill üçünü de kapsayacak şekilde `note_editor_screen.dart`'ın
      gövdesinde, tek yerde.
- [x] **Açık kaydetme** (W2): autosave dış dosyaya **hiç** dokunmaz; kaydet açık bir
      eylem. D21 göstergesi (kaydedildi/kaydediliyor/başarısız) AllisWell notunu
      anlatmaya devam eder — **bant ayrı bir durum taşır ve ikisi karıştırılmaz.**
- [x] **Yazılabilirlik ÖLÇÜLÜR** (W3): `switch (access)` — kaydet eylemi yalnız
      `ExternalWritable` kolunda **build edilir**, diğer ikisinde hiç kurulmaz (OPH-255
      tipleri bunu derleyici düzeyinde zorluyor: `saver` orada yok). Bant sebebi söyler:
      salt okunur / erişim yitirildi / UTF-8 değil.
- [x] **Bayt-sadıklık** (W4): `canWriteBack` false ise eylem "Dosyaya kaydet" değil
      **"Not olarak kaydet"** olur — hem Delta-kanonik notta hem UTF-8 olmayan dosyada.
- [x] **Altından değişme** (W5): çatışmada üç seçenekli `showAwSheet` — **yeniden yükle**
      (`open(handle)`) / **üzerine yaz** (`save(intent: force)`) / **kopya olarak kaydet**
      (`saveCopy()`). Dosya değişikliği izleme (canlı yeniden yükleme) **bu turda değil**;
      primitifi OPH-255'te doğuyor, pollama UI'ı sonraki tura yazıldı.
- [x] **Son açılan dosyalar listesi** (W6) — `Key('notes-open-markdown')` butonu menü
      butonuna dönüşür ("Markdown dosyası aç…" + "Son açılanlar"); ikinci giriş noktası
      `markdown_import_screen`'in boş durumu, çünkü bayat/kırık tutamak zaten oraya düşüyor.
- [x] **Projeye ekle**: dış dosya, notlara kalıcı olarak aktarılmadan da bir projeye
      bağlanabilir (sahibin isteği: "isterse notlara yaz, projeye ekle").
      **Ölçülen: mevcut iki mekanizmanın ikisi de bunu karşılamıyor** — not→proje düz bir
      kolon (`notes.projectId`, yani önce not olmak gerekir), dosya→proje ise ek tablosu
      (`FileRows`) ve **bir kopyayı R2'ye yükler**, ki bu "dış dosyayı bağlamak" değil
      kopyalamak. Çözüm: recents girdisine `projectId` alanı (yerel, senkronsuz — tutamak
      zaten cihaza özel); `ProjectPickerField` yeniden kullanılır.
- [ ] **Kontrast**: bant yeni bir yüzey → `contrast.py` çiftlerine eklenir.
      **YAPILMADI, ölçülerek:** `contrast.py` bugün `surfaceContainerHigh` üzerine
      hiçbir çift taşımıyor (`grep` ile doğrulandı, 0 eşleşme) — yani bant yeşil
      görünüyor çünkü **hiç ölçülmüyor**, OPH-247'nin yakaladığı yalanın aynısı.
      Bu bant tarafından yaratılmadı: `MdToolbar` ve `MdSlashMenu` da aynı yüzeyi
      kullanıyor ve onlar da kapının dışında. Yani iş "bir çift eklemek" değil,
      **paylaşılan bir yüzeyi kapıya sokmak** — kendi turunu hak ediyor. OPH-247'nin
      dersi bağlayıcı: **elle uydurulmuş bir zemini ölçmek `FAILURES: 0` yalanı söyler** —
      bandın gerçekten çizdiği karışım hesaplanır.
- [x] Testler (seam/fake/recents birim testleri OPH-255'e taşındı — burada **arayüz**):
      bant üç modda da görünüyor ve dosya adını taşıyor; salt-okunur dosyada kaydet eylemi
      **hiç build edilmiyor** (finder boş, `enabled: false` değil); altından değişen
      dosyada üç seçenekli akışın üçü de doğru çağrıyı yapıyor; UTF-8 olmayan dosyada bant
      sebebi söylüyor ve "Not olarak kaydet" sunuluyor; son açılanlar menüsü bir girdiden
      dosyayı yeniden açıyor. i18n: tüm yeni dizeler `en`+`tr`.
- **Kabul:** Mac'te bir `README.md` AllisWell ile açılır, düzenlenir, kaydedilir ve
  **dosya diskte değişmiştir**; iPhone'da Dosyalar'dan açılan bir `.md` için aynısı ya
  çalışır ya da bant dürüstçe "salt okunur" der.
- **Doğrulama:** `flutter analyze` · `flutter test` · macOS + iOS + Android'de gerçek
  dosya turu (öncesi/sonrası `shasum` çıktısı kanıt olarak yazılır).

### OPH-252 — Pazarlama: README + landing + mağaza (beş özellik, gerçek ekran görüntüleri)

- [x] Sahibin sıraladığı **beş özellik** landing'de ve README'de öne çıkar
      ([MARKDOWN.md §8](MARKDOWN.md)): (1) görevler + projeler ve görevlerin projelere
      bağlanması, (2) **notlar + markdown görüntüleyici/editör** — not oluşturma, okuma,
      bilgisayardaki `.md` dosyalarını açma/değiştirme/içe aktarma, (3) **alarmlı
      görevler** — unutturmayan sistem, (4) proje ve görevle ilgili **tüm dosyaların aynı
      yerde** durması, (5) **tekrarlı görevlerin** ne kadar ayrıntılı yapılandırılabildiği.
- [x] **Yol boyunca düzeltilecek ÖLÇÜLMÜŞ çelişkiler** (kapsam genişletmesi değil — aynı
      dosyalarda duran ve deponun kendi guardrail'ini çiğneyen satırlar):

      | Nerede | Ne diyor | Neyi çiğniyor |
      | --- | --- | --- |
      | `apps/landing/src/content.js` `widget` bloğu | "On iPhone you can tick one off from the Home Screen" | STORE-LISTING §5 — **`AppIntent` yok, widget salt-okunur** |
      | `README.md` özellik listesi | aynı iddia | aynı |
      | `docs/COMPARISON.md` (iki yer) | "Home-screen widgets ● iOS/Android/**macOS**" | STORE-LISTING §5 — **macOS widget target yok** |
      | `docs/COMPARISON.md` §5 | "We are at 0.9.0" | bayat (1.3.1) |
      | `README.md` durum satırı | "887 app tests" | bayat (STATE: 1093+) |
      | landing `search` bloğu | Search bloğu **Projects ekran görüntüsü** kullanıyor | kabul kriteri: eşleşen, gerçek görüntü |
      | landing `recurrence` bloğu | `shot: 'web/home-dark.jpg'` — Home görüntüsü tekrar iddiasının yerine geçiyor, üstelik blok `App.vue`'da render'dan **filtreleniyor** | #5 landing'de hiç görünmüyor |
- [ ] **Ekran görüntüleri**: mevcut set (`screenshots/`, `docs/store/`, `store/`) bu beş
      başlığa göre denetlenir; **eksik olanlar** çekilir, **bayat olanlar** yenilenir.
      Çekim `scripts/screenshots/web.mjs` (`--only` bayrağı var; önkoşullar dosyanın
      başında: API + `seed-demo.mjs` + `flutter build web --release` + :8080). Yeni
      görüntüler `/screenshots/<platform>/*.png` altına — `apps/landing/public/shots/`
      gitignore'lu, `sync-screenshots.mjs` build'de kendisi üretiyor.
      **Uyarı:** `docs/screenshots/markdown-reading-{light,dark}.png` bir *conformance
      belgesinin* golden render'ı (1800×10400, 1:5.8) — `ScreenshotFrame`'de kullanılamaz;
      uygulama kabuğu çekimi ayrı iştir.

      | Özellik | Hedef | Durum |
      | --- | --- | --- |
      | 1 görevler+projeler | landing `tasks` bloğu (**yeni**), README | `web/projects.png` var — `search` bloğundan alınır |
      | 2 markdown | landing `markdown` bloğu (**hiç yok**), README | **çekilecek:** okuma görünümü *uygulama kabuğunda*, üç mod, dış dosya bandı |
      | 3 alarmlar | `alarms` | `web/reminders.png` + `android/09-alarm-ring.png` var |
      | 4 dosyalar | `files` | `web/files.png` var; **çekilecek:** görev eki + görsel görüntüleyici |
      | 5 tekrar | `recurrence` (filtre kaldırılır ya da `RecurrenceProof` görselle beslenir) | `ios/07-task-detail-repeat.png` + `08-repeat-dialog.png` **var ama hiç kullanılmıyor** |
- [x] `docs/COMPARISON.md`: §1 "Notes & files" altına markdown satırı (OPH-246…251) + §3
      matrisine markdown satırı + **landing'in kendi ikinci karşılaştırma tablosuna**
      (`content.js` `comparison`) — iki tablo var, biri unutulursa sapıyorlar.
      `docs/STORE-LISTING.md`: Apple `NOTES AND FILES` ve Play blokları + **TR aynaları** +
      karakter sayıları yeniden hesaplanır. **Guardrail bağlayıcı:** hiçbir mağaza metni
      "offline / çevrimdışı" diyemez (Play sürüm kodu 16'yı 2026-08-02'de bu yüzden
      reddetti) — "bilgisayarındaki `.md`'yi aç" ifadesi bağlantı iddiası gibi
      okunmayacak şekilde, **dosya işleme** olarak yazılır.
      §5 guardrail tablosu yeniden denetlenir: round 13'ün "recurring tasks yok" dersi
      **zaten düzeltilmiş** — aranan şey *o zamandan beri doğru hâline gelmiş diğer*
      guardrail'ler, yani bu bir yeniden-denetim, yeni bir düzeltme değil.
- [x] README'nin durum satırı (sürüm + test sayıları) güncellenir.
- [x] Landing (`apps/landing/`, Vue 3) beş bloğa göre düzenlenir; `npm run build` yeşil.
- **Kabul:** landing'e ilk bakışta bu beş şey görünüyor ve her birinin **gerçek** bir
  ekran görüntüsü var (mockup değil).
- **Doğrulama:** landing build · `npm run lint` · görüntülerin çekildiği komutlar
  task'ın altına yazılır (tekrar üretilebilirlik).


_(✅ 2026-08-12, **ekran görüntüsü kutusu açık bırakılarak**. Metin işleri bitti:
README'nin beş özelliği MARKDOWN §8'in bağlayıcı sırasına göre YENİDEN yazıldı
(bugünkü beşi başka bir beşti), landing'e hiç olmayan `markdown` bloğu eklendi,
COMPARISON'a iki satır + landing'in kendi tablosuna bir satır, STORE-LISTING'in
dört bloğuna (EN + TR) markdown maddesi._

_**Guardrail denetimi iki GERÇEK ihlal buldu ve ikisi de kaynağında düzeltildi**
— yeniden bayraklanmadı: (1) widget'tan görev tamamlama iddiası README ve
landing'de canlıydı, oysa §5 bunu yasaklıyor (`AppIntent` yok); (2) COMPARISON
"Home-screen widgets ● iOS/Android/**macOS**" diyordu, §5 "macOS widget target
yok" diyor. Round 13'ün dersinin aynası: bir guardrail **izin verici** yönde
bayatlayabildiği gibi, kural yazıldıktan sonra metin kayarsa **ihlal edilmiş**
yönde de bayatlar._

_**Ekran görüntüleri ALINMADI, ve sebebi ölçüldü:** `web.mjs` çalışan bir API +
`seed-demo` + release web build + :8080 istiyor; bu makinede Docker/MySQL ayakta
değil. Beş başlığın dördü mevcut gerçek görsellerle karşılanıyor; **eksik olan
markdown'ın uygulama kabuğundaki çekimi** — landing şimdilik `web/notes.jpg`
kullanıyor, ki gerçek ama markdown çalışma tezgâhını göstermiyor. Kutu bu yüzden
açık: "gerçek görüntü" kabul kriteri henüz karşılanmadı._)
### OPH-253 — Widget başlığında sistem saati (DESIGN §31 C1–C5)

- [x] **Android**: `tasks_widget.xml`'in sağ sütunu iki satır olur — üstte
      **`TextClock`** (`@RemoteView`, RemoteViews içinde kendi tıklar, refresh bütçesi
      harcamaz), altında mevcut `aw_open_today`. 12/24 saat cihaz ayarından
      (`setFormat12Hour`/`setFormat24Hour` `RemoteViews.setCharSequence` ile), tabular
      rakam, `aw_widget_text` rengi, kalın.
- [x] **iOS**: `AllisWellWidget.swift`'in başlık `HStack`'inin sağ tarafı `VStack` olur;
      saat üstte kalın. **Bulgu #10 bağlayıcı:** `Text(date, style: .time)` canlı
      değildir → timeline **dakika granülerliğinde** girdilerle üretilir (mevcut
      "şimdi + 4 gece yarısı" kalıbının üstüne), saat **entry'nin kendi tarihinden**
      çizilir (round 15'in bayat-gün dersinin aynısı).
- [x] **Dürüstlük kapısı (C3)**: iOS'ta girdi ufku dolduğunda ya da sistem timeline'ı
      onurlandırmadığında başlık **yanlış bir saat göstermez** — saat gizlenir, tarih
      bloğu kalır. Bu davranış bir testle sabitlenir (snapshot yaşı > eşik → saat yok).
- [x] **Bütçe (C4)**: saat için ek `home_widget` yazımı YOK, ek `getTimeline` çağrısı
      YOK — sunum katmanı işi.
- [x] Sıfır açık görevde sayı gizli kalır ve saat sağ sütunun dikey ortasına gelir (C5).
- [x] Testler: `widget_snapshot.dart` tarafında entry tarihinden saat türetme saf testi;
      eşik aşımında saatin düşmesi; Android layout'unun `TextClock` taşıdığını bekçileyen
      test (round 16 `web_shell_test.dart` kalıbı).
- **Kabul:** iki gerçek cihazda widget'ta saat görünür ve **dakika sınırını geçerken
  değişir** (ekran kaydı ya da iki ekran görüntüsü kanıt olarak yazılır); iOS'un
  gecikmesi ölçülür ve STATE'e sayıyla yazılır.
- **Doğrulama:** `flutter analyze` · `flutter test` · Android release APK + iOS release
  build'de widget turu.

**Ek kapsam (sahibin isteği, aynı turda):** widget'ın **ilk gerçek fotoğrafı** çekildi ve
README + landing'e kondu.

- [x] `screenshots/ios/12-widget.png` + `13-widget-dark.png` (iPhone 17 Pro Max, Large,
      gerçek demo verisi). Depoda ilk **ev ekranı** çekimi; komutları
      [SCREENSHOTS §6](SCREENSHOTS.md)'ya yazıldı — mevcut harness ev ekranına ulaşamıyor.
- [x] README telefon şeridine beşinci görsel (`<picture>` ile açık/koyu); kredi satırı
      güncellendi. **Satır 183'teki macOS widget iddiası düşürüldü** —
      [STORE-LISTING.md:1023](STORE-LISTING.md) "macOS widget target yok" diyordu, README
      onu çiğniyordu. Sürüm beş yerde 1.3.0'a hizalandı (README, landing `package.json`,
      `content.js`, JSON-LD, durum satırı).
- [x] Landing'e `features[]` sonuna `widget` bloğu (`frame: 'phone'` — varsayılan tarayıcı
      çerçevesi bir telefon ev ekranının etrafına sahte URL çubuğu çiziyordu).
      **`shotDark` ölü veriydi** (`content.js`'te tanımlı, hiçbir bileşen okumuyor);
      `ScreenshotFrame`'e bağlandı — bu `useTheme`'i modül seviyesine taşımayı gerektirdi,
      yoksa tema düğmesi sayfayı çevirip resmi çevirmiyordu. Uzun telefon görselinin CLS'i
      için `aspect-ratio` eklendi.
- **Ölçülenler (DESIGN §31'in altına da yazıldı):** timeline arşiv tavanı
  **16,665,560 bayt** (241 girdi reddedildi, widget placeholder'da kaldı) → ufuk artık
  bayt bütçesinden türetiliyor; dakika sınırı diff'i **13×16 pt**, yalnız bir rakam.
  **Başlık üstten kırpılıyordu** (`.frame(maxHeight:)` kelepçelemiyor) — `GeometryReader`
  ile sabit yükseklik + `.top` hizası.
- **Kalan:** Android emülatöründe `TextClock` turu ve `systemMedium`/`extraLarge`
  görselleri; makinede Docker/MySQL olmadığı için v3 snapshot'lı taze demo verisi yerine
  30 Temmuz'un gerçek seed çıktısı kullanıldı.

## Epic 25 — İstek turu 18: MCP tam kapsama, API anahtarları, gelişmiş ayarlar, not sürümleme & çakışma yönetimi (v1.5.0)

_(Doğdu 2026-08-13 — sahibin sekiz maddelik listesi. (1) **MCP her işlevi kapsasın**: bugün not
oluşturma bile yok; acil alarm işaretlemekten detaylı görev eklemeye, notu göreve bağlamaktan
proje yönetimine her alan birebir kontrol edilebilsin, ve bundan sonra her yeni özellik MCP'ye
de eklensin diye kalıcı bir doküman belirteci konsun. (2) **API katmanı**: kullanıcı Ayarlar'dan
API anahtarı üretsin, süresini/son kullanımını görsün, iptal edebilsin; notları içe/dışa
aktarabilsin, görev/not/proje dahil tüm yazılım işlemleri API'den yapılabilsin; karmaşık
doğrulama YOK — [issue #3](https://github.com/mahirozdin/alliswell/issues/3) doğrudan referans.
(3) **Ayarlar çok karıştı**: işleve göre gruplanıp alt sayfalara bölünsün; takvimler/AI/API
"Entegrasyonlar" altına. (4) [issue #2](https://github.com/mahirozdin/alliswell/issues/2) (OIDC)
araştırılıp ekle/reddet kararı verilsin ve issue uygun dille kapatılsın. (5) **MD editörde
boyama**: son kullanılan 5 renk görünsün — renk seçici olan her yerde; mevcut seçici ne UI ne
UX olarak kullanışlı. (6) **Notlar düzenlenme tarihine göre** sıralansın; sıralama seçenekleri
liste ekranlarına gelsin, satır kaplamadan app bar'da dursun. (7) **Not sürümleme + offline
çakışma yönetimi**: bugün aynı not iki cihazda düzenlenince override yaşanıyor; Google
Docs/Word/bulut ürünleri nasıl çözüyor en az 5 kaynaktan araştırılıp sağlam, kurumsal
kurgulansın. (8) **Geri al barı kaybolmuyor** — daha önce de bildirildi, düzelmedi; web'de de
mobilde de elle kaydırmadıkça gitmiyor.)_

_**Planlama turunda yapılanlar (2026-08-13):** dört paralel keşif koşuldu (MCP/REST envanteri ·
Flutter UI dörtlüsü · sync/çakışma mekaniği · 12+ ürün/sistemlik literatür taraması), bulgular
aşağıdaki iki tabloda; **AGENTS.md kural 12** yazıldı (madde 1'in kalıcı belirteci: her özellik
MCP + docs/API.md yüzeyini de günceller, istisnalar yazılı); **DESIGN §32–§35** bağlandı
(ayarlar IA'sı, renk seçici, sıralama denetimi, sürüm/çakışma yüzeyleri); issue #2 (OIDC)
için karar verildi (aşağıda, "karara bağlananlar" #12) ve park listesine tasarım
taslağıyla yazıldı; issue #3'e plan referansı yorumu bırakıldı._

> **Turun tek cümlesi:** sekiz maddenin dördü cilalama (geri al, sıralama, renk, ayarlar
> düzeni), ikisi ürünün **programlanabilir yüzeyini** doğurma (MCP tam kapsama + API
> anahtarları — 78 REST rotasına karşılık MCP'de 7 araç var), biri ise ürünün **hafızasını**
> doğurma: bugün ezilen bir not gövdesi HİÇBİR yerde durmuyor; sürümleme + not-bazlı base +
> sunucuda diff3 birleştirme bunu "asla sessizce kaybetme" sözleşmesine çevirecek.

**Round'un ÖLÇÜLMÜŞ gerçekleri (planlama turu, 2026-08-13 — hiçbiri varsayım değil; task
uygulanırken satırlar yeniden doğrulanır):**

| # | Bulgu | Kanıt | Sonuç |
| - | ----- | ----- | ----- |
| 1 | Çakışma kopyası mekanizması YAZILI ve TESTLİ (sunucu `NOTE_CONTENT_CONFLICT`, istemci kopya) — ama kilidin base'i yanlış şey: istemci push'ta notun revizyonunu değil **workspace pull imlecini** gönderiyor | `sync_engine.dart:204` (`baseRevision: state.lastRevision`) · sunucu kıyası `sync.js:550-556` · kopya `sync_engine.dart:281-322` | Soket/60 sn zamanlayıcı pull yaptığı an imleç karşı yazımı geçiyor → kilit kör → **sessiz override**. Düzeltme mutation-bazlı `baseRevision` (OPH-268) |
| 2 | Açık editör pull ile gelen içeriği HİÇ yeniden okumuyor (`_doc` `initState`'te bir kez kurulur, `didUpdateWidget` yok); pull replikayı editörün ALTINDA ezer | `note_editor_screen.dart:107` · `sync_applier.dart:101-107` (koşulsuz upsert) | Çevrimiçi senaryoda kopya bile üretilmeden override. Editör davranışı DESIGN §35 V7 (OPH-268) |
| 3 | Bir push batch'i TEK `baseRevision` taşıyor ve settle kopyayı satır başına üretiyor → aynı nota N otosave = N çakışma kopyası; kopya `contentFormat` taşımıyor (markdown notun kopyası 'delta' doğuyor) | `sync.js:1455-1468` · `sync_engine.dart:248-253`, `:288-311` | Outbox'ta not-başına koalesans + kopyada format alanı (OPH-268) |
| 4 | Ezilen not gövdesi HİÇBİR tabloda durmuyor: `sync_revisions` yalnız işaret (kolon adları), gövde tarihçesi yok | `db/sync.js:27-35` · migration `20260714000400:15-31` | Override geri getirilemez → `note_versions` (OPH-267) |
| 5 | Not güncellemesi 1.5 sn boşluk debounce'lu TAM gövde değişimi (title+delta+markdown+format); REST `PATCH /notes/:id` ise HİÇ çakışma kontrolü yapmıyor | `note_editor_screen.dart:77,198-209` · `note_document.dart:217-227` · `notes.js:390-438` | Snapshot birimi hazır; REST'e de base parametresi (OPH-267/268) |
| 6 | Markdown-canonical notta `plain_text` HİÇ türetilmiyor (yalnız `contentDelta` yazımında güncelleniyor) → FULLTEXT arama, `?q=`, MCP `search`/`get_note` o notlar için kör; export da markdown-canonical notta bile delta-öncelikli | `notes.js:161-180` (`row.plain_text` yalnız delta dalında) · `notes.js:380-382` | İki dürüstlük onarımı OPH-261'de |
| 7 | MCP yüzeyi: 7 araç / 78 REST rotası. `update_task`, snooze, checklist, not oluşturma/bağlama/listeleme, proje/etiket araçları tamamen yok; domain katmanı yalnız `db/tasks.js` (notes/projects/tags mantığı hâlâ route içinde) | `lib/mcp/tools.js:122-608` · route envanteri planlama raporunda | ADR-0022 K4 ("MCP ham SQL değil domain katmanı çağırır") gereği önce çıkarım: OPH-261 |
| 8 | MCP kısıtları bağlayıcı: delete KALICI dışarıda; yazma araçları annotation + `ai_action_log(source='mcp')` + `mcp_mutations` idempotency taşır; `ai_action_log` insert'i iki handler'da kopya duruyor, helper yok; red-team korpusu `apps/app/test/fixtures/ai_redteam.json` + `mcp-injection.test.js` CI'da | ADR-0022 Decision 3-4 · `tools.js:10-19,531-540,594-603` · `mcp-injection.test.js:15-19` | Her yeni araç aynı yola oturur; `recordMcpAction()` helper'ı OPH-262'de doğar |
| 9 | API-key zemini hazır ama tablo yok: `hashMcpToken` HMAC-SHA256 + domain separator + char(64) deseni, `newOpaqueToken(48)`, tek `authenticate` decorator'ü (78 rotanın tamamı `onRequest: [app.authenticate]` üzerinden `request.user` kullanıyor), MCP'de token-başına rate-limit `keyGenerator` emsali | `lib/tokens.js:52-63` · `plugins/auth.js:39-50` · `mcp.js:243-254` | Çift-modlu authenticate ile TÜM rotalar tek dosyadan anahtar-uyumlu (OPH-264) |
| 10 | Geri al barının kök nedeni Flutter 3.44'ün kendisi: `SnackBar.persist` varsayılanı `action != null` — Undo'lu her bar otomatik kapanıştan MUAF; zamanlayıcı 2750 ms'de tetiklenip `persist` yüzünden dönüyor ve `_snackBarTimer` bir daha kurulmuyor. Uygulama hiçbir yerde `persist:` geçmiyor; dört action'lı snackbar da aynı durumda | SDK `snack_bar.dart:303` (`persist = persist ?? action != null`), `scaffold.dart:617-625` · `widgets/swipe_actions.dart:114-139` · grep `persist:` → 0 | Tek satırlık fix DEĞİL: bayat barda "Geri al" sessiz no-op (`pending_deletes.dart:66`), `commitNow()` hiç bağlanmamış ölü kod, ve Round 13'te aynı şikâyet "süre sorunu" sanılıp 5sn→3sn sabitiyle YANLIŞ kapatılmış (`TASKS.md:5347-5350`) — OPH-257 üçünü birden kapatır |
| 11 | MD editörde renk aksiyonu aslında YOK (`mdActions()`: bold…divider, renk yok); Live modda Quill'in stok renk diyaloğu açılıyor — **hex alanıyla** ("no hex" kuralının canlı ihlali); delta→markdown dönüşümü `color`/`background`'ı SESSİZCE düşürüyor | `md_actions.dart:106-200` · quill `color_dialog.dart:36,125-131` + `note_editor_screen.dart:604-617` (color butonları kapatılmamış) · `delta_markdown.dart:56-66` | OPH-259: kendi `AwColorPicker`'ımız + stok diyaloğun ölümü + dönüşüm dürüstlüğü (DESIGN §33) |
| 12 | "Son kullanılan renk" mekanizması hiç yok (grep 0); cihaz-yerel kalıcılık emsalleri hazır: `localKv` (`alliswell_*` anahtarları) + `PersistedChoice`, dış-dosya recents şekli `external_session.dart:121-148` | `core/kv/local_kv.dart` · `core/persisted_prefs.dart:36-95` | MRU listesi `alliswell_recent_colors` (OPH-259) |
| 13 | Notlar `id DESC` sıralanıyor (≈oluşturma; `updated_at` OKUNMUYOR) — oysa `updatedAt` her kayıtta zaten damgalanıyor ve satırda ZATEN gösteriliyor; pinli not öne GELMİYOR (pin bugün filtre); Notes app bar'ı ölçülü olarak telefon sınırında (tek "aç" düğmesi bile bu yüzden menü olmuştu) | `note_store.dart:63-89,127-132` (`OrderingTerm.desc(n.id)`) · `:210` (`updatedAt` damgası) · `external_open_menu.dart:8-10` | Varsayılan `updatedAt DESC` + görünüm/sıralama TEK menü düğmesi (DESIGN §34, OPH-258) |
| 14 | Kullanıcıya açık tek sıralama seçici proje Files sekmesinde (`_FileSort` enum + PopupMenu, `setState`-geçici, kalıcı değil); global Dosyalar bölümünde sıralama denetimi HİÇ yok; Ayarlar 19 satırlık düz liste, tek `Divider`'lı tek dev kart; tema satırı diye bir şey YOK (`themeMode` hardcoded system) | `project_detail_screen.dart:524-645` · `files_screen.dart` grep sort → 0 · `settings_screen.dart:40-263` · `app.dart:35` | §34 L4 paylaşılan bileşen; §32 S5 "satır icat etme" |

**Madde 7'nin literatür taraması (sahibin şartı "en az 5 kaynak" — 12+ ürün/sistem tarandı;
tam rapor kararlarla birlikte ADR-0031'e girecek):**

| Ürün / sistem | Mekanizma | Doğrulanmış sayılar / dersler | Kaynak |
| --- | --- | --- | --- |
| Google Docs | OT + append-only revizyon logu; **her değişiklik base revision taşır** ("what the editor saw"); adsız revizyonlar zamanla birleştirilir, adlandırılmış sürüm sabit kalır | 40 adlı sürüm/doküman; "deleting version history is permanent" | idl.uw.edu 2010 OT whitepaper · support.google.com/docs/answer/190843 |
| CouchDB/PouchDB | MVCC revizyon ağacı; çakışan dallar İKİSİ de saklanır, deterministik "kazanan", çözüm UYGULAMANIN işi | compaction gövdeyi atar, soy kütüğünü tutar (`_revs_limit`) | docs.couchdb.org/en/stable/replication/conflicts.html · pouchdb.com/guides/conflicts.html |
| Obsidian Sync | Markdown'da otomatik merge (diff-match-patch), diğer dosyalarda LWW; v1.9.7'den beri cihaz başına "merge / conflict file" seçimi | Sürüm geçmişi 1 ay (Standard) / 12 ay (Plus); kopya adı `(Conflicted copy device YYYYMMDDHHMM)` | obsidian.md/sync · obsidian.md/help/sync/troubleshoot |
| Joplin | Merge YOK — yerel sürüm Conflict defterine kopyalanır (en çok şikâyet edilen UX'i); restore mevcut sürümü DEĞİŞTİRMEZ | 10 dakikada bir sürüm; varsayılan 90 gün; saklama cihazlar arası MINIMUM'a iner → politika SUNUCUDA olmalı | joplinapp.org/help/apps/note_history · /help/apps/conflict |
| Standard Notes | ≥5 dk aralıklı sürümler; cihaz-içi (ücretsiz) + uzak (ücretli) geçmiş; "Restore" VE "Restore as copy" | plan gün sayıları resmî sayfadan doğrulanamadı (bot 403) — işaretli | standardnotes.com/help/26 |
| Figma | OT REDDEDİLDİ ("unnecessarily complex"), tam CRDT de değil: **alan-bazlı LWW**, metin tek property | ders: skaler alanlara LWW yeter, gövde ayrı muamele ister | figma.com/blog/how-figmas-multiplayer-technology-works |
| Yjs / Automerge (CRDT) | Karaktere kadar otomatik merge; tarihçe yapının içinde | Yjs: gerçek iz üzerinde ~%53 ek yer; Automerge ~1.1 B/op; **Dart'ta bakımı yapılan port YOK** → 6 platformda FFI riski | blog.kevinjahns.de/are-crdts-suitable-for-shared-editing · automerge.org/docs |
| git / diff3 | 3-yollu birleştirme "altın standart"; çakışan hunk asla sessizce seçilmez | diff3 makalesi: garanti yalnız "iyi ayrılmış" bölgelerde — markdown'ın tek-satır paragrafları satır-bazlıyı yanıltır → **kelime-düzeyi inceltme şart** | cis.upenn.edu/~bcpierce/papers/diff3-short.pdf · git-scm.com/docs/merge-strategies |
| Notion | Sayfa geçmişi gün-gruplu; restore sonrası her noktaya dönülebilir | 7 gün Free / 30 Plus / 90 Business / sınırsız Enterprise | notion.com/help/duplicate-delete-and-restore-content |
| Dropbox | "Conflicted copy" adlandırma sözleşmesi (ad + kullanıcı + tarih); merge denenmez | 30/180/365 gün plan kademeleri | help.dropbox.com/organize/conflicted-copy |
| Kütüphaneler | **node-diff3** (MIT, sıfır bağımlılık, aktif) birincil motor; **jsdiff** kelime-inceltme + geçmiş diff'i; **diff-match-patch Google tarafından 2024-08-05'te ARŞİVLENDİ** — fuzzy patch zaten istenmiyor (Obsidian'ın "duplicate üretebilir" uyarısının sebebi); pub.dev'de 3-yollu merge paketi YOK → merge SUNUCUDA | github.com/bhousel/node-diff3 · github.com/kpdecker/jsdiff · github.com/google/diff-match-patch |

**Round'da karara bağlananlar (AGENTS §8 — sor değil, karar ver ve yaz):**
(1) MCP'de `delete_*` KALICI olarak yok (ADR-0022'nin kuralı aynen); silme yetkisi API-anahtar
yüzeyinde VAR — iki yüzeyin güven modeli farklı (AI öneri yapar, anahtar sahibin kendi
otomasyonudur) ve bu ayrım ADR-0032'ye yazılır. (2) MCP dosya araçları metadata döndürür,
**presigned URL / bayt asla** (AI.md §7'nin sınırı); dosya yükleme MCP'ye girmez, yazılı sebep:
baytlar MCP host'larından akmaz. (3) API anahtarı **OAuth'suz düz Bearer**: `awk_` önekli tek
gösterimlik sır, HMAC-SHA256 hash'le saklanır (`hashMcpToken` deseni), scope YOK (v1 karar —
anahtar sahibinin tam yetkisi, tek workspace'e bağlı, MCP bağlantısı emsali), anahtar-başına
rate limit. (4) Anahtar yönetim uçları YALNIZ JWT ile çalışır (anahtar anahtar üretemez);
`/auth/*`, hesap silme ve `/ai/*` (BYOK sırları) anahtara KAPALI. (5) Sürümler sunucuda yaşar,
replikaya İNMEZ — geçmiş ekranı çevrimiçi yüzeydir (DESIGN §35 V6). (6) Merge SUNUCUDA koşar
(`node-diff3` satır + `jsdiff` kelime inceltme): pub.dev'de diff3 yok, iki dilde iki merge
motoru tutarsızlık üretir; istemci yalnız SONUCU çizer. Fuzzy patch (dmp) motor olarak RED.
(7) Merge yalnız üç taraf da markdown-canonical iken; delta-canonical notlar çakışmada doğrudan
banner/kopya yoluna düşer (Delta JSON'a satır-merge uygulanmaz — dürüst sınır). (8) Çakışmanın
varsayılan yüzü **not üstünde banner**; kendiliğinden kardeş-not üretimi ölür, "kopya olarak
ayır" kullanıcının seçtiği eylem olur (DESIGN §35 V3). Kayıp taraf HER durumda sürüm satırı
olarak saklanır. (9) Saklama sunucu-politikasıdır (Joplin'in min-across-devices tuzağı):
0–7 gün hepsi (10 dk sunucu koalesansı), 7–90 gün günde 1, sonrası silinir; `conflict`/
`merge`/`restore`/`import` kökenli sürümler 365 gün; not başına tavan 500; env:
`NOTE_VERSION_RETENTION_DAYS` vb. (10) Restore TARİHİ YENİDEN YAZMAZ: yeni head sürümü üretir;
"kopya olarak geri yükle" ikinci seçenek (sektör normu, üç üründe doğrulandı). (11) Renk
seçicide hex ASLA görünmez; son-5 MRU globaldir ve her yüzey kendi paletiyle KESİŞİMİ gösterir
(§23 Q8a kontrat bozulmaz); markdown'a renk sözdizimi EKLENMEZ (GFM'de yok — parked, yazılı
sebep). (12) **Issue #2 (OIDC): meşru ve Firebase'den farklı bir istek — ama bu tura girmez.**
Sunucu yarısı ucuz (ADR-0026'nın `oauth-identity.js`'i zaten JWKS+issuer+audience doğruluyor;
"issuer listesi konfigürasyona açılır" işi), istemci yarısı pahalı (6 platformda code+PKCE
tarayıcı akışı + deep-link dönüşü). Park listesine tasarım taslağıyla yazıldı, issue nazikçe
"parked/not planned" kapatıldı; tetikleyici: çok kullanıcılı workspace UI'ı gündeme gelirse
birlikte açılır. (13) Ayarlar yeniden yapılanması SATIR İCAT ETMEZ (tema anahtarı yok —
`themeMode` hardcoded; §32 S5). (14) Home/Projeler sıralamaya AÇILMAZ (yazılı sebepler §34 L5).
(15) Sürüm/etiket kesimi bu epic'in işi DEĞİL (Epic 24'ün 4. kararı emsal — ayrı tur).

**Sıra bağlayıcı ve iş paketleri:** `257 → 258 → 259 → 260` (P1, uygulama cilası) ·
`261 → 262 → 263` (P2, domain çıkarımı + MCP) · `264 → 265 → 266` (P3, API katmanı) ·
`267 → 268 → 269` (P4, sürümleme & çakışma). Paketler kendi içinde sıralı; P2/P3/P4'ün
tamamı OPH-261'e bağımlı olduğundan paketler arası sıra da bağlayıcıdır. **Cihaz/elle
doğrulama isteyenler:** 257 (bir web + bir telefon hızlı bakışı — SnackBar davranışı widget
testinde de kanıtlanır ama göz teyidi ucuz), 259/260 (light+dark görsel tur + `contrast.py`),
263 (MCP Inspector koşusu — ADR-0022'nin ayakta duran uyum kanaryası), 269 (iki cihazla
gerçek çakışma provası: uçak modu + aynı nota iki düzenleme).

### OPH-257 — Geri al barı: `persist` varsayılanını yen, bayat Geri al'ı sustur, yalanı sil

_Kök neden ÖLÇÜLDÜ (bulgu #10) — bu task teşhis değil, kapanıştır. Round 13'ün "süreyi kısalt"
düzeltmesi neden işe yaramadı sorusunun cevabı da budur: bar süresini hiç dinlemiyordu._

_(✅ 2026-08-15 — **kırmızı önce üretildi, sonra kapatıldı.** Kök neden SDK kaynağından
doğrulandı (Flutter 3.44.0 tag'i: `snack_bar.dart:303` `persist = persist ?? action != null`,
`scaffold.dart` zamanlayıcısı `if (snackBar.persist) return;` ile dönüp bir daha kurulmuyor) ve
gerçek uygulama widget testinde üretildi: bar, pencere kapandıktan 3 sn sonra hâlâ ekrandaydı.
Süitler **1157** (+9), analyze/format/i18n temiz._

_**Turun tek cümlesi: ilk yazdığım kapı yanlış sebepten geçiyordu.** `persist: false`'u
yorum satırına alıp kasıtlı ihlal enjekte ettiğimde `delete_flow_test` **yeşil kaldı** —
çünkü eklediğim yedek zamanlayıcı barı zaten indiriyordu. Yani o testler bayrağı değil,
kendi mekanizmamı ölçüyordu; ve bayrağa tek dayanağı olan **diğer üç bar** (pano taşıma,
AI onayı, kırık kısayol) korumasız kalırdı — onların yedeği yok. Bunun üzerine
`test/widgets/snackbars_test.dart` yazıldı: çıplak yardımcıyı kurar, yedek yoktur, bayrak
kalkınca **kırmızıya döner** (enjekte edilip ölçüldü, sonra geri alındı)._

_**İkinci bulgu: D4 zaten doğruyu yazıyormuş, davranış yokmuş.** DESIGN §19 D4 round 10'dan
beri "delete, snackbar kapanınca ya da ekrandan çıkılınca commit olur" diyor; `commitNow()`
o niyet için yazılmış ama **hiçbir zaman çağrılmamıştı**. Artık barın `closed` future'ına
bağlı: bar giderse (zaman aşımı · kullanıcı kaydırması · sıradaki silmenin `clearSnackBars`'ı)
silme kesinleşir. Görmediğin geri-al, sahip olmadığın geri-aldır._

- [x] `widgets/swipe_actions.dart` → ortak bir `showAwActionSnackBar(...)` yardımcı fonksiyonu
      doğur (aynı dosyada ya da `widgets/snackbars.dart`): `persist: false` + verilen `duration`
      + action'ı sarar; `awDeleteWithUndo` bunu kullanır. **Uygulamadaki action'lı dört snackbar
      da** bu yardımcıya taşınır: `home_board.dart:71-75` (board.undo), `ai_confirm_card.dart:277-290`,
      `quick_access_navigation.dart:121-128`. (Gelecekteki bir action'lı snackbar'ın aynı tuzağa
      düşmemesi için tek kapı.) → `lib/src/widgets/snackbars.dart`; dördü de taşındı.
- [x] Bayat "Geri al" no-op'u kapat: `PendingDeletes.undo` artık **bool** dönüyor (iptal
      edilecek bir şey var mıydı). Dönen `false` ise bar kapanırken gelen dokunuş sessiz
      kalmıyor, `common.undoTooLate` ile dürüstçe cevaplanıyor (en+tr eklendi).
- [x] `commitNow()` — **silinmedi, BAĞLANDI.** Ölü olmasının sebebi eksik niyet değil eksik
      çağrandı: D4 bu davranışı round 10'da tarif etmiş. Artık `bar.closed` future'ına bağlı
      ve `reason != action` ise commit eder. Birim testleri iki kez commit etmediğini ve
      iptal edilmiş bir silmeyi diriltmediğini sabitliyor.
- [x] İki yalan gerçeğe çekildi: `swipe_actions.dart`'ın "control is never on screen after it
      stops working" cümlesi artık mekanizmayla doğru (yedek zamanlayıcı commit ederken barı
      indiriyor); `pending_deletes.dart`'ın Round-13 fosiline "bu sabit yalnız commit'i
      yönetiyordu, barı hiç yönetmedi" notu düşüldü. `delete_flow_test`'in "5 s window"
      yorumu da (round 13'ten beri 3 sn) düzeltildi.
- [x] Testler (+9, süit 1148 → **1157**): `test/widgets/snackbars_test.dart` (bayrağın
      GERÇEK kapısı — ihlal enjekte edilip kırmızı görüldü, geri alındı) ·
      `test/core/pending_deletes_test.dart` (undo'nun bool sözleşmesi, çok-geç hâli,
      commitNow'ın tek-seferliği, iptal edilmişi diriltmemesi) · `delete_flow_test.dart`'a
      üç regresyon: liste swipe'ında ve detay ekranında bar KENDİLİĞİNDEN gidiyor + ikinci
      silme birincisini kesinleştiriyor.
- [ ] **Elle tur — AÇIK, ölçülmüş sebeple.** Bu makinede canlı web/telefon turu kurulamıyor:
      `docker info` başarısız ve `colima` PATH'te yok, yani API+MySQL ayağa kalkmıyor (uygulama
      giriş olmadan listeye ulaşmıyor). `flutter test --platform chrome` ile web motorunda
      koşmak da harness'ın kendisi yüzünden imkânsız: `test/flutter_test_config.dart` i18n
      JSON'ını `dart:io` `File` ile okuyor ve her teste uygulanıyor (`Unsupported operation:
      _Namespace`). **Dürüst sınır:** kalan risk düşük ama sıfır değil — düzeltmenin çalıştığı
      kod (`ScaffoldMessengerState.build`) saf Dart'tır ve her platformda aynıdır, üstelik
      testler onu gerçek widget ağacında çalıştırıyor; bu, native köprü sınıfı bir belirsizlik
      DEĞİL. Sahibin bir sonraki turunda bakılacak: sil → 3 sn bekle → bar kendiliğinden gider.

### OPH-270 — İmleç yerinde kalır: Quill'in her derlemede yeni odak düğümü üretmesi (ACİL, sıra dışı)

_(Doğdu ve kapandı 2026-08-15 — sahibin acil raporu: "not yazamıyorum". Gövdeye yazarken
"kaydedildi" tiki çıktığı anda odak başlığa sıçrıyor, imleç başlığın ortasına düşüyor;
ayrıca mobilde gövdede imleç kayboluyor gibi oluyor. Sıra bozuldu, bilinçli: yazmayı
engelleyen bir arıza sıradaki işi bekleyemez.)_

_**Kök neden ÖLÇÜLDÜ, paket kaynağından:** `QuillEditor.basic`, kendisine verilmediğinde
**her çağrıda yeni bir `FocusNode` ve `ScrollController` üretiyor**
(`flutter_quill-11.5.1/lib/src/editor/editor.dart:163-164`). Editörümüz ikisini de
vermiyordu ve `_body()` her `setState`'te koşuyor — yani her yeniden derleme gövdenin
odağını çöpe atıyor, odak kapsayıcıya düşüyor ve ağaçtaki **ilk odaklanabilir alan olan
başlığa** yerleşiyordu. Sahibin "kaydedildi özelliğinden sonra başladı" tespiti birebir
doğru: D21'in kayıt göstergesi (`_setSaveState`) kayıt anına **iki ek `setState`** koydu
ve o güne kadar sessiz duran hata her kayıtta görünür oldu._

_**Yanlış hipotez, ölçülerek elendi:** ilk şüpheli `SourceMode`'daki
`Focus(autofocus: true)`'du. İzole bir testle sınandı ve **çürüdü** — saf bir ebeveyn
`setState`'i Source alanının odağını almıyor. Kaybettiğim on dakika, tahminle
düzeltmenin maliyetinden ucuzdu._

_**Yol üstünde ölçülen, düzeltilmeyen:** markdown-canonical notlar **Okuma** modunda
açılıyor (`NoteDocument` kurucusu `cameFromOutside: _format == NoteFormat.markdown`
diyor) — yani kendi dönüştürdüğün not her seferinde salt-okunur açılıyor. Ayrı bir
karar; bu turda dokunulmadı, park kuyruğuna yazıldı. Ayrıca `project_detail_screen.dart:374`
ve `markdown_import_screen.dart:266` aynı `QuillEditor.basic` desenini kullanıyor ama
ikisi de `showCursor: false` — salt-okunur önizleme, kaybolacak imleç yok._

- [x] `NoteDocument` odak düğümünü ve kaydırma kontrolcüsünü sahiplenir (`quillFocus`,
      `quillScroll`) — diğer kontrolcülerle aynı gerekçe (D3: "bir belge başına bir kez
      yaratılır, her mod değişimini atlatır") ve `dispose`'da bırakılır.
- [x] `note_editor_screen.dart` Live gövdesinde ikisini de **geçirir**; neden geçirilmek
      ZORUNDA olduğu satırın yanında yazılı.
- [x] Testler (+3, süit 1157 → **1160**), `test/features/notes/note_focus_test.dart`:
      odak düğümü kimliğinin yeniden derlemeyi atlattığı (kapı — `focusNode` kaldırılıp
      kırmızı görüldü, geri alındı) · kaydettikten sonra başlığın odak ALMADIĞI ·
      Source modunda yazıp autosave'i bekleyince imlecin gövdede kaldığı. Sahte API
      artık markdown notu tohumlayabiliyor (`contentFormat`/`contentMarkdown`).
- [x] v1.4.1 kesildi ve sevk edildi (sürüm 6 yerde hizalandı, release kapısının okuduğu
      üçü dahil).

### OPH-258 — Liste sıralaması: notlar düzenlenmeye göre, denetim app bar'da (DESIGN §34)

_Bulgu #13/#14. `updatedAt` zaten her `update()`'te damgalanıyor (`note_store.dart:210`) ve
satırda zaten gösteriliyor — iş sıralamayı ona çevirmek ve seçiciyi SATIR HARCAMADAN vermek._

_(✅ 2026-08-15 — Süitler **1176** (+16), analyze/format/i18n temiz.)_

_**Turun tek cümlesi: sıralama bir SORGU değil, bir görüntüleme tercihi — ve bu, nerede
yaşayacağını belirledi.** Sıra `NotesQuery`'ye bindi (store onu uygulayabilen tek yer,
çünkü başlık sırasının ihtiyaç duyduğu fold'u SQLite yapamıyor — ADR-0013'ün kendi
dersi), ama tercihin kendisi `PersistedChoice`'ta, cihazda, ekranın state'inde değil._

_**Yol boyunca çıkan iki şey:** (1) kendi testimin beklentisi yanlıştı — fold hem `İ`
hem `ı`'yı `i`'ye indiriyor (bilinçli, ADR-0013), yani `ırmak` `İzmir`'den ÖNCE gelir;
kodu değil testi düzelttim ve yorumunu gerçeğe çektim. (2) `notes_flow_test`'in
koşumunu ikinci kez kopyalamak üzereyken durup ortak dosyaya aldım — iki dosya aynı
sahte uygulamayı kurmamalı._

- [x] `AwSortMenuButton` (`widgets/sort_menu.dart`): checkmark'lı seçenekler + "Ters çevir";
      seçenek kümesi ve durum parametre, kalıcılık çağırana ait. Model `core/list_sort.dart`
      (`AwSortChoice` · `AwSortState` — `field:dir` olarak saklanır, bozuk/eski değer
      yüzeyin ilk seçeneğine düşer, alan değişince o alanın DOĞAL yönü gelir: tarih
      yeniden-eskiye, başlık A→Z).
- [x] Notlar varsayılanı **düzenlenme, yeniden eskiye**; null zinciri (`updatedAt` →
      `createdAt` → ULID) tek yerde (`_noteInstant`). Başlık sırası fold-duyarlı. Arama
      açıkken tier önce, seçilen sıra tier İÇİNDE (yoksa sıralama sessizce yok sayılırdı).
      Pin sıralamayı değiştirmiyor (§34 L5). Proje notlar sekmesi de varsayılan sırayı alıyor.
- [x] Notes app bar'ı: görünüm + sıralama TEK menüde (`list-sort-menu`); `notes-view-toggle`
      ikonu kalktı, işlevi menünün "Görünüm" bölümünde.
- [x] Global Dosyalar bölümü seçiciye kavuştu (hiç yoktu) ve proje Files sekmesinin
      `_FileSort` enum'u paylaşılan bileşene taşındı — ikisi de `alliswell_files_sort`'u
      paylaşıyor, yani artık **hatırlanıyor** (eskiden `setState` ile ölüyordu).
- [x] Testler (+16): `list_sort_test` (kodlama/çözümleme/yön/karşılaştırıcı, 8) ·
      `note_sort_test` (üç sıra + ters çevirme + tarihsiz not + menüden seçim + kalıcılık, 7) ·
      Kaynaklar katmanında sıralama + kalıcılık (1). Mevcut iki test yeni yüzeye uyarlandı.
      i18n `sort.*` en+tr.
- [x] Yüzey: Notlar app bar menüsü · Dosyalar bölümü app bar'ı · proje Files sekmesi.

### OPH-271 — Not ekranında hiçbir şey yüzmez (DESIGN §22a, sıra dışı)

_(Doğdu ve kapandı 2026-08-15 — sahibin OPH-259 ile birlikte istediği düzeltme: "not yazma
ve düzenleme ekranında FAB butonların tamamı görünmez olmalı … hızlı erişim butonu, ekleme
butonu ve AI sohbet butonu". Epic'te planlı değildi; yazmayı zorlaştıran bir şey sıradaki
işi bekleyemez.)_

_**Üç düğme üç ayrı yerden geliyordu** ve bu yüzden tek bir yamayla kapanmıyordu: bölüm
FAB'ı ve AI düğmesi shell'in `Scaffold`'una ait (editör shell dalının İÇİNDE bir rota),
hızlı erişim balonu ise `MaterialApp.builder`'da, yani tüm uygulamanın üstünde._

_**Yanlış mekanizmayı önce denedim, ölçüp bıraktım:** ekranın kendini "belge yüzeyi" ilan
ettiği bir provider yazdım; Riverpod `initState`'ten provider yazmayı **yasaklıyor**
(test birebir bu istisnayı bastı), post-frame'e ertelemek de düğmeleri bir kare
göstermek demekti. Rota zaten bu bilgiyi ilk kareden önce taşıyor — kapı `awIsDocumentRoute`
oldu: shell `GoRouterState` ile, balon router delegate'iyle soruyor (balon Router'ın
ÜSTÜNDE, `GoRouterState.of` orada bir `ModalRoute` istiyor ve bulamıyor)._

- [x] `widgets/document_surface.dart`: `awIsDocumentRoute` (şekil eşleşmesi — dört giriş
      noktası da kapsanıyor, `/edit-note/:id` dahil) + `AwDocumentRouteBuilder` (Router'ın
      üstündeki katmanlar için, delegate `Listenable` olduğundan pollama yok).
- [x] `home_shell._fabBar` belge rotasında `null` dönüyor (bölüm FAB'ı + AI düğmesi birlikte).
- [x] `QuickAccessBubbleHost`'a aynı kapı, mevcut tur/alarm kapılarının yanına.
- [x] Markdown import önizlemesi de kapsandı (§22a U3 — kendi birincil eylemi var).
- [x] Testler (+4): rota predicate'i (dört giriş + beş olumsuz) · nota girince üç kontrolün
      de kaybolduğu ve **geri dönünce döndüğü** · yeni notta ilk kareden itibaren gizli.
- [x] Yüzey: not editörü (dört giriş noktası) + markdown import ekranı.

### OPH-259 — Renk sistemi v2: `AwColorPicker`, son 5 renk, hex diyaloğunun ölümü (DESIGN §33)

_Bulgu #11/#12. "Mevcut seçici kullanışsız" şikâyetinin ölçülen karşılığı: Live modda Quill'in
stok diyaloğu (hex alanlı) açılıyor; md tarafında renk aksiyonu zaten yok; dönüşüm renkleri
sessizce siliyor. Bu task seçiciyi BİZİM yapar ve dört yüzeyi tek bileşene bağlar._

_(✅ 2026-08-16 — **tamamlandı.** Süitler **1196** (+16 toplam), analyze/format/i18n
temiz, `contrast.py` FAILURES: 0 (28 yeni çift). Sahip (a) yolunu seçti.)_

_**Turun tek cümlesi: R4'ün sözü aritmetikle çelişiyor ve bunu planlayan bendim.**
Quill'in `color`/`background` niteliği TEK bir sabit hex saklar; altındaki yüzey (ve
üstündeki mürekkep) temayla değişir. Ölçüm: 18 aday metin renginin **sıfırı** hem
`#FFFFFF` hem `#151F3C` üzerinde 4.5'i geçiyor (ışıkta 5–8, karanlıkta 2–3). Vurgu daha
da kötü: bir dolgunun ışıkta `#0F1B2E`, karanlıkta `#EAF0FD` mürekkebin altında okunur
kalması gerekiyor ve bu iki oranın çarpımı en fazla 21 olduğu için ikisi birden ancak
tek bir orta açıklıkta ~4.6'ya ulaşabiliyor — en iyi aday `#808080` **4.37 / 3.46**
veriyor, yani ikisinde de kalıyor ve zaten kimsenin "vurgu" demeyeceği bir gri.
**Renk ham hex olarak saklanırsa bu söz tutulamaz.**_

_**Sahibin kararı: (a) — semantik id + tema başına çözümleme.** Ve mekanizma paketin
kendi içinde çıktı: `stringToColor` herhangi bir ayrıştırma denemeden ÖNCE
`DefaultStyles.palette` haritasına bakıyor, yani `aw:text-red` adını Quill'in kendisi
çözüyor — renderer'ını çatallamaya gerek yok. Belge adı saklıyor, tema hex'i seçiyor.
Ölçüm sonrası: **14 çiftin 14'ü de iki temada geçiyor** (metin 6.0–9.8, vurgu 7.6–15.3),
28 çift `contrast.py`'ye eklendi ve kapı kasıtlı ihlalle sınandı (1.47 → FAILURES: 1)._

_**Yol boyunca kendi hatam:** markdown→delta yamalarım Python kaçış karakterleri yüzünden
**sessizce düşmüştü** — `replace` hiçbir şey yapmadı, dosya değişmedi. OPH-251'in dersi
birebir tekrarladı; `assert`'lerle yeniden yazıldı. Bir yama, uygulandığını iddia
ediyorsa bunu kanıtlamak zorunda._

- [x] `widgets/color_picker.dart` — `AwColorPicker`: son kullanılanlar satırı (boşsa yok) +
      yüzeyin paleti (`AwColorSwatchDot`) + yüzeye göre "daha fazla"/"renk yok". Satır içi
      bileşen; sheet isteyen yüzey onu sheet'e koyuyor (proje/etiket zaten form içinde).
- [x] MRU `core/recent_colors.dart`: `alliswell_recent_colors`, 8 saklanır 5 gösterilir,
      yeniden seçim yukarı taşır (kopya üretmez), bozuk değer çökme değil hafızasızlık.
      **Yazma tek yerde — bileşenin kendisinde**, yani hiçbir çağıran hatırlamayı unutamaz.
- [x] Üç yüzey taşındı: proje · etiket (kendi `InkWell`+`CircleAvatar`'ı vardı, paylaşılan
      swatch'ı bile kullanmıyordu) · hızlı erişim (10'luk palet aynen, §23 Q8a korunuyor).
      Artık üçü de aynı anatomi ve aynı hafıza.
- [x] **Editör.** Stok renk düğmeleri KAPALI (`showColorButton`/`showBackgroundColorButton`
      — paket ikisini de varsayılan olarak AÇIK bırakıyor, bu yüzden test ikisini de
      çiviliyor); yerlerine iki düğme: metin rengi ve vurgu. İkisi de `AwColorPicker`
      açıyor, yazdıkları şey **ad** (`aw:text-red`), ve editör
      `DefaultStyles(palette: awNoteColorPalette(brightness))` ile o adı temaya çözüyor.
      Paletler `data/note_colors.dart`'ta; 8 metin + 6 vurgu, hepsi kapıda.
- [x] Markdown modu: `highlight` aksiyonu (`==…==`) eklendi — renderer'ın OPH-247'den beri
      çizdiği işaret, ve yapısı gereği tema-güvenli. Metin rengi markdown'a girmiyor
      (GFM'de yok — §33 R6, yazılı sebep).
- [x] Dönüşüm dürüstlüğü: delta→markdown vurguyu `==…==` olarak taşıyor, markdown→delta
      onu varsayılan vurgu ADIYLA geri getiriyor — yani round-trip'te kayboluyor değil.
      Metin rengi GFM'de yok, düşüyor ve dönüşüm diyaloğu bunu önceden söylüyor.
- [x] Testler (+16 toplam): semantik renkler (tema başına çözümleme, palet bütünlüğü, ad tekilliği, bize ait olmayan değer, vurgu round-trip, stok düğmelerin kapalılığı — 8) · MRU (sıra/tekilleştirme/tavan/restart/bozuk değer/kesişim, 7) ·
      çapraz-yüzey hafıza (bir yüzeyde seçilen renk diğerinde "son kullanılanlar"da çıkıyor) ·
      üç yüzeyin mevcut testleri yeşil. i18n `color.*` en+tr.
- [x] Yüzey (bu turda): proje · etiket · hızlı erişim renk seçicileri.
- [x] Yüzey (kalan): editör araç çubuğu — iki yeni düğme.

### OPH-272 — Sahibin üç düzeltmesi: dışa aktarma nerede, ikon nerede, yıldız nerede (sıra dışı)

_(Doğdu ve kapandı 2026-08-16 — epic dışı, sahibin doğrudan raporu. v1.5.0 ile sevk edildi.)_

_**Teşhis önce ölçüldü, sonra düzeltildi — ve ilk madde "eksik özellik" DEĞİLDİ.** Telefon
genişliğinde bir teşhis testi üçünü de yerinde buldu: `notes-open-markdown` 294–342 px'de
ve ikonu mevcut, editörün `note-quick-menu`'sü 342–390'da ve **PDF öğesi menünün içinde**.
Yani kod doğruydu; arıza ULAŞILABİLİRLİKTE. §22'nin tanıdık yüzü: "menüde var" ile
"insan bulabiliyor" ayrı cümleler._

- [x] **PDF dışa aktarma bulunabilir oldu.** Sahibin cümlesi birebir yol gösterdi —
      "arşivle sil vs işlemlerinin orda" — ve orası **satır menüsü**. Export oraya kondu
      (`note-row-export-<id>`); satır gövdeyi taşımadığı için not önce replikadan okunuyor
      (`watchDetail(...).first`). Editörün taşma menüsünün ipucu da düzeltildi: "Hızlı
      işlemler" diyordu, artık "Not işlemleri" — kısayol değil, notun kendi eylemleri.
- [x] **Markdown menüsünün ikonu.** Sahibin cihazında hiç çizilmiyor (ipucu çıkıyor, düğme
      belli değil). **Üretilemedi** ve kod noktası teorisi de çürüdü: yanındaki ayarlar
      ikonu aynı 0xf… varyant bloğunda (0xf36e) ve sorunsuz çiziliyor. Tahmin sevk etmek
      yerine o tek glyph'e olan bağımlılık kaldırıldı — `folder_open_outlined` (0xf090)
      yerine klasik kod noktalı kardeşi `folder_open` (0xe2a4).
- [x] **Yıldızlı notlar listenin başında.** Sıralama ne olursa olsun önce yıldızlılar
      gruplanıyor, grup İÇİNDE seçilen sıra aynen işliyor. **DESIGN §34 L5 bunun TERSİNİ
      söylüyordu ve yanlıştı** — sabitleme "bunu gözümün önünde tut" demenin yolu, onu
      gömebilen bir sıra yıldızı süse çevirir. Kural sahibin kararıyla ters çevrildi ve
      gerekçesi yazıldı.
- [x] Testler (+3): üç sıralama seçeneğinde de yıldızlının başa geçtiği · grup içinde
      sıranın korunduğu · satır menüsünde export öğesinin bulunduğu.

### OPH-260 — Gelişmiş ayarlar: 19 satırlık düz liste → 6 gruplu IA (DESIGN §32)

_Bulgu #14. Envanterin tamamı planlama raporunda satır satır çıkarıldı (19 satır, sıra ve
key'lerle); bu task YENİ HİÇBİR AYAR EKLEMEDEN yeniden ev kurar (S5)._

_(✅ 2026-08-17 — Süitler **1204** (+5), analyze/format/i18n temiz, `contrast.py`
FAILURES: 0.)_

_**Turun tek cümlesi: bir yeniden ev kurmanın riski yanlış görünmek değil, bir satırın
hiçbir yere varmaması.** Bu yüzden taşın kendisinden çok SAYIM testi yazıldı: her satır,
zaten sahip olduğu key'le, yeni sayfalardan tam birinde bulunuyor. §22'nin en yalın hâli
— ulaşılamayan bir ayar, ayar değildir._

_**Ölçülen yan etki:** mevcut beş süit kökten doğrudan satırlara gidiyordu ve hiyerarşi
bir seviye derinleştiği için `pageBack()` sayıları da kaydı. Testleri tek tek yamamak
yerine ortak `openSettingsGroup(...)` yardımcısı yazıldı — bir sonraki gruplama tek
düzenleme olsun diye. `completed_screen_test`'in "ayarlar büyüyor, satıra kaydırarak git"
numarası da gereksizleşti ve silindi: grup sayfası kısa._

- [x] Kök artık bir INDEX: hesap başlığı (→ `/settings/account`) + dört grup satırı
      (Genel · Bildirimler & Alarmlar · Entegrasyonlar · Veri) + About satırı (diyalog
      olarak kaldı — içinde ayar yok, bir ekran dolusu bilgi var) + sign-out kartı (S4).
      Grup satırları ikon + ad + **ne içerdiğini sayan** alt başlık (S1).
- [x] Beş yeni rota mevcut desende: `/settings/account`, `/general`, `/notifications`,
      `/integrations`, `/data`. Mevcut beş derin rota AYNEN duruyor ve grup sayfalarından
      bağlanıyor (S3) — bir ayar URL'i dün çalışıyorduysa bugün de çalışıyor (testli).
- [x] Dağılım §32 S2'deki gibi; `_AlarmStatusTile`, `ServerUrlTile`, takvim kartları,
      `AiSettingsCard` widget olarak taşındı, **key'ler ve i18n anahtarları değişmedi**.
      Ortak `_SettingsPage` kabuğu çıkarıldı ki beş sayfa kendi düzenini uydurmasın (S6).
- [x] `/settings/integrations` OPH-265'in "API erişimi" satırına yer bırakıyor — bu turda
      satır YOK (S5, satır icat edilmedi; tema anahtarı da yok, çünkü `themeMode` sabit).
- [x] Testler (+5): kökün beş yeri adlandırdığı ve sign-out'u tuttuğu · **sayım** (11 satır
      key'iyle, ait olduğu grupta) · Hesap'ta sunucu + hesap silme · Entegrasyonlar'da
      takvim · derin rotanın hâlâ açıldığı. Beş mevcut süit yeni gezinmeye uyarlandı.
      i18n `settings.group.*` en+tr.
- [x] Yüzey: Ayarlar kökü + 5 yeni alt sayfa; hiçbir mevcut satır kaybolmadı.

### OPH-273 — Canlıdaki tarayıcı bir yıl boyunca eski uygulamayı çalıştırıyordu (ACİL, sıra dışı)

_(Doğdu ve kapandı 2026-08-17 — sahibin raporu: "deploy çalıştı ama canlıda sıralama hâlâ yok,
bazı özellikler hâlâ yok".)_

_**Rapor haklıydı ve sebep uygulamada değil, sunucu başlıklarındaydı.** Önce üründen ölçüldü:
`/app/version.json` **1.5.0** diyor ve deploy edilen `assets/assets/i18n/tr.json` yeni
`sort` bloğunu ("Sıralama", "Ters çevir", "Düzenlenme") **taşıyor** — yani sunucudaki paket
doğru. Sonra başlıklar ölçüldü ve arıza oradaydı:_

| Dosya | Politika | Doğru mu |
| --- | --- | --- |
| `index.html` | `no-cache, no-store, must-revalidate` | ✓ |
| `flutter_service_worker.js` | `no-cache, no-store, must-revalidate` | ✓ |
| **`main.dart.js`** | **`public, max-age=31536000, immutable`** | ✗ |
| **`flutter_bootstrap.js`** | **`public, max-age=31536000, immutable`** | ✗ |
| `version.json`, `assets/**` | başlık yok (tarayıcı sezgisi) | zayıf |

_**Kök neden depodaydı ve yorumu yanlış bir önerme yazıyordu:** `apps/landing/public/.htaccess`
`.js` uzantılı her şeyi bir yıllığına `immutable` işaretliyor ve "Hashed build assets are
immutable" diyor. Bu pazarlama paketi (Vite, `index-A1b2C3d4.js`) için DOĞRU, Flutter için
YANLIŞ: `main.dart.js`, `flutter_bootstrap.js` ve `assets/` altındaki her dosya build'den
build'e **aynı adı** taşır, yalnız içerikleri değişir. Sonuç, kullanıcının gördüğü şeyin
birebir kendisi: taze index.html, taze service worker, **bir yıllık uygulama kodu**._

_**Ders (§22'nin altyapı kardeşi): "deploy başarılı" ile "kullanıcı yeni kodu çalıştırıyor"
ayrı cümleler.** Deploy doğrulamam `version.json` ve JSON-LD okuyordu — ikisi de o
`immutable` kuralının dışında kaldığı için ikisi de doğruyu söylüyordu. Doğrulama, ürünün
kullanıcıya ULAŞAN katmanını ölçmediği sürece yeşil yanabilir._

- [x] `.htaccess`: `/app/` altındaki her şey `no-cache, must-revalidate` (`<If>` bloğu,
      `<FilesMatch>`'ten sonra merge edildiği için uzantıdan bağımsız kazanır). Pazarlama
      paketinin hash'li varlıkları immutable kalıyor — orada önerme gerçekten doğru.
- [x] `docker/web-nginx.conf`: aynı yanlış önerme kendi barındıranları da vuruyordu; aynı
      şekilde revalidate'e çevrildi (ETag varken değişmeyen dosya 304 döner, maliyet bu).
- [x] Deploy sonrası başlıklar ÜRÜNDEN yeniden ölçüldü (aşağıdaki Run Log satırı).
- [x] Deploy sonrası ÜRÜNDEN ölçüldü (v1.6.0, 2026-08-17) ve **origin düzeldiği kanıtlandı**:
      `version.json` ve `assets/**` artık `no-cache, must-revalidate` dönüyor (`cf-cache-status:
      DYNAMIC` — Cloudflare bunları önbelleklemiyor, yani gördüğümüz doğrudan origin'in
      politikası). `main.dart.js`'in `last-modified`'ı yeni deploy'un damgası.
- [ ] **AÇIK — Cloudflare kenarı, ve düzeltmesi panelde (agent'ın erişimi yok).** Ölçüm:
      | Dosya | Cache-Control | cf-cache-status |
      | --- | --- | --- |
      | `version.json` | `no-cache, must-revalidate` | DYNAMIC (origin'e geçiyor) |
      | `main.dart.js` | **`max-age=14400, must-revalidate`** | EXPIRED (içerik YENİ) |
      | `flutter_bootstrap.js` | **`public, max-age=31536000, immutable`** | **HIT, age 445** |
      İki ayrı Cloudflare davranışı: (1) `.js` CF'nin varsayılan önbelleklenen tipleri
      arasında olduğu için tarayıcı TTL'ini kendi **4 saatine** yeniden yazıyor — origin ne
      derse desin; (2) `flutter_bootstrap.js` kenarda **eski, yıllık-immutable** kopyasıyla
      duruyor (`last-modified` dünkü deploy). **Sahibin yapması gerekenler:** `/app/*` için
      cache **purge**, ve kalıcı çözüm olarak Browser Cache TTL → *Respect Existing Headers*
      ya da `alliswell.space/app/*` için bypass eden bir Cache Rule.
      _Not: purge yapılmasa bile durum yıldan 4 saate indi ve servis edilen kod yeni._

### OPH-261 — Domain katmanı çıkarımı + not dürüstlük onarımları (MCP/API'nin ön koşulu)

_Bulgu #6/#7. ADR-0022 K4: MCP domain katmanını çağırır, ham SQL'i değil — ama notes/projects/
tags mantığı bugün route içinde. Bu task REST davranışını DEĞİŞTİRMEDEN çıkarımı yapar ve iki
ölçülmüş yalanı düzeltir._

_(✅ 2026-08-17 — **tamamlandı: üç onarım + çıkarım.** API süiti **632** (+12),
lint/format temiz. Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: üç ayrı arıza da tek bir şeklin tekrarıydı** — kod ADR-0028'in iki
kanonik biçimini BİR yerde biliyor, diğerlerinde bilmiyordu. `plain_text` yalnız delta
dalında yazılıyordu; export delta'yı varsa her zaman tercih ediyordu; `note_tags` tablosu
ilk migration'dan beri duruyor ve ne yazılabiliyor ne okunabiliyordu._

_**Yazarken bulduğum kendi açığım:** `tagIds`'i serileştirmeye eklediğimde sync PULL da aynı
fonksiyonu çağırdığı için her snapshot `tagIds: []` demeye başlamıştı — yani bir yalanı
kapatırken yenisini açıyordum. Pull artık etiketleri de yüklüyor (link'ler nasıl
yükleniyorsa öyle). Etiketler not PUSH protokolüne girmiyor; bu bilinçli ve yazılı sınır._

- [x] **Çıkarım YAPILDI** (2026-08-17, ikinci tur). `src/db/notes.js` (270 satır:
      `loadNote`, `noteRelations`, `assertProjectUsable`, `toRowPatch`, `createNote`,
      **`createNoteFromTask`**, `updateNote`, `setNoteTags`, `exportNoteMarkdown`,
      `parseDelta`) · `src/db/projects.js` (101: `loadProject`, `assertReadmeNoteUsable`,
      `listProjects`, **`openTaskCounts`** batched, `createProject`, `updateProject`) ·
      `src/db/tags.js` (85: `loadTag`, slug kuralları — ön kontrol + index yarışı birlikte —,
      `listTags`, `createTag`). Route dosyaları delege ediyor; `routes/notes.js` 862 → 655
      satır. **Kanıt: 632 testin hiçbiri değişmeden yeşil** — "aynı davranış, yeni ev"
      sözleşmesi tam olarak budur.
      _`createNoteFromTask` ayrı bir fonksiyon: bağlantı süs değil, işlemin kendisi
      ("bu görevi nota çevir"), ve OPH-263'ün `create_note(taskId:)` aracının ikinci
      çağıranı olacak._
      _Bilinçli olarak taşınmayan: projenin **arşiv kaskadı**. Görevlere ve notlara uzanıyor
      ve kendi onay semantiği var; taşınması bu turun "aynı davranış" sözleşmesinden daha
      büyük bir soru. Sessizce atlanmadı, yazıldı._
- [x] **Onarım 1 (`plain_text`) — ÖLÇÜLDÜ ve kapandı.** `toRowPatch` (`notes.js:161-180` → yeni `db/notes.js`)
      markdown-canonical yazımda `plain_text`'i markdown'dan türetir (yeni `markdownToPlainText`
      — sunucuda md ayrıştırıcıya gerek yok: satır bazlı sözdizimi soyma yeterli, test
      fixture'larıyla). Sync tarafındaki ikiz üretici (`sync.js:535-539`) AYNI yardımcıyı
      kullanır. Kanıt: markdown-canonical not `?q=` ve MCP `search`/`get_note`'ta bulunur
      (bugün bulunmuyor — bulgu #6). Mevcut satırlar için tek seferlik backfill migration'ı
      (yalnız `content_format='markdown'` VE `plain_text` boş/bayat olanlar).
- [x] **Onarım 2 (export) — kapandı.** `exportNoteMarkdown` `content_format`'a saygı duyar —
      markdown-canonical notta `content_markdown` kanonik kaynaktır (bugün delta-öncelikli,
      `notes.js:380-382`).
- [x] **Onarım 3 (`note_tags`) — kapandı.** tablo ilk günden var, REST ucu hiç olmadı. `PUT
      /api/v1/notes/:noteId/tags` (replace-set — `tasks.js:647` emsali) + not
      serileştirmesine `tagIds` eklenir; sync `NOTE_FIELDS`'e girmez (bilinçli: v1'de etiket
      not-sync'ine dahil değil, yazılı sınır — pull serializer'ı zaten links'i taşıyor,
      tagIds de aynı yoldan okunur).
- [x] Testler (+12, süit 620 → **632**): `markdownToPlainText` fixture'ları (bağlantı
      etiketi kalır hedefi gider, görsel ve kod bloğu düşer, junk çökmez) · markdown notun
      create/update'te `plain_text` türettiği ve **`?q=` ile bulunduğu** · delta notun hâlâ
      delta'dan türettiği (asıl bekçi) · export'un kanonik alana uyduğu, iki yönde de ·
      etiket replace-set'i ve başka workspace'in etiketini reddettiği. Eski süitler:
      yeni: plain_text markdown üretimi (fixture'lı), export format-saygısı, note-tags ucu,
      backfill migration'ı. `npm run lint` + format.

### OPH-262 — MCP genişleme 1. dalga: görev yazma araçları + `recordMcpAction`

_Bulgu #7/#8. ADR-0022'nin kendi cümlesi genişlemeye izin veriyor: "v1.5 write tools slot into
the same dispatch + annotation + audit path; `delete_*` never does."_

_(✅ 2026-08-17 — **tamamlandı.** Yüzey 7 → **13 araç**. API süiti **646** (+14),
lint/format/check:no-ts temiz; entegrasyon süiti bu makinede KOŞULAMADI (konteyner çalışma
zamanı yok) — CI kapısı. Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: yeni araç yazmak işin küçük yarısıydı; büyük yarısı araçların
konuşacağı domain katmanını var etmekti.** ADR-0022 §4 "MCP ham SQL değil domain
çağırır" diyor ama OPH-218 yalnız create/complete/detail'i çıkarmıştı — PATCH, snooze,
checklist, acknowledge hâlâ route closure'larının içindeydi. Yani altı yeni aracın önünde
iki seçenek vardı: mantığı kopyalamak ya da katmanın yanından uzanmak. İkisi de yasak._

- [x] **`lib/mcp/actions.js` doğdu.** `findMcpReplay()` (yazımdan ÖNCE `mcp_mutations`
      replay kontrolü) + `recordMcpAction()` (yazımdan SONRA `ai_action_log(source='mcp')`
      + idempotency satırı, `ER_DUP_ENTRY` yutulur). "Ledger LAST" sırası ve gerekçesi
      artık modülün başında yazılı, iki handler'a kopyalanmış hâlde değil.
      `create_task`/`complete_task` buna taşındı — **davranışları değişmedi, o iki testin
      tek satırı bile değişmedi.**
- [x] **Domain çıkarımı (asıl iş).** `db/tasks.js`: `updateTask` (arşiv kuralı + assert'ler
      + urgent→acknowledgement varsayılanı + completionPatch + reconcileTaskReminder +
      `propagateSeriesScope` aynı transaction'da), `reopenTask`, `snoozeTask` (preset
      matematiği + canlı alarmların susturulması), `setTaskTags` (OPH-261'in `setNoteTags`
      ikizi), `loadChecklistItem`/`addChecklistItem`/`updateChecklistItem`;
      `db/reminders.js`: `loadReminder` + `acknowledgeReminder`. `TASK_STATUSES`/
      `TASK_PRIORITIES`/`SNOOZE_PRESETS` de domain'e indi (lib → routes importu ters
      bağımlılık olurdu; `lib/ai/schema.js` bunu zaten yazıyor), route re-export ediyor.
      **Kanıt: çıkarımdan sonra 632 testin hiçbiri değişmeden yeşil kaldı** — sonra araçlar
      yazıldı.
- [x] Yeni araçlar (hepsi: annotation dörtlüsü + `requireScope('mcp:write')` + Ajv +
      workspace-scope + `recordMcpAction` + DATA_NOTE):
      **`update_task`** (MCP-güvenli alt küme: `title`, `description`, `status`, `priority`,
      `dueAt`, `remindAt`, `startAt`, `isUrgent`, `requiresAcknowledgement`, `projectName`
      — id değil, belirsizse aday listesiyle RED K5 —, `tags[]` replace-set/yalnız var olana
      çözülür, `timezone`), **`reopen_task`**, **`snooze_task`** (`oneOf` preset|snoozeUntil,
      REST'le birebir), **`add_checklist_item`** (idempotencyKey'li), **`set_checklist_item`**,
      **`acknowledge_reminder`**.
      _Bilinçli dışarıda: `parentTaskId`/`sortOrder` (yapı insan hareketidir), `colorRgb`
      (UI kararı), `calendarMirrorEnabled`/`alarmsMutedAt` (cihaz anahtarları) ve
      `seriesScope` — bir seri düzenlemesinin diğer günlere uzanması uygulamanın kapsam
      sorusunu ister, modelin tahminini değil._
- [x] **Beklenmedik bulgu — `acknowledge_reminder` ULAŞILAMAZ doğuyordu:** hiçbir okuma
      aracı bir alarm id'si vermiyordu, yani araç yazılır ama çağrılamazdı (DESIGN §22).
      `get_task` artık görevin alarmlarını da veriyor (id/kind/status/remindAt/snoozedUntil/
      requiresAcknowledgement — metin yok, yalnız metadata). Testi de böyle yazıldı: id
      tablodan değil **okuma aracının çıktısından** alınıyor.
- [x] **İkinci bulgu — kendi açtığım kapı:** etiket-yalnız bir `update_task` çağrısı
      `updateTask`'e uğramadığı için ARŞİV kuralını atlıyordu (REST'in `PUT /tags` ucu
      reddederken MCP arşivli görevin etiketlerini yeniden yazabiliyordu). Kural route'tan
      `setTaskTags`'in içine indi + testi yazıldı. _Bir kural, onu atlayan ikinci yol
      çıktığı anda yanlış yerde durduğunu söyler._
- [x] **Domain reddi artık modelin okuyabildiği bir kod.** Domain katmanı HTTP terimleriyle
      reddediyor (`coded()` + sensible), çünkü REST onun diğer çağıranı. `routes/mcp.js`
      dispatch'i 4xx + stabil `code` taşıyan hatayı tool sonucuna çeviriyor (`TASK_ARCHIVED`,
      `TASK_INVALID_TRANSITION`, `TASK_SNOOZE_IN_PAST`…); 5xx opak kalıyor — iç arıza modelin
      düzelteceği şey değil.
- [x] Red-team: `mcp-injection.test.js` yazma dalgasını düşman korpusla çağırıyor
      (`update_task` her başlık vakasıyla, `add_checklist_item`), `tableSnapshot()`
      checklist/ticked/reminders/snoozed/tagLinks ile genişledi; **tek delta istenen satır**.
      Her alanı düşman olan bir görevin okunması da inert (SECURITY.md:89-90 sözleşmesi).
- [x] Unit testler (+14, süit 632 → **646**): mutlu yol (revision + reconcile + tag
      replace-set + ledger) · belirsiz proje reddinin TOTAL olduğu (istenen başlık da
      yazılmaz) · idempotency replay · boş çağrı, arşivli görev ve arşivli etiket yazımı
      kod döndürür ·
      reopen/snooze geçiş kuralları · checklist ekle-replay-tikle + yabancı madde NOT_FOUND ·
      acknowledge idempotent · **her yazma aracı read-only token'ı reddeder** (tablo bazlı) ·
      **her yazma aracı başka workspace'in id'sine NOT_FOUND der ve hiçbir satırı oynatmaz**.
      Kapı doğrulaması: `snooze_task`'ten `requireScope` kasten silindi → süit yakaladı
      (`expected 'NOT_FOUND' to be 'MCP_SCOPE_REQUIRED'`) → geri alındı.
      `mcp-protocol.test.js`'in yüzey listesi 13 araca güncellendi + yazma araçlarının
      annotation dörtlüsünün TAM olduğu iddiası eklendi (eksik hint "false" değil
      "bilinmiyor" demektir — host sessizce çalıştırabilir).
- [x] `docs/MCP.md` tablosu bu dalganın araçlarıyla güncellendi ("Seven tools" → thirteen;
      "no delete tool, by design" cümlesi KALDI), `docs/AI.md` §8 K5'in eski "v1.5 may add"
      cümlesi gerçekle değiştirildi, `routes/mcp.js` `instructions` metni yeni yüzeyi
      söylüyor. ADR-0022 amendment'ı bilinçle OPH-263'e bırakıldı (yüzey tam olduğunda tek
      not; ADR'nin kendi Consequences cümlesi bu dalgaya zaten izin veriyor).
      **Kural 12'nin REST yarısı:** yeni bir kullanıcı yeteneği eklenmedi — altı aracın
      altısının da REST karşılığı zaten vardı (`PATCH /tasks/:id`, `/reopen`, `/snooze`,
      `/checklist`, `PATCH /checklist/:itemId`, `/reminders/:id/acknowledge`), yani
      backfill edilecek uç yok; `docs/API.md` OPH-265'te doğacak.

### OPH-263 — MCP genişleme 2. dalga: not/proje/etiket araçları, listeler, dokümantasyon

_Sahibin cümlesi birebir: "not olusturma yok … not ekleme notu taska baglama … proje yonetimi
not olusturma ayrica task bagimsiz not ekleme yapilabilmesi lazim." Bu dalga onu kapatır._

_(✅ 2026-08-17 — **kod TAMAM**, yüzey **13 → 24 araç** + 3. kaynak. API süiti **658** (+12),
lint/format/check:no-ts temiz. **İki doğrulama BLOKE:** entegrasyon süiti ve MCP Inspector
koşusu — ikisi de MySQL/Redis ister, bu makinede konteyner çalışma zamanı yok. Deploy alınmadı,
sahibin talimatı.)_

_**Turun tek cümlesi: yazma yüzeyi genişledikçe iş "ne ekleyeyim"den "neyi eklememeliyim"e
döndü.** Üç sınır bilinçle çizildi ve üçü de dokümana yazıldı: delta-kanonik notun gövdesi
MCP'den EZİLEMEZ (ADR-0028 §1 — sessiz dönüştürme kullanıcının yazdığı biçimlendirmeyi atardı),
proje ARŞİVLEME uygulamada kalır (kaskad görevlere ve notlara uzanıyor), dosya baytları hiç
geçmez._

- [x] Araçlar (11 yeni): **`create_note`** (markdown-canonical doğar; `projectName` fold-eşleşme
      K5; `taskId?` verilirse bağlantı **aynı transaction'da** — `createNote` artık `links`
      alıyor, "task bağımsız not" da "göreve bağlı not" da tek araç), **`update_note`**,
      **`link_note`** / **`unlink_note`** (`entityType: task|project`; unlink yoksa dürüstçe
      `LINK_NOT_FOUND` döner, hata değil), **`list_notes`** (proje/görev/arşiv/pin filtreleri,
      gövde DEĞİL 200 karakterlik özet), **`create_project`** / **`update_project`**
      (name/description/status/dueAt; renk/ikon YOK), **`list_projects`** (açık görev
      sayılarıyla), **`list_tags`**, **`create_tag`**, **`list_files`** (metadata-only).
      Okuma araçları `readOnlyHint: true` + K7 tavanları (`limitSchema`/`page` ortak).
- [x] **Domain çıkarımı:** not bağlantıları da route closure'ından indi —
      `db/notes.js`'e `NOTE_LINK_TABLES`, `assertLinkTarget`, `findNoteLink`, `linkNote`,
      `unlinkNote` + `createNote(links)`; `PROJECT_STATUSES` domain'e taşındı (route
      re-export). **Kanıt: çıkarımdan sonra 646 test dokunulmadan yeşil**, sonra araçlar yazıldı.
- [x] `get_task` bağlı notları (link + `created_from_task_id`, RELATION_CAP), `get_note`
      etiketleri ve `linkedTo`yu (hedefin ADIYLA) taşıyor — "her alanın görülebilmesi".
- [x] Resources: `alliswell://views/inbox` eklendi. **Spec'ten bilinçli sapma:** planlama
      metni "planlama statüleri" diyordu, ama ürünün Inbox'ı `status='inbox'` (triyaj
      edilmemiş yakalamalar; Home onları OPH-107'den beri DIŞLIYOR). Planlama statüleri
      seçilseydi "Inbox" adı altında Home listesi servis edilecekti. Saf builder
      `queryInbox` olarak `TASK_VIEW_QUERIES`'e girdi, route'a değil.
- [x] **Beklenmedik bulgu — `openTaskCounts` bugüne kadar BİR KEZ ÇALIŞMAMIŞ.** OPH-261'de
      "batched" diye çıkarılmıştı ama hiçbir çağıranı yoktu; `list_projects` onu ilk kez
      çağırdığında `groupBy`+`count` zincirinin birim test ikizinde çalıştırılamadığı ortaya
      çıktı (fakedb'de `groupBy` yok, üstelik gerçek zincir `select`'ten sonra da chainable
      builder ister). Tek sorgu + JS'te tally'ye çevrildi; artık hem koşuyor hem test ediliyor.
      _Ders yine aynı yerden: çağıranı olmayan kod, çalıştığı sanılan koddur._
- [x] Dokümantasyon: `docs/MCP.md` tam tablo (24 araç, iki gruba ayrıldı; "no delete tool —
      by design" KALDI + "bilinçli sınırlar" bölümü kullanıcı diliyle yazıldı), **ADR-0022
      amendment'ı** (yüzey 7 → 24, dört madde: K4 artık her fiil için doğru, domain reddi
      modele ulaşıyor, iki sınır karardır, delete değişmedi), `docs/AI.md` §8 K5,
      `docs/ARCHITECTURE.md` §6d, CHANGELOG. README'de araç sayısı geçmiyor (kontrol edildi).
- [x] Red-team: model TARAFINDAN yazılan not da korpustan geçiyor (fence-escape başlık,
      exfil-url gövde) — verbatim saklanıyor, hiçbir şey izlemiyor; `tableSnapshot()`
      note_links/projects/tags/archivedNotes ile genişledi, tek delta istenen not.
- [x] Unit testler (+12, süit 646 → **658**): aynı yazımda bağlanan not + `get_task`/
      `list_notes` iki yönlü ulaşılabilirlik · bilinmeyen proje HİÇBİR ŞEY yaratmaz + replay ·
      **rich-text notun gövde reddi ve deltasının bozulmadığı** · markdown notun gövdesi
      değişince `plain_text`in takip ettiği (ve `?q=`/search'ün bulduğu) · link/unlink dürüst
      ikili + `NOTE_LINK_EXISTS` · proje açık-görev sayımı (tamamlanan sayılmaz) · arşiv reddi ·
      etiket tekilliği + listenin verdiği adın `update_task`'te çözüldüğü · dosya listesinde
      **URL/anahtar olmadığının** iddia edilmesi · scope tablosu 15 yazma aracına çıktı ·
      not/proje araçları için çapraz-workspace NOT_FOUND + boş listeler.
- [x] **`test/integration/mcp.test.js` genişletmesi — KOŞTU (2026-08-17m).** Konteyner çalışma
      zamanı bu oturumda kuruldu (colima 0.10.3 + Docker 29.7.2); dosya 2 → **6 test**. Gerçek
      MySQL'in çürütebileceği dört şey: **Türkçe fold'un app-owned olduğu** (aşağıdaki bulgu),
      tek dansta proje→görev→not çapraz ulaşılabilirliği + `NOTE_LINK_EXISTS`'in ikinci satır
      YARATMADIĞI, MCP not/proje yazımlarının `/sync/pull`'a düştüğü (eskiden yalnız görev),
      `list_files`'ın storage anahtarını da URL'i de vermediği (AI.md §7).
- [x] **Bulgu — "MySQL ı→i katlıyor mu?" sorusunu YANLIŞ ölçmenin kolay yolu.** Fold testini
      yazarken önce premise'i ölçtüm ve ADR-0013 §3'ü çürütür göründü. Kök neden ölçüm
      aracındaydı: **dizge sabitleri kolonun değil BAĞLANTININ collation'ını alır**, mysql2'nin
      varsayılan bağlantı collation'ı ise `utf8mb4_general_ci` — o da ı=i yapıyor.
      Ölçüm: `@@collation_connection = utf8mb4_general_ci`, `@@collation_database =
      utf8mb4_0900_ai_ci`; `('ışık'='isik')` → **1**, ama `COLLATE utf8mb4_0900_ai_ci` ile
      zorlanınca → **0**. Kolon üzerinden (yani uygulamanın gerçekten ürettiği sorgu biçimi)
      `title LIKE '%isik%'` → 0 ve `MATCH(title, plain_text) AGAINST('sigir*')` → 0.
      **ADR-0013 §3 doğru, düzeltme gerekmiyor**; yanlış olan sabit-sabit probe'uydu — bu yüzden
      test artık premise'i KOLON üzerinden ölçüyor ve tuzağı yorumda adıyla yazıyor.
      (İkinci tuzak: `docker compose exec mysql` CLI'ı da utf8mb4 olmayan bir bağlantı kuruyor,
      yani oradan yapılan Türkçe ölçüm de güvenilmez.)
- [ ] **BLOKE — MCP Inspector elle koşusu** (ADR-0022'nin uyum kanaryası): ayakta bir API +
      tarayıcıdan OAuth onayı ister. Altyapı artık hazır (DB ayakta), **kalan tek engel canlı
      sunucu başlatmak** — 2026-08-17m oturumunda sahip başlatmayı istemedi. Protokol dansının
      kendisi entegrasyonda koşuyor; Inspector'ın eklediği şey resmî istemciyle uyum kanıtı.

### OPH-264 — API anahtarları sunucu tarafı: ADR-0032 + `api_keys` + çift-modlu kimlik

_Bulgu #9. Issue #3'ün gövdesi: "Allow user to create API keys and expose REST API to
applications." Karar #3/#4 çerçeveyi çizdi; ADR-0032 bu task'ın İLK işi olarak yazılır
(tehdit modeli, scope'suz v1, workspace bağı, MCP/anahtar güven ayrımı, hash mirası)._

_(✅ 2026-08-17 — **kod TAMAM.** ADR-0032 yazıldı, `api_keys` migration'ı, çift-modlu
`authenticate`, üç kapı, yönetim uçları, anahtar-başına rate limit. API süiti **669** (+11),
lint/format/check:no-ts temiz. **İki doğrulama BLOKE:** migration `db:migrate` ile ve
entegrasyon süiti KOŞULAMADI — konteyner çalışma zamanı yok. Deploy alınmadı.)_

_**Turun tek cümlesi: bu task'ın riski yeni uçlarda değil, TEK bir fonksiyonun ikiye
çatallanmasındaydı.** `authenticate` artık ~80 rotanın hepsinde `request.user`'ı belirleyen
çatallı fonksiyon; o yüzden JWT dalı bit değişmeden bırakıldı ve **mevcut 658 testin
tamamı regresyon kanıtı olarak koşuldu.**_

- [x] **ADR-0032 yazıldı (task'ın İLK işi):** OAuth'suz düz Bearer + neden MCP'nin OAuth'u
      yeniden kullanılmadığı (cron job'ın onaylayacağı tarayıcısı yok), hash-only saklama,
      **v1'de scope YOK** gerekçesiyle (kimsenin istemediği bir izin modeli icat etmek —
      yarım uygulanmışı hiç olmamasından kötü), workspace bağı = patlama yarıçapı, dört
      alternatif (client-credentials, JWT anahtar, scope'lu v1, hesap-bazlı anahtar) ve
      sonuçları.
- [x] Migration `20260817140000_create_api_keys`: char(26) id/user_id/workspace_id, name(100),
      `key_hash` char(64) UNIQUE, `key_prefix`(16), `expires_at`/`revoked_at`/`last_used_at`
      NULL, FK'ler CASCADE. **`deleted_at` YOK — bilinçli:** iptal kalıcıdır ve iptal edilmiş
      satır kanıt olarak kalır; digest'i tekil kaldığı için aynı sır bir daha kaydedilemez.
- [x] Üretim: `lib/api-keys.js` (`newApiKey` = `awk_` + `newOpaqueToken(32)`, `apiKeyPrefixOf`,
      `bearerApiKey`, `apiKeyRateBucket`). **Spec'ten küçük sapma, gerekçesi yazıldı:** saklama
      `hashMcpToken('api_key', …)` değil, `tokens.js`'e eklenen `hashApiKey` (`api-key:`
      ayrıştırıcısı) — aynı desen, aynı dosya, aynı sır; ama API anahtarı MCP token'ı değildir
      ve `mcp-api_key:` ayrıştırıcısı her gelecekteki okuyucuya yanlış bir şey söylerdi.
- [x] `authenticate` çift-modlu: `awk_` öneki modu İŞ YAPILMADAN önce belirler (anahtar hiç
      `jwtVerify`'a girmez, JWT hiç hash'lenmez); revoked/expired/silinmiş-hesap için ayrı
      kodlar ama hepsi aynı 401 şekli; `last_used_at` ~1 dk throttled ve fire-and-forget.
      `requireWorkspaceMember` anahtarın workspace'ini üyelikten ÖNCE kontrol eder — sahip o
      diğer workspace'in gerçek üyesi olabilir, anahtarın yine işi yok (`AUTH_APIKEY_WORKSPACE`).
- [x] Kapılar (`app.rejectApiKeys` preHandler'ı — `onRequest` DEĞİL, `authenticate`'ten SONRA
      koşmak zorunda): `DELETE /me` + `/me/deletion/cancel`, anahtar yönetim uçlarının üçü, ve
      **`/ai/*`'ın tamamı** — tek tek rotalara değil, `routes/ai.js`'in kendi kapsamına
      eklenen plugin-seviyesi hook'la, böylece yeni bir /ai rotası kapıyı unutamaz.
- [x] Yönetim uçları (JWT-only): `GET/POST /workspaces/:id/api-keys`, `POST
      /api-keys/:keyId/revoke`. Sır yalnız 201 gövdesinde. Başkasının anahtarı 403 değil
      **404** (API'nin başkalarının satırları hakkındaki kuralı); iptal idempotent ve İLK
      damgayı korur ("ne zaman çalışmayı durdurdu?" sorusunun dürüst cevabı).
- [x] Rate limit: global limiter `max` ve `keyGenerator` fonksiyonlarıyla çatallandı;
      anahtar isteği kendi kovasına ve `API_KEY_RATE_LIMIT_MAX`'ine (300/dk) düşer. İkisi de
      `request.apiKeyAuth`'a değil BAŞLIĞA bakar — limiter kimlik doğrulamadan önce koşar.
      `config.js` + `.env.example`.
- [x] Testler (+11, süit 658 → **669**), yeni `test/unit/api-keys.test.js`: sır bir kez döner
      ve satırda düz metin YOK (kolon değil, **tüm satır** aranıyor) · anahtarla `/me` + görev
      CRUD ve yazımın kullanıcının kendi adına düştüğü · `last_used_at` damgası · revoked/
      expired/bilinmeyen üçü de 401 ve ayrı kodlar · **sahibi iki workspace'in de üyesiyken
      anahtarın ikincisine 403 vermesi** (JWT aynı çağrıda 200 — fark kanıtlanıyor) · üç kapı
      (anahtar anahtar üretemez/iptal edemez, hesap silemez, `/ai/*`'a giremez; her birinde
      "hiçbir satır değişmedi" iddiası) · başkasının anahtarına 404 · idempotent iptal.
      **JWT regresyonu:** mevcut 658 testin tamamı değişmeden yeşil.
      Kapı doğrulaması: workspace bağı kasten devre dışı bırakıldı → süit yakaladı
      (`expected 200 to be 403`) → geri alındı.
- [x] `SECURITY.md`'ye "API keys" bölümü (beş madde: tek gösterim + digest, tek workspace/
      scope yok, üç kapalı kapı, iptalin anlığı, anahtar-başına limit) + sızan anahtarda ne
      yapılacağı. ADR-0032, ARCHITECTURE §3, CHANGELOG, `.env.example`.
- [x] **Migration gerçek MySQL'de KOŞTU + entegrasyon testleri indi (2026-08-17m).**
      `npm run db:migrate` → **Batch 1 run: 25 migrations**, temiz. `SHOW CREATE TABLE api_keys`
      tasarımla birebir: `char(26)` id/user/workspace, `uq_api_keys_hash` tekil indeksi,
      `idx_api_keys_workspace_user`, iki FK `ON DELETE CASCADE`, collation `resolveCollation`
      yoluyla `utf8mb4_0900_ai_ci`. Entegrasyon (import-export.test.js içinde, anahtar
      senaryosuyla aynı yerde): anahtarla uçtan uca yazma+okuma · anahtar anahtar üretemez
      (403, ve `api_keys` sayımı 1'de kalıyor) · yabancı workspace 403 · `last_used_at` gerçekten
      doluyor · iptal sonrası 401 `AUTH_API_KEY_REVOKED` · **tekil indeksin gerçekliği** (aynı
      hash'i ikinci kez yazmak reddediliyor) · kullanıcı silinince anahtarların FK ile gitmesi.

### OPH-265 — API anahtarları ekranı (Entegrasyonlar) + `docs/API.md`

_(✅ 2026-08-17 — **tamamlandı.** Ekran + `docs/API.md`. App süiti **1210** (+6),
`flutter analyze` temiz, `dart format` uygulandı, `check:i18n` yeşil, `contrast.py`
FAILURES: 0. Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: ekranı yazmak kolaydı, testler iki gerçek yalanı yakaladı.** Biri
kopyala düğmesiydi (platform kanalı testte patlayınca diyalog açık kalıyordu), diğeri
ciddiydi: **çevrimdışı sunucuda ekran "henüz anahtar yok" diyordu.**_

- [x] `/settings/api-keys` ekranı + Entegrasyonlar grubunda "API erişimi" satırı (OPH-260'ın
      bilinçle boş bıraktığı yer artık dolu). Liste: ad, `awk_XXXXXXXX…` prefix (monospace),
      oluşturma/bitiş/son-kullanım tek satırda; canlı olmayan anahtarın revoke düğmesi YOK
      (yapacak bir şey kalmamıştır) ve durum rengin YANINDA yazıyla da söyleniyor (§3: renk
      tek taşıyıcı olamaz). Oluşturma sheet'i ad + süre (30/90/365/süresiz, ChoiceChip).
      **Sır tek kez:** `barrierDismissible: false`, "bu bir daha gösterilmeyecek" cümlesi,
      SelectableText + kopyala düğmesi.
- [x] **Bulgu 1 — kopyala düğmesi diyalogu kapatmıyordu.** `Clipboard.setData`'yı await edip
      sonra pop etmek, kanal patlarsa kullanıcıyı açık diyalogda bırakıyor. Sıra ters
      çevrildi: önce kapat, sonra kopyala (kapanma başarısız olabilecek parça değil). Test
      panonun İÇERİĞİNİ de doğruluyor — sunucunun ürettiği sır mı, prefix mi.
- [x] **Bulgu 2 — çevrimdışıyken ekran yalan söylüyordu.** `currentWorkspaceProvider`'ın
      `.value`'su hata durumunda `null` dönüyor, o da boş listeye, o da "henüz anahtar yok"
      ekranına çıkıyordu. "Anahtarın yok" SUNUCU hakkında bir iddia ve yükleme başarısızken
      sunucudan haber alınmamıştır. Provider artık hatayı yeniden fırlatıyor → dürüst hata
      ekranı + yeniden dene. _Testi ben yazdım, ekranı ben yazdım, yalanı test yakaladı._
- [x] Store/provider: çevrimiçi yüzey — liste drift replikasına İNMEZ (bir haftadır
      çevrimdışı bir cihazın, hepsi iptal edilmiş olabilecek kimlik bilgilerini kendinden
      emin listelemesi doğru değil; ayrıca sızabilecek ikinci bir yer olurdu). AI bağlantıları
      ekranı emsal.
- [x] `docs/API.md` doğdu (265 satır): anahtar alma + `awk_` header örneği, üç kapalı kapının
      tablosu, `GET /me` ile workspace keşfi, curl tarifleri (görev oluştur/tamamla/ertele,
      not oluştur + göreve bağla, export, arama), **tam uç envanteri** (6 tablo, rota
      dosyalarından üretildi), hata kodu tablosu, rate limit, anahtar yaşam döngüsü ve
      "sızarsa ne yapılır". README doküman tablosuna satır + `docs/MCP.md` ↔ `docs/API.md`
      karşılıklı bağlantı ("script mi yazıyorsun, asistana mı soruyorsun" ayrımı).
      _İçe aktarma tarifleri OPH-266 indiğinde eklenecek (o uçlar henüz yok — yazılmadı)._
- [x] Testler (+6, süit 1204 → **1210**): boş durum · oluşturma akışı (sırın SUNUCUNUN
      ürettiği değer olduğu + panoya o değerin gittiği + listede bir daha görünmediği) ·
      süresiz anahtarın bilinçli seçim olduğu · revoke onayı (iptal edilebilir + sonrası
      düğmenin kaybolması) · **çevrimdışı sunucunun boş liste DEĞİL hata göstermesi** ·
      dark render. i18n `apiKeys.*` 27 anahtar en+tr, `check:i18n` yeşil, `contrast.py`
      FAILURES: 0 (palet değişmedi, mevcut token'lar kullanıldı).

### OPH-266 — Toplu içe/dışa aktarma: issue #3'ün kabul testi

_(✅ 2026-08-17 — **tamamlandı.** `routes/import-export.js`. API süiti **680** (+11),
lint/format temiz. Entegrasyon süiti KOŞULAMADI — konteyner çalışma zamanı yok.
Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: kısmi başarıyı raporlamak, tek büyük transaction'dan daha zor ve daha
doğru.** 500 satırlık bir aktarımın 37.'si ölü bir projeyi işaret ediyorsa doğru cevap "hiçbir
şey aktarılmadı" değil: 499 satır girer, 37. satır indeksi ve kodu ile söylenir. Çağıran o tek
satırı düzeltip yalnız onu tekrar gönderebilir._

- [x] `GET /workspaces/:workspaceId/export/notes` — not BÜTÜN olarak çıkıyor (id, title,
      contentFormat, **her iki gövde alanı**, plainText, projectId, tagIds, links, pin/arşiv,
      tarihler); `limit` ≤200 + `cursor`, `includeArchived` varsayılan **true** (sessizce
      arşivi düşüren bir dışa aktarma yanlış türde bir düzenliliktir). Sayfa başına iki
      batched okuma (note_links + note_tags) — N+1 yok.
      _Zip PARK, yazılı sebep: v1 JSON; tek not zaten `/notes/:id/export`'ta markdown._
      _Dışa aktarma şekli DIŞ SÖZLEŞME olduğu için `serializeNoteSnapshot` yeniden
      kullanılmadı, ayrı yazıldı: iç serializer'ın alanları uygulamanın ihtiyacıyla oynar._
- [x] `POST /import/notes` — tavan 500, markdown-canonical doğar, `db/notes.js.createNote`
      (+ tagIds varsa `setNoteTags`) üzerinden; yanıt `{created:[ids], errors:[{index, code,
      message}]}`.
- [x] `POST /import/tasks` — tavan 500, `db/tasks.js.createTask` döngüsü: assert'ler, urgent→
      acknowledgement varsayılanı, etiket bağları ve **reminder reconcile** dahil. Acil + due
      olan aktarılmış görev gerçek alarm alıyor, çünkü burada özel durum yok.
- [x] Testler (+11, süit 669 → **680**): aktarılmış notun **`?q=` ile bulunduğu** (OPH-261
      onarımı aktarımda da geçerli) + sync revision'ı düştüğü · kısmi başarı (2/3 girer, hata
      indeks + kodla) · etiket bağlama ve hatalı etiketin notun KENDİ hatası olması · 501
      satırın komple reddi · acil görevin alarm üretmesi · export'un links/tags/iki gövde
      alanını taşıması · sayfalama (aynı satır iki kez servis edilmiyor) · yabancıya 403 ·
      **round trip: export → import → 4 not** (issue #3'ün kabul testi) · **API anahtarıyla
      uçtan uca** (anahtarların var olma sebebi budur).
      _Test fixture'ında yakalanan: 25 karakterlik sahte ULID → Ajv tüm isteği 400'lüyor.
      Doğru davranış; düzeltilen testti._
- [x] **AGENTS kural 12 — MCP yarısı, yazılı sebep:** toplu aktarım MCP'ye GİRMEDİ. Bu
      script şeklinde bir işlem (anahtar yüzeyi); asistanın elinde zaten `create_note`/
      `create_task` var ve 500 satırlık bir gövdeyi tool argümanı olarak taşımak ne host
      onay kartına ne de bağlam bütçesine sığar. `docs/API.md`'ye toplu bölüm + uç tablosu
      eklendi (OPH-265'te "uçlar yokken yazılmaz" denmişti; artık varlar).
- [x] OPH-267 indikten sonra import sürümlemede `origin='import'` görünür (V8) — **kapandı
      aynı gün:** OPH-267 inerken `import/notes` çağrısı `origin: 'import'` geçirmeye başladı
      (tek satır, söz verildiği gibi) ve testi OPH-267 süitinde çivili.
- [x] **Testler indi ve KOŞTU (2026-08-17m):** `test/integration/import-export.test.js`, 6 test.
      Round-trip (import → `/sync/pull` görüyor → export aynı belgeyi geri veriyor; arşivli not
      dahil, `contentFormat: 'markdown'`) · kısmi başarı (ölü proje TEK maddeyi düşürüyor, 2
      satır gerçekten yaratılıyor, reddedilen HİÇBİR ŞEY bırakmıyor) · tavanlar (501 → 400,
      boş → 400, `?limit=201` → 400, **500 → 200** yani tavan off-by-one değil) · imleçli
      sayfalama 25 notu tekrarsız/eksiksiz veriyor · 264'ün anahtarıyla uçtan uca senaryo.
      Kapı doğrulaması: `origin: 'import'` satırı kasten silindi → süit yakaladı
      (`Set{'create'}` ≠ `Set{'import'}`) → geri alındı.
- [ ] **AÇIK — sahibe kalan:** **Issue #3'e kapanış yorumu** (sevk edilen uçlar + docs/API.md
      bağlantısı + sürüm) ve issue'nun kapatılması. Dış iletişim; ajan kendiliğinden yazmaz.

### OPH-267 — Sürümlemenin omurgası: ADR-0031, `note_versions`, yakalama + saklama

_Bulgu #4/#5 + literatür tablosu. İLK İŞ ADR-0031: yukarıdaki karar #5-#10 çerçevesi + iki
tablo ADR'ye taşınır (araştırma raporu bağlantısıyla); "hiçbir sürümleme kodu ADR'den önce
yazılmaz" (OPH-246 emsali)._

_(✅ 2026-08-17 — **tamamlandı.** ADR-0031 + `note_versions` + yakalama + saklama + REST.
API süiti **697** (+17), lint/format temiz. Entegrasyon süiti ve migration'ın gerçek MySQL'de
koşması BLOKE (konteyner çalışma zamanı yok). Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: bu tablo bir özellik değil, round 18'in bulgu #4'ünün cevabı** — ezilen
not gövdesi HİÇBİR tabloda durmuyordu; `sync_revisions` yalnız hangi alanların değiştiğini
biliyor. Çakışma kopyası da, merge de, restore da, geri alma da aynı eksik şeye ihtiyaç
duyuyor: **önceki baytlar.**_

- [x] **ADR-0031 yazıldı (task'ın İLK işi, OPH-246 emsali):** 12 ürün/sistemlik literatür
      tablosu ADR'ye taşındı, karar #5–#10 çerçevesi sekiz maddeye açıldı (sunucu-sahipli
      tarihçe, tek yakalama fonksiyonu, yuvarlanan baş, hash dedupe, üç içerik alanı,
      üç kademeli saklama, tarihçeyi yeniden yazmayan restore, sunucuda diff), beş alternatif
      (CRDT, koalesanssız, istemci-tarafı tarihçe, diff saklama, adlandırılmış sürümler)
      gerekçeleriyle reddedildi.
- [x] Migration `20260817160000_create_note_versions`: üç içerik alanı + `content_format`,
      `origin`, `client_id`, `created_by`, `content_hash`, `note_revision`; üç index
      (note+created, note+revision, workspace+created); note ve workspace FK'leri CASCADE.
- [x] **Yakalama:** `db/notes.js.createNote`/`updateNote` — ve **yazılı istisna:** sync push
      motoru `db/notes.js`'ten geçmiyor (OPH-218'den beri kendi ENTITIES makinesi), o yüzden
      AYNI fonksiyonu kendi `afterCreate`/`afterUpdate` dikişinden çağırıyor. **İki çağrı
      noktası, tek politika.** Alternatif — çevrimdışı yolun tarihçe yazmaması — en çok
      üzerine yazan yazarın iz bırakmaması olurdu.
- [x] Koalesans (yuvarlanan baş): aynı not + aynı `client_id` + `origin='edit'` + <10 dk →
      satır YERİNDE güncellenir. Ölçülmüş karşılık: 6 ardışık otosave = 1 satır (testte
      çivili), 1.5 sn debounce'un ürettiği ~260 satır değil.
- [x] `content_hash` (sha256, **formatı da kapsıyor** — biçim dönüşümü notun ne OLDUĞUNU
      değiştirir, ADR-0028 §1) ile özdeş gövde satır üretmez.
- [x] **Beklenmedik bulgu — notun DOĞUŞ hâli ilk düzenlemeye yutuluyordu.** Oluşturma satırı
      `origin='edit'` taşıyınca, 10 dakika içindeki ilk düzenleme onun İÇİNE koalesans yapıyor
      ve "bu not geldiğinde neydi" sessizce siliniyordu. Çözüm spec'in enum'una bir değer
      ekledi: `create`. Yuvarlanan baş yalnız `origin='edit'` satırına birleştiği için doğuş
      satırı **yapısı gereği** birleştirilemez oldu — özel durum yazmaya gerek kalmadı.
- [x] Saklama süpürücüsü (`plugins/note-version-gc.js`, storage-GC emsali): 0–7 gün dokunma,
      7–90 gün not/gün başına 1'e incelt, sonrası sil; `conflict|merge|restore|import` 365 gün;
      not başına 500 tavan. `config.js` + `.env.example` (altı knob).
- [x] REST: `GET /notes/:id/versions` (yalnız metadata + boyut + hangi cihaz),
      `GET …/versions/:versionId` (tam gövde), `GET …/diff` (jsdiff kelime segmentleri, sunucuda
      — istemci yalnız çizer), `POST …/restore` `{mode: replace|copy}`.
- [x] Bağımlılıklar `diff@9` (jsdiff) + `node-diff3@3` girdi; ADR-0031 §8 gerekçesi.
      _node-diff3 OPH-268'in merge motoru; şimdilik kullanılmıyor, ADR'de yazılı._
- [x] Testler (+17, süit 680 → **697**): doğuş satırı · 6 otosave = 1 satır · pencere kapanınca
      yeni satır · özdeş gövde satır üretmez · pin/arşiv sürüm yakmaz · **her yazarın kendi
      origin'i** (edit/api/import/mcp) · çevrimdışı push'un cihaz kimliğiyle yakalanması ·
      liste metadata / detay gövde ayrımı · diff segmentleri · yabancıya 403 · restore-replace'in
      YENİ baş ürettiği ve hem eski sürümü hem bıraktığımız hâli koruduğu · restore-copy'nin
      mevcut notu ellemediği · saklama kademeleri + korumalı origin'ler · **sürümlerin sync
      varlığı OLMADIĞI** (pull'da yok, push reddediyor).
- [x] **Kapı doğrulaması ve ikinci bulgu:** `isContentWrite`'a `is_pinned` eklenerek kasten
      ihlal enjekte edildi — **süit YEŞİL kaldı.** Sebep: pin yazımı zaten hash dedupe'una
      takılıyor, yani iki katman birbirini maskeliyordu. Kuralı doğrudan çiviyen bir birim
      testi eklendi, ihlal tekrar enjekte edildi, bu kez yakalandı, geri alındı.
      _Ders: iki savunma iyidir; hiçbir testin ifade etmediği bir kural değildir._

### OPH-268 — Çakışma doğruluğu: not-bazlı base, sunucuda diff3, kopyanın emekliliği

_Bulgu #1/#2/#3 — override'ın ölçülmüş üç katmanı. Merge YALNIZ üç taraf markdown-canonical
iken (karar #7); gerisi banner/kopya yolu. Eski istemci uyumu: mutation'da base yoksa sunucu
bugünkü davranışa düşer (kendi kendini kırmayan protokol)._

_(⏳ 2026-08-17 — **SUNUCU YARIMI BİTTİ**, istemci yarımı açık. API süiti **709** (+12),
lint/format temiz. Eski istemciler etkilenmiyor: base göndermeyen mutation bugünkü davranışı
alır, yani bu yarım tek başına sevk edilebilir ve edildi.)_

_**Turun tek cümlesi: bulgu #1'in kökü kilidin varlığı değil, NEYİ kıyasladığıydı** —
workspace pull imleci. Soket kaynaklı bir pull imleci karşı tarafın yazımının ötesine
taşıyor, kilit "yabancı bir şey olmadı" diyor ve bir gövde diğerini sessizce siliyordu. Base
artık NOTUN kendi revizyonu ("editörün gördüğü şey")._

- [x] Protokol: push mutation'ına opsiyonel NOT-bazlı `baseRevision` (Ajv) + sonuç zarfında
      `status:'merged'`, `merged{contentMarkdown,contentFormat}`, `conflictVersionId`,
      `reason`. **Kendi başarılı push'unun revizyonu base'i ilerletir** — art arda iki
      otosave'in sahte çakışma ÜRETMEDİĞİ testle çivili.
      _`PendingMutations` kolonu + editörün base'i taşıması istemci yarımında (aşağıda)._
- [ ] Outbox koalesansı: aynı nota push edilmemiş ikinci `update` enqueue edilirse patch'ler
      birleşir — EN ESKİ base + EN YENİ gövde (bulgu #3'ün N-kopya patlamasının istemci ayağı).
- [x] Sunucu `applyUpdate` (not, content intents): mutation base'i varsa notun KENDİ
      `revision`'ıyla kıyasla (workspace-imleç kıyası content için ölür — bulgu #1'in kökü).
      Eşit → uygula + sürüm. Küçük → base gövdesini `note_versions`(note_revision=base)'ten
      getir: bulunamadı YA DA üç taraftan biri markdown-canonical değil → `NOTE_CONTENT_CONFLICT`
      + gelen gövde `origin='conflict'` sürümü olarak SAKLANIR (V1: kayıp yok) + yanıtta
      `conflictVersionId`. Bulundu → normalize (`\r\n`→`\n`) → `node-diff3` satır → çakışan
      bölgede `jsdiff` kelime inceltme (karar #6, diff3 makalesinin tek-satır-paragraf tuzağı)
      → temiz: birleşik gövdeyi uygula (`origin='merge'`, yanıt `status:'merged'` + gövde;
      istemci replika + AÇIK editörü günceller) → örtüşme: yukarıdaki conflict yolu.
- [ ] İstemci çakışma davranışı DEĞİŞİR (karar #8): otomatik kardeş-kopya ÜRETİLMEZ; Notes
      replika satırına yerel `conflictVersionId` işlenir → not banner'ı (OPH-269 çizer; bu
      task state+snackbar'ı koyar). Batch'te aynı nota tek çakışma işlenir (dedupe). "Kopya
      olarak ayır" seçilirse kopya `contentFormat` DAHİL doğar (bulgu #3'ün format bug'ı
      burada ölür — kopya üretimi artık kullanıcı eylemi).
- [ ] Editör V7: pull ile gelen değişiklik AÇIK ve TEMİZ editöre yerinde iner (base ilerler);
      KİRLİ editör kullanıcı metnini korur (push-time base işini yapar). `didUpdateWidget`/
      provider dinleme — bulgu #2'nin kapanışı.
- [x] REST `PATCH /notes/:noteId` opsiyonel `baseRevision` kabul eder (aynı yol; 409 +
      `conflictVersionId`, `docs/API.md`'de "Conflict-safe edits" bölümü).
- [x] **Sunucu testleri (+12, süit 697 → 709)** `test/unit/note-conflict.test.js`: merge
      motoru (ayrık satırlar birleşir · **tek paragrafta KELİME inceltmesi** — diff3
      makalesinin tuzağı · gerçek örtüşme reddedilir · CRLF normalizasyonu) · **Senaryo A:
      iki istemci, iki metin de yaşıyor** (`status:'merged'`, gövdede iki taraf da,
      `origin='merge'` sürümü, plain_text takip ediyor) · gerçek örtüşmede reddin gövdeyi
      SAKLADIĞI (`conflictVersionId` işaret ediyor) · art arda iki otosave sahte çakışma
      üretmiyor · delta-canonical not merge'e girmiyor (`NOT_MARKDOWN`) · saklama süpürmüş
      base (`BASE_MISSING`) · **base göndermeyen eski istemci bugünkü davranışı alıyor** ·
      REST PATCH'in merge'i ve 409'u.
- [x] **İstemci yarımı da BİTTİ** (aynı gün, ikinci tur). App süiti **1213** (+3),
      analyze/format/i18n temiz, `contrast.py` FAILURES: 0.
      · **drift v18** iki kolon: `PendingMutations.baseRevision` (editörün gördüğü) ve
      `Notes.conflictVersionId` (reddedilen gövdenin sunucudaki yeri — cihaz-yerel, ASLA
      push edilmez). İkisi de mevcut tabloda olduğu için `from >= 1` guard'lı; migration
      testi v18'e taşındı ve **yükseltmeden gelen kuyruk satırının base'siz olduğunu** —
      yani sunucunun hâlâ onurlandırdığı eski-istemci yolunu — çiviliyor.
      · **Base taşıma:** `NoteStore.update` içerik yazımlarında replikanın `revision`'ını
      outbox satırına yazıyor; motor başarılı push'ta (applied VE merged) notun yerel
      revizyonunu sonuç revizyonuyla ilerletiyor — art arda iki otosave'in kendi kendine
      çakışmamasının istemci ayağı.
      · **Outbox koalesansı:** aynı nota push edilmemiş ikinci update, EN ESKİ base + EN
      YENİ gövdeyle tek satıra iniyor (üç otosave → bir satır, testli).
      · **Otomatik kardeş-kopya ÖLDÜ.** Yerine nota `conflictVersionId` işleniyor (banner'ı
      OPH-269 çizecek) + snackbar. Kopya üretmek artık kullanıcının seçimi; kaybeden gövde
      zaten sunucunun tarihçesinde.
      · **Editör V7:** `didUpdateWidget` + `NoteDocument.adoptRemote` — TEMİZ editör pull ile
      geleni yerinde alıyor (denetleyiciler yeniden kurulmuyor: odak düğümü ve kaydırma
      konumu OPH-270'in dersi), KİRLİ editör kullanıcının metnini koruyor ve işi push-time
      merge'e bırakıyor.
- [x] **Bulgu — koalesans, uçuştaki satırı silebilirdi.** Motor settle'da outbox satırını
      koşulsuz siliyordu; koalesans push'a girmiş bir satıra daha yeni bir gövde yazarsa o
      gövde silinip giderdi. Silme artık `localUpdatedAt` eşleşmesine bağlı (compare-and-
      delete): satır push'tan sonra değiştiyse silinmiyor, bir sonraki turda birleşmiş
      gövdeyle gidiyor. _Tam da bu task'ın bitirdiği arıza sınıfı._
- [x] **Senaryo A'nın birebir reprodüksiyonu İNDİ ve KOŞUYOR (2026-08-17m)** —
      `test/integration/note-merge.test.js`, 6 test. Reprodüksiyonun çekirdeği: her push
      **TAZE bir üst-seviye `baseRevision`** (soket pull'un ilerlettiği workspace imleci) ve
      **BAYAT bir mutation `baseRevision`** (editörün gördüğü not revizyonu) taşıyor — eski kod
      tam da bu ayrımı kaçırıyordu. Kapsam: Senaryo A (iki metin de yaşıyor, `status:'merged'`,
      sürüm zinciri `create→edit→merge`) · kelime düzeyi (tek paragrafın iki ucu) · gerçek
      örtüşme reddi + reddedilen gövdenin `origin='conflict'` olarak saklanması · offline
      reconnect · `BASE_MISSING`. **Kapı doğrulaması: özgün hata geri enjekte edildi**
      (`baseRevision: ctx.baseRevision`) → 6 testin 6'sı `applied` diyerek düştü, yani sessiz
      ezme aynen geri geldi → geri alındı (`git diff` boş).
- [x] **Bulgu — append-vs-append gerçekten çakışmadır, kusur değil.** İlk yazdığım offline
      testi iki cihazın AYNI listenin sonuna farklı madde eklemesiydi ve `OVERLAP` aldı.
      Ölçtüm (`mergeMarkdown` doğrudan): aynı ekleme noktasına iki farklı içerik, diff3'ün
      sırayı bilemeyeceği bir durum — doğru cevap reddetmek. Test senaryosu düzeltildi
      (offline cihaz başlığı değiştiriyor, diğerleri listeye ekliyor) ve append-vs-append
      **ayrı bir test olarak, belgelenmiş sınır** biçiminde bırakıldı.
- [ ] **AÇIK — app tarafı testleri:** engine settle/base-ilerletme/dedupe + editör temiz/kirli
      davranışı. Sunucu sözleşmesi artık entegrasyonda çivili; bu kalem Flutter süitine ait.

### OPH-269 — Sürüm geçmişi & çakışma yüzeyi (DESIGN §35)

_(✅ 2026-08-17 — **tamamlandı. Epic 25 KAPANDI.** App süiti **1222** (+9),
analyze/format/i18n temiz, `contrast.py` FAILURES: 0 + banner çifti elle ölçüldü.
Deploy alınmadı, sahibin talimatı.)_

_**Turun tek cümlesi: bu ekran yeni bir renderer getirmedi** — önizleme notun KENDİ okuma
modunu kullanıyor (V4). Bir belgeyi iki yerde çizmek, ikisinin ayrı ayrı yanlış olması demek._

- [x] Editör menüsüne "Sürüm geçmişi" (`note-versions`) → `NoteVersionsScreen`: **gün başlıklı**
      liste (Bugün/Dün/tarih), satır = saat + origin etiketi (Bu cihaz · Diğer cihaz ·
      Birleştirme · Çakışma · Geri yükleme · İçe aktarma · API · Asistan — `clientId`
      kıyasıyla; cihaz kimliği `syncClientIdProvider`'dan geliyor) · tık = **mevcut okuma
      renderer'ıyla** önizleme + "Neyin değiştiğini gör" (sunucunun kelime segmentleri) ·
      "Geri yükle" (onaylı; diyalog V5'in cümlesini söylüyor: bıraktığın sürüm de saklanır) ·
      "Kopya olarak geri yükle".
- [x] **Çevrimdışı dürüst boş durum (V6):** "Geçmiş çevrimiçi kullanılabilir" — boş liste
      göstermek yalan olurdu, çünkü gövdeler sunucuda ve replikaya inmiyor.
- [x] Çakışma banner'ı (V3): `conflictVersionId` taşıyan not editörde açılınca üst bant +
      dört eylem. **Hiçbiri veri kaybetmiyor ve banner bunu yazıyor:** "Farkı gör" ·
      "Benimkini kullan" (reddedilen gövdem restore-replace ile yeni head olur) · "Diğerini
      kullan" (sunucununki zaten kazandı — yalnız yerel işaret temizlenir, HİÇBİR yazım yok)
      · "Kopya olarak ayır" (Dropbox tarzı kopya, ama SEÇİLMİŞ sonuç olarak).
- [x] i18n `versions.*` + `conflict.*` (27 anahtar, en+tr), `check:i18n` yeşil.
- [x] **Kontrast:** `contrast.py` FAILURES: 0. Banner `tertiaryContainer` çifti script'in
      listesinde yok (Epic 24'ün açık kalemi), o yüzden **elle ölçüldü ve yazıldı:**
      light `#084F44` on `#BFF2E6` = **7.71**, dark `#BDF6EC` on `#0E5B4F` = **6.68**
      (ikisi de ≥4.5). Diff segmentlerinde renk TEK taşıyıcı değil: eklenen altı çizili,
      silinen üstü çizili (§3).
- [x] Testler (+9, süit 1213 → **1222**): gün gruplaması + origin adları · önizlemenin
      okuma renderer'ıyla çizilmesi · restore'un ÖNCE sorması, iptalin hiçbir çağrı
      yapmaması, onayın `mode:'replace'` göndermesi · "kopya olarak" → `mode:'copy'` ·
      diff segmentlerinin çizilmesi · **çevrimdışı boş-durum yalanının olmaması** · banner'ın
      dört eylemi ve **"diğerini kullan"ın HİÇBİR yazım yapmaması**.
- [x] **Bulgu:** önizleme `ReadingMode`'u bir `SingleChildScrollView` içine koymuştu —
      ReadingMode kendi kaydırıcısını taşıyor, yani "unbounded height" çökmesi. Testler
      yakaladı; sarmalayıcı `Padding`'e indi. _Bir bileşeni bütün olarak yeniden kullanmak,
      onun neyi zaten yaptığını bilmeyi gerektiriyor._
- [ ] **AÇIK — elle cihaz provası:** iki cihaz/simülatör, uçak modu senaryosu (temiz merge,
      örtüşen çakışma banner'ı, restore). Kod tarafı testlerle kapalı; fiziksel iki-cihaz
      turu sahibe kalıyor. **Not (2026-08-17m):** beklediği Senaryo A entegrasyon
      reprodüksiyonu artık indi ve yeşil (`note-merge.test.js`), yani sunucu davranışı
      kanıtlanmış durumda — bu kalemde geriye YALNIZ fiziksel gözlem kaldı.

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
- **Round 17 park kuyruğu — Markdown (gerekçeler [MARKDOWN.md](MARKDOWN.md) §3):**
  `[[wikilink]]`'ler + geri bağlantılar (bir bağlantı indeksi ister — kendi başına bir
  özellik); graf görünümü, PDF üzerine not alma, atıf/BibTeX (**reddedildi** — başka bir
  ürün); yazma hedefleri (Ulysses); ~~sürüm geçmişi/anlık görüntüler~~ (**park bitti —
  round 18'de Epic 25 oldu**, OPH-267…269; "sunucu tarafı tasarım ister" şartı ADR-0031 ile
  karşılanıyor); editör içi AI ("devam ettir", "yeniden yaz" — Epic 20'nin altyapısı hazır, ürün
  kararı); DOCX/ePub dışa aktarma; klasör/vault izleme (**reddedildi** — biz markdown'ı
  iyi okuyan bir görev uygulamasıyız, Obsidian değiliz); Vim/Emacs kısayolları ve özel CSS
  temaları (**reddedildi** — Rule 11, tek tasarım sistemi).
- **Round 18 park kuyruğu (gerekçeler TASKS Epic 25 "karara bağlananlar"):** **generic OIDC
  girişi** ([issue #2](https://github.com/mahirozdin/alliswell/issues/2) — Authentik/Keycloak/
  PocketID; meşru ve Firebase-sosyal-girişten farklı: sunucu yarısı ucuz çünkü ADR-0026'nın
  `src/lib/oauth-identity.js`'i zaten JWKS+issuer+audience doğrulaması ve subject-öncelikli
  hesap merdiveni taşıyor — iş "güvenilen issuer listesi + OIDC discovery'yi konfigürasyona
  açmak"; pahalı olan istemci yarısı: 6 Flutter platformunda authorization-code+PKCE tarayıcı
  akışı, deep-link dönüşü, ayar/doc yüzeyi. Tetikleyici: çok kullanıcılı workspace UI'ı
  açıldığında ya da talep birikince kendi epic'i olur); markdown'a renk sözdizimi (GFM'de yok
  — `==mark==` vurgusu var, gerisi Live/Delta tarafında; DESIGN §33 R6); Home/Projeler liste
  sıralaması (DESIGN §34 L5 yazılı sebepleri); notlar zip/dosya-başına toplu export (v1 JSON —
  OPH-266); API anahtarlarına scope'lar (v1 bilinçli scope'suz — ADR-0032 revizyonu ister);
  sürüm geçmişinde adlandırılmış/sabitlenmiş sürümler (Google Docs deseni; saklama
  inceltmesinden muafiyet mekanizması hazır, UI ürün kararı bekler); **markdown-canonical
  notların Okuma modunda açılması** (OPH-270'te ölçüldü: `NoteDocument` kurucusu
  `cameFromOutside: _format == NoteFormat.markdown` diyor, yani "markdown" ile "dışarıdan
  geldi" eşitleniyor — kendi dönüştürdüğün not da her açılışta salt-okunur geliyor;
  D2'nin niyeti bu değil, ama düzeltmesi dış-belge davranışına dokunuyor ve kendi turunu
  hak ediyor); salt-okunur Quill önizlemelerinin (`project_detail_screen.dart:374`,
  `markdown_import_screen.dart:266`) her derlemede `ScrollController` üretmesi (aynı
  paket deseni, imleç yok — kullanıcıya görünen etkisi ölçülmedi).
- Import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), release packaging (Docker image publish, F-Droid/TestFlight).
