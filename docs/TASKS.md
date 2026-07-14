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
(_Authenticated endpoints don't exist yet — the issued JWT is verified server-side in tests;
the end-to-end acceptance closes with `GET /me` in OPH-023._)

### OPH-021 — Login endpoint ✅

- [x] `POST /api/v1/auth/login` — argon2 verify, timing-safe failure path
- [x] Same token pair response shape as register
- [x] Error `AUTH_INVALID_CREDENTIALS` (no user/pass distinction)
- [x] Rate limit tighter than global (`RATE_LIMIT_AUTH_MAX`, default 10/min/IP, all auth routes)
- [x] Tests: wrong password, unknown email, happy path (+ soft-deleted user, rate limit trip)

### OPH-022 — Refresh token rotation

- [ ] `POST /api/v1/auth/refresh` — rotate: old token revoked, same family id
- [ ] Reuse detection: refresh with a rotated token revokes the whole family
- [ ] `POST /api/v1/auth/logout` — revoke current token (and `?all=true` for family)
- [ ] Tests: rotation chain, reuse attack, expiry

### OPH-023 — Auth middleware / plugin

- [ ] `app.authenticate` decorator verifying JWT (issuer/audience/exp)
- [ ] `request.user` + workspace-membership authorization helper
- [ ] `GET /api/v1/me` returning profile + workspaces
- [ ] Tests: missing/expired/garbage token, membership check

### OPH-024 — Flutter auth repository

- [ ] dio API client with base URL config + auth interceptor (token attach/refresh-on-401)
- [ ] Auth repository (register/login/refresh/logout) + Riverpod providers
- [ ] Login & register screens wired to shell (redirect when unauthenticated)
- [ ] Widget/unit tests with mocked dio

### OPH-025 — Secure token storage

- [ ] flutter_secure_storage for tokens (Keychain/Keystore; web: memory + refresh cookie note)
- [ ] Session restore on app start; logout clears storage
- [ ] Tests for storage wrapper

---

## Epic 04 — Projects / Tags / Tasks (Phase 1)

### OPH-030 — Project CRUD API

- [ ] `GET/POST /api/v1/workspaces/:wsId/projects`, `GET/PATCH/DELETE /api/v1/projects/:id`
- [ ] RGB color validation (`#RRGGBB`), status enum, favorite, sort_order
- [ ] Soft delete; workspace authorization on every route
- [ ] Revision bump + `sync_revisions` row on every write (transaction helper)
- [ ] Tests: CRUD, authz cross-workspace denial, validation

### OPH-031 — Tag CRUD API

- [ ] CRUD under workspace; unique slug per workspace (slugify helper)
- [ ] Tests incl. duplicate slug conflict

### OPH-032 — Task CRUD API

- [ ] Create/list (filters: status, projectId, tag, due range, urgent; cursor pagination) /
      get / patch / soft-delete
- [ ] Checklist items sub-resource; parent_task_id subtasks
- [ ] Tag attach/detach (`PUT /tasks/:id/tags`)
- [ ] Revision + sync_revisions on writes
- [ ] Tests: filters, pagination, subtask nesting, tag ops

### OPH-033 — Task status & priority transitions

- [ ] `POST /tasks/:id/complete` / `reopen`; completed_at handling
- [ ] Status transition validation (e.g. archived tasks immutable)
- [ ] Tests

### OPH-034 — Task urgent / remind fields

- [ ] Validation: remind_at requires timezone; urgent implies requires_acknowledgement default
- [ ] Reminder row lifecycle sync with task.remind_at (create/update/cancel)
- [ ] Tests

### OPH-035 — Task snooze endpoint

- [ ] `POST /api/v1/tasks/:id/snooze` (`snoozeUntil` or preset `5_min|30_min|1_hour|tomorrow_morning`)
- [ ] Updates task.snoozed_until + reminder.snoozed_until/status
- [ ] Tests incl. preset math in user timezone

### OPH-036 — Flutter project screens

- [ ] Projects list (colors, favorite, status) + create/edit sheet with RGB picker
- [ ] Project detail tabs skeleton (Overview/Tasks/Notes)
- [ ] Riverpod repositories hitting the API; tests

