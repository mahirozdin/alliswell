# @alliswell/api

AllisWell backend — **Fastify 5, JavaScript only (ESM, no TypeScript)**, MySQL 8.4 via knex,
Redis via ioredis. Rules: [/AGENTS.md](../../AGENTS.md) • Architecture:
[/docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

```bash
# from repo root
docker compose up -d mysql redis
npm install
npm run db:migrate
npm run dev            # http://localhost:3000

curl localhost:3000/health/live    # process liveness
curl localhost:3000/health/ready   # MySQL + Redis component status

# create an account (returns JWT access + opaque refresh token)
curl -X POST localhost:3000/api/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"email":"you@example.com","password":"a-strong-password","displayName":"You"}'
```

## Endpoints (Epic 03)

| Endpoint                     | Purpose                                                | Errors (`code`)                                                      |
| ---------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- |
| `POST /api/v1/auth/register` | account + personal workspace + session                 | `AUTH_EMAIL_TAKEN`                                                   |
| `POST /api/v1/auth/login`    | credentials → new session (new token family)           | `AUTH_INVALID_CREDENTIALS`                                           |
| `POST /api/v1/auth/refresh`  | rotate refresh token within its family                 | `AUTH_INVALID_REFRESH_TOKEN`, `AUTH_REFRESH_REUSED` (family revoked) |
| `POST /api/v1/auth/logout`   | revoke session (`?all=true`: whole family), always 204 | —                                                                    |
| `GET /api/v1/me`             | profile + workspaces (Bearer access token)             | `AUTH_INVALID_TOKEN`, `AUTH_TOKEN_EXPIRED`                           |

Access tokens are 15-minute JWTs; refresh tokens are opaque, 30-day, stored only as keyed
hashes, and rotate on every refresh (reuse burns the family). Auth routes share a stricter
per-IP rate limit (`RATE_LIMIT_AUTH_MAX`, default 10/min).

Core-domain endpoints (projects/tags/tasks/notes, Epics 04–05) document their error codes in
their route files under `src/routes/`.

## Sync (Epic 06 — server core)

| Endpoint                 | Purpose                                                                                   |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| `GET /api/v1/sync/pull`  | changes since a workspace revision — coalesced snapshots + tombstones, `hasMore` batching |
| `POST /api/v1/sync/push` | idempotent offline mutation batches; per-mutation `applied`/`conflict`/`rejected` results |

Push conflict policy: field-level last-write-wins for metadata (only FOREIGN writers
conflict; the newer wall clock wins per field), document-level lock for note content.
`SYNC_*` error codes are listed in `src/routes/sync.js`.

Live updates (OPH-057): a Socket.IO server on the same listener. Authenticate the
handshake with `auth: { token: <access token> }`; you are joined to a room per workspace
membership and receive `sync:changed {workspaceId, toRevision}` after every committed
write — respond by pulling. Notification devices (OPH-060, Epic 07):
`PUT/GET/DELETE /api/v1/notification-devices[/:id]` register/heartbeat/unregister an
install; delivery strategy is documented in
[docs/NOTIFICATIONS.md](../../docs/NOTIFICATIONS.md).

## Layout

```txt
src/app.js         buildApp() factory — plugins + routes (used by tests via app.inject)
src/server.js      entrypoint: listen + graceful shutdown
src/config.js      env → frozen config (loads .env from repo root and/or apps/api)
src/plugins/       mysql (knex), redis (ioredis), auth (JWT sign/verify) — accept test overrides
src/routes/        health, auth — register (login/refresh/… land per docs/TASKS.md epics)
src/lib/           ids (ULID), passwords (argon2id), tokens (opaque refresh), slug, async helpers
src/db/            shared knex config (runtime + knexfile.js/CLI)
migrations/        knex migrations — append-only (AGENTS.md rule 8)
test/unit/         no infra needed (stubbed db/redis)
test/integration/  real MySQL+Redis (INTEGRATION=1; CI always runs these)
```
