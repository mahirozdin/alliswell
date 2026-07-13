# Contributing to AllisWell

Thanks for considering a contribution! This project is developed by humans **and AI agents**
following the same rules — everything you need is in [AGENTS.md](AGENTS.md).

## Ground rules (short version)

- Backend is **JavaScript only** (Node.js, ESM). TypeScript is not accepted (CI enforces it).
- Canonical database is **MySQL** via knex migrations (append-only).
- The client is **one Flutter codebase** for all platforms.
- Every change ships with tests and doc updates (TASKS/STATE/CHANGELOG).
- Commit style: [Conventional Commits](https://www.conventionalcommits.org) —
  `feat(api): add task snooze endpoint (OPH-035)`.

## Getting started

```bash
git clone <repo> && cd alliswell
cp .env.example .env
docker compose up -d mysql redis
npm install
npm run db:migrate
npm run dev          # API on :3000
# App:
cd apps/app && flutter pub get && flutter run
```

## Picking work

1. Check [docs/TASKS.md](docs/TASKS.md) — tasks are ordered; unchecked boxes are open.
2. Comment on / open an issue so work isn't duplicated.
3. For anything architectural, propose an ADR first ([docs/adr/template.md](docs/adr/template.md)).

## Pull request checklist

- [ ] `npm run lint`, `npm run format:check`, `npm test` pass (API changes)
- [ ] `npm run test:integration` passes locally with compose infra up (or rely on CI)
- [ ] `flutter analyze` + `flutter test` pass (app changes)
- [ ] Tests added/updated for the change
- [ ] Docs updated: `docs/TASKS.md` checkbox, `docs/STATE.md`, `CHANGELOG.md` (+ ADR if needed)
- [ ] Conventional commit message with task id

## Reporting bugs / requesting features

Use the issue templates. For security issues **do not open a public issue** — see
[SECURITY.md](SECURITY.md).

## Code of Conduct

Be excellent to each other — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
