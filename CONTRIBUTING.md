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
git clone https://github.com/mahirozdin/alliswell.git && cd alliswell
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

## Translating (adding a language)

The app's UI strings live in JSON locale files — **adding a language needs no Dart**:

1. Copy `apps/app/assets/i18n/en.json` (the base/fallback) to
   `apps/app/assets/i18n/<code>.json` (e.g. `de.json`) and translate the values.
   Missing keys fall back to English, so a partial translation is fine to ship.
2. Register the locale in `apps/app/lib/src/i18n/i18n.dart`: add `Locale('de')`
   to `awSupportedLocales` and its native name to `awLanguageEndonyms`.
3. `flutter run` — the language shows up in **Settings → Language**, and the
   device/browser language auto-selects it (English is the fallback).

Never hardcode a user-facing string in Dart — wrap it in `'some.key'.tr()` and add
the key to the JSON files. CI enforces this (`npm run check:i18n`). See
[ADR-0009](docs/adr/0009-localization-i18n-architecture.md).

## Pull request checklist

- [ ] `npm run lint`, `npm run format:check`, `npm test` pass (API changes)
- [ ] `npm run test:integration` passes locally with compose infra up (or rely on CI)
- [ ] `flutter analyze` + `flutter test` pass (app changes)
- [ ] No hardcoded UI strings — `npm run check:i18n` (app changes)
- [ ] Tests added/updated for the change
- [ ] Docs updated: `docs/TASKS.md` checkbox, `docs/STATE.md`, `CHANGELOG.md` (+ ADR if needed)
- [ ] Conventional commit message with task id

## Reporting bugs / requesting features

Use the issue templates. For security issues **do not open a public issue** — see
[SECURITY.md](SECURITY.md).

## Code of Conduct

Be excellent to each other — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
