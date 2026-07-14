# STATE — Live development state

> This file is the pointer for the "do the next task" (TR: _"sıradaki işi yap"_) workflow.
> Always read it first; always update it before finishing a session. Backlog: [TASKS.md](TASKS.md).

**Last updated:** 2026-07-14 (bootstrap + public release)

**Repository:** https://github.com/mahirozdin/alliswell (public) — CI green since the first push
([run #1](https://github.com/mahirozdin/alliswell/actions)): migrations apply/rollback/re-apply
against real MySQL 8.4 and all unit+integration tests pass.

## Snapshot

| | |
| --- | --- |
| Current phase | Phase 1 — Core domain |
| Current epic | **Epic 03 — Auth** |
| ➡️ **Next task** | **OPH-020 — Register endpoint** |
| Last completed | Epic 01 (OPH-001…007), Epic 02 (OPH-010…015), OPH-090…093 |

## Recently completed

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
- `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` env vars are placeholders in `.env.example`;
  OPH-020 must read them from config and refuse to boot in production with defaults.
- Apple EventKit work (OPH-077+) requires macOS/Xcode signing setup on the dev machine.

## Environment assumptions

- Node ≥ 22 (dev machine: v25), Flutter 3.44 / Dart 3.12, Docker Desktop with compose v2.
- Local infra: `docker compose up -d mysql redis` then `npm run db:migrate`.

## How to continue (for agents)

1. Read [../AGENTS.md](../AGENTS.md) §2 (protocol) if you haven't.
2. Implement **OPH-020** per its checklist in [TASKS.md](TASKS.md).
3. Verify (`npm run lint && npm test`, integration tests if infra up), document, commit,
   then update this file's Snapshot + Recently completed.
