# ARCHITECTURE — AllisWell

> How the system is put together and why. Product spec: [BLUEPRINT.md](BLUEPRINT.md).
> Decisions with trade-offs: [adr/](adr/). Keep this file updated when structure changes (AGENTS.md rule 5).

## 1. System overview

```txt
┌────────────────────────────────────────────────────────────┐
│  Flutter app (single codebase)                             │
│  iOS · Android · Web · macOS · Windows · Linux             │
│  Riverpod (state) · go_router (nav) · dio (HTTP)           │
│  drift/SQLite (local replica) · flutter_local_notifications│
│  flutter_secure_storage · platform channel → EventKit      │
└──────────────┬─────────────────────────────────────────────┘
               │ REST /api/v1 (JSON, Ajv-validated)
               │ WebSocket (Socket.IO) — change notifications
┌──────────────▼─────────────────────────────────────────────┐
│  apps/api — Node.js (JavaScript ESM, NO TypeScript)        │
│  Fastify 5 · pino logs (request-id) · JWT auth             │
│  ├─ routes/    auth, workspaces, projects, tasks, tags,    │
│  │             notes, sync, integrations, health           │
│  ├─ plugins/   mysql(knex) · redis(ioredis) · auth · io    │
│  ├─ lib/       ids(ULID) · errors · revision helper        │
│  └─ workers/   BullMQ jobs: reminders, calendar sync (Ep.8)│
└───────┬───────────────────────────────┬────────────────────┘
        │                               │
┌───────▼────────┐              ┌───────▼────────┐
│ MySQL 8.4      │              │ Redis 8        │
│ canonical data │              │ BullMQ queues  │
│ knex migrations│              │ Socket.IO fanout│
└────────────────┘              └────────────────┘
        │
        └─ Calendar providers: Google Calendar API (OAuth, webhooks, incremental sync)
                               Apple EventKit (on-device bridge) · CalDAV (v2)
```

## 2. Monorepo layout

| Path | What lives here |
| --- | --- |
| `apps/api` | Fastify backend, knex migrations, Vitest tests |
| `apps/app` | Flutter app for all six platforms |
| `docs/` | Blueprint, this file, TASKS/STATE, ADRs |
| `scripts/` | Repo tooling (policy checks) |
| `.github/` | CI workflows, issue/PR templates |

npm workspaces manage the JS side (`npm install` at root). The Flutter app is managed by its own
`pubspec.yaml` (not part of npm workspaces).

## 3. Backend design

- **Factory pattern:** `buildApp({ config, logger, db, redis })` returns a configured Fastify
  instance. Tests inject stub `db`/`redis`; production uses real connections. `server.js` is a
  thin entrypoint with graceful shutdown (close-with-grace).
- **Config:** `src/config.js` reads env (with `.env` from repo root and/or `apps/api`), applies
  defaults, validates, freezes. No other module reads `process.env` directly.
- **Plugins:** connection lifecycles are Fastify plugins (`src/plugins/mysql.js`, `redis.js`)
  decorating `app.db` (knex) and `app.redis` (ioredis). Boot never hard-fails on missing infra —
  `/health/ready` reports degraded state instead (good for orchestrators and local dev).
- **Validation:** every route ships Ajv JSON schemas for body/query/params/response.
- **Errors:** `@fastify/sensible` HTTP errors + stable `code` strings (e.g. `AUTH_EMAIL_TAKEN`).
- **Observability:** pino structured logs with `x-request-id` propagation; `/health/live` and
  `/health/ready` (component-level status). Metrics endpoint is a v2 task.
- **Security baseline:** helmet, CORS allowlist, global rate limit (tighter on auth routes),
  argon2id password hashing, JWT (15 min) + rotating opaque refresh tokens stored hashed,
  encrypted OAuth tokens (AES-256-GCM), soft-delete-aware queries.

## 4. Data layer

