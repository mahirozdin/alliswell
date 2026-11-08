# Developing AllisWell

> Last updated: 2026-11-08 — OPH-411 moved this out of the README's first screen.

Building from source, the architecture, the everyday commands, every document, and how the AI
agents that write much of the code are kept on rails. Using the app or running your own copy:
the [README](../../README.md).

## Architecture

```txt
Flutter App (iOS / Android / macOS / Windows / Linux / Web)
      │  REST + WebSocket (Socket.IO)   ·   offline-first local SQLite replica
      ▼
Node.js API — Fastify, JavaScript only (no TypeScript)
  ├─ Auth (JWT + refresh rotation)     ├─ Sync engine (revision log, outbox)
  ├─ Projects / Tasks / Tags           ├─ Reminder scheduler
  ├─ Notes / Files (presigned R2/S3)   ├─ Calendar sync workers (BullMQ)
  ├─ Recurrence engine (task_series)   ├─ Remote MCP server (OAuth 2.1)
  └─ Search (accent folding)           └─ AI providers (BYOK, 5 adapters)
      │
      ├─ MySQL 8.4 / MariaDB 10.11+  (canonical data)
      ├─ Redis 8    (queues, Socket.IO fan-out, cache)
      ├─ Object storage: Cloudflare R2 / any S3 (attachments)
      └─ Calendar providers: Google Calendar API · Apple EventKit · CalDAV (iCloud, Nextcloud…)
```

The monorepo:

| Path                                             | What it is                                                      |
| ------------------------------------------------ | --------------------------------------------------------------- |
| [`apps/api`](../../apps/api)                           | Fastify backend — JavaScript only, MySQL via knex               |
| [`apps/app`](../../apps/app)                           | The Flutter app — all six platforms, one codebase               |
| [`apps/landing`](../../apps/landing)                   | The marketing site — Vue 3 + Vite, at the root of alliswell.space |
| [`scripts/seed-demo.mjs`](../../scripts/seed-demo.mjs) | The demo workspace every screenshot is shot from                |
| [`scripts/screenshots/`](../../scripts/screenshots)    | Screenshot + store-asset pipeline                               |

Details: [docs/ARCHITECTURE.md](../ARCHITECTURE.md) • Design decisions: [docs/adr/](../adr/)

## Quickstart

Prerequisites: **Node.js ≥ 22**, **Docker**, **Flutter ≥ 3.44** (for the app).

```bash
git clone https://github.com/mahirozdin/alliswell.git
cd alliswell

# 1. Infra: MySQL + Redis (+ MinIO for attachments)
cp .env.example .env
docker compose up -d mysql redis

# 2. API
npm install
npm run db:migrate
npm run dev              # → http://localhost:3000  (health: /health/ready)

# 3. Flutter app
cd apps/app
flutter pub get
flutter run -d chrome    # or: macos / windows / an emulator
```

Want the app full of realistic data in one command?

```bash
npm run seed:demo        # demo@alliswell.space / AllisWellDemo2026
```

Run everything in containers instead: `docker compose --profile full up`.
Optional DB admin UI: `docker compose --profile tools up -d adminer` → http://localhost:8080.

**Optional integrations** (all off until configured, see [.env.example](../../.env.example)):
Google Calendar (`GOOGLE_*`), file attachments via Cloudflare R2 / any S3 (`STORAGE_S3_*`),
and AI (`AI_*` — off by default; see [docs/AI.md](../AI.md)).

### Useful commands

| Command                              | What it does                                    |
| ------------------------------------ | ----------------------------------------------- |
| `npm run dev`                        | Start API with watch mode                       |
| `npm test`                           | API unit tests (no infra needed)                |
| `npm run test:integration`           | API integration tests (needs MySQL+Redis)       |
| `npm run seed:demo`                  | Fill a running instance with the demo workspace |
| `npm run shots:web`                  | Regenerate the web screenshots                  |
| `npm run landing:dev`                | Run the marketing site locally                  |
| `npm run lint` / `npm run format`    | ESLint / Prettier                               |
| `npm run db:migrate` / `db:rollback` | Knex migrations                                 |
| `npm run check:no-ts`                | Enforce the JavaScript-only policy              |
| `npm run check:i18n`                 | Enforce no hardcoded UI strings (localisation)  |
| `npm run next`                       | Print the next task from docs/TASKS.md          |
| `npm run verify:task -- <tests>`     | The narrow check for the change in hand (K1)    |
| `npm run verify:batch`               | Everything CI checks, once, before a push (K2)  |

