# AGENTS.md — Operating manual for AI agents (and humans)

This repository is designed to be developed incrementally by AI coding agents.
**Read this file before touching any code.** It defines the hard rules, the workflow, and the
definition of done. The product spec lives in [docs/BLUEPRINT.md](docs/BLUEPRINT.md); the backlog
in [docs/TASKS.md](docs/TASKS.md); the current position in [docs/STATE.md](docs/STATE.md).

---

## 1. Hard rules (non-negotiable)

1. **Backend is JavaScript only.** Node.js, ESM (`type: module`). **TypeScript is forbidden** —
   no `.ts` files, no `tsc`, no type-only tooling. CI enforces this (`npm run check:no-ts`).
   Use JSDoc comments for editor type hints where helpful.
2. **Database is MySQL** (8.x), accessed through **knex** + **mysql2**. No ORMs, no other databases
   for canonical data. Redis is for queues/cache/realtime fanout only.
3. **All client platforms are one Flutter codebase** (`apps/app`). No secondary web framework
   unless a task explicitly justifies it with an ADR.
4. **Every feature ships with tests.** API: Vitest (unit + integration). App: `flutter test`.
   A task is not done if `npm test` or `flutter test` fails.
5. **Every task updates the docs.** At minimum: check the box in `docs/TASKS.md`, update
   `docs/STATE.md`, add a `CHANGELOG.md` entry. Update `docs/ARCHITECTURE.md` when structure changes.
6. **Architectural decisions require an ADR** in `docs/adr/` (use the template). Examples: new
   dependency category, schema redesign, protocol change, security-relevant choice.
7. **Never commit secrets.** `.env` is gitignored; only `.env.example` is committed, with
   placeholder values. OAuth tokens are stored encrypted (see BLUEPRINT §15.3).
8. **Migrations are append-only.** Never edit an applied migration; create a new one.
   Naming: `YYYYMMDDHHMMSS_verb_subject.js` with ESM `export async function up/down(knex)`.
9. **Conventional Commits.** `feat(api): …`, `fix(app): …`, `docs: …`, `chore: …`, `ci: …`,
   `refactor(api): …`, `test(api): …`. Scope is `api`, `app`, or omitted for repo-wide.
10. **Do risky things in writing first.** Large refactors and data migrations get a short plan
    (in the task section of `docs/TASKS.md` or an ADR) *before* implementation.
11. **One design system, forever.** All UI follows the "AllisWell Glass" design language defined
    in [docs/DESIGN.md](docs/DESIGN.md) (ADR-0005) — **visual continuity is mandatory for every
    future feature**, screen and platform. Concretely: colors/spacing/radii come from
    `apps/app/lib/src/theme/` tokens (no raw hex or `Colors.*` in widgets), glass/blur is
    chrome-only (never under body text), text contrast ≥ 4.5:1 and icon/border contrast ≥ 3:1 in
    BOTH themes (`python3 scripts/design/contrast.py` must pass after palette edits), tap targets
    ≥ 44 px, and every UI change is checked in light *and* dark before it is done. Deviations
    require amending docs/DESIGN.md in the same change.

## 2. The "do the next task" protocol

When the user says **“do the next task”** / **“sıradaki işi yap”** (or similar):

1. **Locate position.** Read `docs/STATE.md` → “Next task”. Cross-check `docs/TASKS.md`
   (first unchecked `[ ]` task in the current epic; epics are ordered).
2. **Understand scope.** Read the task's checklist, acceptance criteria and tests. Read the
   relevant BLUEPRINT sections. Look at existing code — reuse existing helpers and patterns.
3. **Implement** the task fully, following the hard rules above. Small, cohesive diffs.
4. **Verify.** Run `npm run lint`, `npm test` (and `npm run test:integration` when infra is
   running; `flutter analyze` + `flutter test` for app changes). Fix what breaks.
5. **Document.** Mark the task `[x]` in `docs/TASKS.md`, update `docs/STATE.md` (last completed,
   next task, any new notes/risks), add a `CHANGELOG.md` line, update other docs if needed.
6. **Commit** with a Conventional Commit message referencing the task id, e.g.
   `feat(api): add register endpoint (OPH-020)`.
7. **Report** briefly: what was done, how it was verified, what is next.

Never skip ahead (dependencies are encoded in epic order). If a task is blocked, record why in
`docs/STATE.md` → “Blocked / notes”, pick the next unblocked task, and tell the user.

## 3. Definition of Done (checklist)

- [ ] Code follows hard rules (JS-only backend, MySQL, ESM, tests).
- [ ] `npm run lint` + `npm run format:check` pass.
- [ ] `npm test` passes; integration tests pass if infra available (they always run in CI).
- [ ] For app changes: `flutter analyze` and `flutter test` pass.
- [ ] New/changed endpoints have Ajv JSON schemas (request + response).
- [ ] DB changes shipped as a new knex migration (with `down`).
- [ ] Docs updated: TASKS checkbox, STATE, CHANGELOG (+ ADR/ARCHITECTURE when relevant).
- [ ] Conventional commit created.

