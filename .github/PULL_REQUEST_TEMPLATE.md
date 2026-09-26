## What & why

<!-- Short description. Link the task id (OPH-xxx) and/or issue. -->

Task: OPH-

## Checklist (Definition of Done — see AGENTS.md §3)

- [ ] JavaScript-only backend policy respected (no `.ts` files)
- [ ] `npm run verify:batch` passes (lint, format, gates, API unit + integration, Flutter when the
      app changed) — or name what you ran instead
- [ ] Tests added/updated
- [ ] DB changes are a new knex migration (append-only, with `down`)
- [ ] Docs updated: finished task removed from `docs/TASKS.md`, `docs/STATE.md` updated in place,
      `CHANGELOG.md` (+ ADR / `docs/LESSONS.md` if relevant); `npm run check:docs` passes
- [ ] Conventional commit(s)

## How was this verified?

<!-- Commands run, screenshots for UI, curl examples for API. -->