Every command, with its flags: [commands.md](commands.md).

## Documentation

| Doc                                                                                      | Purpose                                                                                   |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| [docs/COMPARISON.md](../COMPARISON.md)                                                 | Full feature inventory + honest comparison with Google, Apple, Things 3 and the self-hosted alternatives (Vikunja, Super Productivity, Tasks.org, Nextcloud Tasks) |
| [docs/BLUEPRINT.md](../BLUEPRINT.md)                                                   | Product vision, domain model, full functional spec (TR)                                   |
| [docs/ARCHITECTURE.md](../ARCHITECTURE.md)                                             | System architecture, stack, sync &amp; calendar design                                    |
| [docs/SELF-HOSTING.md](../SELF-HOSTING.md)                                             | Run your own instance with Docker: TLS, upgrades, backups, storage                        |
| [docs/AI.md](../AI.md) · [docs/MCP.md](../MCP.md)                                    | AI providers &amp; consent · the remote MCP connector                                     |
| [docs/API.md](../API.md) · [live](https://alliswell.space/docs/api)                     | The REST API &amp; personal API keys: every endpoint with examples, plus a Postman collection |
| [docs/FIREBASE.md](../FIREBASE.md)                                                     | Analytics, Crashlytics, Performance — optional, and how to point them at **your** project |
| [docs/ATTACHMENTS.md](../ATTACHMENTS.md)                                               | File attachments: R2/S3 storage, presigned flow, CORS setup                               |
| [docs/MARKDOWN.md](../MARKDOWN.md)                                                     | The markdown workspace: field survey, feature scope, document model                       |
| [docs/NOTIFICATIONS.md](../NOTIFICATIONS.md)                                           | Exact-time / urgent alarm delivery research &amp; plan                                    |
| [docs/WIDGETS.md](../WIDGETS.md)                                                       | Home-screen widget architecture                                                           |
| [docs/SCREENSHOTS.md](../SCREENSHOTS.md)                                               | How every image in this repo is produced                                                  |
| [docs/STORE-LISTING.md](../STORE-LISTING.md)                                           | App Store &amp; Play copy, asset sizes, claim guardrails                                  |
| [ROADMAP.md](../../ROADMAP.md)                                                                 | Phase-by-phase roadmap: shipped, next, and v2 parking lot                                 |
| [docs/TASKS.md](../TASKS.md) · [docs/STATE.md](../STATE.md)                          | Open OPH-xxx tasks · live development state                                               |
| [CHANGELOG.md](../../CHANGELOG.md)                                                             | What changed, per release                                                                 |
| [docs/adr/](../adr/)                                                                   | Architecture Decision Records                                                             |
| [AGENTS.md](../../AGENTS.md) · [CONTRIBUTING.md](../../CONTRIBUTING.md) · [SECURITY.md](../../SECURITY.md) | Workflow, contributing &amp; security policy                                              |

## Built to be developed by AI agents

This repository is designed for continuous development by AI coding agents:

1. `npm run next` prints the **next task** ([docs/STATE.md](../STATE.md) names it too).
2. Say **"do the next task"** (Turkish: _"sıradaki işi yap"_).
3. The agent follows [AGENTS.md](../../AGENTS.md): implement → its own tests (`verify:task`) → update docs → remove the finished task from [docs/TASKS.md](../TASKS.md) → update STATE → commit; the full set (`verify:batch`) runs once before a push.
4. For a run of many tasks, a phase workflow takes a whole epic ([docs/development/workflow.md](workflow.md)): a fresh agent per task, then the full set, a smoke run and a review once at the end.

The markdown files (STATE / TASKS / CHANGELOG) are the single source of truth — no external board required.
The working notes (STATE, TASKS, LESSONS, much of BLUEPRINT) are written in Turkish; the public
documents are in English.

