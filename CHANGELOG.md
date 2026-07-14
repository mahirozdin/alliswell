# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

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