- MySQL 8.4, utf8mb4. IDs are **ULID** `CHAR(26)` (sortable, no coordination — ADR-0004).
- All timestamps `DATETIME(3)` in UTC; user timezones stored per user/task for alarm math.
- Soft delete via `deleted_at`. Synced entities carry `revision BIGINT`.
- FULLTEXT indexes on tasks(title, description) and notes(title, plain_text) for search.
- Migrations: knex, append-only, ESM `up`/`down`. Full table list in [TASKS.md](TASKS.md) Epic 02.

## 5. Sync engine (live end to end — socket fanout is the remainder)

Per BLUEPRINT §6: workspace-scoped monotonic revision log (`sync_revisions`; the
`recordSyncWrite`/`withRevision` helper in `apps/api/src/db/sync.js` runs inside every entity
write's transaction). `GET /api/v1/sync/pull` streams batched snapshots + delete tombstones
since a revision, coalesced to each entity's latest change. `POST /api/v1/sync/push` applies
client mutation batches idempotently — `client_mutations` records every outcome per
(`clientId`, `clientMutationId`), and replays answer from the record. Conflict policy:
field-level LWW for metadata (foreign changes detected via the changed-fields log with own
writes attributed through recorded result revisions; newer wall clock wins), document-level
optimistic lock for note content (`NOTE_CONTENT_CONFLICT` → client makes a conflict copy).
Still to come (OPH-057): Socket.IO (Redis adapter) broadcasting
`sync:changed {workspaceId, toRevision}`; clients respond by pulling — the socket never carries
entity payloads (keeps ordering and authz in one place: the pull endpoint).

## 6. Calendar sync (Phase 4 — designed, not yet built)

Per BLUEPRINT §7: `calendar_event_links` maps tasks↔events per account. Google: OAuth offline,
`extendedProperties.private.alliswell_task_id`, webhook channels + `syncToken` incremental sync,
BullMQ workers, etag-based conflict detection. Apple: EventKit bridge on-device (platform
channel), URL-field marker `alliswell://task/{id}`; CalDAV connector deferred to v2 (ADR-0003).

## 7. Flutter app design

- **State:** Riverpod. **Navigation:** go_router with `StatefulShellRoute` (adaptive: glass rail
  ≥ 800px, glass bottom bar below). **HTTP:** dio with auth interceptor (Epic 03).
- **Design system ("AllisWell Glass", ADR-0005):** binding spec in [DESIGN.md](DESIGN.md).
  Tokens + hand-tuned contrast-verified `ColorScheme`s in `lib/src/theme/` (`tokens.dart`,
  `theme.dart`); glass chrome + aurora background in `lib/src/widgets/glass.dart`; shared
  empty/error states in `lib/src/widgets/status_views.dart`; palette guard
  `scripts/design/contrast.py`. Widgets never hardcode colors.
- **Local-first (live since OPH-054…056):** drift/SQLite replica (`lib/src/sync/db/`;
  wasm + committed `web/sqlite3.wasm`/`web/drift_worker.js` on web) + `pending_mutations`
  outbox. Feature stores (`features/*/data/*_store.dart`) write optimistically and enqueue
  in one transaction; `SyncEngine` pushes in order (backoff on failure) and pulls
  snapshots/tombstones; conflicts surface via a stream (note content → "çakışan kopya").
  UI subscribes to local DB streams — no REST calls from screens (auth + `/me` aside).
- **Notifications (Phase 3):** flutter_local_notifications scheduled from local data; push (FCM)
  only as a supplementary wake-up. Urgent alarms use action buttons (complete/snooze presets).
- Feature-first folders: `lib/src/features/<domain>/{data,providers,ui}` as epics land.

## 8. Quality gates

- CI (GitHub Actions): ESLint + Prettier check, TypeScript-ban guard, Vitest unit tests,
  knex migrations against a real MySQL 8.4 service, integration tests (real MySQL+Redis),
  `flutter analyze` + `flutter test`.
- Definition of Done: [../AGENTS.md](../AGENTS.md) §3.
