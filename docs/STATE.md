# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-14 (Epic 03 — Auth complete, OPH-020…025)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

| | |
| --- | --- |
| Current phase | Phase 1 — Core domain |
| Current epic | **Epic 04 — Projects / Tags / Tasks** |
| ➡️ **Next task** | **OPH-030 — Project CRUD API** |
| Last completed | Epic 03 (OPH-020…025); Epic 01, Epic 02, OPH-090…093 |

## Recently completed

- **Epic 03 — Auth (complete):**
  - **API:** register/login/refresh/logout + `GET /me` under `/api/v1`. argon2id (timing-safe
    dummy verify on unknown email); 15-min JWTs (iss `alliswell-api`, aud `alliswell-app`;
    `@fastify/jwt` v10 — numeric `expiresIn` is SECONDS); opaque 30-day refresh tokens stored
    as HMAC-SHA256(JWT_REFRESH_SECRET), rotation families with reuse detection (replay revokes
    the family, concurrent rotation settled by atomic claim UPDATE). `app.authenticate`
    (expired → `AUTH_TOKEN_EXPIRED`) + `app.requireWorkspaceMember(request, wsId, {roles})`.
    Auth routes rate-limited via `RATE_LIMIT_AUTH_MAX` (10/min default). Production refuses
    placeholder/short/identical JWT secrets. Error codes listed in apps/api/README.md.
  - **App:** feature-first `lib/src/features/auth/` — dio + AuthInterceptor (attach token,
    single-flight refresh-on-401, one retry), AuthRepository (session source of truth,
    change stream), Riverpod `authControllerProvider`, login/register screens, router guard
    (`/splash` → `/login`), Settings sign-out. Sessions persist via flutter_secure_storage
    (web: memory only, refresh-cookie flow planned) and restore on start. Unit tests stub
    knex (`apps/api/test/helpers/fakedb.js`) and dio (fake HttpClientAdapter).
- **Epic 01 — Foundation:** monorepo (npm workspaces), full docs set, Docker Compose
  (MySQL 8.4 + Redis 8 + optional api/adminer), Fastify API skeleton with health endpoints,
  Flutter 6-platform shell (Riverpod + go_router, adaptive navigation), GitHub Actions CI.
- **Epic 02 — Database:** knex migration baseline — 17 tables covering users/workspaces/members,
  refresh_tokens, projects/tags/tasks (+task_tags, checklist_items), notes (+note_tags,
  note_links), sync_revisions + client_mutations, calendar_accounts/calendar_event_links/reminders.
- **Epic 09 (partial):** CONTRIBUTING, SECURITY, issue/PR templates.

## Blocked / notes

- **Local Docker daemon is missing on the dev machine** (Docker Desktop was uninstalled; CLI
  remains with broken plugin symlinks). Until Docker Desktop/OrbStack is installed,
  `docker compose up` and local integration tests can't run — CI covers them meanwhile.
  Also note: something already listens on local port 3306; use `MYSQL_PORT` in `.env` if it conflicts.
- ~~`JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` placeholders~~ — done in OPH-020: config falls
  back to labeled insecure dev secrets, production refuses placeholders/short/identical values.
- Apple EventKit work (OPH-077+) requires macOS/Xcode signing setup on the dev machine.
- Web builds keep tokens in memory only (signed out after a reload) — the httpOnly
  refresh-cookie flow is the planned hardening; see OPH-025 notes in TASKS.md.

## Environment assumptions

- Node ≥ 22 (dev machine: v25), Flutter 3.44 / Dart 3.12, Docker Desktop with compose v2.
- Local infra: `docker compose up -d mysql redis` then `npm run db:migrate`.

## How to continue (for agents)

1. Read [../AGENTS.md](../AGENTS.md) §2 (protocol) if you haven't.
2. Implement **OPH-030** per its checklist in [TASKS.md](TASKS.md) — use the Epic 03
   helpers: `app.authenticate`, `app.requireWorkspaceMember`, and `apiClientProvider`
   (already-authenticated dio) on the app side.
3. Verify (`npm run lint && npm test`, integration tests if infra up), document, commit,
   then update this file's Snapshot + Recently completed.
