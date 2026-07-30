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

## Licensing of contributions

AllisWell is **source-available**, not open source: it is licensed under
[PolyForm Noncommercial 1.0.0](LICENSE). Free for personal use, self-hosting,
study, charities, schools and public bodies; commercial use needs a licence from
**info@bubiapps.com**. The reasoning is in
[ADR-0024](docs/adr/0024-license-polyform-noncommercial.md).

**By opening a pull request you agree that your contribution is licensed under
those same terms, and that the project owner may also license the combined work
commercially.** That second clause is what makes the commercial licence possible
at all — without it, a single contributed line would block it. If you are not
comfortable with that, please say so in the issue before writing code; a bug
report or a reproduction is just as valuable and carries no such condition.

Nothing here changes what you can do with the software: fork it, run it, modify
it, and keep your fork — all free, for any noncommercial purpose.
