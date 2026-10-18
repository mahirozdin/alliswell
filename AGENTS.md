# AGENTS.md — AllisWell binding contract for agents (and humans)

> Sistem: blueprint-system v3 · Last updated: 2026-10-18 — blueprint v3 upgrade ([ADR-0060](docs/adr/0060-phase-workflow-and-a-light-root-contract.md))

**The product in one sentence:** a source-available, self-hosted productivity hub — tasks,
projects, notes, documents, calendar sync and reminders — with one Fastify/MySQL API and one
Flutter app for every platform.

## Reading order

1. Your slice: `npm run next` (or `-- --list`, `-- --only OPH-NNN --json`). Never read
   [docs/TASKS.md](docs/TASKS.md) or [docs/STATE.md](docs/STATE.md) whole.
2. The docs and ADRs the slice names; grep [docs/LESSONS.md](docs/LESSONS.md) for your area.
3. Touching a critical path → its rule file below, first.

Spec: [docs/BLUEPRINT.md](docs/BLUEPRINT.md) (frozen). Old references "AGENTS §1.N" mean I-0N
below; "§4" → [conventions.md](docs/development/conventions.md); "§5" →
[verification.md](docs/development/verification.md); "§6" → [.claude/rules/sync.md](.claude/rules/sync.md).

## Invariants

| # | Invariant | Enforcement | ADR |
| --- | --- | --- | --- |
| I-01 | Backend is JavaScript (Node, ESM). **No TypeScript** — no `.ts`, no `tsc`; JSDoc for hints | `check:no-ts` | [0001](docs/adr/0001-stack-and-monorepo.md) |
| I-02 | Canonical data in **MySQL 8** via **knex + mysql2**; no ORM. Redis = queues/cache/fanout only | review | [0001](docs/adr/0001-stack-and-monorepo.md) |
| I-03 | Every client platform is the one Flutter codebase `apps/app`; another UI framework needs an ADR | review | [0001](docs/adr/0001-stack-and-monorepo.md) |
| I-04 | Every feature ships with its tests (Vitest unit + integration, `flutter test`) | `verify:task`, review | [0042](docs/adr/0042-layered-verification-and-the-loop-contract.md) |
| I-05 | Every task updates the docs and keeps them small ([doc-protocol](docs/development/doc-protocol.md)) | `check:docs` | [0042](docs/adr/0042-layered-verification-and-the-loop-contract.md) |
| I-06 | An architectural decision is an ADR in `docs/adr/` + its index row | review | — |
| I-07 | No secrets in git (only `.env.example`, placeholders); OAuth tokens stored encrypted | `.gitignore`, verify's secret filter | [0006](docs/adr/0006-google-oauth-token-crypto-and-mirror-queue.md) |
| I-08 | Migrations are append-only; never edit an applied one | migration round trip | [0004](docs/adr/0004-ids-timestamps-schema-conventions.md) |
| I-09 | Conventional Commits with the task id: `feat(api): … (OPH-NNN)` | review | — |
| I-10 | Risky work in writing first: a large refactor or data migration gets a plan (task or ADR) | review | — |
| I-11 | One design system forever — "AllisWell Glass" ([DESIGN.md](docs/DESIGN.md)): tokens only, glass is chrome-only, contrast ≥ 4.5:1 / 3:1 in both themes, taps ≥ 44 px, light **and** dark checked | `check:fab`, `check:opacity`, `scripts/design/contrast.py` | [0005](docs/adr/0005-alliswell-glass-design-system.md) |
| I-12 | A user-facing capability extends MCP ([MCP.md](docs/MCP.md)) and the public REST API ([API.md](docs/API.md)) in the same epic, or the task records why. `delete_*` never enters MCP; no file bytes/presigned URLs through MCP | `check:openapi`, review | [0022](docs/adr/0022-remote-mcp-server.md) |
| I-13 | Push payloads carry IDs only, never task content | `check:push-payload` | [0038](docs/adr/0038-server-to-device-delivery.md) |
| I-14 | The extension's design never enters a public doc or commit; core work keeps CE behaviour | `check:no-ee`, review | [0041](docs/adr/0041-an-extension-that-wrote-data-must-be-present-to-serve-it.md) |

## Critical paths

A mistake here is expensive or irreversible: the task runs its K2 part at K1 time and reads
the rule file first (`next` marks such tasks ⚠).

| Area | Paths | Rule file |
| --- | --- | --- |
| Migrations | `apps/api/migrations/**` | [.claude/rules/migrations.md](.claude/rules/migrations.md) |
| Sync | `src/routes/sync.js`, `src/db/sync.js`, `apps/app/lib/src/sync/**` | [.claude/rules/sync.md](.claude/rules/sync.md) |
| Auth, sessions, keys | `routes/{auth,api-keys,oauth}.js`, `plugins/auth.js`, `lib/{tokens,crypto,totp,…}.js` | [.claude/rules/auth.md](.claude/rules/auth.md) |
| Push privacy, notification platforms | `src/lib/push/**`, `apps/app/lib/src/notifications/**` | [.claude/rules/push-notifications.md](.claude/rules/push-notifications.md) |
| Extension seam | `lib/ee*.js`, `plugins/entitlements.js`, `routes/ee.js`, `features/ee/**` | [.claude/rules/extension-seam.md](.claude/rules/extension-seam.md) |

## Commands

`npm run next` (`-- --list`, `-- --summary`) · `npm run verify:task -- <tests>` (K1) ·
`npm run verify:batch` (K2) · `npm run verify:smoke` (phase end) · `npm run check:docs`.
All of them: [commands.md](docs/development/commands.md).

API suites run on the sandbox (`sbx`) or against `docker compose up -d mysql redis minio radicale`;
Flutter runs here. CI is GitHub-hosted on purpose (public repo, ADR-0060) and never waited on
inside a phase; the merge gate is a local green K2 + smoke. Mobile/desktop behaviour is checked
on a device here before the merge, or `NOT RUN` + a [DEVICE-CHECKS](docs/DEVICE-CHECKS.md) row.

## Execution

Session start: `/isler`; phases: `/faz E35 …` — the contract is
[workflow.md](docs/development/workflow.md); layers: [verification.md](docs/development/verification.md).

## Definition of Done

- **Task:** test written first and green — `npm run verify:task -- <tests>` (+ the area's gate
  when critical) · docs per [doc-protocol](docs/development/doc-protocol.md): task deleted from
  TASKS, STATE cells overwritten, CHANGELOG line if a user sees it · I-12 honoured or reasoned ·
  local commit `type(scope): … (OPH-NNN)`, suite counts and injection proofs in the body.
- **Phase:** `npm run verify:batch` complete and green + `npm run verify:smoke` · review has no
  open blocker/major · STATE Snapshot current, device checks queued · then the git flow.

## Source priority

The user's explicit instruction > SECURITY.md > ADRs > STATE "Sahip kararları" > this file >
docs/ > BLUEPRINT. In a conflict, don't choose silently: an ADR, or a task in TASKS.md.

## Never (what no gate catches)

- A ticked box or deleted task without its check having run; a skipped check not written as
  `NOT RUN` + reason.
- Skipping a test, lowering a threshold, deleting an invariant's test to get green.
- Editing BLUEPRINT.md (a deviation is an ADR) or an accepted ADR's decision text.
- The owner's work: versions, tags, releases, deploys, `gh workflow run`, writing to
  production or an external account, store/console forms → STATE "Kullanıcıdan bekleyen".
- Re-litigating STATE "Sahip kararları"; asking the user what is not a product decision —
  decide, document (ADR / STATE), move.
- Real user data in a doc or screenshot.