### OPH-037 — Flutter task screens

- [ ] Inbox/Today/Upcoming lists from API; quick-add bar
- [ ] Task detail: status, priority, tags, dates, urgent toggle, checklist
- [ ] Tests

---

## Epic 05 — Notes (Phase 1)

### OPH-040 — Note CRUD API

- [ ] CRUD with content_delta (JSON), content_markdown, plain_text extraction
- [ ] Pinned/archived; workspace authz; revisions
- [ ] Tests

### OPH-041 — Note–task link

- [ ] `POST/DELETE /api/v1/notes/:id/links` (polymorphic, v1: task/project)
- [ ] "Create note from task" endpoint: inherits task's project automatically
- [ ] Tests

### OPH-042 — Note–project link

- [ ] Project notes listing (`GET /projects/:id/notes`)
- [ ] Tests

### OPH-043 — Flutter note list

- [ ] All/pinned/project/task-linked filters; search box (server FULLTEXT)
- [ ] Tests

### OPH-044 — Flutter note editor

- [ ] flutter_quill editor (rich text: color, links, headings, checklists, code)
- [ ] Delta autosave; markdown preview/export action
- [ ] Tests

### OPH-045 — Markdown export

- [ ] Server-side delta→markdown converter + `GET /notes/:id/export?format=md`
- [ ] Tests with fixture deltas

---

## Epic 06 — Sync (Phase 2)

### OPH-050 — Revision generator

- [ ] Transaction helper: `withRevision(trx, wsId, entityType, entityId, op, changedFields)`
- [ ] Per-workspace monotonic counter (row lock on workspaces.revision)
- [ ] Retrofit existing write paths; tests incl. concurrency

### OPH-051 — Sync pull endpoint

- [ ] `GET /api/v1/sync/pull?workspaceId&sinceRevision` (batched, `hasMore`)
- [ ] Entity snapshots for create/update; tombstones for delete
- [ ] Tests

### OPH-052 — Sync push endpoint

- [ ] `POST /api/v1/sync/push` with mutation batch (per BLUEPRINT §6.3)
- [ ] Field-level LWW merge for metadata; per-mutation result statuses
- [ ] Tests: apply, conflict, invalid entity

### OPH-053 — Idempotency table usage

- [ ] Duplicate `clientMutationId` returns recorded result without re-applying
- [ ] Tests: replay batch

### OPH-054 — Flutter local DB

- [ ] drift schema mirroring server entities + `pending_mutations` outbox table
- [ ] Repository layer reads local-first
- [ ] Tests

### OPH-055 — Flutter outbox

- [ ] Mutation enqueue on every local write; background push with retry/backoff
- [ ] Tests

### OPH-056 — Conflict handling

- [ ] Server conflict statuses surfaced; note conflict-copy flow (v1 policy)
- [ ] Tests

### OPH-057 — WebSocket live update

- [ ] Socket.IO server (auth on connect, rooms per workspace) + Redis adapter
- [ ] `sync:changed {workspaceId, toRevision}` event on push/API writes → clients pull
- [ ] Flutter socket client triggering pull; tests

---

## Epic 07 — Notifications (Phase 3)

### OPH-060 — Notification device registry

- [ ] `notification_devices` migration + register/unregister endpoints (platform, push token?)
- [ ] Tests

### OPH-061 — Local notification scheduling

- [ ] flutter_local_notifications setup (all platforms incl. timezone handling)
- [ ] Schedule/cancel from task.remind_at via local DB
- [ ] Tests where feasible

### OPH-062 — Snooze actions

- [ ] Notification action buttons: complete / 5m / 30m / 1h / tomorrow / custom
- [ ] Actions call snooze endpoint when online; enqueue mutation when offline

### OPH-063 — Urgent notification UX

- [ ] Urgent channel: critical sound, requires acknowledgement, re-alert loop until acked
- [ ] Acknowledge endpoint wiring (`reminders.acknowledged_at`)

### OPH-064 — Notification privacy mode

- [ ] Setting: payloads/notifications show IDs-only vs. title
- [ ] Server push payloads always minimal (BLUEPRINT §8.3)

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
