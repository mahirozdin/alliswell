## What & why

<!-- Short description. Link the task id (OPH-xxx) and/or issue. -->

Task: OPH-

## Checklist (Definition of Done — see AGENTS.md §3)

- [ ] JavaScript-only backend policy respected (no `.ts` files)
- [ ] `npm run lint` + `npm run format:check` pass
- [ ] `npm test` passes (+ `npm run test:integration` if infra-affecting)
- [ ] `flutter analyze` + `flutter test` pass (if app changed)
- [ ] Tests added/updated
- [ ] DB changes are a new knex migration (append-only, with `down`)
- [ ] Docs updated: `docs/TASKS.md`, `docs/STATE.md`, `CHANGELOG.md` (+ ADR if architectural)
- [ ] Conventional commit(s)

## How was this verified?

<!-- Commands run, screenshots for UI, curl examples for API. -->
