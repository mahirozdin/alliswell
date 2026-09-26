# AGENTS.md — Operating manual for AI agents (and humans)

This repository is designed to be developed incrementally by AI coding agents.
**Read this file before touching any code.** It defines the hard rules, the workflow, and the
definition of done. The product spec lives in [docs/BLUEPRINT.md](docs/BLUEPRINT.md); the backlog
in [docs/TASKS.md](docs/TASKS.md) (`npm run next` prints its next task); the current position in
[docs/STATE.md](docs/STATE.md). A loop of many tasks follows [LOOP.md](LOOP.md).

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
   A task closes on its own tests (K1, `npm run verify:task`), and nothing is pushed until the
   full set is green (K2, `npm run verify:batch`) — §3.
5. **Every task updates the docs — and keeps them small.** At minimum: delete the finished task
   from `docs/TASKS.md`, update `docs/STATE.md` in place, add a `CHANGELOG.md` entry. Update
   `docs/ARCHITECTURE.md` when structure changes. STATE/TASKS are read every session: they hold
   the pointer, the owner's decisions and open work only — never a log (`check:docs` enforces it).
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
12. **The MCP tool surface and the public API are part of every feature.** When a task adds or
    changes a user-facing capability (an entity, a field, an operation), the same epic must
    extend the remote MCP server (and [docs/MCP.md](docs/MCP.md)) and the key-authenticated
    public REST surface ([docs/API.md](docs/API.md)) to match — or record a one-line written
    reason in the task. Standing exceptions, already decided: `delete_*` never enters MCP
    (ADR-0022; the API-key surface does expose deletes), and raw file bytes / presigned URLs
    never flow through MCP (AI.md §7).

## 2. The "do the next task" protocol

When the user says **“do the next task”** / **“sıradaki işi yap”** (or similar):

1. **Locate position.** `npm run next` prints the next task — the first one in `docs/TASKS.md`
   without ⏸️ — with its epic's intro; STATE's “Next task” cell names the same one (`check:docs`
   keeps them equal). Exit 3: only tasks parked on the owner remain; exit 4: nothing is open —
   say so and stop. Don't read TASKS.md whole.
2. **Understand scope.** Read the task's checklist, acceptance criteria and tests. Read the
   relevant BLUEPRINT sections. Look at existing code — reuse existing helpers and patterns.
   Grep [docs/LESSONS.md](docs/LESSONS.md) for the area you touch (`ios-native`, `sync`, …):
   it holds the traps that already cost a round. Don't read it whole.
3. **Implement** the task fully, following the hard rules above. Small, cohesive diffs.
4. **Verify — K1, then K2.** `npm run verify:task -- <the test files you wrote or touched>`:
   lint and format of the changed files, every gate whose input changed, the named tests (API
   tests on the sandbox, Flutter tests here). Fix until green; a critical path (§3) runs its K2
   part now. The full set — `npm run verify:batch` — runs before anything is pushed: once per
   batch in a loop ([LOOP.md](LOOP.md)), right after the task when it is a lone one.
5. **Document.** Delete the finished task's block from `docs/TASKS.md` (git and CHANGELOG are its
   record). Update `docs/STATE.md` **in place**: overwrite the Snapshot cells — no "Önceki
   metin" chains, no session blocks. A trap that could silently recur → one or two lines in
   `docs/LESSONS.md` under its area; an owner decision → STATE "Sahip kararları"; an owner
   step still open → STATE "Kullanıcıdan bekleyen". Add one short `CHANGELOG.md` entry under
   `[Unreleased]` when a user will see the change (owner decision). Verification evidence (suite counts, injection proofs) goes in the commit
   message, not in the docs. `npm run check:docs` must pass.
6. **Commit** with a Conventional Commit message referencing the task id, e.g.
   `feat(api): add register endpoint (OPH-020)` — locally; the push follows a green K2.
7. **Report** briefly: what was done, how it was verified, what is next.

Never skip ahead (dependencies are encoded in epic order). A task that waits on the owner gets
⏸️ in its TASKS heading and its step under STATE “Kullanıcıdan bekleyen” (`check:docs` wants it
named there); `next` then moves on to the next unparked task — tell the user.

## 3. Verification layers, critical paths, Definition of Done

Checks are layered so a task pays for its own proof and a batch for the full set — once
([ADR-0042](docs/adr/0042-layered-verification-and-the-loop-contract.md)):

| Layer | When | Command | Then |
| --- | --- | --- | --- |
| **K1** | every task | `npm run verify:task -- <tests>` | local commit |
| **K2** | every batch, and a lone task | `npm run verify:batch` (`-- --list` shows the plan) | one push, only when green |
| **K3** | after the push | CI — never waited on | read once at the start of the next turn |
| **K4** | when the owner can | device, emulator, screenshots | [docs/DEVICE-CHECKS.md](docs/DEVICE-CHECKS.md) — never a closing condition |

The API suites run on the sandbox (`sbx`), which gets the tracked tree and nothing else; Flutter
runs here. Without a sandbox, `verify` runs the suites against `docker compose up -d mysql redis
minio`. What only CI covers is printed at the end of every `verify:batch`.

**Critical paths run their K2 part at K1 time** — a mistake there is expensive or irreversible,
and the batch's net comes too late for it. In a loop, a batch that touches one is 2 tasks, not 4.

