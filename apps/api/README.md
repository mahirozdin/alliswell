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
