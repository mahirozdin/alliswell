# Commands

> Last updated: 2026-10-18 — [ADR-0060](../adr/0060-phase-workflow-and-a-light-root-contract.md)

Run from the repo root. `check:docs` fails when the agent contract names a script that is not
in `package.json`.

## Work and verification

| Command | What |
| --- | --- |
| `npm run next` | the next task (`-- --list`, `-- --summary`, `-- --phase E35`, `-- --only OPH-401`, `-- --json`, `-- --check-budget`) |
| `npm run verify:task -- <tests>` | K1 — the change in hand |
| `npm run verify:batch` | K2 — the full set since the last push (`-- --list` plan, `-- --all`) |
| `npm run verify:smoke` | K2 — the API runs end to end, the web bundle boots (`-- --web` builds it) |
| `npm run check:docs` | version claims, links, working-doc and root-contract budgets, STATE pointer |

## Development

| Command | What |
| --- | --- |
| `docker compose up -d mysql redis minio radicale` | local services |
| `npm run db:migrate` / `npm run db:rollback` | migrations |
| `npm run dev` / `npm run start` | API (watch / plain) |
| `npm run lint` · `npm run format` · `npm run format:check` | ESLint / Prettier (API) |
| `npm run test` · `npm run test:integration` | API suites |
| `cd apps/app && flutter analyze && flutter test` | app |
| `npm run seed:demo` | demo data for screenshots |
| `npm run landing:dev` · `npm run landing:build` | landing site |

## Gates (each also runs inside `verify:*` when its input changes)

`npm run check:no-ts` · `npm run check:no-ee` · `npm run check:i18n` · `npm run check:pages` ·
`npm run check:copy` · `npm run check:fab` · `npm run check:opacity` ·
`npm run check:push-payload` · `npm run check:notify-matrix` · `npm run check:openapi` ·
`npm run check:apidocs` · `npm run check:postman` · `npm run check:sync-fields` ·
`npm run check:search-reachable`

## Generators

`npm run gen:sync-fields` · `npm run openapi` · `npm run api:docs` · `npm run shots:web` ·
`npm run shots:store` · `npm run shots:ee`

## Health of a checkout

- `git status --short` clean before a phase; someone else's change is left alone and reported.
- `npm run next -- --summary` — anything ready? `npm run next -- --check-budget` — docs in budget?
- `gh run list -L 3` — the last CI runs (read, never waited on inside a phase).