- **Migrations** (`apps/api/migrations/`) — `verify:task` runs migrate → rollback → migrate itself.
- **Sync** (`src/routes/sync.js`, `src/db/sync.js`, `apps/app/lib/src/sync/`) — `check:sync-fields`
  runs itself; name `apps/api/test/integration/sync.test.js`, and `apps/app/test/sync/migration_test.dart`
  when the replica schema moves.
- **Auth, sessions, keys** — name `apps/api/test/integration/{auth,auth-refresh,auth-me,sessions,mfa}.test.js`.
- **Push payload privacy** and **notification platform behaviour** — `check:push-payload` and
  `check:notify-matrix` run themselves.
- **The extension seam** — name `apps/api/test/unit/{ee-seam,ee-status,ee-lock}.test.js`; with the
  extension checked out, its `verify:batch` too (core pushed first).

**Per task (K1):**

- [ ] Code follows hard rules (JS-only backend, MySQL, ESM, tests with the change).
- [ ] `npm run verify:task -- <tests>` green.
- [ ] New/changed endpoints have Ajv JSON schemas (request + response).
- [ ] **Sync push fields touched** (`SYNC_ENTITY_FIELDS` in `apps/api/src/routes/sync.js`) →
      `npm run gen:sync-fields` re-run and `apps/app/lib/src/sync/sync_fields.g.dart` committed;
      `npm run check:sync-fields` passes. The client asserts every `enqueueMutation` against
      that file; a field that does not cross the language boundary in the same change dies
      silently with every suite green (OPH-299).
- [ ] DB changes shipped as a new knex migration (with `down`).
- [ ] **Push payload touched** (`apps/api/src/lib/push/payload.js`) → `npm run check:push-payload`
      passes; a deliberate change is accepted with `node scripts/push/payload.mjs --write` and
      explained in the commit. Nothing a task says may cross a push provider (BLUEPRINT §8.3,
      ADR-0038) — including prose inside a declared key.
- [ ] **Notification platform behaviour touched** (a gateway, a token path, a channel) →
      `apps/app/lib/src/notifications/platform_matrix.dart` updated and
      `npm run check:notify-matrix -- --write` re-run, so `docs/NOTIFICATIONS.md` §3 says what
      the build does (`AwPushMessaging` reads that declaration before asking for a token).
- [ ] Docs: finished task deleted from TASKS, STATE updated in place, one CHANGELOG entry if a
      user will see it (+ LESSONS/ADR/ARCHITECTURE when relevant); `npm run check:docs` passes.
- [ ] User-facing capability added/changed → MCP tools + docs/MCP.md and docs/API.md extended,
      or a written reason recorded (rule 12).
- [ ] Local Conventional Commit with the task id; suite counts and injection proofs in its body.

**Per batch (K2):**

- [ ] `npm run verify:batch` green and complete (no `--only`/`--skip`) — then one `git push`.
- [ ] STATE's Snapshot cells current; anything to see on a device queued in DEVICE-CHECKS.md.
- [ ] CI read at the start of the next turn, not waited on; an epic or a release closes only on
      a green CI.

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
  `sync_revisions` row **in the same transaction** — use `recordSyncWrite`/`withRevision`
  from `src/db/sync.js` (OPH-050) and stamp the returned revision onto the entity row.
- No N+1 queries: batch with `whereIn`, join, or a single aggregate query.

### App (`apps/app`)

- Riverpod for state, go_router for navigation, feature-first folders under `lib/src/features/`.
- **Local-first (Epic 06):** screens never call the REST APIs directly — reads watch the
  drift replica through the feature stores (`features/*/data/*_store.dart`), writes go
  through the same stores (optimistic row + outbox enqueue in one transaction, then poke
  the engine). Widget tests that pump the app need `test/support/sync_overrides.dart`.
- Keep widgets small; extract reusable UI to `lib/src/widgets/`.
- **No hardcoded user-facing strings** (Epic 11, ADR-0009): every label goes through the i18n
  facade — `'some.key'.tr()`, with the key added to `apps/app/assets/i18n/{en,tr}.json` (English is
  the base/fallback). CI enforces this (`npm run check:i18n`); escape hatch `// i18n-ignore`.
- `dart format <the files you touched>` before committing — never the whole tree: the local SDK
  formats collections differently from CI's, and `verify:batch` checks your files with CI's
  formatter (LESSONS `ci-release`). Zero `flutter analyze` warnings.
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
Before a push they run through `verify` (§3): `npm run verify:batch -- --list` shows which parts
a change selects, and `scripts/verify/verify.mjs` is the table — a gate added to CI is a row there.

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
docs/TASKS.md              # THE backlog — open work only; a closed task is deleted
docs/STATE.md              # THE pointer + owner decisions + open owner steps; overwritten, never a log
docs/LESSONS.md            # traps by area — grep the area before touching it
docs/DEVICE-CHECKS.md      # K4 — what to look at on a device; never a closing condition
scripts/tasks/             # `npm run next` + tasks.mjs, the one reader of TASKS.md
scripts/verify/            # `npm run verify:task` / `verify:batch` — the K1/K2 check table
LOOP.md                    # the loop contract: one turn = one batch
```

## 8. When in doubt

- Prefer the BLUEPRINT; where reality diverged, ADRs win (they document deliberate deviations).
- Prefer boring, proven solutions; this is infrastructure people will self-host.
- Ask the user only when a decision is truly product-level (pricing of trade-offs unclear);
  otherwise decide, document (ADR/STATE note), and move.