## 4. Code conventions

### Backend (`apps/api`)

- ESM imports with `.js` extensions; Node built-ins via `node:` prefix.
- Prettier (single quotes, width 100) + ESLint — run `npm run format` before committing.
- Fastify plugins live in `src/plugins/`, routes in `src/routes/` (one file per resource,
  registered with a prefix), shared helpers in `src/lib/`, DB helpers in `src/db/`.
- Every route declares an Ajv schema (`body`, `querystring`, `params`, `response`).
- Errors: use `@fastify/sensible` (`app.httpErrors.badRequest(...)`) + stable machine-readable
  `code` fields (e.g. `AUTH_INVALID_CREDENTIALS`). Never leak internals in error messages.
- IDs are **ULIDs** (`CHAR(26)`), generated via `src/lib/ids.js`. Timestamps are UTC `DATETIME(3)`;
  the API serializes ISO-8601 strings.
- Soft delete via `deleted_at`; queries must filter `whereNull('deleted_at')` unless explicitly
  including deleted rows.
- Any write to a synced entity (project/task/tag/note/…) must bump its `revision` and insert a
  `sync_revisions` row **in the same transaction** (Epic 06 provides the helper; use it).
- No N+1 queries: batch with `whereIn`, join, or a single aggregate query.

### App (`apps/app`)

- Riverpod for state, go_router for navigation, feature-first folders under `lib/src/features/`.
- Keep widgets small; extract reusable UI to `lib/src/widgets/`.
- `dart format .` before committing; zero `flutter analyze` warnings.
- **UI = docs/DESIGN.md.** Theme/tokens live in `lib/src/theme/` (`buildAwTheme`, `AwTokens`,
  `AwSpace`/`AwRadius`/`AwMotion`); glass chrome + aurora in `lib/src/widgets/glass.dart`;
  shared empty/error/inline-error states in `lib/src/widgets/status_views.dart` (use them —
  don't hand-roll new ones). Lists are card rows with `awListPadding(context)`; favorite/pin
  stars use `AwTokens.warning`; priority colors only via `taskPriorityColor*` helpers.

## 5. Testing strategy

| Layer | Tool | Location | Needs infra? |
| --- | --- | --- | --- |
| API unit | Vitest + `app.inject()` | `apps/api/test/unit/` | No (stub db/redis via `buildApp({ db, redis })`) |
| API integration | Vitest | `apps/api/test/integration/` | Yes (MySQL+Redis; `npm run test:integration`) |
| App widget/unit | flutter_test | `apps/app/test/` | No |

CI (`.github/workflows/ci.yml`) runs all of the above with real MySQL/Redis service containers
and runs migrations first — schema errors surface in CI even if local Docker is unavailable.

## 6. Sync & calendar invariants (read before touching those modules)

- MySQL is canonical; clients hold replicas. Every workspace has a monotonic `revision`.
- Client pushes carry `clientMutationId` — the server must be **idempotent** (`client_mutations`
  table records processed ids).
- Conflict policy: field-level last-write-wins for metadata; document-level optimistic lock +
  conflict copy for notes (v1). See BLUEPRINT §6.5.
- Calendar mapping keys: Google `extendedProperties.private.alliswell_task_id` /
  `alliswell_workspace_id`; Apple events carry `alliswell://task/{taskId}` in the URL field.
  The `calendar_event_links` table is the source of truth for mapping (see ADR-0003).
- Notification payloads carry IDs only, never task content (privacy — BLUEPRINT §8.3).

## 7. Repository map

```txt
apps/api/src/app.js        # buildApp() — register plugins/routes (testable factory)
apps/api/src/server.js     # entrypoint (listen + graceful shutdown)
apps/api/src/config.js     # env → validated config object
apps/api/src/plugins/      # mysql (knex), redis (ioredis), …
apps/api/src/routes/       # health, (auth, workspaces, projects, tasks, notes… per epics)
apps/api/migrations/       # knex migrations (append-only)
apps/app/lib/src/          # app.dart, router.dart, screens/, (features/ as epics land)
docs/TASKS.md              # THE backlog — always keep in sync with reality
docs/STATE.md              # THE pointer — always update before ending a session
```

## 8. When in doubt

- Prefer the BLUEPRINT; where reality diverged, ADRs win (they document deliberate deviations).
- Prefer boring, proven solutions; this is infrastructure people will self-host.
- Ask the user only when a decision is truly product-level (pricing of trade-offs unclear);
  otherwise decide, document (ADR/STATE note), and move.
