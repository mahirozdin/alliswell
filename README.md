# AllisWell — Open-Source, Self-Hosted Productivity Hub

**Tasks, projects, notes and urgent reminders in one app — with true two-way Google & Apple
Calendar sync.** One codebase for iOS, Android, Web, macOS, Windows and Linux.

AllisWell is a free, open-source, self-hostable alternative to Apple Reminders, Todoist,
TickTick, Things 3 and Notion — your data lives in **your own MySQL database**, not someone
else's cloud.

[![CI](https://github.com/mahirozdin/alliswell/actions/workflows/ci.yml/badge.svg)](https://github.com/mahirozdin/alliswell/actions/workflows/ci.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-brightgreen)](LICENSE)
[![Backend: JavaScript](https://img.shields.io/badge/Backend-Node.js_(JavaScript_only)-yellow)](AGENTS.md)
[![App: Flutter](https://img.shields.io/badge/App-Flutter_(6_platforms)-02569B)](apps/app)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-orange)](CONTRIBUTING.md)

> ⚠️ **Status: early development.** The foundation (API skeleton, full database schema,
> app shell, CI) is in place; features are landing epic by epic — see the
> [backlog](docs/TASKS.md) and [current state](docs/STATE.md). Star/watch the repo to follow along.

**AllisWell** combines the best ideas of the tools we love but can't fully own:

| Inspiration | What we take from it |
| --- | --- |
| Apple Reminders | Instant capture, date/time alarms, subtasks, smart lists |
| Things 3 | Inbox / Today / Upcoming / Anytime / Someday flow, projects & areas |
| Todoist | Labels, priorities, filters, calendar layout, cross-platform discipline |
| TickTick | Calendar-first planning, kanban/timeline views, rich task notes |
| Notion | Project document pages, block content, notes as a knowledge base |

…and adds what none of them give you: **open source, self-hosted, true two-way calendar sync
(Google + Apple), and a local-first realtime sync engine.**

> 🇹🇷 Bu proje Türkçe bir ürün vizyonuyla başladı — tam vizyon dokümanı için
> [docs/BLUEPRINT.md](docs/BLUEPRINT.md) dosyasına bakın.

---

## ✨ Planned feature set (MVP scope)

- ⚡ **Fast capture** — add a task in seconds, with or without a date.
- 🗂 **Projects** — RGB color, icon, status, favorites; tasks and notes attach to projects.
- 🏷 **Tags & priorities** — colored labels, `none → urgent` priority, urgent flag.
- 🔔 **Urgent reminders** — alarm-grade notifications with snooze actions (5m / 30m / 1h / tomorrow / custom).
- 📝 **Notes & documents** — rich-text notes (Quill Delta), linkable to tasks/projects, Notion-like project doc pages.
- 📅 **Two-way calendar sync** — tasks mirror into Google Calendar (extended-properties mapping, webhooks, incremental sync) and Apple Calendar (EventKit bridge; CalDAV later).
- 🔄 **Local-first sync** — offline work, mutation outbox, revision log, idempotent push, WebSocket live updates.
- 🖥 **One Flutter codebase** — iOS, Android, Web, macOS, Windows, Linux.
- 🔓 **Self-hosted** — your data in your MySQL, one `docker compose up`.

**Status: v0.1.0 — the MVP is complete through Phase 4 (calendar sync).** See the
[roadmap](ROADMAP.md) for the phase-by-phase picture, live progress in
[docs/STATE.md](docs/STATE.md), and the full backlog in [docs/TASKS.md](docs/TASKS.md).

## 🏗 Architecture

```txt
Flutter App (iOS / Android / macOS / Windows / Linux / Web)
      │  REST + WebSocket (Socket.IO)
      ▼
Node.js API — Fastify, JavaScript only (no TypeScript)
  ├─ Auth (JWT + refresh rotation)     ├─ Sync Engine (revision log, outbox)
  ├─ Projects / Tasks / Tags           ├─ Reminder scheduler
  ├─ Notes / Documents                 ├─ Calendar sync workers
  └─ Notifications                     └─ Audit log
      │
      ├─ MySQL 8.4  (canonical data)
      ├─ Redis 8    (queues, Socket.IO fanout, cache)
      └─ Calendar providers: Google Calendar API · Apple EventKit · CalDAV (v2)
```

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) • Design decisions: [docs/adr/](docs/adr/)

## 📁 Repository layout

```txt
alliswell/
├── apps/
│   ├── api/          # Node.js (JavaScript, ESM) Fastify backend + knex migrations
│   └── app/          # Flutter app (all client platforms)
├── docs/
│   ├── BLUEPRINT.md  # Product vision & full functional spec (source of truth)
│   ├── ARCHITECTURE.md
│   ├── TASKS.md      # Epics & tasks backlog (OPH-xxx) — agents work from here
│   ├── STATE.md      # Current development state — "what's next"
│   └── adr/          # Architecture Decision Records
├── AGENTS.md         # Rules + workflow for AI agents & contributors
├── docker-compose.yml
└── ...
```

## 🚀 Quickstart (development)

Prerequisites: **Node.js ≥ 22**, **Docker**, **Flutter ≥ 3.44** (for the app).

```bash
git clone https://github.com/mahirozdin/alliswell.git
cd alliswell

# 1. Infra: MySQL + Redis
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

Run everything in containers instead: `docker compose --profile full up`.
Optional DB admin UI: `docker compose --profile tools up -d adminer` → http://localhost:8080.

### Useful commands

| Command | What it does |
| --- | --- |
| `npm run dev` | Start API with watch mode |
| `npm test` | API unit tests (no infra needed) |
| `npm run test:integration` | API integration tests (needs MySQL+Redis) |
| `npm run lint` / `npm run format` | ESLint / Prettier |
| `npm run db:migrate` / `db:rollback` | Knex migrations |
| `npm run check:no-ts` | Enforce the JavaScript-only policy |

## 📚 Documentation index

| Doc | Purpose |
| --- | --- |
| [docs/BLUEPRINT.md](docs/BLUEPRINT.md) | Product vision, domain model, full functional spec (TR) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, stack, sync & calendar design |
| [ROADMAP.md](ROADMAP.md) | Phase-by-phase roadmap: what's shipped, what's next, what's v2 |
| [docs/TASKS.md](docs/TASKS.md) | Backlog: epics OPH-001…OPH-095 with acceptance criteria |
| [docs/STATE.md](docs/STATE.md) | Live development state — what is done, what is next |
| [CHANGELOG.md](CHANGELOG.md) | What changed, per release |
| [AGENTS.md](AGENTS.md) | Hard rules & step-by-step workflow for AI agents |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute (humans & agents) |
| [SECURITY.md](SECURITY.md) | Security policy & vulnerability reporting |

## 🤖 AI-agent friendly by design

This repository is built to be developed continuously by AI coding agents:

1. Open [docs/STATE.md](docs/STATE.md) → see the current epic and the **next task**.
2. Say **“do the next task”** (or Turkish: *“sıradaki işi yap”*).
3. The agent follows the protocol in [AGENTS.md](AGENTS.md): implement → test → update docs →
   check the box in [docs/TASKS.md](docs/TASKS.md) → update STATE → commit.

## 🤝 Contributing

Contributions are very welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) and pick a task from
[docs/TASKS.md](docs/TASKS.md). Please open an issue before large changes.

## 📄 License

[AGPL-3.0](LICENSE) — free to use, self-host and modify; if you run a modified version as a
service, you must share your changes. See [ADR-0002](docs/adr/0002-license-agpl-3.0.md) for why.
